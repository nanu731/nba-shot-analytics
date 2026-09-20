#!/usr/bin/env Rscript

# Structural and synthetic checks only; this script cannot load real outcomes.
suppressPackageStartupMessages({ library(dplyr); library(readr) })
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_third_validation_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_third_validation_helpers.R"), local = TRUE)

results <- list()
record <- function(id, expression) {
  passed <- TRUE; detail <- "passed"
  tryCatch(force(expression), error = function(e) { passed <<- FALSE; detail <<- conditionMessage(e) })
  results[[length(results) + 1L]] <<- tibble(test_id = id, passed = passed, detail = detail)
}
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
config <- read_csv(file.path(repo_root, "config", "context_edition_third_validation_v0_1.csv"), show_col_types = FALSE)
values <- setNames(config$value, config$key)
runner <- paste(readLines(file.path(repo_root, "R", "context_edition_third_validation.R"), warn = FALSE), collapse = "\n")

record("frozen_third_split", {
  expect_true(values[["training_seasons"]] == "2021-22;2022-23;2023-24;2024-25", "training split changed")
  expect_true(values[["validation_season"]] == "2025-26", "validation season changed")
  expect_true(values[["later_seasons_analytically_sealed"]] == "2026-27", "prospective seal changed")
})
record("frozen_metrics", {
  expect_true(as.numeric(values[["probability_clip"]]) == CONTEXT_LOG_CLIP, "clip changed")
  expect_true(as.integer(values[["bootstrap_replicates"]]) == 2000L, "bootstrap count changed")
  expect_true(as.integer(values[["bootstrap_seed"]]) == 20260914L, "seed changed")
  expect_true(as.numeric(values[["material_calibration_margin"]]) == 0.005, "calibration margin changed")
  expect_true(values[["primary_difference_sign"]] == "M1_minus_M0", "sign changed")
})
record("single_validation_outcome_loader", {
  occurrences <- gregexpr("read_parquet\\(validation_path, col_select = all_of\\(c\\(metadata_fields, \"field_goal_made\"", runner, perl = TRUE)[[1]]
  expect_true(length(occurrences) == 1L && occurrences[[1]] > 0L, "must contain one validation outcome loader")
})
record("no_2026_27_loader", expect_true(!grepl("season=2026-27", runner, fixed = TRUE), "2026-27 path found"))
record("fit_call_confined", {
  expect_true(length(gregexpr("mgcv::gam\\(", runner, perl = TRUE)[[1]]) == 1L, "fit call count changed")
  expect_true(grepl("if \\(mode %in% c\\(\"fit\", \"verify-fit\"\\)\\)", runner), "fit guard missing")
})
record("prior_checkpoints_only", {
  expect_true(grepl("first_private", runner, fixed = TRUE) && grepl("second_private", runner, fixed = TRUE), "private checkpoint paths missing")
  expect_true(grepl("original split-specific", runner, fixed = TRUE), "split-specific verification missing")
})
record("stratified_pooled_bootstrap", {
  toy <- bind_rows(
    data.frame(comparison_id = "r1", game_id = rep(paste0("a", 1:4), each = 4), outcome = rep(c(0L, 1L, 0L, 1L), 4), probability_m0 = .45, probability_m1 = .5),
    data.frame(comparison_id = "r2", game_id = rep(paste0("b", 1:4), each = 4), outcome = rep(c(1L, 0L, 1L, 0L), 4), probability_m0 = .55, probability_m1 = .5),
    data.frame(comparison_id = "r3", game_id = rep(paste0("c", 1:4), each = 4), outcome = rep(c(0L, 1L, 1L, 0L), 4), probability_m0 = .48, probability_m1 = .52)
  )
  first <- context_paired_game_bootstrap(toy, 50L, 20260914L)
  second <- context_paired_game_bootstrap(toy, 50L, 20260914L)
  expect_true(identical(first, second), "pooled bootstrap differs")
})
record("selection_requires_one_se", {
  choice <- context_select_model(.6500, .6495, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M0", "one-SE gate changed")
})
record("selection_requires_calibration", {
  choice <- context_select_model(.6500, .6400, .0010, .006, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M0", "calibration gate changed")
})
record("selection_requires_two_seasons", {
  choice <- context_select_model(.6500, .6400, .0010, 0, 0, c(.64, .64, .64), c(.63, .65, .65))
  expect_true(choice[["model"]] == "M0", "two-of-three gate changed")
})
record("selection_m1_only_after_all_gates", {
  choice <- context_select_model(.6500, .6400, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M1", "all-gates M1 case changed")
})
record("final_outputs_are_aggregate", {
  expect_true(grepl("final_model_decision.csv", runner, fixed = TRUE), "final decision output missing")
  expect_true(grepl("pooled_three_season_metrics.csv", runner, fixed = TRUE), "pooled metrics output missing")
  expect_true(values[["public_shot_rows"]] == "FALSE", "public shot rows enabled")
})

output <- bind_rows(results)
if (!all(output$passed)) {
  print(filter(output, !passed), n = Inf)
  stop("third-validation structural tests failed", call. = FALSE)
}
cat("All ", nrow(output), " third-validation structural tests passed.\n", sep = "")
