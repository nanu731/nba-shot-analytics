# Feasibility-only timing pilot for player-specific spatial shot surfaces.
#
# This file is deliberately not called by R/run_pipeline.R. It uses only folds
# 1-3, never scores predictions, and writes all data-bearing artifacts under the
# ignored data/cache directory.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: Rscript R/spatial_timing_pilot.R <season> <prepare|car|gam>",
    call. = FALSE
  )
}

season <- args[[1]]
mode <- args[[2]]

if (!grepl("^[0-9]{4}-[0-9]{2}$", season)) {
  stop("season must look like 2025-26", call. = FALSE)
}
if (!mode %in% c("prepare", "car", "gam")) {
  stop("mode must be prepare, car, or gam", call. = FALSE)
}

MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
SPLIT_SEED <- 20260830L
SAMPLE_SEED <- 20260831L
FIT_FOLDS <- 1:3
GRID_WIDTH <- 50
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
GAM_BASIS_SIZE <- 10L
MODEL_THREADS <- 1L

raw_path <- file.path("data", "raw", "shots", paste0("season=", season), "shots.parquet")
cache_dir <- file.path("data", "cache", "spatial_pilot", paste0("season=", season))
fold_path <- file.path(cache_dir, "game_folds.parquet")
sample_path <- file.path(cache_dir, "player_sample.parquet")
cell_path <- file.path(cache_dir, "training_player_cells.parquet")

if (!file.exists(raw_path)) {
  stop("Missing raw shot data: ", raw_path, call. = FALSE)
}
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

required_columns <- c(
  "GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y",
  "SHOT_ATTEMPTED_FLAG", "SHOT_MADE_FLAG"
)

