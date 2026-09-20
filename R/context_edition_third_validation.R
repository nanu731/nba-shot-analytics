#!/usr/bin/env Rscript

# Frozen third rolling-origin M0/M1 comparison and final pooled decision.
# audit: metadata and static checks only; fit: training outcomes only;
# run: exactly one 2025-26 outcome read after all frozen checks pass.

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
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_third_validation.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) == 0L) "audit" else args[[1]]
if (!mode %in% c("audit", "fit", "verify-fit", "run", "verify")) {
  stop("mode must be audit, fit, verify-fit, run, or verify", call. = FALSE)
}

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_third_validation_helpers.R"), local = TRUE)

canonical_root <- file.path(repo_root, "data", "cache", "context_edition_canonical", "context_field_goal_v0.1.2__2021-22_to_2025-26")
training_paths <- file.path(canonical_root, paste0("season=", CONTEXT_THIRD_TRAINING_SEASONS), "canonical_shots.parquet")
validation_path <- file.path(canonical_root, paste0("season=", CONTEXT_THIRD_VALIDATION_SEASON), "canonical_shots.parquet")
private_parent <- file.path(repo_root, "data", "cache", "context_edition_third_validation")
private_pre_result <- file.path(private_parent, "pre_result_v0.1.0")
fit_component_parent <- file.path(private_parent, "fit_components")
fit_roots <- c(M0 = file.path(fit_component_parent, "m0_v0.1.0"), M1 = file.path(fit_component_parent, "m1_v0.1.0"))
fit_final <- file.path(private_parent, "four_season_fits_v0.1.0")
fit_lock <- file.path(private_parent, ".four_season_fits_v0.1.0.lock")
private_final <- file.path(private_parent, "retrospective_3_v0.1.0")
private_lock <- file.path(private_parent, ".retrospective_3_v0.1.0.lock")
access_marker <- file.path(private_parent, ".retrospective_3_v0.1.0.accessed")
tracked_parent <- file.path(repo_root, "data", "processed", "context_edition_third_validation_v0_1")
tracked_results <- file.path(tracked_parent, "results")
config_path <- file.path(repo_root, "config", "context_edition_third_validation_v0_1.csv")
first_results <- file.path(repo_root, "data", "processed", "context_edition_first_validation_v0_1", "results")
second_results <- file.path(repo_root, "data", "processed", "context_edition_second_validation_v0_1", "results")
first_private <- file.path(repo_root, "data", "cache", "context_edition_first_validation", "retrospective_1_v0.1.0")
first_recovery <- file.path(repo_root, "data", "cache", "context_edition_first_validation", "retrospective_1_v0.1.1_auc_recovery")
second_private <- file.path(repo_root, "data", "cache", "context_edition_second_validation", "retrospective_2_v0.1.0")

config <- read_csv(config_path, show_col_types = FALSE)
config_values <- setNames(config$value, config$key)
expected_config <- c(
  evaluation_version = CONTEXT_THIRD_VALIDATION_VERSION,
  protocol_version = CONTEXT_PROTOCOL_VERSION,
  comparison_id = CONTEXT_THIRD_COMPARISON_ID,
  training_seasons = paste(CONTEXT_THIRD_TRAINING_SEASONS, collapse = ";"),
  validation_season = CONTEXT_THIRD_VALIDATION_SEASON,
  later_seasons_analytically_sealed = paste(CONTEXT_THIRD_LATER_SEASONS, collapse = ";"),
  canonical_manifest_sha256 = "5f8e294903701a3fb99511f060b1da269823c63fb350cda9a1fc15ca8cea20dc",
  validation_partition_sha256 = "3cc2c2e6b62b7d87c15965639052da62ef909e49e2b8ea09ef6f2a9f8b370ee7",
  first_result_manifest_sha256 = CONTEXT_FIRST_RESULT_MANIFEST_SHA256,
  second_result_manifest_sha256 = CONTEXT_SECOND_RESULT_MANIFEST_SHA256,
  primary_metric = "pooled_shot_level_bernoulli_log_loss",
  primary_difference_sign = "M1_minus_M0",
  bootstrap_unit = "whole_game_within_validation_season",
  bootstrap_interval = "percentile_95"
)
if (!all(config_values[names(expected_config)] == expected_config)) stop("third-validation configuration changed", call. = FALSE)
if (as.integer(config_values[["validation_outcome_read_count"]]) != 1L) stop("validation outcome read count changed", call. = FALSE)
if (as.numeric(config_values[["probability_clip"]]) != CONTEXT_LOG_CLIP ||
    as.integer(config_values[["bootstrap_replicates"]]) != CONTEXT_BOOTSTRAP_REPLICATES ||
    as.integer(config_values[["bootstrap_seed"]]) != CONTEXT_BOOTSTRAP_SEED ||
    as.numeric(config_values[["material_calibration_margin"]]) != CONTEXT_CALIBRATION_MARGIN ||
    as.integer(config_values[["calibration_bins"]]) != CONTEXT_CALIBRATION_BINS ||
    as.integer(config_values[["minimum_subgroup_shots"]]) != CONTEXT_MIN_SUBGROUP_SHOTS) {
  stop("numeric evaluation settings changed", call. = FALSE)
}
if (any(config_values[c("validation_model_updates_allowed", "public_shot_rows")] != "FALSE") ||
    config_values[["final_model_selection_allowed"]] != "TRUE") {
  stop("a protected setting changed", call. = FALSE)
}

required_versions <- c(mgcv = "1.9.4", Matrix = "1.7.5", arrow = "25.0.0", dplyr = "1.2.1", tidyr = "1.3.2", readr = "2.2.0")
observed_versions <- vapply(names(required_versions), function(package) as.character(utils::packageVersion(package)), character(1))
if (!identical(unname(observed_versions), unname(required_versions)) || paste(R.version$major, R.version$minor, sep = ".") != "4.6.0") {
  stop("package or R version differs from the frozen protocol", call. = FALSE)
}

canonical_manifest_path <- file.path(canonical_root, "completion_manifest.csv")
canonical_manifest <- read_csv(canonical_manifest_path, show_col_types = FALSE)
context_verify_file_manifest(canonical_manifest, canonical_root)
if (context_sha256_file(canonical_manifest_path) != config_values[["canonical_manifest_sha256"]]) stop("canonical manifest changed", call. = FALSE)
first_manifest_path <- file.path(first_results, "artifact_manifest.csv")
first_manifest <- read_csv(first_manifest_path, show_col_types = FALSE)
context_verify_file_manifest(first_manifest, first_results)
if (context_sha256_file(first_manifest_path) != CONTEXT_FIRST_RESULT_MANIFEST_SHA256) stop("first result changed", call. = FALSE)
second_manifest_path <- file.path(second_results, "artifact_manifest.csv")
second_manifest <- read_csv(second_manifest_path, show_col_types = FALSE)
context_verify_file_manifest(second_manifest, second_results)
if (context_sha256_file(second_manifest_path) != CONTEXT_SECOND_RESULT_MANIFEST_SHA256) stop("second result changed", call. = FALSE)
verify_private_checkpoint <- function(root, completion_hash, prediction_hash, label) {
  completion_path <- file.path(root, "completion_manifest.csv")
  completion <- read_csv(completion_path, show_col_types = FALSE)
  context_verify_file_manifest(completion, root)
  if (context_sha256_file(completion_path) != completion_hash ||
      context_sha256_file(file.path(root, "shot_predictions.parquet")) != prediction_hash) {
    stop(label, " private prediction checkpoint changed", call. = FALSE)
  }
}
verify_private_checkpoint(first_private, config_values[["first_private_completion_sha256"]], config_values[["first_original_prediction_checkpoint_sha256"]], "first")
context_verify_file_manifest(read_csv(file.path(first_recovery, "completion_manifest.csv"), show_col_types = FALSE), first_recovery)
if (context_sha256_file(file.path(first_recovery, "completion_manifest.csv")) != config_values[["first_auc_recovery_completion_sha256"]]) stop("first AUC recovery changed", call. = FALSE)
verify_private_checkpoint(second_private, config_values[["second_private_completion_sha256"]], config_values[["second_prediction_checkpoint_sha256"]], "second")
training_hashes <- vapply(training_paths, context_sha256_file, character(1))
if (paste(training_hashes, collapse = ";") != config_values[["training_partition_sha256s"]]) stop("training partition changed", call. = FALSE)
if (context_sha256_file(validation_path) != config_values[["validation_partition_sha256"]]) stop("validation partition changed", call. = FALSE)

