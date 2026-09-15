#!/usr/bin/env Rscript

# Evaluate the frozen M0/M1 fits on the first registered future season.
# `audit` reads validation metadata only. `run` creates an exclusive access
# marker and then performs the script's single validation-outcome read.

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
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_first_validation.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) == 0L) "audit" else args[[1]]
if (!mode %in% c("audit", "run", "verify")) stop("mode must be audit, run, or verify", call. = FALSE)

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)

canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
validation_path <- file.path(canonical_root, "season=2023-24", "canonical_shots.parquet")
preflight_root <- file.path(
  repo_root, "data", "cache", "context_edition_m0_m1_preflight",
  "context_m0_m1_preflight_v0.1.0"
)
private_parent <- file.path(repo_root, "data", "cache", "context_edition_first_validation")
private_pre_result <- file.path(private_parent, "pre_result_v0.1.0")
private_final <- file.path(private_parent, "retrospective_1_v0.1.0")
private_lock <- file.path(private_parent, ".retrospective_1_v0.1.0.lock")
access_marker <- file.path(private_parent, ".retrospective_1_v0.1.0.accessed")
tracked_parent <- file.path(repo_root, "data", "processed", "context_edition_first_validation_v0_1")
tracked_results <- file.path(tracked_parent, "results")
config_path <- file.path(repo_root, "config", "context_edition_first_validation_v0_1.csv")

config <- read_csv(config_path, show_col_types = FALSE)
config_values <- setNames(config$value, config$key)
expected_config <- c(
  evaluation_version = CONTEXT_FIRST_VALIDATION_VERSION,
  protocol_version = CONTEXT_PROTOCOL_VERSION,
  comparison_id = CONTEXT_FIRST_COMPARISON_ID,
  training_seasons = paste(CONTEXT_FIRST_TRAINING_SEASONS, collapse = ";"),
  validation_season = CONTEXT_FIRST_VALIDATION_SEASON,
  later_seasons_analytically_sealed = "2024-25;2025-26;2026-27",
  primary_metric = "pooled_shot_level_bernoulli_log_loss",
  primary_difference_sign = "M1_minus_M0",
  bootstrap_unit = "whole_game",
  bootstrap_interval = "percentile_95"
)
if (!all(config_values[names(expected_config)] == expected_config)) stop("first-validation configuration changed", call. = FALSE)
if (as.numeric(config_values[["probability_clip"]]) != CONTEXT_LOG_CLIP ||
    as.integer(config_values[["bootstrap_replicates"]]) != CONTEXT_BOOTSTRAP_REPLICATES ||
    as.integer(config_values[["bootstrap_seed"]]) != CONTEXT_BOOTSTRAP_SEED ||
    as.numeric(config_values[["material_calibration_margin"]]) != CONTEXT_CALIBRATION_MARGIN ||
    as.integer(config_values[["calibration_bins"]]) != CONTEXT_CALIBRATION_BINS ||
    as.integer(config_values[["minimum_subgroup_shots"]]) != CONTEXT_MIN_SUBGROUP_SHOTS) {
  stop("numeric evaluation settings changed", call. = FALSE)
}
if (any(config_values[c("models_may_be_refit", "validation_model_updates_allowed", "public_shot_rows")] != "FALSE")) {
  stop("a protected evaluation setting is not false", call. = FALSE)
}

required_versions <- c(
  mgcv = "1.9.4", Matrix = "1.7.5", arrow = "25.0.0",
  dplyr = "1.2.1", tidyr = "1.3.2", readr = "2.2.0"
)
observed_versions <- vapply(names(required_versions), function(package) {
  if (!requireNamespace(package, quietly = TRUE)) stop(package, " is not installed", call. = FALSE)
  as.character(utils::packageVersion(package))
}, character(1))
if (!identical(unname(observed_versions), unname(required_versions))) stop("package versions differ from the frozen protocol", call. = FALSE)
if (paste(R.version$major, R.version$minor, sep = ".") != "4.6.0") stop("R version differs from frozen 4.6.0", call. = FALSE)

canonical_manifest_path <- file.path(canonical_root, "completion_manifest.csv")
canonical_manifest <- read_csv(canonical_manifest_path, show_col_types = FALSE)
context_verify_file_manifest(canonical_manifest, canonical_root)
if (context_sha256_file(canonical_manifest_path) != config_values[["canonical_manifest_sha256"]]) {
  stop("canonical completion manifest hash changed", call. = FALSE)
}
if (any(canonical_manifest$validation_outcomes_analytically_accessed)) stop("canonical checkpoint records prior analytical validation access", call. = FALSE)

