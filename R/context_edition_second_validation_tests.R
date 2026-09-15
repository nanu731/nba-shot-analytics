#!/usr/bin/env Rscript

# Structural and synthetic checks only; this script cannot load real outcomes.
suppressPackageStartupMessages({ library(dplyr); library(readr) })
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_second_validation_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_second_validation_helpers.R"), local = TRUE)

results <- list(); record <- function(id, expression) { passed <- TRUE; detail <- "passed"; tryCatch(force(expression), error = function(e) { passed <<- FALSE; detail <<- conditionMessage(e) }); results[[length(results) + 1L]] <<- tibble(test_id = id, passed = passed, detail = detail) }
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
config <- read_csv(file.path(repo_root, "config", "context_edition_second_validation_v0_1.csv"), show_col_types = FALSE); values <- setNames(config$value, config$key)
runner <- paste(readLines(file.path(repo_root, "R", "context_edition_second_validation.R"), warn = FALSE), collapse = "\n")

record("frozen_second_split", { expect_true(values[["training_seasons"]] == "2021-22;2022-23;2023-24", "training split changed"); expect_true(values[["validation_season"]] == "2024-25", "validation changed"); expect_true(values[["later_seasons_analytically_sealed"]] == "2025-26;2026-27", "seal changed") })
record("frozen_metrics", { expect_true(as.numeric(values[["probability_clip"]]) == CONTEXT_LOG_CLIP, "clip changed"); expect_true(as.integer(values[["bootstrap_replicates"]]) == 2000L, "bootstrap count changed"); expect_true(as.integer(values[["bootstrap_seed"]]) == 20260914L, "seed changed"); expect_true(as.numeric(values[["material_calibration_margin"]]) == 0.005, "margin changed"); expect_true(values[["primary_difference_sign"]] == "M1_minus_M0", "sign changed") })
record("single_validation_outcome_loader", { occurrences <- gregexpr("read_parquet\\(validation_path, col_select = all_of\\(c\\(metadata_fields, \"field_goal_made\"", runner, perl = TRUE)[[1]]; expect_true(length(occurrences) == 1L && occurrences[[1]] > 0L, "must contain exactly one validation outcome loader") })
record("later_outcome_paths_absent", expect_true(!grepl("season=2025-26|season=2026-27", runner), "later outcome path found"))
record("fit_call_confined_to_fit_component", { expect_true(length(gregexpr("mgcv::gam\\(", runner, perl = TRUE)[[1]]) == 1L, "fit call count changed"); expect_true(grepl("if \\(mode %in% c\\(\"fit\", \"verify-fit\"\\)\\)", runner), "fit mode guard missing") })
record("formula_identity", { formulas <- context_model_formulas(); expect_true(grepl("finish_family", paste(deparse(formulas$M1), collapse = "")), "M1 changed"); expect_true(!grepl("finish_family", paste(deparse(formulas$M0), collapse = "")), "M0 changed") })
record("safe_auc_large_sample", { outcome <- rep(c(0L, 1L), 60000L); probability <- rep(c(0.25, 0.75), 60000L); expect_true(context_auc(outcome, probability) == 1, "AUC overflowed") })
record("paired_bootstrap_deterministic", { toy <- data.frame(comparison_id = "retrospective_2", game_id = rep(paste0("g", 1:6), each = 4), outcome = rep(c(0L, 1L, 0L, 1L), 6), probability_m0 = rep(c(.3,.6,.4,.7),6), probability_m1 = rep(c(.25,.65,.35,.75),6)); expect_true(identical(context_paired_game_bootstrap(toy, 50L, 20260914L), context_paired_game_bootstrap(toy, 50L, 20260914L)), "bootstrap differs") })
record("whole_game_split", { split <- read_csv(file.path(repo_root, "config", "context_edition_rolling_origin_v0_1.csv"), show_col_types = FALSE); row <- filter(split, comparison_id == "retrospective_2"); expect_true(nrow(row) == 1L && row$split_unit == "whole_game" && !row$game_overlap_allowed, "whole-game rule changed") })
record("first_result_hash_frozen", expect_true(values[["first_result_manifest_sha256"]] == CONTEXT_FIRST_RESULT_MANIFEST_SHA256, "first result hash changed"))
record("final_selection_blocked", expect_true(values[["final_model_selection_allowed"]] == "FALSE", "final selection became allowed"))
record("output_schema_includes_running_status", expect_true(grepl("running_season_status.csv", runner, fixed = TRUE), "running status missing"))

output <- bind_rows(results)
if (!all(output$passed)) { print(filter(output, !passed), n = Inf); stop("second-validation tests failed", call. = FALSE) }
cat("All ", nrow(output), " second-validation structural tests passed.\n", sep = "")
