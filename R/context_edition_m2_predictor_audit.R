#!/usr/bin/env Rscript

# Predictor-only audit for the M2 nonlinear-distance preregistration.
# The selected columns intentionally exclude makes, misses, and every outcome.

options(stringsAsFactors = FALSE)
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_predictor_audit.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)

seasons <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
canonical_paths <- file.path(canonical_root, paste0("season=", seasons), "canonical_shots.parquet")
if (!all(file.exists(canonical_paths))) stop("a registered canonical partition is missing", call. = FALSE)

predictor_fields <- c(
  "season", "player_id", "point_value", "finish_family", "creation_family",
  "shot_distance_feet", "location_x_tenths_feet", "location_y_tenths_feet"
)

shots <- arrow::open_dataset(canonical_paths) |>
  select(all_of(predictor_fields)) |>
  collect() |>
  mutate(
    coordinate_distance_feet = sqrt(
      location_x_tenths_feet^2 + location_y_tenths_feet^2
    ) / 10,
    signed_distance_gap_feet = shot_distance_feet - coordinate_distance_feet,
    absolute_distance_gap_feet = abs(signed_distance_gap_feet),
    coordinate_distance_floor = floor(coordinate_distance_feet),
    distance_band = context_m2_distance_band(shot_distance_feet)
  )

if (!identical(sort(unique(shots$season)), sort(seasons))) stop("season scope changed", call. = FALSE)
context_m2_validate_distance(shots$shot_distance_feet)
if (anyNA(shots$location_x_tenths_feet) || anyNA(shots$location_y_tenths_feet)) {
  stop("coordinate audit fields contain missing values", call. = FALSE)
}

overall <- shots |>
  summarise(
    canonical_schema = "context_field_goal_v0.1.2",
    source_field = "ShotChartDetail SHOT_DISTANCE",
    source_unit = "whole feet",
    rows = n(),
    seasons = n_distinct(season),
    players = n_distinct(player_id),
    recorded_missing = sum(is.na(shot_distance_feet)),
    coordinate_missing = sum(is.na(location_x_tenths_feet) | is.na(location_y_tenths_feet)),
    recorded_min_feet = min(shot_distance_feet),
    recorded_max_feet = max(shot_distance_feet),
    coordinate_min_feet = min(coordinate_distance_feet),
    coordinate_max_feet = max(coordinate_distance_feet),
    recorded_noninteger = sum(shot_distance_feet != floor(shot_distance_feet)),
    floor_match_rows = sum(shot_distance_feet == coordinate_distance_floor),
    floor_match_share = mean(shot_distance_feet == coordinate_distance_floor),
    absolute_gap_mean_feet = mean(absolute_distance_gap_feet),
    absolute_gap_median_feet = median(absolute_distance_gap_feet),
    absolute_gap_p95_feet = unname(quantile(absolute_distance_gap_feet, 0.95)),
    absolute_gap_max_feet = max(absolute_distance_gap_feet),
    within_one_foot_share = mean(absolute_distance_gap_feet <= 1),
    impossible_recorded_rows = sum(
      shot_distance_feet < CONTEXT_M2_DISTANCE_MIN |
        shot_distance_feet > CONTEXT_M2_DISTANCE_MAX
    ),
    outcomes_selected = FALSE,
    prospective_2026_27_accessed = FALSE
  )

by_season <- shots |>
  group_by(season) |>
  summarise(
    rows = n(),
    players = n_distinct(player_id),
    unique_recorded_distances = n_distinct(shot_distance_feet),
    recorded_min_feet = min(shot_distance_feet),
    recorded_max_feet = max(shot_distance_feet),
    coordinate_max_feet = max(coordinate_distance_feet),
    recorded_mean_feet = mean(shot_distance_feet),
    coordinate_mean_feet = mean(coordinate_distance_feet),
    absolute_gap_mean_feet = mean(absolute_distance_gap_feet),
    absolute_gap_p95_feet = unname(quantile(absolute_distance_gap_feet, 0.95)),
    floor_match_share = mean(shot_distance_feet == coordinate_distance_floor),
    within_one_foot_share = mean(absolute_distance_gap_feet <= 1),
    three_point_min_feet = min(shot_distance_feet[point_value == 3L]),
    three_point_max_feet = max(shot_distance_feet[point_value == 3L]),
    two_point_max_feet = max(shot_distance_feet[point_value == 2L]),
    .groups = "drop"
  ) |>
  arrange(season)