check_columns <- function(column_names) {
  missing <- setdiff(required_columns, column_names)
  if (length(missing) > 0L) {
    stop("Missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

capture_warnings <- function(expression) {
  seen <- character()
  value <- withCallingHandlers(
    expression,
    warning = function(condition) {
      seen <<- c(seen, conditionMessage(condition))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = unique(seen))
}

write_or_verify_parquet <- function(value, path, key_columns) {
  ordered <- arrange(value, across(all_of(key_columns)))
  if (file.exists(path)) {
    existing <- read_parquet(path) |>
      arrange(across(all_of(key_columns)))
    if (!identical(existing, ordered)) {
      stop("Existing artifact disagrees with the fixed specification: ", path, call. = FALSE)
    }
  } else {
    write_parquet(ordered, path)
  }
  invisible(path)
}

validate_metadata <- function(shots) {
  if (!is.character(shots$GAME_ID) || any(!grepl("^0", shots$GAME_ID))) {
    stop("GAME_ID must remain text with leading zeros", call. = FALSE)
  }
  if (anyNA(shots)) {
    stop("Required shot metadata contains missing values", call. = FALSE)
  }
  attempted <- sort(unique(shots$SHOT_ATTEMPTED_FLAG))
  if (!identical(as.integer(attempted), 1L)) {
    stop("SHOT_ATTEMPTED_FLAG contains values other than 1", call. = FALSE)
  }
  if (any(shots$LOC_X < COURT_X_MIN | shots$LOC_X > COURT_X_MAX)) {
    stop("Shot x-coordinate falls outside the declared court boundary", call. = FALSE)
  }
  if (any(shots$LOC_Y < COURT_Y_MIN)) {
    stop("Shot y-coordinate falls below the declared baseline", call. = FALSE)
  }
  invisible(shots)
}

make_grid <- function() {
  nx <- as.integer((COURT_X_MAX - COURT_X_MIN) / GRID_WIDTH)
  ny <- as.integer((COURT_Y_MAX - COURT_Y_MIN) / GRID_WIDTH)
  if (nx != 10L || ny != 9L) {
    stop("The 5-foot pilot grid must be 10 by 9", call. = FALSE)
  }

  expand_grid(x_index = seq_len(nx), y_index = seq_len(ny)) |>
    mutate(
      cell_id = (y_index - 1L) * nx + x_index,
      x_center = COURT_X_MIN + (x_index - 0.5) * GRID_WIDTH,
      y_center = COURT_Y_MIN + (y_index - 0.5) * GRID_WIDTH
    ) |>
    arrange(cell_id)
}

prepare_artifacts <- function() {
  started <- proc.time()[["elapsed"]]

  schema_names <- names(read_parquet(raw_path, as_data_frame = FALSE)$schema)
  check_columns(schema_names)

  # Do not load make/miss outcomes while creating the game split or player sample.
  metadata <- read_parquet(
    raw_path,
    col_select = all_of(setdiff(required_columns, "SHOT_MADE_FLAG"))
  ) |>
    as_tibble()
  validate_metadata(metadata)

  game_ids <- sort(unique(metadata$GAME_ID))
  set.seed(SPLIT_SEED)
  shuffled_games <- sample(game_ids, length(game_ids), replace = FALSE)
  folds <- tibble(
    GAME_ID = shuffled_games,
    fold = rep(seq_len(5L), length.out = length(shuffled_games))
  ) |>
    arrange(GAME_ID)
  if (n_distinct(folds$GAME_ID) != length(game_ids) || anyNA(folds$fold)) {
    stop("Game split failed to assign every game exactly once", call. = FALSE)
  }
  write_or_verify_parquet(folds, fold_path, "GAME_ID")

  in_play <- metadata |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    left_join(folds, by = "GAME_ID")
  if (anyNA(in_play$fold)) {
    stop("At least one in-play shot did not receive a fold", call. = FALSE)
  }

  eligible <- in_play |>
    summarise(
      PLAYER_NAME = first(PLAYER_NAME),
      season_attempts = n(),
      season_games = n_distinct(GAME_ID),
      .by = PLAYER_ID
    ) |>
    filter(season_games >= MIN_GAMES, season_attempts >= MIN_ATTEMPTS)
  if (nrow(eligible) != 318L) {
    stop("Expected 318 eligible players, found ", nrow(eligible), call. = FALSE)
  }

  training_volume <- in_play |>
    filter(fold %in% FIT_FOLDS, PLAYER_ID %in% eligible$PLAYER_ID) |>
    count(PLAYER_ID, name = "training_attempts")
  sampled_frame <- eligible |>
    inner_join(training_volume, by = "PLAYER_ID") |>
    arrange(training_attempts, PLAYER_ID) |>
    mutate(volume_group = ntile(row_number(), 4L))
  if (nrow(sampled_frame) != 318L || any(sampled_frame$training_attempts == 0L)) {
    stop("Every eligible player must have fitting attempts", call. = FALSE)
  }

  set.seed(SAMPLE_SEED)
  sampled <- sampled_frame |>
    group_by(volume_group) |>
    slice(sample.int(n(), 10L, replace = FALSE)) |>
    ungroup() |>
    arrange(volume_group, PLAYER_ID)
  sample_counts <- count(sampled, volume_group)
  if (nrow(sampled) != 40L || n_distinct(sampled$PLAYER_ID) != 40L ||
      nrow(sample_counts) != 4L || any(sample_counts$n != 10L)) {
    stop("The fallback sample must contain 10 distinct players per volume group", call. = FALSE)
  }
  write_or_verify_parquet(sampled, sample_path, c("volume_group", "PLAYER_ID"))

  # Only after the split and sample are fixed do we load outcomes, filtered to
  # fitting games and sampled players before collection.
  fitting_games <- folds$GAME_ID[folds$fold %in% FIT_FOLDS]
  fitting_shots <- open_dataset(raw_path) |>
    filter(GAME_ID %in% fitting_games, PLAYER_ID %in% sampled$PLAYER_ID) |>
    select(all_of(required_columns)) |>
    collect() |>
    as_tibble()
  if (any(!fitting_shots$GAME_ID %in% fitting_games)) {
    stop("A non-fitting game reached the pilot outcome data", call. = FALSE)
  }
  validate_metadata(select(fitting_shots, -SHOT_MADE_FLAG))
  if (anyNA(fitting_shots$SHOT_MADE_FLAG) ||
      !all(fitting_shots$SHOT_MADE_FLAG %in% c(0L, 1L))) {
    stop("SHOT_MADE_FLAG must contain only 0 or 1", call. = FALSE)
  }

  fitting_shots <- fitting_shots |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L,
        as.integer((COURT_X_MAX - COURT_X_MIN) / GRID_WIDTH)
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L,
        as.integer((COURT_Y_MAX - COURT_Y_MIN) / GRID_WIDTH)
      ),
      cell_id = (y_index - 1L) * 10L + x_index
    )
  if (any(!fitting_shots$cell_id %in% 1:90)) {
    stop("At least one fitting shot was not assigned to the 90-cell grid", call. = FALSE)
  }

  observed <- fitting_shots |>
    summarise(
      makes = sum(SHOT_MADE_FLAG),
      attempts = n(),
      .by = c(PLAYER_ID, cell_id)
    )
  grid <- make_grid()
  cells <- sampled |>
    select(PLAYER_ID, PLAYER_NAME, volume_group, training_attempts) |>
    crossing(grid) |>
    left_join(observed, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      makes = coalesce(as.integer(makes), 0L),
      attempts = coalesce(as.integer(attempts), 0L)
    ) |>
    arrange(PLAYER_ID, cell_id)
  if (nrow(cells) != 40L * 90L || sum(cells$attempts) != nrow(fitting_shots)) {
    stop("Player-cell aggregation did not preserve every fitting shot", call. = FALSE)
  }
  write_or_verify_parquet(cells, cell_path, c("PLAYER_ID", "cell_id"))

  metrics <- tibble(
    season = season,
    split_seed = SPLIT_SEED,
    sample_seed = SAMPLE_SEED,
    games = length(game_ids),
    fitting_games = length(fitting_games),
    eligible_players = nrow(eligible),
    sampled_players = nrow(sampled),
    raw_rows = nrow(metadata),
    excluded_backcourt_rows = sum(metadata$LOC_Y > COURT_Y_MAX),
    fitting_shots = nrow(fitting_shots),
    observed_player_cells = sum(cells$attempts > 0L),
    total_player_cells = nrow(cells),
    setup_elapsed_sec = proc.time()[["elapsed"]] - started
  )
  write_parquet(metrics, file.path(cache_dir, "prepare_metrics.parquet"))
  print(metrics, width = Inf)
  invisible(metrics)
}

read_cells <- function() {
  if (!all(file.exists(c(fold_path, sample_path, cell_path)))) {
    stop("Run prepare mode before fitting a model", call. = FALSE)
  }
  cells <- read_parquet(cell_path) |>
    arrange(PLAYER_ID, cell_id) |>
    mutate(
      player_factor = factor(PLAYER_ID, levels = sort(unique(PLAYER_ID))),
      player_index = as.integer(player_factor)
    )
  if (nrow(cells) != 3600L || n_distinct(cells$PLAYER_ID) != 40L ||
      n_distinct(cells$cell_id) != 90L) {
    stop("Prepared model data must be 40 players by 90 cells", call. = FALSE)
  }
  cells
}

minimum_surface_distance <- function(centered_surface) {
  matrix_form <- matrix(centered_surface, nrow = 90L, ncol = 40L)
  distances <- as.matrix(dist(t(matrix_form))) / sqrt(nrow(matrix_form))
  distances[lower.tri(distances, diag = TRUE)] <- NA_real_
  minimum <- min(distances, na.rm = TRUE)
  if (!is.finite(minimum) || minimum <= 1e-8) {
    stop("At least two players received the same centered spatial surface", call. = FALSE)
  }
  minimum
}

write_full_league_estimate <- function() {
  car_metrics_path <- file.path(cache_dir, "car_metrics.parquet")
  gam_metrics_path <- file.path(cache_dir, "gam_metrics.parquet")
  if (!all(file.exists(c(car_metrics_path, gam_metrics_path)))) {
    return(invisible(NULL))
  }

  scale_factor <- 318 / 40
  estimates <- bind_rows(
    select(read_parquet(car_metrics_path), model, fit_elapsed_sec),
    select(read_parquet(gam_metrics_path), model, fit_elapsed_sec)
  ) |>
    mutate(
      sampled_players = 40L,
      estimated_players = 318L,
      grid = "5-foot, 90 cells per player",
      estimate_method = "pilot fit time multiplied by 318 / 40",
      estimated_full_league_fit_sec = fit_elapsed_sec * scale_factor
    )
  write_parquet(estimates, file.path(cache_dir, "full_league_runtime_estimates.parquet"))
  invisible(estimates)
}

grid_adjacency <- function() {
  grid <- make_grid()
  horizontal <- grid |>
    filter(x_index < 10L) |>
    transmute(from = cell_id, to = cell_id + 1L)
  vertical <- grid |>
    filter(y_index < 9L) |>
    transmute(from = cell_id, to = cell_id + 10L)
  edges <- bind_rows(horizontal, vertical)
  Matrix::sparseMatrix(
    i = c(edges$from, edges$to),
    j = c(edges$to, edges$from),
    x = 1,
    dims = c(90L, 90L)
  )
}

fit_car <- function() {
  if (!requireNamespace("INLA", quietly = TRUE)) {
    stop("R-INLA is not installed", call. = FALSE)
  }
  cells <- read_cells()
  setup_started <- proc.time()[["elapsed"]]
  cells <- cells |>
    mutate(
      y = if_else(attempts > 0L, makes, NA_integer_),
      trials = if_else(attempts > 0L, attempts, 1L)
    )
  graph <- INLA::inla.read.graph(grid_adjacency())
  formula <- y ~ -1 + player_factor +
    f(cell_id, model = "besagproper2", graph = graph, replicate = player_index)
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started

  gc(reset = TRUE)
  fit_started <- proc.time()[["elapsed"]]
  captured <- capture_warnings(INLA::inla(
    formula,
    family = "binomial",
    Ntrials = cells$trials,
    data = cells,
    # link = 1 tells INLA to use the binomial model's logit link for the
    # zero-attempt prediction rows as well as the observed likelihood rows.
    control.predictor = list(compute = TRUE, link = 1L),
    control.compute = list(dic = FALSE, waic = FALSE, cpo = FALSE, config = FALSE),
    num.threads = MODEL_THREADS,
    safe = FALSE,
    verbose = FALSE
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  memory_after_fit <- gc()
  fit <- captured$value

  if (nrow(fit$summary.fixed) != 40L || nrow(fit$summary.hyperpar) != 2L ||
      nrow(fit$summary.random$cell_id) != 3600L ||
      nrow(fit$summary.linear.predictor) != nrow(cells)) {
    stop(
      "R-INLA fit does not have the expected player, spatial, hyperparameter, or predictor count",
      call. = FALSE
    )
  }
  centered <- fit$summary.linear.predictor$mean -
    ave(fit$summary.linear.predictor$mean, cells$PLAYER_ID, FUN = mean)
  minimum_distance <- minimum_surface_distance(centered)
  surfaces <- cells |>
    transmute(
      PLAYER_ID,
      cell_id,
      probability = fit$summary.fitted.values$mean,
      centered_logit = centered
    )

  fit_path <- file.path(cache_dir, "car_fit.rds")
  saveRDS(fit, fit_path, compress = FALSE)
  write_parquet(surfaces, file.path(cache_dir, "car_surfaces.parquet"))
  metrics <- tibble(
    season = season,
    model = "R-INLA replicated besagproper2",
    status = "success",
    threads = MODEL_THREADS,
    players = 40L,
    cells_per_player = 90L,
    likelihood_rows = sum(cells$attempts > 0L),
    fixed_effects = nrow(fit$summary.fixed),
    spatial_effects = 40L * 90L,
    smoothing_hyperparameters = nrow(fit$summary.hyperpar),
    setup_elapsed_sec = setup_elapsed,
    fit_elapsed_sec = fit_elapsed,
    approximate_r_heap_peak_mb = as.numeric(
      (memory_after_fit[1, 6] * 56 + memory_after_fit[2, 6] * 8) / 1024^2
    ),
    object_bytes = as.numeric(object.size(fit)),
    serialized_bytes = as.numeric(file.size(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    distinct_centered_surfaces = 40L,
    minimum_centered_surface_rmse = minimum_distance
  )
  write_parquet(metrics, file.path(cache_dir, "car_metrics.parquet"))
  write_full_league_estimate()
  print(metrics, width = Inf)
  invisible(metrics)
}

fit_gam <- function() {
  cells <- read_cells()
  observed <- filter(cells, attempts > 0L)
  setup_started <- proc.time()[["elapsed"]]
  formula <- cbind(makes, attempts - makes) ~ 0 + player_factor +
    s(x_center, y_center, by = player_factor, id = 1, bs = "tp", k = GAM_BASIS_SIZE)
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started

  gc(reset = TRUE)
  fit_started <- proc.time()[["elapsed"]]
  captured <- capture_warnings(mgcv::bam(
    formula,
    family = binomial(link = "logit"),
    data = observed,
    method = "fREML",
    discrete = TRUE,
    nthreads = MODEL_THREADS
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  memory_after_fit <- gc()
  fit <- captured$value
  if (length(fit$sp) != 1L || length(fit$smooth) != 40L) {
    stop("GAM must have one shared smoothing parameter and 40 player smooths", call. = FALSE)
  }

  link_prediction <- as.numeric(predict(fit, newdata = cells, type = "link"))
  centered <- link_prediction - ave(link_prediction, cells$PLAYER_ID, FUN = mean)
  minimum_distance <- minimum_surface_distance(centered)
  surfaces <- cells |>
    transmute(
      PLAYER_ID,
      cell_id,
      probability = plogis(link_prediction),
      centered_logit = centered
    )

  fit_path <- file.path(cache_dir, "gam_fit.rds")
  saveRDS(fit, fit_path, compress = FALSE)
  write_parquet(surfaces, file.path(cache_dir, "gam_surfaces.parquet"))
  metrics <- tibble(
    season = season,
    model = "mgcv shared-smoothing player GAM",
    status = "success",
    threads = MODEL_THREADS,
    players = 40L,
    cells_per_player = 90L,
    likelihood_rows = nrow(observed),
    coefficients = length(coef(fit)),
    player_smooths = length(fit$smooth),
    smoothing_hyperparameters = length(fit$sp),
    setup_elapsed_sec = setup_elapsed,
    fit_elapsed_sec = fit_elapsed,
    approximate_r_heap_peak_mb = as.numeric(
      (memory_after_fit[1, 6] * 56 + memory_after_fit[2, 6] * 8) / 1024^2
    ),
    object_bytes = as.numeric(object.size(fit)),
    serialized_bytes = as.numeric(file.size(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    distinct_centered_surfaces = 40L,
    minimum_centered_surface_rmse = minimum_distance
  )
  write_parquet(metrics, file.path(cache_dir, "gam_metrics.parquet"))
  write_full_league_estimate()
  print(metrics, width = Inf)
  invisible(metrics)
}

switch(
  mode,
  prepare = prepare_artifacts(),
  car = fit_car(),
  gam = fit_gam()
)