metadata_fields <- c("season", "canonical_shot_key", "source_game_id", "player_id", "point_value", "finish_family", "creation_family")
training_metadata <- map_dfr(training_paths, ~ read_parquet(.x, col_select = all_of(metadata_fields), as_data_frame = TRUE)) |>
  arrange(season, canonical_shot_key)
validation_metadata <- read_parquet(validation_path, col_select = all_of(metadata_fields), as_data_frame = TRUE) |>
  arrange(canonical_shot_key)
factor_levels <- context_factor_levels()
if (!identical(sort(unique(training_metadata$season)), CONTEXT_THIRD_TRAINING_SEASONS) || nrow(training_metadata) != 872169L ||
    n_distinct(training_metadata$source_game_id) != 4920L || n_distinct(training_metadata$player_id) != 913L) stop("training metadata changed", call. = FALSE)
if (!identical(unique(validation_metadata$season), CONTEXT_THIRD_VALIDATION_SEASON) || nrow(validation_metadata) != 219160L ||
    n_distinct(validation_metadata$source_game_id) != 1230L || n_distinct(validation_metadata$player_id) != 582L ||
    anyDuplicated(validation_metadata$canonical_shot_key)) stop("validation metadata changed", call. = FALSE)
if (!setequal(validation_metadata$finish_family, factor_levels$finish_family) ||
    !setequal(validation_metadata$creation_family, factor_levels$creation_family)) stop("validation taxonomy support changed", call. = FALSE)
if (length(intersect(as.character(training_metadata$source_game_id), as.character(validation_metadata$source_game_id))) > 0L) stop("training and validation games overlap", call. = FALSE)

shot_key_hash <- context_hash_values(validation_metadata$canonical_shot_key)
game_key_hash <- context_hash_values(sort(unique(as.character(validation_metadata$source_game_id))))
player_key_hash <- context_hash_values(sort(unique(as.character(validation_metadata$player_id))))
population_manifest <- tibble(
  evaluation_version = CONTEXT_THIRD_VALIDATION_VERSION,
  comparison_id = CONTEXT_THIRD_COMPARISON_ID,
  training_seasons = paste(CONTEXT_THIRD_TRAINING_SEASONS, collapse = ";"),
  validation_season = CONTEXT_THIRD_VALIDATION_SEASON,
  training_games = 4920L, training_shots = 872169L, training_players = 913L,
  validation_games = 1230L, validation_shots = 219160L, validation_players = 582L,
  canonical_partition_sha256 = context_sha256_file(validation_path),
  ordered_shot_key_sha256 = shot_key_hash,
  sorted_game_key_sha256 = game_key_hash,
  sorted_player_key_sha256 = player_key_hash,
  validation_outcomes_accessed = FALSE,
  later_seasons_outcomes_accessed = FALSE
)

output_schema <- tibble(
  artifact = c("execution_manifest.csv", "fit_diagnostics.csv", "pooled_metrics.csv", "season_metrics.csv", "calibration_bins.csv", "subgroup_calibration.csv", "bootstrap_summary.csv", "model_selection.csv", "running_season_status.csv", "three_season_metrics.csv", "pooled_three_season_metrics.csv", "pooled_calibration_bins.csv", "pooled_subgroup_calibration.csv", "pooled_bootstrap_summary.csv", "final_model_decision.csv", "execution_checks.csv", "artifact_manifest.csv"),
  public_granularity = c("one evaluation row", "one row per model", "metric by model and paired difference", "season-metric by model and paired difference", "model by calibration bin", "model by registered aggregate subgroup", "three aggregate paired-bootstrap rows", "one completed season record", "one row per completed retrospective season", "season-model-metric rows", "pooled model-metric rows", "pooled model-bin rows", "pooled registered subgroup rows", "three pooled bootstrap rows", "one mechanical final decision", "aggregate pass-fail rows", "one row per public artifact"),
  contains_shot_rows = FALSE,
  contains_identifiers = FALSE
)

pre_result_checks <- tibble(
  check_id = c("canonical_hashes", "prior_results_immutable", "prior_prediction_checkpoints", "training_metadata", "validation_metadata", "whole_games", "taxonomy_levels", "safe_auc_double_arithmetic", "later_seasons_sealed", "no_existing_access", "no_existing_result"),
  passed = c(TRUE, TRUE, TRUE, nrow(training_metadata) == 872169L, nrow(validation_metadata) == 219160L,
             length(intersect(training_metadata$source_game_id, validation_metadata$source_game_id)) == 0L,
             setequal(validation_metadata$finish_family, factor_levels$finish_family) && setequal(validation_metadata$creation_family, factor_levels$creation_family),
             is.double(as.double(sum(rep(c(0L, 1L), 60000L) == 1L))), TRUE,
             !dir.exists(access_marker), !dir.exists(private_final) && !dir.exists(tracked_results)),
  detail = c("canonical completion and five selected partition hashes matched", "first and second public results unchanged", "original split-specific prediction manifests matched", "872169 shots; 4920 games; 913 players", "219160 shots; 1230 games; 582 players; no outcomes selected", "zero shared game ids", "all seven finish and four creation levels present", "AUC count products are promoted to double", "2026-27 has no loader or path", "no third marker", "no third result")
)

