# One-time final fold-5 comparison of the completed full-league GAM and CAR.
#
# This script never fits a model. Audit mode verifies immutable artifacts and
# metadata without selecting SHOT_MADE_FLAG. Run mode regenerates fold-5
# uncertainty from the verified saved fits, publishes an exclusive access-audit
# marker, and then opens fold 5 outcomes exactly once.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    paste(
      "Usage: Rscript R/spatial_full_league_fold5_comparison.R",
      "<season> <audit|run>"
    ),
    call. = FALSE
  )
}

season <- args[[1]]
mode <- args[[2]]
if (!identical(season, "2025-26")) {
  stop("The frozen final comparison is registered only for 2025-26", call. = FALSE)
}
if (!mode %in% c("audit", "run")) {
  stop("Mode must be audit or run", call. = FALSE)
}

FITTING_FOLDS <- 1:3
PROVISIONAL_FOLD <- 4L
FINAL_TEST_FOLD <- 5L
GRID_WIDTH <- 40L
GRID_CELLS <- 156L
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
EXPECTED_PLAYERS <- 318L
EXPECTED_TRAINING_SHOTS <- 116955L
EXPECTED_OBSERVED_PLAYER_CELLS <- 19475L
EXPECTED_LATTICE_ROWS <- 49608L
EXPECTED_SPARSE_PLAYERS <- 80L
POSTERIOR_DRAWS <- 4000L
GAM_DRAW_SEED <- 20260901L
CAR_DRAW_SEED <- 20260902L
PREDICTIVE_SEED <- 20260903L
BOOTSTRAP_DRAWS <- 2000L
# Narayan explicitly directed the final test to reuse the fold-4 bootstrap seed.
BOOTSTRAP_SEED <- 20260904L
LOG_EPSILON <- 1e-15
EXPECTED_SPLIT_SHA256 <- paste0(
  "aaee94c1e8380999190aea5f00f8c02c738db6438ffe7b7a1a761d19c5a6ee33"
)
EXPECTED_GAM_INPUT_SHA256 <- paste0(
  "9608cd06ef83ab0866ad1c81f8d25802326d3f91cc349a81c570f46103eaae47"
)
EXPECTED_GAM_COMPLETION_SHA256 <- paste0(
  "eaeb947ec92e51f17b3c8273bb0584226a60f47fb84bd523f66152a2c7f3c453"
)
EXPECTED_GAM_FIT_SHA256 <- paste0(
  "6f458046726d601033aa6a1c51d029283319844b8e63a6ceb9454e3cb02c0d39"
)
EXPECTED_GAM_FIT_MD5 <- "0c378a0eba332161f6a689bcf952f5a1"
EXPECTED_CAR_COMPLETION_SHA256 <- paste0(
  "f7506b0badf00aaebccaa23bd9d49f5db05b83fc733bc0f3a1f0fca6c744d77b"
)
EXPECTED_CAR_MODEL_CHECKPOINT_SHA256 <- paste0(
  "6ab8ab7aa45592e9a1677cc3eece9a71944dc89ad3db8fb0dbb38942e4fd57f9"
)
EXPECTED_CAR_FIT_SHA256 <- paste0(
  "8ac0a0bb4070e35ec16a3472f1a861bfaf4b52d9b21b89216107abfcf81791d8"
)
EXPECTED_CAR_FIT_MD5 <- "71637ec9ec44e7cc2d62259067a0048a"
EXPECTED_FOLD4_PRE_EVALUATION_COMMIT <- paste0(
  "42b4038e05dc55720e496b16acaa496444e8bf2f"
)
EXPECTED_FOLD4_RESULT_COMMIT <- paste0(
  "ec2299025236db21dd9ee79451285e8d5bb44720"
)

raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", season), "shots.parquet"
)
fold_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "game_folds.parquet"
)
gam_cache_dir <- file.path(
  "data", "cache", "spatial_gam_exact_full_league_benchmark",
  paste0("season=", season)
)
car_cache_dir <- file.path(
  "data", "cache", "spatial_car_full_league_benchmark",
  paste0("season=", season)
)
fold4_result_dir <- file.path(
  "data", "processed", "spatial_full_league_fold4_comparison",
  paste0("season=", season)
)
result_dir <- file.path(
  "data", "processed", "spatial_full_league_fold5_comparison",
  paste0("season=", season)
)
access_dir <- file.path(
  "data", "cache", "spatial_full_league_fold5_comparison",
  paste0("season=", season)
)
access_marker_path <- file.path(access_dir, "fold5_access_audit.rds")

gam_completion_path <- file.path(gam_cache_dir, "benchmark_complete_checkpoint.rds")
gam_fit_path <- file.path(gam_cache_dir, "gam_exact_grid_40_fit.rds")
gam_signature_path <- file.path(gam_cache_dir, "input_signature.rds")
car_completion_path <- file.path(car_cache_dir, "benchmark_complete_checkpoint.rds")
car_model_checkpoint_path <- file.path(car_cache_dir, "car_grid_40_checkpoint.rds")
car_fit_path <- file.path(car_cache_dir, "car_grid_40_fit.rds")

METADATA_COLUMNS <- c(
  "GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y",
  "SHOT_ATTEMPTED_FLAG"
)
OUTCOME_COLUMNS <- c(METADATA_COLUMNS, "SHOT_MADE_FLAG")

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(value) != 1L) {
    stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  }
  strsplit(value, "[[:space:]]+")[[1]][[1]]
}

