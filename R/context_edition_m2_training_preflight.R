#!/usr/bin/env Rscript

# Atomic first-window training-only preflight for the frozen D1 and M2 models.
# Modes: audit (no data/outcomes), verify-partial (check preserved D1 without
# mutation), run (fit exactly once), resume (reuse D1 and fit M2 exactly once),
# verify (no refit).

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
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_training_preflight.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
mode <- commandArgs(trailingOnly = TRUE)
if (length(mode) != 1L || !mode %in% c("audit", "verify-partial", "run", "resume", "verify")) {
  stop("usage: Rscript R/context_edition_m2_training_preflight.R audit|verify-partial|run|resume|verify", call. = FALSE)
}

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)

PREFLIGHT_VERSION <- "context_m2_training_preflight_v0.1.0"
PREFIT_IMPLEMENTATION_COMMIT <- "18cbe2ffcd85641214419d88a5520f0b55e561da"
RECOVERY_ATTEMPT_ID <- "20260921T003642Z"
RECOVERY_INPUT_HASH <- "07c541d645e8336a64f2d2266c52eb9077707cb6dd991d08597731d2429139a1"
RECOVERY_D1_FIT_SHA256 <- "e7632292dd9a8c0d2b223430862efa9bf0216d7d16d171e37d9f2752c24b3fb9"
RECOVERY_D1_COUNTS_SHA256 <- "3fa19b60755dae9b82dc8a26dac16c336974be0e447c2d82c206a93166eb6782"
RECOVERY_M2_COUNTS_SHA256 <- "fce87be19053655ff65a2fa77e477dbece15f93edd9acd1c26f101fc11cb03ae"
TRAINING_SEASONS <- c("2021-22", "2022-23")
PROHIBITED_OUTCOME_SEASONS <- c("2023-24", "2024-25", "2025-26", "2026-27")
EXPECTED <- c(
  games = 2460L, shots = 433942L, players = 700L,
  makes = 203190L, misses = 230752L,
  D1_rows = 18396L, M2_rows = 57190L,
  distance_min = 0L, distance_max = 88L
)
EXPECTED_PACKAGE_VERSIONS <- c(
  R = "4.6.0", arrow = "25.0.0", dplyr = "1.2.1", mgcv = "1.9.4",
  Matrix = "1.7.5", purrr = "1.2.2", readr = "2.2.0", tidyr = "1.3.2"
)

canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
private_parent <- file.path(repo_root, "data", "cache", "context_edition_m2_training_preflight")
private_final <- file.path(private_parent, "context_m2_training_preflight_v0.1.0")
private_lock <- file.path(private_parent, ".preflight-lock-v0.1.0")
tracked_parent <- file.path(repo_root, "data", "processed")
tracked_final <- file.path(tracked_parent, "context_edition_m2_training_preflight_v0_1")
config_path <- file.path(repo_root, "config", "context_edition_m2_training_preflight_v0_1.csv")
model_spec_path <- file.path(repo_root, "config", "context_edition_m2_model_spec_v0_1.csv")
feature_path <- file.path(repo_root, "config", "context_edition_m2_feature_allowlist_v0_1.csv")
smooth_path <- file.path(repo_root, "config", "context_edition_m2_smooth_v0_1.csv")
taxonomy_path <- file.path(repo_root, "config", "context_edition_taxonomy_v0_1.csv")

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) stop("could not hash ", path, call. = FALSE)
  sub("[[:space:]].*$", "", output)
}

hash_values <- function(values) {
  temporary <- tempfile("context-m2-hash-")
  on.exit(unlink(temporary), add = TRUE)
  writeLines(enc2utf8(as.character(values)), temporary, useBytes = TRUE)
  sha256_file(temporary)
}

write_csv_stable <- function(data, path) readr::write_csv(data, path, na = "", quote = "needed")

write_lines_atomic <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = paste0(".", basename(path), "-"), tmpdir = dirname(path))
  writeLines(lines, temporary, useBytes = TRUE)
  if (!file.rename(temporary, path)) stop("atomic text publication failed: ", path, call. = FALSE)
}

available_disk_bytes <- function(path) {
  output <- system2("df", c("-k", path), stdout = TRUE)
  fields <- strsplit(trimws(output[[length(output)]]), "[[:space:]]+")[[1]]
  value <- suppressWarnings(as.numeric(fields[[4]]))
  if (!is.finite(value)) stop("could not measure available disk", call. = FALSE)
  value * 1024
}

git_value <- function(arguments) {
  output <- system2("git", c("-C", repo_root, arguments), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(output, "status"))) stop("git command failed", call. = FALSE)
  if (length(output) == 0L) return(character())
  trimws(output)
}

read_configuration <- function() {
  config <- readr::read_csv(config_path, show_col_types = FALSE)
  values <- setNames(config$value, config$key)
  required <- c(
    "preflight_version", "protocol_version", "approved_design_commit",
    "pre_fit_implementation_commit",
    "training_seasons", "prohibited_outcome_seasons", "engine_version",
    "method", "optimizer", "discrete", "select", "gamma", "k_initial",
    "k_check_seed", "k_check_subsample", "k_check_replicates",
    "expected_games", "expected_shots", "expected_players", "expected_makes",
    "expected_misses", "expected_d1_grouped_rows", "expected_m2_grouped_rows",
    "expected_distance_min", "expected_distance_max", "validation_outcomes_accessed",
    "validation_predictions_created", "performance_metrics_created",
    "prospective_2026_27_accessed", "public_shot_rows"
  )
  if (!all(required %in% names(values))) stop("preflight config is incomplete", call. = FALSE)
  if (!identical(values[["preflight_version"]], PREFLIGHT_VERSION) ||
      !identical(values[["protocol_version"]], CONTEXT_M2_PROTOCOL_VERSION) ||
      !identical(values[["pre_fit_implementation_commit"]], PREFIT_IMPLEMENTATION_COMMIT) ||
      !identical(strsplit(values[["training_seasons"]], ";", fixed = TRUE)[[1]], TRAINING_SEASONS) ||
      !identical(strsplit(values[["prohibited_outcome_seasons"]], ";", fixed = TRUE)[[1]], PROHIBITED_OUTCOME_SEASONS)) {
    stop("preflight scope differs from the frozen configuration", call. = FALSE)
  }
  false_keys <- c(
    "validation_outcomes_accessed", "validation_predictions_created",
    "performance_metrics_created", "prospective_2026_27_accessed", "public_shot_rows"
  )
  if (any(values[false_keys] != "FALSE")) stop("a protected-scope flag is not FALSE", call. = FALSE)
  values
}

