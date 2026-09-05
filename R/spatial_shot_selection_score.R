# Frozen self-relative 0-100 Shot Selection Score.
#
# Audit mode verifies source artifacts without loading the model or sampling.
# Run mode regenerates the frozen CAR posterior draws and calculates only the
# approved 25% score. This script cannot fit a statistical model.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: Rscript R/spatial_shot_selection_score.R <season> <audit|run>",
    call. = FALSE
  )
}
season <- args[[1]]
mode <- args[[2]]
if (!identical(season, "2025-26")) {
  stop("The frozen score is registered only for 2025-26", call. = FALSE)
}
if (!mode %in% c("audit", "run")) {
  stop("Mode must be audit or run", call. = FALSE)
}

METHOD_ID <- "self-relative-shot-selection-score-25pct-v1"
RELOCATION_METHOD_ID <- "car-proportional-relocation-v1"
SCORE_SLIDER <- 0.25
POSTERIOR_DRAWS <- 4000L
POSTERIOR_SEED <- 20260902L
EXPECTED_PLAYERS <- 318L
EXPECTED_QUALIFIED <- 122L
EXPECTED_INSUFFICIENT <- 196L
GRID_CELLS <- 156L
EXPECTED_LATTICE_ROWS <- 49608L
DRAW_REPRO_TOLERANCE <- 1e-12
SUMMARY_REPRO_TOLERANCE <- 1e-12

PRODUCTION_RESULT_COMMIT <- "16a55dcc13f84279ccf9841c4bcc44c4e910333b"
RELOCATION_FREEZE_COMMIT <- "5c4cd112970756dea31e0fa295cb20afd4f01bb6"
TOLERANCE_COMMIT <- "4382a19abc188a16589954e119d7ff13daea9913"
RELOCATION_RESULT_COMMIT <- "d0844a93ed1e0231303ae52c81a133931b09442b"

EXPECTED_PRODUCTION_HASHES <- c(
  input = "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6",
  fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  completion = "c2d6c92b36981feaf5870a58fb7eca84eff399ddd7ed1c7ed39d649c932f923c"
)
EXPECTED_RELOCATION_COMPLETION_SHA256 <-
  "e06f32b9da196feb9692b66c7c821a0bbaa3aa38d3927990c7afda3c6fc045d4"
EXPECTED_RELOCATION_HASHES <- c(
  relocation_manifest.parquet = "664235d9f14287f07e1043a81130f0a327fc9533b39e7939e5c930122bb338a8",
  player_cell_support.parquet = "aa30d46ee54e4a9c3dce0594aeb66dac46fa5b8b833a9770f577b5b2c070832d",
  player_evidence.parquet = "7c4dda82739043e731c0fad34d7ae4182c758c090b1f5a51d9647ed07675b2c2",
  slider_results.parquet = "0418f1241158e91d9ac48b18244d75838b3badf43664e30d7151ef418848aff4",
  concentration_audit.parquet = "53556f2ab70fe2a2cdebcd0b70efff4d47bf28f1ea69c3e035a18fa9d12392fb",
  calculation_notices.parquet = "2c82724ab004520181359d61576af6445afd869d5d57caeec5adc41309b84e78",
  sanity_checks.parquet = "ccca6c25730af0e3a8cf50bfda90c55809c25259c913a29f45cf522f5b3f4427"
)
EXPECTED_VERSIONS <- c(
  R = "4.6.0", INLA = "26.8.7", Matrix = "1.7.5", fmesher = "0.8.0",
  sn = "2.1.3", arrow = "25.0.0", dplyr = "1.2.1"
)

production_cache <- file.path(
  "data", "cache", "spatial_car_production", paste0("season=", season)
)
relocation_cache <- file.path(
  "data", "cache", "spatial_relocation", paste0("season=", season)
)
relocation_result <- file.path(
  "data", "processed", "spatial_relocation", paste0("season=", season)
)
score_cache <- file.path(
  "data", "cache", "spatial_shot_selection_score", paste0("season=", season)
)
score_result <- file.path(
  "data", "processed", "spatial_shot_selection_score", paste0("season=", season)
)

production_paths <- c(
  input = file.path(production_cache, "production_input.rds"),
  fit = file.path(production_cache, "car_production_fit.rds"),
  surface = file.path(production_cache, "player_probability_surfaces.parquet"),
  completion = file.path(production_cache, "production_complete_checkpoint.rds")
)
relocation_completion_path <- file.path(
  relocation_cache, "relocation_complete.rds"
)
relocation_paths <- setNames(
  file.path(relocation_result, names(EXPECTED_RELOCATION_HASHES)),
  names(EXPECTED_RELOCATION_HASHES)
)
lock_path <- file.path(score_cache, "active_run.lock")
pending_completion_path <- file.path(score_cache, "score_complete.pending.rds")
completion_path <- file.path(score_cache, "score_complete.rds")