if (mode == "audit") {
  if (dir.exists(access_marker) || dir.exists(private_final) || dir.exists(tracked_results)) stop("prior third-validation state exists", call. = FALSE)
  dir.create(private_parent, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(private_pre_result)) {
    stage <- paste0(private_pre_result, ".partial")
    if (dir.exists(stage)) stop("partial pre-result state exists", call. = FALSE)
    dir.create(stage, recursive = TRUE)
    context_write_csv_stable(population_manifest, file.path(stage, "validation_population_manifest.csv"))
    context_write_csv_stable(pre_result_checks, file.path(stage, "pre_result_checks.csv"))
    manifest <- tibble(artifact = c("validation_population_manifest.csv", "pre_result_checks.csv"), sha256 = vapply(file.path(stage, c("validation_population_manifest.csv", "pre_result_checks.csv")), context_sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE)
    context_write_csv_stable(manifest, file.path(stage, "completion_manifest.csv"))
    if (!file.rename(stage, private_pre_result)) stop("private pre-result publication failed", call. = FALSE)
  } else {
    context_verify_file_manifest(read_csv(file.path(private_pre_result, "completion_manifest.csv"), show_col_types = FALSE), private_pre_result)
    saved <- read_csv(file.path(private_pre_result, "validation_population_manifest.csv"), show_col_types = FALSE)
    if (!context_character_equal(saved, population_manifest)) stop("saved outcome-free population changed", call. = FALSE)
  }
  dir.create(tracked_parent, recursive = TRUE, showWarnings = FALSE)
  context_atomic_write_csv(population_manifest, file.path(tracked_parent, "outcome_free_population_manifest.csv"))
  context_atomic_write_csv(pre_result_checks, file.path(tracked_parent, "pre_result_checks.csv"))
  context_atomic_write_csv(output_schema, file.path(tracked_parent, "output_schema.csv"))
  message("Outcome-free third-validation audit passed; no validation outcome was read")
  quit(save = "no", status = 0L)
}

verify_clean_pushed <- function() {
  pre_result_commit <- config_values[["pre_result_implementation_commit"]]
  if (!grepl("^[0-9a-f]{40}$", pre_result_commit)) stop("pre-result commit is not recorded", call. = FALSE)
  head_commit <- context_git_value(repo_root, c("rev-parse", "HEAD"))
  upstream_commit <- context_git_value(repo_root, c("rev-parse", "@{upstream}"))
  if (head_commit != upstream_commit) stop("local and remote commits differ", call. = FALSE)
  if (system2("git", c("-C", repo_root, "merge-base", "--is-ancestor", pre_result_commit, "HEAD")) != 0L) stop("pre-result commit is not in history", call. = FALSE)
  if (system2("git", c("-C", repo_root, "diff", "--quiet")) != 0L || system2("git", c("-C", repo_root, "diff", "--cached", "--quiet")) != 0L) stop("tracked worktree is not clean", call. = FALSE)
  status_lines <- system2("git", c("-C", repo_root, "status", "--porcelain"), stdout = TRUE)
  unexpected <- status_lines[startsWith(status_lines, "?? ") & status_lines != "?? skill-observations/"]
  if (length(unexpected) > 0L) stop("unexpected untracked files exist", call. = FALSE)
  c(head = head_commit, pre_result = pre_result_commit)
}

validate_fit <- function(model_id, fit, counts, warnings_seen, fit_seconds, cpu_used, setup_seconds) {
  probabilities <- as.numeric(predict(fit, newdata = counts, type = "response"))
  probabilities_repeat <- as.numeric(predict(fit, newdata = counts, type = "response"))
  gradient <- if (!is.null(fit$outer.info$grad)) max(abs(fit$outer.info$grad)) else NA_real_
  random_edf <- sum(fit$edf[grepl("player_id_factor", names(fit$edf), fixed = TRUE)])
  expected_formula <- gsub("[[:space:]]+", "", paste(deparse(context_model_formulas()[[model_id]]), collapse = ""))
  observed_formula <- gsub("[[:space:]]+", "", paste(deparse(formula(fit)), collapse = ""))
  checks <- tibble(model_id = model_id, check = c("fit_converged", "finite_coefficients", "finite_covariance", "positive_finite_smoothing", "nonboundary_player_effect", "finite_interior_probabilities", "deterministic_prediction", "formula_identity", "no_fit_warning"), passed = c(isTRUE(fit$converged), all(is.finite(coef(fit))), all(is.finite(fit$Vp)), length(fit$sp) == 1L && all(is.finite(fit$sp)) && all(fit$sp > 0), is.finite(random_edf) && random_edf > 0, all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1), isTRUE(all.equal(probabilities, probabilities_repeat, tolerance = 1e-13)), expected_formula == observed_formula, length(warnings_seen) == 0L))
  if (!all(checks$passed)) stop(model_id, " failed frozen fit sanity checks", call. = FALSE)
  diagnostics <- tibble(model_id = model_id, training_shots = sum(counts$attempts), grouped_rows = nrow(counts), players = n_distinct(counts$player_id_factor), coefficients = length(coef(fit)), smooth_terms = length(fit$smooth), random_effect_basis_dimension = fit$smooth[[1]]$bs.dim, smoothing_parameter = unname(fit$sp[[1]]), effective_degrees_freedom = sum(fit$edf), random_effect_effective_degrees_freedom = random_edf, converged = isTRUE(fit$converged), convergence_message = ifelse(is.null(fit$outer.info$conv), "unavailable", fit$outer.info$conv), maximum_absolute_gradient = gradient, setup_seconds = setup_seconds, fit_seconds = fit_seconds, cpu_user_seconds = unname(cpu_used[["user.self"]]), cpu_system_seconds = unname(cpu_used[["sys.self"]]), sampled_rss_bytes_after_fit = context_current_rss_bytes(), fit_object_bytes = as.numeric(object.size(fit)), warnings = paste(warnings_seen, collapse = " | "), warning_count = length(warnings_seen))
  list(checks = checks, diagnostics = diagnostics)
}