static_audit <- function() {
  config_values <- read_configuration()
  installed_versions <- c(
    R = paste(R.version$major, R.version$minor, sep = "."),
    vapply(names(EXPECTED_PACKAGE_VERSIONS)[-1L], function(x) as.character(packageVersion(x)), character(1))
  )
  if (!identical(installed_versions, EXPECTED_PACKAGE_VERSIONS)) stop("frozen package versions changed", call. = FALSE)
  formulas <- context_m2_formulas()
  model_spec <- readr::read_csv(model_spec_path, show_col_types = FALSE)
  feature_spec <- readr::read_csv(feature_path, show_col_types = FALSE)
  smooth_spec <- readr::read_csv(smooth_path, show_col_types = FALSE)
  context_m2_validate_feature_allowlist(feature_spec)
  normalize <- function(x) gsub("[[:space:]]+", "", x)
  for (model_id in c("D1", "M2")) {
    configured <- model_spec$formula[model_spec$model_id == model_id]
    actual <- paste(deparse(formulas[[model_id]]), collapse = "")
    if (length(configured) != 1L || normalize(configured) != normalize(actual)) {
      stop(model_id, " formula differs from preregistration", call. = FALSE)
    }
  }
  if (nrow(smooth_spec) != 1L || smooth_spec$basis != "cr" || smooth_spec$k_initial != 10L ||
      smooth_spec$method != "REML" || smooth_spec$select || smooth_spec$shrinkage != "none") {
    stop("smooth configuration differs from preregistration", call. = FALSE)
  }
  code <- paste(readLines(script_path, warn = FALSE), collapse = "\n")
  forbidden_partition_literals <- paste0("season=", PROHIBITED_OUTCOME_SEASONS)
  if (any(vapply(forbidden_partition_literals, grepl, logical(1), x = code, fixed = TRUE))) {
    stop("runner contains a prohibited outcome partition path", call. = FALSE)
  }
  list(
    config = config_values,
    formulas = formulas,
    model_spec = model_spec,
    feature_spec = feature_spec,
    smooth_spec = smooth_spec,
    package_versions = installed_versions,
    configuration_sha256 = sha256_file(config_path),
    preregistration_inputs_sha256 = hash_values(c(
      sha256_file(model_spec_path), sha256_file(feature_path), sha256_file(smooth_path),
      sha256_file(file.path(repo_root, "R", "context_edition_m2_protocol.R"))
    ))
  )
}

group_keys <- function(model_id) {
  switch(
    model_id,
    D1 = c("player_id_factor", "point_value_factor", "shot_distance_feet"),
    M2 = c("player_id_factor", "point_value_factor", "finish_family", "creation_family", "shot_distance_feet"),
    stop("unsupported model_id", call. = FALSE)
  )
}

group_counts <- function(training, model_id) {
  keys <- group_keys(model_id)
  training |>
    group_by(across(all_of(keys)), .drop = TRUE) |>
    summarise(
      makes = sum(field_goal_made),
      attempts = n(),
      misses = attempts - makes,
      .groups = "drop"
    ) |>
    arrange(across(all_of(keys)))
}

write_stage <- function(stage_path, attempt_id, stage, input_hash) {
  write_lines_atomic(
    c(
      paste0("pid=", Sys.getpid()),
      paste0("attempt_id=", attempt_id),
      paste0("updated_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      paste0("stage=", stage),
      paste0("input_hash=", input_hash),
      "training_seasons=2021-22;2022-23",
      "validation_outcomes_accessed=false",
      "prospective_2026_27_accessed=false"
    ),
    stage_path
  )
}

process_snapshot <- function(pids, model_id, started_at) {
  pids <- unique(as.integer(pids[is.finite(pids)]))
  output <- system2(
    "ps", c("-o", "pid=,ppid=,rss=,%cpu=,time=", "-p", paste(pids, collapse = ",")),
    stdout = TRUE, stderr = FALSE
  )
  if (length(output) == 0L) return(tibble())
  rows <- strsplit(trimws(output), "[[:space:]]+")
  bind_rows(lapply(rows, function(fields) {
    if (length(fields) < 5L) return(NULL)
    tibble(
      sampled_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      model_id = model_id,
      wall_seconds = as.numeric(difftime(Sys.time(), started_at, units = "secs")),
      pid = as.integer(fields[[1]]),
      ppid = as.integer(fields[[2]]),
      rss_bytes = as.numeric(fields[[3]]) * 1024,
      cpu_percent = as.numeric(fields[[4]]),
      cpu_time_text = fields[[5]]
    )
  }))
}

fit_worker <- function(model_id, counts, formula, output_path) {
  warnings_seen <- character()
  messages_seen <- character()
  started_wall <- Sys.time()
  started_cpu <- proc.time()
  fit <- withCallingHandlers(
    mgcv::gam(
      formula = formula,
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
    },
    message = function(message) {
      messages_seen <<- c(messages_seen, conditionMessage(message))
      invokeRestart("muffleMessage")
    }
  )
  fit_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs"))
  cpu <- proc.time() - started_cpu
  serialized_started <- Sys.time()
  saveRDS(fit, output_path, compress = "xz")
  serialization_seconds <- as.numeric(difftime(Sys.time(), serialized_started, units = "secs"))
  list(
    model_id = model_id,
    fit_seconds = fit_seconds,
    serialization_seconds = serialization_seconds,
    fit_and_serialization_wall_seconds = fit_seconds + serialization_seconds,
    cpu_user_seconds = unname(cpu[["user.self"]]),
    cpu_system_seconds = unname(cpu[["sys.self"]]),
    fit_object_bytes = as.numeric(object.size(fit)),
    sampled_cpu_seconds = NA_real_,
    reused_from_partial = FALSE,
    warning_count = length(unique(warnings_seen)),
    warning_metadata_status = "complete",
    warnings = unique(warnings_seen),
    message_count = length(unique(messages_seen)),
    message_metadata_status = "complete",
    messages = unique(messages_seen)
  )
}

run_fit_monitored <- function(model_id, counts, formula, output_path, resource_path, stage_path, attempt_id, input_hash) {
  write_stage(stage_path, attempt_id, paste0("fitting_", tolower(model_id)), input_hash)
  started_at <- Sys.time()
  job <- parallel::mcparallel(
    fit_worker(model_id, counts, formula, output_path),
    mc.set.seed = FALSE,
    silent = TRUE
  )
  samples <- tibble()
  result <- NULL
  repeat {
    samples <- bind_rows(samples, process_snapshot(c(Sys.getpid(), job$pid), model_id, started_at))
    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      result <- collected[[1]]
      break
    }
    Sys.sleep(1)
  }
  if (inherits(result, "try-error")) stop(model_id, " fit worker failed: ", as.character(result), call. = FALSE)
  if (!file.exists(output_path)) stop(model_id, " fit worker did not create its private artifact", call. = FALSE)
  write_csv_stable(samples, resource_path)
  result$peak_process_tree_rss_bytes <- if (nrow(samples) == 0L) NA_real_ else max(
    samples |>
      group_by(sampled_at_utc) |>
      summarise(total = sum(rss_bytes), .groups = "drop") |>
      pull(total), na.rm = TRUE
  )
  result
}