OUTPUT_FILES <- c(
  "score_manifest.parquet",
  "shot_selection_scores.parquet",
  "score_diagnostics.parquet",
  "calculation_notices.parquet",
  "sanity_checks.parquet"
)

checks <- list()
record_check <- function(area, check, condition, detail) {
  passed <- isTRUE(condition)
  checks[[length(checks) + 1L]] <<- tibble(
    area = area, check = check, passed = passed, detail = as.character(detail)
  )
  if (!passed) {
    stop("SCORE CHECK FAILED: ", check, " - ", detail, call. = FALSE)
  }
  invisible(TRUE)
}

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) stop("Could not hash ", path, call. = FALSE)
  strsplit(output, "[[:space:]]+")[[1]][[1]]
}

git_value <- function(arguments) {
  output <- system2("git", arguments, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop("Git verification failed: ", paste(output, collapse = " | "),
         call. = FALSE)
  }
  output
}

set_frozen_rng <- function(seed) {
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
}

capture_conditions <- function(expression) {
  warnings <- character()
  messages <- character()
  value <- withCallingHandlers(
    expression,
    warning = function(condition) {
      warnings <<- c(warnings, conditionMessage(condition))
      invokeRestart("muffleWarning")
    },
    message = function(condition) {
      messages <<- c(messages, conditionMessage(condition))
      invokeRestart("muffleMessage")
    }
  )
  list(value = value, warnings = unique(warnings), messages = unique(messages))
}

write_new_atomic_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) stop("Refusing to replace ", path, call. = FALSE)
  temporary <- tempfile(paste0(basename(path), ".partial-"), dirname(path))
  saveRDS(object, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not publish ", path, "; partial file preserved", call. = FALSE)
  }
  invisible(path)
}

write_new_atomic_parquet <- function(object, path) {
  if (file.exists(path)) stop("Refusing to replace ", path, call. = FALSE)
  temporary <- tempfile(
    paste0(basename(path), ".partial-"), dirname(path), fileext = ".parquet"
  )
  write_parquet(object, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not publish ", path, "; partial file preserved", call. = FALSE)
  }
  invisible(path)
}

quantile_value <- function(values, probability) {
  as.numeric(stats::quantile(values, probability, names = FALSE, type = 7))
}

score_draw_values <- function(baseline, relocated) {
  if (length(baseline) != length(relocated) ||
      any(!is.finite(baseline)) || any(!is.finite(relocated)) ||
      any(baseline <= 0) || any(relocated <= 0)) {
    stop("Score inputs must be paired, finite, and positive", call. = FALSE)
  }
  raw <- 100 * baseline / relocated
  list(raw = raw, display = pmin(pmax(raw, 0), 100))
}

verify_score_function <- function() {
  equal <- score_draw_values(c(1, 2), c(1, 2))
  record_check(
    "formula", "zero_gain_is_100",
    identical(equal$raw, c(100, 100)) &&
      identical(equal$display, c(100, 100)),
    "equal baseline and relocated efficiency gives score 100"
  )
  gain <- score_draw_values(c(1, 2), c(1.1, 2.2))
  record_check(
    "formula", "positive_gain_is_below_100",
    all(gain$raw < 100) && all(gain$display < 100),
    "higher relocated efficiency gives a score below 100"
  )
  adverse <- score_draw_values(1.1, 1)
  record_check(
    "formula", "raw_above_100_is_preserved_then_display_capped",
    adverse$raw > 100 && abs(adverse$raw - 110) <= 1e-12 &&
      identical(adverse$display, 100),
    "raw diagnostics retain 110 while the display draw is capped at 100"
  )
  invalid_failed <- vapply(
    list(
      function() score_draw_values(c(1, NA_real_), c(1, 1)),
      function() score_draw_values(Inf, 1),
      function() score_draw_values(0, 1),
      function() score_draw_values(1, -1)
    ),
    function(invalid_call) tryCatch({
      invalid_call()
      FALSE
    }, error = function(condition) TRUE),
    logical(1)
  )
  record_check(
    "formula", "invalid_inputs_fail",
    all(invalid_failed),
    "missing, infinite, or nonpositive inputs cannot enter division"
  )
}

