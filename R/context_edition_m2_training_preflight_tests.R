#!/usr/bin/env Rscript

# No-fit structural and synthetic checks for the M2 training-preflight runner.

options(stringsAsFactors = FALSE)
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_training_preflight_tests.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)

config_path <- file.path(repo_root, "config", "context_edition_m2_training_preflight_v0_1.csv")
runner_path <- file.path(repo_root, "R", "context_edition_m2_training_preflight.R")
config <- utils::read.csv(config_path, check.names = FALSE)
values <- setNames(config$value, config$key)
model_spec <- utils::read.csv(file.path(repo_root, "config", "context_edition_m2_model_spec_v0_1.csv"), check.names = FALSE)
feature_spec <- utils::read.csv(file.path(repo_root, "config", "context_edition_m2_feature_allowlist_v0_1.csv"), check.names = FALSE)
formulas <- context_m2_formulas()

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
expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_error <- function(expression) {
  raised <- FALSE
  tryCatch(force(expression), error = function(error) raised <<- TRUE)
  expect_true(raised, "expected an error")
}
normalize <- function(x) gsub("[[:space:]]+", "", x)

record("approved_design_commit_frozen", {
  expect_true(values[["approved_design_commit"]] == "5b54ebf6354198b2111fba084e55a9a473802eac", "approved design commit changed")
  expect_true(values[["pre_fit_implementation_commit"]] == "18cbe2ffcd85641214419d88a5520f0b55e561da", "pre-fit implementation commit changed")
})

record("expected_points_helper_imported_by_runner", {
  runner_lines <- readLines(runner_path, warn = FALSE)
  import_line <- grep("context_edition_m0_m1_protocol.R", runner_lines, fixed = TRUE)
  use_line <- grep("context_expected_points(probability, point_values)", runner_lines, fixed = TRUE)
  expect_true(length(import_line) == 1L && length(use_line) == 1L && import_line < use_line, "expected-points helper is not imported before use")
})

record("first_window_only", {
  expect_true(values[["training_seasons"]] == "2021-22;2022-23", "training window changed")
  expect_true(values[["prohibited_outcome_seasons"]] == "2023-24;2024-25;2025-26;2026-27", "protected seasons changed")
  expect_true(all(values[c("validation_outcomes_accessed", "validation_predictions_created", "performance_metrics_created", "prospective_2026_27_accessed")] == "FALSE"), "a seal flag is true")
})

record("exact_formulas", {
  for (model_id in c("D1", "M2")) {
    configured <- model_spec$formula[model_spec$model_id == model_id]
    actual <- paste(deparse(formulas[[model_id]]), collapse = "")
    expect_true(length(configured) == 1L && normalize(configured) == normalize(actual), paste(model_id, "formula mismatch"))
  }
})

record("exact_grouping_keys", {
  d1 <- c("player_id_factor", "point_value_factor", "shot_distance_feet")
  m2 <- c("player_id_factor", "point_value_factor", "finish_family", "creation_family", "shot_distance_feet")
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  expect_true(all(vapply(c(d1, m2), grepl, logical(1), x = runner, fixed = TRUE)), "a grouping field is missing from runner")
})

record("synthetic_grouping_preserves_counts", {
  invented <- data.frame(
    player_id_factor = factor(c("A", "A", "A", "B")),
    point_value_factor = factor(c("two", "two", "two", "three")),
    finish_family = factor(c("layup", "layup", "layup", "regular_jumper")),
    creation_family = factor(c("other_or_unknown", "other_or_unknown", "other_or_unknown", "pull_up_or_self_created")),
    shot_distance_feet = c(3L, 3L, 3L, 22L),
    field_goal_made = c(1L, 0L, 1L, 0L)
  )
  key <- interaction(invented, drop = TRUE)
  makes <- as.numeric(rowsum(invented$field_goal_made, key))
  attempts <- as.numeric(rowsum(rep(1L, nrow(invented)), key))
  expect_true(sum(makes) == 2L && sum(attempts) == 4L && sum(attempts - makes) == 2L, "grouping changed totals")
})

record("distance_and_boundary_guards", {
  context_m2_validate_distance(c(0L, 22L, 23L, 30L, 88L))
  expect_error(context_m2_validate_distance(c(-1L, 10L)))
  expect_error(context_m2_validate_distance(c(10L, 101L)))
  expect_error(context_m2_validate_distance(c(10, NA)))
})

record("boundary_grid_has_exactly_178_rows", {
  grid <- context_preflight_boundary_grid(
    player_levels = sprintf("player_%03d", seq_len(700L)),
    point_value_levels = c("two", "three"),
    distances = 0:88
  )
  expect_true(nrow(grid) == 178L, "boundary grid expanded unused player levels")
  expect_true(nlevels(grid$player_id_factor) == 700L, "training player levels were not retained")
  expect_true(length(unique(as.character(grid$player_id_factor))) == 1L, "boundary grid contains more than one player")
})

record("expected_points_conversion", {
  expect_true(isTRUE(all.equal(context_expected_points(c(0.4, 0.4), c(2, 3)), c(0.8, 1.2), tolerance = 1e-15)), "expected-points rule changed")
})

