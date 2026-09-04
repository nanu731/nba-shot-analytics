# Frozen proportional relocation calculation using the selected production CAR.
#
# Audit mode verifies metadata and hashes without loading the fit or sampling.
# Run mode is the only path that recreates the frozen posterior draws and
# calculates relocation summaries. It cannot fit a statistical model.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript R/spatial_relocation.R <season> <audit|run>", call. = FALSE)
}
season <- args[[1]]
mode <- args[[2]]
if (!identical(season, "2025-26")) {
  stop("The frozen relocation calculation is registered only for 2025-26",
       call. = FALSE)
}
if (!mode %in% c("audit", "run")) {
  stop("Mode must be audit or run", call. = FALSE)
}

METHOD_ID <- "car-proportional-relocation-v1"
SLIDERS <- c(0, 0.05, 0.10, 0.15, 0.20, 0.25)
MIN_ATTEMPTS <- 10L
MIN_CERTAINTY <- 0.90
MIN_DESTINATIONS <- 2L
POSTERIOR_DRAWS <- 4000L
POSTERIOR_SEED <- 20260902L
GRID_WIDTH <- 40L
GRID_CELLS <- 156L
EXPECTED_PLAYERS <- 318L
EXPECTED_SHOTS <- 194987L
EXPECTED_OBSERVED_CELLS <- 22447L
EXPECTED_LATTICE_ROWS <- 49608L
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
DRAW_REPRO_TOLERANCE <- 1e-12
MASS_TOLERANCE <- 1e-12

PLANNING_COMMIT <- "2e31f43e750d88c17f5a1d265a595acb80fbdd85"
PRODUCTION_RESULT_COMMIT <- "16a55dcc13f84279ccf9841c4bcc44c4e910333b"
FINAL_RESULT_COMMIT <- "f7d7a155f49cd33b8fcb5978a90f62b2a6ae84c3"
EXPECTED_HASHES <- c(
  production_manifest = "ccf887be231989019eacb93601beb5de74c5aeaa1c4ba52b3365a6bb71748c89",
  input = "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6",
  configuration = "fc072f03e0579f32eba941717c4c8767912b72f82584d7e4842c6dab2699a80e",
  fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  uncertainty = "7894ac8ad170712928a3842711a403d43bb20fd56022762af270ae26d9c97d9e",
  hyperparameter = "2b758b71395431755d357d41bdf9fd54c8215de0ce5bbb62fdc6235643514627",
  model_checkpoint = "69592bb1d2d07ea2c799309026ab0ae0cb1b7841476aeb1b1c9940115be9ccaf",
  completion = "c2d6c92b36981feaf5870a58fb7eca84eff399ddd7ed1c7ed39d649c932f923c"
)
EXPECTED_RAW_SHA256 <- "20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498"
EXPECTED_VERSIONS <- c(
  R = "4.6.0", INLA = "26.8.7", Matrix = "1.7.5", fmesher = "0.8.0",
  sn = "2.1.3", arrow = "25.0.0", dplyr = "1.2.1", tidyr = "1.3.2"
)

production_cache <- file.path(
  "data", "cache", "spatial_car_production", paste0("season=", season)
)
production_result <- file.path(
  "data", "processed", "spatial_car_production", paste0("season=", season)
)
final_result <- file.path(
  "data", "processed", "spatial_full_league_fold5_comparison",
  paste0("season=", season)
)
raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", season), "shots.parquet"
)
cache_dir <- file.path(
  "data", "cache", "spatial_relocation", paste0("season=", season)
)
result_dir <- file.path(
  "data", "processed", "spatial_relocation", paste0("season=", season)
)

artifact_paths <- c(
  production_manifest = file.path(production_result, "production_manifest.parquet"),
  input = file.path(production_cache, "production_input.rds"),
  configuration = file.path(production_cache, "production_configuration.rds"),
  fit = file.path(production_cache, "car_production_fit.rds"),
  surface = file.path(production_cache, "player_probability_surfaces.parquet"),
  uncertainty = file.path(production_cache, "player_uncertainty_summary.parquet"),
  hyperparameter = file.path(production_cache, "hyperparameter_summary.parquet"),
  model_checkpoint = file.path(production_cache, "model_checkpoint.rds"),
  completion = file.path(production_cache, "production_complete_checkpoint.rds")
)
lock_path <- file.path(cache_dir, "active_run.lock")
pending_completion_path <- file.path(cache_dir, "relocation_complete.pending.rds")
completion_path <- file.path(cache_dir, "relocation_complete.rds")