check_records <- list()
check_or_stop <- function(area, check, condition, detail) {
  passed <- isTRUE(condition)
  check_records[[length(check_records) + 1L]] <<- tibble(
    area = area, check = check, passed = passed, detail = as.character(detail)
  )
  if (!passed) {
    stop("Frozen final-test check failed: ", check, " — ", detail, call. = FALSE)
  }
  invisible(TRUE)
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

write_new_atomic_parquet <- function(table, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    stop("Refusing to overwrite an existing final-test result: ", path,
         call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"), tmpdir = dirname(path)
  )
  write_parquet(table, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish final-test result: ", path, call. = FALSE)
  }
}

read_frozen_folds <- function() {
  check_or_stop(
    "split", "split_artifact_sha256",
    file.exists(fold_path) && sha256_file(fold_path) == EXPECTED_SPLIT_SHA256,
    EXPECTED_SPLIT_SHA256
  )
  folds <- read_parquet(fold_path) |>
    as_tibble() |>
    arrange(GAME_ID)
  counts <- count(folds, fold)
  check_or_stop(
    "split", "split_dimensions",
    nrow(folds) == 1230L && n_distinct(folds$GAME_ID) == 1230L &&
      identical(counts$fold, 1:5) && all(counts$n == 246L) &&
      is.character(folds$GAME_ID),
    "1,230 text game ids; 246 games in each of five folds"
  )
  folds
}

read_metadata_only <- function(folds) {
  schema_names <- names(read_parquet(raw_path, as_data_frame = FALSE)$schema)
  check_or_stop(
    "data", "raw_schema",
    all(OUTCOME_COLUMNS %in% schema_names),
    "all frozen metadata and outcome columns are present"
  )
  metadata <- read_parquet(raw_path, col_select = all_of(METADATA_COLUMNS)) |>
    as_tibble()
  check_or_stop(
    "data", "metadata_has_no_outcome",
    !"SHOT_MADE_FLAG" %in% names(metadata),
    "metadata-only read excludes make/miss"
  )
  check_or_stop(
    "data", "metadata_types_and_values",
    is.character(metadata$GAME_ID) && !anyNA(metadata) &&
      all(metadata$SHOT_ATTEMPTED_FLAG == 1L),
    "game ids are text and required metadata are complete"
  )
  joined <- metadata |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    left_join(folds, by = "GAME_ID")
  check_or_stop(
    "data", "all_in_play_rows_have_fold",
    !anyNA(joined$fold),
    paste(nrow(joined), "in-play metadata rows")
  )
  eligible <- joined |>
    summarise(
      season_attempts = n(), season_games = n_distinct(GAME_ID),
      .by = PLAYER_ID
    ) |>
    filter(season_games >= MIN_GAMES, season_attempts >= MIN_ATTEMPTS) |>
    arrange(PLAYER_ID)
  check_or_stop(
    "data", "eligible_players",
    nrow(eligible) == EXPECTED_PLAYERS &&
      n_distinct(eligible$PLAYER_ID) == EXPECTED_PLAYERS,
    paste(nrow(eligible), "eligible players")
  )
  list(joined = joined, eligible = eligible)
}

make_grid <- function() {
  nx <- as.integer(ceiling((COURT_X_MAX - COURT_X_MIN) / GRID_WIDTH))
  ny <- as.integer(ceiling((COURT_Y_MAX - COURT_Y_MIN) / GRID_WIDTH))
  grid <- expand_grid(x_index = seq_len(nx), y_index = seq_len(ny)) |>
    mutate(
      cell_id = (y_index - 1L) * nx + x_index,
      x_left = COURT_X_MIN + (x_index - 1L) * GRID_WIDTH,
      x_right = pmin(x_left + GRID_WIDTH, COURT_X_MAX),
      y_bottom = COURT_Y_MIN + (y_index - 1L) * GRID_WIDTH,
      y_top = pmin(y_bottom + GRID_WIDTH, COURT_Y_MAX),
      x_ft = ((x_left + x_right) / 2) / 10,
      y_ft = ((y_bottom + y_top) / 2) / 10
    ) |>
    select(x_index, y_index, cell_id, x_ft, y_ft) |>
    arrange(cell_id)
  check_or_stop(
    "grid", "fixed_grid_dimensions",
    nrow(grid) == GRID_CELLS && identical(grid$cell_id, seq_len(GRID_CELLS)),
    "fixed 40-unit grid has 156 ordered cells"
  )
  attr(grid, "nx") <- nx
  attr(grid, "ny") <- ny
  grid
}

assign_grid_cells <- function(shots, grid) {
  nx <- attr(grid, "nx")
  ny <- attr(grid, "ny")
  assigned <- shots |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L, nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L, ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    )
  check_or_stop(
    "grid", "all_rows_map_to_fixed_grid",
    all(assigned$cell_id %in% grid$cell_id),
    paste(nrow(assigned), "rows mapped to the frozen grid")
  )
  assigned
}

verify_fold4_record <- function() {
  required <- file.path(
    fold4_result_dir,
    c(
      "comparison_manifest.parquet", "model_metrics.parquet",
      "bootstrap_summary.parquet", "decision.parquet", "sanity_checks.parquet"
    )
  )
  check_or_stop(
    "prior", "fold4_result_files_exist", all(file.exists(required)),
    "fold-4 manifest, metrics, bootstrap, decision, and checks exist"
  )
  manifest <- read_parquet(required[[1]])
  checks <- read_parquet(required[[5]])
  head_commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
  check_or_stop(
    "prior", "fold4_commits_and_results_verified",
    identical(manifest$pre_evaluation_commit[[1]],
              EXPECTED_FOLD4_PRE_EVALUATION_COMMIT) &&
      all(checks$passed) && all(!checks$fold5_outcomes_read) &&
      system2(
        "git", c("merge-base", "--is-ancestor", EXPECTED_FOLD4_RESULT_COMMIT,
                 head_commit)
      ) == 0L,
    "fold-4 pre-evaluation commit 42b4038 and result commit ec22990 verified"
  )
}

