#!/usr/bin/env Rscript

# Run the frozen M0/M1 engine preflight using only 2021-22 and 2022-23
# outcomes. Later-season canonical partitions are verified but never loaded.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(mgcv)
  library(purrr)
  library(readr)
  library(tidyr)
})

options(stringsAsFactors = FALSE)
options(contrasts = c("contr.treatment", "contr.poly"))

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) {
  sub("^--file=", "", script_arg)
} else {
  "R/context_edition_m0_m1_training_preflight.R"
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
verify_recovery_only <- "--verify-recovery" %in% args

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)

canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
private_parent <- file.path(repo_root, "data", "cache", "context_edition_m0_m1_preflight")
private_final <- file.path(private_parent, "context_m0_m1_preflight_v0.1.0")
private_lock <- file.path(private_parent, ".preflight-lock-v0.1.0")
tracked_parent <- file.path(repo_root, "data", "processed")
tracked_final <- file.path(tracked_parent, "context_edition_validation_data_preflight_v0_1")
config_path <- file.path(repo_root, "config", "context_edition_training_preflight_v0_1.csv")
model_spec_path <- file.path(repo_root, "config", "context_edition_m0_m1_model_spec_v0_1.csv")
feature_path <- file.path(repo_root, "config", "context_edition_feature_allowlist_v0_1.csv")
taxonomy_path <- file.path(repo_root, "config", "context_edition_taxonomy_v0_1.csv")
source_drift_path <- file.path(
  repo_root, "data", "processed", "context_edition_canonical_v0_1_2_five_season",
  "source_drift.csv"
)

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(result) != 1L) stop("could not hash ", path, call. = FALSE)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

write_csv_stable <- function(data, path) {
  readr::write_csv(data, path, na = "", quote = "needed")
}

current_rss_bytes <- function() {
  output <- suppressWarnings(system2(
    "ps", c("-o", "rss=", "-p", as.character(Sys.getpid())), stdout = TRUE
  ))
  value <- suppressWarnings(as.numeric(trimws(output[[1]])))
  if (length(value) != 1L || !is.finite(value)) return(NA_real_)
  value * 1024
}

available_disk_bytes <- function(path) {
  output <- system2("df", c("-k", path), stdout = TRUE)
  fields <- strsplit(trimws(output[[length(output)]]), "[[:space:]]+")[[1]]
  value <- suppressWarnings(as.numeric(fields[[4]]))
  if (!is.finite(value)) stop("could not measure available disk", call. = FALSE)
  value * 1024
}

dir.create(private_parent, recursive = TRUE, showWarnings = FALSE)

if (verify_recovery_only) {
  manifest_path <- file.path(private_final, "completion_manifest.csv")
  if (!file.exists(manifest_path)) stop("no completed preflight checkpoint", call. = FALSE)
  manifest <- read_csv(manifest_path, show_col_types = FALSE)
  context_preflight_verify_manifest(manifest, private_final, sha256_file)
  message("Verified completed preflight checkpoint; no fit was run")
  quit(save = "no", status = 0L)
}

if (dir.exists(private_final) || dir.exists(tracked_final)) {
  stop("a completed preflight output already exists; use --verify-recovery", call. = FALSE)
}
if (dir.exists(private_lock)) {
  stop("a preflight lock already exists; verify its process before recovery", call. = FALSE)
}
if (!dir.create(private_lock, showWarnings = FALSE)) {
  stop("could not acquire preflight lock", call. = FALSE)
}

attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
private_stage <- file.path(private_parent, paste0(".preflight-", attempt_id, ".partial"))
tracked_stage <- file.path(tracked_parent, paste0(".context-preflight-", attempt_id))
dir.create(private_stage, recursive = TRUE, showWarnings = FALSE)
dir.create(tracked_stage, recursive = TRUE, showWarnings = FALSE)
log_path <- file.path(private_stage, "preflight.log")
success <- FALSE