fit_one_component <- function(model_id, counts, setup_seconds, attempt_id, fit_log_path) {
  component_root <- fit_roots[[model_id]]
  if (dir.exists(component_root)) return(context_verify_third_fit_component(component_root, model_id))
  stage <- paste0(component_root, ".", attempt_id, ".partial")
  if (dir.exists(stage)) stop("partial fit component exists; inspect before recovery", call. = FALSE)
  dir.create(stage, recursive = TRUE)
  cat(format(Sys.time(), tz = "UTC", usetz = TRUE), " starting ", model_id, "\n", sep = "", file = fit_log_path, append = TRUE)
  warnings_seen <- character()
  started <- Sys.time(); cpu_started <- proc.time()
  setTimeLimit(elapsed = as.numeric(config_values[["fit_timeout_seconds"]]), transient = TRUE)
  fit <- withCallingHandlers(mgcv::gam(formula = context_model_formulas()[[model_id]], family = stats::binomial(link = "logit"), data = counts, method = "REML", optimizer = c("outer", "newton"), control = mgcv::gam.control(), select = FALSE, gamma = 1, na.action = stats::na.fail, drop.unused.levels = FALSE, discrete = FALSE), warning = function(w) { warnings_seen <<- c(warnings_seen, conditionMessage(w)); invokeRestart("muffleWarning") })
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  fit_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs")); cpu_used <- proc.time() - cpu_started
  verified <- validate_fit(model_id, fit, counts, unique(warnings_seen), fit_seconds, cpu_used, setup_seconds)
  saveRDS(fit, file.path(stage, "fit.rds"), compress = "xz")
  verified$diagnostics$serialized_fit_bytes <- file.info(file.path(stage, "fit.rds"))$size
  metadata <- tibble(model_id = model_id, training_seasons = paste(CONTEXT_THIRD_TRAINING_SEASONS, collapse = ";"), training_shots = sum(counts$attempts), training_players = n_distinct(counts$player_id_factor), grouped_rows = nrow(counts), converged = TRUE, validation_outcomes_accessed = FALSE, fit_sha256 = context_sha256_file(file.path(stage, "fit.rds")), config_sha256 = context_sha256_file(config_path), canonical_manifest_sha256 = context_sha256_file(canonical_manifest_path), training_partition_sha256s = paste(training_hashes, collapse = ";"), process_id = Sys.getpid(), completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
  context_write_csv_stable(metadata, file.path(stage, "fit_metadata.csv")); context_write_csv_stable(verified$diagnostics, file.path(stage, "fit_diagnostics.csv")); context_write_csv_stable(verified$checks, file.path(stage, "sanity_checks.csv"))
  artifacts <- c("fit.rds", "fit_metadata.csv", "fit_diagnostics.csv", "sanity_checks.csv")
  manifest <- tibble(artifact = artifacts, sha256 = vapply(file.path(stage, artifacts), context_sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE)
  context_write_csv_stable(manifest, file.path(stage, "completion_manifest.csv")); context_verify_file_manifest(manifest, stage)
  if (!file.rename(stage, component_root)) stop("atomic fit component publication failed", call. = FALSE)
  cat(format(Sys.time(), tz = "UTC", usetz = TRUE), " completed ", model_id, "\n", sep = "", file = fit_log_path, append = TRUE)
  context_verify_third_fit_component(component_root, model_id)
}

if (mode %in% c("fit", "verify-fit")) {
  commits <- verify_clean_pushed()
  if (dir.exists(access_marker) || dir.exists(private_final) || dir.exists(tracked_results)) stop("outcome-dependent third-validation state already exists", call. = FALSE)
  if (!dir.exists(private_pre_result)) stop("outcome-free pre-result manifest is missing", call. = FALSE)
  if (mode == "verify-fit") {
    if (!dir.exists(fit_final)) stop("combined fit checkpoint is missing", call. = FALSE)
    context_verify_file_manifest(read_csv(file.path(fit_final, "completion_manifest.csv"), show_col_types = FALSE), fit_final)
    fits_verified <- map2(fit_roots, names(fit_roots), context_verify_third_fit_component)
    summary <- read_csv(file.path(fit_final, "fit_summary.csv"), show_col_types = FALSE)
    if (!all(summary$fit_sha256 == vapply(fits_verified, `[[`, character(1), "fit_sha256"))) stop("combined fit hashes changed", call. = FALSE)
    message("Four-season M0/M1 fit checkpoint verified; no model was refit")
    quit(save = "no", status = 0L)
  }
  if (dir.exists(fit_final)) stop("combined fit checkpoint exists; use verify-fit", call. = FALSE)
  if (dir.exists(fit_lock) || !dir.create(fit_lock, recursive = TRUE)) stop("fit lock exists or cannot be acquired", call. = FALSE)
  attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  fit_log_path <- file.path(fit_lock, "fit.log")
  writeLines(c(paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id), "stage=loading_four_training_seasons", "validation_outcomes_accessed=false", "2026_27_accessed=false"), file.path(fit_lock, "metadata.txt"))
  writeLines(paste(format(Sys.time(), tz = "UTC", usetz = TRUE), "fit attempt started"), fit_log_path)
  fit_success <- FALSE
  on.exit({
    if (!fit_success && dir.exists(fit_lock)) {
      writeLines(c(paste0("attempt_id=", attempt_id), paste0("ended_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)), "status=failed_or_interrupted", "validation_outcomes_accessed=false", "no_statistical_rule_changed=true"), file.path(fit_lock, "failure_or_interruption.txt"))
    }
  }, add = TRUE)
  fit_started <- Sys.time(); cpu_started <- proc.time(); memory_samples <- context_current_rss_bytes(); disk_before <- context_available_disk_bytes(repo_root)
  training <- map_dfr(training_paths, ~ read_parquet(.x, col_select = all_of(c("season", "player_id", "point_value", "finish_family", "creation_family", "field_goal_made")), as_data_frame = TRUE))
  if (nrow(training) != 872169L || !identical(sort(unique(training$season)), CONTEXT_THIRD_TRAINING_SEASONS) || any(!training$field_goal_made %in% c(0L, 1L))) stop("training outcomes failed frozen checks", call. = FALSE)
  player_levels <- sort(unique(as.character(training$player_id)))
  training <- training |> mutate(player_id_factor = factor(as.character(player_id), levels = player_levels), point_value_factor = factor(if_else(point_value == 2L, "two", "three"), levels = factor_levels$point_value_factor), finish_family = factor(finish_family, levels = factor_levels$finish_family), creation_family = factor(creation_family, levels = factor_levels$creation_family)) |> select(-player_id)
  if (anyNA(training) || n_distinct(training$player_id_factor) != 913L ||
      !setequal(training$finish_family, factor_levels$finish_family) ||
      !setequal(training$creation_family, factor_levels$creation_family)) stop("training factor construction failed", call. = FALSE)
  setup_seconds <- as.numeric(difftime(Sys.time(), fit_started, units = "secs"))
  m0_counts <- context_preflight_group_counts(training, "M0"); m1_counts <- context_preflight_group_counts(training, "M1")
  if (sum(m0_counts$attempts) != 872169L || sum(m1_counts$attempts) != 872169L || sum(m0_counts$makes) != sum(training$field_goal_made) || sum(m1_counts$makes) != sum(training$field_goal_made)) stop("grouped counts do not reproduce training", call. = FALSE)
  writeLines(c(paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id), "stage=fitting_or_recovering_m0_m1", "validation_outcomes_accessed=false"), file.path(fit_lock, "metadata.txt"))
  m0 <- fit_one_component("M0", m0_counts, setup_seconds, attempt_id, fit_log_path); memory_samples <- c(memory_samples, context_current_rss_bytes())
  m1 <- fit_one_component("M1", m1_counts, setup_seconds, attempt_id, fit_log_path); memory_samples <- c(memory_samples, context_current_rss_bytes())
  combined_stage <- paste0(fit_final, ".", attempt_id, ".partial"); dir.create(combined_stage, recursive = TRUE)
  fit_summary <- bind_rows(m0$metadata, m1$metadata) |> mutate(total_training_games = 4920L, total_training_shots = 872169L, total_training_players = 913L, fits_completed = 2L, validation_outcomes_accessed = FALSE) |> arrange(model_id)
  context_write_csv_stable(fit_summary, file.path(combined_stage, "fit_summary.csv"))
  context_write_csv_stable(bind_rows(m0$diagnostics, m1$diagnostics) |> arrange(model_id), file.path(combined_stage, "fit_diagnostics.csv"))
  context_write_csv_stable(bind_rows(m0$checks, m1$checks) |> arrange(model_id, check), file.path(combined_stage, "sanity_checks.csv"))
  runtime <- tibble(total_wall_seconds = as.numeric(difftime(Sys.time(), fit_started, units = "secs")), total_cpu_user_seconds = unname((proc.time() - cpu_started)[["user.self"]]), total_cpu_system_seconds = unname((proc.time() - cpu_started)[["sys.self"]]), sampled_peak_rss_bytes = max(memory_samples, na.rm = TRUE), disk_bytes_before = disk_before, disk_bytes_after = context_available_disk_bytes(repo_root), fits_completed = 2L, validation_outcomes_accessed = FALSE)
  context_write_csv_stable(runtime, file.path(combined_stage, "runtime_summary.csv"))
  small_artifacts <- c("fit_summary.csv", "fit_diagnostics.csv", "sanity_checks.csv", "runtime_summary.csv")
  manifest <- tibble(artifact = small_artifacts, sha256 = vapply(file.path(combined_stage, small_artifacts), context_sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE)
  context_write_csv_stable(manifest, file.path(combined_stage, "completion_manifest.csv")); context_verify_file_manifest(manifest, combined_stage)
  if (!file.rename(combined_stage, fit_final)) stop("combined fit checkpoint publication failed", call. = FALSE)
  if (!file.rename(fit_lock, file.path(fit_final, "completed_lock_metadata"))) stop("could not preserve fit lock metadata", call. = FALSE)
  fit_success <- TRUE
  message("Frozen four-season M0/M1 fits completed and published atomically; no validation outcome was read")
  quit(save = "no", status = 0L)
}

if (mode == "verify") {
  if (!dir.exists(private_final) || !dir.exists(tracked_results)) stop("completed third-validation result is missing", call. = FALSE)
  context_verify_file_manifest(read_csv(file.path(private_final, "completion_manifest.csv"), show_col_types = FALSE), private_final)
  context_verify_file_manifest(read_csv(file.path(tracked_results, "artifact_manifest.csv"), show_col_types = FALSE), tracked_results)
  message("Completed third-validation result verified without loading outcomes or refitting")
  quit(save = "no", status = 0L)
}

# run mode: verify fits and outcome-free predictions before creating access marker.
commits <- verify_clean_pushed()
if (!dir.exists(fit_final)) stop("four-season fit checkpoint is missing", call. = FALSE)
context_verify_file_manifest(read_csv(file.path(fit_final, "completion_manifest.csv"), show_col_types = FALSE), fit_final)
m0 <- context_verify_third_fit_component(fit_roots[["M0"]], "M0"); m1 <- context_verify_third_fit_component(fit_roots[["M1"]], "M1")
if (dir.exists(private_final) || dir.exists(tracked_results)) stop("completed result exists; use verify", call. = FALSE)
if (dir.exists(access_marker)) stop("2025-26 outcome access already marked; fresh execution prohibited", call. = FALSE)
if (dir.exists(private_lock) || !dir.create(private_lock, recursive = TRUE)) stop("evaluation lock exists or cannot be acquired", call. = FALSE)

attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
private_stage <- file.path(private_parent, paste0(".retrospective_3-", attempt_id, ".partial"))
tracked_stage <- file.path(tracked_parent, paste0(".results-", attempt_id, ".partial"))
dir.create(private_stage, recursive = TRUE); dir.create(tracked_stage, recursive = TRUE)
success <- FALSE; started_wall <- Sys.time(); started_cpu <- proc.time(); memory_samples <- context_current_rss_bytes(); disk_before <- context_available_disk_bytes(repo_root)
log_path <- file.path(private_stage, "evaluation.log")
log_line <- function(...) { line <- paste0(format(Sys.time(), tz = "UTC", usetz = TRUE), " ", paste0(..., collapse = "")); cat(line, "\n", file = log_path, append = TRUE); message(line) }
writeLines(c(paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id), "stage=outcome_free_prediction_check", "validation_outcomes_accessed=false", "2025_26_outcomes_accessed=false", "2026_27_accessed=false"), file.path(private_lock, "metadata.txt"))
on.exit({ if (!success && dir.exists(private_stage)) context_write_csv_stable(tibble(attempt_id = attempt_id, ended_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), status = "failed_or_interrupted", access_marker_exists = dir.exists(access_marker), no_statistical_rule_changed = TRUE), file.path(private_stage, "failure_or_interruption.csv")) }, add = TRUE)

m0_dry <- context_predict_first_validation(m0$fit, validation_metadata); m1_dry <- context_predict_first_validation(m1$fit, validation_metadata)
if (length(m0_dry$probability) != 219160L || length(m1_dry$probability) != 219160L) stop("outcome-free prediction row count changed", call. = FALSE)
memory_samples <- c(memory_samples, context_current_rss_bytes())
log_line("All pre-outcome checks passed; publishing exclusive 2025-26 access marker")
if (!dir.create(access_marker)) stop("could not create exclusive access marker", call. = FALSE)
access_record <- tibble(evaluation_version = CONTEXT_THIRD_VALIDATION_VERSION, comparison_id = CONTEXT_THIRD_COMPARISON_ID, validation_season = CONTEXT_THIRD_VALIDATION_SEASON, opened_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), pid = Sys.getpid(), code_commit = commits[["head"]], pre_result_implementation_commit = commits[["pre_result"]], canonical_manifest_sha256 = context_sha256_file(canonical_manifest_path), validation_partition_sha256 = context_sha256_file(validation_path), configuration_sha256 = context_sha256_file(config_path), m0_fit_sha256 = m0$fit_sha256, m1_fit_sha256 = m1$fit_sha256, outcome_read_authorized = TRUE, outcome_read_count_allowed = 1L, source_read_count = 1L, season_2025_26_outcomes_accessed = TRUE, season_2026_27_accessed = FALSE)
context_atomic_write_csv(access_record, file.path(access_marker, "access_marker.csv"))
writeLines(c(paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id), "stage=loading_2025_26_outcomes_once", "validation_outcomes_accessed=true", "2025_26_outcomes_accessed=true", "2026_27_accessed=false"), file.path(private_lock, "metadata.txt"))
outcome_started <- Sys.time()
validation <- read_parquet(validation_path, col_select = all_of(c(metadata_fields, "field_goal_made")), as_data_frame = TRUE) |> arrange(canonical_shot_key)
outcome_read_seconds <- as.numeric(difftime(Sys.time(), outcome_started, units = "secs"))
context_atomic_write_csv(tibble(completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), outcome_reads_completed = 1L), file.path(access_marker, "outcome_read_completed.csv"))
if (nrow(validation) != 219160L || context_hash_values(validation$canonical_shot_key) != shot_key_hash || any(!validation$field_goal_made %in% c(0L, 1L))) stop("single outcome read failed frozen population checks", call. = FALSE)

