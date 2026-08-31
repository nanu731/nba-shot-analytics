# Training-only audit of computational forms for the frozen spatial GAM.
#
# This script reads make/miss outcomes only for folds 1-3. It never reads fold 4
# or fold 5 outcomes. Large fit objects stay under ignored data/cache/ paths;
# only small benchmark summaries are written under data/processed/.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop(
    paste(
      "Usage: Rscript R/spatial_gam_aggregation_benchmark.R <season>",
      "<audit|compare40|compare40_discrete|benchmark318|record_timeout>",
      "[nondiscrete|discrete] [elapsed_seconds]"
    ),
    call. = FALSE
  )
}

season <- args[[1]]
mode <- args[[2]]
method <- if (length(args) >= 3L) args[[3]] else NA_character_
if (season != "2025-26") {
  stop("The frozen experiment is registered only for 2025-26", call. = FALSE)
}
if (!mode %in% c(
  "audit", "compare40", "compare40_discrete", "benchmark318",
  "record_timeout"
)) {
  stop("Unknown benchmark mode", call. = FALSE)
}
if (mode %in% c("benchmark318", "record_timeout") &&
    !method %in% c("nondiscrete", "discrete")) {
  stop("benchmark method must be nondiscrete or discrete", call. = FALSE)
}

FITTING_FOLDS <- 1:3
GRID_WIDTH <- 40L
GRID_CELLS <- 156L
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
GAM_BASIS_SIZE <- 20L
GAM_DRAW_SEED <- 20260901L
POSTERIOR_DRAWS <- 4000L
MODEL_THREADS <- 1L
EXPECTED_ALL_PLAYERS <- 318L
EXPECTED_FALLBACK_PLAYERS <- 40L
EXPECTED_SPLIT_SHA256 <- paste0(
  "aaee94c1e8380999190aea5f00f8c02c738db6438ffe7b7a1a761d19c5a6ee33"
)
EXPECTED_SAMPLE_SHA256 <- paste0(
  "bba00938e29c2a365c668d337067f3958e849db9957c8b2d259629e50c78ae84"
)

# These thresholds are fixed before the comparison is run. Grouping repeated
# Bernoulli rows should agree to numerical precision, so the tolerances are much
# tighter than any difference that could matter to a shot probability.
AGGREGATION_PROBABILITY_TOLERANCE <- 1e-6
AGGREGATION_LOG_SP_TOLERANCE <- 1e-6
AGGREGATION_EDF_TOLERANCE <- 1e-5

# discrete=TRUE is a separately identified approximation. It is tested only if
# the exact non-discrete computation is impractical. These still require close
# agreement with the exact aggregated fit on the 40-player sample.
DISCRETE_OBSERVED_PROBABILITY_TOLERANCE <- 1e-4
DISCRETE_LATTICE_PROBABILITY_TOLERANCE <- 5e-4
DISCRETE_MEAN_PROBABILITY_TOLERANCE <- 1e-5
DISCRETE_LOG_SP_TOLERANCE <- 1e-2
DISCRETE_EDF_TOLERANCE <- 1e-2

raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", season), "shots.parquet"
)
fold_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "game_folds.parquet"
)
sample_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "player_sample.parquet"
)
cache_dir <- file.path(
  "data", "cache", "spatial_gam_aggregation", paste0("season=", season)
)
result_dir <- file.path(
  "data", "processed", "spatial_gam_aggregation", paste0("season=", season)
)
equivalence_path <- file.path(result_dir, "aggregation_equivalence.parquet")
discrete_path <- file.path(result_dir, "discrete_approximation.parquet")
benchmark_path <- file.path(result_dir, "full_league_benchmark.parquet")

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

set_frozen_rng <- function(seed) {
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
}

write_atomic_parquet <- function(table, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = paste0(basename(path), ".partial-"),
                        tmpdir = dirname(path))
  write_parquet(table, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not publish benchmark result atomically: ", path, call. = FALSE)
  }
}

