#!/usr/bin/env Rscript

# Structural and fully synthetic tests for the frozen M0/M1 protocol.
# The script never opens canonical or validation shot data and never fits a model.

options(stringsAsFactors = FALSE)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m0_m1_structural_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)

read_config <- function(name) {
  utils::read.csv(file.path(repo_root, "config", name), check.names = FALSE)
}

results <- list()
record <- function(name, expression) {
  message_text <- "passed"
  passed <- TRUE
  tryCatch(
    force(expression),
    error = function(error) {
      passed <<- FALSE
      message_text <<- conditionMessage(error)
    }
  )
  results[[length(results) + 1L]] <<- data.frame(
    test_id = name,
    passed = passed,
    detail = message_text,
    stringsAsFactors = FALSE
  )
  invisible(passed)
}

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

expect_error <- function(expression) {
  raised <- FALSE
  tryCatch(force(expression), error = function(error) raised <<- TRUE)
  expect_true(raised, "expected an error")
}

model_spec <- read_config("context_edition_m0_m1_model_spec_v0_1.csv")
split_spec <- read_config("context_edition_rolling_origin_v0_1.csv")
metrics_spec <- read_config("context_edition_metrics_v0_1.csv")
feature_matrix <- read_config("context_edition_feature_allowlist_v0_1.csv")
selection_spec <- read_config("context_edition_model_selection_v0_1.csv")
taxonomy_spec <- read_config("context_edition_taxonomy_v0_1.csv")
formulas <- context_model_formulas()
levels <- context_factor_levels()

record("formula_construction", {
  expect_true(inherits(formulas$M0, "formula") && inherits(formulas$M1, "formula"), "formula object missing")
  m0_text <- paste(deparse(formulas$M0), collapse = " ")
  m1_text <- paste(deparse(formulas$M1), collapse = " ")
  expect_true(grepl("finish_family", m1_text), "M1 finish term missing")
  expect_true(!grepl("finish_family", m0_text), "M0 contains taxonomy")
  expect_true(grepl("bs = \"re\"", m0_text, fixed = TRUE), "player random effect missing")
})

record("formula_config_agreement", {
  normalized <- function(x) gsub("[[:space:]]+", "", x)
  expect_true(normalized(model_spec$formula[model_spec$model_id == "M0"]) == normalized(paste(deparse(formulas$M0), collapse = "")), "M0 formula differs from config")
  expect_true(normalized(model_spec$formula[model_spec$model_id == "M1"]) == normalized(paste(deparse(formulas$M1), collapse = "")), "M1 formula differs from config")
})

record("engine_version_available", {
  expect_true(requireNamespace("mgcv", quietly = TRUE), "mgcv is not installed")
  installed <- gsub("-", ".", as.character(utils::packageVersion("mgcv")), fixed = TRUE)
  configured <- gsub("-", ".", unique(model_spec$engine_version), fixed = TRUE)
  expect_true(length(configured) == 1L && installed == configured, "installed mgcv version differs from config")
})

record("factor_level_references", {
  expect_true(levels$point_value_factor[1] == "two", "two-point reference changed")
  expect_true(levels$finish_family[1] == "regular_jumper", "finish reference changed")
  expect_true(levels$creation_family[1] == "other_or_unknown", "creation reference changed")
  expect_true(length(levels$finish_family) == 7L && length(levels$creation_family) == 4L, "taxonomy dimensions changed")
})

record("taxonomy_config_agreement", {
  expect_true(setequal(unique(taxonomy_spec$finish_family), levels$finish_family), "finish levels differ from frozen taxonomy")
  expect_true(setequal(unique(taxonomy_spec$creation_family), levels$creation_family), "creation levels differ from frozen taxonomy")
})

record("other_or_unknown_retained", {
  synthetic <- factor(c("other_or_unknown", "putback"), levels = levels$creation_family)
  expect_true(!anyNA(synthetic) && synthetic[1] == "other_or_unknown", "other_or_unknown was lost")
})

record("rare_category_retained", {
  synthetic <- factor(c(rep("regular_jumper", 99), "hook"), levels = levels$finish_family)
  expect_true(sum(synthetic == "hook") == 1L && nlevels(synthetic) == 7L, "rare category was collapsed")
})

record("known_and_unseen_player_policy", {
  expect_true(all(model_spec$unseen_player_rule == "set the unseen random-effect contribution to zero"), "unseen-player rule changed")
  expect_true(all(model_spec$player_pooling == "iid Normal random intercept; variance estimated by REML"), "pooling rule changed")
})

record("two_three_expected_value", {
  result <- context_expected_points(c(0.5, 0.5), c(2, 3))
  expect_true(isTRUE(all.equal(result, c(1, 1.5), tolerance = 0)), "expected-points conversion is wrong")
})

record("whole_game_split_integrity", {
  synthetic <- data.frame(game_id = c("A", "A", "B", "B"), split = c("train", "train", "test", "test"))
  by_game <- split(synthetic$split, synthetic$game_id)
  expect_true(all(vapply(by_game, function(x) length(unique(x)) == 1L, logical(1))), "a game crossed splits")
})

record("chronological_split_spec", {
  context_validate_split_spec(split_spec)
})

