#!/usr/bin/env Rscript

# Deep verification of completed training-only M0/M1 checkpoints. This script
# cannot fit a model and loads only the two training-season partitions.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(mgcv)
  library(purrr)
  library(readr)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) {
  sub("^--file=", "", script_arg)
} else {
  "R/context_edition_m0_m1_checkpoint_verify.R"
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
checkpoint_root <- file.path(
  repo_root, "data", "cache", "context_edition_m0_m1_preflight",
  "context_m0_m1_preflight_v0.1.0"
)
output_path <- file.path(
  repo_root, "data", "processed", "context_edition_validation_data_preflight_v0_1",
  "postflight_verification.csv"
)
if (file.exists(output_path)) stop("postflight verification already exists", call. = FALSE)

manifest <- read_csv(file.path(checkpoint_root, "completion_manifest.csv"), show_col_types = FALSE)
context_preflight_verify_manifest(manifest, checkpoint_root, sha256_file)

fits <- list(
  M0 = readRDS(file.path(checkpoint_root, "m0_fit.rds")),
  M1 = readRDS(file.path(checkpoint_root, "m1_fit.rds"))
)
if (any(vapply(fits, function(fit) !inherits(fit, "gam"), logical(1)))) {
  stop("checkpoint does not contain two gam objects", call. = FALSE)
}

training_paths <- file.path(
  canonical_root,
  paste0("season=", CONTEXT_PREFLIGHT_TRAINING_SEASONS),
  "canonical_shots.parquet"
)
required <- c(
  "season", "player_id", "point_value", "finish_family",
  "creation_family", "field_goal_made"
)
training <- map_dfr(training_paths, function(path) {
  read_parquet(path, col_select = all_of(required), as_data_frame = TRUE)
})
if (!identical(sort(unique(training$season)), CONTEXT_PREFLIGHT_TRAINING_SEASONS)) {
  stop("non-training data entered checkpoint verification", call. = FALSE)
}

levels_frozen <- context_factor_levels()
player_levels <- sort(unique(as.character(training$player_id)))
training <- training |>
  mutate(
    player_id_factor = factor(as.character(player_id), levels = player_levels),
    point_value_factor = factor(
      if_else(point_value == 2L, "two", "three"),
      levels = levels_frozen$point_value_factor
    ),
    finish_family = factor(finish_family, levels = levels_frozen$finish_family),
    creation_family = factor(creation_family, levels = levels_frozen$creation_family)
  ) |>
  select(-player_id)

verify_one <- function(model_id) {
  fit <- fits[[model_id]]
  grouped <- context_preflight_group_counts(training, model_id)
  grouped_probability <- as.numeric(predict(fit, newdata = grouped, type = "response"))
  grouped$.group_probability <- grouped_probability
  keys <- context_preflight_group_keys(model_id)

  representatives <- training |>
    group_by(across(all_of(keys)), .drop = TRUE) |>
    slice_head(n = 1L) |>
    ungroup() |>
    arrange(across(all_of(keys)))
  direct_probability <- as.numeric(predict(fit, newdata = representatives, type = "response"))
  mapped <- representatives |>
    left_join(
      grouped |> select(all_of(keys), .group_probability),
      by = keys,
      relationship = "many-to-one"
    )
  mapping_max_difference <- max(abs(direct_probability - mapped$.group_probability))

  random_names <- names(coef(fit))[grepl("s\\(player_id_factor\\)", names(coef(fit)))]
  random_coefficients <- unname(coef(fit)[random_names])
  if (length(random_coefficients) != 700L || any(!is.finite(random_coefficients))) {
    stop(model_id, " player deviations are incomplete", call. = FALSE)
  }

  first <- grouped[1L, , drop = FALSE]
  known_full <- as.numeric(predict(fit, newdata = first, type = "response"))
  known_fixed <- as.numeric(context_preflight_fixed_prediction(fit, first))

  tibble(
    model_id = model_id,
    checkpoint_hash_verified = TRUE,
    models_refit = 0L,
    training_seasons = paste(CONTEXT_PREFLIGHT_TRAINING_SEASONS, collapse = ";"),
    validation_outcomes_accessed = FALSE,
    player_deviation_count = length(random_coefficients),
    nonzero_player_deviation_count = sum(abs(random_coefficients) > 1e-12),
    minimum_player_deviation = min(random_coefficients),
    maximum_player_deviation = max(random_coefficients),
    known_player_full_minus_fixed_probability = known_full - known_fixed,
    representative_groups_checked = nrow(representatives),
    grouped_to_representative_max_probability_difference = mapping_max_difference,
    grouped_prediction_mapping_passed = mapping_max_difference <= 1e-13,
    all_checks_passed = length(random_coefficients) == 700L &&
      any(abs(random_coefficients) > 1e-12) && mapping_max_difference <= 1e-13
  )
}

verification <- bind_rows(verify_one("M0"), verify_one("M1"))
if (!all(verification$all_checks_passed)) {
  stop("postflight checkpoint verification failed", call. = FALSE)
}

temp_path <- tempfile(
  pattern = "postflight_verification_",
  tmpdir = dirname(output_path), fileext = ".csv"
)
write_csv(verification, temp_path, na = "", quote = "needed")
if (!file.rename(temp_path, output_path)) stop("atomic verification publication failed", call. = FALSE)
message("Completed checkpoint verified without refitting")
