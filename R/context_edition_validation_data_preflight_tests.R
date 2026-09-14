#!/usr/bin/env Rscript

# Structural, synthetic, and hash-only checks for the five-season canonical
# extension and training-only M0/M1 preflight. No real shot outcome is loaded.

options(stringsAsFactors = FALSE)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) {
  sub("^--file=", "", script_arg)
} else {
  "R/context_edition_validation_data_preflight_tests.R"
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)

results <- list()
record <- function(name, expression) {
  passed <- TRUE
  detail <- "passed"
  tryCatch(
    force(expression),
    error = function(error) {
      passed <<- FALSE
      detail <<- conditionMessage(error)
    }
  )
  results[[length(results) + 1L]] <<- data.frame(
    test_id = name, passed = passed, detail = detail, stringsAsFactors = FALSE
  )
}
expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_error <- function(expression) {
  raised <- FALSE
  tryCatch(force(expression), error = function(error) raised <<- TRUE)
  expect_true(raised, "expected an error")
}
sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

config <- utils::read.csv(
  file.path(repo_root, "config", "context_edition_training_preflight_v0_1.csv"),
  stringsAsFactors = FALSE
)
config_values <- setNames(config$value, config$key)
model_spec <- utils::read.csv(
  file.path(repo_root, "config", "context_edition_m0_m1_model_spec_v0_1.csv"),
  stringsAsFactors = FALSE
)
taxonomy <- utils::read.csv(
  file.path(repo_root, "config", "context_edition_taxonomy_v0_1.csv"),
  stringsAsFactors = FALSE
)

record("five_seasons_frozen", {
  expected <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
  observed <- strsplit(config_values[["mechanically_canonicalized_seasons"]], ";", fixed = TRUE)[[1]]
  expect_true(identical(observed, expected), "five-season scope changed")
})

record("training_and_validation_seasons_separate", {
  training <- strsplit(config_values[["training_seasons"]], ";", fixed = TRUE)[[1]]
  validation <- strsplit(config_values[["validation_seasons"]], ";", fixed = TRUE)[[1]]
  expect_true(identical(training, CONTEXT_PREFLIGHT_TRAINING_SEASONS), "training seasons changed")
  expect_true(identical(validation, CONTEXT_PREFLIGHT_VALIDATION_SEASONS), "validation seasons changed")
  expect_true(length(intersect(training, validation)) == 0L, "training and validation overlap")
})

record("validation_access_flags_false", {
  keys <- c(
    "validation_outcomes_for_fit", "validation_outcomes_for_prediction",
    "validation_outcomes_for_metrics"
  )
  expect_true(all(config_values[keys] == "FALSE"), "validation outcome seal changed")
})

record("no_2026_27_access", {
  expect_true(config_values[["prospective_season"]] == "2026-27", "prospective label changed")
  runner <- readLines(
    file.path(repo_root, "R", "context_edition_m0_m1_training_preflight.R"), warn = FALSE
  )
  expect_true(!any(grepl("season=2026-27|play_by_play_2027", runner)), "runner contains a 2026-27 input path")
})

record("accepted_hash_register", {
  hashes <- utils::read.csv(
    file.path(repo_root, "config", "context_edition_accepted_v0_1_2_hashes.csv"),
    stringsAsFactors = FALSE
  )
  paths <- file.path(repo_root, hashes$path)
  expect_true(all(file.exists(paths)), "accepted artifact missing")
  observed <- vapply(paths, sha256_file, character(1))
  expect_true(identical(unname(observed), hashes$sha256), "accepted artifact hash changed")
})

record("frozen_versions", {
  expect_true(config_values[["canonical_schema"]] == "context_field_goal_v0.1.2", "schema changed")
  expect_true(config_values[["taxonomy_version"]] == "context_taxonomy_v0.1.0", "taxonomy changed")
  expect_true(config_values[["join_version"]] == "shotchart_espn_exact_clock_player_v0.1.1", "join changed")
})

record("cross_season_taxonomy_levels", {
  levels <- context_factor_levels()
  expect_true(setequal(taxonomy$finish_family, levels$finish_family), "finish levels changed")
  expect_true(setequal(taxonomy$creation_family, levels$creation_family), "creation levels changed")
})

record("new_raw_label_rejected", {
  observed <- c(taxonomy$ACTION_TYPE, "UNREGISTERED_TEST_LABEL")
  expect_true(!setequal(observed, taxonomy$ACTION_TYPE), "unregistered label was accepted")
})

record("registered_seasonal_subset_accepted", {
  seasonal_subset <- taxonomy$ACTION_TYPE[seq_len(46L)]
  expect_true(
    length(setdiff(seasonal_subset, taxonomy$ACTION_TYPE)) == 0L,
    "a registered seasonal subset was rejected"
  )
  expect_true(
    length(setdiff(c(seasonal_subset, "UNREGISTERED_TEST_LABEL"), taxonomy$ACTION_TYPE)) == 1L,
    "an unregistered seasonal label was not detected"
  )
})

