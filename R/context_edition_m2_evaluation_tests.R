#!/usr/bin/env Rscript

# Structural and synthetic tests only. This file cannot read canonical data or fit a model.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_evaluation_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_evaluation_helpers.R"), local = TRUE)

results <- list()
record <- function(test_id, expression) {
  passed <- TRUE; detail <- "passed"
  tryCatch(force(expression), error = function(error) {
    passed <<- FALSE; detail <<- conditionMessage(error)
  })
  results[[length(results) + 1L]] <<- tibble(test_id, passed, detail)
}
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_error <- function(expression, pattern) {
  message_seen <- tryCatch({ force(expression); "" }, error = conditionMessage)
  if (!grepl(pattern, message_seen, fixed = TRUE)) stop("expected error was not raised: ", pattern, call. = FALSE)
}

config <- read_csv(file.path(repo_root, "config", "context_edition_m2_evaluation_v0_1.csv"), show_col_types = FALSE)
values <- setNames(config$value, config$key)
windows <- read_csv(file.path(repo_root, "config", "context_edition_m2_evaluation_windows_v0_1.csv"), show_col_types = FALSE, na = character())
reuse <- read_csv(file.path(repo_root, "config", "context_edition_m2_evaluation_reuse_v0_1.csv"), show_col_types = FALSE, na = character())
runner <- paste(readLines(file.path(repo_root, "R", "context_edition_m2_evaluation.R"), warn = FALSE), collapse = "\n")
helpers <- paste(readLines(file.path(repo_root, "R", "context_edition_m2_evaluation_helpers.R"), warn = FALSE), collapse = "\n")