record("validation_outcomes_sealed", {
  expect_true(all(!split_spec$validation_outcomes_accessed), "a validation outcome-access flag is true")
  expect_true(all(split_spec$status %in% c("frozen_not_run", "reserved_not_accessed")), "split status implies execution")
})

record("deterministic_seed", {
  expect_true(CONTEXT_BOOTSTRAP_SEED == 20260914L, "bootstrap seed changed")
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(CONTEXT_BOOTSTRAP_SEED)
  first <- sample.int(100, 10)
  set.seed(CONTEXT_BOOTSTRAP_SEED)
  second <- sample.int(100, 10)
  expect_true(identical(first, second), "seed is not deterministic")
})

record("toy_log_loss", {
  observed <- context_log_loss(c(1, 0), c(0.8, 0.2))
  expect_true(isTRUE(all.equal(observed, -log(0.8), tolerance = 1e-15)), "toy log loss is wrong")
})

record("toy_calibration", {
  outcome <- c(0, 0, 1, 1)
  probability <- c(0.1, 0.2, 0.8, 0.9)
  bins <- context_equal_count_bins(probability, bins = 2L)
  errors <- context_calibration_errors(outcome, probability, bins)
  expect_true(isTRUE(all.equal(unname(errors["calibration_in_large_abs"]), 0, tolerance = 1e-15)), "calibration bias is wrong")
  expect_true(isTRUE(all.equal(unname(errors["ece"]), 0.15, tolerance = 1e-15)), "ECE is wrong")
})

record("paired_game_bootstrap_deterministic", {
  toy <- data.frame(
    comparison_id = rep(c("r1", "r2", "r3"), each = 8),
    game_id = rep(paste0("g", seq_len(6)), each = 4),
    outcome = rep(c(0, 1, 0, 1), 6),
    probability_m0 = rep(c(0.3, 0.6, 0.4, 0.7), 6),
    probability_m1 = rep(c(0.25, 0.65, 0.35, 0.75), 6)
  )
  first <- context_paired_game_bootstrap(toy, replicates = 50L, seed = CONTEXT_BOOTSTRAP_SEED)
  second <- context_paired_game_bootstrap(toy, replicates = 50L, seed = CONTEXT_BOOTSTRAP_SEED)
  expect_true(identical(first, second), "paired bootstrap is not reproducible")
  expect_true(nrow(first) == 50L && all(is.finite(as.matrix(first))), "paired bootstrap output is invalid")
})

record("one_standard_error_selection", {
  near <- context_select_model(0.66, 0.6595, 0.001, 0, 0, rep(0.66, 3), rep(0.6595, 3))
  clear <- context_select_model(0.66, 0.658, 0.001, 0, 0, c(0.66, 0.66, 0.66), c(0.658, 0.659, 0.661))
  worse_cal <- context_select_model(0.66, 0.658, 0.001, 0.006, 0, rep(0.66, 3), rep(0.658, 3))
  expect_true(near[["model"]] == "M0", "one-SE preference failed")
  expect_true(clear[["model"]] == "M1", "clear M1 case failed")
  expect_true(worse_cal[["model"]] == "M0", "calibration gate failed")
})

record("null_and_nonfinite_rejection", {
  expect_error(context_log_loss(c(1, NA), c(0.5, 0.5)))
  expect_error(context_log_loss(c(1, 0), c(0.5, Inf)))
  expect_error(context_expected_points(c(0.5), c(4)))
})

record("m2_plus_features_blocked", {
  context_validate_feature_matrix(feature_matrix)
})

record("metric_and_selection_config_complete", {
  required_metrics <- c("bernoulli_log_loss", "expected_points_rmse", "game_points_mae", "equal_count_decile_ece")
  expect_true(all(required_metrics %in% metrics_spec$metric_id), "required metric missing")
  expect_true(identical(selection_spec$priority, 1:5), "selection priorities changed")
})

record("no_fit_or_outcome_loader_in_test_code", {
  code_paths <- file.path(
    repo_root,
    "R",
    c("context_edition_m0_m1_protocol.R", "context_edition_m0_m1_structural_tests.R")
  )
  code <- paste(unlist(lapply(code_paths, readLines, warn = FALSE)), collapse = "\n")
  blocked_patterns <- c("mgcv::gam\\s*\\(", "mgcv::bam\\s*\\(", "read_parquet\\s*\\(", "open_dataset\\s*\\(")
  expect_true(!any(vapply(blocked_patterns, grepl, logical(1), x = code, perl = TRUE)), "fit or shot-data loader found in test code")
})

test_results <- do.call(rbind, results)
if (!all(test_results$passed)) {
  print(test_results, row.names = FALSE)
  stop("one or more structural tests failed", call. = FALSE)
}

output_dir <- file.path(repo_root, "data", "processed", "context_edition_m0_m1_preregistration_v0_1")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_path <- file.path(output_dir, "structural_test_results.csv")
temp_path <- tempfile(pattern = "structural_test_results_", tmpdir = output_dir, fileext = ".csv")
utils::write.csv(test_results, temp_path, row.names = FALSE, na = "")
if (!file.rename(temp_path, output_path)) {
  stop("failed to publish structural test results atomically", call. = FALSE)
}

message("All ", nrow(test_results), " structural and synthetic tests passed.")