preflight_manifest_path <- file.path(preflight_root, "completion_manifest.csv")
preflight_manifest <- read_csv(preflight_manifest_path, show_col_types = FALSE)
context_verify_file_manifest(preflight_manifest, preflight_root)
fit_paths <- setNames(file.path(preflight_root, c("m0_fit.rds", "m1_fit.rds")), c("M0", "M1"))
fit_hashes <- vapply(fit_paths, context_sha256_file, character(1))
if (fit_hashes[["M0"]] != config_values[["m0_fit_sha256"]] ||
    fit_hashes[["M1"]] != config_values[["m1_fit_sha256"]]) stop("frozen fit hash changed", call. = FALSE)
if (any(preflight_manifest$validation_outcomes_accessed)) stop("preflight fit manifest records validation access", call. = FALSE)

metadata_fields <- c(
  "season", "canonical_shot_key", "source_game_id", "player_id",
  "point_value", "finish_family", "creation_family"
)
validation_metadata_path <- validation_path
validation_metadata <- read_parquet(
  validation_metadata_path,
  col_select = all_of(metadata_fields),
  as_data_frame = TRUE
) |>
  arrange(canonical_shot_key)
if (nrow(validation_metadata) != 218700L || n_distinct(validation_metadata$source_game_id) != 1230L ||
    n_distinct(validation_metadata$player_id) != 568L || anyDuplicated(validation_metadata$canonical_shot_key)) {
  stop("outcome-free validation population differs from the canonical manifest", call. = FALSE)
}
if (!identical(unique(validation_metadata$season), "2023-24")) stop("validation metadata contains the wrong season", call. = FALSE)
if (context_sha256_file(validation_path) != config_values[["validation_partition_sha256"]]) stop("validation partition hash changed", call. = FALSE)

shot_key_hash <- context_hash_values(validation_metadata$canonical_shot_key)
game_key_hash <- context_hash_values(sort(unique(as.character(validation_metadata$source_game_id))))
player_key_hash <- context_hash_values(sort(unique(as.character(validation_metadata$player_id))))
population_manifest <- tibble(
  evaluation_version = CONTEXT_FIRST_VALIDATION_VERSION,
  comparison_id = CONTEXT_FIRST_COMPARISON_ID,
  validation_season = CONTEXT_FIRST_VALIDATION_SEASON,
  games = n_distinct(validation_metadata$source_game_id),
  shots = nrow(validation_metadata),
  players = n_distinct(validation_metadata$player_id),
  canonical_partition_sha256 = context_sha256_file(validation_path),
  ordered_shot_key_sha256 = shot_key_hash,
  sorted_game_key_sha256 = game_key_hash,
  sorted_player_key_sha256 = player_key_hash,
  validation_outcomes_accessed = FALSE,
  later_seasons_outcomes_accessed = FALSE
)

formulas <- context_model_formulas()
fits <- lapply(fit_paths, readRDS)
for (model_id in names(fits)) {
  fit <- fits[[model_id]]
  expected_formula <- gsub("[[:space:]]+", "", paste(deparse(formulas[[model_id]]), collapse = ""))
  observed_formula <- gsub("[[:space:]]+", "", paste(deparse(stats::formula(fit)), collapse = ""))
  if (!inherits(fit, "gam") || !isTRUE(fit$converged) || expected_formula != observed_formula ||
      length(fit$sp) != 1L || any(!is.finite(stats::coef(fit))) || any(!is.finite(fit$Vp))) {
    stop(model_id, " is not the frozen completed fit", call. = FALSE)
  }
}

pre_result_checks <- tibble(
  check_id = c(
    "canonical_manifest_hashes", "preflight_manifest_hashes", "fit_hashes",
    "fit_formulas", "fit_convergence", "fit_training_only", "validation_population",
    "validation_unique_keys", "validation_taxonomy_levels", "later_seasons_sealed",
    "no_existing_access_marker", "no_existing_result"
  ),
  passed = c(
    TRUE, TRUE, TRUE, TRUE, TRUE, all(!preflight_manifest$validation_outcomes_accessed),
    nrow(validation_metadata) == 218700L && n_distinct(validation_metadata$source_game_id) == 1230L,
    !anyDuplicated(validation_metadata$canonical_shot_key),
    setequal(validation_metadata$finish_family, context_factor_levels()$finish_family) &&
      setequal(validation_metadata$creation_family, context_factor_levels()$creation_family),
    TRUE, !dir.exists(access_marker), !dir.exists(private_final) && !dir.exists(tracked_results)
  ),
  detail = c(
    "seven private canonical payload hashes matched", "two private fit hashes matched",
    paste(names(fit_hashes), fit_hashes, collapse = ";"),
    "M0 and M1 formulas match protocol v0.1.0", "both preflight fits converged",
    "fit manifest validation_outcomes_accessed is false", "218700 shots; 1230 whole games; 568 players",
    "zero duplicated canonical shot keys", "all seven finish and four creation levels present",
    "2024-25, 2025-26, and 2026-27 have no runner input path", "no prior marker", "no prior result"
  )
)