record("registered_expanding_windows", {
  context_m2_evaluation_validate_windows(windows)
  expect_true(identical(windows$validation_season, c("2023-24", "2024-25", "2025-26")), "validation seasons changed")
})
record("freeze_stage_blocks_outcome_access", {
  expect_true(values[["pre_result_implementation_commit"]] == "PENDING" || grepl("^[0-9a-f]{40}$", values[["pre_result_implementation_commit"]]), "pre-result commit field is malformed")
  expect_true(values[["execution_authorization_required"]] == "TRUE", "authorization guard disabled")
  authorization_position <- regexpr("context_m2_evaluation_verify_authorization", runner, fixed = TRUE)[[1]]
  outcome_position <- regexpr("read_parquet(validation_path", runner, fixed = TRUE)[[1]]
  expect_true(authorization_position > 0L && outcome_position > authorization_position, "outcome loader is not behind authorization")
})
record("prospective_2026_27_hard_guard", {
  expect_error(context_m2_evaluation_guard_seasons(c("2021-22"), "2026-27"), "2026-27 is sealed")
  expect_error(context_m2_evaluation_guard_seasons(c("2021-22", "2026-27"), "2025-26"), "2026-27 is sealed")
  expect_true(!grepl("season=2026-27", runner, fixed = TRUE), "runner contains a prospective partition path")
})
record("exact_formulas_and_fit_settings", {
  formulas <- context_m2_formulas(k = 10L)
  expect_true(grepl("finish_family", paste(deparse(formulas$M1), collapse = "")), "M1 formula changed")
  expect_true(grepl("shot_distance_feet", paste(deparse(formulas$M2), collapse = "")), "M2 distance smooth missing")
  expect_true(grepl("k = 10", paste(deparse(formulas$M2), collapse = ""), fixed = TRUE), "M2 k changed")
  expect_true(values[["fit_method"]] == "REML" && values[["discrete"]] == "FALSE", "fit settings changed")
})
record("m2_minus_m1_sign", {
  outcome <- c(1L, 0L, 1L, 0L)
  m1 <- c(.55, .45, .55, .45)
  m2 <- c(.75, .25, .75, .25)
  expect_true(context_log_loss(outcome, m2) - context_log_loss(outcome, m1) < 0, "negative no longer favors M2")
})
record("predictor_support_precedes_marker_and_outcomes", {
  support <- regexpr("context_m2_evaluation_preaccess(m2$fit", runner, fixed = TRUE)[[1]]
  marker <- regexpr("if (!dir.create(marker", runner, fixed = TRUE)[[1]]
  outcome <- regexpr("validation <- read_parquet", runner, fixed = TRUE)[[1]]
  expect_true(support > 0L && support < marker && marker < outcome, "support check is not before access")
  fields_seen <- NULL; marked <- FALSE; outcome_reads <- 0L
  fake_fit <- list(model = data.frame(shot_distance_feet = c(0L, 88L)))
  toy <- tibble(season = "2025-26", player_id = "synthetic", point_value = 3L,
                finish_family = "regular_jumper", creation_family = "other_or_unknown", shot_distance_feet = 89L)
  reader <- function(path, fields) {
    fields_seen <<- fields
    if ("field_goal_made" %in% fields) { outcome_reads <<- outcome_reads + 1L; stop("outcome requested") }
    toy[, fields]
  }
  attempt <- function() {
    context_m2_evaluation_preaccess(fake_fit, "synthetic", "2025-26", reader)
    marked <<- TRUE
  }
  expect_error(attempt(), "training")
  expect_true(!marked && outcome_reads == 0L, "unsupported distance reached outcome access")
  toy$shot_distance_feet <- 88L
  expect_true(context_m2_evaluation_preaccess(fake_fit, "synthetic", "2025-26", reader), "valid support rejected")
  expect_true(!marked && outcome_reads == 0L && length(fields_seen) == 6L, "support check accessed outcomes")
  toy$creation_family <- "unregistered"
  expect_error(attempt(), "factor support")
  expect_true(!marked, "unsupported taxonomy reached access")
})
record("training_volume_quartiles_ties_and_boundaries", {
  players <- letters[1:8]
  attempts <- c(1L, 2L, 2L, 2L, 4L, 4L, 7L, 8L)
  fake_fit <- list(model = data.frame(player_id_factor = factor(players)))
  fake_fit$model[["cbind(makes, misses)"]] <- cbind(makes = rep(0L, 8L), misses = attempts)
  groups <- context_m2_evaluation_volume_groups(fake_fit, sum(attempts), 8L)
  expect_true(identical(groups$player_volume_group, rep(paste0("returning_q", 1:4), each = 2L)), "quartile boundaries changed")
  expect_true(identical(groups$player_id, players), "equal-count ties no longer follow player ID")
  expected <- context_training_volume_groups(data.frame(player_id = rep(players, attempts)))
  expect_true(identical(groups, expected), "saved counts differ from frozen shot-row grouping")
  shuffled <- fake_fit; shuffled$model <- fake_fit$model[8:1, , drop = FALSE]
  expect_true(identical(groups, context_m2_evaluation_volume_groups(shuffled, sum(attempts), 8L)), "grouping depends on row order")
  fake_fit$model <- fake_fit$model[1:5, , drop = FALSE]
  uneven <- context_m2_evaluation_volume_groups(fake_fit, sum(attempts[1:5]), 5L)
  expect_true(identical(uneven$player_volume_group, paste0("returning_q", c(1, 1, 2, 3, 4))), "uneven quartile boundary changed")
})
record("training_volume_excludes_validation_and_future_volume", {
  groups <- context_training_volume_groups(data.frame(player_id = rep(letters[1:8], 1:8)))
  validation <- tibble(player_id = c("a", "c", "e", "g", "new"), outcome = 0L, future_volume = 1L)
  first <- context_m2_evaluation_volume_labels(validation$player_id, groups)
  validation$outcome <- 1L; validation$future_volume <- 999999L
  second <- context_m2_evaluation_volume_labels(validation$player_id, groups)
  expect_true(identical(first, c(paste0("returning_q", 1:4), "unseen_player")), "quartile or unseen assignment changed")
  expect_true(identical(first, second), "outcomes or future volume changed assignment")
})
record("paired_whole_game_bootstrap_by_season", {
  toy <- bind_rows(
    tibble(comparison_id = "development_1", game_id = rep(c("a", "b"), each = 4L), outcome = rep(c(1L, 0L, 1L, 0L), 2L), probability_m1 = .5, probability_m2 = rep(c(.6, .4, .6, .4), 2L)),
    tibble(comparison_id = "development_2", game_id = rep(c("c", "d"), each = 4L), outcome = rep(c(0L, 1L, 0L, 1L), 2L), probability_m1 = .5, probability_m2 = rep(c(.4, .6, .4, .6), 2L))
  )
  first <- context_m2_paired_game_bootstrap(toy, 50L, 20260914L)
  second <- context_m2_paired_game_bootstrap(toy, 50L, 20260914L)
  expect_true(identical(first, second) && nrow(first) == 50L, "stratified whole-game bootstrap is not deterministic")
  expect_true(grepl("strata <- split(game_strata$game_id, game_strata$comparison_id)", helpers, fixed = TRUE), "bootstrap is not stratified by validation season")
})
record("one_standard_error_gate", {
  choice <- context_m2_evaluation_select(.6500, .6495, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M1", "one-standard-error rule changed")
})
record("calibration_gate", {
  choice <- context_m2_evaluation_select(.6500, .6400, .0010, .006, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M1", "calibration gate changed")
})
record("two_of_three_gate", {
  choice <- context_m2_evaluation_select(.6500, .6400, .0010, 0, 0, c(.64, .64, .64), c(.63, .65, .65))
  expect_true(choice[["model"]] == "M1", "two-of-three rule changed")
})
record("all_gates_advance_m2", {
  choice <- context_m2_evaluation_select(.6500, .6400, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63))
  expect_true(choice[["model"]] == "M2", "all-gates M2 case changed")
})
record("d1_cannot_select", {
  first <- context_m2_evaluation_select(.6500, .6400, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63), d1_signal = -Inf)
  second <- context_m2_evaluation_select(.6500, .6400, .0010, 0, 0, c(.66, .65, .64), c(.65, .64, .63), d1_signal = Inf)
  expect_true(identical(first, second), "D1 affected formal selection")
})
record("exact_reuse_hash_accepts_and_rejects", {
  expect_true(nrow(reuse) == 4L && all(grepl("^[0-9a-f]{64}$", reuse$fit_sha256)), "frozen reuse declarations are incomplete")
  path <- tempfile("reuse-")
  on.exit(unlink(path), add = TRUE)
  writeLines("frozen artifact", path)
  hash <- strsplit(system2("shasum", c("-a", "256", path), stdout = TRUE)[[1]], " ", fixed = TRUE)[[1]][[1]]
  context_m2_evaluation_verify_hash(path, hash, function(value) strsplit(system2("shasum", c("-a", "256", value), stdout = TRUE)[[1]], " ", fixed = TRUE)[[1]][[1]])
  expect_error(context_m2_evaluation_verify_hash(path, paste(rep("0", 64L), collapse = ""), function(value) hash), "hash mismatch")
})
record("m2_grouped_row_verifier_precedence", {
  grouped_row_expression <-
    'metadata$grouped_rows != (if (model_id == "M1") row$m1_grouped_rows else row$m2_grouped_rows) ||'
  expect_true(grepl(grouped_row_expression, runner, fixed = TRUE), "M2 grouped-row comparison is not parenthesized")
  metadata <- tibble(grouped_rows = 69649L, converged = TRUE, validation_outcomes_accessed = FALSE)
  row <- tibble(m1_grouped_rows = 10852L, m2_grouped_rows = 69649L)
  model_id <- "M2"
  rejected <- metadata$grouped_rows !=
    (if (model_id == "M1") row$m1_grouped_rows else row$m2_grouped_rows) ||
    ("converged" %in% names(metadata) && !isTRUE(metadata$converged)) ||
    ("validation_outcomes_accessed" %in% names(metadata) && isTRUE(metadata$validation_outcomes_accessed))
  expect_true(!rejected, "matching M2 grouped-row metadata was falsely rejected")
})
record("interruption_recovery_is_nonduplicating", {
  expect_true(context_m2_evaluation_recovery_action(TRUE, TRUE, TRUE) == "verify_completed_result", "completed result would rerun")
  expect_true(context_m2_evaluation_recovery_action(FALSE, TRUE, TRUE) == "resume_from_predictions", "prediction checkpoint would rerun")
  expect_true(context_m2_evaluation_recovery_action(FALSE, TRUE, FALSE) == "stop_for_manual_recovery", "unsafe reread was allowed")
})
record("atomic_publication_hides_partial_state", {
  root <- tempfile("atomic-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  stage <- file.path(root, ".result.partial"); final <- file.path(root, "result")
  dir.create(stage); writeLines("complete", file.path(stage, "payload"))
  expect_true(!dir.exists(final), "partial result was exposed")
  context_m2_evaluation_atomic_publish(stage, final)
  expect_true(dir.exists(final) && !dir.exists(stage), "atomic publication failed")
})
record("known_unseen_and_taxonomy_rules_present", {
  expect_true(grepl("__UNSEEN_PLAYER__", helpers, fixed = TRUE), "unseen-player path missing")
  expect_true("other_or_unknown" %in% context_m2_factor_levels()$creation_family, "other_or_unknown missing")
})
record("expected_points_exact", {
  expect_true(identical(context_expected_points(c(.25, .5), c(2, 3)), c(.5, 1.5)), "expected-points conversion changed")
})
record("no_private_outputs_tracked", {
  ignore <- paste(readLines(file.path(repo_root, ".gitignore"), warn = FALSE), collapse = "\n")
  expect_true(grepl("data/cache/", ignore, fixed = TRUE), "private cache is not ignored")
  expect_true(values[["public_shot_rows"]] == "FALSE", "shot-level publication enabled")
})

output <- bind_rows(results)
if (!all(output$passed)) {
  print(filter(output, !passed), n = Inf)
  stop("M2 evaluation freeze tests failed", call. = FALSE)
}
output_path <- file.path(repo_root, "data", "processed", "context_edition_m2_evaluation_v0_1", "freeze_test_results.csv")
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(".freeze-tests-", tmpdir = dirname(output_path))
write_csv(output, temporary, na = "", quote = "needed")
if (!file.rename(temporary, output_path)) stop("could not publish test results atomically", call. = FALSE)
cat("All ", nrow(output), " M2 evaluation freeze tests passed.\n", sep = "")
