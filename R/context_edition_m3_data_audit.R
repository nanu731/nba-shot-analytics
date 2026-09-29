#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(purrr)
  library(readr)
  library(tidyr)
})

protocol_version <- "context_m3_data_audit_v0.1.0"
expected_seasons <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
allowed_columns <- c(
  "season", "period", "minutes_remaining", "seconds_remaining",
  "shooter_home_away", "score_margin_before", "pre_shot_score_verified",
  "linkage_status", "score_sequence_agrees", "pbp_candidate_count",
  "shot_clock_player_count"
)
blocked_names <- c(
  "field_goal_made", "realized_field_goal_points", "raw_pbp_description",
  "pbp_made", "pbp_point_observed", "result_disagreement", "player_id",
  "player_name", "source_game_id", "source_event_id"
)

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(result) != 1L) stop("Could not hash ", path)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

write_csv_stable <- function(data, path) {
  write_csv(data, path, na = "", quote = "needed")
}

guard_predictor_frame <- function(data) {
  if (!identical(names(data), allowed_columns)) stop("Predictor allowlist changed")
  if (any(names(data) %in% blocked_names)) stop("Blocked column entered the audit")
  observed <- sort(unique(data$season))
  if (!identical(observed, sort(expected_seasons))) stop("Historical season set changed")
  if (any(data$season == "2026-27")) stop("2026-27 is sealed")
  if (anyNA(data$period) || anyNA(data$minutes_remaining) || anyNA(data$seconds_remaining)) {
    stop("ShotChartDetail period clock must be complete")
  }
  if (any(data$period < 1L) || any(data$period > 10L)) stop("Period is out of range")
  if (any(data$minutes_remaining < 0L) || any(data$minutes_remaining > 12L) ||
      any(data$seconds_remaining < 0L) || any(data$seconds_remaining > 59L)) {
    stop("Period clock is out of range")
  }
  if (any(!data$pre_shot_score_verified & !is.na(data$score_margin_before))) {
    stop("Unverified rows must not expose score margin")
  }
  if (any(data$pre_shot_score_verified & is.na(data$score_margin_before))) {
    stop("Verified score rows must expose score margin")
  }
  invisible(data)
}

prepare_predictors <- function(data) {
  guard_predictor_frame(data)
  data |>
    mutate(
      period_seconds_remaining = minutes_remaining * 60L + seconds_remaining,
      period_group = if_else(period <= 4L, as.character(period), "OT"),
      home_away_available = !is.na(shooter_home_away),
      score_available = pre_shot_score_verified & !is.na(score_margin_before)
    )
}

quantile_value <- function(x, probability) {
  as.numeric(quantile(x, probability, na.rm = TRUE, names = FALSE, type = 7))
}