OUTPUT_FILES <- c(
  "relocation_manifest.parquet",
  "player_cell_support.parquet",
  "player_evidence.parquet",
  "slider_results.parquet",
  "concentration_audit.parquet",
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
    stop("RELOCATION CHECK FAILED: ", check, " — ", detail, call. = FALSE)
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

quantile_value <- function(x, probability) {
  as.numeric(stats::quantile(x, probability, names = FALSE, type = 7))
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

verify_artifacts <- function() {
  record_check(
    "history", "required_commits_in_history",
    system2("git", c("merge-base", "--is-ancestor", PLANNING_COMMIT, "HEAD")) == 0L &&
      system2("git", c("merge-base", "--is-ancestor", PRODUCTION_RESULT_COMMIT,
                       "HEAD")) == 0L &&
      system2("git", c("merge-base", "--is-ancestor", FINAL_RESULT_COMMIT,
                       "HEAD")) == 0L,
    "planning, production, and final-test commits are ancestors of HEAD"
  )
  record_check(
    "artifacts", "all_production_artifacts_exist",
    all(file.exists(artifact_paths)),
    paste(length(artifact_paths), "required production artifacts")
  )
  observed_hashes <- vapply(unname(artifact_paths), sha256_file, character(1))
  names(observed_hashes) <- names(artifact_paths)
  record_check(
    "artifacts", "all_production_hashes_match",
    identical(observed_hashes, EXPECTED_HASHES),
    "manifest, input, configuration, fit, surfaces, uncertainty, and checkpoints"
  )

  manifest <- read_parquet(artifact_paths[["production_manifest"]])
  completion <- readRDS(artifact_paths[["completion"]])
  decision <- read_parquet(file.path(final_result, "decision.parquet"))
  record_check(
    "selection", "final_selection_immutable",
    identical(decision$evidence_classification[[1]], "favors_car") &&
      !isTRUE(decision$model_settings_changed[[1]]) &&
      !isTRUE(decision$models_refitted[[1]]) &&
      identical(manifest$selection_result_commit[[1]], FINAL_RESULT_COMMIT),
    "frozen final test favors CAR with no setting change or refit"
  )
  record_check(
    "production", "production_manifest_verified",
    nrow(manifest) == 1L && isTRUE(manifest$verification_passed[[1]]) &&
      isTRUE(manifest$production_only_no_new_evaluation[[1]]) &&
      manifest$player_count[[1]] == EXPECTED_PLAYERS &&
      manifest$shot_count[[1]] == EXPECTED_SHOTS &&
      manifest$observed_player_cells[[1]] == EXPECTED_OBSERVED_CELLS &&
      manifest$cells_per_player[[1]] == GRID_CELLS &&
      manifest$lattice_rows[[1]] == EXPECTED_LATTICE_ROWS &&
      manifest$posterior_draws[[1]] == POSTERIOR_DRAWS,
    "verified all-data 318-player production CAR manifest"
  )
  record_check(
    "production", "production_completion_verified",
    isTRUE(completion$complete) && all(completion$checks$passed) &&
      identical(completion$fit_sha256, EXPECTED_HASHES[["fit"]]) &&
      identical(completion$surface_sha256, EXPECTED_HASHES[["surface"]]),
    "atomic production completion and all saved checks passed"
  )

  input <- readRDS(artifact_paths[["input"]])
  record_check(
    "input", "production_input_dimensions",
    isTRUE(input$complete) && input$player_count == EXPECTED_PLAYERS &&
      input$shot_count == EXPECTED_SHOTS &&
      input$observed_player_cells == EXPECTED_OBSERVED_CELLS &&
      input$lattice_rows == EXPECTED_LATTICE_ROWS &&
      nrow(input$lattice) == EXPECTED_LATTICE_ROWS &&
      all(count(input$lattice, PLAYER_ID)$n == GRID_CELLS),
    "318 players x 156 cells, 194,987 attempts"
  )
  surface_schema <- names(open_dataset(artifact_paths[["surface"]])$schema)
  expected_surface_schema <- c(
    "PLAYER_ID", "PLAYER_NAME", "cell_id", "x_ft", "y_ft", "attempts",
    "makes", "probability", "draw_mean_probability", "probability_sd",
    "probability_lower_90", "probability_median", "probability_upper_90"
  )
  record_check(
    "artifacts", "surface_schema",
    identical(surface_schema, expected_surface_schema),
    "production player-cell surface schema is unchanged"
  )
  raw_schema <- names(open_dataset(raw_path)$schema)
  record_check(
    "input", "shot_value_schema",
    all(c("PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y", "SHOT_TYPE",
          "SHOT_ATTEMPTED_FLAG") %in% raw_schema),
    "raw data contain location and two/three-point shot type"
  )
  raw_sha256 <- sha256_file(raw_path)
  record_check(
    "input", "raw_shot_file_hash",
    identical(raw_sha256, EXPECTED_RAW_SHA256), EXPECTED_RAW_SHA256
  )
  list(
    manifest = manifest, completion = completion, input = input,
    raw_sha256 = raw_sha256
  )
}

verify_git_freeze <- function() {
  head <- git_value(c("rev-parse", "HEAD"))[[1]]
  origin <- git_value(c("rev-parse", "origin/codex/spatial-shot-selection"))[[1]]
  clean <- system2("git", c("diff", "--quiet")) == 0L &&
    system2("git", c("diff", "--cached", "--quiet")) == 0L
  record_check(
    "freeze", "pre_result_commit_pushed",
    identical(head, origin) && clean &&
      system2("git", c("merge-base", "--is-ancestor", PLANNING_COMMIT,
                       head)) == 0L,
    paste("clean local and origin revision", head)
  )
  head
}

acquire_lock <- function() {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    stop("Relocation lock exists; preserve it and inspect before recovery",
         call. = FALSE)
  }
  write_new_atomic_rds(
    list(pid = Sys.getpid(), started_at_utc = format(Sys.time(), tz = "UTC",
                                                     usetz = TRUE)),
    file.path(lock_path, "owner.rds")
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

assign_cells <- function(shots) {
  nx <- as.integer(ceiling((COURT_X_MAX - COURT_X_MIN) / GRID_WIDTH))
  ny <- as.integer(ceiling((COURT_Y_MAX - COURT_Y_MIN) / GRID_WIDTH))
  shots |>
    mutate(
      x_index = pmin(as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L,
                     nx),
      y_index = pmin(as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L,
                     ny),
      cell_id = (y_index - 1L) * nx + x_index
    )
}

load_point_values <- function(input) {
  shots <- open_dataset(raw_path) |>
    filter(
      PLAYER_ID %in% input$player_ids,
      LOC_Y <= COURT_Y_MAX
    ) |>
    select(PLAYER_ID, PLAYER_NAME, LOC_X, LOC_Y, SHOT_TYPE,
           SHOT_ATTEMPTED_FLAG) |>
    collect() |>
    as_tibble()
  record_check(
    "input", "shot_value_rows",
    nrow(shots) == EXPECTED_SHOTS && all(shots$SHOT_ATTEMPTED_FLAG == 1L) &&
      !anyNA(shots),
    "194,987 complete eligible all-data shot-type rows"
  )
  record_check(
    "input", "shot_type_values",
    setequal(unique(shots$SHOT_TYPE), c("2PT Field Goal", "3PT Field Goal")),
    paste(sort(unique(shots$SHOT_TYPE)), collapse = ", ")
  )
  assigned <- assign_cells(shots)
  values <- assigned |>
    summarise(
      point_value_attempts = n(),
      three_point_attempts = sum(SHOT_TYPE == "3PT Field Goal"),
      .by = c(PLAYER_ID, cell_id)
    ) |>
    mutate(
      three_point_share = three_point_attempts / point_value_attempts,
      point_value = 2 + three_point_share
    ) |>
    arrange(PLAYER_ID, cell_id)
  observed <- input$lattice |>
    filter(attempts > 0L) |>
    select(PLAYER_ID, cell_id, attempts) |>
    left_join(values, by = c("PLAYER_ID", "cell_id"))
  record_check(
    "input", "point_value_aggregation_matches_production",
    nrow(observed) == EXPECTED_OBSERVED_CELLS && !anyNA(observed) &&
      all(observed$attempts == observed$point_value_attempts) &&
      sum(observed$three_point_attempts) ==
        sum(shots$SHOT_TYPE == "3PT Field Goal") &&
      all(observed$point_value >= 2 & observed$point_value <= 3),
    "shot-type aggregation matches every observed production player-cell"
  )
  values
}

draw_summary <- function(values, prefix) {
  tibble(
    !!prefix := mean(values),
    !!paste0(prefix, "_lower_90") := quantile_value(values, 0.05),
    !!paste0(prefix, "_upper_90") := quantile_value(values, 0.95)
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
    identical(completed$production_hashes, EXPECTED_HASHES) &&
    verify_output_bundle(result_dir, completed$output_hashes) &&
    all(completed$checks$passed)
  if (!valid) stop("Existing relocation completion is invalid and preserved",
                   call. = FALSE)
  if (identical(marker, pending_completion_path)) {
    if (!file.rename(pending_completion_path, completion_path)) {
      stop("Could not finalize valid pending completion", call. = FALSE)
    }
  }
  completed
}

run_relocation <- function(audit) {
  recovered <- recover_completion()
  if (!is.null(recovered)) {
    message("Reused verified atomic relocation result; no draws recalculated")
    print(read_parquet(file.path(result_dir, "relocation_manifest.parquet")))
    return(invisible(recovered))
  }
  staging_paths <- Sys.glob(paste0(result_dir, ".partial-*"))
  if (dir.exists(result_dir) ||
      length(list.files(cache_dir, pattern = "partial")) > 0L ||
      length(staging_paths) > 0L) {
    stop("Partial relocation artifacts exist and were preserved", call. = FALSE)
  }
  pre_result_commit <- verify_git_freeze()
  acquire_lock()
  success <- FALSE
  on.exit({
    if (success && dir.exists(lock_path)) unlink(lock_path, recursive = TRUE)
  }, add = TRUE)
  started <- proc.time()[["elapsed"]]
  input <- audit$input
  lattice <- input$lattice |>
    arrange(PLAYER_ID, cell_id)
  record_check(
    "input", "predictor_order_matches_saved_fit",
    identical(lattice$predictor_index, seq_len(EXPECTED_LATTICE_ROWS)),
    "saved predictor indices match the ordered 318-player lattice"
  )
  point_values <- load_point_values(input)
  lattice <- lattice |>
    left_join(point_values, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      baseline_share = attempts / sum(attempts),
      point_value_for_calculation = coalesce(point_value, 0),
      .by = PLAYER_ID
    ) |>
    arrange(PLAYER_ID, cell_id)
  record_check(
    "baseline", "baseline_mass",
    max(abs((lattice |> summarise(total = sum(baseline_share), .by = PLAYER_ID))$total -
              1)) <= MASS_TOLERANCE,
    "all 318 baseline shot-share distributions sum to one"
  )

  fit <- readRDS(artifact_paths[["fit"]])
  record_check(
    "model", "saved_fit_unchanged_and_valid",
    isTRUE(fit$ok) && identical(as.numeric(fit$mode$mode.status), 0) &&
      nrow(fit$summary.linear.predictor) == EXPECTED_LATTICE_ROWS,
    "verified saved production fit; no model fitting is present in this script"
  )
  set_frozen_rng(POSTERIOR_SEED)
  captured_posterior <- capture_conditions(INLA::inla.posterior.sample(
    n = POSTERIOR_DRAWS,
    result = fit,
    selection = list(Predictor = lattice$predictor_index),
    seed = POSTERIOR_SEED,
    num.threads = 1L,
    parallel.configs = FALSE,
    add.names = FALSE
  ))
  probability_draws <- extract_predictors(
    captured_posterior$value, lattice$predictor_index
  )
  calculation_notices <- bind_rows(
    tibble(
      type = rep("warning", length(captured_posterior$warnings)),
      message = captured_posterior$warnings
    ),
    tibble(
      type = rep("message", length(captured_posterior$messages)),
      message = captured_posterior$messages
    )
  )
  captured_posterior$value <- NULL
  rm(captured_posterior, fit)
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
  saved_surface <- read_parquet(artifact_paths[["surface"]]) |>
    arrange(PLAYER_ID, cell_id)
  draw_mean_difference <- max(abs(
    rowMeans(probability_draws) - saved_surface$draw_mean_probability
  ))
  record_check(
    "posterior", "frozen_draws_reproduce_production_surface",
    is.finite(draw_mean_difference) && draw_mean_difference <= DRAW_REPRO_TOLERANCE,
    paste("maximum draw-mean probability difference", draw_mean_difference)
  )

  baseline_draws <- matrix(
    NA_real_, nrow = EXPECTED_PLAYERS, ncol = POSTERIOR_DRAWS
  )
  support_probability <- rep(NA_real_, EXPECTED_LATTICE_ROWS)
  player_ids <- input$player_ids
  for (player_index in seq_along(player_ids)) {
    rows <- which(lattice$PLAYER_ID == player_ids[[player_index]])
    weights <- lattice$baseline_share[rows] *
      lattice$point_value_for_calculation[rows]
    baseline_draws[player_index, ] <- colSums(
      probability_draws[rows, , drop = FALSE] * weights
    )
    observed_rows <- rows[lattice$attempts[rows] > 0L]
    cell_expected_points <- probability_draws[observed_rows, , drop = FALSE] *
      lattice$point_value[observed_rows]
    support_probability[observed_rows] <- rowMeans(
      sweep(cell_expected_points, 2L, baseline_draws[player_index, ], `>`)
    )
  }
  record_check(
    "posterior", "baseline_draws_finite",
    all(is.finite(baseline_draws)) && all(baseline_draws >= 0) &&
      all(baseline_draws <= 3),
    "318 x 4,000 finite current-mix expected-points draws"
  )

  player_cell <- lattice |>
    mutate(
      posterior_mean_expected_points_per_shot = if_else(
        attempts > 0L, rowMeans(probability_draws) * point_value, NA_real_
      )
    ) |>
    mutate(
      posterior_probability_above_current_mix = support_probability,
      minimum_attempts_pass = attempts >= MIN_ATTEMPTS,
      certainty_pass = coalesce(
        posterior_probability_above_current_mix >= MIN_CERTAINTY, FALSE
      ),
      supported_destination = minimum_attempts_pass & certainty_pass,
      supported_baseline_share = sum(
        baseline_share[supported_destination], na.rm = TRUE
      ),
      supported_allocation_weight = if_else(
        supported_destination & supported_baseline_share > 0,
        baseline_share / supported_baseline_share,
        0
      ),
      .by = PLAYER_ID
    ) |>
    select(
      PLAYER_ID, PLAYER_NAME, cell_id, x_ft, y_ft, attempts, baseline_share,
      point_value_attempts, three_point_attempts, three_point_share, point_value,
      posterior_mean_expected_points_per_shot,
      posterior_probability_above_current_mix, minimum_attempts_pass,
      certainty_pass, supported_destination, supported_allocation_weight
    )

  evidence <- player_cell |>
    summarise(
      attempts = sum(attempts),
      supported_destination_count = sum(supported_destination),
      supported_attempt_share = sum(baseline_share[supported_destination]),
      largest_supported_allocation_share = if_else(
        any(supported_destination), max(supported_allocation_weight), NA_real_
      ),
      baseline_largest_cell_share = max(baseline_share),
      .by = c(PLAYER_ID, PLAYER_NAME)
    ) |>
    mutate(
      evidence_status = if_else(
        supported_destination_count >= MIN_DESTINATIONS,
        "estimated", "insufficient_supported_destinations"
      )
    ) |>
    arrange(PLAYER_ID)
  estimable_ids <- evidence$PLAYER_ID[evidence$evidence_status == "estimated"]
  record_check(
    "evidence", "player_evidence_complete",
    nrow(evidence) == EXPECTED_PLAYERS && !anyDuplicated(evidence$PLAYER_ID) &&
      all(evidence$attempts > 0L),
    "one evidence status for each production player"
  )
  record_check(
    "allocation", "supported_weights",
    all(player_cell$supported_allocation_weight >= 0) &&
      all(player_cell$supported_allocation_weight[
        !player_cell$supported_destination
      ] == 0) &&
      all(abs(
        (player_cell |>
           filter(PLAYER_ID %in% estimable_ids) |>
           summarise(total = sum(supported_allocation_weight), .by = PLAYER_ID))$total -
          1
      ) <= MASS_TOLERANCE),
    "unsupported cells receive zero allocation; estimable-player weights sum to one"
  )
  proportional_difference <- player_cell |>
    filter(PLAYER_ID %in% estimable_ids, supported_destination) |>
    mutate(
      expected_weight = baseline_share / sum(baseline_share),
      difference = abs(supported_allocation_weight - expected_weight),
      .by = PLAYER_ID
    ) |>
    summarise(maximum = max(difference)) |>
    pull(maximum)
  record_check(
    "allocation", "allocation_is_proportional",
    proportional_difference <= MASS_TOLERANCE,
    paste("maximum proportional-weight difference", proportional_difference)
  )

  allocation_audit <- lapply(estimable_ids, function(player_id) {
    rows <- which(lattice$PLAYER_ID == player_id)
    player_attempts <- sum(lattice$attempts[rows])
    f <- lattice$baseline_share[rows]
    w <- player_cell$supported_allocation_weight[rows]
    supported <- player_cell$supported_destination[rows]
    bind_rows(lapply(SLIDERS, function(slider) {
      q <- (1 - slider) * f + slider * w
      tibble(
        PLAYER_ID = player_id,
        slider_fraction = slider,
        relocated_mass = sum(q),
        minimum_relocated_share = min(q),
        relocated_attempts = player_attempts * sum(q),
        original_attempts = player_attempts,
        maximum_unsupported_allocation_error = if (all(supported)) 0 else
          max(abs(q[!supported] - (1 - slider) * f[!supported]))
      )
    }))
  }) |>
    bind_rows()
  record_check(
    "allocation", "every_relocated_distribution_valid",
    nrow(allocation_audit) == length(estimable_ids) * length(SLIDERS) &&
      max(abs(allocation_audit$relocated_mass - 1)) <= MASS_TOLERANCE &&
      min(allocation_audit$minimum_relocated_share) >= 0,
    paste(
      "maximum mass error",
      max(abs(allocation_audit$relocated_mass - 1)),
      "minimum share", min(allocation_audit$minimum_relocated_share)
    )
  )
  record_check(
    "allocation", "attempt_totals_unchanged",
    max(abs(allocation_audit$relocated_attempts -
              allocation_audit$original_attempts)) <= MASS_TOLERANCE,
    paste(
      "maximum implied-attempt difference",
      max(abs(allocation_audit$relocated_attempts -
                allocation_audit$original_attempts))
    )
  )
  record_check(
    "allocation", "unsupported_cells_receive_no_allocation",
    max(allocation_audit$maximum_unsupported_allocation_error) <=
      MASS_TOLERANCE,
    paste(
      "maximum unsupported allocation error",
      max(allocation_audit$maximum_unsupported_allocation_error)
    )
  )
  record_check(
    "allocation", "supported_set_fixed_across_sliders",
    TRUE,
    "supported destinations are computed once before all slider calculations"
  )

  slider_results <- lapply(seq_along(player_ids), function(player_index) {
    player_id <- player_ids[[player_index]]
    rows <- which(lattice$PLAYER_ID == player_id)
    player_evidence <- evidence |> filter(PLAYER_ID == player_id)
    baseline <- baseline_draws[player_index, ]
    baseline_summary <- draw_summary(
      baseline, "baseline_expected_points_per_shot"
    )
    if (player_evidence$evidence_status != "estimated") {
      return(tibble(
        PLAYER_ID = player_id,
        PLAYER_NAME = player_evidence$PLAYER_NAME,
        evidence_status = player_evidence$evidence_status,
        slider_fraction = SLIDERS,
        baseline_expected_points_per_shot = baseline_summary[[1]],
        baseline_expected_points_per_shot_lower_90 = baseline_summary[[2]],
        baseline_expected_points_per_shot_upper_90 = baseline_summary[[3]],
        relocated_expected_points_per_shot = NA_real_,
        relocated_expected_points_per_shot_lower_90 = NA_real_,
        relocated_expected_points_per_shot_upper_90 = NA_real_,
        additional_season_points = NA_real_,
        additional_season_points_lower_90 = NA_real_,
        additional_season_points_upper_90 = NA_real_,
        additional_points_per_100_shots = NA_real_,
        additional_points_per_100_shots_lower_90 = NA_real_,
        additional_points_per_100_shots_upper_90 = NA_real_,
        largest_post_relocation_cell_share = NA_real_,
        effective_post_relocation_cell_count = NA_real_
      ))
    }
    f <- lattice$baseline_share[rows]
    v <- lattice$point_value_for_calculation[rows]
    w <- player_cell$supported_allocation_weight[rows]
    lapply(SLIDERS, function(slider) {
      q <- (1 - slider) * f + slider * w
      relocated <- if (slider == 0) baseline else colSums(
        probability_draws[rows, , drop = FALSE] * (q * v)
      )
      gain <- if (slider == 0) rep(0, POSTERIOR_DRAWS) else relocated - baseline
      relocated_summary <- draw_summary(
        relocated, "relocated_expected_points_per_shot"
      )
      season_summary <- draw_summary(
        gain * player_evidence$attempts, "additional_season_points"
      )
      per100_summary <- draw_summary(
        gain * 100, "additional_points_per_100_shots"
      )
      bind_cols(
        tibble(
          PLAYER_ID = player_id,
          PLAYER_NAME = player_evidence$PLAYER_NAME,
          evidence_status = player_evidence$evidence_status,
          slider_fraction = slider,
          baseline_expected_points_per_shot = baseline_summary[[1]],
          baseline_expected_points_per_shot_lower_90 = baseline_summary[[2]],
          baseline_expected_points_per_shot_upper_90 = baseline_summary[[3]]
        ),
        relocated_summary, season_summary, per100_summary,
        tibble(
          largest_post_relocation_cell_share = max(q),
          effective_post_relocation_cell_count = 1 / sum(q^2)
        )
      )
    }) |>
      bind_rows()
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID, slider_fraction)

  estimable_results <- slider_results |>
    filter(evidence_status == "estimated")
  metric_columns <- c(
    "baseline_expected_points_per_shot",
    "baseline_expected_points_per_shot_lower_90",
    "baseline_expected_points_per_shot_upper_90",
    "relocated_expected_points_per_shot",
    "relocated_expected_points_per_shot_lower_90",
    "relocated_expected_points_per_shot_upper_90",
    "additional_season_points", "additional_season_points_lower_90",
    "additional_season_points_upper_90", "additional_points_per_100_shots",
    "additional_points_per_100_shots_lower_90",
    "additional_points_per_100_shots_upper_90",
    "largest_post_relocation_cell_share",
    "effective_post_relocation_cell_count"
  )
  record_check(
    "results", "result_dimensions_and_status",
    nrow(slider_results) == EXPECTED_PLAYERS * length(SLIDERS) &&
      all(count(slider_results, PLAYER_ID)$n == length(SLIDERS)) &&
      all(is.na(as.matrix(slider_results[
        slider_results$evidence_status == "insufficient_supported_destinations",
        setdiff(metric_columns, grep("^baseline_", metric_columns, value = TRUE))
      ]))),
    "six rows per player; insufficient-evidence gains remain missing, not zero"
  )
  record_check(
    "results", "reported_values_finite",
    all(is.finite(as.matrix(estimable_results[metric_columns]))) &&
      all(is.finite(as.matrix(slider_results[
        , grep("^baseline_", names(slider_results), value = TRUE)
      ]))),
    "all estimable results and every baseline summary are finite"
  )
  ordered_intervals <- list(
    c("baseline_expected_points_per_shot_lower_90",
      "baseline_expected_points_per_shot_upper_90"),
    c("relocated_expected_points_per_shot_lower_90",
      "relocated_expected_points_per_shot_upper_90"),
    c("additional_season_points_lower_90",
      "additional_season_points_upper_90"),
    c("additional_points_per_100_shots_lower_90",
      "additional_points_per_100_shots_upper_90")
  )
  intervals_ordered <- all(vapply(ordered_intervals, function(columns) {
    all(estimable_results[[columns[[1]]]] <= estimable_results[[columns[[2]]]])
  }, logical(1)))
  record_check(
    "uncertainty", "intervals_finite_and_ordered",
    intervals_ordered,
    "all reported 90% posterior intervals are finite and ordered"
  )
  zero <- estimable_results |> filter(slider_fraction == 0)
  record_check(
    "slider", "zero_slider_identity",
    all(zero$additional_season_points == 0) &&
      all(zero$additional_season_points_lower_90 == 0) &&
      all(zero$additional_season_points_upper_90 == 0) &&
      all(zero$additional_points_per_100_shots == 0) &&
      all(zero$additional_points_per_100_shots_lower_90 == 0) &&
      all(zero$additional_points_per_100_shots_upper_90 == 0) &&
      all(zero$relocated_expected_points_per_shot ==
            zero$baseline_expected_points_per_shot),
    "slider 0 has identical mixes and exactly zero gains"
  )
  consistency <- estimable_results |>
    left_join(select(evidence, PLAYER_ID, attempts), by = "PLAYER_ID")
  record_check(
    "results", "gain_units_consistent",
    max(abs(
      consistency$additional_season_points -
        consistency$additional_points_per_100_shots / 100 * consistency$attempts
    )) <= 1e-10 &&
      max(abs(
        consistency$additional_points_per_100_shots / 100 -
          (consistency$relocated_expected_points_per_shot -
             consistency$baseline_expected_points_per_shot)
      )) <= 1e-12,
    "season, per-100, baseline, and relocated point estimates agree"
  )
  gain_steps <- consistency |>
    arrange(PLAYER_ID, slider_fraction) |>
    mutate(
      gain_change = additional_season_points - lag(additional_season_points),
      .by = PLAYER_ID
    ) |>
    filter(!is.na(gain_change))
  record_check(
    "results", "mean_gain_nondecreasing_with_slider",
    all(gain_steps$gain_change >= -MASS_TOLERANCE),
    paste("minimum adjacent mean-gain change", min(gain_steps$gain_change))
  )

  concentration <- estimable_results |>
    summarise(
      estimable_players = n(),
      median_largest_cell_share = median(largest_post_relocation_cell_share),
      p90_largest_cell_share = quantile_value(
        largest_post_relocation_cell_share, 0.90
      ),
      maximum_largest_cell_share = max(largest_post_relocation_cell_share),
      players_above_50_percent = sum(largest_post_relocation_cell_share > 0.50),
      players_above_75_percent = sum(largest_post_relocation_cell_share > 0.75),
      players_above_90_percent = sum(largest_post_relocation_cell_share > 0.90),
      median_effective_cell_count = median(effective_post_relocation_cell_count),
      .by = slider_fraction
    ) |>
    arrange(slider_fraction)

  final_checks <- bind_rows(checks)
  record_check(
    "publication", "all_checks_pass_before_publication",
    all(final_checks$passed),
    paste(nrow(final_checks), "checks passed before publication")
  )
  final_checks <- bind_rows(checks)
  elapsed <- proc.time()[["elapsed"]] - started
  staging <- paste0(result_dir, ".partial-", Sys.getpid())
  dir.create(dirname(result_dir), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(staging, recursive = FALSE, showWarnings = FALSE)) {
    stop("Could not create relocation staging directory", call. = FALSE)
  }

  write_new_atomic_parquet(player_cell,
                           file.path(staging, "player_cell_support.parquet"))
  write_new_atomic_parquet(evidence,
                           file.path(staging, "player_evidence.parquet"))
  write_new_atomic_parquet(slider_results,
                           file.path(staging, "slider_results.parquet"))
  write_new_atomic_parquet(concentration,
                           file.path(staging, "concentration_audit.parquet"))
  write_new_atomic_parquet(calculation_notices,
                           file.path(staging, "calculation_notices.parquet"))
  write_new_atomic_parquet(final_checks,
                           file.path(staging, "sanity_checks.parquet"))
  non_manifest_files <- setdiff(OUTPUT_FILES, "relocation_manifest.parquet")
  non_manifest_hashes <- vapply(
    file.path(staging, non_manifest_files), sha256_file, character(1)
  )
  manifest <- tibble(
    season = season,
    method_id = METHOD_ID,
    status = "descriptive_model_estimate_not_causal",
    pre_result_commit = pre_result_commit,
    planning_commit = PLANNING_COMMIT,
    production_result_commit = PRODUCTION_RESULT_COMMIT,
    final_result_commit = FINAL_RESULT_COMMIT,
    production_fit_sha256 = EXPECTED_HASHES[["fit"]],
    production_completion_sha256 = EXPECTED_HASHES[["completion"]],
    raw_shots_sha256 = audit$raw_sha256,
    player_count = EXPECTED_PLAYERS,
    shot_count = EXPECTED_SHOTS,
    cells_per_player = GRID_CELLS,
    lattice_rows = EXPECTED_LATTICE_ROWS,
    posterior_draws = POSTERIOR_DRAWS,
    posterior_seed = POSTERIOR_SEED,
    sliders = paste(SLIDERS, collapse = ","),
    minimum_attempts = MIN_ATTEMPTS,
    minimum_posterior_certainty = MIN_CERTAINTY,
    minimum_supported_destinations = MIN_DESTINATIONS,
    additional_destination_cap = "none",
    point_value = "2 + observed player-cell three-point-attempt share",
    allocation = "proportional to baseline shares among supported cells",
    interval = "posterior 5th to 95th percentile",
    supported_player_count = length(estimable_ids),
    insufficient_supported_player_count = EXPECTED_PLAYERS - length(estimable_ids),
    draw_mean_reproduction_max_abs_difference = draw_mean_difference,
    calculation_elapsed_sec = elapsed,
    posterior_warning_count = sum(calculation_notices$type == "warning"),
    posterior_message_count = sum(calculation_notices$type == "message"),
    negative_gain_lower_bound_count = sum(
      estimable_results$additional_season_points_lower_90 < 0
    ),
    gain_lower_bounds_clipped = FALSE,
    model_refit = FALSE,
    prediction_test_run = FALSE,
    score_created = FALSE,
    website_modified = FALSE,
    verification_passed = all(final_checks$passed),
    r_version = EXPECTED_VERSIONS[["R"]],
    inla_version = EXPECTED_VERSIONS[["INLA"]],
    arrow_version = EXPECTED_VERSIONS[["arrow"]],
    dplyr_version = EXPECTED_VERSIONS[["dplyr"]],
    tidyr_version = EXPECTED_VERSIONS[["tidyr"]]
  )
  for (file_name in non_manifest_files) {
    hash_name <- paste0(sub("\\.parquet$", "", file_name), "_sha256")
    manifest[[hash_name]] <- non_manifest_hashes[[file_name]]
  }
  write_new_atomic_parquet(manifest,
                           file.path(staging, "relocation_manifest.parquet"))
  output_hashes <- vapply(
    file.path(staging, OUTPUT_FILES), sha256_file, character(1)
  )
  names(output_hashes) <- OUTPUT_FILES
  completion <- list(
    complete = TRUE,
    method_id = METHOD_ID,
    pre_result_commit = pre_result_commit,
    production_hashes = EXPECTED_HASHES,
    output_hashes = output_hashes,
    supported_player_count = length(estimable_ids),
    insufficient_supported_player_count = EXPECTED_PLAYERS - length(estimable_ids),
    checks = final_checks,
    completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  write_new_atomic_rds(completion, pending_completion_path)
  if (!file.rename(staging, result_dir)) {
    stop("Could not publish relocation result directory", call. = FALSE)
  }
  if (!file.rename(pending_completion_path, completion_path)) {
    stop("Results are complete but completion marker remains pending", call. = FALSE)
  }
  success <- TRUE
  print(manifest, width = Inf)
  invisible(completion)
}

verify_versions()
audit <- verify_artifacts()

if (mode == "audit") {
  print(tibble(
    season = season,
    method_id = METHOD_ID,
    mode = mode,
    players = audit$input$player_count,
    shots = audit$input$shot_count,
    cells_per_player = GRID_CELLS,
    lattice_rows = audit$input$lattice_rows,
    posterior_draws = POSTERIOR_DRAWS,
    model_loaded = FALSE,
    posterior_sampled = FALSE,
    relocation_calculated = FALSE,
    all_checks_passed = all(bind_rows(checks)$passed)
  ), width = Inf)
  quit(save = "no", status = 0L)
}

run_relocation(audit)