fixed_prediction <- function(fit, newdata) {
  suppressWarnings(context_preflight_fixed_prediction(fit, newdata))
}

validate_fit <- function(model_id, fit_path, counts, run_metadata, setup_seconds) {
  fit <- readRDS(fit_path)
  model_id_value <- model_id
  expected_coefficients <- if (model_id == "D1") 711L else 720L
  expected_terms <- if (model_id == "D1") {
    c("point_value_factor", "player_id_factor", "shot_distance_feet")
  } else {
    c("point_value_factor", "finish_family", "creation_family", "player_id_factor", "shot_distance_feet")
  }
  prediction_started <- Sys.time()
  probability <- as.numeric(predict(fit, newdata = counts, type = "response"))
  probability_repeat <- as.numeric(predict(fit, newdata = counts, type = "response"))
  prediction_seconds <- as.numeric(difftime(Sys.time(), prediction_started, units = "secs"))
  point_values <- ifelse(counts$point_value_factor == "two", 2L, 3L)
  expected_points <- context_expected_points(probability, point_values)

  player_coef_index <- grepl("player_id_factor", names(coef(fit)), fixed = TRUE)
  player_coefficients <- coef(fit)[player_coef_index]
  chosen_player <- levels(counts$player_id_factor)[which.max(abs(player_coefficients))]
  representative_index <- which(as.character(counts$player_id_factor) == chosen_player)[1]
  if (is.na(representative_index)) representative_index <- 1L
  representative <- counts[representative_index, , drop = FALSE]
  known_full <- as.numeric(predict(fit, newdata = representative, type = "response"))
  known_fixed <- fixed_prediction(fit, representative)
  unseen <- representative
  unseen$player_id_factor <- factor(
    "__UNSEEN_PLAYER__", levels = c(levels(counts$player_id_factor), "__UNSEEN_PLAYER__")
  )
  unseen_probability <- fixed_prediction(fit, unseen)

  levels_frozen <- context_m2_factor_levels()
  boundary <- context_preflight_boundary_grid(
    player_levels = levels(counts$player_id_factor),
    point_value_levels = levels_frozen$point_value_factor,
    distances = 0:88
  )
  if (model_id == "M2") {
    boundary <- boundary |>
      mutate(
        finish_family = factor("regular_jumper", levels = levels_frozen$finish_family),
        creation_family = factor("other_or_unknown", levels = levels_frozen$creation_family),
        .before = 3L
      )
  }
  boundary_probability <- as.numeric(predict(fit, newdata = boundary, type = "response"))

  taxonomy_probability <- numeric()
  if (model_id == "M2") {
    taxonomy_data <- tidyr::crossing(
      point_value_factor = factor(levels_frozen$point_value_factor, levels = levels_frozen$point_value_factor),
      finish_family = factor(levels_frozen$finish_family, levels = levels_frozen$finish_family),
      creation_family = factor(levels_frozen$creation_family, levels = levels_frozen$creation_family)
    ) |>
      mutate(
        player_id_factor = factor(levels(counts$player_id_factor)[[1]], levels = levels(counts$player_id_factor)),
        shot_distance_feet = 22L,
        .before = 1L
      )
    taxonomy_probability <- as.numeric(predict(fit, newdata = taxonomy_data, type = "response"))
  }

  lpmatrix <- predict(fit, newdata = counts[seq_len(min(25L, nrow(counts))), , drop = FALSE], type = "lpmatrix")
  summary_fit <- summary(fit)
  smooth_table <- summary_fit$s.table
  distance_row <- match("s(shot_distance_feet)", rownames(smooth_table))
  if (is.na(distance_row)) stop(model_id, " distance smooth is missing", call. = FALSE)
  distance_edf <- unname(smooth_table[distance_row, "edf"])
  player_row <- match("s(player_id_factor)", rownames(smooth_table))
  player_edf <- unname(smooth_table[player_row, "edf"])
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(CONTEXT_M2_K_CHECK_SEED)
  k_result <- mgcv::k.check(
    fit,
    subsample = CONTEXT_M2_K_CHECK_SUBSAMPLE,
    n.rep = CONTEXT_M2_K_CHECK_REPLICATES
  )
  k_row <- match("s(shot_distance_feet)", rownames(k_result))
  if (is.na(k_row)) stop(model_id, " distance k-check row is missing", call. = FALSE)
  k_index <- unname(k_result[k_row, "k-index"])
  k_p_value <- unname(k_result[k_row, "p-value"])
  k_action <- context_m2_k_escalation(distance_edf, k_index, k_p_value, CONTEXT_M2_INITIAL_K)

  smooth_labels <- vapply(fit$smooth, `[[`, character(1), "label")
  sp_names <- names(fit$sp)
  checks <- tibble(
    model_id = model_id_value,
    check_id = c(
      "formula_identity", "frozen_fit_settings", "registered_terms_only", "coefficient_dimension",
      "model_matrix_identity", "full_convergence", "finite_coefficients",
      "finite_covariance", "two_positive_smoothing_parameters",
      "registered_smooths_only", "finite_interior_probabilities",
      "deterministic_predictions", "expected_points_exact",
      "known_player_effect_used", "unseen_player_zero_deviation",
      "all_0_to_88_distances_predict", "heave_and_boundary_predict",
      "all_taxonomy_levels_predict", "other_or_unknown_predicts",
      "k_10_adequate"
    ),
    passed = c(
      identical(
        gsub("[[:space:]]+", "", paste(deparse(formula(fit)), collapse = "")),
        gsub("[[:space:]]+", "", paste(deparse(context_m2_formulas()[[model_id_value]]), collapse = ""))
      ),
      identical(fit$method, "REML") && identical(fit$optimizer, c("outer", "newton")) &&
        identical(eval(fit$call$discrete), FALSE) && identical(eval(fit$call$select), FALSE) &&
        identical(eval(fit$call$gamma), 1) && identical(eval(fit$call$drop.unused.levels), FALSE),
      setequal(attr(terms(fit), "term.labels"), expected_terms),
      length(coef(fit)) == expected_coefficients,
      ncol(lpmatrix) == length(coef(fit)) && identical(colnames(lpmatrix), names(coef(fit))),
      isTRUE(fit$converged) && identical(fit$outer.info$conv, "full convergence"),
      all(is.finite(coef(fit))),
      all(is.finite(fit$Vp)),
      length(fit$sp) == 2L && all(is.finite(fit$sp)) && all(fit$sp > 0),
      setequal(smooth_labels, c("s(player_id_factor)", "s(shot_distance_feet)")) &&
        setequal(sp_names, c("s(player_id_factor)", "s(shot_distance_feet)")),
      all(is.finite(probability)) && all(probability > 0 & probability < 1),
      isTRUE(all.equal(probability, probability_repeat, tolerance = 1e-13)),
      isTRUE(all.equal(expected_points, probability * point_values, tolerance = 1e-15)),
      is.finite(known_full) && is.finite(known_fixed) && abs(known_full - known_fixed) > 1e-12,
      is.finite(unseen_probability) && isTRUE(all.equal(unseen_probability, known_fixed, tolerance = 1e-12)),
      length(boundary_probability) == 178L && all(is.finite(boundary_probability)) &&
        all(boundary_probability > 0 & boundary_probability < 1),
      all(is.finite(boundary_probability[boundary$shot_distance_feet %in% c(0L, 22L, 23L, 30L, 88L)])),
      model_id_value == "D1" || (length(taxonomy_probability) == 56L && all(is.finite(taxonomy_probability))),
      model_id_value == "D1" || any(taxonomy_data$creation_family == "other_or_unknown"),
      identical(k_action, "retain_k_10")
    ),
    detail = c(
      paste(deparse(formula(fit)), collapse = " "),
      paste0(
        "method=", fit$method, ";optimizer=", paste(fit$optimizer, collapse = "+"),
        ";discrete=", eval(fit$call$discrete), ";select=", eval(fit$call$select),
        ";gamma=", eval(fit$call$gamma), ";drop.unused.levels=", eval(fit$call$drop.unused.levels)
      ),
      paste(sort(attr(terms(fit), "term.labels")), collapse = ";"),
      as.character(length(coef(fit))),
      paste0(nrow(lpmatrix), "x", ncol(lpmatrix)),
      as.character(fit$outer.info$conv),
      as.character(sum(!is.finite(coef(fit)))),
      as.character(sum(!is.finite(fit$Vp))),
      paste(signif(fit$sp, 12), collapse = ";"),
      paste(smooth_labels, collapse = ";"),
      paste(range(probability), collapse = ";"),
      format(max(abs(probability - probability_repeat)), digits = 16),
      format(max(abs(expected_points - probability * point_values)), digits = 16),
      format(known_full - known_fixed, digits = 16),
      format(unseen_probability - known_fixed, digits = 16),
      paste(range(boundary$shot_distance_feet), collapse = ";"),
      "0;22;23;30;88 feet",
      if (model_id_value == "D1") "not_applicable" else "56 combinations",
      if (model_id_value == "D1") "not_applicable" else "ordinary frozen level",
      k_action
    )
  )

  gradient <- if (!is.null(fit$outer.info$grad)) max(abs(fit$outer.info$grad)) else NA_real_
  probability_hash <- hash_values(sprintf("%.17g", probability))
  coefficient_hash <- hash_values(sprintf("%.17g", coef(fit)))
  diagnostics <- tibble(
    model_id = model_id_value,
    training_shots = sum(counts$attempts),
    grouped_rows = nrow(counts),
    players = n_distinct(counts$player_id_factor),
    coefficients = length(coef(fit)),
    smooth_terms = length(fit$smooth),
    player_basis_dimension = fit$smooth[[match("s(player_id_factor)", smooth_labels)]]$bs.dim,
    distance_basis_dimension = fit$smooth[[match("s(shot_distance_feet)", smooth_labels)]]$bs.dim,
    total_effective_degrees_freedom = sum(fit$edf),
    player_effective_degrees_freedom = player_edf,
    distance_effective_degrees_freedom = distance_edf,
    player_smoothing_parameter = unname(fit$sp[[match("s(player_id_factor)", sp_names)]]),
    distance_smoothing_parameter = unname(fit$sp[[match("s(shot_distance_feet)", sp_names)]]),
    k_index = k_index,
    k_p_value = k_p_value,
    k_action = k_action,
    converged = isTRUE(fit$converged),
    convergence_message = fit$outer.info$conv,
    maximum_absolute_gradient = gradient,
    setup_seconds = setup_seconds,
    fit_seconds = run_metadata$fit_seconds,
    serialization_seconds = run_metadata$serialization_seconds,
    fit_and_serialization_wall_seconds = run_metadata$fit_and_serialization_wall_seconds,
    prediction_and_check_seconds = prediction_seconds,
    cpu_user_seconds = run_metadata$cpu_user_seconds,
    cpu_system_seconds = run_metadata$cpu_system_seconds,
    peak_process_tree_rss_bytes = run_metadata$peak_process_tree_rss_bytes,
    fit_object_bytes = run_metadata$fit_object_bytes,
    serialized_fit_bytes = as.numeric(file.info(fit_path)$size),
    sampled_cpu_seconds = run_metadata$sampled_cpu_seconds,
    reused_from_partial = run_metadata$reused_from_partial,
    warning_count = run_metadata$warning_count,
    warning_metadata_status = run_metadata$warning_metadata_status,
    warnings = paste(run_metadata$warnings, collapse = " | "),
    message_count = run_metadata$message_count,
    message_metadata_status = run_metadata$message_metadata_status,
    messages = paste(run_metadata$messages, collapse = " | "),
    probability_sha256 = probability_hash,
    coefficient_sha256 = coefficient_hash
  )
  list(checks = checks, diagnostics = diagnostics, probability_hash = probability_hash, coefficient_hash = coefficient_hash)
}