record("unseen_player_policy", {
  rules <- model_spec$unseen_player_rule[model_spec$model_id %in% c("D1", "M2")]
  expect_true(length(rules) == 2L && all(grepl("exclude s\\(player_id_factor\\)", rules)), "unseen-player zero-deviation rule changed")
})

record("prohibited_features_blocked", {
  context_m2_validate_feature_allowlist(feature_spec)
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  formula_text <- paste(vapply(formulas[c("D1", "M2")], function(x) paste(deparse(x), collapse = " "), character(1)), collapse = " ")
  expect_true(!grepl("location_x|location_y|score_margin|game_clock|defender", formula_text), "blocked formula term entered")
  expect_true(!grepl("season=2023-24|season=2024-25|season=2025-26|season=2026-27", runner), "runner contains a protected partition path")
})

record("atomic_duplicate_and_recovery_guards", {
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  required <- c("private_lock", "context_preflight_atomic_publish", "verify_private_checkpoint", "another M2 training preflight process is active")
  expect_true(all(vapply(required, grepl, logical(1), x = runner, fixed = TRUE)), "runner safeguard missing")
})

record("partial_resume_reuses_d1_and_fits_only_m2", {
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  required <- c(
    "RECOVERY_D1_FIT_SHA256", "recovered_d1_metadata", "models_to_fit <- \"M2\"",
    "d1_refit_count = 0L", "warning_metadata_status = \"unavailable_after_interrupted_checker\"",
    "partial_verification_only"
  )
  expect_true(all(vapply(required, grepl, logical(1), x = runner, fixed = TRUE)), "partial-resume invariant is missing")
})

record("resource_and_failure_evidence", {
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  required <- c("resource_samples", "peak_process_tree_rss_bytes", "failure_or_interruption.txt", "available_disk_bytes")
  expect_true(all(vapply(required, grepl, logical(1), x = runner, fixed = TRUE)), "resource or failure evidence missing")
})

record("frozen_k_gate", {
  expect_true(values[["k_initial"]] == "10", "initial k changed")
  expect_true(values[["k_check_seed"]] == "20260916", "k-check seed changed")
  expect_true(context_m2_k_escalation(8.7, 0.85, 0.01, 10) == "refit_once_at_k_20", "mechanical escalation rule changed")
  expect_true(context_m2_k_escalation(7, 0.85, 0.01, 10) == "retain_k_10", "mechanical retain rule changed")
})

record("no_performance_comparison_code", {
  runner <- paste(readLines(runner_path, warn = FALSE), collapse = "\n")
  blocked <- c("context_log_loss\\s*\\(", "context_select_model\\s*\\(", "context_m2_select\\s*\\(", "context_paired_game_bootstrap\\s*\\(")
  expect_true(!any(vapply(blocked, grepl, logical(1), x = runner, perl = TRUE)), "performance comparison entered preflight runner")
})

record("existing_preregistration_tests_passed", {
  prior <- utils::read.csv(file.path(repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1", "structural_test_results.csv"))
  expect_true(nrow(prior) == 21L && all(prior$passed), "one of 21 preregistration tests is not passing")
})

test_results <- do.call(rbind, results)
if (!all(test_results$passed)) {
  print(test_results, row.names = FALSE)
  stop("one or more M2 preflight implementation tests failed", call. = FALSE)
}

output_dir <- file.path(repo_root, "data", "processed", "context_edition_m2_training_preflight_implementation_v0_1")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
temp_path <- tempfile(pattern = ".structural-tests-", tmpdir = output_dir)
utils::write.csv(test_results, temp_path, row.names = FALSE, na = "")
output_path <- file.path(output_dir, "structural_test_results.csv")
if (!file.rename(temp_path, output_path)) stop("failed to publish test results atomically", call. = FALSE)

sha256 <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  sub("[[:space:]].*$", "", output)
}
pre_fit_audit <- data.frame(
  preflight_version = "context_m2_training_preflight_v0.1.0",
  approved_design_commit = values[["approved_design_commit"]],
  pre_fit_implementation_commit = values[["pre_fit_implementation_commit"]],
  configuration_sha256 = sha256(config_path),
  runner_sha256 = sha256(runner_path),
  tests_sha256 = sha256(script_path),
  tests = nrow(test_results),
  passed = sum(test_results$passed),
  models_fit_by_test = 0L,
  preserved_d1_fit_count = 1L,
  m2_fit_count = 0L,
  historical_validation_outcomes_accessed = FALSE,
  prospective_2026_27_accessed = FALSE,
  stringsAsFactors = FALSE
)
temp_audit <- tempfile(pattern = ".pre-fit-audit-", tmpdir = output_dir)
utils::write.csv(pre_fit_audit, temp_audit, row.names = FALSE, na = "")
if (!file.rename(temp_audit, file.path(output_dir, "pre_fit_audit.csv"))) stop("failed to publish pre-fit audit", call. = FALSE)

message("All ", nrow(test_results), " M2 preflight implementation tests passed; no model or outcome data was opened.")