output_schema <- tibble(
  artifact = c(
    "execution_manifest.csv", "fit_diagnostics.csv", "pooled_metrics.csv",
    "season_metrics.csv", "calibration_bins.csv", "subgroup_calibration.csv",
    "bootstrap_summary.csv", "model_selection.csv", "execution_checks.csv",
    "artifact_manifest.csv"
  ),
  public_granularity = c(
    "one evaluation row", "one row per model", "metric by model and paired difference",
    "season-metric by model and paired difference", "model by calibration bin",
    "model by registered aggregate subgroup", "three aggregate paired-bootstrap rows",
    "one provisional season record", "aggregate pass-fail rows", "one row per public artifact"
  ),
  contains_shot_rows = FALSE,
  contains_identifiers = FALSE
)

if (mode == "audit") {
  if (dir.exists(access_marker) || dir.exists(private_final) || dir.exists(tracked_results)) {
    stop("a prior access marker or result exists; audit will not overwrite it", call. = FALSE)
  }
  dir.create(private_parent, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(private_pre_result)) {
    stage <- paste0(private_pre_result, ".partial")
    if (dir.exists(stage)) stop("partial pre-result manifest exists", call. = FALSE)
    dir.create(stage, recursive = TRUE)
    context_write_csv_stable(population_manifest, file.path(stage, "validation_population_manifest.csv"))
    context_write_csv_stable(pre_result_checks, file.path(stage, "pre_result_checks.csv"))
    private_manifest <- tibble(
      artifact = c("validation_population_manifest.csv", "pre_result_checks.csv"),
      sha256 = vapply(file.path(stage, c("validation_population_manifest.csv", "pre_result_checks.csv")), context_sha256_file, character(1)),
      atomic_complete = TRUE,
      checks_passed = TRUE
    )
    context_write_csv_stable(private_manifest, file.path(stage, "completion_manifest.csv"))
    if (!file.rename(stage, private_pre_result)) stop("could not publish private pre-result manifest", call. = FALSE)
  } else {
    manifest <- read_csv(file.path(private_pre_result, "completion_manifest.csv"), show_col_types = FALSE)
    context_verify_file_manifest(manifest, private_pre_result)
    saved_population <- read_csv(file.path(private_pre_result, "validation_population_manifest.csv"), show_col_types = FALSE)
    if (!identical(saved_population, population_manifest)) stop("saved validation population changed", call. = FALSE)
  }
  dir.create(tracked_parent, recursive = TRUE, showWarnings = FALSE)
  context_atomic_write_csv(population_manifest, file.path(tracked_parent, "outcome_free_population_manifest.csv"))
  context_atomic_write_csv(pre_result_checks, file.path(tracked_parent, "pre_result_checks.csv"))
  context_atomic_write_csv(output_schema, file.path(tracked_parent, "output_schema.csv"))
  message("Outcome-free first-validation audit passed; no validation outcome was read")
  quit(save = "no", status = 0L)
}

if (mode == "verify") {
  if (!dir.exists(private_final) || !dir.exists(tracked_results)) stop("completed result is missing", call. = FALSE)
  private_manifest <- read_csv(file.path(private_final, "completion_manifest.csv"), show_col_types = FALSE)
  tracked_manifest <- read_csv(file.path(tracked_results, "artifact_manifest.csv"), show_col_types = FALSE)
  context_verify_file_manifest(private_manifest, private_final)
  context_verify_file_manifest(tracked_manifest, tracked_results)
  message("Completed first-validation result verified without loading outcomes or refitting")
  quit(save = "no", status = 0L)
}