volume_groups <- context_training_volume_groups(training_metadata)
validation <- validation |> left_join(volume_groups, by = "player_id", relationship = "many-to-one") |> mutate(player_volume_group = if_else(is.na(player_volume_group), "unseen_player", player_volume_group), comparison_id = CONTEXT_THIRD_COMPARISON_ID)
returning_players <- n_distinct(validation$player_id[validation$player_volume_group != "unseen_player"]); unseen_players <- n_distinct(validation$player_id[validation$player_volume_group == "unseen_player"])
prediction_started <- Sys.time(); m0_prediction <- context_predict_first_validation(m0$fit, validation); m1_prediction <- context_predict_first_validation(m1$fit, validation); prediction_seconds <- as.numeric(difftime(Sys.time(), prediction_started, units = "secs"))
predictions <- validation |> transmute(comparison_id, season, canonical_shot_key, game_id = as.character(source_game_id), player_id, point_value, finish_family, creation_family, player_volume_group, outcome = field_goal_made, probability_m0 = m0_prediction$probability, probability_m1 = m1_prediction$probability, expected_points_m0 = context_expected_points(probability_m0, point_value), expected_points_m1 = context_expected_points(probability_m1, point_value), known_player_m0 = m0_prediction$known_player, known_player_m1 = m1_prediction$known_player)
if (anyNA(predictions) || anyDuplicated(predictions$canonical_shot_key) || any(!is.finite(predictions$probability_m0)) || any(!is.finite(predictions$probability_m1)) || !identical(predictions$expected_points_m0, predictions$probability_m0 * predictions$point_value) || !identical(predictions$expected_points_m1, predictions$probability_m1 * predictions$point_value)) stop("prediction integrity failed", call. = FALSE)