save_atomic_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = paste0(basename(path), ".partial-"),
                        tmpdir = dirname(path))
  saveRDS(object, temporary, compress = FALSE)
  if (!file.rename(temporary, path)) {
    stop("Could not publish benchmark fit atomically: ", path, call. = FALSE)
  }
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
  list(
    value = value,
    warnings = unique(warnings),
    messages = unique(messages)
  )
}

verify_environment <- function() {
  expected <- c(
    mgcv = "1.9.4", arrow = "25.0.0", dplyr = "1.2.1", tidyr = "1.3.2"
  )
  found <- vapply(names(expected), function(package) {
    as.character(packageVersion(package))
  }, character(1))
  if (getRversion() != "4.6.0" || !identical(found, expected)) {
    stop(
      "R or package versions do not match the frozen experiment",
      call. = FALSE
    )
  }
}

read_folds <- function() {
  if (!file.exists(fold_path) || sha256_file(fold_path) != EXPECTED_SPLIT_SHA256) {
    stop("The frozen split artifact is missing or has the wrong hash", call. = FALSE)
  }
  folds <- read_parquet(fold_path) |>
    as_tibble() |>
    arrange(GAME_ID)
  counts <- count(folds, fold)
  if (nrow(folds) != 1230L || n_distinct(folds$GAME_ID) != 1230L ||
      !identical(counts$fold, 1:5) || any(counts$n != 246L)) {
    stop("The frozen split artifact has unexpected dimensions", call. = FALSE)
  }
  folds
}

read_metadata <- function(folds) {
  schema_names <- names(read_parquet(raw_path, as_data_frame = FALSE)$schema)
  if (!all(OUTCOME_COLUMNS %in% schema_names)) {
    stop("Raw shot data is missing required columns", call. = FALSE)
  }
  metadata <- read_parquet(raw_path, col_select = all_of(METADATA_COLUMNS)) |>
    as_tibble()
  if (!is.character(metadata$GAME_ID) || anyNA(metadata)) {
    stop("Shot metadata failed type or missing-value checks", call. = FALSE)
  }
  metadata |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    left_join(folds, by = "GAME_ID")
}

eligible_players <- function(metadata) {
  eligible <- metadata |>
    summarise(
      PLAYER_NAME = first(PLAYER_NAME),
      season_attempts = n(),
      season_games = n_distinct(GAME_ID),
      .by = PLAYER_ID
    ) |>
    filter(season_games >= MIN_GAMES, season_attempts >= MIN_ATTEMPTS) |>
    arrange(PLAYER_ID)
  if (nrow(eligible) != EXPECTED_ALL_PLAYERS) {
    stop("All-player eligibility count changed", call. = FALSE)
  }
  eligible
}

fallback_players <- function(metadata, eligible) {
  if (!file.exists(sample_path) || sha256_file(sample_path) != EXPECTED_SAMPLE_SHA256) {
    stop("The frozen fallback sample is missing or has the wrong hash", call. = FALSE)
  }
  saved <- read_parquet(sample_path) |>
    as_tibble() |>
    arrange(volume_group, PLAYER_ID)
  training_volume <- metadata |>
    filter(fold %in% FITTING_FOLDS, PLAYER_ID %in% eligible$PLAYER_ID) |>
    count(PLAYER_ID, name = "training_attempts")
  frame <- eligible |>
    inner_join(training_volume, by = "PLAYER_ID") |>
    arrange(training_attempts, PLAYER_ID) |>
    mutate(volume_group = ntile(row_number(), 4L))
  set_frozen_rng(20260831L)
  expected <- frame |>
    group_by(volume_group) |>
    slice(sample.int(n(), 10L, replace = FALSE)) |>
    ungroup() |>
    arrange(volume_group, PLAYER_ID)
  if (!identical(as.data.frame(saved), as.data.frame(expected)) ||
      nrow(saved) != EXPECTED_FALLBACK_PLAYERS) {
    stop("The fallback sample does not reproduce its frozen selection", call. = FALSE)
  }
  saved
}