verify_private_checkpoint <- function(expected_input_hash = NULL) {
  manifest_path <- file.path(private_final, "completion_manifest.csv")
  if (!file.exists(manifest_path)) stop("no completed M2 preflight checkpoint", call. = FALSE)
  manifest <- readr::read_csv(manifest_path, show_col_types = FALSE)
  context_preflight_verify_manifest(manifest, private_final, sha256_file)
  if (any(manifest$validation_outcomes_accessed) || any(manifest$prospective_2026_27_accessed)) {
    stop("checkpoint reports protected outcome access", call. = FALSE)
  }
  if (!is.null(expected_input_hash) && any(manifest$input_hash != expected_input_hash)) {
    stop("checkpoint input hash differs from current frozen inputs", call. = FALSE)
  }
  verification_state <- readr::read_csv(file.path(private_final, "verification_state.csv"), show_col_types = FALSE)
  for (model_id in c("D1", "M2")) {
    fit <- readRDS(file.path(private_final, paste0(tolower(model_id), "_fit.rds")))
    counts <- readRDS(file.path(private_final, paste0(tolower(model_id), "_counts.rds")))
    probability <- as.numeric(predict(fit, newdata = counts, type = "response"))
    expected_hash <- verification_state$probability_sha256[verification_state$model_id == model_id]
    if (hash_values(sprintf("%.17g", probability)) != expected_hash) {
      stop(model_id, " recovery prediction hash mismatch", call. = FALSE)
    }
  }
  tibble(
    checkpoint_complete = TRUE,
    manifest_hashes_verified = TRUE,
    models_refit_during_recovery = 0L,
    prediction_hashes_reproduced = TRUE,
    validation_outcomes_accessed = FALSE,
    prospective_2026_27_accessed = FALSE
  )
}