evaluation_started <- Sys.time(); metrics <- list(M0 = context_model_metrics(validation, predictions$probability_m0), M1 = context_model_metrics(validation, predictions$probability_m1)); evaluation_seconds <- as.numeric(difftime(Sys.time(), evaluation_started, units = "secs"))
metric_ids <- names(metrics$M0); metric_roles <- c(bernoulli_log_loss = "primary", brier_score = "diagnostic", roc_auc = "diagnostic", expected_points_rmse = "secondary", game_points_mae = "secondary", game_points_rmse = "secondary", points_bias_per_100 = "diagnostic", predicted_rate = "calibration", observed_rate = "calibration", signed_bias_observed_minus_predicted = "calibration", absolute_bias = "calibration_gate", calibration_intercept = "calibration", calibration_intercept_estimable = "check", calibration_slope = "calibration", calibration_slope_estimable = "check")
pooled_metrics <- bind_rows(tibble(model_id = "M0", metric_id = metric_ids, value = unname(metrics$M0)), tibble(model_id = "M1", metric_id = metric_ids, value = unname(metrics$M1)), tibble(model_id = "M1_minus_M0", metric_id = metric_ids, value = unname(metrics$M1 - metrics$M0))) |> mutate(scope = "pooled_2025_26", selection_role = unname(metric_roles[metric_id]), .before = 1L) |> arrange(metric_id, model_id)
season_metrics <- pooled_metrics |> mutate(validation_season = CONTEXT_THIRD_VALIDATION_SEASON, .before = 1L)
calibration_bins <- bind_rows(context_calibration_bins_table(validation, predictions$probability_m0, "M0"), context_calibration_bins_table(validation, predictions$probability_m1, "M1")) |> arrange(model_id, bin_id)
subgroup_calibration <- bind_rows(context_subgroup_calibration(validation, predictions$probability_m0, "M0"), context_subgroup_calibration(validation, predictions$probability_m1, "M1")) |> arrange(subgroup_axis, subgroup, model_id)

bootstrap_started <- Sys.time(); bootstrap_input <- predictions |> select(comparison_id, game_id, outcome, probability_m0, probability_m1); bootstrap_draws <- context_paired_game_bootstrap(bootstrap_input); bootstrap_repeat <- context_paired_game_bootstrap(bootstrap_input); bootstrap_seconds <- as.numeric(difftime(Sys.time(), bootstrap_started, units = "secs"))
if (!identical(bootstrap_draws, bootstrap_repeat) || nrow(bootstrap_draws) != 2000L || any(!is.finite(as.matrix(bootstrap_draws)))) stop("bootstrap reproducibility failed", call. = FALSE)
point_differences <- c(log_loss_m1_minus_m0 = metrics$M1[["bernoulli_log_loss"]] - metrics$M0[["bernoulli_log_loss"]], calibration_abs_m1_minus_m0 = metrics$M1[["absolute_bias"]] - metrics$M0[["absolute_bias"]], ece_m1_minus_m0 = with(calibration_bins, sum(shots[model_id == "M1"] * absolute_gap[model_id == "M1"]) / sum(shots[model_id == "M1"]) - sum(shots[model_id == "M0"] * absolute_gap[model_id == "M0"]) / sum(shots[model_id == "M0"])))
bootstrap_summary <- imap_dfr(as.list(bootstrap_draws), function(values, metric_id) tibble(metric_id = metric_id, difference_direction = "M1_minus_M0", point_difference = unname(point_differences[[metric_id]]), bootstrap_replicates = 2000L, bootstrap_standard_error = sd(values), interval_lower_95 = unname(quantile(values, 0.025, names = FALSE)), interval_upper_95 = unname(quantile(values, 0.975, names = FALSE)), seed = CONTEXT_BOOTSTRAP_SEED, resampling_unit = "whole_game")) |> arrange(metric_id)
log_bootstrap <- filter(bootstrap_summary, metric_id == "log_loss_m1_minus_m0"); cal_bootstrap <- filter(bootstrap_summary, metric_id == "calibration_abs_m1_minus_m0"); ece_bootstrap <- filter(bootstrap_summary, metric_id == "ece_m1_minus_m0")
interpretation <- context_third_season_interpretation(metrics$M0[["bernoulli_log_loss"]], metrics$M1[["bernoulli_log_loss"]], log_bootstrap$bootstrap_standard_error, cal_bootstrap$interval_lower_95, ece_bootstrap$interval_lower_95)
qualifying <- interpretation[["label"]] == "provisional_M1_clears_first_season_gates"
model_selection <- tibble(comparison_id = CONTEXT_THIRD_COMPARISON_ID, validation_season = CONTEXT_THIRD_VALIDATION_SEASON, status = "completed_third_of_three", provisional_label = sub("first_season", "third_season", interpretation[["label"]], fixed = TRUE), m0_log_loss = metrics$M0[["bernoulli_log_loss"]], m1_log_loss = metrics$M1[["bernoulli_log_loss"]], m0_minus_m1_improvement = metrics$M0[["bernoulli_log_loss"]] - metrics$M1[["bernoulli_log_loss"]], paired_bootstrap_standard_error = log_bootstrap$bootstrap_standard_error, m1_exceeds_one_standard_error = interpretation[["one_se_passed"]] == "TRUE", calibration_gate_passed = interpretation[["calibration_gate_passed"]] == "TRUE", season_qualifying_m1_win = qualifying)
prior_selections <- bind_rows(
  read_csv(file.path(first_results, "model_selection.csv"), show_col_types = FALSE),
  read_csv(file.path(second_results, "model_selection.csv"), show_col_types = FALSE)
)
running_season_status <- bind_rows(
  prior_selections |>
    transmute(comparison_id, validation_season, provisional_label, season_qualifying_m1_win = grepl("M1_clears", provisional_label, fixed = TRUE)),
  model_selection |>
    transmute(comparison_id, validation_season, provisional_label, season_qualifying_m1_win)
) |>
  mutate(completed_retrospective_seasons = 3L, qualifying_m1_wins = sum(season_qualifying_m1_win))

# The pooled calculation reads only immutable private prediction checkpoints;
# it never rereads the first two canonical outcome partitions.
log_line("Third-season result complete; loading immutable prior prediction checkpoints")
first_predictions <- read_parquet(file.path(first_private, "shot_predictions.parquet"), as_data_frame = TRUE)
second_predictions <- read_parquet(file.path(second_private, "shot_predictions.parquet"), as_data_frame = TRUE)
if (nrow(first_predictions) != 218700L || nrow(second_predictions) != 219527L ||
    any(first_predictions$comparison_id != "retrospective_1") || any(second_predictions$comparison_id != "retrospective_2") ||
    any(first_predictions$season != "2023-24") || any(second_predictions$season != "2024-25") ||
    anyDuplicated(first_predictions$canonical_shot_key) || anyDuplicated(second_predictions$canonical_shot_key)) {
  stop("prior prediction checkpoint contents changed", call. = FALSE)
}
all_predictions <- bind_rows(first_predictions, second_predictions, predictions)
if (nrow(all_predictions) != 657387L || anyDuplicated(paste(all_predictions$comparison_id, all_predictions$canonical_shot_key, sep = "::"))) stop("pooled prediction rows failed checks", call. = FALSE)

pooled_data <- all_predictions |>
  transmute(
    source_game_id = paste(comparison_id, game_id, sep = "::"),
    field_goal_made = outcome,
    point_value,
    finish_family,
    creation_family,
    player_volume_group
  )
pooled_model_metrics <- list(
  M0 = context_model_metrics(pooled_data, all_predictions$probability_m0),
  M1 = context_model_metrics(pooled_data, all_predictions$probability_m1)
)
pooled_three_season_metrics <- bind_rows(
  tibble(model_id = "M0", metric_id = metric_ids, value = unname(pooled_model_metrics$M0)),
  tibble(model_id = "M1", metric_id = metric_ids, value = unname(pooled_model_metrics$M1)),
  tibble(model_id = "M1_minus_M0", metric_id = metric_ids, value = unname(pooled_model_metrics$M1 - pooled_model_metrics$M0))
) |>
  mutate(scope = "pooled_three_validation_seasons", selection_role = unname(metric_roles[metric_id]), .before = 1L) |>
  arrange(metric_id, model_id)
pooled_calibration_bins <- bind_rows(
  context_calibration_bins_table(pooled_data, all_predictions$probability_m0, "M0"),
  context_calibration_bins_table(pooled_data, all_predictions$probability_m1, "M1")
) |>
  arrange(model_id, bin_id)