read_training_outcomes <- function(folds, player_ids) {
  # The only outcome read is pushed down to the declared fitting games. Neither
  # fold 4 nor fold 5 SHOT_MADE_FLAG values can enter this process.
  allowed_games <- folds$GAME_ID[folds$fold %in% FITTING_FOLDS]
  outcomes <- open_dataset(raw_path) |>
    filter(GAME_ID %in% allowed_games, PLAYER_ID %in% player_ids) |>
    select(all_of(OUTCOME_COLUMNS)) |>
    collect() |>
    as_tibble() |>
    left_join(select(folds, GAME_ID, fold), by = "GAME_ID") |>
    filter(LOC_Y <= COURT_Y_MAX)
  if (anyNA(outcomes$fold) ||
      !identical(sort(unique(outcomes$fold)), FITTING_FOLDS) ||
      any(!outcomes$SHOT_MADE_FLAG %in% c(0L, 1L))) {
    stop("Training outcome loader returned an undeclared row", call. = FALSE)
  }
  outcomes
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
  if (nrow(grid) != GRID_CELLS) {
    stop("The fixed 4-foot grid does not have 156 cells", call. = FALSE)
  }
  attr(grid, "nx") <- nx
  attr(grid, "ny") <- ny
  grid
}

prepare_gam_data <- function(training, player_ids) {
  grid <- make_grid()
  nx <- attr(grid, "nx")
  ny <- attr(grid, "ny")
  shot_rows <- training |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L, nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L, ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    ) |>
    left_join(select(grid, cell_id, x_ft, y_ft), by = "cell_id") |>
    mutate(player_factor = factor(PLAYER_ID, levels = player_ids)) |>
    arrange(PLAYER_ID, cell_id, GAME_ID, LOC_X, LOC_Y, SHOT_MADE_FLAG)
  if (anyNA(shot_rows$cell_id) || anyNA(shot_rows$x_ft) ||
      anyNA(shot_rows$player_factor)) {
    stop("A fitting shot failed grid or player assignment", call. = FALSE)
  }
  repeated_inputs <- shot_rows |>
    summarise(
      coordinate_pairs = n_distinct(paste(x_ft, y_ft)),
      factor_levels = n_distinct(as.character(player_factor)),
      .by = c(PLAYER_ID, cell_id)
    )
  if (any(repeated_inputs$coordinate_pairs != 1L) ||
      any(repeated_inputs$factor_levels != 1L)) {
    stop("Shots within a player-cell do not have identical model inputs", call. = FALSE)
  }
  aggregated <- shot_rows |>
    summarise(
      makes = sum(SHOT_MADE_FLAG),
      attempts = n(),
      x_ft = first(x_ft),
      y_ft = first(y_ft),
      .by = c(PLAYER_ID, cell_id, player_factor)
    ) |>
    arrange(PLAYER_ID, cell_id)
  if (sum(aggregated$attempts) != nrow(shot_rows) ||
      sum(aggregated$makes) != sum(shot_rows$SHOT_MADE_FLAG)) {
    stop("Player-cell aggregation did not preserve outcomes", call. = FALSE)
  }
  lattice <- tibble(PLAYER_ID = player_ids) |>
    crossing(select(grid, cell_id, x_ft, y_ft)) |>
    mutate(player_factor = factor(PLAYER_ID, levels = player_ids)) |>
    arrange(PLAYER_ID, cell_id)
  list(
    shots = shot_rows,
    aggregated = aggregated,
    lattice = lattice,
    grid = grid,
    exact_repeated_inputs = TRUE
  )
}

gam_formula <- function(response = c("aggregated", "shots")) {
  response <- match.arg(response)
  response_expression <- if (response == "aggregated") {
    quote(cbind(makes, attempts - makes))
  } else {
    quote(SHOT_MADE_FLAG)
  }
  as.formula(substitute(
    RESPONSE ~ 0 + player_factor +
      s(x_ft, y_ft, by = player_factor, bs = "tp", m = 2, k = 20, id = 1),
    list(RESPONSE = response_expression)
  ))
}