verify_artifacts <- function(metadata, grid) {
  expected_paths <- c(
    gam_completion_path, gam_fit_path, gam_signature_path,
    car_completion_path, car_model_checkpoint_path, car_fit_path
  )
  check_or_stop(
    "artifacts", "all_artifacts_exist", all(file.exists(expected_paths)),
    "both completion checkpoints, model checkpoints/signature, and fits exist"
  )
  observed_hashes <- c(
    gam_completion = sha256_file(gam_completion_path),
    gam_fit = sha256_file(gam_fit_path),
    gam_input = sha256_file(gam_signature_path),
    car_completion = sha256_file(car_completion_path),
    car_model_checkpoint = sha256_file(car_model_checkpoint_path),
    car_fit = sha256_file(car_fit_path)
  )
  expected_hashes <- c(
    gam_completion = EXPECTED_GAM_COMPLETION_SHA256,
    gam_fit = EXPECTED_GAM_FIT_SHA256,
    gam_input = EXPECTED_GAM_INPUT_SHA256,
    car_completion = EXPECTED_CAR_COMPLETION_SHA256,
    car_model_checkpoint = EXPECTED_CAR_MODEL_CHECKPOINT_SHA256,
    car_fit = EXPECTED_CAR_FIT_SHA256
  )
  check_or_stop(
    "artifacts", "all_sha256_hashes_match",
    identical(observed_hashes, expected_hashes),
    "six frozen SHA-256 values match"
  )
  observed_md5 <- c(
    gam = unname(tools::md5sum(gam_fit_path)),
    car = unname(tools::md5sum(car_fit_path))
  )
  check_or_stop(
    "artifacts", "fitted_model_md5_hashes_match",
    identical(
      observed_md5,
      c(gam = EXPECTED_GAM_FIT_MD5, car = EXPECTED_CAR_FIT_MD5)
    ),
    "both serialized fitted-model MD5 values match"
  )

  # Hashes are checked before any checkpoint or fit is loaded.
  gam <- readRDS(gam_completion_path)
  gam_signature <- readRDS(gam_signature_path)
  car_completion <- readRDS(car_completion_path)
  car <- readRDS(car_model_checkpoint_path)
  check_or_stop(
    "artifacts", "completion_headers",
    isTRUE(gam$complete) && isTRUE(car_completion$complete) && isTRUE(car$complete) &&
      identical(gam$season, season) && identical(car_completion$season, season) &&
      identical(car$season, season) &&
      identical(gam$split_sha256, EXPECTED_SPLIT_SHA256) &&
      identical(car_completion$split_sha256, EXPECTED_SPLIT_SHA256) &&
      identical(car$split_sha256, EXPECTED_SPLIT_SHA256) &&
      identical(gam$input_sha256, EXPECTED_GAM_INPUT_SHA256) &&
      identical(car_completion$model_checkpoint_sha256,
                EXPECTED_CAR_MODEL_CHECKPOINT_SHA256) &&
      identical(gam$fit_md5, EXPECTED_GAM_FIT_MD5) &&
      identical(car_completion$serialized_model_md5, EXPECTED_CAR_FIT_MD5),
    "both completions belong to the frozen season, split, inputs, and fits"
  )

  gm <- gam$result$metrics
  cm <- car$result$metrics
  cbm <- car_completion$metrics
  check_or_stop(
    "models", "frozen_model_identities",
    identical(gam$specification_id, "frozen-gam-grid40-exact-long-v1") &&
      identical(gam$method, "aggregated_exact_nondiscrete_two_worker_psock") &&
      identical(car$specification_id, "frozen-car-full-league-grid40-training-v1") &&
      identical(car$model, "CAR"),
    "exact non-discrete GAM and frozen replicated CAR specification ids"
  )
  check_or_stop(
    "reproducibility", "frozen_package_versions",
    identical(gm$r_version[[1]], "4.6.0") &&
      identical(gm$mgcv_version[[1]], "1.9.4") &&
      identical(gm$arrow_version[[1]], "25.0.0") &&
      identical(gm$dplyr_version[[1]], "1.2.1") &&
      identical(gm$tidyr_version[[1]], "1.3.2") &&
      identical(cbm$r_version[[1]], "4.6.0") &&
      identical(cbm$inla_version[[1]], "26.8.7") &&
      identical(cbm$matrix_version[[1]], "1.7.5") &&
      identical(cbm$fmesher_version[[1]], "0.8.0") &&
      identical(cbm$sn_version[[1]], "2.1.3") &&
      identical(cbm$arrow_version[[1]], "25.0.0") &&
      identical(cbm$dplyr_version[[1]], "1.2.1") &&
      identical(cbm$tidyr_version[[1]], "1.3.2"),
    "saved models record every frozen R and package version"
  )
  check_or_stop(
    "models", "frozen_gam_structure",
    grepl("cbind\\(makes, attempts - makes\\)", gm$formula[[1]]) &&
      grepl("by = player_factor", gm$formula[[1]], fixed = TRUE) &&
      grepl('bs = "tp"', gm$formula[[1]], fixed = TRUE) &&
      grepl("k = 20", gm$formula[[1]], fixed = TRUE) &&
      grepl("id = 1", gm$formula[[1]], fixed = TRUE) &&
      identical(gm$method[[1]],
                "aggregated_exact_nondiscrete_two_worker_psock") &&
      gm$basis_size[[1]] == 20L &&
      gm$worker_count[[1]] == 2L && gm$coefficient_count[[1]] == 6360L &&
      gm$smooth_count[[1]] == EXPECTED_PLAYERS &&
      gm$smoothing_parameter_count[[1]] == 1L,
    "grouped binomial, 318 intercepts/smooths, k=20, shared id=1, exact fREML"
  )
  check_or_stop(
    "models", "frozen_car_structure",
    grepl('model = "besagproper2"', cm$formula[[1]], fixed = TRUE) &&
      grepl("replicate = player_index", cm$formula[[1]], fixed = TRUE) &&
      grepl("nrep = n_players", cm$formula[[1]], fixed = TRUE) &&
      grepl("constr = FALSE", cm$formula[[1]], fixed = TRUE) &&
      grepl("diagonal = 0", cm$formula[[1]], fixed = TRUE) &&
      grepl('prior = "pc.prec"', cm$formula[[1]], fixed = TRUE) &&
      grepl("param = c(1, 0.01)", cm$formula[[1]], fixed = TRUE) &&
      grepl('prior = "logitbeta"', cm$formula[[1]], fixed = TRUE) &&
      grepl("param = c(1, 1)", cm$formula[[1]], fixed = TRUE) &&
      cm$coefficient_count[[1]] == EXPECTED_PLAYERS &&
      cm$spatial_effect_count[[1]] == EXPECTED_LATTICE_ROWS &&
      cm$hyperparameter_count[[1]] == 2L,
    "binomial replicated besagproper2 with frozen priors and hyperparameters"
  )
  check_or_stop(
    "models", "saved_prevalidation_checks",
    all(gam$result$checks$passed) && all(car_completion$checks$passed) &&
      all(car$checks$passed) && gm$warning_count[[1]] == 0L &&
      cm$warning_count[[1]] == 0L,
    "all saved GAM and CAR checks passed with no model warnings"
  )

  training_metadata <- metadata$joined |>
    filter(fold %in% FITTING_FOLDS, PLAYER_ID %in% metadata$eligible$PLAYER_ID)
  training_cells <- assign_grid_cells(training_metadata, grid) |>
    distinct(PLAYER_ID, cell_id)
  check_or_stop(
    "fairness", "shared_training_dimensions",
    nrow(training_metadata) == EXPECTED_TRAINING_SHOTS &&
      nrow(training_cells) == EXPECTED_OBSERVED_PLAYER_CELLS &&
      gm$training_shots[[1]] == EXPECTED_TRAINING_SHOTS &&
      cbm$training_shot_count[[1]] == EXPECTED_TRAINING_SHOTS &&
      gm$observed_player_cells[[1]] == EXPECTED_OBSERVED_PLAYER_CELLS &&
      cbm$observed_player_cell_count[[1]] == EXPECTED_OBSERVED_PLAYER_CELLS &&
      identical(gm$fitting_folds[[1]], "1,2,3") &&
      identical(cbm$fitting_folds[[1]], "1,2,3"),
    "both saved fits record the same 116,955 folds-1-to-3 shots"
  )

  gam_probabilities <- gam$result$probabilities |>
    arrange(PLAYER_ID, cell_id)
  car_probabilities <- car$result$probabilities |>
    arrange(PLAYER_ID, cell_id)
  keys <- c("PLAYER_ID", "cell_id")
  expected_lattice <- tibble(PLAYER_ID = metadata$eligible$PLAYER_ID) |>
    crossing(select(grid, cell_id, x_ft, y_ft)) |>
    arrange(PLAYER_ID, cell_id)
  signature_lattice <- gam_signature$lattice |>
    select(PLAYER_ID, cell_id, x_ft, y_ft) |>
    as_tibble() |>
    arrange(PLAYER_ID, cell_id)
  check_or_stop(
    "fairness", "identical_prediction_lattice",
    nrow(gam_probabilities) == EXPECTED_LATTICE_ROWS &&
      nrow(car_probabilities) == EXPECTED_LATTICE_ROWS &&
      identical(gam_probabilities[keys], car_probabilities[keys]) &&
      n_distinct(gam_probabilities$PLAYER_ID) == EXPECTED_PLAYERS &&
      n_distinct(gam_probabilities$cell_id) == GRID_CELLS &&
      all(count(gam_probabilities, PLAYER_ID)$n == GRID_CELLS) &&
      identical(sort(unique(gam_probabilities$PLAYER_ID)), metadata$eligible$PLAYER_ID) &&
      identical(signature_lattice, expected_lattice) &&
      identical(signature_lattice[keys], gam_probabilities[keys]),
    "same players, ids, boundaries, coordinates, and 49,608-row lattice"
  )
  check_or_stop(
    "predictions", "saved_probability_bounds",
    all(is.finite(gam_probabilities$probability)) &&
      all(is.finite(car_probabilities$probability)) &&
      all(gam_probabilities$probability >= 0 & gam_probabilities$probability <= 1) &&
      all(car_probabilities$probability >= 0 & car_probabilities$probability <= 1),
    "all saved point probabilities are finite and within [0,1]"
  )

  gam_sparse <- gam$result$sparse_intervals |>
    arrange(PLAYER_ID)
  car_sparse <- car$result$sparse |>
    arrange(PLAYER_ID)
  check_or_stop(
    "uncertainty", "identical_sparse_player_set",
    nrow(gam_sparse) == EXPECTED_SPARSE_PLAYERS &&
      nrow(car_sparse) == EXPECTED_SPARSE_PLAYERS &&
      identical(gam_sparse$PLAYER_ID, car_sparse$PLAYER_ID),
    "both saved artifacts identify the same 80 training-defined sparse players"
  )

  final_metadata <- metadata$joined |>
    filter(fold == FINAL_TEST_FOLD, PLAYER_ID %in% metadata$eligible$PLAYER_ID) |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  check_or_stop(
    "seal", "pretest_metadata_only",
    identical(sort(unique(final_metadata$fold)), FINAL_TEST_FOLD) &&
      !"SHOT_MADE_FLAG" %in% names(final_metadata),
    paste(nrow(final_metadata), "fold-5 metadata rows; make/miss remains unopened")
  )

  list(
    gam_probabilities = gam_probabilities,
    car_probabilities = car_probabilities,
    sparse_ids = gam_sparse$PLAYER_ID,
    gam_metrics = gm,
    car_metrics = cbm,
    final_metadata = final_metadata,
    observed_hashes = observed_hashes
  )
}