pre_result_commit <- config_values[["pre_result_implementation_commit"]]
if (!grepl("^[0-9a-f]{40}$", pre_result_commit)) stop("pre-result implementation commit is not frozen", call. = FALSE)
head_commit <- context_git_value(repo_root, c("rev-parse", "HEAD"))
upstream_commit <- context_git_value(repo_root, c("rev-parse", "@{upstream}"))
if (head_commit != upstream_commit) stop("local and remote commits differ", call. = FALSE)
ancestor_status <- system2("git", c("-C", repo_root, "merge-base", "--is-ancestor", pre_result_commit, "HEAD"))
if (ancestor_status != 0L) stop("recorded pre-result commit is not in current history", call. = FALSE)
if (system2("git", c("-C", repo_root, "diff", "--quiet")) != 0L ||
    system2("git", c("-C", repo_root, "diff", "--cached", "--quiet")) != 0L) {
  stop("tracked worktree must be clean before outcome access", call. = FALSE)
}
status_lines <- system2("git", c("-C", repo_root, "status", "--porcelain"), stdout = TRUE)
unexpected_untracked <- status_lines[startsWith(status_lines, "?? ") & status_lines != "?? skill-observations/"]
if (length(unexpected_untracked) > 0L) stop("unexpected untracked files exist before outcome access", call. = FALSE)
if (!dir.exists(private_pre_result)) stop("private outcome-free manifest is missing", call. = FALSE)
context_verify_file_manifest(
  read_csv(file.path(private_pre_result, "completion_manifest.csv"), show_col_types = FALSE),
  private_pre_result
)
if (dir.exists(private_final) || dir.exists(tracked_results)) stop("completed result already exists; use verify", call. = FALSE)
if (dir.exists(access_marker)) stop("2023-24 outcome access was already marked; fresh execution is prohibited", call. = FALSE)
if (dir.exists(private_lock)) stop("evaluation lock exists; verify its process before recovery", call. = FALSE)
if (!dir.create(private_lock, recursive = TRUE)) stop("could not acquire evaluation lock", call. = FALSE)

attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
private_stage <- file.path(private_parent, paste0(".retrospective_1-", attempt_id, ".partial"))
tracked_stage <- file.path(dirname(tracked_results), paste0(".results-", attempt_id, ".partial"))
dir.create(private_stage, recursive = TRUE)
dir.create(tracked_stage, recursive = TRUE)
log_path <- file.path(private_stage, "evaluation.log")
success <- FALSE
started_wall <- Sys.time()
started_cpu <- proc.time()
memory_samples <- context_current_rss_bytes()
disk_before <- context_available_disk_bytes(repo_root)
if (disk_before < 2 * 1024^3) stop("less than 2 GiB free disk", call. = FALSE)

writeLines(c(
  paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id),
  paste0("started_at_utc=", format(started_wall, tz = "UTC", usetz = TRUE)),
  "stage=pre_outcome_checks", "validation_outcomes_accessed=false",
  "later_seasons_outcomes_accessed=false"
), file.path(private_lock, "metadata.txt"))