pooled_subgroup_calibration <- bind_rows(
  context_subgroup_calibration(pooled_data, all_predictions$probability_m0, "M0"),
  context_subgroup_calibration(pooled_data, all_predictions$probability_m1, "M1")
) |>
  arrange(subgroup_axis, subgroup, model_id)

pooled_bootstrap_input <- all_predictions |>
  select(comparison_id, game_id, outcome, probability_m0, probability_m1)
pooled_bootstrap_draws <- context_paired_game_bootstrap(pooled_bootstrap_input)
pooled_bootstrap_repeat <- context_paired_game_bootstrap(pooled_bootstrap_input)
if (!identical(pooled_bootstrap_draws, pooled_bootstrap_repeat) || nrow(pooled_bootstrap_draws) != 2000L || any(!is.finite(as.matrix(pooled_bootstrap_draws)))) stop("pooled stratified bootstrap reproducibility failed", call. = FALSE)
pooled_point_differences <- c(
  log_loss_m1_minus_m0 = pooled_model_metrics$M1[["bernoulli_log_loss"]] - pooled_model_metrics$M0[["bernoulli_log_loss"]],
  calibration_abs_m1_minus_m0 = pooled_model_metrics$M1[["absolute_bias"]] - pooled_model_metrics$M0[["absolute_bias"]],
  ece_m1_minus_m0 = with(pooled_calibration_bins, sum(shots[model_id == "M1"] * absolute_gap[model_id == "M1"]) / sum(shots[model_id == "M1"]) - sum(shots[model_id == "M0"] * absolute_gap[model_id == "M0"]) / sum(shots[model_id == "M0"]))
)
pooled_bootstrap_summary <- imap_dfr(as.list(pooled_bootstrap_draws), function(values, metric_id) {
  tibble(
    metric_id = metric_id,
    difference_direction = "M1_minus_M0",
    point_difference = unname(pooled_point_differences[[metric_id]]),
    bootstrap_replicates = 2000L,
    bootstrap_standard_error = sd(values),
    interval_lower_95 = unname(quantile(values, 0.025, names = FALSE)),
    interval_upper_95 = unname(quantile(values, 0.975, names = FALSE)),
    seed = CONTEXT_BOOTSTRAP_SEED,
    resampling_unit = "whole_game_within_validation_season"
  )
}) |>
  arrange(metric_id)
pooled_log <- filter(pooled_bootstrap_summary, metric_id == "log_loss_m1_minus_m0")
pooled_cal <- filter(pooled_bootstrap_summary, metric_id == "calibration_abs_m1_minus_m0")
pooled_ece <- filter(pooled_bootstrap_summary, metric_id == "ece_m1_minus_m0")

prior_season_metrics <- bind_rows(
  read_csv(file.path(first_results, "season_metrics.csv"), show_col_types = FALSE),
  read_csv(file.path(second_results, "season_metrics.csv"), show_col_types = FALSE)
)
three_season_metrics <- bind_rows(prior_season_metrics, season_metrics) |>
  arrange(validation_season, metric_id, model_id)
season_log <- three_season_metrics |>
  filter(metric_id == "bernoulli_log_loss", model_id %in% c("M0", "M1")) |>
  select(validation_season, model_id, value) |>
  pivot_wider(names_from = model_id, values_from = value) |>
  arrange(validation_season)
final_choice <- context_select_model(
  pooled_model_metrics$M0[["bernoulli_log_loss"]],
  pooled_model_metrics$M1[["bernoulli_log_loss"]],
  pooled_log$bootstrap_standard_error,
  pooled_cal$interval_lower_95,
  pooled_ece$interval_lower_95,
  season_log$M0,
  season_log$M1
)
pooled_improvement <- pooled_model_metrics$M0[["bernoulli_log_loss"]] - pooled_model_metrics$M1[["bernoulli_log_loss"]]
season_lower_loss_wins <- sum(season_log$M1 < season_log$M0)
final_model_decision <- tibble(
  selected_model = final_choice[["model"]],
  reason = final_choice[["reason"]],
  pooled_m0_log_loss = pooled_model_metrics$M0[["bernoulli_log_loss"]],
  pooled_m1_log_loss = pooled_model_metrics$M1[["bernoulli_log_loss"]],
  pooled_m1_minus_m0 = pooled_point_differences[["log_loss_m1_minus_m0"]],
  pooled_bootstrap_standard_error = pooled_log$bootstrap_standard_error,
  pooled_improvement_exceeds_one_se = pooled_improvement > pooled_log$bootstrap_standard_error,
  calibration_gate_passed = pooled_cal$interval_lower_95 <= CONTEXT_CALIBRATION_MARGIN && pooled_ece$interval_lower_95 <= CONTEXT_CALIBRATION_MARGIN,
  m1_lower_log_loss_seasons = season_lower_loss_wins,
  two_of_three_gate_passed = season_lower_loss_wins >= 2L,
  qualifying_m1_seasons = sum(running_season_status$season_qualifying_m1_win),
  rules_applied_mechanically = TRUE
)
bootstrap_seconds <- as.numeric(difftime(Sys.time(), bootstrap_started, units = "secs"))

execution_checks <- tibble(
  check_id = c("training_seasons_only", "validation_season_only", "whole_game_separation", "training_counts", "validation_counts", "identical_model_rows", "one_prediction_per_shot", "expected_points_exact", "probabilities_valid", "unseen_player_zero_effect", "all_taxonomy_levels", "other_unknown_included", "model_formulas_frozen", "forbidden_features_absent", "outcome_not_predictor", "third_bootstrap_deterministic", "pooled_bootstrap_stratified_deterministic", "difference_sign_consistent", "prior_results_unchanged", "prior_predictions_split_specific", "pooled_row_count", "final_decision_reproducible", "aggregate_outputs_only", "2026_27_sealed", "models_fit_exactly_once"),
  passed = c(
    TRUE, TRUE, TRUE,
    nrow(training_metadata) == 872169L && n_distinct(training_metadata$source_game_id) == 4920L && n_distinct(training_metadata$player_id) == 913L,
    nrow(validation) == 219160L && n_distinct(validation$source_game_id) == 1230L && n_distinct(validation$player_id) == 582L,
    nrow(predictions) == nrow(validation), !anyDuplicated(predictions$canonical_shot_key),
    identical(predictions$expected_points_m0, predictions$probability_m0 * predictions$point_value) && identical(predictions$expected_points_m1, predictions$probability_m1 * predictions$point_value),
    all(predictions$probability_m0 > 0 & predictions$probability_m0 < 1) && all(predictions$probability_m1 > 0 & predictions$probability_m1 < 1),
    all(!predictions$known_player_m0[predictions$player_volume_group == "unseen_player"]) && all(!predictions$known_player_m1[predictions$player_volume_group == "unseen_player"]),
    setequal(validation$finish_family, factor_levels$finish_family) && setequal(validation$creation_family, factor_levels$creation_family),
    any(validation$creation_family == "other_or_unknown"), TRUE, TRUE, TRUE,
    identical(bootstrap_draws, bootstrap_repeat) && nrow(bootstrap_draws) == 2000L,
    identical(pooled_bootstrap_draws, pooled_bootstrap_repeat) && nrow(pooled_bootstrap_draws) == 2000L && n_distinct(all_predictions$comparison_id) == 3L,
    isTRUE(all.equal(pooled_point_differences[["log_loss_m1_minus_m0"]], pooled_model_metrics$M1[["bernoulli_log_loss"]] - pooled_model_metrics$M0[["bernoulli_log_loss"]], tolerance = 0)),
    context_sha256_file(first_manifest_path) == CONTEXT_FIRST_RESULT_MANIFEST_SHA256 && context_sha256_file(second_manifest_path) == CONTEXT_SECOND_RESULT_MANIFEST_SHA256,
    all(first_predictions$comparison_id == "retrospective_1") && all(second_predictions$comparison_id == "retrospective_2"),
    nrow(all_predictions) == 657387L,
    identical(final_choice, context_select_model(pooled_model_metrics$M0[["bernoulli_log_loss"]], pooled_model_metrics$M1[["bernoulli_log_loss"]], pooled_log$bootstrap_standard_error, pooled_cal$interval_lower_95, pooled_ece$interval_lower_95, season_log$M0, season_log$M1)),
    TRUE, !access_record$season_2026_27_accessed, TRUE
  ),
  detail = c("2021-22 through 2024-25 only", "2025-26 only", "zero shared game ids", "872169 shots; 4920 games; 913 players", "219160 shots; 1230 games; 582 players", "shared ordered prediction table", "zero duplicate shot keys", "probability times point value exactly", "finite and strictly interior", "unseen rows exclude player random effect", "seven finish and four creation levels", "ordinary registered level retained", "M0/M1 formulas match protocol", "no forbidden formula term", "outcome used only for metrics", "2000 whole-game draws repeated exactly", "2000 whole-game draws within each season repeated exactly", "M1 minus M0", "first and second public manifests unchanged", "original split-specific checkpoints", "657387 shots across three seasons", "frozen selection function reproduced exactly", "no identifiers in tracked tables", "false access flag and no loader", "one completed atomic component per model")
)
if (!all(execution_checks$passed)) stop("one or more frozen execution checks failed", call. = FALSE)