build_tables <- function(data, input_manifest, field_register) {
  prepared <- prepare_predictors(data)
  total_by_season <- prepared |> count(season, name = "rows")

  missing_fields <- c(
    "period", "period_seconds_remaining", "shooter_home_away",
    "score_margin_before"
  )
  missingness <- prepared |>
    group_by(season) |>
    summarise(
      rows = n(),
      across(all_of(missing_fields), ~ sum(is.na(.x))),
      .groups = "drop"
    ) |>
    pivot_longer(all_of(missing_fields), names_to = "field", values_to = "missing_rows") |>
    mutate(missing_share = missing_rows / rows) |>
    arrange(season, field)

  linkage_missingness <- prepared |>
    group_by(season, linkage_status) |>
    summarise(
      rows = n(),
      home_away_missing_rows = sum(!home_away_available),
      score_missing_rows = sum(!score_available),
      home_away_missing_share = mean(!home_away_available),
      score_missing_share = mean(!score_available),
      .groups = "drop"
    ) |>
    arrange(season, linkage_status)

  period_support <- prepared |>
    count(season, period_group, name = "rows") |>
    left_join(total_by_season, by = "season") |>
    mutate(share = rows.x / rows.y) |>
    transmute(season, period_group, rows = rows.x, share) |>
    arrange(season, period_group)

  clock_support <- prepared |>
    group_by(season) |>
    summarise(
      rows = n(),
      minimum_seconds_remaining = min(period_seconds_remaining),
      p01_seconds_remaining = quantile_value(period_seconds_remaining, 0.01),
      median_seconds_remaining = quantile_value(period_seconds_remaining, 0.5),
      p99_seconds_remaining = quantile_value(period_seconds_remaining, 0.99),
      maximum_seconds_remaining = max(period_seconds_remaining),
      zero_clock_rows = sum(period_seconds_remaining == 0L),
      .groups = "drop"
    )

  score_support <- prepared |>
    group_by(season) |>
    summarise(
      rows = n(),
      available_rows = sum(score_available),
      missing_rows = sum(!score_available),
      available_share = mean(score_available),
      minimum_margin = min(score_margin_before, na.rm = TRUE),
      p01_margin = quantile_value(score_margin_before, 0.01),
      p05_margin = quantile_value(score_margin_before, 0.05),
      median_margin = quantile_value(score_margin_before, 0.5),
      p95_margin = quantile_value(score_margin_before, 0.95),
      p99_margin = quantile_value(score_margin_before, 0.99),
      maximum_margin = max(score_margin_before, na.rm = TRUE),
      .groups = "drop"
    )

  timing_checks <- tibble(
    check = c(
      "allowed_columns_only", "historical_seasons_only", "period_clock_complete",
      "score_requires_verification", "verified_score_is_present",
      "score_sequence_disagreements_hidden", "no_outcome_access", "no_model_fit"
    ),
    status = "pass",
    measured_value = c(
      paste(allowed_columns, collapse = ";"), paste(expected_seasons, collapse = ";"),
      as.character(sum(is.na(prepared$period_seconds_remaining))),
      as.character(sum(!prepared$pre_shot_score_verified & !is.na(prepared$score_margin_before))),
      as.character(sum(prepared$pre_shot_score_verified & is.na(prepared$score_margin_before))),
      as.character(sum(prepared$score_sequence_agrees %in% FALSE & !is.na(prepared$score_margin_before))),
      "field_goal_made and realized points not selected", "0"
    )
  )
  if (timing_checks$measured_value[[6]] != "0") stop("Disagreed score sequence exposed a margin")

  missing_data_options <- tribble(
    ~strategy, ~status_after_audit, ~reason,
    "complete_case", "retain_as_diagnostic", "honest observed context but discards every failed or unavailable join and changes the evaluation sample",
    "neutral_fill_plus_missingness_indicator", "preferred_simple_candidate_for_preregistration", "predicts every shot while separating unavailable context from a real tied score; filled values are not interpreted as recovered states",
    "predictive_mean_matching", "do_not_advance_without_separate_evidence", "join failure is not an ordinary missing numeric measurement; added complexity needs a future-season benefit before use",
    "silent_mean_or_median_fill", "reject", "without a missingness indicator the model would treat fabricated margins as observed game state"
  )

  readiness <- tibble(
    item = c("period", "period_clock", "home_away", "score_margin", "direct_defense", "shot_clock", "M3_fit"),
    decision = c("go", "go", "conditional_go_with_unknown", "conditional_go_with_missing_indicator", "no_go", "no_go", "not_authorized"),
    note = c(
      "complete ShotChartDetail field", "complete ShotChartDetail field; functional form remains unfrozen",
      "use exact-match side only and retain unknown", "use only verified lagged score; compare complete-case diagnostic with explicit missingness treatment",
      "no verified same-attempt source", "no verified same-attempt source", "freeze formula and decision rule separately before fitting"
    )
  )

  list(
    input_manifest.csv = input_manifest,
    candidate_field_register.csv = field_register,
    missingness_by_season.csv = missingness,
    missingness_by_linkage.csv = linkage_missingness,
    period_support.csv = period_support,
    clock_support.csv = clock_support,
    score_margin_support.csv = score_support,
    timing_checks.csv = timing_checks,
    missing_data_options.csv = missing_data_options,
    readiness.csv = readiness
  )
}