build_final_lattice <- function(final_metadata, player_ids, grid, sparse_ids) {
  assigned <- assign_grid_cells(final_metadata, grid)
  counts <- assigned |>
    count(PLAYER_ID, cell_id, name = "final_attempts")
  lattice <- tibble(PLAYER_ID = player_ids) |>
    crossing(select(grid, cell_id, x_ft, y_ft)) |>
    left_join(counts, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      final_attempts = coalesce(as.integer(final_attempts), 0L),
      player_factor = factor(PLAYER_ID, levels = player_ids),
      player_index = as.integer(player_factor),
      predictor_index = row_number()
    ) |>
    arrange(PLAYER_ID, cell_id) |>
    mutate(predictor_index = row_number())
  sparse_counts <- lattice |>
    filter(PLAYER_ID %in% sparse_ids) |>
    summarise(final_attempts = sum(final_attempts), .by = PLAYER_ID)
  check_or_stop(
    "uncertainty", "final_lattice_dimensions",
    nrow(lattice) == EXPECTED_LATTICE_ROWS &&
      sum(lattice$final_attempts) == nrow(final_metadata) &&
      nrow(sparse_counts) == EXPECTED_SPARSE_PLAYERS &&
      all(sparse_counts$final_attempts > 0L),
    "49,608 lattice rows preserve all fold-5 metadata and sparse-player attempts"
  )
  lattice
}

simulate_totals <- function(probability_draws, attempts) {
  if (nrow(probability_draws) != length(attempts) ||
      ncol(probability_draws) != POSTERIOR_DRAWS) {
    stop("Posterior-predictive dimensions do not match attempts", call. = FALSE)
  }
  simulated <- matrix(
    rbinom(
      length(probability_draws),
      size = rep(as.integer(attempts), times = POSTERIOR_DRAWS),
      prob = as.vector(probability_draws)
    ),
    nrow = nrow(probability_draws), ncol = POSTERIOR_DRAWS
  )
  colSums(simulated)
}

smooth_edf <- function(fit) {
  vapply(
    fit$smooth,
    function(smooth) sum(fit$edf[smooth$first.para:smooth$last.para]),
    numeric(1)
  )
}

