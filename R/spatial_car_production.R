# Frozen all-data production fit for the selected Bayesian CAR model.
#
# This script never compares models or calculates held-out accuracy. Audit mode
# reads metadata only. Prepare mode freezes the all-five-fold production input
# and configuration without fitting. Run mode requires their pre-registered
# hashes, fits exactly once, and publishes only fully checked atomic artifacts.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

SCRIPT_STARTED <- proc.time()[["elapsed"]]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: Rscript R/spatial_car_production.R <season> <audit|prepare|run>",
    call. = FALSE
  )
}

season <- args[[1]]
mode <- args[[2]]
if (!identical(season, "2025-26")) {
  stop("The frozen production fit is registered only for 2025-26", call. = FALSE)
}
if (!mode %in% c("audit", "prepare", "run")) {
  stop("Mode must be audit, prepare, or run", call. = FALSE)
}

AUTHORIZED_FOLDS <- 1:5
GRID_WIDTH <- 40L
GRID_CELLS <- 156L
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
EXPECTED_PLAYERS <- 318L
EXPECTED_GAMES <- 1230L
EXPECTED_LATTICE_ROWS <- 49608L
EXPECTED_METADATA_SHOTS <- 194987L
EXPECTED_METADATA_FOLD_COUNTS <- c(38794L, 38827L, 39334L, 38820L, 39212L)
EXPECTED_OBSERVED_PLAYER_CELLS <- 22447L
POSTERIOR_DRAWS <- 4000L
CAR_DRAW_SEED <- 20260902L
PREDICTIVE_SEED <- 20260903L
MODEL_THREADS <- 1L
SURFACE_TOLERANCE <- 1e-8
SPECIFICATION_ID <- "frozen-car-production-all-folds-grid40-v1"
FINAL_RESULT_COMMIT <- "f7d7a155f49cd33b8fcb5978a90f62b2a6ae84c3"
ORIGINAL_FOLD5_PRETEST_COMMIT <- "49d98bbf584ca019a36cddc51329a0478e801846"
RECOVERY_PRETEST_COMMIT <- "5d47e6b0b4117165dedb8688b8810fc9ea2320be"
EXPECTED_SPLIT_SHA256 <- "aaee94c1e8380999190aea5f00f8c02c738db6438ffe7b7a1a761d19c5a6ee33"
EXPECTED_PLAYER_SOURCE_SHA256 <- "9608cd06ef83ab0866ad1c81f8d25802326d3f91cc349a81c570f46103eaae47"
EXPECTED_CAR_COMPARISON_CHECKPOINT_SHA256 <- "6ab8ab7aa45592e9a1677cc3eece9a71944dc89ad3db8fb0dbb38942e4fd57f9"

# Filled from prepare mode before the pre-fit commit. Run mode refuses to fit
# while either value is not a lowercase 64-character SHA-256 hash.
EXPECTED_PRODUCTION_INPUT_SHA256 <- "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6"
EXPECTED_PRODUCTION_CONFIG_SHA256 <- "fc072f03e0579f32eba941717c4c8767912b72f82584d7e4842c6dab2699a80e"

EXPECTED_R_VERSION <- "4.6.0"
EXPECTED_VERSIONS <- c(
  INLA = "26.8.7",
  Matrix = "1.7.5",
  fmesher = "0.8.0",
  sn = "2.1.3",
  arrow = "25.0.0",
  dplyr = "1.2.1",
  tidyr = "1.3.2"
)

raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", season), "shots.parquet"
)
split_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "game_folds.parquet"
)
player_source_path <- file.path(
  "data", "cache", "spatial_gam_exact_full_league_benchmark",
  paste0("season=", season), "input_signature.rds"
)
comparison_car_checkpoint_path <- file.path(
  "data", "cache", "spatial_car_full_league_benchmark",
  paste0("season=", season), "car_grid_40_checkpoint.rds"
)
final_result_dir <- file.path(
  "data", "processed", "spatial_full_league_fold5_comparison",
  paste0("season=", season)
)
cache_dir <- file.path(
  "data", "cache", "spatial_car_production", paste0("season=", season)
)
result_dir <- file.path(
  "data", "processed", "spatial_car_production", paste0("season=", season)
)

config_path <- file.path(cache_dir, "production_configuration.rds")
input_path <- file.path(cache_dir, "production_input.rds")
fit_path <- file.path(cache_dir, "car_production_fit.rds")
surface_path <- file.path(cache_dir, "player_probability_surfaces.parquet")
uncertainty_path <- file.path(cache_dir, "player_uncertainty_summary.parquet")
hyperparameter_path <- file.path(cache_dir, "hyperparameter_summary.parquet")
model_checkpoint_path <- file.path(cache_dir, "model_checkpoint.rds")
completion_path <- file.path(cache_dir, "production_complete_checkpoint.rds")
resource_path <- file.path(cache_dir, "resource_samples.rds")
pid_path <- file.path(cache_dir, "pid_metadata.rds")
lock_path <- file.path(cache_dir, "active_run.lock")

METADATA_COLUMNS <- c(
  "GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y",
  "SHOT_ATTEMPTED_FLAG"
)
OUTCOME_COLUMNS <- c(METADATA_COLUMNS, "SHOT_MADE_FLAG")

check_records <- list()
record_check <- function(area, check, condition, detail) {
  passed <- isTRUE(condition)
  check_records[[length(check_records) + 1L]] <<- tibble(
    area = area,
    check = check,
    passed = passed,
    detail = as.character(detail)
  )
  if (!passed) {
    stop("PRODUCTION CHECK FAILED: ", check, " — ", detail, call. = FALSE)
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

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(value) != 1L) {
    stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  }
  strsplit(value, "[[:space:]]+")[[1]][[1]]
}

is_sha256 <- function(value) {
  length(value) == 1L && grepl("^[0-9a-f]{64}$", value)
}

write_new_atomic_rds <- function(object, path, compress = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    stop("Refusing to replace existing production artifact: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"), tmpdir = dirname(path)
  )
  saveRDS(object, temporary, compress = compress)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish artifact; partial preserved: ", temporary,
         call. = FALSE)
  }
  invisible(path)
}

write_replace_atomic_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"), tmpdir = dirname(path)
  )
  saveRDS(object, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically update recovery metadata: ", path, call. = FALSE)
  }
  invisible(path)
}

write_new_atomic_parquet <- function(table, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    stop("Refusing to replace existing production table: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path), fileext = ".parquet"
  )
  write_parquet(table, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish table; partial preserved: ", temporary,
         call. = FALSE)
  }
  invisible(path)
}