band_support <- shots |>
  count(season, distance_band, name = "shots") |>
  group_by(season) |>
  mutate(share = shots / sum(shots)) |>
  ungroup() |>
  arrange(season, distance_band)

point_distance_overlap <- bind_rows(
  shots |>
    group_by(point_value) |>
    summarise(
      diagnostic = "point_value_distance_range",
      rows = n(),
      recorded_min_feet = min(shot_distance_feet),
      recorded_max_feet = max(shot_distance_feet),
      coordinate_min_feet = min(coordinate_distance_feet),
      coordinate_max_feet = max(coordinate_distance_feet),
      .groups = "drop"
    ),
  shots |>
    filter(point_value == 3L, abs(location_x_tenths_feet) >= 220L, shot_distance_feet == 22L) |>
    summarise(
      point_value = 3L,
      diagnostic = "22_foot_corner_three_geometry",
      rows = n(),
      recorded_min_feet = min(shot_distance_feet),
      recorded_max_feet = max(shot_distance_feet),
      coordinate_min_feet = min(coordinate_distance_feet),
      coordinate_max_feet = max(coordinate_distance_feet)
    ),
  shots |>
    filter(point_value == 2L, shot_distance_feet >= 22L) |>
    summarise(
      point_value = 2L,
      diagnostic = "two_point_attempts_at_least_22_feet",
      rows = n(),
      recorded_min_feet = min(shot_distance_feet),
      recorded_max_feet = max(shot_distance_feet),
      coordinate_min_feet = min(coordinate_distance_feet),
      coordinate_max_feet = max(coordinate_distance_feet)
    )
)

boundary_counts <- shots |>
  filter(shot_distance_feet >= 20L, shot_distance_feet <= 25L) |>
  count(shot_distance_feet, point_value, name = "shots") |>
  arrange(shot_distance_feet, point_value)

splits <- list(
  development_1 = c("2021-22", "2022-23"),
  development_2 = c("2021-22", "2022-23", "2023-24"),
  development_3 = c("2021-22", "2022-23", "2023-24", "2024-25")
)

grouping <- bind_rows(lapply(names(splits), function(comparison_id) {
  training <- filter(shots, season %in% splits[[comparison_id]])
  d1_rows <- training |>
    distinct(player_id, point_value, shot_distance_feet) |>
    nrow()
  m2_rows <- training |>
    distinct(player_id, point_value, finish_family, creation_family, shot_distance_feet) |>
    nrow()
  players <- n_distinct(training$player_id)
  tibble(
    comparison_id = comparison_id,
    training_seasons = paste(splits[[comparison_id]], collapse = ";"),
    training_shots = nrow(training),
    players = players,
    training_distance_min = min(training$shot_distance_feet),
    training_distance_max = max(training$shot_distance_feet),
    d1_grouped_rows = d1_rows,
    m2_grouped_rows = m2_rows,
    d1_nominal_coefficients = players + 11L,
    m2_nominal_coefficients = players + 20L,
    smooth_terms_each = 2L,
    distance_basis_dimension = CONTEXT_M2_INITIAL_K,
    distance_centered_coefficients = CONTEXT_M2_INITIAL_K - 1L,
    smoothing_parameters_each = 2L
  )
}))

computation <- grouping |>
  transmute(
    comparison_id,
    training_shots,
    players,
    d1_grouped_rows,
    m2_grouped_rows,
    d1_nominal_coefficients,
    m2_nominal_coefficients,
    d1_runtime_estimate = c("2-8 minutes", "3-10 minutes", "4-15 minutes"),
    m2_runtime_estimate = c("5-20 minutes", "8-30 minutes", "12-45 minutes"),
    peak_memory_estimate = c("1-4 GB", "2-5 GB", "3-6 GB"),
    serialized_checkpoint_estimate = c("20-50 MB", "25-60 MB", "30-70 MB"),
    estimate_basis = c(
      "M1 measured 104.7 s at 9,328 rows; distance raises grouped rows to 57,190 but adds only 9 coefficients",
      "M1 measured 159.7 s at 10,852 rows; distance raises grouped rows to 69,649 but adds only 9 coefficients",
      "M1 measured 274.6 s at 12,415 rows; distance raises grouped rows to 81,746 but adds only 9 coefficients"
    ),
    estimate_only = TRUE
  )

