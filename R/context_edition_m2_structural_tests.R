#!/usr/bin/env Rscript

# Structural and synthetic tests for the M2 preregistration. The script uses
# invented rows only, constructs a smooth basis without fitting a model, and
# never opens canonical data or historical outcomes.

options(stringsAsFactors = FALSE)
suppressPackageStartupMessages(library(mgcv))

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_structural_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)

read_config <- function(name) {
  utils::read.csv(file.path(repo_root, "config", name), check.names = FALSE)
}
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_error <- function(expression) {
  raised <- FALSE
  tryCatch(force(expression), error = function(error) raised <<- TRUE)
  expect_true(raised, "expected an error")
}
normalized <- function(x) gsub("[[:space:]]+", "", x)

results <- list()
record <- function(name, expression) {
  passed <- TRUE
  detail <- "passed"
  tryCatch(force(expression), error = function(error) {
    passed <<- FALSE
    detail <<- conditionMessage(error)
  })
  results[[length(results) + 1L]] <<- data.frame(
    test_id = name, passed = passed, detail = detail, stringsAsFactors = FALSE
  )
}

model_spec <- read_config("context_edition_m2_model_spec_v0_1.csv")
feature_matrix <- read_config("context_edition_m2_feature_allowlist_v0_1.csv")
smooth_spec <- read_config("context_edition_m2_smooth_v0_1.csv")
grouping_spec <- read_config("context_edition_m2_grouping_v0_1.csv")
split_spec <- read_config("context_edition_m2_development_plan_v0_1.csv")
decision_spec <- read_config("context_edition_m2_decision_v0_1.csv")
subgroups <- read_config("context_edition_m2_subgroups_v0_1.csv")
prospective <- read_config("context_edition_m2_prospective_v0_1.csv")
formulas <- context_m2_formulas()
old_formulas <- context_model_formulas()
levels <- context_m2_factor_levels()

record("exact_m1_preservation", {
  expect_true(normalized(paste(deparse(formulas$M0), collapse = "")) == normalized(paste(deparse(old_formulas$M0), collapse = "")), "M0 changed")
  expect_true(normalized(paste(deparse(formulas$M1), collapse = "")) == normalized(paste(deparse(old_formulas$M1), collapse = "")), "M1 changed")
})

record("exact_d1_and_m2_formulas", {
  for (model in c("M0", "M1", "D1", "M2")) {
    configured <- model_spec$formula[model_spec$model_id == model]
    actual <- paste(deparse(formulas[[model]]), collapse = "")
    expect_true(length(configured) == 1L && normalized(configured) == normalized(actual), paste(model, "formula mismatch"))
  }
  expect_true(grepl("shot_distance_feet", paste(deparse(formulas$D1), collapse = " ")), "D1 distance term missing")
  expect_true(grepl("shot_distance_feet", paste(deparse(formulas$M2), collapse = " ")), "M2 distance term missing")
})

record("distance_units_and_guards", {
  expect_true(smooth_spec$unit == "whole_feet", "distance unit changed")
  context_m2_validate_distance(c(0, 22, 30, 88, 100))
  expect_error(context_m2_validate_distance(c(2.5, 3)))
})

record("missing_and_impossible_distances", {
  expect_error(context_m2_validate_distance(c(1, NA)))
  expect_error(context_m2_validate_distance(c(-1, 10)))
  expect_error(context_m2_validate_distance(c(1, 101)))
})

record("corner_three_and_long_two_examples", {
  invented <- data.frame(point_value = c(3L, 2L), distance = c(22L, 23L))
  expect_true(invented$distance[1] < invented$distance[2], "corner-three example is not shorter")
  expect_true(invented$point_value[1] == 3L && invented$point_value[2] == 2L, "point status was inferred from distance")
})

record("heaves_and_maximum_range", {
  context_m2_validate_distance(c(30L, 50L, 88L, 100L))
  bands <- as.character(context_m2_distance_band(c(30L, 88L)))
  expect_true(all(bands == "long_heave_30_plus"), "heave band changed")
})