smooth_edf <- function(fit) {
  vapply(
    fit$smooth,
    function(smooth) sum(fit$edf[smooth$first.para:smooth$last.para]),
    numeric(1)
  )
}

draw_averaged_predictions <- function(fit, lattice) {
  covariance <- vcov(fit, unconditional = TRUE)
  if (any(!is.finite(covariance))) {
    stop("The unconditional GAM covariance contains non-finite values", call. = FALSE)
  }
  set_frozen_rng(GAM_DRAW_SEED)
  draws <- mgcv::rmvn(POSTERIOR_DRAWS, mu = coef(fit), V = covariance)
  player_ids <- levels(lattice$player_factor)
  pieces <- vector("list", length(player_ids))
  for (position in seq_along(player_ids)) {
    rows <- which(lattice$PLAYER_ID == player_ids[[position]])
    design <- predict(
      fit, newdata = lattice[rows, ], type = "lpmatrix",
      discrete = isTRUE(fit$discrete)
    )
    active <- which(colSums(abs(design)) > 0)
    eta <- design[, active, drop = FALSE] %*%
      t(draws[, active, drop = FALSE])
    pieces[[position]] <- rowMeans(plogis(eta))
  }
  unlist(pieces, use.names = FALSE)
}

fit_gam_form <- function(data, lattice, response, discrete) {
  formula <- gam_formula(response)
  started <- proc.time()[["elapsed"]]
  captured <- capture_conditions(mgcv::bam(
    formula,
    family = binomial(link = "logit"),
    data = data,
    method = "fREML",
    discrete = discrete,
    select = FALSE,
    gamma = 1,
    nthreads = MODEL_THREADS,
    na.action = na.fail
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - started
  fit <- captured$value
  edf <- smooth_edf(fit)
  if (!isTRUE(fit$converged) || any(!is.finite(coef(fit))) ||
      length(fit$sp) != 1L || length(fit$smooth) != nlevels(data$player_factor) ||
      any(edf >= 0.95 * (GAM_BASIS_SIZE - 1L))) {
    stop("The GAM failed a frozen fit sanity check", call. = FALSE)
  }
  prediction_started <- proc.time()[["elapsed"]]
  plugin <- plogis(as.numeric(predict(fit, newdata = lattice, type = "link",
                                      discrete = discrete)))
  draws <- draw_averaged_predictions(fit, lattice)
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started
  if (any(!is.finite(plugin)) || any(!is.finite(draws)) ||
      any(plugin < 0 | plugin > 1) || any(draws < 0 | draws > 1)) {
    stop("The GAM failed a frozen prediction sanity check", call. = FALSE)
  }
  list(
    fit = fit,
    plugin = plugin,
    draw_probability = draws,
    edf = edf,
    fit_elapsed_sec = fit_elapsed,
    prediction_elapsed_sec = prediction_elapsed,
    warnings = captured$warnings,
    messages = captured$messages
  )
}

build_inputs <- function(scope = c("fallback40", "all318")) {
  scope <- match.arg(scope)
  verify_environment()
  folds <- read_folds()
  metadata <- read_metadata(folds)
  all_eligible <- eligible_players(metadata)
  fallback <- fallback_players(metadata, all_eligible)
  selected <- if (scope == "fallback40") fallback$PLAYER_ID else all_eligible$PLAYER_ID
  selected <- sort(selected)
  training <- read_training_outcomes(folds, selected)
  data <- prepare_gam_data(training, selected)
  list(
    data = data,
    training_shots = nrow(training),
    players = length(selected),
    folds = paste(FITTING_FOLDS, collapse = ","),
    split_sha256 = EXPECTED_SPLIT_SHA256,
    fallback_sample_sha256 = EXPECTED_SAMPLE_SHA256
  )
}

compare_aggregation <- function() {
  setup_started <- proc.time()[["elapsed"]]
  inputs <- build_inputs("fallback40")
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started
  shot <- fit_gam_form(
    inputs$data$shots, inputs$data$lattice, "shots", discrete = FALSE
  )
  aggregated <- fit_gam_form(
    inputs$data$aggregated, inputs$data$lattice, "aggregated", discrete = FALSE
  )
  observed_lattice_rows <- match(
    paste(inputs$data$aggregated$PLAYER_ID, inputs$data$aggregated$cell_id),
    paste(inputs$data$lattice$PLAYER_ID, inputs$data$lattice$cell_id)
  )
  observed_probability_difference <- max(abs(
    shot$plugin[observed_lattice_rows] - aggregated$plugin[observed_lattice_rows]
  ))
  lattice_probability_difference <- max(abs(shot$plugin - aggregated$plugin))
  draw_probability_difference <- max(abs(
    shot$draw_probability - aggregated$draw_probability
  ))
  log_sp_difference <- abs(log(shot$fit$sp) - log(aggregated$fit$sp))
  edf_difference <- max(abs(shot$edf - aggregated$edf))
  passed <- observed_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    lattice_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    draw_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    log_sp_difference <= AGGREGATION_LOG_SP_TOLERANCE &&
    edf_difference <= AGGREGATION_EDF_TOLERANCE
  result <- tibble(
    season = season,
    scope = "predeclared_40_player_fallback",
    grid_width = GRID_WIDTH,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    exact_repeated_inputs = inputs$data$exact_repeated_inputs,
    mathematically_equivalent_likelihood = TRUE,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    setup_elapsed_sec = setup_elapsed,
    shot_fit_elapsed_sec = shot$fit_elapsed_sec,
    aggregated_fit_elapsed_sec = aggregated$fit_elapsed_sec,
    shot_prediction_elapsed_sec = shot$prediction_elapsed_sec,
    aggregated_prediction_elapsed_sec = aggregated$prediction_elapsed_sec,
    smoothing_parameter_shot = unname(shot$fit$sp),
    smoothing_parameter_aggregated = unname(aggregated$fit$sp),
    maximum_smooth_edf_shot = max(shot$edf),
    maximum_smooth_edf_aggregated = max(aggregated$edf),
    maximum_observed_probability_difference = observed_probability_difference,
    maximum_lattice_probability_difference = lattice_probability_difference,
    maximum_draw_probability_difference = draw_probability_difference,
    absolute_log_smoothing_parameter_difference = log_sp_difference,
    maximum_smooth_edf_difference = edf_difference,
    probability_tolerance = AGGREGATION_PROBABILITY_TOLERANCE,
    log_smoothing_parameter_tolerance = AGGREGATION_LOG_SP_TOLERANCE,
    edf_tolerance = AGGREGATION_EDF_TOLERANCE,
    warning_count = length(c(shot$warnings, aggregated$warnings)),
    passed = passed,
    split_sha256 = inputs$split_sha256,
    fallback_sample_sha256 = inputs$fallback_sample_sha256
  )
  write_atomic_parquet(result, equivalence_path)
  save_atomic_rds(
    aggregated$fit, file.path(cache_dir, "fallback40_aggregated_exact_fit.rds")
  )
  print(result, width = Inf)
  if (!passed) {
    stop("Aggregation did not meet its predeclared numerical tolerances", call. = FALSE)
  }
}

compare_discrete <- function() {
  inputs <- build_inputs("fallback40")
  exact <- fit_gam_form(
    inputs$data$aggregated, inputs$data$lattice, "aggregated", discrete = FALSE
  )
  discrete <- fit_gam_form(
    inputs$data$aggregated, inputs$data$lattice, "aggregated", discrete = TRUE
  )
  observed_rows <- match(
    paste(inputs$data$aggregated$PLAYER_ID, inputs$data$aggregated$cell_id),
    paste(inputs$data$lattice$PLAYER_ID, inputs$data$lattice$cell_id)
  )
  observed_difference <- max(abs(
    exact$plugin[observed_rows] - discrete$plugin[observed_rows]
  ))
  lattice_difference <- max(abs(exact$plugin - discrete$plugin))
  mean_difference <- mean(abs(exact$plugin - discrete$plugin))
  draw_difference <- max(abs(
    exact$draw_probability - discrete$draw_probability
  ))
  log_sp_difference <- abs(log(exact$fit$sp) - log(discrete$fit$sp))
  edf_difference <- max(abs(exact$edf - discrete$edf))
  passed <- observed_difference <= DISCRETE_OBSERVED_PROBABILITY_TOLERANCE &&
    lattice_difference <= DISCRETE_LATTICE_PROBABILITY_TOLERANCE &&
    mean_difference <= DISCRETE_MEAN_PROBABILITY_TOLERANCE &&
    log_sp_difference <= DISCRETE_LOG_SP_TOLERANCE &&
    edf_difference <= DISCRETE_EDF_TOLERANCE
  result <- tibble(
    season = season,
    scope = "predeclared_40_player_fallback",
    grid_width = GRID_WIDTH,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    exact_fit_elapsed_sec = exact$fit_elapsed_sec,
    discrete_fit_elapsed_sec = discrete$fit_elapsed_sec,
    exact_prediction_elapsed_sec = exact$prediction_elapsed_sec,
    discrete_prediction_elapsed_sec = discrete$prediction_elapsed_sec,
    maximum_observed_probability_difference = observed_difference,
    maximum_lattice_probability_difference = lattice_difference,
    mean_lattice_probability_difference = mean_difference,
    maximum_draw_probability_difference = draw_difference,
    absolute_log_smoothing_parameter_difference = log_sp_difference,
    maximum_smooth_edf_difference = edf_difference,
    observed_probability_tolerance = DISCRETE_OBSERVED_PROBABILITY_TOLERANCE,
    lattice_probability_tolerance = DISCRETE_LATTICE_PROBABILITY_TOLERANCE,
    mean_probability_tolerance = DISCRETE_MEAN_PROBABILITY_TOLERANCE,
    log_smoothing_parameter_tolerance = DISCRETE_LOG_SP_TOLERANCE,
    edf_tolerance = DISCRETE_EDF_TOLERANCE,
    warning_count = length(c(exact$warnings, discrete$warnings)),
    passed = passed,
    split_sha256 = inputs$split_sha256,
    fallback_sample_sha256 = inputs$fallback_sample_sha256
  )
  write_atomic_parquet(result, discrete_path)
  save_atomic_rds(
    discrete$fit, file.path(cache_dir, "fallback40_aggregated_discrete_fit.rds")
  )
  print(result, width = Inf)
  if (!passed) {
    stop("discrete=TRUE did not meet its predeclared approximation tolerances",
         call. = FALSE)
  }
}

benchmark_full_league <- function(discrete) {
  total_started <- proc.time()[["elapsed"]]
  setup_started <- proc.time()[["elapsed"]]
  inputs <- build_inputs("all318")
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started
  fit <- fit_gam_form(
    inputs$data$aggregated, inputs$data$lattice, "aggregated", discrete
  )
  total_elapsed <- proc.time()[["elapsed"]] - total_started
  method_name <- if (discrete) "aggregated_discrete" else "aggregated_nondiscrete"
  fit_path <- file.path(cache_dir, paste0("all318_", method_name, "_fit.rds"))
  save_atomic_rds(fit$fit, fit_path)
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = method_name,
    grid_width = GRID_WIDTH,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = TRUE,
    timed_out = FALSE,
    runtime_ceiling_sec = 1800,
    setup_elapsed_sec = setup_elapsed,
    fit_elapsed_sec = fit$fit_elapsed_sec,
    prediction_elapsed_sec = fit$prediction_elapsed_sec,
    total_elapsed_sec = total_elapsed,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = length(coef(fit$fit)),
    smooth_count = length(fit$fit$smooth),
    smoothing_parameter_count = length(fit$fit$sp),
    smoothing_parameter = unname(fit$fit$sp),
    maximum_smooth_edf = max(fit$edf),
    model_object_bytes = as.numeric(object.size(fit$fit)),
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    warning_count = length(fit$warnings),
    warnings = paste(fit$warnings, collapse = " | "),
    message_count = length(fit$messages),
    messages = paste(fit$messages, collapse = " | "),
    split_sha256 = inputs$split_sha256
  )
  existing <- if (file.exists(benchmark_path)) {
    read_parquet(benchmark_path) |> as_tibble() |>
      filter(method != method_name)
  } else {
    result[0, ]
  }
  write_atomic_parquet(bind_rows(existing, result) |> arrange(method), benchmark_path)
  print(result, width = Inf)
}

record_timeout <- function(method, elapsed_seconds) {
  method_name <- if (method == "discrete") {
    "aggregated_discrete"
  } else {
    "aggregated_nondiscrete"
  }
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = method_name,
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = FALSE,
    timed_out = TRUE,
    runtime_ceiling_sec = 1800,
    setup_elapsed_sec = NA_real_,
    fit_elapsed_sec = NA_real_,
    prediction_elapsed_sec = NA_real_,
    total_elapsed_sec = as.numeric(elapsed_seconds),
    players = EXPECTED_ALL_PLAYERS,
    training_shots = NA_integer_,
    observed_player_cells = NA_integer_,
    full_lattice_rows = EXPECTED_ALL_PLAYERS * GRID_CELLS,
    coefficient_count = EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    smooth_count = EXPECTED_ALL_PLAYERS,
    smoothing_parameter_count = 1L,
    smoothing_parameter = NA_real_,
    maximum_smooth_edf = NA_real_,
    model_object_bytes = NA_real_,
    serialized_model_bytes = NA_real_,
    serialized_model_md5 = NA_character_,
    warning_count = NA_integer_,
    warnings = "process exceeded the predeclared wall-time ceiling",
    message_count = NA_integer_,
    messages = "",
    split_sha256 = EXPECTED_SPLIT_SHA256
  )
  existing <- if (file.exists(benchmark_path)) {
    read_parquet(benchmark_path) |> as_tibble() |>
      filter(method != method_name)
  } else {
    result[0, ]
  }
  write_atomic_parquet(bind_rows(existing, result) |> arrange(method), benchmark_path)
  print(result, width = Inf)
}