audit <- tibble(
  check_id = c(
    "exact_source_scope", "five_seasons_only", "predictor_fields_only",
    "distance_complete", "coordinates_complete", "distance_range_valid",
    "recorded_equals_coordinate_floor", "agreement_within_one_foot",
    "corner_three_distance_overlap", "long_two_distance_overlap",
    "heaves_retained", "model_fits_created", "historical_outcomes_analyzed",
    "prospective_2026_27_accessed", "shot_level_rows_written"
  ),
  passed = c(
    nrow(shots) == 1091329L,
    identical(sort(unique(shots$season)), sort(seasons)),
    identical(sort(names(select(shots, all_of(predictor_fields)))), sort(predictor_fields)),
    !anyNA(shots$shot_distance_feet),
    !anyNA(shots$location_x_tenths_feet) && !anyNA(shots$location_y_tenths_feet),
    all(shots$shot_distance_feet >= 0L & shots$shot_distance_feet <= 100L),
    all(shots$shot_distance_feet == shots$coordinate_distance_floor),
    all(shots$absolute_distance_gap_feet <= 1),
    any(shots$point_value == 3L & shots$shot_distance_feet == 22L),
    any(shots$point_value == 2L & shots$shot_distance_feet >= 22L),
    any(shots$shot_distance_feet >= 30L),
    TRUE, TRUE, TRUE, TRUE
  ),
  observed = c(
    as.character(nrow(shots)), paste(sort(unique(shots$season)), collapse = ";"),
    paste(predictor_fields, collapse = ";"), as.character(sum(is.na(shots$shot_distance_feet))),
    as.character(sum(is.na(shots$location_x_tenths_feet) | is.na(shots$location_y_tenths_feet))),
    paste(range(shots$shot_distance_feet), collapse = ";"),
    as.character(sum(shots$shot_distance_feet == shots$coordinate_distance_floor)),
    format(max(shots$absolute_distance_gap_feet), digits = 16),
    as.character(sum(
      shots$point_value == 3L & abs(shots$location_x_tenths_feet) >= 220L &
        shots$shot_distance_feet == 22L
    )),
    as.character(sum(shots$point_value == 2L & shots$shot_distance_feet >= 22L)),
    as.character(sum(shots$shot_distance_feet >= 30L)),
    "0", "0", "FALSE", "0"
  ),
  expected = c(
    "1091329", paste(seasons, collapse = ";"), paste(predictor_fields, collapse = ";"),
    "0", "0", "0;100 guard", "all rows", "maximum <= 1 foot",
    "positive count", "positive count", "positive count", "0", "0", "FALSE", "0"
  )
)
if (!all(audit$passed)) stop("a predictor-only distance audit check failed", call. = FALSE)

output_dir <- file.path(repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write_atomic <- function(data, filename) {
  destination <- file.path(output_dir, filename)
  temporary <- tempfile(pattern = paste0(filename, "_"), tmpdir = output_dir)
  readr::write_csv(data, temporary, na = "")
  if (!file.rename(temporary, destination)) stop("atomic publish failed for ", filename, call. = FALSE)
}

write_atomic(overall, "distance_audit_overall.csv")
write_atomic(by_season, "distance_audit_by_season.csv")
write_atomic(band_support, "distance_band_support.csv")
write_atomic(point_distance_overlap, "point_distance_overlap.csv")
write_atomic(boundary_counts, "point_value_boundary_counts.csv")
write_atomic(grouping, "grouping_dimensions.csv")
write_atomic(computation, "computational_estimate.csv")
write_atomic(audit, "pre_registration_audit.csv")

message("Predictor-only M2 distance audit passed; no outcomes were selected.")