extract_predictors <- function(samples, expected_indices) {
  labels <- rownames(samples[[1]]$latent)
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  if (is.null(labels) || anyNA(parsed) || !setequal(parsed, expected_indices)) {
    stop("Posterior predictor selection does not match the production lattice",
         call. = FALSE)
  }
  values <- vapply(
    samples, function(sample) as.numeric(sample$latent),
    numeric(length(expected_indices))
  )
  values[match(expected_indices, parsed), , drop = FALSE]
}

verify_versions <- function() {
  record_check(
    "configuration", "r_version",
    identical(paste(R.version$major, R.version$minor, sep = "."),
              EXPECTED_VERSIONS[["R"]]),
    paste("expected", EXPECTED_VERSIONS[["R"]])
  )
  for (package in setdiff(names(EXPECTED_VERSIONS), "R")) {
    found <- as.character(packageVersion(package))
    record_check(
      "configuration", paste0("package_", package),
      identical(found, EXPECTED_VERSIONS[[package]]),
      paste("expected", EXPECTED_VERSIONS[[package]], "found", found)
    )
  }
}

verify_source_artifacts <- function() {
  required_commits <- c(
    PRODUCTION_RESULT_COMMIT, RELOCATION_FREEZE_COMMIT, TOLERANCE_COMMIT,
    RELOCATION_RESULT_COMMIT
  )
  commit_status <- vapply(
    required_commits,
    function(commit) system2(
      "git", c("merge-base", "--is-ancestor", commit, "HEAD")
    ) == 0L,
    logical(1)
  )
  record_check(
    "history", "required_commits_in_history",
    all(commit_status),
    "production, relocation freeze, tolerance, and relocation results are ancestors"
  )
  record_check(
    "artifacts", "required_artifacts_exist",
    all(file.exists(production_paths)) &&
      file.exists(relocation_completion_path) &&
      all(file.exists(relocation_paths)),
    "production model, relocation completion, and seven relocation outputs"
  )
  observed_production <- vapply(
    production_paths, sha256_file, character(1)
  )
  record_check(
    "artifacts", "production_hashes_match",
    identical(observed_production, EXPECTED_PRODUCTION_HASHES),
    "production input, fit, surface, and completion hashes match"
  )
  record_check(
    "artifacts", "relocation_completion_hash_matches",
    identical(
      sha256_file(relocation_completion_path),
      EXPECTED_RELOCATION_COMPLETION_SHA256
    ),
    EXPECTED_RELOCATION_COMPLETION_SHA256
  )
  observed_relocation <- vapply(
    relocation_paths, sha256_file, character(1)
  )
  record_check(
    "artifacts", "relocation_output_hashes_match",
    identical(observed_relocation, EXPECTED_RELOCATION_HASHES),
    "all seven compact relocation output hashes match"
  )

  production_completion <- readRDS(production_paths[["completion"]])
  relocation_completion <- readRDS(relocation_completion_path)
  relocation_manifest <- read_parquet(
    relocation_paths[["relocation_manifest.parquet"]]
  )
  cells <- read_parquet(relocation_paths[["player_cell_support.parquet"]]) |>
    arrange(PLAYER_ID, cell_id)
  evidence <- read_parquet(relocation_paths[["player_evidence.parquet"]]) |>
    arrange(PLAYER_ID)
  slider_25 <- read_parquet(relocation_paths[["slider_results.parquet"]]) |>
    filter(slider_fraction == SCORE_SLIDER) |>
    arrange(PLAYER_ID)
  input <- readRDS(production_paths[["input"]])

  record_check(
    "production", "production_completion_valid",
    isTRUE(production_completion$complete) &&
      all(production_completion$checks$passed) &&
      production_completion$player_count == EXPECTED_PLAYERS &&
      production_completion$lattice_rows == EXPECTED_LATTICE_ROWS,
    "verified 318-player production CAR completion"
  )
  record_check(
    "relocation", "relocation_completion_valid",
    isTRUE(relocation_completion$complete) &&
      identical(relocation_completion$method_id, RELOCATION_METHOD_ID) &&
      all(relocation_completion$checks$passed) &&
      identical(relocation_completion$output_hashes,
                EXPECTED_RELOCATION_HASHES) &&
      relocation_completion$supported_player_count == EXPECTED_QUALIFIED &&
      relocation_completion$insufficient_supported_player_count ==
        EXPECTED_INSUFFICIENT,
    "verified atomic relocation result with 122 qualified players"
  )
  record_check(
    "relocation", "relocation_manifest_valid",
    nrow(relocation_manifest) == 1L &&
      relocation_manifest$method_id[[1]] == RELOCATION_METHOD_ID &&
      isTRUE(relocation_manifest$verification_passed[[1]]) &&
      !isTRUE(relocation_manifest$model_refit[[1]]) &&
      !isTRUE(relocation_manifest$score_created[[1]]),
    "relocation completed without a model refit or score calculation"
  )
  record_check(
    "relocation", "source_dimensions_and_statuses",
    nrow(cells) == EXPECTED_LATTICE_ROWS &&
      all(count(cells, PLAYER_ID)$n == GRID_CELLS) &&
      !anyDuplicated(cells[c("PLAYER_ID", "cell_id")]) &&
      nrow(evidence) == EXPECTED_PLAYERS &&
      !anyDuplicated(evidence$PLAYER_ID) &&
      sum(evidence$evidence_status == "estimated") == EXPECTED_QUALIFIED &&
      sum(evidence$evidence_status ==
            "insufficient_supported_destinations") == EXPECTED_INSUFFICIENT &&
      nrow(slider_25) == EXPECTED_PLAYERS &&
      !anyDuplicated(slider_25$PLAYER_ID),
    "49,608 cells, 318 evidence rows, and one frozen 25% row per player"
  )
  record_check(
    "input", "production_lattice_matches_relocation_cells",
    nrow(input$lattice) == EXPECTED_LATTICE_ROWS &&
      identical(input$player_ids, evidence$PLAYER_ID) &&
      identical(
        input$lattice |> arrange(PLAYER_ID, cell_id) |>
          select(PLAYER_ID, cell_id, attempts),
        cells |> select(PLAYER_ID, cell_id, attempts)
      ),
    "production predictor lattice and frozen relocation cells match"
  )
  list(
    input = input, cells = cells, evidence = evidence, slider_25 = slider_25,
    production_completion = production_completion,
    relocation_completion = relocation_completion
  )
}