read_key_value_file <- function(path) {
  if (!file.exists(path)) stop("required recovery metadata is missing: ", path, call. = FALSE)
  lines <- readLines(path, warn = FALSE)
  parts <- strsplit(lines, "=", fixed = TRUE)
  keys <- vapply(parts, `[[`, character(1), 1L)
  values <- vapply(parts, function(x) paste(x[-1L], collapse = "="), character(1))
  setNames(values, keys)
}

parse_ps_cpu_seconds <- function(value) {
  fields <- as.numeric(strsplit(value, ":", fixed = TRUE)[[1]])
  if (anyNA(fields) || !length(fields) %in% c(2L, 3L)) return(NA_real_)
  if (length(fields) == 2L) fields[[1]] * 60 + fields[[2]] else
    fields[[1]] * 3600 + fields[[2]] * 60 + fields[[3]]
}

recovered_d1_metadata <- function(fit_path, resource_path) {
  samples <- readr::read_csv(
    resource_path, show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )
  samples$wall_seconds <- as.numeric(samples$wall_seconds)
  samples$rss_bytes <- as.numeric(samples$rss_bytes)
  cpu_seconds <- vapply(samples$cpu_time_text, parse_ps_cpu_seconds, numeric(1))
  tree_rss <- samples |>
    group_by(sampled_at_utc) |>
    summarise(total = sum(rss_bytes), .groups = "drop")
  fit <- readRDS(fit_path)
  list(
    model_id = "D1",
    fit_seconds = NA_real_,
    serialization_seconds = NA_real_,
    fit_and_serialization_wall_seconds = max(samples$wall_seconds),
    cpu_user_seconds = NA_real_,
    cpu_system_seconds = NA_real_,
    fit_object_bytes = as.numeric(object.size(fit)),
    sampled_cpu_seconds = max(cpu_seconds, na.rm = TRUE),
    peak_process_tree_rss_bytes = max(tree_rss$total),
    reused_from_partial = TRUE,
    warning_count = NA_integer_,
    warning_metadata_status = "unavailable_after_interrupted_checker",
    warnings = character(),
    message_count = NA_integer_,
    message_metadata_status = "unavailable_after_interrupted_checker",
    messages = character()
  )
}

if (mode == "audit") {
  audit <- static_audit()
  message(
    "Static M2 preflight audit passed: training seasons are 2021-22 and 2022-23; ",
    "configuration_sha256=", audit$configuration_sha256, "; no outcomes or model fits were opened."
  )
  quit(save = "no", status = 0L)
}

if (mode == "verify") {
  audit <- static_audit()
  result <- verify_private_checkpoint()
  message("Verified completed M2 training-only checkpoint without refitting; no validation outcomes were opened.")
  quit(save = "no", status = 0L)
}

audit <- static_audit()
dir.create(private_parent, recursive = TRUE, showWarnings = FALSE)
if (dir.exists(private_final) || dir.exists(tracked_final)) {
  stop("a completed M2 preflight exists; use verify instead of fitting again", call. = FALSE)
}
recovery_mode <- mode %in% c("verify-partial", "resume")
partial_verification_only <- identical(mode, "verify-partial")
if (!recovery_mode && dir.exists(private_lock)) {
  stop("an M2 preflight lock already exists; inspect its PID before recovery", call. = FALSE)
}
if (recovery_mode && !dir.exists(private_lock)) stop("the approved recovery lock is missing", call. = FALSE)

process_lines <- system2("ps", c("-axo", "pid=,command="), stdout = TRUE)
matching <- process_lines[
  grepl("context_edition_m2_training_preflight.R", process_lines, fixed = TRUE) &
    (grepl(" run", process_lines, fixed = TRUE) | grepl(" resume", process_lines, fixed = TRUE)) &
    grepl("/bin/exec/R", process_lines, fixed = TRUE)
]
matching_pids <- suppressWarnings(as.integer(sub("^[[:space:]]*([0-9]+).*$", "\\1", matching)))
other_pids <- matching_pids[is.finite(matching_pids) & matching_pids != Sys.getpid()]
if (length(other_pids) > 0L) stop("another M2 training preflight process is active", call. = FALSE)

current_branch <- git_value(c("branch", "--show-current"))
if (current_branch != "codex/context-edition-m2-training-preflight") stop("execution requires the isolated preflight branch", call. = FALSE)
head_commit <- git_value(c("rev-parse", "HEAD"))
origin_commit <- git_value(c("rev-parse", "origin/codex/context-edition-m2-training-preflight"))
if (head_commit != origin_commit) stop("local and origin preflight commits differ", call. = FALSE)
if (recovery_mode && system2(
  "git", c("-C", repo_root, "merge-base", "--is-ancestor", PREFIT_IMPLEMENTATION_COMMIT, head_commit)
) != 0L) stop("the approved pre-fit commit is not in recovery history", call. = FALSE)
status <- git_value(c("status", "--porcelain", "--untracked-files=all"))
status_lines <- status[nzchar(status)]
unrelated <- status_lines[!grepl("^\\?\\? skill-observations/", status_lines)]
if (length(unrelated) > 0L) stop("tracked or unrelated untracked work is present", call. = FALSE)

started_wall <- Sys.time()
started_cpu <- proc.time()
disk_before <- available_disk_bytes(repo_root)
if (disk_before < 5 * 1024^3) stop("less than 5 GiB free disk", call. = FALSE)