run_synthetic_tests <- function() {
  sample <- tibble(
    season = rep(expected_seasons, each = 2), period = rep(c(1L, 5L), 5),
    minutes_remaining = 11L, seconds_remaining = rep(c(59L, 0L), 5),
    shooter_home_away = rep(c("home", NA_character_), 5),
    score_margin_before = rep(c(0L, NA_integer_), 5),
    pre_shot_score_verified = rep(c(TRUE, FALSE), 5),
    linkage_status = rep(c("unique_exact", "unmatched_event"), 5),
    score_sequence_agrees = rep(c(TRUE, NA), 5),
    pbp_candidate_count = rep(c(1L, 0L), 5),
    shot_clock_player_count = 1L
  )
  prepared <- prepare_predictors(sample)
  stopifnot(identical(prepared$period_seconds_remaining[1:2], c(719L, 660L)))
  synthetic_tables <- build_tables(
    sample,
    tibble(source = "synthetic"),
    tibble(field = "synthetic")
  )
  stopifnot(nrow(synthetic_tables$missingness_by_season.csv) == 20L)
  bad_season <- sample
  bad_season$season[[1]] <- "2026-27"
  stopifnot(inherits(try(guard_predictor_frame(bad_season), silent = TRUE), "try-error"))
  bad_score <- sample
  bad_score$score_margin_before[[2]] <- 3L
  stopifnot(inherits(try(guard_predictor_frame(bad_score), silent = TRUE), "try-error"))
  bad_clock <- sample
  bad_clock$seconds_remaining[[1]] <- 60L
  stopifnot(inherits(try(guard_predictor_frame(bad_clock), silent = TRUE), "try-error"))
  message("Synthetic M3 predictor-audit checks passed")
}

mode <- if (length(commandArgs(trailingOnly = TRUE))) commandArgs(trailingOnly = TRUE)[[1]] else "test"
if (!mode %in% c("test", "run", "verify")) stop("Use test, run, or verify")
run_synthetic_tests()
if (mode == "test") quit(status = 0L)

repo_root <- normalizePath(".", mustWork = TRUE)
canonical_root <- file.path(repo_root, "data", "cache", "context_edition_canonical", "context_field_goal_v0.1.2__2021-22_to_2025-26")
canonical_path <- file.path(canonical_root, "canonical_shots.parquet")
completion_path <- file.path(canonical_root, "completion_manifest.csv")
field_path <- file.path(repo_root, "config", "context_edition_m3_candidate_fields_v0_1.csv")
output_dir <- file.path(repo_root, "data", "processed", "context_edition_m3_data_audit_v0_1")

if (!all(file.exists(c(canonical_path, completion_path, field_path)))) stop("Missing frozen audit input")
completion <- read_csv(completion_path, show_col_types = FALSE)
canonical_row <- completion |> filter(artifact == "canonical_shots.parquet")
if (nrow(canonical_row) != 1L || canonical_row$sha256 != sha256_file(canonical_path) ||
    canonical_row$schema_version != "context_field_goal_v0.1.2" ||
    !canonical_row$checks_passed || !canonical_row$atomic_complete) stop("Canonical manifest verification failed")

if (mode == "verify") {
  manifest_path <- file.path(output_dir, "output_manifest.csv")
  if (!file.exists(manifest_path)) stop("No completed M3 audit bundle")
  manifest <- read_csv(manifest_path, show_col_types = FALSE)
  for (index in seq_len(nrow(manifest))) {
    path <- file.path(output_dir, manifest$file[[index]])
    if (!file.exists(path) || sha256_file(path) != manifest$sha256[[index]]) stop("M3 audit output hash failed: ", path)
  }
  message("Completed M3 predictor-audit bundle verified")
  quit(status = 0L)
}

