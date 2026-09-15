#!/usr/bin/env Rscript

# Structural and fully synthetic tests. This script cannot read real shot data.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
})

options(stringsAsFactors = FALSE)
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_first_validation_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)

results <- list()
record <- function(test_id, expression) {
  passed <- TRUE
  detail <- "passed"
  tryCatch(force(expression), error = function(error) {
    passed <<- FALSE
    detail <<- conditionMessage(error)
  })
  results[[length(results) + 1L]] <<- tibble(test_id = test_id, passed = passed, detail = detail)
}
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

config <- read_csv(file.path(repo_root, "config", "context_edition_first_validation_v0_1.csv"), show_col_types = FALSE)
values <- setNames(config$value, config$key)
runner <- paste(readLines(file.path(repo_root, "R", "context_edition_first_validation.R"), warn = FALSE), collapse = "\n")

record("frozen_split", {
  expect_true(values[["training_seasons"]] == "2021-22;2022-23", "training seasons changed")
  expect_true(values[["validation_season"]] == "2023-24", "validation season changed")
  expect_true(values[["later_seasons_analytically_sealed"]] == "2024-25;2025-26;2026-27", "later-season seal changed")
})
record("frozen_metrics", {
  expect_true(as.numeric(values[["probability_clip"]]) == CONTEXT_LOG_CLIP, "clip changed")
  expect_true(as.integer(values[["bootstrap_replicates"]]) == 2000L, "bootstrap count changed")
  expect_true(as.integer(values[["bootstrap_seed"]]) == 20260914L, "bootstrap seed changed")
  expect_true(as.numeric(values[["material_calibration_margin"]]) == 0.005, "calibration margin changed")
  expect_true(values[["primary_difference_sign"]] == "M1_minus_M0", "metric sign changed")
})
record("single_outcome_loader", {
  occurrences <- gregexpr("read_parquet\\(validation_path", runner, perl = TRUE)[[1]]
  expect_true(length(occurrences) == 1L && occurrences[[1]] > 0L, "runner must have exactly one validation outcome read")
})
record("later_season_paths_absent", {
  expect_true(!grepl("season=2024-25|season=2025-26|season=2026-27", runner), "runner contains a later-season path")
})
record("no_fitting_call", {
  blocked <- c("mgcv::gam\\s*\\(", "mgcv::bam\\s*\\(", "INLA::inla\\s*\\(")
  expect_true(!any(vapply(blocked, grepl, logical(1), x = runner, perl = TRUE)), "runner contains a model-fitting call")
})
record("toy_metrics", {
  toy <- data.frame(
    source_game_id = rep(c("g1", "g2"), each = 2L),
    field_goal_made = c(1L, 0L, 1L, 0L),
    point_value = c(2L, 3L, 2L, 3L)
  )
  metrics <- context_model_metrics(toy, c(0.8, 0.2, 0.7, 0.3))
  expect_true(all(is.finite(metrics)), "toy metrics are invalid")
  expect_true(abs(metrics[["bernoulli_log_loss"]] - mean(-log(c(0.8, 0.8, 0.7, 0.7)))) < 1e-15, "toy log loss differs")
})
record("expected_points_exact", {
  expect_true(identical(context_expected_points(c(0.25, 0.5), c(2, 3)), c(0.5, 1.5)), "expected points changed")
})
record("paired_game_bootstrap_reproducible", {
  toy <- data.frame(
    comparison_id = "retrospective_1",
    game_id = rep(paste0("g", 1:6), each = 4),
    outcome = rep(c(0L, 1L, 0L, 1L), 6),
    probability_m0 = rep(c(0.3, 0.6, 0.4, 0.7), 6),
    probability_m1 = rep(c(0.25, 0.65, 0.35, 0.75), 6)
  )
  first <- context_paired_game_bootstrap(toy, replicates = 50L, seed = CONTEXT_BOOTSTRAP_SEED)
  second <- context_paired_game_bootstrap(toy, replicates = 50L, seed = CONTEXT_BOOTSTRAP_SEED)
  expect_true(identical(first, second) && nrow(first) == 50L, "bootstrap is not deterministic")
})
record("first_season_interpretation", {
  clear <- context_first_season_interpretation(0.66, 0.658, 0.001, 0, 0)
  near <- context_first_season_interpretation(0.66, 0.6595, 0.001, 0, 0)
  worse <- context_first_season_interpretation(0.66, 0.658, 0.001, 0.006, 0)
  expect_true(clear[["label"]] == "provisional_M1_clears_first_season_gates", "clear M1 case failed")
  expect_true(near[["label"]] == "provisional_M0_within_one_standard_error", "one-SE case failed")
  expect_true(worse[["label"]] == "provisional_M1_improvement_blocked_by_calibration", "calibration gate failed")
})
record("output_schema_frozen", {
  required <- c(
    "execution_manifest.csv", "fit_diagnostics.csv", "pooled_metrics.csv",
    "season_metrics.csv", "calibration_bins.csv", "subgroup_calibration.csv",
    "bootstrap_summary.csv", "model_selection.csv", "execution_checks.csv",
    "artifact_manifest.csv"
  )
  expect_true(all(vapply(required, grepl, logical(1), x = runner, fixed = TRUE)), "tracked output schema is incomplete")
})
record("manifest_recovery_ignores_csv_type_inference", {
  original <- tibble(integer_value = 1L, logical_value = FALSE, text_value = "x")
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  write_csv(original, path)
  recovered <- read_csv(path, show_col_types = FALSE)
  expect_true(
    identical(lapply(original, as.character), lapply(recovered, as.character)),
    "unchanged serialized values failed recovery comparison"
  )
})

output <- bind_rows(results)
if (!all(output$passed)) {
  print(filter(output, !passed), n = Inf)
  stop("first-validation structural tests failed", call. = FALSE)
}
cat("All ", nrow(output), " first-validation structural tests passed.\n", sep = "")