if (mode == "audit") {
  fallback <- build_inputs("fallback40")
  all_players <- build_inputs("all318")
  audit <- tibble(
    scope = c("predeclared_40_player_fallback", "all_318_eligible_players"),
    players = c(fallback$players, all_players$players),
    training_shots = c(fallback$training_shots, all_players$training_shots),
    observed_player_cells = c(
      nrow(fallback$data$aggregated), nrow(all_players$data$aggregated)
    ),
    shot_rows = c(nrow(fallback$data$shots), nrow(all_players$data$shots)),
    full_lattice_rows = c(
      nrow(fallback$data$lattice), nrow(all_players$data$lattice)
    ),
    current_gam_rows_equal_observed_player_cells = TRUE,
    identical_inputs_within_player_cell = c(
      fallback$data$exact_repeated_inputs, all_players$data$exact_repeated_inputs
    ),
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE
  )
  print(audit, width = Inf)
} else if (mode == "compare40") {
  compare_aggregation()
} else if (mode == "compare40_discrete") {
  compare_discrete()
} else if (mode == "benchmark318") {
  benchmark_full_league(discrete = method == "discrete")
} else if (mode == "record_timeout") {
  if (length(args) != 4L) {
    stop("record_timeout requires method and elapsed seconds", call. = FALSE)
  }
  record_timeout(method, as.numeric(args[[4]]))
}