verify_git_freeze <- function() {
  head <- git_value(c("rev-parse", "HEAD"))[[1]]
  origin <- git_value(
    c("rev-parse", "origin/codex/spatial-shot-selection")
  )[[1]]
  clean <- system2("git", c("diff", "--quiet")) == 0L &&
    system2("git", c("diff", "--cached", "--quiet")) == 0L
  record_check(
    "freeze", "pre_result_commit_pushed",
    identical(head, origin) && clean &&
      system2("git", c("merge-base", "--is-ancestor",
                       RELOCATION_RESULT_COMMIT, head)) == 0L,
    paste("clean local and origin revision", head)
  )
  head
}

acquire_lock <- function() {
  dir.create(score_cache, recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    stop("Score lock exists; inspect it before recovery", call. = FALSE)
  }
  write_new_atomic_rds(
    list(
      pid = Sys.getpid(),
      started_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    ),
    file.path(lock_path, "owner.rds")
  )
}

verify_output_bundle <- function(directory, expected_hashes = NULL) {
  paths <- file.path(directory, OUTPUT_FILES)
  if (!all(file.exists(paths))) return(FALSE)
  observed <- vapply(paths, sha256_file, character(1))
  names(observed) <- OUTPUT_FILES
  if (!is.null(expected_hashes) && !identical(observed, expected_hashes)) {
    return(FALSE)
  }
  TRUE
}

recover_completion <- function() {
  marker <- if (file.exists(completion_path)) completion_path else
    if (file.exists(pending_completion_path)) pending_completion_path else NULL
  if (is.null(marker)) return(NULL)
  completed <- readRDS(marker)
  valid <- isTRUE(completed$complete) &&
    identical(completed$method_id, METHOD_ID) &&
    identical(completed$production_hashes, EXPECTED_PRODUCTION_HASHES) &&
    identical(completed$relocation_hashes, EXPECTED_RELOCATION_HASHES) &&
    identical(completed$relocation_completion_sha256,
              EXPECTED_RELOCATION_COMPLETION_SHA256) &&
    verify_output_bundle(score_result, completed$output_hashes) &&
    all(completed$checks$passed)
  if (!valid) stop("Existing score completion is invalid and preserved",
                   call. = FALSE)
  if (identical(marker, pending_completion_path)) {
    if (!file.rename(pending_completion_path, completion_path)) {
      stop("Could not finalize valid pending score completion", call. = FALSE)
    }
  }
  completed
}