copy_new_atomic_file <- function(source, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    stop("Refusing to replace existing production file: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"), tmpdir = dirname(path)
  )
  if (!file.copy(source, temporary, overwrite = FALSE) ||
      !file.rename(temporary, path)) {
    stop("Could not atomically copy production file; partial preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

publish_stage <- function(number, name, detail = "") {
  path <- file.path(cache_dir, sprintf("stage_%02d_%s.rds", number, name))
  write_new_atomic_rds(
    list(
      complete = TRUE,
      stage_number = as.integer(number),
      stage = name,
      detail = detail,
      pid = Sys.getpid(),
      recorded_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    ),
    path
  )
  invisible(path)
}

git_value <- function(args) {
  value <- system2("git", args, stdout = TRUE, stderr = TRUE)
  status <- attr(value, "status")
  if (!is.null(status) && status != 0L) {
    stop("Git verification failed: ", paste(value, collapse = " | "), call. = FALSE)
  }
  value
}

verify_versions <- function() {
  record_check(
    "configuration", "r_version", getRversion() == EXPECTED_R_VERSION,
    paste("expected", EXPECTED_R_VERSION, "found", getRversion())
  )
  for (package in names(EXPECTED_VERSIONS)) {
    found <- as.character(packageVersion(package))
    record_check(
      "configuration", paste0("package_", package),
      identical(found, EXPECTED_VERSIONS[[package]]),
      paste("expected", EXPECTED_VERSIONS[[package]], "found", found)
    )
  }
}

verify_selection_result <- function() {
  required <- file.path(
    final_result_dir,
    c(
      "comparison_manifest.parquet", "model_metrics.parquet",
      "bootstrap_summary.parquet", "decision.parquet", "sanity_checks.parquet"
    )
  )
  record_check(
    "selection", "final_result_files_exist", all(file.exists(required)),
    "final fold-5 manifest, metrics, bootstrap, decision, and checks exist"
  )
  manifest <- read_parquet(required[[1]])
  metrics <- read_parquet(required[[2]])
  bootstrap <- read_parquet(required[[3]])
  decision <- read_parquet(required[[4]])
  checks <- read_parquet(required[[5]])
  head <- git_value(c("rev-parse", "HEAD"))[[1]]
  original_pretest_preceded <- system2(
    "git", c("merge-base", "--is-ancestor", ORIGINAL_FOLD5_PRETEST_COMMIT,
             RECOVERY_PRETEST_COMMIT)
  ) == 0L
  result_is_ancestor <- system2(
    "git", c("merge-base", "--is-ancestor", FINAL_RESULT_COMMIT, head)
  ) == 0L
  record_check(
    "selection", "final_result_is_immutable_and_verified",
    nrow(checks) == 46L && all(checks$passed) &&
      identical(manifest$pretest_commit[[1]], RECOVERY_PRETEST_COMMIT) &&
      isTRUE(manifest$fold5_outcomes_read[[1]]) &&
      !isTRUE(manifest$models_refitted[[1]]) &&
      original_pretest_preceded && result_is_ancestor,
    paste("46 checks passed; pre-test 49d98bb preceded access; result", head)
  )
  gam_loss <- metrics$log_loss[metrics$model == "GAM"]
  car_loss <- metrics$log_loss[metrics$model == "CAR"]
  record_check(
    "selection", "frozen_final_metrics",
    abs(gam_loss - 0.66391031147909441) < 1e-15 &&
      abs(car_loss - 0.65968043339499571) < 1e-15 &&
      abs(bootstrap$gam_minus_car_log_loss[[1]] -
            0.0042298780840986927) < 1e-15 &&
      abs(bootstrap$gam_minus_car_log_loss_ci_lower[[1]] -
            0.0030253808748117879) < 1e-15 &&
      abs(bootstrap$gam_minus_car_log_loss_ci_upper[[1]] -
            0.0053455716593744356) < 1e-15 &&
      identical(decision$evidence_classification[[1]], "favors_car"),
    "exact GAM 0.6639103; CAR 0.6596804; frozen rule selects CAR"
  )
}

read_split <- function() {
  record_check(
    "input", "split_sha256",
    file.exists(split_path) && sha256_file(split_path) == EXPECTED_SPLIT_SHA256,
    EXPECTED_SPLIT_SHA256
  )
  folds <- read_parquet(split_path) |>
    as_tibble() |>
    arrange(GAME_ID)
  counts <- count(folds, fold)
  record_check(
    "input", "split_complete_unique",
    nrow(folds) == EXPECTED_GAMES &&
      n_distinct(folds$GAME_ID) == EXPECTED_GAMES &&
      identical(counts$fold, AUTHORIZED_FOLDS) &&
      all(counts$n == 246L) && is.character(folds$GAME_ID),
    "1,230 unique text game ids; 246 per fold"
  )
  folds
}

read_frozen_player_registry <- function() {
  record_check(
    "input", "player_source_sha256",
    file.exists(player_source_path) &&
      sha256_file(player_source_path) == EXPECTED_PLAYER_SOURCE_SHA256,
    EXPECTED_PLAYER_SOURCE_SHA256
  )
  record_check(
    "input", "comparison_car_checkpoint_sha256",
    file.exists(comparison_car_checkpoint_path) &&
      sha256_file(comparison_car_checkpoint_path) ==
        EXPECTED_CAR_COMPARISON_CHECKPOINT_SHA256,
    EXPECTED_CAR_COMPARISON_CHECKPOINT_SHA256
  )
  signature <- readRDS(player_source_path)
  checkpoint <- readRDS(comparison_car_checkpoint_path)
  player_ids <- sort(signature$player_ids)
  car_player_ids <- sort(unique(checkpoint$result$probabilities$PLAYER_ID))
  record_check(
    "selection", "comparison_car_specification_matches_production",
    identical(checkpoint$specification_id,
              "frozen-car-full-league-grid40-training-v1") &&
      identical(checkpoint$result$metrics$formula[[1]], formula_text()),
    "production reuses the selected CAR formula without modification"
  )
  record_check(
    "input", "frozen_player_ids_match_both_models",
    length(player_ids) == EXPECTED_PLAYERS &&
      length(unique(player_ids)) == EXPECTED_PLAYERS &&
      identical(player_ids, car_player_ids),
    "same frozen 318-player id set from the exact-GAM and CAR artifacts"
  )
  player_ids
}

read_metadata_only <- function(folds, player_ids) {
  schema_names <- names(read_parquet(raw_path, as_data_frame = FALSE)$schema)
  record_check(
    "input", "raw_schema", all(OUTCOME_COLUMNS %in% schema_names),
    "all frozen metadata and outcome columns exist"
  )
  metadata <- read_parquet(raw_path, col_select = all_of(METADATA_COLUMNS)) |>
    as_tibble()
  record_check(
    "input", "metadata_excludes_outcome",
    !"SHOT_MADE_FLAG" %in% names(metadata),
    "audit mode did not select make/miss"
  )
  record_check(
    "input", "metadata_valid",
    is.character(metadata$GAME_ID) && !anyNA(metadata) &&
      all(metadata$SHOT_ATTEMPTED_FLAG == 1L) &&
      all(metadata$LOC_X >= COURT_X_MIN & metadata$LOC_X <= COURT_X_MAX) &&
      all(metadata$LOC_Y >= COURT_Y_MIN),
    "game ids, required values, and court bounds are valid"
  )
  in_play <- metadata |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    left_join(folds, by = "GAME_ID")
  record_check(
    "input", "all_in_play_rows_have_one_fold", !anyNA(in_play$fold),
    paste(nrow(in_play), "in-play metadata rows")
  )
  recalculated <- in_play |>
    summarise(
      season_attempts = n(), season_games = n_distinct(GAME_ID),
      .by = PLAYER_ID
    ) |>
    filter(season_games >= MIN_GAMES, season_attempts >= MIN_ATTEMPTS) |>
    arrange(PLAYER_ID)
  record_check(
    "input", "eligibility_reproduction_only",
    identical(recalculated$PLAYER_ID, player_ids),
    "eligibility rule reproduces frozen ids; saved ids remain authoritative"
  )
  names <- in_play |>
    filter(PLAYER_ID %in% player_ids) |>
    summarise(
      PLAYER_NAME = first(PLAYER_NAME), name_count = n_distinct(PLAYER_NAME),
      .by = PLAYER_ID
    ) |>
    arrange(PLAYER_ID)
  record_check(
    "input", "player_registry_complete_unique",
    nrow(names) == EXPECTED_PLAYERS && all(names$name_count == 1L) &&
      identical(names$PLAYER_ID, player_ids),
    "one stable name for every frozen player id"
  )
  eligible_metadata <- in_play |>
    filter(PLAYER_ID %in% player_ids)
  fold_counts <- count(eligible_metadata, fold) |>
    arrange(fold)
  record_check(
    "input", "all_fold_metadata_counts",
    nrow(eligible_metadata) == EXPECTED_METADATA_SHOTS &&
      n_distinct(eligible_metadata$GAME_ID) == EXPECTED_GAMES &&
      identical(fold_counts$fold, AUTHORIZED_FOLDS) &&
      identical(as.integer(fold_counts$n), EXPECTED_METADATA_FOLD_COUNTS),
    paste("194,987 shots; fold counts", paste(fold_counts$n, collapse = ","))
  )
  list(
    eligible = eligible_metadata,
    registry = select(names, PLAYER_ID, PLAYER_NAME),
    fold_counts = fold_counts
  )
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
  record_check(
    "grid", "fixed_grid_dimensions",
    nrow(grid) == GRID_CELLS && identical(grid$cell_id, seq_len(GRID_CELLS)),
    "fixed 40-unit grid has 156 cells"
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
  record_check(
    "grid", "all_rows_map_to_grid", all(assigned$cell_id %in% grid$cell_id),
    paste(nrow(assigned), "rows mapped to fixed grid")
  )
  assigned
}

make_graph <- function(grid) {
  nx <- attr(grid, "nx")
  ny <- attr(grid, "ny")
  horizontal <- grid |>
    filter(x_index < nx) |>
    transmute(from = cell_id, to = cell_id + 1L)
  vertical <- grid |>
    filter(y_index < ny) |>
    transmute(from = cell_id, to = cell_id + nx)
  edges <- bind_rows(horizontal, vertical)
  Matrix::sparseMatrix(
    i = c(edges$from, edges$to),
    j = c(edges$to, edges$from),
    x = 1,
    dims = c(nrow(grid), nrow(grid))
  )
}

graph_is_connected <- function(graph) {
  visited <- rep(FALSE, nrow(graph))
  queue <- 1L
  visited[[1]] <- TRUE
  while (length(queue) > 0L) {
    current <- queue[[1]]
    queue <- queue[-1L]
    neighbours <- which(graph[current, ] != 0)
    new <- neighbours[!visited[neighbours]]
    if (length(new) > 0L) {
      visited[new] <- TRUE
      queue <- c(queue, new)
    }
  }
  all(visited)
}

validate_graph <- function(graph) {
  degrees <- Matrix::rowSums(graph)
  record_check(
    "graph", "binary_symmetric_zero_diagonal",
    all(graph@x == 1) &&
      isTRUE(all.equal(graph, Matrix::t(graph))) &&
      all(Matrix::diag(graph) == 0),
    paste(Matrix::nnzero(graph) / 2, "undirected rook edges")
  )
  record_check(
    "graph", "connected_no_isolates",
    all(degrees > 0) && graph_is_connected(graph),
    paste("degree range", min(degrees), "to", max(degrees))
  )
}

formula_text <- function() {
  paste(
    deparse(
      y ~ 0 + player_factor +
        f(
          cell_id,
          model = "besagproper2",
          graph = graph,
          replicate = player_index,
          nrep = n_players,
          constr = FALSE,
          diagonal = 0,
          hyper = list(
            prec = list(
              prior = "pc.prec", param = c(1, 0.01),
              initial = 0, fixed = FALSE
            ),
            lambda = list(
              prior = "logitbeta", param = c(1, 1),
              initial = 0, fixed = FALSE
            )
          )
        )
    ),
    collapse = " "
  )
}

production_configuration <- function() {
  list(
    complete = TRUE,
    specification_id = SPECIFICATION_ID,
    season = season,
    model = "Bayesian CAR selected at final result commit f7d7a15",
    authorized_folds = AUTHORIZED_FOLDS,
    eligibility_source_sha256 = EXPECTED_PLAYER_SOURCE_SHA256,
    player_count = EXPECTED_PLAYERS,
    grid_width = GRID_WIDTH,
    cells_per_player = GRID_CELLS,
    lattice_rows = EXPECTED_LATTICE_ROWS,
    court = c(
      x_min = COURT_X_MIN, x_max = COURT_X_MAX,
      y_min = COURT_Y_MIN, y_max = COURT_Y_MAX
    ),
    adjacency = "binary symmetric rook; zero diagonal; connected; unscaled",
    formula = formula_text(),
    likelihood = "binomial makes with Ntrials=attempts; NA for empty cells",
    fixed_effect_prior = list(
      mean = 0, precision = 0.001,
      expand_factor_strategy = "model.matrix"
    ),
    precision_prior = list(name = "pc.prec", parameters = c(1, 0.01)),
    dependence_prior = list(name = "logitbeta", parameters = c(1, 1)),
    shared_hyperparameters = TRUE,
    constraint = FALSE,
    diagonal = 0,
    family = "binomial",
    predictor = list(compute = TRUE, link = 1),
    compute = list(
      config = TRUE, dic = FALSE, waic = FALSE, cpo = FALSE,
      return_marginals_predictor = TRUE
    ),
    inla = list(
      strategy = "simplified.laplace", integration = "auto",
      threads = MODEL_THREADS, safe = FALSE, verbose = FALSE
    ),
    posterior_draws = POSTERIOR_DRAWS,
    posterior_seed = CAR_DRAW_SEED,
    predictive_seed = PREDICTIVE_SEED,
    probability = "summary.fitted.values$mean on full lattice",
    uncertainty = paste(
      "4,000 joint predictor samples transformed with plogis; 90% cell",
      "probability intervals and player-total posterior-predictive intervals",
      "with binomial shot noise"
    ),
    package_versions = c(R = EXPECTED_R_VERSION, EXPECTED_VERSIONS),
    local_surface_schema = c(
      "PLAYER_ID", "PLAYER_NAME", "cell_id", "x_ft", "y_ft", "attempts",
      "makes", "probability", "draw_mean_probability", "probability_sd",
      "probability_lower_90", "probability_median", "probability_upper_90"
    ),
    player_uncertainty_schema = c(
      "PLAYER_ID", "PLAYER_NAME", "attempts", "observed_makes",
      "posterior_expected_makes", "posterior_predictive_mean_makes",
      "interval_lower_90", "interval_upper_90", "interval_width_90"
    ),
    tracked_outputs = c(
      "production_manifest.parquet", "surface_qa.parquet",
      "player_uncertainty_summary.parquet", "hyperparameter_summary.parquet",
      "sanity_checks.parquet", "environment_notices.parquet"
    )
  )
}

audit_state <- function() {
  verify_versions()
  verify_selection_result()
  folds <- read_split()
  player_ids <- read_frozen_player_registry()
  metadata <- read_metadata_only(folds, player_ids)
  grid <- make_grid()
  metadata_cells <- assign_grid_cells(metadata$eligible, grid) |>
    distinct(PLAYER_ID, cell_id)
  record_check(
    "input", "metadata_observed_player_cells",
    nrow(metadata_cells) == EXPECTED_OBSERVED_PLAYER_CELLS,
    paste(nrow(metadata_cells), "all-data observed player-cells")
  )
  graph <- make_graph(grid)
  validate_graph(graph)
  list(
    folds = folds,
    player_ids = player_ids,
    metadata = metadata,
    grid = grid,
    graph = graph
  )
}

read_all_authorized_outcomes <- function(audit) {
  allowed_games <- audit$folds$GAME_ID[
    audit$folds$fold %in% AUTHORIZED_FOLDS
  ]
  shots <- open_dataset(raw_path) |>
    filter(
      GAME_ID %in% allowed_games,
      PLAYER_ID %in% audit$player_ids
    ) |>
    select(all_of(OUTCOME_COLUMNS)) |>
    collect() |>
    as_tibble() |>
    left_join(select(audit$folds, GAME_ID, fold), by = "GAME_ID") |>
    filter(LOC_Y <= COURT_Y_MAX)
  record_check(
    "input", "all_five_outcome_folds_once",
    !anyNA(shots$fold) &&
      identical(sort(unique(shots$fold)), AUTHORIZED_FOLDS) &&
      nrow(shots) == EXPECTED_METADATA_SHOTS &&
      identical(
        as.integer(count(shots, fold) |> arrange(fold) |> pull(n)),
        EXPECTED_METADATA_FOLD_COUNTS
      ),
    paste(nrow(shots), "authorized outcomes from folds 1-5 exactly once")
  )
  record_check(
    "input", "outcomes_binary_complete",
    !anyNA(shots$SHOT_MADE_FLAG) &&
      all(shots$SHOT_MADE_FLAG %in% c(0L, 1L)),
    "all production make/miss values are binary and complete"
  )
  metadata_keys <- audit$metadata$eligible |>
    select(all_of(METADATA_COLUMNS), fold) |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  outcome_keys <- shots |>
    select(all_of(METADATA_COLUMNS), fold) |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  record_check(
    "input", "outcomes_match_audited_metadata",
    identical(as.data.frame(metadata_keys), as.data.frame(outcome_keys)),
    "production outcomes exactly match the audited metadata rows"
  )
  shots
}

build_production_input <- function(audit, shots) {
  assigned <- assign_grid_cells(shots, audit$grid)
  observed <- assigned |>
    summarise(
      makes = sum(SHOT_MADE_FLAG), attempts = n(),
      .by = c(PLAYER_ID, cell_id)
    ) |>
    arrange(PLAYER_ID, cell_id)
  lattice <- audit$metadata$registry |>
    crossing(select(audit$grid, cell_id, x_ft, y_ft)) |>
    left_join(observed, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      makes = coalesce(as.integer(makes), 0L),
      attempts = coalesce(as.integer(attempts), 0L),
      player_factor = factor(PLAYER_ID, levels = audit$player_ids),
      player_index = as.integer(player_factor)
    ) |>
    arrange(PLAYER_ID, cell_id) |>
    mutate(predictor_index = row_number())
  fold_counts <- assigned |>
    summarise(shots = n(), makes = sum(SHOT_MADE_FLAG), .by = fold) |>
    arrange(fold)
  record_check(
    "input", "production_lattice_dimensions",
    nrow(lattice) == EXPECTED_LATTICE_ROWS &&
      n_distinct(lattice$PLAYER_ID) == EXPECTED_PLAYERS &&
      all(count(lattice, PLAYER_ID)$n == GRID_CELLS),
    "318 players x 156 cells = 49,608 rows"
  )
  record_check(
    "input", "production_attempts_and_makes_preserved",
    sum(lattice$attempts) == nrow(assigned) &&
      sum(lattice$makes) == sum(assigned$SHOT_MADE_FLAG),
    paste(sum(lattice$attempts), "attempts and", sum(lattice$makes), "makes")
  )
  record_check(
    "input", "production_observed_cell_count",
    sum(lattice$attempts > 0L) == EXPECTED_OBSERVED_PLAYER_CELLS,
    paste(sum(lattice$attempts > 0L), "observed player-cells")
  )
  validate_graph(audit$graph)
  list(
    complete = TRUE,
    specification_id = SPECIFICATION_ID,
    season = season,
    selection_commit = FINAL_RESULT_COMMIT,
    split_sha256 = EXPECTED_SPLIT_SHA256,
    player_source_sha256 = EXPECTED_PLAYER_SOURCE_SHA256,
    authorized_folds = AUTHORIZED_FOLDS,
    player_count = EXPECTED_PLAYERS,
    shot_count = nrow(assigned),
    game_count = n_distinct(assigned$GAME_ID),
    observed_player_cells = sum(lattice$attempts > 0L),
    lattice_rows = nrow(lattice),
    fold_counts = fold_counts,
    player_ids = audit$player_ids,
    grid = audit$grid,
    graph = audit$graph,
    lattice = lattice
  )
}

prepare_inputs <- function(audit) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(config_path) || file.exists(input_path)) {
    stop("Prepared production input already exists; verify it instead of replacing it",
         call. = FALSE)
  }
  configuration <- production_configuration()
  shots <- read_all_authorized_outcomes(audit)
  input <- build_production_input(audit, shots)
  write_new_atomic_rds(configuration, config_path)
  write_new_atomic_rds(input, input_path)
  hashes <- tibble(
    configuration_sha256 = sha256_file(config_path),
    input_sha256 = sha256_file(input_path),
    players = input$player_count,
    shots = input$shot_count,
    games = input$game_count,
    observed_player_cells = input$observed_player_cells,
    lattice_rows = input$lattice_rows,
    model_fit_started = FALSE
  )
  print(hashes, width = Inf)
  invisible(hashes)
}

verify_prepared_inputs <- function() {
  record_check(
    "prepared", "expected_hashes_frozen",
    is_sha256(EXPECTED_PRODUCTION_INPUT_SHA256) &&
      is_sha256(EXPECTED_PRODUCTION_CONFIG_SHA256),
    "production input and configuration hashes are committed"
  )
  record_check(
    "prepared", "prepared_files_exist",
    file.exists(input_path) && file.exists(config_path),
    "ignored production input and configuration artifacts exist"
  )
  input_hash <- sha256_file(input_path)
  config_hash <- sha256_file(config_path)
  record_check(
    "prepared", "prepared_hashes_match",
    identical(input_hash, EXPECTED_PRODUCTION_INPUT_SHA256) &&
      identical(config_hash, EXPECTED_PRODUCTION_CONFIG_SHA256),
    paste("input", input_hash, "configuration", config_hash)
  )
  input <- readRDS(input_path)
  configuration <- readRDS(config_path)
  record_check(
    "prepared", "configuration_contents_match_code",
    identical(configuration, production_configuration()),
    "serialized configuration exactly matches committed construction"
  )
  record_check(
    "prepared", "input_header_and_dimensions",
    isTRUE(input$complete) &&
      identical(input$specification_id, SPECIFICATION_ID) &&
      identical(input$authorized_folds, AUTHORIZED_FOLDS) &&
      identical(input$player_count, EXPECTED_PLAYERS) &&
      identical(input$shot_count, EXPECTED_METADATA_SHOTS) &&
      identical(input$game_count, EXPECTED_GAMES) &&
      identical(input$observed_player_cells, EXPECTED_OBSERVED_PLAYER_CELLS) &&
      identical(input$lattice_rows, EXPECTED_LATTICE_ROWS) &&
      nrow(input$lattice) == EXPECTED_LATTICE_ROWS,
    "prepared input is the frozen all-data 318-player lattice"
  )
  list(input = input, configuration = configuration)
}

minimum_surface_rmse <- function(centered_surface, cells_per_player, n_players) {
  surface_matrix <- matrix(
    centered_surface, nrow = cells_per_player, ncol = n_players
  )
  distances <- as.matrix(dist(t(surface_matrix))) / sqrt(cells_per_player)
  distances[lower.tri(distances, diag = TRUE)] <- NA_real_
  min(distances, na.rm = TRUE)
}

extract_selected_predictors <- function(samples, expected_indices) {
  labels <- rownames(samples[[1]]$latent)
  if (is.null(labels)) {
    stop("R-INLA posterior sample did not label selected predictors", call. = FALSE)
  }
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  if (anyNA(parsed) || !setequal(parsed, expected_indices)) {
    stop("Posterior predictor selection does not match the full lattice",
         call. = FALSE)
  }
  matrix_values <- vapply(
    samples,
    function(sample) as.numeric(sample$latent),
    numeric(length(expected_indices))
  )
  matrix_values[match(expected_indices, parsed), , drop = FALSE]
}

row_probability_summaries <- function(linear_predictor_draws, chunk_size = 500L) {
  rows <- nrow(linear_predictor_draws)
  result <- matrix(NA_real_, nrow = rows, ncol = 5L)
  colnames(result) <- c("mean", "sd", "lower", "median", "upper")
  starts <- seq.int(1L, rows, by = chunk_size)
  for (start in starts) {
    index <- start:min(start + chunk_size - 1L, rows)
    probabilities <- plogis(linear_predictor_draws[index, , drop = FALSE])
    result[index, "mean"] <- rowMeans(probabilities)
    result[index, "sd"] <- apply(probabilities, 1L, stats::sd)
    quantiles <- t(apply(
      probabilities, 1L, stats::quantile,
      probs = c(0.05, 0.5, 0.95), names = FALSE
    ))
    result[index, c("lower", "median", "upper")] <- quantiles
  }
  result
}

simulate_player_totals <- function(draw_probabilities, attempts) {
  simulated <- matrix(
    rbinom(
      length(draw_probabilities),
      size = rep(as.integer(attempts), times = ncol(draw_probabilities)),
      prob = as.vector(draw_probabilities)
    ),
    nrow = nrow(draw_probabilities), ncol = ncol(draw_probabilities)
  )
  colSums(simulated)
}

production_worker <- function(prepared) {
  lattice <- prepared$input$lattice |>
    mutate(
      y = if_else(attempts > 0L, makes, NA_integer_),
      trials = if_else(attempts > 0L, attempts, 1L)
    )
  graph <- INLA::inla.read.graph(prepared$input$graph)
  n_players <- length(prepared$input$player_ids)
  car_formula <- y ~ 0 + player_factor +
    f(
      cell_id,
      model = "besagproper2",
      graph = graph,
      replicate = player_index,
      nrep = n_players,
      constr = FALSE,
      diagonal = 0,
      hyper = list(
        prec = list(
          prior = "pc.prec", param = c(1, 0.01),
          initial = 0, fixed = FALSE
        ),
        lambda = list(
          prior = "logitbeta", param = c(1, 1),
          initial = 0, fixed = FALSE
        )
      )
    )
  record_check(
    "model", "formula_matches_frozen_configuration",
    identical(paste(deparse(car_formula), collapse = " "), formula_text()),
    formula_text()
  )

  publish_stage(1L, "fitting", "joint all-data CAR fit started")
  fit_started <- proc.time()[["elapsed"]]
  captured_fit <- capture_conditions(INLA::inla(
    car_formula,
    family = "binomial",
    Ntrials = lattice$trials,
    data = lattice,
    control.fixed = list(
      mean = 0,
      prec = 0.001,
      expand.factor.strategy = "model.matrix"
    ),
    control.predictor = list(compute = TRUE, link = 1),
    control.compute = list(
      config = TRUE,
      dic = FALSE,
      waic = FALSE,
      cpo = FALSE,
      return.marginals.predictor = TRUE
    ),
    control.inla = list(
      strategy = "simplified.laplace",
      int.strategy = "auto"
    ),
    num.threads = MODEL_THREADS,
    safe = FALSE,
    verbose = FALSE
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  fit <- captured_fit$value
  mode_status <- fit$mode$mode.status
  record_check(
    "fit", "fit_ok", isTRUE(fit$ok), paste("fit$ok =", fit$ok)
  )
  record_check(
    "fit", "no_fit_warning_or_retry",
    length(captured_fit$warnings) == 0L && identical(as.numeric(mode_status), 0),
    paste(length(captured_fit$warnings), "warnings; mode status", mode_status)
  )
  record_check(
    "fit", "fixed_effect_count", nrow(fit$summary.fixed) == EXPECTED_PLAYERS,
    paste(nrow(fit$summary.fixed), "player intercepts")
  )
  record_check(
    "fit", "replicated_spatial_count",
    nrow(fit$summary.random$cell_id) == EXPECTED_LATTICE_ROWS,
    paste(nrow(fit$summary.random$cell_id), "player-cell spatial effects")
  )
  record_check(
    "fit", "hyperparameter_count", nrow(fit$summary.hyperpar) == 2L,
    paste(nrow(fit$summary.hyperpar), "shared CAR hyperparameters")
  )
  record_check(
    "fit", "predictor_count",
    nrow(fit$summary.linear.predictor) == EXPECTED_LATTICE_ROWS,
    paste(nrow(fit$summary.linear.predictor), "full-lattice predictors")
  )
  posterior_values <- c(
    fit$summary.fixed$mean,
    fit$summary.random$cell_id$mean,
    fit$summary.hyperpar$mean,
    fit$summary.linear.predictor$mean,
    fit$summary.fitted.values$mean
  )
  record_check(
    "fit", "finite_posterior_summaries", all(is.finite(posterior_values)),
    paste(length(posterior_values), "finite posterior summary values")
  )
  record_check(
    "fit", "posterior_configuration_preserved", !is.null(fit$misc$configs),
    "joint posterior configuration is retained for relocation uncertainty"
  )

  publish_stage(2L, "predicting", "full production surface construction started")
  prediction_started <- proc.time()[["elapsed"]]
  surface <- lattice |>
    transmute(
      PLAYER_ID, PLAYER_NAME, cell_id, x_ft, y_ft, attempts, makes,
      probability = fit$summary.fitted.values$mean
    ) |>
    arrange(PLAYER_ID, cell_id)
  record_check(
    "prediction", "surface_complete_unique",
    nrow(surface) == EXPECTED_LATTICE_ROWS &&
      n_distinct(surface$PLAYER_ID) == EXPECTED_PLAYERS &&
      !anyDuplicated(surface[c("PLAYER_ID", "cell_id")]) &&
      all(count(surface, PLAYER_ID)$n == GRID_CELLS),
    "49,608 unique player-cell predictions"
  )
  record_check(
    "prediction", "point_probabilities_valid",
    all(is.finite(surface$probability)) &&
      all(surface$probability >= 0 & surface$probability <= 1),
    paste("range", paste(range(surface$probability), collapse = " to "))
  )
  centered_links <- fit$summary.linear.predictor$mean -
    ave(fit$summary.linear.predictor$mean, lattice$PLAYER_ID, FUN = mean)
  minimum_rmse <- minimum_surface_rmse(
    centered_links, GRID_CELLS, EXPECTED_PLAYERS
  )
  record_check(
    "prediction", "distinct_player_surfaces",
    is.finite(minimum_rmse) && minimum_rmse > SURFACE_TOLERANCE,
    paste("minimum centered-surface RMSE", format(minimum_rmse, digits = 10))
  )
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started

  publish_stage(3L, "uncertainty", "4,000 joint posterior draws started")
  uncertainty_started <- proc.time()[["elapsed"]]
  all_indices <- lattice$predictor_index
  set_frozen_rng(CAR_DRAW_SEED)
  captured_draws <- capture_conditions(INLA::inla.posterior.sample(
    n = POSTERIOR_DRAWS,
    result = fit,
    selection = list(Predictor = all_indices),
    seed = CAR_DRAW_SEED,
    num.threads = MODEL_THREADS,
    parallel.configs = FALSE,
    add.names = FALSE
  ))
  linear_draws <- extract_selected_predictors(captured_draws$value, all_indices)
  captured_draws$value <- NULL
  gc()
  record_check(
    "uncertainty", "joint_draw_dimensions",
    nrow(linear_draws) == EXPECTED_LATTICE_ROWS &&
      ncol(linear_draws) == POSTERIOR_DRAWS && all(is.finite(linear_draws)),
    "49,608 predictors by 4,000 finite joint draws"
  )
  probability_summaries <- row_probability_summaries(linear_draws)
  surface <- surface |>
    mutate(
      draw_mean_probability = probability_summaries[, "mean"],
      probability_sd = probability_summaries[, "sd"],
      probability_lower_90 = probability_summaries[, "lower"],
      probability_median = probability_summaries[, "median"],
      probability_upper_90 = probability_summaries[, "upper"]
    )
  record_check(
    "uncertainty", "cell_probability_intervals_valid",
    all(is.finite(as.matrix(surface[c(
      "draw_mean_probability", "probability_sd", "probability_lower_90",
      "probability_median", "probability_upper_90"
    )]))) &&
      all(surface$probability_sd >= 0) &&
      all(surface$probability_lower_90 >= 0) &&
      all(surface$probability_lower_90 <= surface$probability_median) &&
      all(surface$probability_median <= surface$probability_upper_90) &&
      all(surface$probability_upper_90 <= 1),
    "all 49,608 posterior probability summaries are finite and ordered"
  )

  set_frozen_rng(PREDICTIVE_SEED)
  player_summaries <- lapply(prepared$input$player_ids, function(player_id) {
    rows <- which(lattice$PLAYER_ID == player_id & lattice$attempts > 0L)
    probabilities <- plogis(linear_draws[rows, , drop = FALSE])
    expected_totals <- colSums(probabilities * lattice$attempts[rows])
    predictive_totals <- simulate_player_totals(probabilities, lattice$attempts[rows])
    tibble(
      PLAYER_ID = player_id,
      PLAYER_NAME = lattice$PLAYER_NAME[rows[[1]]],
      attempts = sum(lattice$attempts[rows]),
      observed_makes = sum(lattice$makes[rows]),
      posterior_expected_makes = mean(expected_totals),
      posterior_predictive_mean_makes = mean(predictive_totals),
      interval_lower_90 = as.numeric(
        quantile(predictive_totals, 0.05, names = FALSE)
      ),
      interval_upper_90 = as.numeric(
        quantile(predictive_totals, 0.95, names = FALSE)
      )
    ) |>
      mutate(interval_width_90 = interval_upper_90 - interval_lower_90)
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID)
  record_check(
    "uncertainty", "player_uncertainty_complete_unique",
    nrow(player_summaries) == EXPECTED_PLAYERS &&
      !anyDuplicated(player_summaries$PLAYER_ID) &&
      identical(player_summaries$PLAYER_ID, prepared$input$player_ids),
    "one uncertainty summary for each frozen player"
  )
  record_check(
    "uncertainty", "player_intervals_valid",
    all(is.finite(as.matrix(player_summaries[c(
      "posterior_expected_makes", "posterior_predictive_mean_makes",
      "interval_lower_90", "interval_upper_90", "interval_width_90"
    )]))) &&
      all(player_summaries$interval_lower_90 >= 0) &&
      all(player_summaries$interval_lower_90 <=
            player_summaries$interval_upper_90) &&
      all(player_summaries$interval_upper_90 <= player_summaries$attempts),
    "all 318 player-total 90% intervals are finite, ordered, and feasible"
  )
  uncertainty_elapsed <- proc.time()[["elapsed"]] - uncertainty_started
  rm(linear_draws, probability_summaries)
  gc()

  hyperparameters <- fit$summary.hyperpar |>
    as_tibble(rownames = "hyperparameter") |>
    mutate(season = season, specification_id = SPECIFICATION_ID, .before = 1)
  record_check(
    "fit", "hyperparameter_summary_finite",
    nrow(hyperparameters) == 2L &&
      all(vapply(hyperparameters, function(column) {
        !is.numeric(column) || all(is.finite(column))
      }, logical(1))),
    "two finite shared CAR hyperparameter summaries"
  )
  checks <- bind_rows(check_records)
  record_check(
    "publication", "all_checks_pass_before_publication",
    all(checks$passed), paste(nrow(checks), "checks passed before publication")
  )
  checks <- bind_rows(check_records)

  publish_stage(4L, "serializing", "verified fit and surfaces are being published")
  serialization_started <- proc.time()[["elapsed"]]
  write_new_atomic_rds(fit, fit_path, compress = FALSE)
  write_new_atomic_parquet(surface, surface_path)
  write_new_atomic_parquet(player_summaries, uncertainty_path)
  write_new_atomic_parquet(hyperparameters, hyperparameter_path)
  fit_sha256 <- sha256_file(fit_path)
  surface_sha256 <- sha256_file(surface_path)
  uncertainty_sha256 <- sha256_file(uncertainty_path)
  hyperparameter_sha256 <- sha256_file(hyperparameter_path)
  metrics <- list(
    fit_elapsed_sec = fit_elapsed,
    prediction_elapsed_sec = prediction_elapsed,
    uncertainty_elapsed_sec = uncertainty_elapsed,
    model_object_bytes = as.numeric(object.size(fit)),
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    fit_sha256 = fit_sha256,
    fit_md5 = unname(tools::md5sum(fit_path)),
    minimum_probability = min(surface$probability),
    maximum_probability = max(surface$probability),
    minimum_centered_surface_rmse = minimum_rmse,
    fit_warning_count = length(captured_fit$warnings),
    fit_warnings = captured_fit$warnings,
    fit_message_count = length(captured_fit$messages),
    fit_messages = captured_fit$messages,
    posterior_warning_count = length(captured_draws$warnings),
    posterior_warnings = captured_draws$warnings,
    posterior_message_count = length(captured_draws$messages),
    posterior_messages = captured_draws$messages,
    mode_status = as.numeric(mode_status)
  )
  model_checkpoint <- list(
    complete = TRUE,
    season = season,
    specification_id = SPECIFICATION_ID,
    input_sha256 = EXPECTED_PRODUCTION_INPUT_SHA256,
    configuration_sha256 = EXPECTED_PRODUCTION_CONFIG_SHA256,
    player_count = EXPECTED_PLAYERS,
    shot_count = EXPECTED_METADATA_SHOTS,
    observed_player_cells = EXPECTED_OBSERVED_PLAYER_CELLS,
    lattice_rows = EXPECTED_LATTICE_ROWS,
    posterior_draws = POSTERIOR_DRAWS,
    fit_sha256 = fit_sha256,
    surface_sha256 = surface_sha256,
    uncertainty_sha256 = uncertainty_sha256,
    hyperparameter_sha256 = hyperparameter_sha256,
    metrics = metrics,
    checks = checks
  )
  write_new_atomic_rds(model_checkpoint, model_checkpoint_path)
  serialization_elapsed <- proc.time()[["elapsed"]] - serialization_started
  rm(fit, surface)
  gc()
  list(
    metrics = metrics,
    serialization_elapsed_sec = serialization_elapsed,
    checks = checks,
    fit_sha256 = fit_sha256,
    surface_sha256 = surface_sha256,
    uncertainty_sha256 = uncertainty_sha256,
    hyperparameter_sha256 = hyperparameter_sha256,
    model_checkpoint_sha256 = sha256_file(model_checkpoint_path)
  )
}

parse_cpu_seconds <- function(values) {
  vapply(values, function(value) {
    pieces <- strsplit(trimws(value), "-", fixed = TRUE)[[1]]
    days <- if (length(pieces) == 2L) as.numeric(pieces[[1]]) else 0
    clock <- as.numeric(strsplit(tail(pieces, 1L), ":", fixed = TRUE)[[1]])
    seconds <- if (length(clock) == 3L) {
      clock[[1]] * 3600 + clock[[2]] * 60 + clock[[3]]
    } else if (length(clock) == 2L) {
      clock[[1]] * 60 + clock[[2]]
    } else {
      clock[[1]]
    }
    days * 86400 + seconds
  }, numeric(1))
}

process_tree_snapshot <- function(root_pid) {
  output <- system2("ps", c("-axo", "pid=,ppid=,rss=,time="), stdout = TRUE)
  table <- read.table(
    text = output, header = FALSE, col.names = c("pid", "ppid", "rss_kb", "cpu"),
    colClasses = c("integer", "integer", "numeric", "character")
  )
  descendants <- as.integer(root_pid)
  repeat {
    children <- table$pid[table$ppid %in% descendants]
    expanded <- unique(c(descendants, children))
    if (length(expanded) == length(descendants)) break
    descendants <- expanded
  }
  selected <- filter(table, pid %in% descendants)
  list(
    pids = selected$pid,
    rss_mb = sum(selected$rss_kb) / 1024,
    cpu_seconds = setNames(parse_cpu_seconds(selected$cpu), selected$pid)
  )
}

free_disk_gib <- function() {
  lines <- system2("df", c("-Pk", "."), stdout = TRUE)
  fields <- strsplit(trimws(lines[[length(lines)]]), "[[:space:]]+")[[1]]
  as.numeric(fields[[4]]) / 1024^2
}

acquire_lock <- function() {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    owner_path <- file.path(lock_path, "owner.rds")
    owner <- tryCatch(readRDS(owner_path), error = function(condition) NULL)
    pids <- if (is.null(owner)) integer() else {
      unique(as.integer(c(owner$runner_pid, owner$model_pid)))
    }
    active <- vapply(pids, function(pid) {
      length(system2("ps", c("-p", pid, "-o", "pid="), stdout = TRUE)) > 0L
    }, logical(1))
    if (any(active)) {
      stop("DUPLICATE RUN SAFEGUARD: production CAR is already active",
           call. = FALSE)
    }
    stop("A stale production lock exists and was preserved for recovery",
         call. = FALSE)
  }
  owner <- list(
    runner_pid = Sys.getpid(),
    model_pid = NA_integer_,
    season = season,
    mode = mode,
    started_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  write_new_atomic_rds(owner, file.path(lock_path, "owner.rds"))
  owner
}

update_lock <- function(owner, model_pid) {
  owner$model_pid <- as.integer(model_pid)
  write_replace_atomic_rds(owner, file.path(lock_path, "owner.rds"))
  owner
}

verify_git_prefit <- function() {
  head <- git_value(c("rev-parse", "HEAD"))[[1]]
  origin <- git_value(
    c("rev-parse", "origin/codex/spatial-shot-selection")
  )[[1]]
  record_check(
    "reproducibility", "prefit_commit_pushed",
    identical(head, origin) && system2(
      "git", c("merge-base", "--is-ancestor", FINAL_RESULT_COMMIT, head)
    ) == 0L,
    paste("HEAD and origin", head)
  )
  tracked_clean <- system2("git", c("diff", "--quiet")) == 0L &&
    system2("git", c("diff", "--cached", "--quiet")) == 0L
  record_check(
    "reproducibility", "tracked_worktree_clean", tracked_clean,
    "no tracked change exists outside the committed pre-fit specification"
  )
  head
}

verify_completion <- function() {
  if (!file.exists(completion_path)) return(NULL)
  completion <- readRDS(completion_path)
  paths <- c(
    fit = fit_path,
    surface = surface_path,
    uncertainty = uncertainty_path,
    hyperparameter = hyperparameter_path,
    model_checkpoint = model_checkpoint_path
  )
  observed <- vapply(paths, sha256_file, character(1))
  expected <- c(
    fit = completion$fit_sha256,
    surface = completion$surface_sha256,
    uncertainty = completion$uncertainty_sha256,
    hyperparameter = completion$hyperparameter_sha256,
    model_checkpoint = completion$model_checkpoint_sha256
  )
  valid <- isTRUE(completion$complete) &&
    identical(completion$specification_id, SPECIFICATION_ID) &&
    identical(completion$input_sha256, EXPECTED_PRODUCTION_INPUT_SHA256) &&
    identical(completion$configuration_sha256,
              EXPECTED_PRODUCTION_CONFIG_SHA256) &&
    identical(observed, expected) &&
    completion$player_count == EXPECTED_PLAYERS &&
    completion$lattice_rows == EXPECTED_LATTICE_ROWS &&
    all(completion$checks$passed)
  if (!valid) {
    stop("Existing production completion is invalid and was preserved",
         call. = FALSE)
  }
  completion
}

write_tracked_results <- function(completion) {
  expected_files <- completion$configuration$tracked_outputs
  existing <- if (dir.exists(result_dir)) list.files(result_dir) else character()
  if (length(existing) > 0L) {
    if (!setequal(existing, expected_files)) {
      stop("Incomplete tracked production results exist and were preserved",
           call. = FALSE)
    }
    return(invisible(existing))
  }
  dir.create(dirname(result_dir), recursive = TRUE, showWarnings = FALSE)
  partial_pattern <- paste0("^", basename(result_dir), "\\.partial-")
  existing_partials <- list.files(dirname(result_dir), pattern = partial_pattern)
  if (length(existing_partials) > 0L) {
    stop("Partial tracked production directory exists and was preserved",
         call. = FALSE)
  }
  temporary_result_dir <- paste0(result_dir, ".partial-", Sys.getpid())
  if (!dir.create(temporary_result_dir, recursive = FALSE, showWarnings = FALSE)) {
    stop("Could not create atomic production-result staging directory",
         call. = FALSE)
  }
  metrics <- completion$metrics
  manifest <- tibble(
    season = season,
    model = "Bayesian CAR",
    specification_id = SPECIFICATION_ID,
    selection_result_commit = FINAL_RESULT_COMMIT,
    prefit_commit = completion$prefit_commit,
    production_only_no_new_evaluation = TRUE,
    authorized_folds = paste(AUTHORIZED_FOLDS, collapse = ","),
    player_count = completion$player_count,
    shot_count = completion$shot_count,
    game_count = completion$game_count,
    observed_player_cells = completion$observed_player_cells,
    cells_per_player = GRID_CELLS,
    lattice_rows = completion$lattice_rows,
    posterior_draws = POSTERIOR_DRAWS,
    input_sha256 = completion$input_sha256,
    configuration_sha256 = completion$configuration_sha256,
    fit_sha256 = completion$fit_sha256,
    surface_sha256 = completion$surface_sha256,
    uncertainty_sha256 = completion$uncertainty_sha256,
    hyperparameter_sha256 = completion$hyperparameter_sha256,
    model_checkpoint_sha256 = completion$model_checkpoint_sha256,
    completion_checkpoint_sha256 = sha256_file(completion_path),
    setup_elapsed_sec = completion$setup_elapsed_sec,
    fit_elapsed_sec = metrics$fit_elapsed_sec,
    prediction_elapsed_sec = metrics$prediction_elapsed_sec,
    uncertainty_elapsed_sec = metrics$uncertainty_elapsed_sec,
    serialization_elapsed_sec = completion$serialization_elapsed_sec,
    total_wall_elapsed_sec = completion$total_wall_elapsed_sec,
    approximate_process_tree_cpu_sec = completion$approximate_process_tree_cpu_sec,
    approximate_peak_process_tree_rss_mb = completion$approximate_peak_process_tree_rss_mb,
    free_disk_gib_start = completion$free_disk_gib_start,
    free_disk_gib_finish = completion$free_disk_gib_finish,
    model_object_bytes = metrics$model_object_bytes,
    serialized_model_bytes = metrics$serialized_model_bytes,
    fit_warning_count = metrics$fit_warning_count,
    posterior_warning_count = metrics$posterior_warning_count,
    verification_passed = all(completion$checks$passed),
    r_version = EXPECTED_R_VERSION,
    inla_version = EXPECTED_VERSIONS[["INLA"]],
    matrix_version = EXPECTED_VERSIONS[["Matrix"]],
    fmesher_version = EXPECTED_VERSIONS[["fmesher"]],
    sn_version = EXPECTED_VERSIONS[["sn"]],
    arrow_version = EXPECTED_VERSIONS[["arrow"]],
    dplyr_version = EXPECTED_VERSIONS[["dplyr"]],
    tidyr_version = EXPECTED_VERSIONS[["tidyr"]]
  )
  surface_qa <- tibble(
    season = season,
    player_count = completion$player_count,
    cells_per_player = GRID_CELLS,
    surface_rows = completion$lattice_rows,
    unique_player_cells = completion$lattice_rows,
    minimum_probability = metrics$minimum_probability,
    maximum_probability = metrics$maximum_probability,
    minimum_centered_surface_rmse = metrics$minimum_centered_surface_rmse,
    distinct_player_surfaces = metrics$minimum_centered_surface_rmse >
      SURFACE_TOLERANCE,
    all_probability_intervals_valid = TRUE,
    all_surface_rows_complete_unique = TRUE
  )
  notices <- tibble(
    season = season,
    severity = "compatibility_warning",
    source = "arrow package startup",
    notice = paste(
      "arrow was built under R 4.6.1 while the frozen runtime is R 4.6.0;",
      "all production Arrow operations and checks completed successfully"
    ),
    package_build = packageDescription("arrow")$Built,
    fit_warning_count = metrics$fit_warning_count,
    posterior_warning_count = metrics$posterior_warning_count
  )
  write_new_atomic_parquet(
    manifest, file.path(temporary_result_dir, expected_files[[1]])
  )
  write_new_atomic_parquet(
    surface_qa, file.path(temporary_result_dir, expected_files[[2]])
  )
  copy_new_atomic_file(
    uncertainty_path, file.path(temporary_result_dir, expected_files[[3]])
  )
  copy_new_atomic_file(
    hyperparameter_path, file.path(temporary_result_dir, expected_files[[4]])
  )
  write_new_atomic_parquet(
    completion$checks, file.path(temporary_result_dir, expected_files[[5]])
  )
  write_new_atomic_parquet(
    notices, file.path(temporary_result_dir, expected_files[[6]])
  )
  if (!setequal(list.files(temporary_result_dir), expected_files) ||
      !file.rename(temporary_result_dir, result_dir)) {
    stop("Could not atomically publish the complete tracked result directory",
         call. = FALSE)
  }
  invisible(expected_files)
}

run_production <- function(audit) {
  if (!is_sha256(EXPECTED_PRODUCTION_INPUT_SHA256) ||
      !is_sha256(EXPECTED_PRODUCTION_CONFIG_SHA256)) {
    stop("Production hashes are not frozen; run prepare and commit them first",
         call. = FALSE)
  }
  completed <- verify_completion()
  if (!is.null(completed)) {
    write_tracked_results(completed)
    message("Reused verified atomic production completion; no model was refit")
    print(read_parquet(file.path(result_dir, "production_manifest.parquet")),
          width = Inf)
    return(invisible(completed))
  }
  conflicting <- c(fit_path, surface_path, uncertainty_path, hyperparameter_path,
                   model_checkpoint_path)
  if (any(file.exists(conflicting))) {
    stop("Incomplete production artifacts exist and were preserved; do not restart",
         call. = FALSE)
  }
  if (dir.exists(result_dir) && length(list.files(result_dir)) > 0L) {
    stop("Tracked production output exists without completion; preserved",
         call. = FALSE)
  }
  prefit_commit <- verify_git_prefit()
  prepared <- verify_prepared_inputs()
  disk_start <- free_disk_gib()
  setup_elapsed <- proc.time()[["elapsed"]] - SCRIPT_STARTED
  record_check(
    "resources", "sufficient_free_disk", is.finite(disk_start) && disk_start > 15,
    paste(round(disk_start, 3), "GiB free before fit")
  )
  owner <- acquire_lock()
  success <- FALSE
  on.exit({
    if (success && dir.exists(lock_path)) unlink(lock_path, recursive = TRUE)
  }, add = TRUE)
  wall_started <- proc.time()[["elapsed"]]
  job <- parallel::mcparallel(
    production_worker(prepared), detached = FALSE, silent = FALSE
  )
  owner <- update_lock(owner, job$pid)
  write_new_atomic_rds(
    list(
      runner_pid = Sys.getpid(), model_pid = job$pid,
      prefit_commit = prefit_commit, input_sha256 = EXPECTED_PRODUCTION_INPUT_SHA256,
      configuration_sha256 = EXPECTED_PRODUCTION_CONFIG_SHA256,
      started_at_utc = owner$started_at_utc
    ),
    pid_path
  )
  peak_rss_mb <- 0
  cpu_by_pid <- numeric()
  samples <- list()
  next_report <- 60
  repeat {
    elapsed <- proc.time()[["elapsed"]] - wall_started
    snapshot <- process_tree_snapshot(job$pid)
    peak_rss_mb <- max(peak_rss_mb, snapshot$rss_mb)
    if (length(snapshot$cpu_seconds) > 0L) {
      for (pid in names(snapshot$cpu_seconds)) {
        previous <- unname(cpu_by_pid[pid])
        if (length(previous) == 0L || is.na(previous)) previous <- 0
        cpu_by_pid[pid] <- max(previous, snapshot$cpu_seconds[[pid]])
      }
    }
    samples[[length(samples) + 1L]] <- tibble(
      elapsed_sec = elapsed,
      sampled_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      visible_processes = length(snapshot$pids),
      process_tree_rss_mb = snapshot$rss_mb,
      accumulated_sampled_cpu_sec = sum(cpu_by_pid, na.rm = TRUE)
    )
    if (length(samples) %% 5L == 0L) {
      write_replace_atomic_rds(bind_rows(samples), resource_path)
    }
    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      value <- collected[[1]]
      if (inherits(value, "try-error")) {
        write_replace_atomic_rds(bind_rows(samples), resource_path)
        stop("Production child failed; evidence and lock preserved: ", value,
             call. = FALSE)
      }
      total_elapsed <- proc.time()[["elapsed"]] - SCRIPT_STARTED
      disk_finish <- free_disk_gib()
      write_replace_atomic_rds(bind_rows(samples), resource_path)
      completion <- list(
        complete = TRUE,
        season = season,
        specification_id = SPECIFICATION_ID,
        selection_result_commit = FINAL_RESULT_COMMIT,
        prefit_commit = prefit_commit,
        input_sha256 = EXPECTED_PRODUCTION_INPUT_SHA256,
        configuration_sha256 = EXPECTED_PRODUCTION_CONFIG_SHA256,
        player_count = EXPECTED_PLAYERS,
        shot_count = prepared$input$shot_count,
        game_count = prepared$input$game_count,
        observed_player_cells = prepared$input$observed_player_cells,
        lattice_rows = prepared$input$lattice_rows,
        fit_sha256 = value$fit_sha256,
        surface_sha256 = value$surface_sha256,
        uncertainty_sha256 = value$uncertainty_sha256,
        hyperparameter_sha256 = value$hyperparameter_sha256,
        model_checkpoint_sha256 = value$model_checkpoint_sha256,
        setup_elapsed_sec = setup_elapsed,
        serialization_elapsed_sec = value$serialization_elapsed_sec,
        total_wall_elapsed_sec = total_elapsed,
        approximate_process_tree_cpu_sec = sum(cpu_by_pid, na.rm = TRUE),
        approximate_peak_process_tree_rss_mb = peak_rss_mb,
        free_disk_gib_start = disk_start,
        free_disk_gib_finish = disk_finish,
        resource_sample_count = nrow(bind_rows(samples)),
        metrics = value$metrics,
        checks = value$checks,
        configuration = prepared$configuration,
        completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
      )
      write_new_atomic_rds(completion, completion_path)
      write_tracked_results(completion)
      publish_stage(5L, "complete", "atomic completion and QA outputs published")
      success <- TRUE
      print(read_parquet(file.path(result_dir, "production_manifest.parquet")),
            width = Inf)
      return(invisible(completion))
    }
    if (elapsed >= next_report) {
      message(
        "PRODUCTION elapsed_sec=", round(elapsed, 1),
        " sampled_cpu_sec=", round(sum(cpu_by_pid, na.rm = TRUE), 1),
        " peak_rss_mb=", round(peak_rss_mb, 1)
      )
      next_report <- next_report + 60
    }
    Sys.sleep(1)
  }
}

audit <- audit_state()

if (mode == "audit") {
  prepared_verified <- FALSE
  if (file.exists(input_path) && file.exists(config_path) &&
      is_sha256(EXPECTED_PRODUCTION_INPUT_SHA256) &&
      is_sha256(EXPECTED_PRODUCTION_CONFIG_SHA256)) {
    verify_prepared_inputs()
    prepared_verified <- TRUE
  }
  prepared_hashes <- if (file.exists(input_path) && file.exists(config_path)) {
    c(input = sha256_file(input_path), configuration = sha256_file(config_path))
  } else {
    c(input = NA_character_, configuration = NA_character_)
  }
  print(tibble(
    season = season,
    mode = mode,
    selected_model = "Bayesian CAR",
    players = EXPECTED_PLAYERS,
    games = EXPECTED_GAMES,
    metadata_shots = nrow(audit$metadata$eligible),
    observed_player_cells = EXPECTED_OBSERVED_PLAYER_CELLS,
    cells_per_player = GRID_CELLS,
    lattice_rows = EXPECTED_LATTICE_ROWS,
    prepared_input_sha256 = prepared_hashes[["input"]],
    prepared_configuration_sha256 = prepared_hashes[["configuration"]],
    prepared_artifacts_verified = prepared_verified,
    all_checks_passed = all(bind_rows(check_records)$passed),
    model_fit_started = FALSE,
    further_model_evaluation = FALSE
  ), width = Inf)
  quit(save = "no", status = 0L)
}

if (mode == "prepare") {
  prepare_inputs(audit)
  quit(save = "no", status = 0L)
}

run_production(audit)