if (recovery_mode) {
  attempt_id <- RECOVERY_ATTEMPT_ID
  private_stage <- file.path(private_parent, paste0(".preflight-", attempt_id, ".partial"))
  tracked_stage <- file.path(
    tracked_parent,
    paste0(".context-m2-preflight-recovery-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"))
  )
  if (!dir.exists(private_stage)) stop("the approved partial checkpoint is missing", call. = FALSE)
  if (!partial_verification_only) {
    if (dir.exists(tracked_stage)) stop("the recovery tracked stage already exists", call. = FALSE)
    dir.create(tracked_stage, recursive = TRUE, showWarnings = FALSE)
  }
  log_path <- file.path(private_stage, "preflight.log")
  stage_path <- file.path(private_lock, "metadata.txt")
  lock_metadata <- read_key_value_file(stage_path)
  old_pid <- suppressWarnings(as.integer(lock_metadata[["pid"]]))
  old_pid_line <- system2("ps", c("-p", old_pid, "-o", "pid="), stdout = TRUE)
  if (length(old_pid_line) > 0L && any(nzchar(trimws(old_pid_line)))) {
    stop("the original preflight PID is still active", call. = FALSE)
  }
  if (!identical(lock_metadata[["attempt_id"]], RECOVERY_ATTEMPT_ID) ||
      !identical(lock_metadata[["input_hash"]], RECOVERY_INPUT_HASH)) {
    stop("the stale lock does not belong to the approved recovery attempt", call. = FALSE)
  }
  input_hash <- RECOVERY_INPUT_HASH
  required_hashes <- c(
    "d1_fit.unverified.rds" = RECOVERY_D1_FIT_SHA256,
    "d1_counts.rds" = RECOVERY_D1_COUNTS_SHA256,
    "m2_counts.rds" = RECOVERY_M2_COUNTS_SHA256
  )
  observed_hashes <- map_chr(file.path(private_stage, names(required_hashes)), sha256_file)
  if (!identical(unname(observed_hashes), unname(required_hashes))) {
    stop("a preserved recovery artifact hash changed", call. = FALSE)
  }
  if (file.exists(file.path(private_stage, "m2_fit.unverified.rds")) ||
      file.exists(file.path(private_stage, "m2_fit.rds"))) {
    stop("an M2 fit artifact already exists; duplicate fitting is prohibited", call. = FALSE)
  }
  d1_counts <- readRDS(file.path(private_stage, "d1_counts.rds"))
  m2_counts <- readRDS(file.path(private_stage, "m2_counts.rds"))
  setup_seconds <- NA_real_
  training_counts <- tibble(
    training_seasons = paste(TRAINING_SEASONS, collapse = ";"),
    games = EXPECTED[["games"]], shots = sum(d1_counts$attempts),
    players = n_distinct(d1_counts$player_id_factor), makes = sum(d1_counts$makes),
    misses = sum(d1_counts$misses), distance_min = min(d1_counts$shot_distance_feet),
    distance_max = max(d1_counts$shot_distance_feet),
    heaves_30_plus = sum(d1_counts$attempts[d1_counts$shot_distance_feet >= 30L]),
    validation_outcomes_accessed = FALSE, prospective_2026_27_accessed = FALSE
  )
} else {
  if (!dir.create(private_lock, showWarnings = FALSE)) stop("could not acquire M2 preflight lock", call. = FALSE)
  attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  private_stage <- file.path(private_parent, paste0(".preflight-", attempt_id, ".partial"))
  tracked_stage <- file.path(tracked_parent, paste0(".context-m2-preflight-", attempt_id))
  dir.create(private_stage, recursive = TRUE, showWarnings = FALSE)
  dir.create(tracked_stage, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(private_stage, "preflight.log")
  stage_path <- file.path(private_lock, "metadata.txt")
  training_paths <- file.path(canonical_root, paste0("season=", TRAINING_SEASONS), "canonical_shots.parquet")
  if (!all(file.exists(training_paths))) stop("training partitions are missing", call. = FALSE)
  canonical_manifest_path <- file.path(canonical_root, "completion_manifest.csv")
  canonical_manifest <- readr::read_csv(canonical_manifest_path, show_col_types = FALSE)
  training_manifest <- canonical_manifest[
    canonical_manifest$artifact %in% file.path(paste0("season=", TRAINING_SEASONS), "canonical_shots.parquet"),,
    drop = FALSE
  ]
  if (nrow(training_manifest) != 2L || any(!training_manifest$checks_passed) || any(!training_manifest$atomic_complete)) {
    stop("training partition manifest is incomplete", call. = FALSE)
  }
  if (!identical(unname(vapply(training_paths, sha256_file, character(1))), unname(training_manifest$sha256))) {
    stop("training partition hash mismatch", call. = FALSE)
  }
  input_hash <- hash_values(c(
    sha256_file(config_path), audit$preregistration_inputs_sha256,
    training_manifest$sha256, head_commit
  ))
  write_stage(stage_path, attempt_id, "setup", input_hash)
  write_stage(file.path(private_stage, "stage.txt"), attempt_id, "setup", input_hash)
  message("Loading only frozen first-window training outcomes")
  required_fields <- c(
    "season", "source_game_id", "player_id", "point_value", "finish_family",
    "creation_family", "shot_distance_feet", "field_goal_made"
  )
  training <- purrr::map_dfr(training_paths, function(path) {
    arrow::read_parquet(path, col_select = all_of(required_fields), as_data_frame = TRUE)
  })
  if (!identical(sort(unique(training$season)), TRAINING_SEASONS)) stop("non-training season entered preflight", call. = FALSE)
  if (any(training$season %in% PROHIBITED_OUTCOME_SEASONS)) stop("protected season entered preflight", call. = FALSE)
  context_m2_validate_distance(training$shot_distance_feet)
  if (range(training$shot_distance_feet)[1] != EXPECTED[["distance_min"]] ||
      range(training$shot_distance_feet)[2] != EXPECTED[["distance_max"]]) stop("distance range changed", call. = FALSE)
  if (anyNA(training) || any(!training$field_goal_made %in% 0:1)) stop("training model fields are invalid", call. = FALSE)
  levels_frozen <- context_m2_factor_levels()
  player_levels <- sort(unique(as.character(training$player_id)))
  training <- training |>
    mutate(
      player_id_factor = factor(as.character(player_id), levels = player_levels),
      point_value_factor = factor(if_else(point_value == 2L, "two", "three"), levels = levels_frozen$point_value_factor),
      finish_family = factor(finish_family, levels = levels_frozen$finish_family),
      creation_family = factor(creation_family, levels = levels_frozen$creation_family)
    )
  if (anyNA(training[c("player_id_factor", "point_value_factor", "finish_family", "creation_family")])) {
    stop("factor handling introduced missing values", call. = FALSE)
  }
  training_counts <- tibble(
    training_seasons = paste(TRAINING_SEASONS, collapse = ";"),
    games = n_distinct(training$source_game_id), shots = nrow(training),
    players = n_distinct(training$player_id_factor), makes = sum(training$field_goal_made),
    misses = nrow(training) - sum(training$field_goal_made),
    distance_min = min(training$shot_distance_feet), distance_max = max(training$shot_distance_feet),
    heaves_30_plus = sum(training$shot_distance_feet >= 30L),
    validation_outcomes_accessed = FALSE, prospective_2026_27_accessed = FALSE
  )
  d1_counts <- group_counts(training, "D1")
  m2_counts <- group_counts(training, "M2")
  rm(training)
  invisible(gc())
  saveRDS(d1_counts, file.path(private_stage, "d1_counts.rds"), compress = "xz")
  saveRDS(m2_counts, file.path(private_stage, "m2_counts.rds"), compress = "xz")
  setup_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs"))
}

log_line <- function(...) {
  line <- paste0(format(Sys.time(), tz = "UTC", usetz = TRUE), " ", paste0(..., collapse = ""))
  cat(line, "\n", file = log_path, append = TRUE)
  message(line)
}

if (nrow(d1_counts) != EXPECTED[["D1_rows"]] || nrow(m2_counts) != EXPECTED[["M2_rows"]]) {
  stop("grouped row counts changed", call. = FALSE)
}
for (counts in list(d1_counts, m2_counts)) {
  if (sum(counts$attempts) != EXPECTED[["shots"]] || sum(counts$makes) != EXPECTED[["makes"]] ||
      sum(counts$misses) != EXPECTED[["misses"]] || any(counts$makes + counts$misses != counts$attempts)) {
    stop("grouped counts do not reproduce training totals", call. = FALSE)
  }
}
observed_counts <- unlist(training_counts[c("games", "shots", "players", "makes", "misses")])
if (!identical(as.integer(observed_counts), as.integer(EXPECTED[names(observed_counts)]))) {
  stop("frozen training counts changed", call. = FALSE)
}

formulas <- audit$formulas
all_checks <- list()
all_diagnostics <- list()
models_to_fit <- c("D1", "M2")

if (recovery_mode) {
  if (!partial_verification_only) write_stage(stage_path, attempt_id, "verifying_preserved_d1", input_hash)
  d1_unverified_path <- file.path(private_stage, "d1_fit.unverified.rds")
  d1_resource_path <- file.path(private_stage, "d1_resource_samples.csv")
  d1_metadata <- recovered_d1_metadata(d1_unverified_path, d1_resource_path)
  d1_verified <- validate_fit("D1", d1_unverified_path, d1_counts, d1_metadata, setup_seconds)
  all_checks[["D1"]] <- d1_verified$checks
  all_diagnostics[["D1"]] <- d1_verified$diagnostics
  if (any(!d1_verified$checks$passed)) {
    write_csv_stable(d1_verified$checks, file.path(private_stage, "d1_failed_checks.csv"))
    write_csv_stable(d1_verified$diagnostics, file.path(private_stage, "d1_failed_diagnostics.csv"))
    stop("preserved D1 fit failed a frozen recovery check", call. = FALSE)
  }
  if (partial_verification_only) {
    message("Preserved D1 fit passed every corrected frozen check without mutation or refitting.")
    quit(save = "no", status = 0L)
  }
  if (!file.rename(d1_unverified_path, file.path(private_stage, "d1_fit.rds"))) {
    stop("could not promote the verified preserved D1 fit", call. = FALSE)
  }
  log_line("D1 preserved fit passed all corrected frozen checks without refitting")
  models_to_fit <- "M2"
}

for (model_id in models_to_fit) {
  counts <- if (model_id == "D1") d1_counts else m2_counts
  unverified_path <- file.path(private_stage, paste0(tolower(model_id), "_fit.unverified.rds"))
  final_fit_path <- file.path(private_stage, paste0(tolower(model_id), "_fit.rds"))
  resource_path <- file.path(private_stage, paste0(tolower(model_id), "_resource_samples.csv"))
  metadata <- run_fit_monitored(
    model_id, counts, formulas[[model_id]], unverified_path, resource_path,
    stage_path, attempt_id, input_hash
  )
  verified <- validate_fit(model_id, unverified_path, counts, metadata, setup_seconds)
  all_checks[[model_id]] <- verified$checks
  all_diagnostics[[model_id]] <- verified$diagnostics
  if (any(!verified$checks$passed)) {
    write_csv_stable(verified$checks, file.path(private_stage, paste0(tolower(model_id), "_failed_checks.csv")))
    write_csv_stable(verified$diagnostics, file.path(private_stage, paste0(tolower(model_id), "_failed_diagnostics.csv")))
    stop(model_id, " failed a frozen training-only sanity check", call. = FALSE)
  }
  if (!file.rename(unverified_path, final_fit_path)) stop("could not promote verified private fit", call. = FALSE)
  log_line(model_id, " passed all frozen training-only checks")
}

sanity_checks <- bind_rows(all_checks)
fit_diagnostics <- bind_rows(all_diagnostics)
grouping_audit <- tibble(
  model_id = c("D1", "M2"),
  group_keys = c(paste(group_keys("D1"), collapse = ";"), paste(group_keys("M2"), collapse = ";")),
  grouped_rows = c(nrow(d1_counts), nrow(m2_counts)),
  grouped_attempts = c(sum(d1_counts$attempts), sum(m2_counts$attempts)),
  grouped_makes = c(sum(d1_counts$makes), sum(m2_counts$makes)),
  grouped_misses = c(sum(d1_counts$misses), sum(m2_counts$misses)),
  complete_attempt_reproduction = TRUE,
  validation_rows_loaded = 0L
)
formula_feature_audit <- tibble(
  model_id = c("D1", "M2"),
  formula = vapply(formulas[c("D1", "M2")], function(x) paste(deparse(x), collapse = " "), character(1)),
  registered_predictors_only = TRUE,
  coordinates_in_model = FALSE,
  game_context_in_model = FALSE,
  point_value_preserved = TRUE,
  distance_smooth_shared = TRUE
)
smooth_adequacy <- fit_diagnostics |>
  select(
    model_id, distance_basis_dimension, distance_effective_degrees_freedom,
    distance_smoothing_parameter, k_index, k_p_value, k_action
  ) |>
  mutate(k_10_adequate = k_action == "retain_k_10")
package_versions <- tibble(
  package = c("R", "arrow", "dplyr", "mgcv", "Matrix", "purrr", "readr", "tidyr"),
  version = c(
    paste(R.version$major, R.version$minor, sep = "."),
    map_chr(c("arrow", "dplyr", "mgcv", "Matrix", "purrr", "readr", "tidyr"), ~ as.character(packageVersion(.x)))
  )
)
validation_seal <- tibble(
  season = c(TRAINING_SEASONS, PROHIBITED_OUTCOME_SEASONS),
  outcome_access_for_fit = season %in% TRAINING_SEASONS,
  prediction_created = season %in% TRAINING_SEASONS,
  performance_metric_created = FALSE,
  validation_or_prospective_outcome_accessed = FALSE
)
verification_state <- fit_diagnostics |>
  select(model_id, probability_sha256, coefficient_sha256) |>
  mutate(input_hash = input_hash)
write_csv_stable(verification_state, file.path(private_stage, "verification_state.csv"))

private_artifacts <- c(
  "d1_fit.rds", "m2_fit.rds", "d1_counts.rds", "m2_counts.rds",
  "verification_state.csv", "d1_resource_samples.csv", "m2_resource_samples.csv",
  "preflight.log", "stage.txt"
)
if (recovery_mode && file.exists(file.path(private_stage, "failure_or_interruption.txt"))) {
  private_artifacts <- c(private_artifacts, "failure_or_interruption.txt")
}
private_manifest <- tibble(
  artifact = private_artifacts,
  sha256 = map_chr(file.path(private_stage, private_artifacts), sha256_file),
  atomic_complete = TRUE,
  checks_passed = TRUE,
  preflight_version = PREFLIGHT_VERSION,
  protocol_version = CONTEXT_M2_PROTOCOL_VERSION,
  input_hash = input_hash,
  configuration_sha256 = audit$configuration_sha256,
  pre_fit_implementation_commit = PREFIT_IMPLEMENTATION_COMMIT,
  execution_commit = head_commit,
  recovery_mode = recovery_mode,
  validation_outcomes_accessed = FALSE,
  prospective_2026_27_accessed = FALSE
)
write_csv_stable(private_manifest, file.path(private_stage, "completion_manifest.csv"))
write_stage(file.path(private_stage, "stage.txt"), attempt_id, "complete", input_hash)
# stage.txt changed after its manifest hash was created, so refresh that manifest row.
private_manifest$sha256[private_manifest$artifact == "stage.txt"] <- sha256_file(file.path(private_stage, "stage.txt"))
write_csv_stable(private_manifest, file.path(private_stage, "completion_manifest.csv"))

context_preflight_atomic_publish(private_stage, private_final)
checkpoint_verification <- verify_private_checkpoint(input_hash)
write_stage(stage_path, attempt_id, "verified_complete", input_hash)

total_cpu <- proc.time() - started_cpu
preflight_summary <- tibble(
  preflight_version = PREFLIGHT_VERSION,
  protocol_version = CONTEXT_M2_PROTOCOL_VERSION,
  execution_commit = head_commit,
  pre_fit_implementation_commit = PREFIT_IMPLEMENTATION_COMMIT,
  configuration_sha256 = audit$configuration_sha256,
  input_hash = input_hash,
  training_seasons = paste(TRAINING_SEASONS, collapse = ";"),
  models_fit = 2L,
  d1_fit_count = 1L,
  d1_refit_count = 0L,
  m2_fit_count = 1L,
  models_fit_during_recovery = if_else(recovery_mode, 1L, 2L),
  validation_models_fit = 0L,
  performance_metrics_created = 0L,
  total_wall_seconds = as.numeric(difftime(Sys.time(), started_wall, units = "secs")) +
    if_else(recovery_mode, fit_diagnostics$fit_and_serialization_wall_seconds[fit_diagnostics$model_id == "D1"], 0),
  recovery_wall_seconds = as.numeric(difftime(Sys.time(), started_wall, units = "secs")),
  total_cpu_user_seconds = if_else(
    anyNA(fit_diagnostics$cpu_user_seconds), NA_real_,
    unname(total_cpu[["user.self"]]) + sum(fit_diagnostics$cpu_user_seconds)
  ),
  total_cpu_system_seconds = if_else(
    anyNA(fit_diagnostics$cpu_system_seconds), NA_real_,
    unname(total_cpu[["sys.self"]]) + sum(fit_diagnostics$cpu_system_seconds)
  ),
  d1_sampled_cpu_seconds = fit_diagnostics$sampled_cpu_seconds[fit_diagnostics$model_id == "D1"],
  peak_process_tree_rss_bytes = max(fit_diagnostics$peak_process_tree_rss_bytes, na.rm = TRUE),
  available_disk_bytes_before = disk_before,
  available_disk_bytes_after = available_disk_bytes(repo_root),
  all_checks_passed = all(sanity_checks$passed),
  validation_outcomes_accessed = FALSE,
  prospective_2026_27_accessed = FALSE,
  public_shot_rows = 0L
)
readiness <- tibble(
  decision = if_else(
    all(sanity_checks$passed) && all(smooth_adequacy$k_10_adequate),
    "operationally_ready_for_historical_development_evaluation",
    "stop"
  ),
  d1_role = "non_selection_diagnostic",
  future_formal_comparison = "M2 versus M1",
  validation_run_during_preflight = FALSE,
  basis = "both frozen k=10 training fits passed formula, convergence, prediction, checkpoint, and basis-dimension checks"
)

tracked_tables <- list(
  "training_counts.csv" = training_counts,
  "grouping_audit.csv" = grouping_audit,
  "formula_feature_audit.csv" = formula_feature_audit,
  "fit_diagnostics.csv" = fit_diagnostics,
  "smooth_adequacy.csv" = smooth_adequacy,
  "sanity_checks.csv" = sanity_checks,
  "checkpoint_verification.csv" = checkpoint_verification,
  "preflight_summary.csv" = preflight_summary,
  "package_versions.csv" = package_versions,
  "validation_seal_audit.csv" = validation_seal,
  "readiness.csv" = readiness
)
walk2(tracked_tables, names(tracked_tables), ~ write_csv_stable(.x, file.path(tracked_stage, .y)))
tracked_files <- sort(names(tracked_tables))
tracked_manifest <- tibble(
  file = tracked_files,
  bytes = as.numeric(file.info(file.path(tracked_stage, tracked_files))$size),
  sha256 = map_chr(file.path(tracked_stage, tracked_files), sha256_file),
  contains_shot_level_rows = FALSE,
  declarative_or_aggregate = TRUE
)
write_csv_stable(tracked_manifest, file.path(tracked_stage, "artifact_manifest.csv"))

context_preflight_atomic_publish(tracked_stage, tracked_final)
unlink(private_lock, recursive = TRUE)
if (dir.exists(private_lock)) stop("completed M2 preflight lock did not clear", call. = FALSE)
success <- TRUE
message("D1 and M2 first-window training preflight passed and published atomically; no validation outcome was opened.")