run_score <- function(audit) {
  recovered <- recover_completion()
  if (!is.null(recovered)) {
    message("Reused verified atomic score result; no draws recalculated")
    print(read_parquet(file.path(score_result, "score_manifest.parquet")))
    return(invisible(recovered))
  }
  staging_paths <- Sys.glob(paste0(score_result, ".partial-*"))
  if (dir.exists(score_result) ||
      length(list.files(score_cache, pattern = "partial")) > 0L ||
      length(staging_paths) > 0L) {
    stop("Partial score artifacts exist and were preserved", call. = FALSE)
  }
  pre_result_commit <- verify_git_freeze()
  acquire_lock()
  success <- FALSE
  on.exit({
    if (success && dir.exists(lock_path)) unlink(lock_path, recursive = TRUE)
  }, add = TRUE)
  started <- proc.time()[["elapsed"]]

  input <- audit$input
  cells <- audit$cells
  evidence <- audit$evidence
  slider_25 <- audit$slider_25
  lattice <- input$lattice |>
    arrange(PLAYER_ID, cell_id)
  record_check(
    "input", "predictor_order",
    identical(lattice$predictor_index, seq_len(EXPECTED_LATTICE_ROWS)),
    "saved predictor indices match the ordered production lattice"
  )
  record_check(
    "relocation", "frozen_support_weights",
    all(cells$supported_allocation_weight >= 0) &&
      all(cells$supported_allocation_weight[!cells$supported_destination] == 0),
    "score reuses the published support set and allocation weights"
  )

  fit <- readRDS(production_paths[["fit"]])
  record_check(
    "model", "saved_fit_valid",
    isTRUE(fit$ok) && identical(as.numeric(fit$mode$mode.status), 0) &&
      nrow(fit$summary.linear.predictor) == EXPECTED_LATTICE_ROWS,
    "verified production fit loaded; this script contains no model-fitting call"
  )
  set_frozen_rng(POSTERIOR_SEED)
  captured <- capture_conditions(INLA::inla.posterior.sample(
    n = POSTERIOR_DRAWS,
    result = fit,
    selection = list(Predictor = lattice$predictor_index),
    seed = POSTERIOR_SEED,
    num.threads = 1L,
    parallel.configs = FALSE,
    add.names = FALSE
  ))
  probability_draws <- extract_predictors(
    captured$value, lattice$predictor_index
  )
  calculation_notices <- bind_rows(
    tibble(
      type = rep("warning", length(captured$warnings)),
      message = captured$warnings
    ),
    tibble(
      type = rep("message", length(captured$messages)),
      message = captured$messages
    )
  )
  captured$value <- NULL
  rm(captured, fit)
  probability_draws[] <- plogis(probability_draws)
  gc()
  record_check(
    "posterior", "draw_dimensions_and_bounds",
    nrow(probability_draws) == EXPECTED_LATTICE_ROWS &&
      ncol(probability_draws) == POSTERIOR_DRAWS &&
      all(is.finite(probability_draws)) &&
      all(probability_draws >= 0 & probability_draws <= 1),
    "49,608 x 4,000 finite CAR probability draws"
  )
  saved_surface <- read_parquet(production_paths[["surface"]]) |>
    arrange(PLAYER_ID, cell_id)
  draw_mean_difference <- max(abs(
    rowMeans(probability_draws) - saved_surface$draw_mean_probability
  ))
  record_check(
    "posterior", "draws_reproduce_production_surface",
    is.finite(draw_mean_difference) &&
      draw_mean_difference <= DRAW_REPRO_TOLERANCE,
    paste("maximum draw-mean probability difference", draw_mean_difference)
  )

  player_ids <- input$player_ids
  score_rows <- vector("list", length(player_ids))
  baseline_mean <- rep(NA_real_, length(player_ids))
  relocated_mean <- rep(NA_real_, length(player_ids))
  for (player_index in seq_along(player_ids)) {
    player_id <- player_ids[[player_index]]
    rows <- which(cells$PLAYER_ID == player_id)
    player_evidence <- evidence[player_index, ]
    point_values <- coalesce(cells$point_value[rows], 0)
    baseline_weights <- cells$baseline_share[rows] * point_values
    baseline <- colSums(
      probability_draws[rows, , drop = FALSE] * baseline_weights
    )
    baseline_mean[[player_index]] <- mean(baseline)
    qualified <- player_evidence$evidence_status == "estimated"
    if (!qualified) {
      score_rows[[player_index]] <- tibble(
        PLAYER_ID = player_id,
        PLAYER_NAME = player_evidence$PLAYER_NAME,
        evidence_status = "insufficient_evidence",
        baseline_expected_points_per_shot = median(baseline),
        expected_points_per_shot_after_25pct_relocation = NA_real_,
        raw_score = NA_real_,
        raw_score_lower_90 = NA_real_,
        raw_score_upper_90 = NA_real_,
        display_score = NA_real_,
        display_score_lower_90 = NA_real_,
        display_score_upper_90 = NA_real_,
        raw_draws_above_100 = NA_integer_,
        posterior_draws = NA_integer_
      )
      next
    }
    q <- (1 - SCORE_SLIDER) * cells$baseline_share[rows] +
      SCORE_SLIDER * cells$supported_allocation_weight[rows]
    relocated <- colSums(
      probability_draws[rows, , drop = FALSE] * (q * point_values)
    )
    relocated_mean[[player_index]] <- mean(relocated)
    score_values <- score_draw_values(baseline, relocated)
    score_rows[[player_index]] <- tibble(
      PLAYER_ID = player_id,
      PLAYER_NAME = player_evidence$PLAYER_NAME,
      evidence_status = "qualified",
      baseline_expected_points_per_shot = median(baseline),
      expected_points_per_shot_after_25pct_relocation = median(relocated),
      raw_score = median(score_values$raw),
      raw_score_lower_90 = quantile_value(score_values$raw, 0.05),
      raw_score_upper_90 = quantile_value(score_values$raw, 0.95),
      display_score = median(score_values$display),
      display_score_lower_90 = quantile_value(score_values$display, 0.05),
      display_score_upper_90 = quantile_value(score_values$display, 0.95),
      raw_draws_above_100 = as.integer(sum(score_values$raw > 100)),
      posterior_draws = POSTERIOR_DRAWS
    )
  }
  scores <- bind_rows(score_rows) |>
    mutate(
      score_method_version = METHOD_ID,
      production_fit_sha256 = EXPECTED_PRODUCTION_HASHES[["fit"]],
      relocation_completion_sha256 = EXPECTED_RELOCATION_COMPLETION_SHA256
    ) |>
    arrange(PLAYER_ID)

  qualified_scores <- scores |> filter(evidence_status == "qualified")
  insufficient_scores <- scores |>
    filter(evidence_status == "insufficient_evidence")
  qualified_index <- evidence$evidence_status == "estimated"
  baseline_reproduction_difference <- max(abs(
    baseline_mean - slider_25$baseline_expected_points_per_shot
  ))
  relocated_reproduction_difference <- max(abs(
    relocated_mean[qualified_index] -
      slider_25$relocated_expected_points_per_shot[qualified_index]
  ))
  score_fields <- c(
    "expected_points_per_shot_after_25pct_relocation",
    "raw_score", "raw_score_lower_90", "raw_score_upper_90",
    "display_score", "display_score_lower_90", "display_score_upper_90",
    "raw_draws_above_100", "posterior_draws"
  )

  record_check(
    "results", "one_row_per_player",
    nrow(scores) == EXPECTED_PLAYERS && !anyDuplicated(scores$PLAYER_ID) &&
      identical(scores$PLAYER_ID, input$player_ids),
    "318 ordered player rows"
  )
  record_check(
    "eligibility", "qualified_and_insufficient_counts",
    nrow(qualified_scores) == EXPECTED_QUALIFIED &&
      nrow(insufficient_scores) == EXPECTED_INSUFFICIENT,
    "122 qualified and 196 insufficient-evidence players"
  )
  record_check(
    "eligibility", "insufficient_score_fields_missing",
    all(is.na(as.matrix(insufficient_scores[score_fields]))),
    "insufficient-evidence players have no score or relocated estimate"
  )
  record_check(
    "formula", "positive_efficiencies_before_division",
    all(qualified_scores$baseline_expected_points_per_shot > 0) &&
      all(qualified_scores$expected_points_per_shot_after_25pct_relocation > 0),
    "all qualified median efficiencies are positive"
  )
  record_check(
    "formula", "qualified_scores_finite_and_raw_preserved",
    all(is.finite(as.matrix(qualified_scores[score_fields]))) &&
      all(qualified_scores$raw_score > 0) &&
      all(qualified_scores$raw_score_lower_90 > 0),
    "qualified raw and displayed summaries are finite"
  )
  record_check(
    "display", "display_scores_bounded",
    all(as.matrix(qualified_scores[c(
      "display_score", "display_score_lower_90", "display_score_upper_90"
    )]) >= 0) &&
      all(as.matrix(qualified_scores[c(
        "display_score", "display_score_lower_90", "display_score_upper_90"
      )]) <= 100),
    "display point estimates and bounds stay within 0 to 100"
  )
  record_check(
    "uncertainty", "intervals_ordered",
    all(qualified_scores$raw_score_lower_90 <= qualified_scores$raw_score) &&
      all(qualified_scores$raw_score <= qualified_scores$raw_score_upper_90) &&
      all(qualified_scores$display_score_lower_90 <=
            qualified_scores$display_score) &&
      all(qualified_scores$display_score <=
            qualified_scores$display_score_upper_90),
    "raw and displayed 90% score intervals are ordered"
  )
  record_check(
    "reproducibility", "relocation_summaries_reproduced",
    baseline_reproduction_difference <= SUMMARY_REPRO_TOLERANCE &&
      relocated_reproduction_difference <= SUMMARY_REPRO_TOLERANCE,
    paste(
      "maximum baseline-mean difference", baseline_reproduction_difference,
      "maximum 25%-relocated-mean difference",
      relocated_reproduction_difference
    )
  )
  record_check(
    "interpretation", "positive_median_gain_scores_below_100",
    all(
      qualified_scores$expected_points_per_shot_after_25pct_relocation >
        qualified_scores$baseline_expected_points_per_shot
    ) && all(qualified_scores$display_score < 100),
    "each qualified player has positive median modeled gain and score below 100"
  )
  record_check(
    "schema", "no_ranking_or_league_normalization",
    !any(grepl("rank|percentile|league|label", names(scores), ignore.case = TRUE)),
    "score output contains no rank, percentile, league comparison, or label"
  )

  diagnostics <- qualified_scores |>
    summarise(
      qualified_player_count = n(),
      insufficient_evidence_player_count = nrow(insufficient_scores),
      posterior_draws_per_qualified_player = POSTERIOR_DRAWS,
      qualified_posterior_draw_count = n() * POSTERIOR_DRAWS,
      players_with_raw_draws_above_100 = sum(raw_draws_above_100 > 0),
      raw_draws_above_100 = sum(raw_draws_above_100),
      raw_draws_above_100_share =
        sum(raw_draws_above_100) / (n() * POSTERIOR_DRAWS),
      minimum_display_score = min(display_score),
      first_quartile_display_score = quantile_value(display_score, 0.25),
      median_display_score = median(display_score),
      third_quartile_display_score = quantile_value(display_score, 0.75),
      maximum_display_score = max(display_score),
      display_score_iqr = IQR(display_score, type = 7),
      players_at_or_above_95 = sum(display_score >= 95),
      share_at_or_above_95 = mean(display_score >= 95),
      players_at_or_above_99 = sum(display_score >= 99),
      share_at_or_above_99 = mean(display_score >= 99),
      players_at_100 = sum(display_score == 100),
      share_at_100 = mean(display_score == 100)
    )
  record_check(
    "diagnostics", "draw_count_accounting",
    diagnostics$qualified_posterior_draw_count ==
      EXPECTED_QUALIFIED * POSTERIOR_DRAWS &&
      diagnostics$raw_draws_above_100 >= 0 &&
      diagnostics$raw_draws_above_100 <=
        diagnostics$qualified_posterior_draw_count,
    "488,000 qualified draw-level scores accounted for"
  )
  record_check(
    "diagnostics", "distribution_complete",
    all(is.finite(as.matrix(diagnostics))) &&
      diagnostics$minimum_display_score <= diagnostics$median_display_score &&
      diagnostics$median_display_score <= diagnostics$maximum_display_score &&
      diagnostics$display_score_iqr >= 0,
    "minimum, quartiles, median, maximum, IQR, and near-100 counts are finite"
  )

  final_checks <- bind_rows(checks)
  record_check(
    "publication", "all_checks_pass_before_publication",
    all(final_checks$passed),
    paste(nrow(final_checks), "checks passed before publication")
  )
  final_checks <- bind_rows(checks)
  elapsed <- proc.time()[["elapsed"]] - started

  staging <- paste0(score_result, ".partial-", Sys.getpid())
  dir.create(dirname(score_result), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(staging, recursive = FALSE, showWarnings = FALSE)) {
    stop("Could not create score staging directory", call. = FALSE)
  }
  write_new_atomic_parquet(
    scores, file.path(staging, "shot_selection_scores.parquet")
  )
  write_new_atomic_parquet(
    diagnostics, file.path(staging, "score_diagnostics.parquet")
  )
  write_new_atomic_parquet(
    calculation_notices, file.path(staging, "calculation_notices.parquet")
  )
  write_new_atomic_parquet(
    final_checks, file.path(staging, "sanity_checks.parquet")
  )
  non_manifest_files <- setdiff(OUTPUT_FILES, "score_manifest.parquet")
  non_manifest_hashes <- vapply(
    file.path(staging, non_manifest_files), sha256_file, character(1)
  )
  names(non_manifest_hashes) <- non_manifest_files
  manifest <- tibble(
    season = season,
    method_id = METHOD_ID,
    status = "descriptive_self_relative_score_not_causal",
    pre_result_commit = pre_result_commit,
    production_result_commit = PRODUCTION_RESULT_COMMIT,
    relocation_result_commit = RELOCATION_RESULT_COMMIT,
    production_fit_sha256 = EXPECTED_PRODUCTION_HASHES[["fit"]],
    production_completion_sha256 = EXPECTED_PRODUCTION_HASHES[["completion"]],
    relocation_completion_sha256 = EXPECTED_RELOCATION_COMPLETION_SHA256,
    player_count = EXPECTED_PLAYERS,
    qualified_player_count = EXPECTED_QUALIFIED,
    insufficient_evidence_player_count = EXPECTED_INSUFFICIENT,
    score_slider_fraction = SCORE_SLIDER,
    posterior_draws = POSTERIOR_DRAWS,
    posterior_seed = POSTERIOR_SEED,
    draw_formula = "100 * baseline expected points per shot / 25%-relocated expected points per shot",
    point_estimate = "posterior median of draw-level score",
    interval = "posterior 5th to 95th percentile",
    display_cap = "draw-level pmin(pmax(raw_score, 0), 100)",
    stored_precision = "full numerical precision; one decimal recommended for future display",
    raw_draws_above_100 = diagnostics$raw_draws_above_100,
    raw_draws_above_100_share = diagnostics$raw_draws_above_100_share,
    calculation_elapsed_sec = elapsed,
    draw_mean_reproduction_max_abs_difference = draw_mean_difference,
    baseline_mean_reproduction_max_abs_difference =
      baseline_reproduction_difference,
    relocated_mean_reproduction_max_abs_difference =
      relocated_reproduction_difference,
    posterior_warning_count = sum(calculation_notices$type == "warning"),
    posterior_message_count = sum(calculation_notices$type == "message"),
    model_refit = FALSE,
    relocation_rerun = FALSE,
    other_slider_scores_calculated = FALSE,
    league_normalization_used = FALSE,
    ranking_created = FALSE,
    website_modified = FALSE,
    verification_passed = all(final_checks$passed),
    r_version = EXPECTED_VERSIONS[["R"]],
    inla_version = EXPECTED_VERSIONS[["INLA"]],
    arrow_version = EXPECTED_VERSIONS[["arrow"]],
    dplyr_version = EXPECTED_VERSIONS[["dplyr"]]
  )
  for (file_name in non_manifest_files) {
    hash_name <- paste0(sub("\\.parquet$", "", file_name), "_sha256")
    manifest[[hash_name]] <- non_manifest_hashes[[file_name]]
  }
  write_new_atomic_parquet(
    manifest, file.path(staging, "score_manifest.parquet")
  )
  output_hashes <- vapply(
    file.path(staging, OUTPUT_FILES), sha256_file, character(1)
  )
  names(output_hashes) <- OUTPUT_FILES
  completion <- list(
    complete = TRUE,
    method_id = METHOD_ID,
    pre_result_commit = pre_result_commit,
    production_hashes = EXPECTED_PRODUCTION_HASHES,
    relocation_completion_sha256 = EXPECTED_RELOCATION_COMPLETION_SHA256,
    relocation_hashes = EXPECTED_RELOCATION_HASHES,
    output_hashes = output_hashes,
    qualified_player_count = EXPECTED_QUALIFIED,
    insufficient_evidence_player_count = EXPECTED_INSUFFICIENT,
    checks = final_checks,
    completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  write_new_atomic_rds(completion, pending_completion_path)
  if (!file.rename(staging, score_result)) {
    stop("Could not publish score result directory", call. = FALSE)
  }
  if (!file.rename(pending_completion_path, completion_path)) {
    stop("Score results are complete but the marker remains pending",
         call. = FALSE)
  }
  success <- TRUE
  print(manifest, width = Inf)
  invisible(completion)
}

verify_score_function()
verify_versions()
audit <- verify_source_artifacts()

if (mode == "audit") {
  print(tibble(
    season = season,
    method_id = METHOD_ID,
    mode = mode,
    players = nrow(audit$evidence),
    qualified_players = sum(audit$evidence$evidence_status == "estimated"),
    insufficient_evidence_players =
      sum(audit$evidence$evidence_status != "estimated"),
    score_slider_fraction = SCORE_SLIDER,
    posterior_draws = POSTERIOR_DRAWS,
    model_loaded = FALSE,
    posterior_sampled = FALSE,
    score_calculated = FALSE,
    all_checks_passed = all(bind_rows(checks)$passed)
  ), width = Inf)
  quit(save = "no", status = 0L)
}

run_score(audit)
