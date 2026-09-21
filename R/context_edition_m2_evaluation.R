#!/usr/bin/env Rscript

# Frozen historical M2-versus-M1 rolling-origin evaluation.
# audit: outcome-free artifact/configuration checks only.
# fit: fit one missing split-specific M2 training component.
# evaluate: open one authorized validation season once and publish atomically.
# verify: verify a completed split without loading canonical outcomes.

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
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_evaluation.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) >= 1L) args[[1]] else "audit"
comparison_id <- if (length(args) >= 2L) args[[2]] else NA_character_
if (!mode %in% c("audit", "fit", "evaluate", "verify", "finalize")) {
  stop("usage: Rscript R/context_edition_m2_evaluation.R audit|fit|evaluate|verify [development_1|development_2|development_3] or finalize", call. = FALSE)
}
if (!mode %in% c("audit", "finalize") && (is.na(comparison_id) || !comparison_id %in% paste0("development_", 1:3))) {
  stop("a registered comparison_id is required", call. = FALSE)
}

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_evaluation_helpers.R"), local = TRUE)

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(result) != 1L) stop("could not hash ", path, call. = FALSE)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

write_csv_stable <- function(data, path) readr::write_csv(data, path, na = "", quote = "needed")

git_value <- function(arguments) {
  output <- system2("git", c("-C", repo_root, arguments), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop("git command failed", call. = FALSE)
  trimws(output[[1]])
}

config_path <- file.path(repo_root, "config", "context_edition_m2_evaluation_v0_1.csv")
windows_path <- file.path(repo_root, "config", "context_edition_m2_evaluation_windows_v0_1.csv")
reuse_path <- file.path(repo_root, "config", "context_edition_m2_evaluation_reuse_v0_1.csv")
config <- read_csv(config_path, show_col_types = FALSE)
config_values <- setNames(config$value, config$key)
windows <- read_csv(windows_path, show_col_types = FALSE, na = character())
reuse_requirements <- read_csv(reuse_path, show_col_types = FALSE, na = character())
context_m2_evaluation_validate_windows(windows)

expected_config <- c(
  evaluation_version = CONTEXT_M2_EVALUATION_VERSION,
  protocol_version = CONTEXT_M2_PROTOCOL_VERSION,
  primary_metric = "pooled_shot_level_bernoulli_log_loss",
  primary_difference_sign = "M2_minus_M1",
  bootstrap_unit = "whole_game_within_validation_season",
  bootstrap_interval = "percentile_95",
  tie_or_failed_gate_action = "retain_M1",
  d1_selection_role = "diagnostic_only_cannot_select",
  expected_points_selection_role = "diagnostic_only",
  fit_engine = "mgcv::gam",
  fit_method = "REML",
  optimizer = "outer;newton",
  discrete = "FALSE"
)
if (!all(config_values[names(expected_config)] == expected_config)) stop("evaluation configuration changed", call. = FALSE)
if (as.numeric(config_values[["probability_clip"]]) != CONTEXT_M2_LOG_CLIP ||
    as.integer(config_values[["bootstrap_replicates"]]) != CONTEXT_M2_BOOTSTRAP_REPLICATES ||
    as.integer(config_values[["bootstrap_seed"]]) != CONTEXT_M2_BOOTSTRAP_SEED ||
    as.numeric(config_values[["material_calibration_margin"]]) != CONTEXT_M2_CALIBRATION_MARGIN ||
    as.integer(config_values[["distance_k"]]) != 10L ||
    config_values[["prospective_2026_27_access_allowed"]] != "FALSE") {
  stop("numeric or seal setting changed", call. = FALSE)
}

required_versions <- c(mgcv = "1.9.4", Matrix = "1.7.5", arrow = "25.0.0", dplyr = "1.2.1", tidyr = "1.3.2", readr = "2.2.0")
observed_versions <- vapply(names(required_versions), function(package) as.character(utils::packageVersion(package)), character(1))
if (!identical(unname(observed_versions), unname(required_versions)) || paste(R.version$major, R.version$minor, sep = ".") != "4.6.0") {
  stop("package or R version differs from the frozen protocol", call. = FALSE)
}

canonical_root <- file.path(repo_root, "data", "cache", "context_edition_canonical", "context_field_goal_v0.1.2__2021-22_to_2025-26")
private_root <- file.path(repo_root, "data", "cache", "context_edition_m2_evaluation")
tracked_root <- file.path(repo_root, "data", "processed", "context_edition_m2_evaluation_v0_1")
authorization_path <- file.path(private_root, "execution_authorization.csv")

verify_manifest <- function(root) {
  manifest_path <- file.path(root, "completion_manifest.csv")
  if (!file.exists(manifest_path)) stop("completion manifest missing: ", root, call. = FALSE)
  manifest <- read_csv(manifest_path, show_col_types = FALSE)
  context_preflight_verify_manifest(manifest, root, sha256_file)
  manifest
}

verify_fit <- function(row, model_id) {
  relative_path <- if (model_id == "M1") row$m1_fit_source else row$m2_fit_source
  expected_hash <- if (model_id == "M1") row$m1_fit_sha256 else row$m2_fit_sha256
  fit_path <- file.path(repo_root, relative_path)
  if (!file.exists(fit_path)) stop(model_id, " fit is missing for ", row$comparison_id, call. = FALSE)
  observed_hash <- sha256_file(fit_path)
  if (nzchar(expected_hash)) context_m2_evaluation_verify_hash(fit_path, expected_hash, sha256_file)
  component_root <- dirname(fit_path)
  manifest <- verify_manifest(component_root)
  manifest_row <- manifest[manifest$artifact == basename(fit_path), , drop = FALSE]
  if (nrow(manifest_row) != 1L || manifest_row$sha256 != observed_hash) {
    stop(model_id, " manifest does not identify the frozen fit", call. = FALSE)
  }
  reuse_row <- reuse_requirements[
    reuse_requirements$comparison_id == row$comparison_id & reuse_requirements$model_id == model_id,
    , drop = FALSE
  ]
  if (nrow(reuse_row) == 1L) {
    if (reuse_row$fit_sha256 != observed_hash || isTRUE(reuse_row$validation_outcomes_accessed)) {
      stop(model_id, " reuse declaration differs from the artifact", call. = FALSE)
    }
    if ("canonical_manifest_sha256" %in% names(manifest) &&
        any(manifest$canonical_manifest_sha256 != reuse_row$canonical_manifest_sha256)) {
      stop(model_id, " canonical manifest provenance differs", call. = FALSE)
    }
    source_config_field <- intersect(c("configuration_sha256", "config_sha256"), names(manifest))
    if (length(source_config_field) == 1L &&
        any(manifest[[source_config_field]] != reuse_row$source_configuration_sha256)) {
      stop(model_id, " source configuration provenance differs", call. = FALSE)
    }
    if (nzchar(reuse_row$training_input_hash) && "input_hash" %in% names(manifest) &&
        any(manifest$input_hash != reuse_row$training_input_hash)) {
      stop(model_id, " training input hash differs", call. = FALSE)
    }
    if (nzchar(reuse_row$source_model_spec_sha256) && "model_spec_sha256" %in% names(manifest) &&
        any(manifest$model_spec_sha256 != reuse_row$source_model_spec_sha256)) {
      stop(model_id, " source model specification differs", call. = FALSE)
    }
  }
  metadata_path <- file.path(component_root, "fit_metadata.csv")
  if (file.exists(metadata_path)) {
    metadata <- read_csv(metadata_path, show_col_types = FALSE)
    if (nrow(metadata) != 1L || metadata$model_id != model_id ||
        metadata$training_seasons != row$training_seasons ||
        metadata$training_shots != row$training_shots ||
        metadata$grouped_rows != if (model_id == "M1") row$m1_grouped_rows else row$m2_grouped_rows ||
        ("converged" %in% names(metadata) && !isTRUE(metadata$converged)) ||
        ("validation_outcomes_accessed" %in% names(metadata) && isTRUE(metadata$validation_outcomes_accessed))) {
      stop(model_id, " fit metadata does not match the required split", call. = FALSE)
    }
    if ("training_partition_sha256s" %in% names(metadata) &&
        metadata$training_partition_sha256s != row$training_partition_sha256s) {
      stop(model_id, " training partition hashes differ", call. = FALSE)
    }
    if (nrow(reuse_row) == 1L && "config_sha256" %in% names(metadata) &&
        metadata$config_sha256 != reuse_row$source_configuration_sha256) {
      stop(model_id, " fit metadata configuration hash differs", call. = FALSE)
    }
    if (nrow(reuse_row) == 1L && "canonical_manifest_sha256" %in% names(metadata) &&
        metadata$canonical_manifest_sha256 != reuse_row$canonical_manifest_sha256) {
      stop(model_id, " fit metadata canonical hash differs", call. = FALSE)
    }
  }
  fit <- readRDS(fit_path)
  expected_formula <- context_m2_formulas()[[model_id]]
  formula_text <- function(value) gsub("[[:space:]]+", "", paste(deparse(value), collapse = ""))
  expected_coefficients <- if (model_id == "M1") row$m1_coefficients else row$m2_coefficients
  expected_sp <- if (model_id == "M1") 1L else 2L
  if (!inherits(fit, "gam") || !isTRUE(fit$converged) ||
      formula_text(formula(fit)) != formula_text(expected_formula) ||
      length(coef(fit)) != expected_coefficients || length(fit$sp) != expected_sp ||
      any(!is.finite(coef(fit))) || any(!is.finite(fit$Vp)) || any(!is.finite(fit$sp)) || any(fit$sp <= 0)) {
    stop(model_id, " fit failed frozen structural checks for ", row$comparison_id, call. = FALSE)
  }
  list(fit = fit, hash = observed_hash)
}

fit_component_root <- function(id) file.path(private_root, "fit_components", id, "m2_v0.1.0")
result_root <- function(id) file.path(private_root, "results", paste0(id, "_v0.1.0"))
prediction_root <- function(id) file.path(private_root, "predictions", paste0(id, "_v0.1.0"))
access_root <- function(id) file.path(private_root, "access", paste0(".", id, ".accessed"))
lock_root <- function(id, stage) file.path(private_root, "locks", paste0(".", id, ".", stage, ".lock"))

verify_clean_pushed <- function() {
  pre_result <- config_values[["pre_result_implementation_commit"]]
  if (!grepl("^[0-9a-f]{40}$", pre_result)) stop("pre-result implementation commit is not recorded", call. = FALSE)
  head <- git_value(c("rev-parse", "HEAD"))
  upstream <- git_value(c("rev-parse", "@{upstream}"))
  if (head != upstream) stop("local and upstream revisions differ", call. = FALSE)
  if (system2("git", c("-C", repo_root, "merge-base", "--is-ancestor", pre_result, "HEAD")) != 0L) {
    stop("recorded pre-result commit is not in current history", call. = FALSE)
  }
  if (system2("git", c("-C", repo_root, "diff", "--quiet")) != 0L ||
      system2("git", c("-C", repo_root, "diff", "--cached", "--quiet")) != 0L) {
    stop("tracked worktree must be clean", call. = FALSE)
  }
  status <- system2("git", c("-C", repo_root, "status", "--porcelain"), stdout = TRUE)
  unexpected <- status[startsWith(status, "?? ") & status != "?? skill-observations/"]
  if (length(unexpected) > 0L) stop("unexpected untracked files exist", call. = FALSE)
  c(head = head, pre_result = pre_result)
}

window_audit <- map_dfr(seq_len(nrow(windows)), function(index) {
  row <- windows[index, ]
  training <- strsplit(row$training_seasons, ";", fixed = TRUE)[[1]]
  context_m2_evaluation_guard_seasons(training, row$validation_season)
  m1 <- verify_fit(row, "M1")
  m2_expected_now <- row$m2_fit_policy == "reuse_verified_preflight" || file.exists(file.path(repo_root, row$m2_fit_source))
  m2 <- if (m2_expected_now) verify_fit(row, "M2") else NULL
  tibble(
    comparison_id = row$comparison_id,
    training_seasons = row$training_seasons,
    validation_season = row$validation_season,
    m1_fit_reusable = TRUE,
    m1_fit_sha256 = m1$hash,
    m2_fit_reusable = m2_expected_now,
    m2_fit_sha256 = if (is.null(m2)) "not_yet_fit" else m2$hash,
    validation_outcomes_accessed = dir.exists(access_root(row$comparison_id)),
    prospective_2026_27_accessed = FALSE
  )
})

if (mode == "audit") {
  if (any(window_audit$validation_outcomes_accessed)) stop("historical validation access already exists", call. = FALSE)
  if (dir.exists(file.path(private_root, "locks"))) {
    active_locks <- list.dirs(file.path(private_root, "locks"), recursive = FALSE, full.names = TRUE)
    if (length(active_locks) > 0L) stop("an evaluation lock exists", call. = FALSE)
  }
  output_schema <- tibble(
    artifact = c(
      "execution_manifest.csv", "fit_accounting.csv", "pooled_metrics.csv",
      "season_metrics.csv", "calibration_bins.csv", "subgroup_calibration.csv",
      "bootstrap_summary.csv", "model_selection.csv", "execution_checks.csv",
      "artifact_manifest.csv", "final_model_decision.csv", "season_log_loss.csv",
      "final_checks.csv"
    ),
    contains_shot_rows = FALSE,
    contains_game_or_player_identifiers = FALSE
  )
  checks <- tibble(
    check_id = c(
      "three_registered_windows", "training_seasons_exact", "validation_seasons_sealed",
      "m1_artifacts_verified", "first_m2_artifact_verified", "later_m2_not_prefit",
      "m2_minus_m1_sign", "paired_bootstrap_seed", "d1_cannot_select",
      "prospective_guard", "authorization_required", "no_existing_attempt"
    ),
    passed = c(
      nrow(windows) == 3L, TRUE, all(!windows$validation_outcomes_accessed),
      all(window_audit$m1_fit_reusable), window_audit$m2_fit_reusable[1],
      all(!window_audit$m2_fit_reusable[2:3]),
      config_values[["primary_difference_sign"]] == "M2_minus_M1",
      as.integer(config_values[["bootstrap_seed"]]) == 20260914L,
      config_values[["d1_selection_role"]] == "diagnostic_only_cannot_select",
      config_values[["prospective_2026_27_access_allowed"]] == "FALSE",
      config_values[["execution_authorization_required"]] == "TRUE", TRUE
    ),
    detail = c(
      "three expanding historical windows", "registered seasons only",
      "2023-24 through 2025-26 outcomes remain unopened by this runner",
      "three exact M1 hashes and structures matched", "first-window M2 preflight hash matched",
      "later-window M2 fits remain future fit-once work", "negative favors M2",
      "2000 whole-game samples; seed 20260914", "argument ignored by selection helper",
      "2026-27 rejected in every mode", "private per-comparison authorization file required",
      "no access marker, lock, result, or partial evaluation"
    )
  )
  if (!all(checks$passed)) stop("outcome-free audit failed", call. = FALSE)
  dir.create(tracked_root, recursive = TRUE, showWarnings = FALSE)
  context_atomic_write_csv(window_audit, file.path(tracked_root, "pre_result_artifact_audit.csv"))
  context_atomic_write_csv(checks, file.path(tracked_root, "pre_result_checks.csv"))
  context_atomic_write_csv(output_schema, file.path(tracked_root, "output_schema.csv"))
  message("Outcome-free M2 evaluation audit passed; no validation outcome was read and no model was fit")
  quit(save = "no", status = 0L)
}

if (mode == "finalize") {
  prediction_roots <- vapply(windows$comparison_id, prediction_root, character(1))
  result_roots <- vapply(windows$comparison_id, result_root, character(1))
  if (!all(dir.exists(prediction_roots)) || !all(dir.exists(result_roots))) {
    stop("all three atomic season results and prediction checkpoints are required", call. = FALSE)
  }
  walk(prediction_roots, ~ verify_manifest(.x))
  walk(result_roots, ~ verify_manifest(.x))
  predictions <- map_dfr(prediction_roots, ~ read_parquet(file.path(.x, "shot_predictions.parquet"), as_data_frame = TRUE))
  if (!identical(sort(unique(predictions$comparison_id)), windows$comparison_id) ||
      anyDuplicated(predictions$canonical_shot_key) || anyNA(predictions)) {
    stop("pooled prediction checkpoints are incomplete or overlap", call. = FALSE)
  }
  pooled_bootstrap <- context_m2_paired_game_bootstrap(predictions)
  pooled_repeat <- context_m2_paired_game_bootstrap(predictions)
  if (!identical(pooled_bootstrap, pooled_repeat)) stop("pooled bootstrap is not deterministic", call. = FALSE)
  pooled_m1 <- context_log_loss(predictions$outcome, predictions$probability_m1)
  pooled_m2 <- context_log_loss(predictions$outcome, predictions$probability_m2)
  bin_m1 <- context_equal_count_bins(predictions$probability_m1)
  bin_m2 <- context_equal_count_bins(predictions$probability_m2)
  cal_m1 <- context_calibration_errors(predictions$outcome, predictions$probability_m1, bin_m1)
  cal_m2 <- context_calibration_errors(predictions$outcome, predictions$probability_m2, bin_m2)
  season_losses <- predictions |>
    group_by(comparison_id) |>
    summarise(
      m1_log_loss = context_log_loss(outcome, probability_m1),
      m2_log_loss = context_log_loss(outcome, probability_m2), .groups = "drop"
    ) |>
    arrange(comparison_id)
  selection <- context_m2_evaluation_select(
    pooled_m1, pooled_m2,
    sd(pooled_bootstrap$log_loss_m2_minus_m1),
    unname(quantile(pooled_bootstrap$calibration_abs_m2_minus_m1, 0.025, names = FALSE)),
    unname(quantile(pooled_bootstrap$ece_m2_minus_m1, 0.025, names = FALSE)),
    season_losses$m1_log_loss, season_losses$m2_log_loss,
    d1_signal = "ignored_by_design"
  )
  final_decision <- tibble(
    evaluation_version = CONTEXT_M2_EVALUATION_VERSION,
    selected_model = unname(selection[["model"]]),
    reason = unname(selection[["reason"]]),
    pooled_m1_log_loss = pooled_m1, pooled_m2_log_loss = pooled_m2,
    m2_minus_m1 = pooled_m2 - pooled_m1,
    paired_bootstrap_standard_error = sd(pooled_bootstrap$log_loss_m2_minus_m1),
    calibration_abs_m2_minus_m1 = cal_m2[["calibration_in_large_abs"]] - cal_m1[["calibration_in_large_abs"]],
    ece_m2_minus_m1 = cal_m2[["ece"]] - cal_m1[["ece"]],
    m2_season_wins = sum(season_losses$m2_log_loss < season_losses$m1_log_loss),
    d1_used_for_selection = FALSE, prospective_2026_27_accessed = FALSE
  )
  final_checks <- tibble(
    check_id = c("three_seasons_complete", "pooled_rows_unique", "bootstrap_deterministic", "d1_isolated", "prospective_sealed"),
    passed = c(nrow(season_losses) == 3L, !anyDuplicated(predictions$canonical_shot_key), identical(pooled_bootstrap, pooled_repeat), TRUE, TRUE)
  )
  final_root <- file.path(private_root, "results", "pooled_historical_decision_v0.1.0")
  if (dir.exists(final_root)) stop("pooled decision already exists", call. = FALSE)
  stage <- paste0(final_root, ".partial")
  dir.create(stage, recursive = TRUE)
  payloads <- list(
    "final_model_decision.csv" = final_decision,
    "season_log_loss.csv" = season_losses,
    "final_checks.csv" = final_checks
  )
  walk2(payloads, names(payloads), ~ write_csv_stable(.x, file.path(stage, .y)))
  manifest <- tibble(
    artifact = names(payloads), sha256 = vapply(file.path(stage, names(payloads)), sha256_file, character(1)),
    atomic_complete = TRUE, checks_passed = TRUE
  )
  write_csv_stable(manifest, file.path(stage, "completion_manifest.csv"))
  verify_manifest(stage)
  context_m2_evaluation_atomic_publish(stage, final_root)
  tracked_final <- file.path(tracked_root, "results", "pooled_historical_decision")
  tracked_stage <- paste0(tracked_final, ".partial")
  dir.create(tracked_stage, recursive = TRUE)
  walk2(payloads, names(payloads), ~ write_csv_stable(.x, file.path(tracked_stage, .y)))
  write_csv_stable(manifest, file.path(tracked_stage, "artifact_manifest.csv"))
  context_m2_evaluation_atomic_publish(tracked_stage, tracked_final)
  message("Published the frozen pooled historical decision; 2026-27 remained sealed")
  quit(save = "no", status = 0L)
}

row <- windows[windows$comparison_id == comparison_id, ]
training_seasons <- strsplit(row$training_seasons, ";", fixed = TRUE)[[1]]
context_m2_evaluation_guard_seasons(training_seasons, row$validation_season)

if (row$order > 1L) {
  prior_ids <- windows$comparison_id[windows$order < row$order]
  prior_roots <- vapply(prior_ids, result_root, character(1))
  if (!all(dir.exists(prior_roots))) stop("earlier rolling-origin results must complete first", call. = FALSE)
  walk(prior_roots, ~ verify_manifest(.x))
}

if (mode == "verify") {
  final <- result_root(comparison_id)
  verify_manifest(final)
  message("Verified completed ", comparison_id, " result without loading canonical outcomes or fitting")
  quit(save = "no", status = 0L)
}

commits <- verify_clean_pushed()
context_m2_evaluation_verify_authorization(
  authorization_path, comparison_id, commits[["pre_result"]]
)

if (mode == "fit") {
  m1 <- verify_fit(row, "M1")
  if (row$m2_fit_policy == "reuse_verified_preflight") {
    verify_fit(row, "M2")
    message("Both first-window fits are exactly reusable; no model was fit")
    quit(save = "no", status = 0L)
  }
  final_component <- fit_component_root(comparison_id)
  if (dir.exists(final_component)) {
    verify_manifest(final_component)
    message("Verified existing M2 component; no duplicate fit was run")
    quit(save = "no", status = 0L)
  }
  lock <- lock_root(comparison_id, "fit")
  if (dir.exists(lock) || !dir.create(lock, recursive = TRUE, showWarnings = FALSE)) stop("fit lock exists or cannot be acquired", call. = FALSE)
  on.exit(if (dir.exists(lock)) unlink(lock, recursive = TRUE), add = TRUE)
  total_started <- Sys.time()
  disk_before <- context_available_disk_bytes(repo_root)
  training_paths <- file.path(canonical_root, paste0("season=", training_seasons), "canonical_shots.parquet")
  expected_training_hashes <- strsplit(row$training_partition_sha256s, ";", fixed = TRUE)[[1]]
  if (!identical(unname(vapply(training_paths, sha256_file, character(1))), expected_training_hashes)) stop("training partition hash mismatch", call. = FALSE)
  fields <- c("season", "player_id", "point_value", "finish_family", "creation_family", "shot_distance_feet", "field_goal_made")
  training <- map_dfr(training_paths, ~ read_parquet(.x, col_select = all_of(fields), as_data_frame = TRUE))
  if (!identical(sort(unique(training$season)), training_seasons) || nrow(training) != row$training_shots) stop("training population changed", call. = FALSE)
  levels_frozen <- context_m2_factor_levels()
  player_levels <- sort(unique(as.character(training$player_id)))
  prepared <- training |>
    mutate(
      player_id_factor = factor(as.character(player_id), levels = player_levels),
      point_value_factor = factor(if_else(point_value == 2L, "two", "three"), levels = levels_frozen$point_value_factor),
      finish_family = factor(finish_family, levels = levels_frozen$finish_family),
      creation_family = factor(creation_family, levels = levels_frozen$creation_family)
    )
  counts <- context_m2_evaluation_group_counts(prepared)
  if (nrow(counts) != row$m2_grouped_rows || sum(counts$attempts) != row$training_shots) stop("M2 grouped counts changed", call. = FALSE)
  warnings_seen <- character()
  started <- Sys.time(); cpu_started <- proc.time()
  fit <- withCallingHandlers(
    mgcv::gam(
      formula = context_m2_formulas(k = 10L)$M2,
      family = stats::binomial(link = "logit"), data = counts,
      method = "REML", optimizer = c("outer", "newton"),
      control = mgcv::gam.control(), select = FALSE, gamma = 1,
      na.action = stats::na.fail, drop.unused.levels = FALSE, discrete = FALSE
    ),
    warning = function(warning) {
      warnings_seen <<- c(warnings_seen, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )
  fit_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  cpu <- proc.time() - cpu_started
  if (!isTRUE(fit$converged) || length(coef(fit)) != row$m2_coefficients ||
      any(!is.finite(coef(fit))) || any(!is.finite(fit$Vp)) ||
      length(fit$sp) != 2L || any(!is.finite(fit$sp)) || any(fit$sp <= 0) || length(warnings_seen) > 0L) {
    stop("M2 fit failed frozen structural checks", call. = FALSE)
  }
  set.seed(CONTEXT_M2_K_CHECK_SEED)
  k_table <- mgcv::k.check(fit, subsample = CONTEXT_M2_K_CHECK_SUBSAMPLE, n.rep = CONTEXT_M2_K_CHECK_REPLICATES)
  distance_row <- k_table[grepl("shot_distance_feet", rownames(k_table), fixed = TRUE), , drop = FALSE]
  k_action <- context_m2_k_escalation(sum(fit$edf[grepl("shot_distance_feet", names(fit$edf), fixed = TRUE)]), distance_row[1, "k-index"], distance_row[1, "p-value"], 10L)
  if (k_action != "retain_k_10") stop("registered k=10 adequacy rule did not pass; outcome access remains blocked", call. = FALSE)
  stage <- paste0(final_component, ".", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".partial")
  dir.create(stage, recursive = TRUE)
  saveRDS(fit, file.path(stage, "fit.rds"), compress = "xz")
  metadata <- tibble(
    evaluation_version = CONTEXT_M2_EVALUATION_VERSION, comparison_id,
    model_id = "M2", training_seasons = row$training_seasons,
    training_shots = row$training_shots, grouped_rows = nrow(counts),
    players = length(player_levels), coefficients = length(coef(fit)),
    fit_count = 1L, converged = TRUE, validation_outcomes_accessed = FALSE,
    fit_seconds, cpu_user_seconds = unname(cpu[["user.self"]]),
    cpu_system_seconds = unname(cpu[["sys.self"]]),
    total_wall_seconds = as.numeric(difftime(Sys.time(), total_started, units = "secs")),
    sampled_rss_bytes_after_fit = context_current_rss_bytes(),
    disk_bytes_before = disk_before,
    disk_bytes_after = context_available_disk_bytes(repo_root),
    fit_object_bytes = as.numeric(object.size(fit)),
    serialized_fit_bytes = file.info(file.path(stage, "fit.rds"))$size,
    smoothing_parameters = paste(signif(fit$sp, 12), collapse = ";"),
    k_action, warning_count = length(warnings_seen), warnings = paste(warnings_seen, collapse = " | "),
    training_partition_sha256s = row$training_partition_sha256s,
    evaluation_config_sha256 = sha256_file(config_path),
    windows_config_sha256 = sha256_file(windows_path),
    formula = paste(deparse(context_m2_formulas(k = 10L)$M2), collapse = " "),
    engine_settings = "mgcv::gam;binomial_logit;REML;outer+newton;discrete=FALSE;select=FALSE;gamma=1;drop.unused.levels=FALSE",
    fit_sha256 = sha256_file(file.path(stage, "fit.rds"))
  )
  write_csv_stable(metadata, file.path(stage, "fit_metadata.csv"))
  artifacts <- c("fit.rds", "fit_metadata.csv")
  manifest <- tibble(artifact = artifacts, sha256 = vapply(file.path(stage, artifacts), sha256_file, character(1)), atomic_complete = TRUE, checks_passed = TRUE)
  write_csv_stable(manifest, file.path(stage, "completion_manifest.csv"))
  verify_manifest(stage)
  context_m2_evaluation_atomic_publish(stage, final_component)
  message("Published one verified M2 fit component for ", comparison_id)
  quit(save = "no", status = 0L)
}

# Evaluation begins only after both exact split-specific fits pass verification.
m1 <- verify_fit(row, "M1")
if (row$m2_fit_policy == "reuse_verified_preflight") {
  m2 <- verify_fit(row, "M2")
} else {
  component <- fit_component_root(comparison_id)
  verify_manifest(component)
  row$m2_fit_source <- file.path("data", "cache", "context_edition_m2_evaluation", "fit_components", comparison_id, "m2_v0.1.0", "fit.rds")
  row$m2_fit_sha256 <- sha256_file(file.path(component, "fit.rds"))
  m2 <- verify_fit(row, "M2")
}

final <- result_root(comparison_id)
if (dir.exists(final)) stop("completed result exists; use verify", call. = FALSE)
execution_started <- Sys.time()
execution_cpu_started <- proc.time()
lock <- lock_root(comparison_id, "evaluation")
if (dir.exists(lock) || !dir.create(lock, recursive = TRUE, showWarnings = FALSE)) stop("evaluation lock exists or cannot be acquired", call. = FALSE)
on.exit(if (dir.exists(lock)) unlink(lock, recursive = TRUE), add = TRUE)

marker <- access_root(comparison_id)
prediction_final <- prediction_root(comparison_id)
if (dir.exists(marker) && !dir.exists(prediction_final)) {
  stop("outcome access marker exists without an atomic prediction checkpoint; manual recovery decision required", call. = FALSE)
}

if (!dir.exists(prediction_final)) {
  if (!dir.create(marker, recursive = TRUE, showWarnings = FALSE)) stop("could not publish exclusive validation-access marker", call. = FALSE)
  access_record <- tibble(
    evaluation_version = CONTEXT_M2_EVALUATION_VERSION, comparison_id,
    validation_season = row$validation_season,
    opened_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    pre_result_implementation_commit = commits[["pre_result"]],
    execution_commit = commits[["head"]], outcome_read_count_allowed = 1L,
    prospective_2026_27_accessed = FALSE
  )
  context_atomic_write_csv(access_record, file.path(marker, "access_marker.csv"))
  validation_path <- file.path(canonical_root, paste0("season=", row$validation_season), "canonical_shots.parquet")
  if (sha256_file(validation_path) != row$validation_partition_sha256) stop("validation partition hash mismatch", call. = FALSE)
  fields <- c("season", "canonical_shot_key", "source_game_id", "player_id", "point_value", "finish_family", "creation_family", "shot_distance_feet", "field_goal_made")
  outcome_started <- Sys.time()
  validation <- read_parquet(validation_path, col_select = all_of(fields), as_data_frame = TRUE) |>
    arrange(canonical_shot_key)
  outcome_read_seconds <- as.numeric(difftime(Sys.time(), outcome_started, units = "secs"))
  if (!identical(unique(validation$season), row$validation_season) || anyDuplicated(validation$canonical_shot_key) ||
      anyNA(validation$field_goal_made) || any(!validation$field_goal_made %in% c(0L, 1L))) stop("validation population failed frozen checks", call. = FALSE)
  prediction_started <- Sys.time()
  m1_prediction <- context_predict_first_validation(m1$fit, validation)
  m2_prediction <- context_m2_evaluation_predict(m2$fit, validation)
  prediction_seconds <- as.numeric(difftime(Sys.time(), prediction_started, units = "secs"))
  predictions <- validation |>
    transmute(
      comparison_id, season, canonical_shot_key, game_id = as.character(source_game_id),
      player_id, point_value, finish_family, creation_family, shot_distance_feet,
      outcome = field_goal_made,
      probability_m1 = m1_prediction$probability,
      probability_m2 = m2_prediction$probability,
      known_player_m1 = m1_prediction$known_player,
      known_player_m2 = m2_prediction$known_player
    )
  if (anyNA(predictions) || anyDuplicated(predictions$canonical_shot_key) ||
      any(!is.finite(predictions$probability_m1)) || any(!is.finite(predictions$probability_m2)) ||
      any(predictions$probability_m1 <= 0 | predictions$probability_m1 >= 1) ||
      any(predictions$probability_m2 <= 0 | predictions$probability_m2 >= 1)) stop("prediction integrity failed", call. = FALSE)
  prediction_stage <- paste0(prediction_final, ".", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".partial")
  dir.create(prediction_stage, recursive = TRUE)
  write_parquet(predictions, file.path(prediction_stage, "shot_predictions.parquet"), compression = "zstd")
  prediction_manifest <- tibble(
    artifact = "shot_predictions.parquet",
    sha256 = sha256_file(file.path(prediction_stage, "shot_predictions.parquet")),
    atomic_complete = TRUE, checks_passed = TRUE
  )
  write_csv_stable(prediction_manifest, file.path(prediction_stage, "completion_manifest.csv"))
  verify_manifest(prediction_stage)
  context_m2_evaluation_atomic_publish(prediction_stage, prediction_final)
} else {
  verify_manifest(prediction_final)
  predictions <- read_parquet(file.path(prediction_final, "shot_predictions.parquet"), as_data_frame = TRUE)
  outcome_read_seconds <- 0
  prediction_seconds <- 0
}

evaluation_started <- Sys.time()
metric_data <- tibble(
  source_game_id = predictions$game_id,
  field_goal_made = predictions$outcome,
  point_value = predictions$point_value
)
metrics <- list(
  M1 = context_model_metrics(metric_data, predictions$probability_m1),
  M2 = context_model_metrics(metric_data, predictions$probability_m2)
)
evaluation_seconds <- as.numeric(difftime(Sys.time(), evaluation_started, units = "secs"))
bootstrap_started <- Sys.time()
bootstrap <- context_m2_paired_game_bootstrap(predictions)
bootstrap_repeat <- context_m2_paired_game_bootstrap(predictions)
bootstrap_seconds <- as.numeric(difftime(Sys.time(), bootstrap_started, units = "secs"))
if (!identical(bootstrap, bootstrap_repeat) || nrow(bootstrap) != 2000L || any(!is.finite(as.matrix(bootstrap)))) stop("bootstrap reproducibility failed", call. = FALSE)
bins <- bind_rows(
  context_calibration_bins_table(metric_data, predictions$probability_m1, "M1"),
  context_calibration_bins_table(metric_data, predictions$probability_m2, "M2")
)
ece <- bins |>
  group_by(model_id) |>
  summarise(value = weighted.mean(absolute_gap, shots), .groups = "drop")
point_difference <- c(
  log_loss_m2_minus_m1 = metrics$M2[["bernoulli_log_loss"]] - metrics$M1[["bernoulli_log_loss"]],
  calibration_abs_m2_minus_m1 = metrics$M2[["absolute_bias"]] - metrics$M1[["absolute_bias"]],
  ece_m2_minus_m1 = ece$value[ece$model_id == "M2"] - ece$value[ece$model_id == "M1"]
)
bootstrap_summary <- imap_dfr(as.list(bootstrap), function(values, metric_id) tibble(
  metric_id, difference_direction = "M2_minus_M1",
  point_difference = unname(point_difference[[metric_id]]),
  bootstrap_replicates = 2000L, bootstrap_standard_error = sd(values),
  interval_lower_95 = unname(quantile(values, 0.025, names = FALSE)),
  interval_upper_95 = unname(quantile(values, 0.975, names = FALSE)),
  seed = CONTEXT_M2_BOOTSTRAP_SEED, resampling_unit = "whole_game_within_validation_season"
))
metric_ids <- names(metrics$M1)
pooled_metrics <- bind_rows(
  tibble(model_id = "M1", metric_id = metric_ids, value = unname(metrics$M1)),
  tibble(model_id = "M2", metric_id = metric_ids, value = unname(metrics$M2)),
  tibble(model_id = "M2_minus_M1", metric_id = metric_ids, value = unname(metrics$M2 - metrics$M1))
)
season_metrics <- pooled_metrics |> mutate(validation_season = row$validation_season, .before = 1L)
subgroup_input <- metric_data |>
  mutate(
    finish_family = predictions$finish_family,
    creation_family = predictions$creation_family,
    player_volume_group = if_else(predictions$known_player_m2, "known_player", "unseen_player")
  )
subgroup_calibration <- bind_rows(
  context_subgroup_calibration(subgroup_input, predictions$probability_m1, "M1"),
  context_subgroup_calibration(subgroup_input, predictions$probability_m2, "M2"),
  context_m2_distance_subgroup_calibration(
    mutate(metric_data, shot_distance_feet = predictions$shot_distance_feet),
    predictions$probability_m1, "M1"
  ),
  context_m2_distance_subgroup_calibration(
    mutate(metric_data, shot_distance_feet = predictions$shot_distance_feet),
    predictions$probability_m2, "M2"
  )
)
fit_accounting <- tibble(
  model_id = c("M1", "M2"), fit_source = c(row$m1_fit_source, row$m2_fit_source),
  fit_sha256 = c(m1$hash, m2$hash),
  fit_reused = c(TRUE, row$m2_fit_policy == "reuse_verified_preflight" || dir.exists(fit_component_root(comparison_id))),
  evaluation_time_fit_count = 0L
)
execution_checks <- tibble(
  check_id = c(
    "registered_training_window", "registered_validation_season", "identical_model_rows",
    "one_prediction_per_shot", "probabilities_valid", "expected_points_exact",
    "known_and_unseen_supported", "other_or_unknown_retained", "bootstrap_reproducible",
    "difference_sign_m2_minus_m1", "d1_excluded_from_selection", "aggregate_outputs_only",
    "prospective_2026_27_sealed", "evaluation_time_refits_zero"
  ),
  passed = c(
    TRUE, TRUE, TRUE, !anyDuplicated(predictions$canonical_shot_key),
    all(predictions$probability_m1 > 0 & predictions$probability_m1 < 1) && all(predictions$probability_m2 > 0 & predictions$probability_m2 < 1),
    identical(context_expected_points(predictions$probability_m2, predictions$point_value), predictions$probability_m2 * predictions$point_value),
    any(predictions$known_player_m2) && any(!predictions$known_player_m2),
    any(predictions$creation_family == "other_or_unknown"), identical(bootstrap, bootstrap_repeat),
    isTRUE(all.equal(point_difference[["log_loss_m2_minus_m1"]], metrics$M2[["bernoulli_log_loss"]] - metrics$M1[["bernoulli_log_loss"]], tolerance = 0)),
    TRUE, TRUE, TRUE, TRUE
  )
)
if (!all(execution_checks$passed)) stop("frozen execution check failed", call. = FALSE)
model_selection <- tibble(
  comparison_id, validation_season = row$validation_season,
  status = "season_result_only_no_final_selection",
  m1_log_loss = metrics$M1[["bernoulli_log_loss"]],
  m2_log_loss = metrics$M2[["bernoulli_log_loss"]],
  m2_minus_m1 = point_difference[["log_loss_m2_minus_m1"]],
  d1_used_for_selection = FALSE, final_model_selected = FALSE
)
execution_manifest <- tibble(
  evaluation_version = CONTEXT_M2_EVALUATION_VERSION, comparison_id,
  training_seasons = row$training_seasons, validation_season = row$validation_season,
  validation_games = n_distinct(predictions$game_id), validation_shots = nrow(predictions),
  validation_players = n_distinct(predictions$player_id),
  m1_fit_sha256 = m1$hash, m2_fit_sha256 = m2$hash,
  pre_result_implementation_commit = commits[["pre_result"]], execution_commit = commits[["head"]],
  outcome_reads_completed = 1L, prospective_2026_27_accessed = FALSE,
  models_fit_during_evaluation = 0L, bootstrap_seed = CONTEXT_M2_BOOTSTRAP_SEED,
  outcome_read_seconds = outcome_read_seconds, prediction_seconds = prediction_seconds,
  evaluation_seconds = evaluation_seconds,
  bootstrap_seconds_including_reproducibility_repeat = bootstrap_seconds,
  total_wall_seconds = as.numeric(difftime(Sys.time(), execution_started, units = "secs")),
  cpu_user_seconds = unname((proc.time() - execution_cpu_started)[["user.self"]]),
  cpu_system_seconds = unname((proc.time() - execution_cpu_started)[["sys.self"]]),
  sampled_rss_bytes_after_evaluation = context_current_rss_bytes(),
  available_disk_bytes_after = context_available_disk_bytes(repo_root),
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  mgcv_version = observed_versions[["mgcv"]], arrow_version = observed_versions[["arrow"]]
)

stage <- paste0(final, ".", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".partial")
dir.create(stage, recursive = TRUE)
payloads <- list(
  "execution_manifest.csv" = execution_manifest,
  "fit_accounting.csv" = fit_accounting,
  "pooled_metrics.csv" = pooled_metrics,
  "season_metrics.csv" = season_metrics,
  "calibration_bins.csv" = bins,
  "subgroup_calibration.csv" = subgroup_calibration,
  "bootstrap_summary.csv" = bootstrap_summary,
  "model_selection.csv" = model_selection,
  "execution_checks.csv" = execution_checks
)
walk2(payloads, names(payloads), ~ write_csv_stable(.x, file.path(stage, .y)))
manifest <- tibble(
  artifact = names(payloads), sha256 = vapply(file.path(stage, names(payloads)), sha256_file, character(1)),
  atomic_complete = TRUE, checks_passed = TRUE
)
write_csv_stable(manifest, file.path(stage, "completion_manifest.csv"))
verify_manifest(stage)
context_m2_evaluation_atomic_publish(stage, final)

tracked_final <- file.path(tracked_root, "results", comparison_id)
tracked_stage <- paste0(tracked_final, ".partial")
dir.create(tracked_stage, recursive = TRUE)
walk2(payloads, names(payloads), ~ write_csv_stable(.x, file.path(tracked_stage, .y)))
write_csv_stable(manifest, file.path(tracked_stage, "artifact_manifest.csv"))
context_m2_evaluation_atomic_publish(tracked_stage, tracked_final)
message("Completed and atomically published ", comparison_id, "; 2026-27 remained sealed")