record("grouped_count_likelihood_preservation", {
  invented <- data.frame(
    player_id_factor = factor(c("A", "A", "A", "B")),
    point_value_factor = factor(c("two", "two", "two", "three")),
    shot_distance_feet = c(5L, 5L, 5L, 22L),
    finish_family = factor(c("layup", "layup", "layup", "regular_jumper")),
    creation_family = factor(c("other_or_unknown", "other_or_unknown", "other_or_unknown", "pull_up_or_self_created")),
    made = c(1L, 0L, 1L, 0L)
  )
  key <- interaction(invented[c("player_id_factor", "point_value_factor", "finish_family", "creation_family", "shot_distance_feet")], drop = TRUE)
  makes <- as.numeric(rowsum(invented$made, key))
  attempts <- as.numeric(rowsum(rep(1L, nrow(invented)), key))
  for (p in c(0.3, 0.7)) {
    individual_kernel <- sum(invented$made * log(p) + (1 - invented$made) * log(1 - p))
    grouped_kernel <- sum(makes * log(p) + (attempts - makes) * log(1 - p))
    expect_true(isTRUE(all.equal(individual_kernel, grouped_kernel, tolerance = 1e-15)), "grouping changed the likelihood kernel")
  }
  expect_true(sum(makes) == sum(invented$made) && sum(attempts) == nrow(invented), "grouped counts changed totals")
})

record("smooth_basis_construction", {
  synthetic <- data.frame(shot_distance_feet = rep(0:88, each = 2))
  specification <- mgcv::s(shot_distance_feet, bs = "cr", k = 10, m = 2)
  constructed <- mgcv::smoothCon(specification, data = synthetic, absorb.cons = TRUE)[[1]]
  expect_true(constructed$bs.dim == 10L, "basis dimension changed")
  expect_true(ncol(constructed$X) == 9L, "centered basis should contribute nine columns")
  expect_true(length(constructed$S) == 1L && all(is.finite(constructed$S[[1]])), "smooth penalty is invalid")
})

record("basis_boundary_behavior", {
  synthetic <- data.frame(shot_distance_feet = rep(0:88, each = 2))
  constructed <- mgcv::smoothCon(mgcv::s(shot_distance_feet, bs = "cr", k = 10, m = 2), data = synthetic, absorb.cons = TRUE)[[1]]
  inside <- mgcv::PredictMat(constructed, data.frame(shot_distance_feet = c(0, 22, 88)))
  expect_true(all(is.finite(inside)), "in-range basis prediction is invalid")
  context_m2_validate_distance(c(0, 88), training_range = c(0, 88))
  expect_error(context_m2_validate_distance(89, training_range = c(0, 88)))
})

record("mechanical_k_rule", {
  expect_true(context_m2_k_escalation(8.7, 0.85, 0.01, 10) == "refit_once_at_k_20", "registered escalation did not fire")
  expect_true(context_m2_k_escalation(7, 0.85, 0.01, 10) == "retain_k_10", "EDF guard failed")
  expect_true(context_m2_k_escalation(8.7, 0.95, 0.01, 10) == "retain_k_10", "k-index guard failed")
  expect_true(context_m2_k_escalation(15, 0.8, 0.01, 20) == "stop_if_still_inadequate", "one-time limit failed")
})

record("known_and_unseen_players", {
  expect_true(all(grepl("exclude s\\(player_id_factor\\)", model_spec$unseen_player_rule)), "unseen-player zero-effect rule changed")
  expect_true(all(grepl("iid Normal random intercept", model_spec$player_pooling)), "player pooling changed")
})

record("expected_points_conversion", {
  observed <- context_expected_points(c(0.5, 0.5), c(2, 3))
  expect_true(identical(observed, c(1, 1.5)), "expected points is not probability times point value")
})

record("factor_levels_and_other_unknown", {
  expect_true(levels$point_value_factor[1] == "two", "point reference changed")
  expect_true(levels$finish_family[1] == "regular_jumper", "finish reference changed")
  expect_true(levels$creation_family[1] == "other_or_unknown", "creation reference changed")
  synthetic <- factor(c("other_or_unknown", "putback"), levels = levels$creation_family)
  expect_true(!anyNA(synthetic) && nlevels(synthetic) == 4L, "other_or_unknown was dropped")
})