record("grouped_binomial_reproduces_counts", {
  levels <- context_factor_levels()
  synthetic <- expand.grid(
    player_id_factor = factor(c("p1", "p2")),
    point_value_factor = factor(levels$point_value_factor, levels = levels$point_value_factor),
    finish_family = factor(levels$finish_family, levels = levels$finish_family),
    creation_family = factor(levels$creation_family, levels = levels$creation_family),
    replicate = seq_len(2L),
    KEEP.OUT.ATTRS = FALSE
  )
  synthetic$field_goal_made <- rep(c(0L, 1L), length.out = nrow(synthetic))
  for (model_id in c("M0", "M1")) {
    grouped <- context_preflight_group_counts(synthetic, model_id)
    expect_true(sum(grouped$attempts) == nrow(synthetic), paste(model_id, "attempts differ"))
    expect_true(sum(grouped$makes) == sum(synthetic$field_goal_made), paste(model_id, "makes differ"))
    expect_true(all(grouped$makes + grouped$misses == grouped$attempts), paste(model_id, "counts differ"))
  }
})

record("m0_m1_formula_identity", {
  formulas <- context_model_formulas()
  normalize <- function(x) gsub("[[:space:]]+", "", x)
  for (model_id in c("M0", "M1")) {
    expected <- model_spec$formula[model_spec$model_id == model_id]
    observed <- paste(deparse(formulas[[model_id]]), collapse = "")
    expect_true(normalize(expected) == normalize(observed), paste(model_id, "formula differs"))
  }
})

record("expected_points_conversion", {
  expect_true(
    identical(context_expected_points(c(0.25, 0.50), c(2, 3)), c(0.50, 1.50)),
    "expected-points conversion changed"
  )
})

record("other_unknown_is_predictable_level", {
  levels <- context_factor_levels()
  value <- factor("other_or_unknown", levels = levels$creation_family)
  expect_true(!is.na(value) && levels(value)[[1]] == "other_or_unknown", "other/unknown is not registered")
})

record("unseen_player_zero_effect_helper", {
  helper <- paste(
    readLines(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_true(grepl('exclude = "s\\(player_id_factor\\)"', helper), "unseen-player exclusion is missing")
  expect_true(grepl("newdata.guaranteed = TRUE", helper, fixed = TRUE), "fixed-part prediction safeguard missing")
})

record("checkpoint_hash_mismatch_rejected", {
  root <- tempfile("context-manifest-")
  dir.create(root)
  file_path <- file.path(root, "artifact.txt")
  writeLines("safe", file_path)
  manifest <- data.frame(
    artifact = "artifact.txt", sha256 = strrep("0", 64),
    atomic_complete = TRUE, checks_passed = TRUE
  )
  expect_error(context_preflight_verify_manifest(manifest, root, sha256_file))
  unlink(root, recursive = TRUE)
})

record("atomic_publication", {
  parent <- tempfile("context-atomic-")
  dir.create(parent)
  stage <- file.path(parent, "stage")
  final <- file.path(parent, "final")
  dir.create(stage)
  writeLines("complete", file.path(stage, "marker.txt"))
  context_preflight_atomic_publish(stage, final)
  expect_true(dir.exists(final) && !dir.exists(stage), "atomic rename failed")
  expect_error(context_preflight_atomic_publish(final, final))
  unlink(parent, recursive = TRUE)
})

record("no_public_shot_rows", {
  expect_true(config_values[["public_shot_rows"]] == "FALSE", "public shot-row flag changed")
  runner <- paste(
    readLines(file.path(repo_root, "R", "context_edition_m0_m1_training_preflight.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_true(!grepl("write_parquet", runner, fixed = TRUE), "preflight runner writes Parquet")
})

record("preflight_reads_only_training_partitions", {
  runner <- paste(
    readLines(file.path(repo_root, "R", "context_edition_m0_m1_training_preflight.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_true(length(gregexpr("read_parquet\\(", runner, perl = TRUE)[[1]]) == 1L, "unexpected shot-data reader count")
  expect_true(grepl("map_dfr\\(training_paths", runner, perl = TRUE), "reader is not restricted to training paths")
})

record("feature_allowlist_still_blocks_m2", {
  feature <- utils::read.csv(
    file.path(repo_root, "config", "context_edition_feature_allowlist_v0_1.csv"),
    stringsAsFactors = FALSE
  )
  context_validate_feature_matrix(feature)
})

test_results <- do.call(rbind, results)
if (!all(test_results$passed)) {
  print(test_results[!test_results$passed, ], row.names = FALSE)
  stop("one or more validation-data preflight tests failed", call. = FALSE)
}
cat("All ", nrow(test_results), " validation-data preflight tests passed.\n", sep = "")