on.exit({
  if (!success && dir.exists(private_stage)) {
    writeLines(c(
      paste0("attempt_id=", attempt_id),
      paste0("ended_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      "status=failed_or_interrupted", paste0("access_marker_exists=", dir.exists(access_marker)),
      "no_statistical_rule_changed=true"
    ), file.path(private_stage, "failure_or_interruption.txt"))
  }
}, add = TRUE)

log_line <- function(...) {
  line <- paste0(format(Sys.time(), tz = "UTC", usetz = TRUE), " ", paste0(..., collapse = ""))
  cat(line, "\n", file = log_path, append = TRUE)
  message(line)
}

log_line("Pre-outcome checks passed; publishing exclusive access marker")
if (!dir.create(access_marker)) stop("could not create exclusive outcome-access marker", call. = FALSE)
access_record <- tibble(
  evaluation_version = CONTEXT_FIRST_VALIDATION_VERSION,
  comparison_id = CONTEXT_FIRST_COMPARISON_ID,
  validation_season = CONTEXT_FIRST_VALIDATION_SEASON,
  opened_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  pid = Sys.getpid(),
  code_commit = head_commit,
  pre_result_implementation_commit = pre_result_commit,
  canonical_manifest_sha256 = context_sha256_file(canonical_manifest_path),
  validation_partition_sha256 = context_sha256_file(validation_path),
  configuration_sha256 = context_sha256_file(config_path),
  m0_fit_sha256 = fit_hashes[["M0"]],
  m1_fit_sha256 = fit_hashes[["M1"]],
  outcome_read_authorized = TRUE,
  outcome_read_count_allowed = 1L,
  later_seasons_outcomes_accessed = FALSE
)
context_atomic_write_csv(access_record, file.path(access_marker, "access_marker.csv"))

writeLines(c(
  paste0("pid=", Sys.getpid()), paste0("attempt_id=", attempt_id),
  paste0("updated_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "stage=loading_2023_24_outcomes_once", "validation_outcomes_accessed=true",
  "later_seasons_outcomes_accessed=false"
), file.path(private_lock, "metadata.txt"))

outcome_read_started <- Sys.time()
validation <- read_parquet(validation_path, col_select = all_of(c(metadata_fields, "field_goal_made")), as_data_frame = TRUE) |>
  arrange(canonical_shot_key)
outcome_read_seconds <- as.numeric(difftime(Sys.time(), outcome_read_started, units = "secs"))
context_atomic_write_csv(
  tibble(completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), outcome_reads_completed = 1L),
  file.path(access_marker, "outcome_read_completed.csv")
)
if (nrow(validation) != nrow(validation_metadata) ||
    context_hash_values(validation$canonical_shot_key) != shot_key_hash ||
    any(!validation$field_goal_made %in% c(0L, 1L)) || anyNA(validation$field_goal_made)) {
  stop("single outcome read does not match the frozen population", call. = FALSE)
}

training_metadata <- map_dfr(CONTEXT_FIRST_TRAINING_SEASONS, function(season_value) {
  path <- file.path(canonical_root, paste0("season=", season_value), "canonical_shots.parquet")
  read_parquet(path, col_select = c("season", "source_game_id", "player_id"), as_data_frame = TRUE)
})
if (!identical(sort(unique(training_metadata$season)), CONTEXT_FIRST_TRAINING_SEASONS) ||
    nrow(training_metadata) != 433942L) stop("training metadata changed", call. = FALSE)
if (length(intersect(as.character(training_metadata$source_game_id), as.character(validation$source_game_id))) > 0L) {
  stop("a game identifier overlaps training and validation", call. = FALSE)
}
volume_groups <- context_training_volume_groups(training_metadata)
validation <- validation |>
  left_join(volume_groups, by = "player_id", relationship = "many-to-one") |>
  mutate(
    player_volume_group = if_else(is.na(player_volume_group), "unseen_player", player_volume_group),
    comparison_id = CONTEXT_FIRST_COMPARISON_ID
  )
returning_players <- n_distinct(validation$player_id[validation$player_volume_group != "unseen_player"])
unseen_players <- n_distinct(validation$player_id[validation$player_volume_group == "unseen_player"])

prediction_started <- Sys.time()
m0_prediction <- context_predict_first_validation(fits$M0, validation)
m1_prediction <- context_predict_first_validation(fits$M1, validation)
prediction_seconds <- as.numeric(difftime(Sys.time(), prediction_started, units = "secs"))
memory_samples <- c(memory_samples, context_current_rss_bytes())
predictions <- validation |>
  transmute(
    comparison_id, season, canonical_shot_key,
    game_id = as.character(source_game_id), player_id,
    point_value, finish_family, creation_family, player_volume_group,
    outcome = field_goal_made,
    probability_m0 = m0_prediction$probability,
    probability_m1 = m1_prediction$probability,
    expected_points_m0 = context_expected_points(probability_m0, point_value),
    expected_points_m1 = context_expected_points(probability_m1, point_value),
    known_player_m0 = m0_prediction$known_player,
    known_player_m1 = m1_prediction$known_player
  )
if (anyNA(predictions) || any(!is.finite(predictions$probability_m0)) || any(!is.finite(predictions$probability_m1)) ||
    any(predictions$probability_m0 <= 0 | predictions$probability_m0 >= 1) ||
    any(predictions$probability_m1 <= 0 | predictions$probability_m1 >= 1) ||
    !identical(predictions$expected_points_m0, predictions$probability_m0 * predictions$point_value) ||
    !identical(predictions$expected_points_m1, predictions$probability_m1 * predictions$point_value)) {
  stop("prediction integrity check failed", call. = FALSE)
}

evaluation_started <- Sys.time()
metrics <- list(
  M0 = context_model_metrics(validation, predictions$probability_m0),
  M1 = context_model_metrics(validation, predictions$probability_m1)
)
metric_ids <- names(metrics$M0)
metric_roles <- c(
  bernoulli_log_loss = "primary", brier_score = "diagnostic", roc_auc = "diagnostic",
  expected_points_rmse = "secondary", game_points_mae = "secondary",
  game_points_rmse = "secondary", points_bias_per_100 = "diagnostic",
  predicted_rate = "calibration", observed_rate = "calibration",
  signed_bias_observed_minus_predicted = "calibration", absolute_bias = "calibration_gate",
  calibration_intercept = "calibration", calibration_intercept_estimable = "check",
  calibration_slope = "calibration", calibration_slope_estimable = "check"
)
pooled_metrics <- bind_rows(
  tibble(model_id = "M0", metric_id = metric_ids, value = unname(metrics$M0)),
  tibble(model_id = "M1", metric_id = metric_ids, value = unname(metrics$M1)),
  tibble(model_id = "M1_minus_M0", metric_id = metric_ids, value = unname(metrics$M1 - metrics$M0))
) |>
  mutate(scope = "pooled_2023_24", selection_role = unname(metric_roles[metric_id]), .before = 1L) |>
  arrange(metric_id, model_id)
season_metrics <- pooled_metrics |>
  mutate(validation_season = CONTEXT_FIRST_VALIDATION_SEASON, .before = 1L)
calibration_bins <- bind_rows(
  context_calibration_bins_table(validation, predictions$probability_m0, "M0"),
  context_calibration_bins_table(validation, predictions$probability_m1, "M1")
) |>
  arrange(model_id, bin_id)
subgroup_calibration <- bind_rows(
  context_subgroup_calibration(validation, predictions$probability_m0, "M0"),
  context_subgroup_calibration(validation, predictions$probability_m1, "M1")
) |>
  arrange(subgroup_axis, subgroup, model_id)
evaluation_seconds <- as.numeric(difftime(Sys.time(), evaluation_started, units = "secs"))

bootstrap_input <- predictions |>
  select(comparison_id, game_id, outcome, probability_m0, probability_m1)
bootstrap_started <- Sys.time()
bootstrap_draws <- context_paired_game_bootstrap(
  bootstrap_input, replicates = CONTEXT_BOOTSTRAP_REPLICATES, seed = CONTEXT_BOOTSTRAP_SEED
)
bootstrap_repeat <- context_paired_game_bootstrap(
  bootstrap_input, replicates = CONTEXT_BOOTSTRAP_REPLICATES, seed = CONTEXT_BOOTSTRAP_SEED
)
bootstrap_seconds <- as.numeric(difftime(Sys.time(), bootstrap_started, units = "secs"))
if (!identical(bootstrap_draws, bootstrap_repeat) || nrow(bootstrap_draws) != 2000L || any(!is.finite(as.matrix(bootstrap_draws)))) {
  stop("paired whole-game bootstrap reproducibility failed", call. = FALSE)
}
memory_samples <- c(memory_samples, context_current_rss_bytes())

point_differences <- c(
  log_loss_m1_minus_m0 = metrics$M1[["bernoulli_log_loss"]] - metrics$M0[["bernoulli_log_loss"]],
  calibration_abs_m1_minus_m0 = metrics$M1[["absolute_bias"]] - metrics$M0[["absolute_bias"]],
  ece_m1_minus_m0 = with(
    calibration_bins,
    sum(shots[model_id == "M1"] * absolute_gap[model_id == "M1"]) / sum(shots[model_id == "M1"]) -
      sum(shots[model_id == "M0"] * absolute_gap[model_id == "M0"]) / sum(shots[model_id == "M0"])
  )
)
bootstrap_summary <- imap_dfr(as.list(bootstrap_draws), function(values, metric_id) {
  tibble(
    metric_id = metric_id,
    difference_direction = "M1_minus_M0",
    point_difference = unname(point_differences[[metric_id]]),
    bootstrap_replicates = nrow(bootstrap_draws),
    bootstrap_standard_error = stats::sd(values),
    interval_lower_95 = unname(stats::quantile(values, 0.025, names = FALSE)),
    interval_upper_95 = unname(stats::quantile(values, 0.975, names = FALSE)),
    seed = CONTEXT_BOOTSTRAP_SEED,
    resampling_unit = "whole_game"
  )
}) |>
  arrange(metric_id)
log_bootstrap <- filter(bootstrap_summary, metric_id == "log_loss_m1_minus_m0")
cal_bootstrap <- filter(bootstrap_summary, metric_id == "calibration_abs_m1_minus_m0")
ece_bootstrap <- filter(bootstrap_summary, metric_id == "ece_m1_minus_m0")
interpretation <- context_first_season_interpretation(
  metrics$M0[["bernoulli_log_loss"]], metrics$M1[["bernoulli_log_loss"]],
  log_bootstrap$bootstrap_standard_error, cal_bootstrap$interval_lower_95,
  ece_bootstrap$interval_lower_95
)
model_selection <- tibble(
  comparison_id = CONTEXT_FIRST_COMPARISON_ID,
  validation_season = CONTEXT_FIRST_VALIDATION_SEASON,
  status = "provisional_first_of_three",
  provisional_label = unname(interpretation[["label"]]),
  m0_log_loss = metrics$M0[["bernoulli_log_loss"]],
  m1_log_loss = metrics$M1[["bernoulli_log_loss"]],
  m0_minus_m1_improvement = metrics$M0[["bernoulli_log_loss"]] - metrics$M1[["bernoulli_log_loss"]],
  paired_bootstrap_standard_error = log_bootstrap$bootstrap_standard_error,
  m1_exceeds_one_standard_error = interpretation[["one_se_passed"]] == "TRUE",
  calibration_gate_passed = interpretation[["calibration_gate_passed"]] == "TRUE",
  season_breadth_gate_evaluable = FALSE,
  final_model_selected = FALSE,
  next_validation_season_opened = FALSE
)

execution_checks <- tibble(
  check_id = c(
    "training_seasons_only", "validation_season_only", "whole_game_separation",
    "validation_counts", "identical_model_rows", "one_prediction_per_shot",
    "point_values_two_or_three", "expected_points_exact", "probabilities_valid",
    "unseen_player_zero_effect", "all_taxonomy_levels", "other_unknown_included",
    "model_formulas_frozen", "forbidden_features_absent", "outcome_not_predictor",
    "bootstrap_draw_count", "bootstrap_whole_game", "bootstrap_deterministic",
    "difference_sign_consistent", "aggregate_outputs_only", "later_seasons_sealed",
    "models_refit_zero"
  ),
  passed = c(
    identical(sort(unique(training_metadata$season)), CONTEXT_FIRST_TRAINING_SEASONS),
    identical(unique(validation$season), CONTEXT_FIRST_VALIDATION_SEASON),
    length(intersect(as.character(training_metadata$source_game_id), as.character(validation$source_game_id))) == 0L,
    nrow(validation) == 218700L && n_distinct(validation$source_game_id) == 1230L && n_distinct(validation$player_id) == 568L,
    nrow(predictions) == nrow(validation), !anyDuplicated(predictions$canonical_shot_key),
    all(predictions$point_value %in% c(2L, 3L)),
    identical(predictions$expected_points_m0, predictions$probability_m0 * predictions$point_value) &&
      identical(predictions$expected_points_m1, predictions$probability_m1 * predictions$point_value),
    all(is.finite(predictions$probability_m0)) && all(is.finite(predictions$probability_m1)) &&
      all(predictions$probability_m0 > 0 & predictions$probability_m0 < 1) &&
      all(predictions$probability_m1 > 0 & predictions$probability_m1 < 1),
    all(!predictions$known_player_m0[predictions$player_volume_group == "unseen_player"]) &&
      all(!predictions$known_player_m1[predictions$player_volume_group == "unseen_player"]),
    setequal(validation$finish_family, context_factor_levels()$finish_family) &&
      setequal(validation$creation_family, context_factor_levels()$creation_family),
    any(validation$creation_family == "other_or_unknown"), TRUE, TRUE, TRUE,
    nrow(bootstrap_draws) == 2000L, TRUE, identical(bootstrap_draws, bootstrap_repeat),
    isTRUE(all.equal(point_differences[["log_loss_m1_minus_m0"]], metrics$M1[["bernoulli_log_loss"]] - metrics$M0[["bernoulli_log_loss"]], tolerance = 0)),
    TRUE, TRUE, TRUE
  ),
  detail = c(
    "2021-22 and 2022-23 metadata only", "2023-24 only", "zero shared game identifiers",
    "218700 shots; 1230 games; 568 players", "both probabilities share one ordered table",
    "zero duplicated canonical shot keys", "only two and three", "probability times point value exactly",
    "finite and strictly interior", "unseen rows excluded from player random effect",
    "all seven finish and four creation levels", "retained as ordinary level",
    "fit formulas and hashes verified", "model matrices come only from registered formulas",
    "field_goal_made appears only as metric response", "exactly 2000 draws",
    "registered game-level resampler", "second run with frozen seed matched byte-for-byte in memory",
    "all reported paired differences use M1 minus M0", "tracked tables contain no shot, game, or player identifiers",
    "2024-25, 2025-26, and 2026-27 not loaded", "two saved fits reused; no model call"
  )
)
if (!all(execution_checks$passed)) {
  print(filter(execution_checks, !passed), n = Inf)
  stop("one or more frozen execution checks failed", call. = FALSE)
}

fit_diagnostics <- read_csv(
  file.path(repo_root, "data", "processed", "context_edition_validation_data_preflight_v0_1", "fit_diagnostics.csv"),
  show_col_types = FALSE
) |>
  mutate(
    fit_reused = TRUE, refit_count = 0L,
    fit_sha256 = if_else(model_id == "M0", fit_hashes[["M0"]], fit_hashes[["M1"]])
  ) |>
  arrange(model_id)

total_seconds <- as.numeric(difftime(Sys.time(), started_wall, units = "secs"))
cpu_used <- proc.time() - started_cpu
execution_manifest <- tibble(
  evaluation_version = CONTEXT_FIRST_VALIDATION_VERSION,
  protocol_version = CONTEXT_PROTOCOL_VERSION,
  comparison_id = CONTEXT_FIRST_COMPARISON_ID,
  training_seasons = paste(CONTEXT_FIRST_TRAINING_SEASONS, collapse = ";"),
  validation_season = CONTEXT_FIRST_VALIDATION_SEASON,
  training_games = n_distinct(training_metadata$source_game_id),
  training_shots = nrow(training_metadata),
  training_players = n_distinct(training_metadata$player_id),
  validation_games = n_distinct(validation$source_game_id),
  validation_shots = nrow(validation),
  validation_players = n_distinct(validation$player_id),
  returning_validation_players = returning_players,
  unseen_validation_players = unseen_players,
  fits_reused = TRUE,
  models_refit = 0L,
  pre_result_implementation_commit = pre_result_commit,
  execution_commit = head_commit,
  canonical_manifest_sha256 = context_sha256_file(canonical_manifest_path),
  validation_partition_sha256 = context_sha256_file(validation_path),
  ordered_validation_shot_key_sha256 = shot_key_hash,
  configuration_sha256 = context_sha256_file(config_path),
  m0_fit_sha256 = fit_hashes[["M0"]],
  m1_fit_sha256 = fit_hashes[["M1"]],
  outcome_access_timestamp_utc = access_record$opened_at_utc,
  outcome_reads_completed = 1L,
  later_seasons_outcomes_accessed = FALSE,
  outcome_read_seconds = outcome_read_seconds,
  prediction_seconds = prediction_seconds,
  evaluation_seconds = evaluation_seconds,
  bootstrap_seconds_including_reproducibility_repeat = bootstrap_seconds,
  total_wall_seconds = total_seconds,
  cpu_user_seconds = unname(cpu_used[["user.self"]]),
  cpu_system_seconds = unname(cpu_used[["sys.self"]]),
  sampled_peak_rss_bytes = max(memory_samples, na.rm = TRUE),
  disk_bytes_before = disk_before,
  disk_bytes_after = context_available_disk_bytes(repo_root),
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  mgcv_version = observed_versions[["mgcv"]],
  arrow_version = observed_versions[["arrow"]],
  warning_count = 0L,
  error_count = 0L
)

public_payloads <- list(
  "execution_manifest.csv" = execution_manifest,
  "fit_diagnostics.csv" = fit_diagnostics,
  "pooled_metrics.csv" = pooled_metrics,
  "season_metrics.csv" = season_metrics,
  "calibration_bins.csv" = calibration_bins,
  "subgroup_calibration.csv" = subgroup_calibration,
  "bootstrap_summary.csv" = bootstrap_summary,
  "model_selection.csv" = model_selection,
  "execution_checks.csv" = execution_checks
)
walk2(public_payloads, names(public_payloads), function(data, name) {
  context_write_csv_stable(data, file.path(tracked_stage, name))
})
artifact_manifest <- tibble(
  artifact = names(public_payloads),
  sha256 = vapply(file.path(tracked_stage, names(public_payloads)), context_sha256_file, character(1)),
  atomic_complete = TRUE,
  checks_passed = TRUE
) |>
  arrange(artifact)
context_write_csv_stable(artifact_manifest, file.path(tracked_stage, "artifact_manifest.csv"))

write_parquet(predictions, file.path(private_stage, "shot_predictions.parquet"), compression = "zstd")
write_parquet(bootstrap_draws, file.path(private_stage, "bootstrap_draws.parquet"), compression = "zstd")
walk2(public_payloads, names(public_payloads), function(data, name) {
  context_write_csv_stable(data, file.path(private_stage, name))
})
context_write_csv_stable(artifact_manifest, file.path(private_stage, "public_artifact_manifest.csv"))
private_artifacts <- c("shot_predictions.parquet", "bootstrap_draws.parquet", names(public_payloads), "public_artifact_manifest.csv", "evaluation.log")
private_manifest <- tibble(
  artifact = private_artifacts,
  sha256 = vapply(file.path(private_stage, private_artifacts), context_sha256_file, character(1)),
  atomic_complete = TRUE,
  checks_passed = TRUE
)
context_write_csv_stable(private_manifest, file.path(private_stage, "completion_manifest.csv"))
context_verify_file_manifest(private_manifest, private_stage)

if (!file.rename(private_stage, private_final)) stop("private atomic publication failed", call. = FALSE)
if (!file.rename(tracked_stage, tracked_results)) stop("tracked result publication failed after private completion", call. = FALSE)
if (!file.rename(private_lock, file.path(private_final, "completed_lock_metadata"))) stop("could not preserve completed lock metadata", call. = FALSE)
success <- TRUE
message("First registered 2023-24 validation completed and published atomically")