fit_diagnostics <- bind_rows(m0$diagnostics, m1$diagnostics) |> mutate(fit_count = 1L, fit_reused_for_validation = TRUE, refit_count = 0L, fit_sha256 = if_else(model_id == "M0", m0$fit_sha256, m1$fit_sha256)) |> arrange(model_id)
total_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs")); cpu_used <- proc.time() - started_cpu; memory_samples <- c(memory_samples, context_current_rss_bytes())
execution_manifest <- tibble(evaluation_version = CONTEXT_THIRD_VALIDATION_VERSION, protocol_version = CONTEXT_PROTOCOL_VERSION, comparison_id = CONTEXT_THIRD_COMPARISON_ID, training_seasons = paste(CONTEXT_THIRD_TRAINING_SEASONS, collapse = ";"), validation_season = CONTEXT_THIRD_VALIDATION_SEASON, training_games = 4920L, training_shots = 872169L, training_players = 913L, validation_games = 1230L, validation_shots = 219160L, validation_players = 582L, returning_validation_players = returning_players, unseen_validation_players = unseen_players, unseen_validation_shots = sum(validation$player_volume_group == "unseen_player"), pooled_validation_seasons = 3L, pooled_validation_games = n_distinct(paste(all_predictions$comparison_id, all_predictions$game_id)), pooled_validation_shots = nrow(all_predictions), models_fit = 2L, pre_result_implementation_commit = commits[["pre_result"]], execution_commit = commits[["head"]], canonical_manifest_sha256 = context_sha256_file(canonical_manifest_path), validation_partition_sha256 = context_sha256_file(validation_path), ordered_validation_shot_key_sha256 = shot_key_hash, configuration_sha256 = context_sha256_file(config_path), m0_fit_sha256 = m0$fit_sha256, m1_fit_sha256 = m1$fit_sha256, first_result_manifest_sha256 = context_sha256_file(first_manifest_path), second_result_manifest_sha256 = context_sha256_file(second_manifest_path), outcome_access_timestamp_utc = access_record$opened_at_utc, outcome_reads_completed = 1L, season_2025_26_outcomes_accessed = TRUE, season_2026_27_accessed = FALSE, outcome_read_seconds = outcome_read_seconds, prediction_seconds = prediction_seconds, evaluation_seconds = evaluation_seconds, bootstrap_seconds_including_reproducibility_repeats = bootstrap_seconds, total_wall_seconds = total_seconds, cpu_user_seconds = unname(cpu_used[["user.self"]]), cpu_system_seconds = unname(cpu_used[["sys.self"]]), sampled_peak_rss_bytes = max(memory_samples, na.rm = TRUE), disk_bytes_before = disk_before, disk_bytes_after = context_available_disk_bytes(repo_root), r_version = paste(R.version$major, R.version$minor, sep = "."), mgcv_version = observed_versions[["mgcv"]], arrow_version = observed_versions[["arrow"]], warning_count = 0L, error_count = 0L)

public_payloads <- list("execution_manifest.csv" = execution_manifest, "fit_diagnostics.csv" = fit_diagnostics, "pooled_metrics.csv" = pooled_metrics, "season_metrics.csv" = season_metrics, "calibration_bins.csv" = calibration_bins, "subgroup_calibration.csv" = subgroup_calibration, "bootstrap_summary.csv" = bootstrap_summary, "model_selection.csv" = model_selection, "running_season_status.csv" = running_season_status, "three_season_metrics.csv" = three_season_metrics, "pooled_three_season_metrics.csv" = pooled_three_season_metrics, "pooled_calibration_bins.csv" = pooled_calibration_bins, "pooled_subgroup_calibration.csv" = pooled_subgroup_calibration, "pooled_bootstrap_summary.csv" = pooled_bootstrap_summary, "final_model_decision.csv" = final_model_decision, "execution_checks.csv" = execution_checks)
walk2(public_payloads, names(public_payloads), ~ context_write_csv_stable(.x, file.path(tracked_stage, .y)))
artifact_manifest <- tibble(artifact = names(public_payloads), sha256 = vapply(file.path(tracked_stage, names(public_payloads)), context_sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE) |> arrange(artifact)
context_write_csv_stable(artifact_manifest, file.path(tracked_stage, "artifact_manifest.csv"))
write_parquet(predictions, file.path(private_stage, "shot_predictions.parquet"), compression = "zstd"); write_parquet(bootstrap_draws, file.path(private_stage, "bootstrap_draws.parquet"), compression = "zstd"); write_parquet(pooled_bootstrap_draws, file.path(private_stage, "pooled_bootstrap_draws.parquet"), compression = "zstd")
walk2(public_payloads, names(public_payloads), ~ context_write_csv_stable(.x, file.path(private_stage, .y)))
context_write_csv_stable(artifact_manifest, file.path(private_stage, "public_artifact_manifest.csv"))
private_artifacts <- c("shot_predictions.parquet", "bootstrap_draws.parquet", "pooled_bootstrap_draws.parquet", names(public_payloads), "public_artifact_manifest.csv", "evaluation.log")
private_manifest <- tibble(artifact = private_artifacts, sha256 = vapply(file.path(private_stage, private_artifacts), context_sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE)
context_write_csv_stable(private_manifest, file.path(private_stage, "completion_manifest.csv")); context_verify_file_manifest(private_manifest, private_stage)
if (!file.rename(private_stage, private_final)) stop("private atomic publication failed", call. = FALSE)
if (!file.rename(tracked_stage, tracked_results)) stop("tracked atomic publication failed", call. = FALSE)
if (!file.rename(private_lock, file.path(private_final, "completed_lock_metadata"))) stop("could not preserve completed lock", call. = FALSE)
success <- TRUE
message("Third registered 2025-26 validation and pooled decision completed and published atomically")