options(error = function() {
  if (dir.exists(private_stage)) {
    writeLines(
      c(
        paste0("attempt_id=", attempt_id),
        paste0("ended_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
        "status=failed_or_interrupted",
        "validation_outcomes_accessed=false"
      ),
      file.path(private_stage, "failure_or_interruption.txt")
    )
  }
})

log_line <- function(...) {
  line <- paste0(format(Sys.time(), tz = "UTC", usetz = TRUE), " ", paste0(..., collapse = ""))
  cat(line, "\n", file = log_path, append = TRUE)
  message(line)
}

writeLines(
  c(
    paste0("pid=", Sys.getpid()),
    paste0("attempt_id=", attempt_id),
    paste0("started_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    "stage=setup",
    "training_seasons=2021-22;2022-23",
    "validation_outcomes_accessed=false"
  ),
  file.path(private_lock, "metadata.txt")
)

on.exit({
  if (!success) {
    writeLines(
      c(
        paste0("attempt_id=", attempt_id),
        paste0("ended_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
        "status=failed_or_interrupted",
        "validation_outcomes_accessed=false"
      ),
      file.path(private_stage, "failure_or_interruption.txt")
    )
  }
}, add = TRUE)

started_wall <- Sys.time()
started_cpu <- proc.time()
memory_samples <- current_rss_bytes()
disk_bytes_before <- available_disk_bytes(repo_root)
if (disk_bytes_before < 5 * 1024^3) stop("less than 5 GiB free disk", call. = FALSE)
log_line("Preflight setup started")

config <- read_csv(config_path, show_col_types = FALSE)
config_values <- setNames(config$value, config$key)
if (!identical(
  strsplit(config_values[["training_seasons"]], ";", fixed = TRUE)[[1]],
  CONTEXT_PREFLIGHT_TRAINING_SEASONS
)) stop("training seasons differ from frozen configuration", call. = FALSE)
if (!identical(
  strsplit(config_values[["validation_seasons"]], ";", fixed = TRUE)[[1]],
  CONTEXT_PREFLIGHT_VALIDATION_SEASONS
)) stop("validation seasons differ from frozen configuration", call. = FALSE)
if (any(config_values[c(
  "validation_outcomes_for_fit", "validation_outcomes_for_prediction",
  "validation_outcomes_for_metrics", "public_shot_rows"
)] != "FALSE")) stop("a frozen seal flag is not FALSE", call. = FALSE)

model_spec <- read_csv(model_spec_path, show_col_types = FALSE)
feature_spec <- read_csv(feature_path, show_col_types = FALSE)
taxonomy <- read_csv(taxonomy_path, show_col_types = FALSE)
source_drift <- read_csv(source_drift_path, show_col_types = FALSE)
if (nrow(source_drift) != 5L || any(source_drift$status != "pass") ||
    any(!source_drift$all_raw_labels_registered)) {
  stop("canonical source-drift checks are not fully passing", call. = FALSE)
}
context_validate_feature_matrix(feature_spec)
formulas <- context_model_formulas()
factor_levels <- context_factor_levels()
if (!identical(as.character(packageVersion("mgcv")), "1.9.4")) {
  stop("installed mgcv version differs from frozen 1.9-4", call. = FALSE)
}

canonical_manifest_path <- file.path(canonical_root, "completion_manifest.csv")
if (!file.exists(canonical_manifest_path)) {
  stop("five-season canonical checkpoint is missing", call. = FALSE)
}
canonical_manifest <- read_csv(canonical_manifest_path, show_col_types = FALSE)
context_preflight_verify_manifest(canonical_manifest, canonical_root, sha256_file)
if (!all(canonical_manifest$schema_version == "context_field_goal_v0.1.2") ||
    !all(canonical_manifest$taxonomy_version == "context_taxonomy_v0.1.0") ||
    !all(canonical_manifest$join_version == "shotchart_espn_exact_clock_player_v0.1.1") ||
    !all(canonical_manifest$training_rows_identical_to_accepted) ||
    any(canonical_manifest$validation_outcomes_analytically_accessed)) {
  stop("canonical checkpoint does not satisfy the frozen contract", call. = FALSE)
}

training_paths <- file.path(
  canonical_root,
  paste0("season=", CONTEXT_PREFLIGHT_TRAINING_SEASONS),
  "canonical_shots.parquet"
)
if (!all(file.exists(training_paths))) stop("training partitions are missing", call. = FALSE)

required_training_fields <- c(
  "season", "player_id", "point_value", "finish_family",
  "creation_family", "field_goal_made"
)
training <- map_dfr(training_paths, function(path) {
  read_parquet(path, col_select = all_of(required_training_fields), as_data_frame = TRUE)
})
if (!identical(sort(unique(training$season)), CONTEXT_PREFLIGHT_TRAINING_SEASONS)) {
  stop("a non-training season entered the preflight", call. = FALSE)
}
if (nrow(training) != 433942L) stop("training shot count changed", call. = FALSE)
if (any(!training$field_goal_made %in% c(0L, 1L)) || anyNA(training$field_goal_made)) {
  stop("training outcomes are invalid", call. = FALSE)
}

player_levels <- sort(unique(as.character(training$player_id)))
training <- training |>
  mutate(
    player_id_factor = factor(as.character(player_id), levels = player_levels),
    point_value_factor = factor(
      if_else(point_value == 2L, "two", "three"),
      levels = factor_levels$point_value_factor
    ),
    finish_family = factor(finish_family, levels = factor_levels$finish_family),
    creation_family = factor(creation_family, levels = factor_levels$creation_family)
  ) |>
  select(-player_id)
if (anyNA(training)) stop("training model fields contain missing values", call. = FALSE)
if (n_distinct(training$player_id_factor) != 700L) stop("training player count changed", call. = FALSE)

m0_counts <- context_preflight_group_counts(training, "M0")
m1_counts <- context_preflight_group_counts(training, "M1")
if (sum(m0_counts$attempts) != nrow(training) || sum(m1_counts$attempts) != nrow(training) ||
    sum(m0_counts$makes) != sum(training$field_goal_made) ||
    sum(m1_counts$makes) != sum(training$field_goal_made)) {
  stop("grouped counts do not reproduce training totals", call. = FALSE)
}
if (any(m0_counts$makes + m0_counts$misses != m0_counts$attempts) ||
    any(m1_counts$makes + m1_counts$misses != m1_counts$attempts)) {
  stop("grouped binomial rows are inconsistent", call. = FALSE)
}

setup_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs"))
memory_samples <- c(memory_samples, current_rss_bytes())

fit_one <- function(model_id, counts) {
  log_line("Fitting ", model_id)
  writeLines(
    c(
      paste0("pid=", Sys.getpid()),
      paste0("attempt_id=", attempt_id),
      paste0("updated_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      paste0("stage=fitting_", tolower(model_id)),
      "training_seasons=2021-22;2022-23",
      "validation_outcomes_accessed=false"
    ),
    file.path(private_lock, "metadata.txt")
  )
  warnings_seen <- character()
  fit_started <- Sys.time()
  cpu_started <- proc.time()
  setTimeLimit(elapsed = as.numeric(config_values[["fit_timeout_seconds"]]), transient = TRUE)
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
  fit <- withCallingHandlers(
    mgcv::gam(
      formula = formulas[[model_id]],
      family = stats::binomial(link = "logit"),
      data = counts,
      method = "REML",
      optimizer = c("outer", "newton"),
      control = mgcv::gam.control(),
      select = FALSE,
      gamma = 1,
      na.action = stats::na.fail,
      drop.unused.levels = FALSE,
      discrete = FALSE
    ),
    warning = function(warning) {
      warnings_seen <<- c(warnings_seen, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  fit_seconds <- as.numeric(difftime(Sys.time(), fit_started, units = "secs"))
  cpu_used <- proc.time() - cpu_started
  list(
    fit = fit,
    warnings = unique(warnings_seen),
    fit_seconds = fit_seconds,
    cpu_user_seconds = unname(cpu_used[["user.self"]]),
    cpu_system_seconds = unname(cpu_used[["sys.self"]])
  )
}

m0_result <- fit_one("M0", m0_counts)
memory_samples <- c(memory_samples, current_rss_bytes())
m1_result <- fit_one("M1", m1_counts)
memory_samples <- c(memory_samples, current_rss_bytes())

validate_fit <- function(model_id, result, counts) {
  model_id_value <- model_id
  fit <- result$fit
  prediction_started <- Sys.time()
  probabilities <- as.numeric(predict(fit, newdata = counts, type = "response"))
  probabilities_repeat <- as.numeric(predict(fit, newdata = counts, type = "response"))
  prediction_seconds <- as.numeric(difftime(Sys.time(), prediction_started, units = "secs"))
  expected_points <- context_expected_points(
    probabilities,
    ifelse(counts$point_value_factor == "two", 2L, 3L)
  )
  representative <- counts[1L, , drop = FALSE]
  unseen <- representative
  unseen$player_id_factor <- factor(
    "__UNSEEN_PLAYER__", levels = c(levels(counts$player_id_factor), "__UNSEEN_PLAYER__")
  )
  unseen_probability <- suppressWarnings(context_preflight_fixed_prediction(fit, unseen))
  fixed_known_probability <- context_preflight_fixed_prediction(fit, representative)

  taxonomy_probabilities <- numeric()
  if (model_id == "M1") {
    taxonomy_newdata <- tidyr::crossing(
      point_value_factor = factor(factor_levels$point_value_factor, levels = factor_levels$point_value_factor),
      finish_family = factor(factor_levels$finish_family, levels = factor_levels$finish_family),
      creation_family = factor(factor_levels$creation_family, levels = factor_levels$creation_family)
    ) |>
      mutate(
        player_id_factor = factor(levels(counts$player_id_factor)[[1]], levels = levels(counts$player_id_factor)),
        .before = 1L
      )
    taxonomy_probabilities <- as.numeric(predict(fit, newdata = taxonomy_newdata, type = "response"))
  }

  gradient <- if (!is.null(fit$outer.info$grad)) max(abs(fit$outer.info$grad)) else NA_real_
  convergence_text <- if (!is.null(fit$outer.info$conv)) fit$outer.info$conv else "unavailable"
  random_edf <- sum(fit$edf[grepl("player_id_factor", names(fit$edf), fixed = TRUE)])
  checks <- tibble(
    model_id = model_id_value,
    check = c(
      "fit_converged", "finite_coefficients", "finite_covariance",
      "positive_finite_smoothing", "nonboundary_player_effect",
      "finite_interior_probabilities", "deterministic_prediction",
      "expected_points_conversion", "unseen_player_zero_effect",
      "all_registered_taxonomy_levels_predict", "formula_identity",
      "no_forbidden_feature"
    ),
    status = c(
      isTRUE(fit$converged),
      all(is.finite(coef(fit))),
      all(is.finite(fit$Vp)),
      length(fit$sp) == 1L && all(is.finite(fit$sp)) && all(fit$sp > 0),
      is.finite(random_edf) && random_edf > 0,
      all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1),
      isTRUE(all.equal(probabilities, probabilities_repeat, tolerance = 1e-13)),
      isTRUE(all.equal(
        expected_points,
        probabilities * ifelse(counts$point_value_factor == "two", 2L, 3L),
        tolerance = 1e-15
      )),
      length(unseen_probability) == 1L && is.finite(unseen_probability) &&
        isTRUE(all.equal(unseen_probability, fixed_known_probability, tolerance = 1e-12)),
      model_id_value == "M0" || (
        length(taxonomy_probabilities) == 56L && all(is.finite(taxonomy_probabilities)) &&
          all(taxonomy_probabilities > 0 & taxonomy_probabilities < 1)
      ),
      identical(
        gsub("[[:space:]]+", "", paste(deparse(formula(fit)), collapse = "")),
        gsub("[[:space:]]+", "", paste(deparse(formulas[[model_id_value]]), collapse = ""))
      ),
      setequal(
        attr(terms(fit), "term.labels"),
        if (model_id_value == "M0") {
          c("point_value_factor", "player_id_factor")
        } else {
          c(
            "point_value_factor", "finish_family", "creation_family",
            "player_id_factor"
          )
        }
      )
    ) |>
      if_else("pass", "fail")
  )
  if (any(checks$status == "fail")) {
    print(checks |> filter(status == "fail"))
    stop(model_id_value, " failed a frozen sanity check", call. = FALSE)
  }
  list(
    checks = checks,
    diagnostics = tibble(
      model_id = model_id_value,
      training_shots = sum(counts$attempts),
      grouped_rows = nrow(counts),
      players = n_distinct(counts$player_id_factor),
      coefficients = length(coef(fit)),
      smooth_terms = length(fit$smooth),
      random_effect_basis_dimension = fit$smooth[[1]]$bs.dim,
      smoothing_parameter = unname(fit$sp[[1]]),
      effective_degrees_freedom = sum(fit$edf),
      random_effect_effective_degrees_freedom = random_edf,
      converged = isTRUE(fit$converged),
      convergence_message = convergence_text,
      maximum_absolute_gradient = gradient,
      setup_seconds = setup_seconds,
      fit_seconds = result$fit_seconds,
      prediction_check_seconds = prediction_seconds,
      cpu_user_seconds = result$cpu_user_seconds,
      cpu_system_seconds = result$cpu_system_seconds,
      sampled_rss_bytes_after_fit = current_rss_bytes(),
      fit_object_bytes = as.numeric(object.size(fit)),
      warnings = paste(result$warnings, collapse = " | "),
      warning_count = length(result$warnings)
    ),
    probabilities = probabilities
  )
}

m0_verified <- validate_fit("M0", m0_result, m0_counts)
memory_samples <- c(memory_samples, current_rss_bytes())
m1_verified <- validate_fit("M1", m1_result, m1_counts)
memory_samples <- c(memory_samples, current_rss_bytes())

grouping_checks <- bind_rows(
  tibble(
    model_id = "M0", group_keys = paste(context_preflight_group_keys("M0"), collapse = ";"),
    training_shots = nrow(training), grouped_rows = nrow(m0_counts),
    grouped_attempts = sum(m0_counts$attempts), grouped_makes = sum(m0_counts$makes),
    grouped_misses = sum(m0_counts$misses), training_total_reproduced = TRUE,
    validation_rows_in_groups = 0L
  ),
  tibble(
    model_id = "M1", group_keys = paste(context_preflight_group_keys("M1"), collapse = ";"),
    training_shots = nrow(training), grouped_rows = nrow(m1_counts),
    grouped_attempts = sum(m1_counts$attempts), grouped_makes = sum(m1_counts$makes),
    grouped_misses = sum(m1_counts$misses), training_total_reproduced = TRUE,
    validation_rows_in_groups = 0L
  )
)

fit_paths <- c(
  M0 = file.path(private_stage, "m0_fit.rds"),
  M1 = file.path(private_stage, "m1_fit.rds")
)
saveRDS(m0_result$fit, fit_paths[["M0"]], compress = "xz")
saveRDS(m1_result$fit, fit_paths[["M1"]], compress = "xz")
serialized_bytes <- file.info(fit_paths)$size
serialized_bytes <- setNames(as.numeric(serialized_bytes), names(fit_paths))
fit_diagnostics <- bind_rows(m0_verified$diagnostics, m1_verified$diagnostics) |>
  mutate(serialized_fit_bytes = unname(serialized_bytes[model_id]))
sanity_checks <- bind_rows(m0_verified$checks, m1_verified$checks)

seal_audit <- tibble(
  season = c(CONTEXT_PREFLIGHT_TRAINING_SEASONS, CONTEXT_PREFLIGHT_VALIDATION_SEASONS),
  mechanical_canonicalization_access = TRUE,
  outcome_access_for_preflight_fit = season %in% CONTEXT_PREFLIGHT_TRAINING_SEASONS,
  outcome_access_for_prediction = season %in% CONTEXT_PREFLIGHT_TRAINING_SEASONS,
  outcome_access_for_metrics = FALSE,
  performance_result_created = FALSE
)

all_checks_pass <- all(sanity_checks$status == "pass") &&
  all(grouping_checks$training_total_reproduced) &&
  all(grouping_checks$validation_rows_in_groups == 0L) &&
  !any(seal_audit$outcome_access_for_preflight_fit[seal_audit$season %in% CONTEXT_PREFLIGHT_VALIDATION_SEASONS])

total_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs"))
cpu_total <- proc.time() - started_cpu
summary_table <- tibble(
  protocol_version = CONTEXT_PROTOCOL_VERSION,
  training_seasons = paste(CONTEXT_PREFLIGHT_TRAINING_SEASONS, collapse = ";"),
  training_shots = nrow(training),
  training_players = n_distinct(training$player_id_factor),
  models_fit = 2L,
  validation_models_fit = 0L,
  validation_performance_metrics = 0L,
  total_wall_seconds = total_seconds,
  total_cpu_user_seconds = unname(cpu_total[["user.self"]]),
  total_cpu_system_seconds = unname(cpu_total[["sys.self"]]),
  sampled_peak_rss_bytes = max(memory_samples, na.rm = TRUE),
  available_disk_bytes_before = disk_bytes_before,
  available_disk_bytes_after = available_disk_bytes(repo_root),
  public_shot_rows = 0L,
  all_checks_passed = all_checks_pass
)

package_versions <- tibble(
  package = c("R", "arrow", "dplyr", "mgcv", "Matrix", "purrr", "readr", "tidyr"),
  version = c(
    paste(R.version$major, R.version$minor, sep = "."),
    map_chr(c("arrow", "dplyr", "mgcv", "Matrix", "purrr", "readr", "tidyr"),
            ~ as.character(packageVersion(.x)))
  )
)

readiness <- tibble(
  decision = if_else(all_checks_pass, "go", "stop"),
  next_comparison = "train 2021-22 and 2022-23; validate 2023-24",
  validation_run_during_preflight = FALSE,
  basis = if_else(
    all_checks_pass,
    "all five canonical seasons passed; accepted training rows reproduced; both frozen fits and recovery checks passed; validation outcomes remained analytically sealed",
    "one or more required preflight checks failed"
  )
)

tracked_tables <- list(
  grouping_verification.csv = grouping_checks,
  fit_diagnostics.csv = fit_diagnostics,
  package_versions.csv = package_versions,
  preflight_summary.csv = summary_table,
  readiness.csv = readiness,
  sanity_checks.csv = sanity_checks,
  validation_seal_audit.csv = seal_audit
)
walk2(tracked_tables, names(tracked_tables), ~ write_csv_stable(.x, file.path(tracked_stage, .y)))

private_manifest <- tibble(
  artifact = basename(fit_paths),
  sha256 = map_chr(fit_paths, sha256_file),
  atomic_complete = TRUE,
  checks_passed = all_checks_pass,
  protocol_version = CONTEXT_PROTOCOL_VERSION,
  canonical_manifest_sha256 = sha256_file(canonical_manifest_path),
  config_sha256 = sha256_file(config_path),
  model_spec_sha256 = sha256_file(model_spec_path),
  validation_outcomes_accessed = FALSE
)
write_csv_stable(private_manifest, file.path(private_stage, "completion_manifest.csv"))

tracked_files <- sort(names(tracked_tables))
tracked_manifest <- tibble(
  file = tracked_files,
  bytes = file.info(file.path(tracked_stage, tracked_files))$size,
  sha256 = map_chr(file.path(tracked_stage, tracked_files), sha256_file),
  contains_shot_level_rows = FALSE,
  declarative_or_aggregate = TRUE
)
write_csv_stable(tracked_manifest, file.path(tracked_stage, "artifact_manifest.csv"))

context_preflight_atomic_publish(private_stage, private_final)
context_preflight_atomic_publish(tracked_stage, tracked_final)
unlink(private_lock, recursive = TRUE)
if (dir.exists(private_lock)) stop("completed preflight lock did not clear", call. = FALSE)
success <- TRUE
message("Training-only M0/M1 preflight completed and published atomically")