gam_fold5_intervals <- function(lattice, sparse_ids, saved_probabilities) {
  started <- proc.time()[["elapsed"]]
  fit <- readRDS(gam_fit_path)
  expected_formula <- paste(
    deparse(
      cbind(makes, attempts - makes) ~ 0 + player_factor +
        s(
          x_ft, y_ft, by = player_factor, bs = "tp", m = 2, k = 20,
          id = 1
        )
    ),
    collapse = " "
  )
  edf <- smooth_edf(fit)
  check_or_stop(
    "models", "loaded_gam_structure",
    inherits(fit, "bam") && identical(fit$method, "fREML") &&
      identical(fit$family$family, "binomial") &&
      identical(fit$family$link, "logit") && isTRUE(fit$converged) &&
      !isTRUE(fit$dinfo$para.discrete) &&
      paste(deparse(fit$formula), collapse = " ") == expected_formula &&
      length(coef(fit)) == 6360L && length(fit$smooth) == EXPECTED_PLAYERS &&
      length(fit$sp) == 1L && all(edf < 0.95 * 19),
    "verified saved exact discrete=FALSE GAM; no fitting call is present"
  )
  covariance <- vcov(fit, unconditional = TRUE)
  check_or_stop(
    "uncertainty", "gam_finite_unconditional_covariance",
    all(is.finite(covariance)) && nrow(covariance) == 6360L,
    "6,360 by 6,360 unconditional covariance is finite"
  )
  set_frozen_rng(GAM_DRAW_SEED)
  coefficient_draws <- mgcv::rmvn(
    POSTERIOR_DRAWS, mu = coef(fit), V = covariance
  )
  saved <- saved_probabilities |>
    filter(PLAYER_ID %in% sparse_ids) |>
    arrange(PLAYER_ID, cell_id)
  probability_parts <- list()
  draw_parts <- list()
  for (player_id in sparse_ids) {
    player_lattice <- lattice |>
      filter(PLAYER_ID == player_id) |>
      arrange(cell_id)
    design <- predict(
      fit, newdata = player_lattice, type = "lpmatrix", discrete = FALSE
    )
    active <- which(colSums(abs(design)) > 0)
    eta_draws <- design[, active, drop = FALSE] %*%
      t(coefficient_draws[, active, drop = FALSE])
    probability_draws <- plogis(eta_draws)
    probability_parts[[as.character(player_id)]] <- tibble(
      PLAYER_ID = player_id,
      cell_id = player_lattice$cell_id,
      probability = rowMeans(probability_draws)
    )
    used <- player_lattice$final_attempts > 0L
    draw_parts[[as.character(player_id)]] <- list(
      probabilities = probability_draws[used, , drop = FALSE],
      attempts = player_lattice$final_attempts[used]
    )
  }
  regenerated <- bind_rows(probability_parts) |>
    arrange(PLAYER_ID, cell_id)
  check_or_stop(
    "uncertainty", "gam_regenerated_point_predictions",
    identical(regenerated[c("PLAYER_ID", "cell_id")], saved[c("PLAYER_ID", "cell_id")]) &&
      max(abs(regenerated$probability - saved$probability)) < 1e-12,
    "frozen draws reproduce saved sparse-player probabilities within 1e-12"
  )
  set_frozen_rng(PREDICTIVE_SEED)
  intervals <- lapply(sparse_ids, function(player_id) {
    values <- draw_parts[[as.character(player_id)]]
    totals <- simulate_totals(values$probabilities, values$attempts)
    tibble(
      model = "GAM", PLAYER_ID = player_id,
      final_attempts = sum(values$attempts),
      interval_lower = as.numeric(quantile(totals, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(totals, 0.95, names = FALSE))
    ) |>
      mutate(interval_width = interval_upper - interval_lower)
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID)
  elapsed <- proc.time()[["elapsed"]] - started
  rm(fit, covariance, coefficient_draws, probability_parts, draw_parts)
  gc()
  list(intervals = intervals, elapsed_sec = elapsed,
       warnings = character(), messages = character())
}

extract_selected_predictors <- function(samples, expected_indices) {
  labels <- rownames(samples[[1]]$latent)
  if (is.null(labels)) {
    stop("R-INLA posterior sample did not label selected predictors", call. = FALSE)
  }
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  if (anyNA(parsed) || !setequal(parsed, expected_indices)) {
    stop("R-INLA posterior predictor selection does not match requested rows",
         call. = FALSE)
  }
  matrix_values <- vapply(
    samples,
    function(sample) as.numeric(sample$latent),
    numeric(length(expected_indices))
  )
  matrix_values[match(expected_indices, parsed), , drop = FALSE]
}

car_fold5_intervals <- function(lattice, sparse_ids) {
  started <- proc.time()[["elapsed"]]
  fit <- readRDS(car_fit_path)
  check_or_stop(
    "models", "loaded_car_structure",
    inherits(fit, "inla") && isTRUE(fit$ok) &&
      identical(as.numeric(fit$mode$mode.status), 0) &&
      nrow(fit$summary.fixed) == EXPECTED_PLAYERS &&
      nrow(fit$summary.random$cell_id) == EXPECTED_LATTICE_ROWS &&
      nrow(fit$summary.hyperpar) == 2L &&
      nrow(fit$summary.linear.predictor) == EXPECTED_LATTICE_ROWS &&
      !is.null(fit$misc$configs),
    "verified saved R-INLA fit and posterior configuration; no fitting call is present"
  )
  selected <- lattice |>
    filter(PLAYER_ID %in% sparse_ids, final_attempts > 0L) |>
    arrange(predictor_index)
  indices <- selected$predictor_index
  set_frozen_rng(CAR_DRAW_SEED)
  captured <- capture_conditions(INLA::inla.posterior.sample(
    n = POSTERIOR_DRAWS,
    result = fit,
    selection = list(Predictor = indices),
    seed = CAR_DRAW_SEED,
    num.threads = 1L,
    parallel.configs = FALSE,
    add.names = FALSE
  ))
  predictor_draws <- extract_selected_predictors(captured$value, indices)
  rm(fit)
  gc()
  check_or_stop(
    "uncertainty", "car_selected_posterior_draws",
    nrow(predictor_draws) == nrow(selected) &&
      ncol(predictor_draws) == POSTERIOR_DRAWS &&
      all(is.finite(predictor_draws)),
    paste(nrow(selected), "selected predictors by 4,000 finite posterior draws")
  )
  set_frozen_rng(PREDICTIVE_SEED)
  intervals <- lapply(sparse_ids, function(player_id) {
    rows <- which(selected$PLAYER_ID == player_id)
    probability_draws <- plogis(predictor_draws[rows, , drop = FALSE])
    totals <- simulate_totals(probability_draws, selected$final_attempts[rows])
    tibble(
      model = "CAR", PLAYER_ID = player_id,
      final_attempts = sum(selected$final_attempts[rows]),
      interval_lower = as.numeric(quantile(totals, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(totals, 0.95, names = FALSE))
    ) |>
      mutate(interval_width = interval_upper - interval_lower)
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID)
  elapsed <- proc.time()[["elapsed"]] - started
  rm(predictor_draws)
  gc()
  list(
    intervals = intervals, elapsed_sec = elapsed,
    warnings = captured$warnings, messages = captured$messages
  )
}

validate_intervals <- function(gam, car, lattice, sparse_ids) {
  intervals <- bind_rows(gam$intervals, car$intervals) |>
    arrange(model, PLAYER_ID)
  expected_attempts <- lattice |>
    filter(PLAYER_ID %in% sparse_ids) |>
    summarise(final_attempts = sum(final_attempts), .by = PLAYER_ID)
  checked <- intervals |>
    select(-final_attempts) |>
    left_join(expected_attempts, by = "PLAYER_ID")
  check_or_stop(
    "uncertainty", "fold5_intervals_complete_and_feasible",
    nrow(checked) == 2L * EXPECTED_SPARSE_PLAYERS &&
      all(count(checked, model)$n == EXPECTED_SPARSE_PLAYERS) &&
      all(is.finite(checked$interval_lower)) &&
      all(is.finite(checked$interval_upper)) &&
      all(is.finite(checked$interval_width)) &&
      all(checked$interval_lower >= 0) &&
      all(checked$interval_lower <= checked$interval_upper) &&
      all(checked$interval_upper <= checked$final_attempts),
    "both models produced 80 finite, ordered, feasible fold-5 intervals"
  )
  checked
}

create_one_time_access_marker <- function(pretest_commit) {
  if (file.exists(access_marker_path)) {
    stop(
      "ONE-TIME FOLD-5 SAFEGUARD: an access marker already exists; no outcome was read",
      call. = FALSE
    )
  }
  dir.create(access_dir, recursive = TRUE, showWarnings = FALSE)
  marker <- list(
    complete = TRUE,
    access_count = 1L,
    season = season,
    fold = FINAL_TEST_FOLD,
    purpose = "one_time_final_predictive_comparison",
    pretest_commit = pretest_commit,
    script_sha256 = sha256_file("R/spatial_full_league_fold5_comparison.R"),
    split_sha256 = EXPECTED_SPLIT_SHA256,
    gam_fit_md5 = EXPECTED_GAM_FIT_MD5,
    car_fit_md5 = EXPECTED_CAR_FIT_MD5,
    authorized_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  temporary <- tempfile(pattern = "fold5_access_audit.rds.partial-", tmpdir = access_dir)
  saveRDS(marker, temporary)
  if (file.exists(access_marker_path) || !file.rename(temporary, access_marker_path)) {
    stop("Could not exclusively publish the fold-5 access marker", call. = FALSE)
  }
  sha256_file(access_marker_path)
}

# The only outcome loader in this file accepts fold 5 exactly. The durable
# access marker is created before this function is called, preventing reruns.
read_fold5_outcomes_once <- local({
  already_read <- FALSE
  function(folds, eligible_players) {
    if (already_read || !file.exists(access_marker_path)) {
      stop("ONE-TIME FOLD-5 SAFEGUARD blocked the outcome read", call. = FALSE)
    }
    requested_fold <- FINAL_TEST_FOLD
    if (!identical(requested_fold, 5L)) {
      stop("Final outcome loader may request fold 5 exactly", call. = FALSE)
    }
    allowed_games <- folds$GAME_ID[folds$fold == requested_fold]
    outcomes <- open_dataset(raw_path) |>
      filter(GAME_ID %in% allowed_games, PLAYER_ID %in% eligible_players) |>
      select(all_of(OUTCOME_COLUMNS)) |>
      collect() |>
      as_tibble() |>
      left_join(select(folds, GAME_ID, fold), by = "GAME_ID") |>
      filter(LOC_Y <= COURT_Y_MAX)
    already_read <<- TRUE
    check_or_stop(
      "access", "only_fold5_outcomes_opened",
      identical(sort(unique(outcomes$fold)), FINAL_TEST_FOLD),
      "the one held-out outcome read contains fold 5 only"
    )
    check_or_stop(
      "data", "fold5_outcome_values",
      !anyNA(outcomes$SHOT_MADE_FLAG) &&
        all(outcomes$SHOT_MADE_FLAG %in% c(0L, 1L)),
      "fold-5 make/miss values are complete and binary"
    )
    outcomes
  }
})

clip_for_log <- function(probability) {
  pmin(pmax(probability, LOG_EPSILON), 1 - LOG_EPSILON)
}

calibration_frame <- function(scored, model, probability_column) {
  probability_symbol <- rlang::sym(probability_column)
  scored |>
    transmute(
      GAME_ID, PLAYER_ID, final_row_id, SHOT_MADE_FLAG,
      probability = !!probability_symbol
    ) |>
    arrange(probability, GAME_ID, PLAYER_ID, final_row_id) |>
    mutate(calibration_bin = ntile(row_number(), 10L), model = model)
}

calibration_table <- function(scored, model, probability_column) {
  calibration_frame(scored, model, probability_column) |>
    summarise(
      attempts = n(),
      predicted_probability = mean(probability),
      observed_make_rate = mean(SHOT_MADE_FLAG),
      calibration_gap = observed_make_rate - predicted_probability,
      .by = calibration_bin
    ) |>
    mutate(model = model, .before = 1)
}

calibration_matrices <- function(frame, games) {
  game_factor <- factor(frame$GAME_ID, levels = games)
  bin_factor <- factor(frame$calibration_bin, levels = 1:10)
  list(
    attempts = unclass(xtabs(~ game_factor + bin_factor)),
    predicted = unclass(xtabs(frame$probability ~ game_factor + bin_factor)),
    observed = unclass(xtabs(frame$SHOT_MADE_FLAG ~ game_factor + bin_factor))
  )
}

weighted_ece <- function(matrices, weights) {
  attempts <- as.numeric(crossprod(weights, matrices$attempts))
  predicted <- as.numeric(crossprod(weights, matrices$predicted))
  observed <- as.numeric(crossprod(weights, matrices$observed))
  used <- attempts > 0
  sum(abs(observed[used] / attempts[used] - predicted[used] / attempts[used]) *
        attempts[used]) / sum(attempts[used])
}

paired_game_bootstrap <- function(scored, gam_frame, car_frame) {
  games <- sort(unique(scored$GAME_ID))
  game_losses <- scored |>
    summarise(
      attempts = n(), gam_loss = sum(gam_log_loss), car_loss = sum(car_log_loss),
      .by = GAME_ID
    ) |>
    arrange(match(GAME_ID, games))
  gam_matrices <- calibration_matrices(gam_frame, games)
  car_matrices <- calibration_matrices(car_frame, games)
  log_loss_difference <- numeric(BOOTSTRAP_DRAWS)
  calibration_ece_difference <- numeric(BOOTSTRAP_DRAWS)
  set_frozen_rng(BOOTSTRAP_SEED)
  for (draw in seq_len(BOOTSTRAP_DRAWS)) {
    weights <- tabulate(
      sample.int(length(games), length(games), replace = TRUE),
      nbins = length(games)
    )
    log_loss_difference[[draw]] <-
      sum(weights * (game_losses$gam_loss - game_losses$car_loss)) /
      sum(weights * game_losses$attempts)
    calibration_ece_difference[[draw]] <-
      weighted_ece(gam_matrices, weights) - weighted_ece(car_matrices, weights)
  }
  list(
    draws = tibble(
      draw = seq_len(BOOTSTRAP_DRAWS),
      gam_minus_car_log_loss = log_loss_difference,
      gam_minus_car_calibration_ece = calibration_ece_difference
    ),
    games = games
  )
}

folds <- read_frozen_folds()
metadata <- read_metadata_only(folds)
grid <- make_grid()
verify_fold4_record()
artifacts <- verify_artifacts(metadata, grid)
player_ids <- sort(metadata$eligible$PLAYER_ID)
final_lattice <- build_final_lattice(
  artifacts$final_metadata, player_ids, grid, artifacts$sparse_ids
)

if (mode == "audit") {
  check_or_stop(
    "access", "fold5_not_previously_opened",
    !file.exists(access_marker_path) &&
      (!dir.exists(result_dir) || length(list.files(result_dir)) == 0L),
    "no final-test access marker or result exists"
  )
  print(tibble(
    season = season, mode = mode, players = EXPECTED_PLAYERS,
    training_shots = EXPECTED_TRAINING_SHOTS,
    cells_per_player = GRID_CELLS, lattice_rows = EXPECTED_LATTICE_ROWS,
    fold5_metadata_games = n_distinct(artifacts$final_metadata$GAME_ID),
    fold5_metadata_shots = nrow(artifacts$final_metadata),
    fold5_metadata_players = n_distinct(artifacts$final_metadata$PLAYER_ID),
    frozen_checks_passed = all(bind_rows(check_records)$passed),
    fold5_outcomes_read = FALSE
  ), width = Inf)
  quit(save = "no", status = 0L)
}

if (file.exists(access_marker_path) ||
    (dir.exists(result_dir) && length(list.files(result_dir)) > 0L)) {
  stop(
    "ONE-TIME FOLD-5 SAFEGUARD: access or results already exist; refusing to rerun",
    call. = FALSE
  )
}

pretest_commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
origin_commit <- system2(
  "git", c("rev-parse", "origin/codex/spatial-shot-selection"), stdout = TRUE
)
check_or_stop(
  "reproducibility", "pretest_commit_pushed",
  length(pretest_commit) == 1L && grepl("^[0-9a-f]{40}$", pretest_commit) &&
    identical(pretest_commit, origin_commit),
  pretest_commit
)

# Both interval calculations finish before the one-time fold-5 outcome read.
gam_uncertainty <- gam_fold5_intervals(
  final_lattice, artifacts$sparse_ids, artifacts$gam_probabilities
)
car_uncertainty <- car_fold5_intervals(final_lattice, artifacts$sparse_ids)
intervals <- validate_intervals(
  gam_uncertainty, car_uncertainty, final_lattice, artifacts$sparse_ids
)
check_or_stop(
  "models", "no_model_refit_or_repair",
  !any(grepl("bam\\s*\\(|INLA::inla\\s*\\(", readLines(
    "R/spatial_full_league_fold5_comparison.R", warn = FALSE
  ))),
  "evaluation script contains prediction/posterior sampling but no model-fitting call"
)

access_marker_sha256 <- create_one_time_access_marker(pretest_commit)
final <- read_fold5_outcomes_once(folds, player_ids) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y, SHOT_MADE_FLAG) |>
  mutate(final_row_id = row_number())
metadata_keys <- artifacts$final_metadata |>
  select(all_of(METADATA_COLUMNS), fold) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
outcome_keys <- final |>
  select(all_of(METADATA_COLUMNS), fold) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
check_or_stop(
  "access", "fold5_rows_match_preopened_metadata",
  identical(as.data.frame(metadata_keys), as.data.frame(outcome_keys)),
  paste(nrow(final), "fold-5 outcomes match metadata audited before access")
)

final <- assign_grid_cells(final, grid)
gam_predictions <- artifacts$gam_probabilities |>
  transmute(PLAYER_ID, cell_id, gam_probability = probability)
car_predictions <- artifacts$car_probabilities |>
  transmute(PLAYER_ID, cell_id, car_probability = probability)
scored <- final |>
  left_join(gam_predictions, by = c("PLAYER_ID", "cell_id")) |>
  left_join(car_predictions, by = c("PLAYER_ID", "cell_id"))
check_or_stop(
  "evaluation", "identical_complete_scoring_rows",
  nrow(scored) == nrow(final) &&
    !anyNA(scored$gam_probability) && !anyNA(scored$car_probability),
  "every fold-5 shot has exactly one GAM and one CAR probability"
)
check_or_stop(
  "evaluation", "scored_probability_bounds",
  all(is.finite(scored$gam_probability)) && all(is.finite(scored$car_probability)) &&
    all(scored$gam_probability >= 0 & scored$gam_probability <= 1) &&
    all(scored$car_probability >= 0 & scored$car_probability <= 1),
  "all final-test probabilities are finite and within [0,1] before clipping"
)
check_or_stop(
  "evaluation", "no_duplicate_prediction_keys",
  !anyDuplicated(gam_predictions[c("PLAYER_ID", "cell_id")]) &&
    !anyDuplicated(car_predictions[c("PLAYER_ID", "cell_id")]),
  "one saved prediction per player-cell for each model"
)

scored <- scored |>
  mutate(
    gam_clipped = clip_for_log(gam_probability),
    car_clipped = clip_for_log(car_probability),
    gam_log_loss = -(SHOT_MADE_FLAG * log(gam_clipped) +
      (1L - SHOT_MADE_FLAG) * log(1 - gam_clipped)),
    car_log_loss = -(SHOT_MADE_FLAG * log(car_clipped) +
      (1L - SHOT_MADE_FLAG) * log(1 - car_clipped))
  )

gam_calibration_frame <- calibration_frame(scored, "GAM", "gam_probability")
car_calibration_frame <- calibration_frame(scored, "CAR", "car_probability")
calibration_bins <- bind_rows(
  calibration_table(scored, "GAM", "gam_probability"),
  calibration_table(scored, "CAR", "car_probability")
) |>
  mutate(
    absolute_gap = abs(calibration_gap), season = season,
    evaluation_fold = FINAL_TEST_FOLD, .before = 1
  ) |>
  arrange(model, calibration_bin)

player_calibration <- bind_rows(
  scored |>
    summarise(
      attempts = n(), observed_makes = sum(SHOT_MADE_FLAG),
      predicted_makes = sum(gam_probability), .by = PLAYER_ID
    ) |>
    mutate(model = "GAM", .before = 1),
  scored |>
    summarise(
      attempts = n(), observed_makes = sum(SHOT_MADE_FLAG),
      predicted_makes = sum(car_probability), .by = PLAYER_ID
    ) |>
    mutate(model = "CAR", .before = 1)
) |>
  mutate(
    error = observed_makes - predicted_makes,
    absolute_error = abs(error), squared_error = error^2,
    season = season, evaluation_fold = FINAL_TEST_FOLD, .before = 1
  ) |>
  arrange(model, PLAYER_ID)

sparse_actuals <- scored |>
  filter(PLAYER_ID %in% artifacts$sparse_ids) |>
  summarise(
    final_attempts = n(), observed_makes = sum(SHOT_MADE_FLAG),
    .by = PLAYER_ID
  )
sparse_intervals <- intervals |>
  select(-final_attempts) |>
  left_join(sparse_actuals, by = "PLAYER_ID") |>
  mutate(
    covered_90 = observed_makes >= interval_lower & observed_makes <= interval_upper,
    season = season, evaluation_fold = FINAL_TEST_FOLD, .before = 1
  ) |>
  arrange(model, PLAYER_ID)
check_or_stop(
  "uncertainty", "sparse_interval_evaluation_dimensions",
  nrow(sparse_intervals) == 2L * EXPECTED_SPARSE_PLAYERS &&
    all(count(sparse_intervals, model)$n == EXPECTED_SPARSE_PLAYERS) &&
    !anyNA(sparse_intervals$final_attempts),
  "two evaluated interval rows for each of 80 sparse players"
)

bootstrap <- paired_game_bootstrap(
  scored, gam_calibration_frame, car_calibration_frame
)
check_or_stop(
  "bootstrap", "paired_game_bootstrap_dimensions",
  length(bootstrap$games) == 246L && nrow(bootstrap$draws) == BOOTSTRAP_DRAWS &&
    all(is.finite(bootstrap$draws$gam_minus_car_log_loss)) &&
    all(is.finite(bootstrap$draws$gam_minus_car_calibration_ece)),
  "2,000 finite paired resamples of all 246 fold-5 games"
)

model_metrics <- tibble(
  model = c("GAM", "CAR"),
  log_loss = c(mean(scored$gam_log_loss), mean(scored$car_log_loss))
) |>
  left_join(
    calibration_bins |>
      summarise(
        calibration_ece = weighted.mean(absolute_gap, attempts),
        calibration_max_absolute_gap = max(absolute_gap), .by = model
      ),
    by = "model"
  ) |>
  left_join(
    player_calibration |>
      summarise(
        player_total_mae = mean(absolute_error),
        player_total_rmse = sqrt(mean(squared_error)),
        player_total_mean_bias_observed_minus_predicted = mean(error),
        .by = model
      ),
    by = "model"
  ) |>
  left_join(
    sparse_intervals |>
      summarise(
        sparse_coverage_90 = mean(covered_90),
        sparse_average_interval_width = mean(interval_width), .by = model
      ),
    by = "model"
  ) |>
  mutate(
    season = season, evaluation_fold = FINAL_TEST_FOLD,
    final_test = TRUE, validation_games = n_distinct(scored$GAME_ID),
    validation_shots = nrow(scored),
    validation_players = n_distinct(scored$PLAYER_ID),
    probability_clip_lower = LOG_EPSILON,
    probability_clip_upper = 1 - LOG_EPSILON,
    uncertainty_generation_elapsed_sec = if_else(
      model == "GAM", gam_uncertainty$elapsed_sec, car_uncertainty$elapsed_sec
    ),
    training_fit_elapsed_sec_descriptive = if_else(
      model == "GAM", artifacts$gam_metrics$fit_elapsed_sec[[1]],
      artifacts$car_metrics$fit_elapsed_sec[[1]]
    ),
    .before = 1
  )

point_log_difference <-
  model_metrics$log_loss[model_metrics$model == "GAM"] -
  model_metrics$log_loss[model_metrics$model == "CAR"]
point_ece_difference <-
  model_metrics$calibration_ece[model_metrics$model == "GAM"] -
  model_metrics$calibration_ece[model_metrics$model == "CAR"]
log_interval <- quantile(
  bootstrap$draws$gam_minus_car_log_loss, c(0.025, 0.975), names = FALSE
)
ece_interval <- quantile(
  bootstrap$draws$gam_minus_car_calibration_ece,
  c(0.025, 0.975), names = FALSE
)
bootstrap_summary <- tibble(
  season = season, evaluation_fold = FINAL_TEST_FOLD, final_test = TRUE,
  bootstrap_unit = "whole_game", bootstrap_seed = BOOTSTRAP_SEED,
  bootstrap_draws = BOOTSTRAP_DRAWS,
  difference_direction = "GAM minus CAR; positive favors CAR",
  gam_minus_car_log_loss = point_log_difference,
  gam_minus_car_log_loss_ci_lower = log_interval[[1]],
  gam_minus_car_log_loss_ci_upper = log_interval[[2]],
  gam_minus_car_calibration_ece = point_ece_difference,
  gam_minus_car_calibration_ece_ci_lower = ece_interval[[1]],
  gam_minus_car_calibration_ece_ci_upper = ece_interval[[2]]
)

car_calibration_materially_worse <- ece_interval[[2]] < 0
primary_classification <- if (log_interval[[1]] > 0) {
  "favors_car"
} else if (log_interval[[2]] < 0) {
  "favors_gam"
} else {
  "practically_tied"
}
evidence_classification <- if (
  identical(primary_classification, "favors_car") &&
    !car_calibration_materially_worse
) {
  "favors_car"
} else if (identical(primary_classification, "favors_gam")) {
  "favors_gam"
} else {
  "practically_tied"
}
decision_reason <- if (identical(evidence_classification, "favors_car")) {
  paste(
    "The paired whole-game log-loss interval is entirely above zero and",
    "CAR does not have a clearly worse calibration ECE interval."
  )
} else if (identical(evidence_classification, "favors_gam")) {
  "The paired whole-game log-loss interval is entirely below zero."
} else if (
  identical(primary_classification, "favors_car") &&
    car_calibration_materially_worse
) {
  paste(
    "Log loss favors CAR, but calibration ECE clearly favors GAM;",
    "the frozen final-test rule therefore records a practical tie."
  )
} else {
  paste(
    "The paired whole-game log-loss interval includes zero, so the numerical",
    "difference is treated as normal evaluation noise."
  )
}
decision <- tibble(
  season = season, evaluation_fold = FINAL_TEST_FOLD,
  result_scope = "full_league_fold5_one_time_final_test",
  evidence_classification = evidence_classification,
  primary_classification = primary_classification,
  car_calibration_materially_worse = car_calibration_materially_worse,
  secondary_metrics_override_primary = FALSE,
  decision_reason = decision_reason,
  final_test = TRUE, model_settings_changed = FALSE,
  models_refitted = FALSE, fold5_outcomes_read = TRUE
)

check_or_stop(
  "access", "access_marker_unchanged",
  file.exists(access_marker_path) &&
    sha256_file(access_marker_path) == access_marker_sha256,
  access_marker_sha256
)
check_or_stop(
  "final", "all_checks_passed_before_write",
  all(bind_rows(check_records)$passed),
  paste(length(check_records), "checks passed before result publication")
)

manifest <- tibble(
  season = season, scope = "full_league_fold5_one_time_final_test",
  pretest_commit = pretest_commit,
  fold4_pre_evaluation_commit = EXPECTED_FOLD4_PRE_EVALUATION_COMMIT,
  fold4_result_commit = EXPECTED_FOLD4_RESULT_COMMIT,
  access_marker_sha256 = access_marker_sha256,
  selected_grid_width = GRID_WIDTH,
  selected_grid_source = "predeclared_40_player_fallback_fold4_selection",
  training_folds = "1,2,3", final_test_fold = FINAL_TEST_FOLD,
  models_refitted = FALSE,
  primary_metric = "pooled per-shot binomial log loss",
  metric_direction = "GAM minus CAR; positive favors CAR",
  probability_clipping = "[1e-15, 1-1e-15] for logarithms only",
  calibration_rule = paste(
    "model-specific equal-count deciles; weighted absolute gap and maximum gap;",
    "per-player predicted versus observed total makes"
  ),
  uncertainty_rule = paste(
    "folds-1-to-3 bottom 80 players; regenerated frozen 4,000-draw",
    "90% posterior-predictive intervals for fold-5 attempts"
  ),
  bootstrap_rule = "2,000 paired whole-game resamples; percentile 95% interval",
  bootstrap_seed = BOOTSTRAP_SEED,
  interpretation_rule = paste(
    "CAR requires an entirely positive log-loss interval and no entirely",
    "negative calibration-ECE interval; entirely negative log-loss favors GAM;",
    "otherwise practically tied; secondary measures cannot override"
  ),
  fold5_outcomes_read = TRUE,
  gam_completion_sha256 = EXPECTED_GAM_COMPLETION_SHA256,
  gam_fit_sha256 = EXPECTED_GAM_FIT_SHA256,
  gam_input_sha256 = EXPECTED_GAM_INPUT_SHA256,
  car_completion_sha256 = EXPECTED_CAR_COMPLETION_SHA256,
  car_model_checkpoint_sha256 = EXPECTED_CAR_MODEL_CHECKPOINT_SHA256,
  car_fit_sha256 = EXPECTED_CAR_FIT_SHA256,
  split_sha256 = EXPECTED_SPLIT_SHA256,
  gam_uncertainty_warning_count = length(gam_uncertainty$warnings),
  car_uncertainty_warning_count = length(car_uncertainty$warnings),
  car_uncertainty_warnings = paste(car_uncertainty$warnings, collapse = " | "),
  car_uncertainty_message_count = length(car_uncertainty$messages),
  car_uncertainty_messages = paste(car_uncertainty$messages, collapse = " | ")
)
checks <- bind_rows(check_records) |>
  mutate(
    season = season, evaluation_fold = FINAL_TEST_FOLD,
    fold5_outcomes_read = TRUE, .before = 1
  )

outputs <- list(
  comparison_manifest = manifest,
  model_metrics = model_metrics,
  calibration_bins = calibration_bins,
  player_calibration = player_calibration,
  sparse_player_uncertainty = sparse_intervals,
  bootstrap_summary = bootstrap_summary,
  decision = decision,
  sanity_checks = checks
)
for (name in names(outputs)) {
  write_new_atomic_parquet(
    outputs[[name]], file.path(result_dir, paste0(name, ".parquet"))
  )
}

print(model_metrics, width = Inf)
print(bootstrap_summary, width = Inf)
print(decision, width = Inf)