if (dir.exists(output_dir)) stop("M3 audit output exists; verify instead of overwriting")
field_register <- read_csv(field_path, show_col_types = FALSE)
dataset <- read_parquet(canonical_path, col_select = all_of(allowed_columns), as_data_frame = TRUE)
guard_predictor_frame(dataset)
input_manifest <- tibble(
  source = c("canonical predictor file", "canonical completion manifest", "frozen candidate-field register", "audit implementation"),
  file = c(
    file.path("data", "cache", "context_edition_canonical", "context_field_goal_v0.1.2__2021-22_to_2025-26", "canonical_shots.parquet"),
    file.path("data", "cache", "context_edition_canonical", "context_field_goal_v0.1.2__2021-22_to_2025-26", "completion_manifest.csv"),
    file.path("config", basename(field_path)), file.path("R", "context_edition_m3_data_audit.R")
  ),
  bytes = file.info(c(canonical_path, completion_path, field_path, file.path(repo_root, "R", "context_edition_m3_data_audit.R")))$size,
  sha256 = map_chr(c(canonical_path, completion_path, field_path, file.path(repo_root, "R", "context_edition_m3_data_audit.R")), sha256_file),
  outcome_columns_accessed = FALSE,
  contains_2026_27 = FALSE
)

tables_a <- build_tables(dataset, input_manifest, field_register)
tables_b <- build_tables(dataset, input_manifest, field_register)
if (!identical(tables_a, tables_b)) stop("Repeated M3 audit calculation differed")

attempt <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
stage_a <- file.path(dirname(output_dir), paste0(".m3-a-", attempt))
stage_b <- file.path(dirname(output_dir), paste0(".m3-b-", attempt))
dir.create(stage_a, recursive = TRUE, showWarnings = FALSE)
dir.create(stage_b, recursive = TRUE, showWarnings = FALSE)
walk2(tables_a, names(tables_a), ~ write_csv_stable(.x, file.path(stage_a, .y)))
walk2(tables_b, names(tables_b), ~ write_csv_stable(.x, file.path(stage_b, .y)))
files <- sort(names(tables_a))
hashes_a <- map_chr(file.path(stage_a, files), sha256_file)
hashes_b <- map_chr(file.path(stage_b, files), sha256_file)
if (!identical(hashes_a, hashes_b)) stop("Repeated M3 audit serialization differed")

determinism <- tibble(
  check = c("repeated_calculation", "repeated_serialization", "model_fits", "outcome_columns_accessed", "prospective_season_accessed"),
  status = "pass", measured_value = c("identical", "byte-identical", "0", "FALSE", "FALSE")
)
walk(c(stage_a, stage_b), ~ write_csv_stable(determinism, file.path(.x, "determinism.csv")))
files <- sort(c(files, "determinism.csv"))
manifest <- tibble(
  file = files, bytes = file.info(file.path(stage_a, files))$size,
  sha256 = map_chr(file.path(stage_a, files), sha256_file),
  contains_shot_level_rows = FALSE, contains_identifiers = FALSE,
  protocol_version = .env$protocol_version
)
write_csv_stable(manifest, file.path(stage_a, "output_manifest.csv"))
write_csv_stable(manifest, file.path(stage_b, "output_manifest.csv"))
if (!identical(sha256_file(file.path(stage_a, "output_manifest.csv")), sha256_file(file.path(stage_b, "output_manifest.csv")))) {
  stop("Repeated output manifests differed")
}
if (!file.rename(stage_a, output_dir)) stop("Could not publish M3 audit bundle atomically")
unlink(stage_b, recursive = TRUE)
message("M3 predictor-data audit completed without model or outcome access")