record("feature_allowlist", {
  context_m2_validate_feature_allowlist(feature_matrix)
})

record("no_two_dimensional_or_context_terms", {
  formula_text <- paste(vapply(formulas, function(x) paste(deparse(x), collapse = " "), character(1)), collapse = " ")
  blocked <- c("location_x", "location_y", "period", "clock", "score", "team", "defender")
  expect_true(!any(vapply(blocked, grepl, logical(1), x = formula_text, fixed = TRUE)), "a blocked model term is present")
})

record("deterministic_split_and_bootstrap", {
  context_m2_validate_split_spec(split_spec)
  expect_true(all(split_spec$split_unit == "whole_game"), "split unit changed")
  expect_true(all(split_spec$bootstrap_seed == CONTEXT_M2_BOOTSTRAP_SEED), "bootstrap seed changed")
  expect_true(all(split_spec$bootstrap_replicates == CONTEXT_M2_BOOTSTRAP_REPLICATES), "bootstrap replicates changed")
})

record("mechanical_decision_table", {
  expect_true(identical(decision_spec$priority, 1:5), "decision priorities changed")
  close <- context_m2_select(0.65, 0.6495, 0.001, 0, 0, rep(0.65, 3), rep(0.6495, 3))
  advance <- context_m2_select(0.65, 0.648, 0.001, 0, 0, rep(0.65, 3), c(0.648, 0.649, 0.651))
  calibration_fail <- context_m2_select(0.65, 0.648, 0.001, 0.006, 0, rep(0.65, 3), rep(0.648, 3))
  expect_true(close[["model"]] == "M1", "one-SE rule failed")
  expect_true(advance[["model"]] == "M2", "advancement case failed")
  expect_true(calibration_fail[["model"]] == "M1", "calibration gate failed")
})

record("historical_development_labeling", {
  historical <- split_spec$validation_season %in% c("2023-24", "2024-25", "2025-26")
  expect_true(all(split_spec$evidence_status[historical] == "historical_model_development"), "historical outcomes were mislabeled")
})

record("prospective_access_prohibition", {
  expect_true(all(!split_spec$outcomes_accessed), "an outcome-access flag is true")
  guard <- prospective$frozen_rule[prospective$item == "access_guard"]
  expect_true(length(guard) == 1L && grepl("do not create", guard), "2026-27 guard is incomplete")
})

record("distance_subgroups_fixed", {
  expected <- c(
    "restricted_0_to_under_4", "other_paint_4_to_under_10",
    "midrange_10_to_under_22", "three_point_distance_22_to_under_30",
    "long_heave_30_plus"
  )
  expect_true(all(expected %in% subgroups$group_id), "distance subgroup missing")
  expect_true(all(!subgroups$selection_use), "a subgroup can override selection")
})

record("no_fit_or_real_data_loader_in_protocol_tests", {
  code_paths <- file.path(repo_root, "R", c("context_edition_m2_protocol.R", "context_edition_m2_structural_tests.R"))
  code <- paste(unlist(lapply(code_paths, readLines, warn = FALSE)), collapse = "\n")
  blocked_patterns <- c("mgcv::gam\\s*\\(", "mgcv::bam\\s*\\(", "read_parquet\\s*\\(", "open_dataset\\s*\\(")
  expect_true(!any(vapply(blocked_patterns, grepl, logical(1), x = code, perl = TRUE)), "fit or real-data loader found")
})

test_results <- do.call(rbind, results)
if (!all(test_results$passed)) {
  print(test_results, row.names = FALSE)
  stop("one or more M2 structural tests failed", call. = FALSE)
}

output_dir <- file.path(repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_path <- file.path(output_dir, "structural_test_results.csv")
temp_path <- tempfile(pattern = "structural_test_results_", tmpdir = output_dir, fileext = ".csv")
utils::write.csv(test_results, temp_path, row.names = FALSE, na = "")
if (!file.rename(temp_path, output_path)) stop("failed to publish structural test results atomically", call. = FALSE)

message("All ", nrow(test_results), " M2 structural and synthetic tests passed; no model was fitted.")
