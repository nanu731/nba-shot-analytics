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
      paste0(
        "<audit|compare40|compare40_discrete|compare40_parallel|",
        "benchmark318|benchmark318_parallel|record_timeout|",
        "record_parallel_timeout|discrete318-audit|discrete318-run|",
        "exact318-long-audit|exact318-long-run|",
        "exact318-launchagent-smoke>"
      ),
      "[method_or_workers] [elapsed_seconds]"
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
  "audit", "compare40", "compare40_discrete", "compare40_parallel",
  "benchmark318", "benchmark318_parallel", "record_timeout",
  "record_parallel_timeout", "discrete318-audit", "discrete318-run",
  "exact318-long-audit", "exact318-long-run", "exact318-launchagent-smoke"
)) {
  stop("Unknown benchmark mode", call. = FALSE)
}
if (identical(Sys.getenv("SPATIAL_EXACT_SMOKE_ONLY"), "1") &&
    mode != "exact318-launchagent-smoke") {
  stop("SMOKE SAFEGUARD: audit-only environment cannot dispatch another mode",
       call. = FALSE)
}
if (mode %in% c("benchmark318", "record_timeout") &&
    !method %in% c("nondiscrete", "discrete")) {
  stop("benchmark method must be nondiscrete or discrete", call. = FALSE)
}
if (mode %in% c(
  "compare40_parallel", "benchmark318_parallel", "record_parallel_timeout"
)) {
  worker_count <- suppressWarnings(as.integer(method))
  if (is.na(worker_count) || worker_count < 2L) {
    stop("parallel modes require a worker count of at least two", call. = FALSE)
  }
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
PREDICTIVE_SEED <- 20260903L
POSTERIOR_DRAWS <- 4000L
MODEL_THREADS <- 1L
DISCRETE_RUNTIME_CEILING_SEC <- 1800
EXACT_LONG_WORKERS <- 2L
EXACT_LONG_SAMPLE_INTERVAL_SEC <- 60
EXACT_LONG_MIN_FREE_GIB <- 20
SURFACE_TOLERANCE <- 1e-8
EXPECTED_ALL_PLAYERS <- 318L
EXPECTED_FALLBACK_PLAYERS <- 40L
EXPECTED_PHYSICAL_CORES <- 10L
EXPECTED_LOGICAL_CORES <- 10L
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
parallel_equivalence_path <- file.path(result_dir, "parallel_equivalence.parquet")
parallel_benchmark_path <- file.path(
  result_dir, "full_league_parallel_benchmark.parquet"
)
discrete_cache_dir <- file.path(
  "data", "cache", "spatial_gam_discrete_full_league_benchmark",
  paste0("season=", season)
)
discrete_result_dir <- file.path(
  "data", "processed", "spatial_gam_discrete_full_league_benchmark",
  paste0("season=", season)
)
exact_long_cache_dir <- file.path(
  "data", "cache", "spatial_gam_exact_full_league_benchmark",
  paste0("season=", season)
)
exact_long_result_dir <- file.path(
  "data", "processed", "spatial_gam_exact_full_league_benchmark",
  paste0("season=", season)
)
exact_smoke_root_dir <- file.path(
  "data", "cache", "spatial_gam_exact_launchagent_smoke",
  paste0("season=", season)
)

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
  invisible(lapply(names(expected), function(package) {
    loadNamespace(package)
  }))
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
      discrete = isTRUE(fit$dinfo$para.discrete)
    )
    active <- which(colSums(abs(design)) > 0)
    eta <- design[, active, drop = FALSE] %*%
      t(draws[, active, drop = FALSE])
    pieces[[position]] <- rowMeans(plogis(eta))
  }
  unlist(pieces, use.names = FALSE)
}

fit_gam_form <- function(data, lattice, response, discrete, cluster = NULL) {
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
    cluster = cluster,
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

process_cpu_seconds <- function() {
  timing <- proc.time()
  unname(timing[["user.self"]] + timing[["sys.self"]])
}

r_heap_max_mb <- function() {
  sum(gc()[, "max used", drop = TRUE] * c(56, 8) / 1024^2)
}

cluster_cpu_seconds <- function(cluster) {
  values <- parallel::clusterCall(cluster, function() {
    timing <- proc.time()
    unname(timing[["user.self"]] + timing[["sys.self"]])
  })
  sum(unlist(values, use.names = FALSE))
}

cluster_heap_max_mb <- function(cluster) {
  values <- parallel::clusterCall(cluster, function() {
    sum(gc()[, "max used", drop = TRUE] * c(56, 8) / 1024^2)
  })
  sum(unlist(values, use.names = FALSE))
}

load_exact_fallback_fit <- function(inputs) {
  path <- file.path(cache_dir, "fallback40_aggregated_exact_fit.rds")
  if (!file.exists(path)) {
    stop("The completed exact 40-player fit is missing", call. = FALSE)
  }
  fit <- readRDS(path)
  evidence <- read_parquet(equivalence_path) |> as_tibble()
  expected_formula <- paste(deparse(gam_formula("aggregated")), collapse = " ")
  found_formula <- paste(deparse(fit$formula), collapse = " ")
  if (nrow(evidence) != 1L ||
      !identical(evidence$fold4_outcomes_read[[1]], FALSE) ||
      !identical(evidence$fold5_outcomes_read[[1]], FALSE) ||
      !isTRUE(fit$converged) || length(coef(fit)) != 800L ||
      length(fit$smooth) != EXPECTED_FALLBACK_PLAYERS || length(fit$sp) != 1L ||
      !isTRUE(all.equal(
        unname(fit$sp), evidence$smoothing_parameter_aggregated,
        tolerance = .Machine$double.eps^0.5
      )) || found_formula != expected_formula ||
      nrow(inputs$data$aggregated) != evidence$observed_player_cells) {
    stop("The completed exact 40-player fit failed provenance checks", call. = FALSE)
  }
  list(
    fit = fit,
    md5 = unname(tools::md5sum(path)),
    evidence = evidence
  )
}

compare_parallel <- function(worker_count) {
  setup_started <- proc.time()[["elapsed"]]
  inputs <- build_inputs("fallback40")
  exact <- load_exact_fallback_fit(inputs)
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started

  exact_edf <- smooth_edf(exact$fit)
  exact_plugin <- plogis(as.numeric(predict(
    exact$fit, newdata = inputs$data$lattice, type = "link", discrete = FALSE
  )))
  exact_draw_probability <- draw_averaged_predictions(
    exact$fit, inputs$data$lattice
  )

  cluster <- parallel::makeCluster(worker_count, type = "PSOCK")
  cluster_stopped <- FALSE
  on.exit({
    if (!cluster_stopped) parallel::stopCluster(cluster)
  }, add = TRUE)
  worker_cpu_before <- cluster_cpu_seconds(cluster)
  parent_cpu_before <- process_cpu_seconds()
  parallel_fit <- fit_gam_form(
    inputs$data$aggregated,
    inputs$data$lattice,
    "aggregated",
    discrete = FALSE,
    cluster = cluster
  )
  parent_cpu_elapsed <- process_cpu_seconds() - parent_cpu_before
  worker_cpu_elapsed <- cluster_cpu_seconds(cluster) - worker_cpu_before
  approximate_peak_r_heap_mb <- r_heap_max_mb() + cluster_heap_max_mb(cluster)
  parallel::stopCluster(cluster)
  cluster_stopped <- TRUE

  observed_probability_difference <- max(abs(
    fitted(exact$fit) - fitted(parallel_fit$fit)
  ))
  lattice_probability_difference <- max(abs(
    exact_plugin - parallel_fit$plugin
  ))
  draw_probability_difference <- max(abs(
    exact_draw_probability - parallel_fit$draw_probability
  ))
  log_sp_difference <- abs(log(exact$fit$sp) - log(parallel_fit$fit$sp))
  edf_difference <- max(abs(exact_edf - parallel_fit$edf))
  passed <- observed_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    lattice_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    draw_probability_difference <= AGGREGATION_PROBABILITY_TOLERANCE &&
    log_sp_difference <= AGGREGATION_LOG_SP_TOLERANCE &&
    edf_difference <= AGGREGATION_EDF_TOLERANCE

  fit_path <- file.path(cache_dir, "fallback40_aggregated_parallel_fit.rds")
  save_atomic_rds(parallel_fit$fit, fit_path)
  result <- tibble(
    season = season,
    scope = "predeclared_40_player_fallback",
    method = "exact_nondiscrete_psock_cluster",
    grid_width = GRID_WIDTH,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    physical_cores = EXPECTED_PHYSICAL_CORES,
    logical_cores = EXPECTED_LOGICAL_CORES,
    worker_count = worker_count,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    setup_elapsed_sec = setup_elapsed,
    exact_single_fit_elapsed_sec = exact$evidence$aggregated_fit_elapsed_sec,
    parallel_fit_elapsed_sec = parallel_fit$fit_elapsed_sec,
    parallel_prediction_elapsed_sec = parallel_fit$prediction_elapsed_sec,
    parent_cpu_elapsed_sec = parent_cpu_elapsed,
    worker_cpu_elapsed_sec = worker_cpu_elapsed,
    total_cpu_elapsed_sec = parent_cpu_elapsed + worker_cpu_elapsed,
    approximate_peak_r_heap_mb_sum = approximate_peak_r_heap_mb,
    smoothing_parameter_exact = unname(exact$fit$sp),
    smoothing_parameter_parallel = unname(parallel_fit$fit$sp),
    maximum_smooth_edf_exact = max(exact_edf),
    maximum_smooth_edf_parallel = max(parallel_fit$edf),
    maximum_observed_probability_difference = observed_probability_difference,
    maximum_lattice_probability_difference = lattice_probability_difference,
    maximum_draw_probability_difference = draw_probability_difference,
    absolute_log_smoothing_parameter_difference = log_sp_difference,
    maximum_smooth_edf_difference = edf_difference,
    probability_tolerance = AGGREGATION_PROBABILITY_TOLERANCE,
    log_smoothing_parameter_tolerance = AGGREGATION_LOG_SP_TOLERANCE,
    edf_tolerance = AGGREGATION_EDF_TOLERANCE,
    warning_count = length(parallel_fit$warnings),
    warnings = paste(parallel_fit$warnings, collapse = " | "),
    reference_fit_md5 = exact$md5,
    parallel_fit_md5 = unname(tools::md5sum(fit_path)),
    passed = passed,
    split_sha256 = inputs$split_sha256,
    fallback_sample_sha256 = inputs$fallback_sample_sha256
  )
  write_atomic_parquet(result, parallel_equivalence_path)
  print(result, width = Inf)
  if (!passed) {
    stop("The exact parallel fit exceeded numerical-rounding tolerances",
         call. = FALSE)
  }
}

benchmark_full_league_parallel <- function(worker_count, worker_pid_path = NULL) {
  total_wall_started <- proc.time()[["elapsed"]]
  parent_cpu_started <- process_cpu_seconds()
  setup_started <- proc.time()[["elapsed"]]
  inputs <- build_inputs("all318")
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started

  cluster <- parallel::makeCluster(worker_count, type = "PSOCK")
  cluster_stopped <- FALSE
  on.exit({
    if (!cluster_stopped) parallel::stopCluster(cluster)
  }, add = TRUE)
  if (!is.null(worker_pid_path)) {
    save_atomic_rds(
      as.integer(unlist(parallel::clusterCall(cluster, Sys.getpid))),
      worker_pid_path
    )
  }
  worker_cpu_before <- cluster_cpu_seconds(cluster)
  fit <- fit_gam_form(
    inputs$data$aggregated,
    inputs$data$lattice,
    "aggregated",
    discrete = FALSE,
    cluster = cluster
  )
  worker_cpu_elapsed <- cluster_cpu_seconds(cluster) - worker_cpu_before
  approximate_peak_r_heap_mb <- r_heap_max_mb() + cluster_heap_max_mb(cluster)
  parallel::stopCluster(cluster)
  cluster_stopped <- TRUE

  total_wall_elapsed <- proc.time()[["elapsed"]] - total_wall_started
  parent_cpu_elapsed <- process_cpu_seconds() - parent_cpu_started
  fit_path <- file.path(cache_dir, "all318_aggregated_parallel_fit.rds")
  save_atomic_rds(fit$fit, fit_path)
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "exact_nondiscrete_psock_cluster",
    grid_width = GRID_WIDTH,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    physical_cores = EXPECTED_PHYSICAL_CORES,
    logical_cores = EXPECTED_LOGICAL_CORES,
    worker_count = worker_count,
    completed = TRUE,
    timed_out = FALSE,
    runtime_ceiling_sec = 1800,
    setup_elapsed_sec = setup_elapsed,
    fit_elapsed_sec = fit$fit_elapsed_sec,
    prediction_elapsed_sec = fit$prediction_elapsed_sec,
    total_wall_elapsed_sec = total_wall_elapsed,
    parent_cpu_elapsed_sec = parent_cpu_elapsed,
    worker_cpu_elapsed_sec = worker_cpu_elapsed,
    total_cpu_elapsed_sec = parent_cpu_elapsed + worker_cpu_elapsed,
    cpu_measurement = "R proc.time for parent plus cluster-reported worker CPU",
    peak_memory_mb = approximate_peak_r_heap_mb,
    memory_measurement = paste(
      "sum of per-process maximum R heaps; upper bound because peaks",
      "may not coincide"
    ),
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
  write_atomic_parquet(result, parallel_benchmark_path)
  print(result, width = Inf)
}

parse_ps_cpu_seconds <- function(values) {
  vapply(values, function(value) {
    day_parts <- strsplit(value, "-", fixed = TRUE)[[1]]
    days <- if (length(day_parts) == 2L) as.numeric(day_parts[[1]]) else 0
    clock <- strsplit(tail(day_parts, 1L), ":", fixed = TRUE)[[1]]
    clock <- as.numeric(clock)
    if (length(clock) == 3L) {
      seconds <- clock[[1]] * 3600 + clock[[2]] * 60 + clock[[3]]
    } else if (length(clock) == 2L) {
      seconds <- clock[[1]] * 60 + clock[[2]]
    } else {
      seconds <- clock[[1]]
    }
    days * 86400 + seconds
  }, numeric(1))
}

process_tree_snapshot <- function(root_pid, additional_pids = integer()) {
  output <- system2(
    "ps", c("-axo", "pid=,ppid=,rss=,time="), stdout = TRUE
  )
  process_table <- read.table(
    text = output,
    col.names = c("pid", "ppid", "rss_kb", "cpu_time"),
    colClasses = c("integer", "integer", "numeric", "character")
  )
  descendants <- unique(c(as.integer(root_pid), as.integer(additional_pids)))
  repeat {
    children <- process_table$pid[process_table$ppid %in% descendants]
    expanded <- sort(unique(c(descendants, children)))
    if (identical(expanded, sort(unique(descendants)))) break
    descendants <- expanded
  }
  selected <- process_table |>
    filter(pid %in% descendants)
  list(
    pids = selected$pid,
    rss_mb = sum(selected$rss_kb) / 1024,
    cpu_seconds = sum(parse_ps_cpu_seconds(selected$cpu_time))
  )
}

terminate_process_tree <- function(root_pid, additional_pids = integer()) {
  snapshot <- process_tree_snapshot(root_pid, additional_pids)
  for (pid in rev(snapshot$pids)) {
    try(tools::pskill(pid, signal = 15L), silent = TRUE)
  }
  Sys.sleep(5)
  remaining <- process_tree_snapshot(root_pid, additional_pids)$pids
  for (pid in rev(remaining)) {
    try(tools::pskill(pid, signal = 9L), silent = TRUE)
  }
  invisible(length(remaining) == 0L)
}

run_capped_parallel_benchmark <- function(worker_count) {
  ceiling_seconds <- 1800
  wall_started <- proc.time()[["elapsed"]]
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  worker_pid_path <- tempfile(
    pattern = "active_parallel_worker_pids-",
    tmpdir = cache_dir,
    fileext = ".rds"
  )
  job <- parallel::mcparallel(
    benchmark_full_league_parallel(worker_count, worker_pid_path),
    detached = FALSE,
    silent = FALSE
  )
  peak_rss_mb <- 0
  last_cpu_seconds <- 0
  next_report_seconds <- 60

  repeat {
    elapsed <- proc.time()[["elapsed"]] - wall_started
    worker_pids <- if (file.exists(worker_pid_path)) {
      tryCatch(readRDS(worker_pid_path), error = function(condition) integer())
    } else {
      integer()
    }
    snapshot <- process_tree_snapshot(job$pid, worker_pids)
    peak_rss_mb <- max(peak_rss_mb, snapshot$rss_mb)
    last_cpu_seconds <- max(last_cpu_seconds, snapshot$cpu_seconds)
    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      value <- collected[[1]]
      if (inherits(value, "try-error")) {
        stop("The capped parallel benchmark child failed: ", value, call. = FALSE)
      }
      result <- read_parquet(parallel_benchmark_path) |>
        as_tibble() |>
        mutate(
          watchdog_wall_elapsed_sec = elapsed,
          watchdog_last_process_tree_cpu_sec = last_cpu_seconds,
          watchdog_peak_process_tree_rss_mb = peak_rss_mb,
          watchdog_termination = "completed_before_ceiling"
        )
      write_atomic_parquet(result, parallel_benchmark_path)
      print(result, width = Inf)
      return(invisible(result))
    }
    if (elapsed >= ceiling_seconds) {
      terminate_process_tree(job$pid, worker_pids)
      parallel::mccollect(job, wait = FALSE)
      record_parallel_timeout(
        worker_count,
        elapsed,
        last_cpu_seconds,
        peak_rss_mb
      )
      return(invisible(NULL))
    }
    if (elapsed >= next_report_seconds) {
      message(
        "WATCHDOG elapsed_sec=", round(elapsed, 1),
        " process_tree_cpu_sec=", round(last_cpu_seconds, 1),
        " peak_process_tree_rss_mb=", round(peak_rss_mb, 1)
      )
      next_report_seconds <- next_report_seconds + 60
    }
    Sys.sleep(1)
  }
}

record_parallel_timeout <- function(worker_count, elapsed_seconds, cpu_seconds,
                                    peak_memory_mb) {
  inputs <- build_inputs("all318")
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "exact_nondiscrete_psock_cluster",
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    physical_cores = EXPECTED_PHYSICAL_CORES,
    logical_cores = EXPECTED_LOGICAL_CORES,
    worker_count = worker_count,
    completed = FALSE,
    timed_out = TRUE,
    runtime_ceiling_sec = 1800,
    setup_elapsed_sec = NA_real_,
    fit_elapsed_sec = NA_real_,
    prediction_elapsed_sec = NA_real_,
    total_wall_elapsed_sec = as.numeric(elapsed_seconds),
    parent_cpu_elapsed_sec = as.numeric(cpu_seconds),
    worker_cpu_elapsed_sec = NA_real_,
    total_cpu_elapsed_sec = NA_real_,
    cpu_measurement = paste(
      "watchdog-visible master CPU only; PSOCK worker CPU unavailable because",
      "macOS reparented workers during this timed-out run"
    ),
    peak_memory_mb = as.numeric(peak_memory_mb),
    memory_measurement = paste(
      "maximum sampled descendant RSS before worker reparenting; the value is",
      "an incomplete process-tree measurement afterward"
    ),
    players = EXPECTED_ALL_PLAYERS,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
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
  write_atomic_parquet(result, parallel_benchmark_path)
  print(result, width = Inf)
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
    player_ids = selected,
    metadata = metadata,
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

new_discrete_check_log <- function() {
  new.env(parent = emptyenv())
}

discrete_check <- function(log, check, condition, detail) {
  row <- tibble(
    check = check,
    passed = isTRUE(condition),
    detail = as.character(detail)
  )
  log$records <- c(log$records, list(row))
  if (!isTRUE(condition)) {
    stop("DISCRETE GAM SANITY CHECK FAILED: ", check, " — ", detail,
         call. = FALSE)
  }
  invisible(NULL)
}

save_new_atomic_rds <- function(object, path) {
  if (file.exists(path)) {
    stop("Refusing to replace an existing benchmark artifact: ", path,
         call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path)
  )
  saveRDS(object, temporary, compress = FALSE)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish benchmark artifact; partial preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

write_new_atomic_parquet <- function(table, path) {
  if (file.exists(path)) {
    stop("Refusing to replace an existing benchmark result: ", path,
         call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path),
    fileext = ".parquet"
  )
  write_parquet(table, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish benchmark result; partial preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

write_discrete_stage <- function(stage) {
  dir.create(discrete_cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(discrete_cache_dir, "stage_heartbeat.rds")
  temporary <- tempfile(pattern = "stage_heartbeat.rds.partial-",
                        tmpdir = discrete_cache_dir)
  saveRDS(
    list(
      stage = stage,
      timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      process_id = Sys.getpid()
    ),
    temporary
  )
  if (!file.rename(temporary, path)) {
    stop("Could not publish the atomic benchmark stage heartbeat", call. = FALSE)
  }
  invisible(path)
}

assign_fixed_grid <- function(shots, grid) {
  nx <- attr(grid, "nx")
  ny <- attr(grid, "ny")
  assigned <- shots |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L,
        nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L,
        ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    )
  if (any(!assigned$cell_id %in% grid$cell_id)) {
    stop("A metadata row failed fixed-grid assignment", call. = FALSE)
  }
  assigned
}

load_discrete_reference_evidence <- function() {
  if (!file.exists(discrete_path)) {
    stop("The completed 40-player exact-versus-discrete evidence is missing",
         call. = FALSE)
  }
  evidence <- read_parquet(discrete_path) |>
    as_tibble()
  valid <- nrow(evidence) == 1L &&
    identical(evidence$players[[1]], EXPECTED_FALLBACK_PLAYERS) &&
    identical(evidence$fitting_folds[[1]], paste(FITTING_FOLDS, collapse = ",")) &&
    identical(evidence$fold4_outcomes_read[[1]], FALSE) &&
    identical(evidence$fold5_outcomes_read[[1]], FALSE) &&
    identical(evidence$split_sha256[[1]], EXPECTED_SPLIT_SHA256) &&
    identical(evidence$fallback_sample_sha256[[1]], EXPECTED_SAMPLE_SHA256)
  if (!valid) {
    stop("The 40-player discrete evidence failed provenance checks", call. = FALSE)
  }
  evidence
}

prepare_discrete_full_inputs <- function(check_log) {
  setup_started <- proc.time()[["elapsed"]]
  inputs <- build_inputs("all318")
  reference <- load_discrete_reference_evidence()
  grid <- inputs$data$grid
  validation_metadata <- inputs$metadata |>
    filter(fold == 4L, PLAYER_ID %in% inputs$player_ids) |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  discrete_check(
    check_log, "exactly_318_eligible_players",
    inputs$players == EXPECTED_ALL_PLAYERS &&
      length(inputs$player_ids) == EXPECTED_ALL_PLAYERS,
    paste(inputs$players, "eligible players")
  )
  discrete_check(
    check_log, "fitting_outcomes_only_folds_1_to_3",
    identical(inputs$folds, paste(FITTING_FOLDS, collapse = ",")),
    paste("fitting folds", inputs$folds)
  )
  discrete_check(
    check_log, "fold4_metadata_has_no_outcome",
    nrow(validation_metadata) > 0L &&
      !"SHOT_MADE_FLAG" %in% names(validation_metadata),
    paste(nrow(validation_metadata), "fold-4 metadata rows; no outcome column")
  )
  discrete_check(
    check_log, "fold5_outcomes_sealed",
    !"SHOT_MADE_FLAG" %in% names(inputs$metadata),
    "full-season metadata contains no make/miss outcome column"
  )
  discrete_check(
    check_log, "fixed_four_foot_grid",
    nrow(grid) == GRID_CELLS && GRID_WIDTH == 40L,
    paste(nrow(grid), "cells at width", GRID_WIDTH)
  )
  validation_counts <- validation_metadata |>
    assign_fixed_grid(grid) |>
    count(PLAYER_ID, cell_id, name = "validation_attempts")
  lattice <- inputs$data$lattice |>
    left_join(validation_counts, by = c("PLAYER_ID", "cell_id")) |>
    mutate(validation_attempts = coalesce(as.integer(validation_attempts), 0L)) |>
    arrange(PLAYER_ID, cell_id)
  training_counts <- inputs$data$aggregated |>
    summarise(fitting_attempts = sum(attempts), .by = PLAYER_ID) |>
    right_join(tibble(PLAYER_ID = inputs$player_ids), by = "PLAYER_ID") |>
    arrange(fitting_attempts, PLAYER_ID)
  discrete_check(
    check_log, "every_player_has_fitting_attempts",
    !anyNA(training_counts$fitting_attempts) &&
      all(training_counts$fitting_attempts > 0L),
    paste(min(training_counts$fitting_attempts), "minimum fitting attempts")
  )
  sparse_players <- training_counts |>
    mutate(volume_quarter = ntile(row_number(), 4L)) |>
    filter(volume_quarter == 1L) |>
    arrange(PLAYER_ID)
  discrete_check(
    check_log, "sparse_player_definition",
    nrow(sparse_players) == 80L,
    "80 players in the bottom quarter by folds-1-to-3 attempts"
  )
  inputs$data$lattice <- lattice
  inputs$validation_metadata_rows <- nrow(validation_metadata)
  inputs$sparse_players <- sparse_players
  inputs$reference <- reference
  inputs$setup_elapsed_sec <- proc.time()[["elapsed"]] - setup_started
  inputs
}

minimum_discrete_surface_rmse <- function(centered_surface) {
  surface_matrix <- matrix(
    centered_surface,
    nrow = GRID_CELLS,
    ncol = EXPECTED_ALL_PLAYERS
  )
  distances <- as.matrix(dist(t(surface_matrix))) / sqrt(GRID_CELLS)
  distances[lower.tri(distances, diag = TRUE)] <- NA_real_
  min(distances, na.rm = TRUE)
}

simulate_discrete_totals <- function(probability_draws, attempts) {
  simulated <- matrix(
    rbinom(
      length(probability_draws),
      size = rep(as.integer(attempts), times = POSTERIOR_DRAWS),
      prob = as.vector(probability_draws)
    ),
    nrow = nrow(probability_draws),
    ncol = POSTERIOR_DRAWS
  )
  colSums(simulated)
}

fit_full_league_discrete_gam <- function(inputs, check_log) {
  formula <- gam_formula("aggregated")
  expected_formula <- paste(
    deparse(gam_formula("aggregated")), collapse = " "
  )
  write_discrete_stage("fitting_discrete_gam")
  fit_started <- proc.time()[["elapsed"]]
  captured <- capture_conditions(mgcv::bam(
    formula,
    family = binomial(link = "logit"),
    data = inputs$data$aggregated,
    method = "fREML",
    discrete = TRUE,
    select = FALSE,
    gamma = 1,
    nthreads = MODEL_THREADS,
    na.action = na.fail
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  fit <- captured$value
  edf <- smooth_edf(fit)
  discrete_check(
    check_log, "gam_formula_unchanged",
    paste(deparse(fit$formula), collapse = " ") == expected_formula,
    expected_formula
  )
  discrete_check(
    check_log, "discrete_amendment_active",
    isTRUE(fit$dinfo$para.discrete),
    "mgcv fit records para.discrete = TRUE"
  )
  discrete_check(
    check_log, "gam_converged",
    isTRUE(fit$converged),
    paste("converged =", fit$converged)
  )
  discrete_check(
    check_log, "gam_finite_coefficients",
    all(is.finite(coef(fit))),
    paste(length(coef(fit)), "finite coefficients")
  )
  discrete_check(
    check_log, "gam_coefficient_count",
    length(coef(fit)) == EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    paste(length(coef(fit)), "coefficients")
  )
  discrete_check(
    check_log, "gam_one_shared_smoothing_parameter",
    length(fit$sp) == 1L,
    paste(length(fit$sp), "smoothing parameter")
  )
  discrete_check(
    check_log, "gam_one_smooth_per_player",
    length(fit$smooth) == EXPECTED_ALL_PLAYERS,
    paste(length(fit$smooth), "player-specific smooths")
  )
  discrete_check(
    check_log, "gam_basis_ceiling_not_exhausted",
    all(edf < 0.95 * (GAM_BASIS_SIZE - 1L)),
    paste("maximum smooth EDF", format(max(edf), digits = 10))
  )

  write_discrete_stage("drawing_and_predicting_full_lattice")
  prediction_started <- proc.time()[["elapsed"]]
  covariance <- vcov(fit, unconditional = TRUE)
  discrete_check(
    check_log, "gam_finite_unconditional_covariance",
    all(is.finite(covariance)),
    paste(nrow(covariance), "by", ncol(covariance), "finite covariance")
  )
  set_frozen_rng(GAM_DRAW_SEED)
  coefficient_draws <- mgcv::rmvn(
    POSTERIOR_DRAWS,
    mu = coef(fit),
    V = covariance
  )
  player_levels <- levels(inputs$data$lattice$player_factor)
  probabilities <- numeric(nrow(inputs$data$lattice))
  centered_links <- numeric(nrow(inputs$data$lattice))
  sparse_draws <- vector("list", nrow(inputs$sparse_players))
  names(sparse_draws) <- as.character(inputs$sparse_players$PLAYER_ID)
  for (player_position in seq_along(player_levels)) {
    player_level <- player_levels[[player_position]]
    rows <- which(inputs$data$lattice$player_factor == player_level)
    player_lattice <- inputs$data$lattice[rows, ]
    design <- predict(
      fit,
      newdata = player_lattice,
      type = "lpmatrix",
      discrete = TRUE
    )
    active <- which(colSums(abs(design)) > 0)
    eta_draws <- design[, active, drop = FALSE] %*%
      t(coefficient_draws[, active, drop = FALSE])
    probability_draws <- plogis(eta_draws)
    probabilities[rows] <- rowMeans(probability_draws)
    plugin_link <- as.numeric(
      design[, active, drop = FALSE] %*% coef(fit)[active]
    )
    centered_links[rows] <- plugin_link - mean(plugin_link)
    sparse_name <- as.character(player_level)
    if (sparse_name %in% names(sparse_draws)) {
      used <- player_lattice$validation_attempts > 0L
      sparse_draws[[sparse_name]] <- list(
        probabilities = probability_draws[used, , drop = FALSE],
        attempts = player_lattice$validation_attempts[used]
      )
    }
  }
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started
  discrete_check(
    check_log, "gam_finite_predictions",
    all(is.finite(probabilities)),
    paste(length(probabilities), "finite draw-averaged probabilities")
  )
  discrete_check(
    check_log, "gam_probability_bounds",
    all(probabilities >= 0 & probabilities <= 1),
    paste("range", paste(range(probabilities), collapse = " to "))
  )
  minimum_rmse <- minimum_discrete_surface_rmse(centered_links)
  discrete_check(
    check_log, "gam_distinct_player_surfaces",
    is.finite(minimum_rmse) && minimum_rmse > SURFACE_TOLERANCE,
    paste("minimum centered-surface RMSE", format(minimum_rmse, digits = 10))
  )

  write_discrete_stage("simulating_sparse_player_uncertainty")
  uncertainty_started <- proc.time()[["elapsed"]]
  set_frozen_rng(PREDICTIVE_SEED)
  sparse_intervals <- lapply(names(sparse_draws), function(player_id) {
    values <- sparse_draws[[player_id]]
    if (is.null(values) || nrow(values$probabilities) == 0L) {
      stop("A sparse player has no fold-4 metadata support", call. = FALSE)
    }
    total_draws <- simulate_discrete_totals(
      values$probabilities,
      values$attempts
    )
    tibble(
      PLAYER_ID = as.integer(player_id),
      validation_attempts = sum(values$attempts),
      interval_lower = as.numeric(quantile(total_draws, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(total_draws, 0.95, names = FALSE))
    ) |>
      mutate(interval_width = interval_upper - interval_lower)
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID)
  uncertainty_elapsed <- proc.time()[["elapsed"]] - uncertainty_started
  discrete_check(
    check_log, "gam_sparse_uncertainty_dimensions",
    nrow(sparse_intervals) == 80L &&
      n_distinct(sparse_intervals$PLAYER_ID) == 80L,
    paste(nrow(sparse_intervals), "sparse-player intervals")
  )
  discrete_check(
    check_log, "gam_sparse_uncertainty_finite_ordered",
    all(is.finite(sparse_intervals$interval_lower)) &&
      all(is.finite(sparse_intervals$interval_upper)) &&
      all(is.finite(sparse_intervals$interval_width)) &&
      all(sparse_intervals$interval_lower >= 0) &&
      all(sparse_intervals$interval_lower <= sparse_intervals$interval_upper) &&
      all(sparse_intervals$interval_upper <= sparse_intervals$validation_attempts),
    "all 90% posterior-predictive intervals are finite, ordered, and feasible"
  )
  checks <- bind_rows(check_log$records)
  discrete_check(
    check_log, "all_applicable_checks_passed",
    all(checks$passed),
    paste(nrow(checks), "prior checks passed")
  )
  checks <- bind_rows(check_log$records)

  write_discrete_stage("all_checks_passed_serializing_fit")
  fit_path <- file.path(discrete_cache_dir, "gam_discrete_grid_40_fit.rds")
  model_object_bytes <- as.numeric(object.size(fit))
  save_new_atomic_rds(fit, fit_path)
  metrics <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_discrete_approximation",
    specification_id = "frozen-gam-grid40-discrete-computation-v1",
    formula = expected_formula,
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = TRUE,
    timed_out = FALSE,
    failed = FALSE,
    runtime_ceiling_sec = DISCRETE_RUNTIME_CEILING_SEC,
    setup_elapsed_sec = inputs$setup_elapsed_sec,
    fit_elapsed_sec = fit_elapsed,
    prediction_elapsed_sec = prediction_elapsed,
    uncertainty_elapsed_sec = uncertainty_elapsed,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = length(coef(fit)),
    smooth_count = length(fit$smooth),
    basis_size = GAM_BASIS_SIZE,
    smoothing_parameter_count = length(fit$sp),
    smoothing_parameter = unname(fit$sp),
    maximum_smooth_edf = max(edf),
    minimum_centered_surface_rmse = minimum_rmse,
    minimum_probability = min(probabilities),
    maximum_probability = max(probabilities),
    posterior_draws = POSTERIOR_DRAWS,
    gam_draw_seed = GAM_DRAW_SEED,
    predictive_seed = PREDICTIVE_SEED,
    model_object_bytes = model_object_bytes,
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    message_count = length(captured$messages),
    messages = paste(captured$messages, collapse = " | "),
    r_version = as.character(getRversion()),
    mgcv_version = as.character(packageVersion("mgcv")),
    arrow_version = as.character(packageVersion("arrow")),
    dplyr_version = as.character(packageVersion("dplyr")),
    tidyr_version = as.character(packageVersion("tidyr")),
    split_sha256 = EXPECTED_SPLIT_SHA256
  )
  rm(coefficient_draws, covariance, sparse_draws, fit)
  gc()
  list(
    metrics = metrics,
    probabilities = tibble(
      PLAYER_ID = inputs$data$lattice$PLAYER_ID,
      cell_id = inputs$data$lattice$cell_id,
      probability = probabilities
    ),
    sparse_intervals = sparse_intervals,
    checks = checks
  )
}

discrete_result_paths <- function() {
  file.path(
    discrete_result_dir,
    c(
      "benchmark_metrics.parquet", "uncertainty_summary.parquet",
      "sanity_checks.parquet", "exact_discrete_reference.parquet",
      "environment_notices.parquet"
    )
  )
}

write_discrete_results <- function(result, reference) {
  paths <- discrete_result_paths()
  uncertainty_summary <- result$sparse_intervals |>
    summarise(
      sparse_player_count = n(),
      minimum_interval_width = min(interval_width),
      mean_interval_width = mean(interval_width),
      maximum_interval_width = max(interval_width),
      all_intervals_finite_ordered_feasible = TRUE
    ) |>
    mutate(
      season = season,
      scope = "all_318_eligible_players_training_only",
      method = "aggregated_discrete_approximation",
      grid_width = GRID_WIDTH,
      fold4_outcomes_read = FALSE,
      fold5_outcomes_read = FALSE,
      .before = 1
    )
  checks <- result$checks |>
    mutate(
      season = season,
      scope = "all_318_eligible_players_training_only",
      method = "aggregated_discrete_approximation",
      grid_width = GRID_WIDTH,
      fold4_outcomes_read = FALSE,
      fold5_outcomes_read = FALSE,
      .before = 1
    )
  reference_summary <- reference |>
    transmute(
      season,
      scope,
      comparison = "40-player exact versus discrete training-only evidence",
      grid_width,
      fitting_folds,
      fold4_outcomes_read,
      fold5_outcomes_read,
      players,
      training_shots,
      observed_player_cells,
      exact_fit_elapsed_sec,
      discrete_fit_elapsed_sec,
      maximum_observed_probability_difference,
      maximum_lattice_probability_difference,
      mean_lattice_probability_difference,
      maximum_draw_probability_difference,
      absolute_log_smoothing_parameter_difference,
      maximum_smooth_edf_difference,
      observed_probability_tolerance,
      lattice_probability_tolerance,
      mean_probability_tolerance,
      log_smoothing_parameter_tolerance,
      edf_tolerance,
      passed,
      split_sha256,
      fallback_sample_sha256
    )
  environment_notices <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    severity = "compatibility_warning",
    source = "arrow package startup",
    notice = paste(
      "arrow was built under R 4.6.1 while the frozen runtime is R 4.6.0;",
      "Arrow operations and every benchmark check completed successfully"
    ),
    package_build = packageDescription("arrow")$Built,
    model_warning_count = result$metrics$warning_count,
    model_message_count = result$metrics$message_count,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE
  )
  tables <- list(
    result$metrics,
    uncertainty_summary,
    checks,
    reference_summary,
    environment_notices
  )
  for (index in seq_along(paths)) {
    write_new_atomic_parquet(tables[[index]], paths[[index]])
  }
}

save_discrete_completion <- function(result) {
  if (!all(result$checks$passed)) {
    stop("Refusing to publish completion before every check passes",
         call. = FALSE)
  }
  fit_path <- file.path(discrete_cache_dir, "gam_discrete_grid_40_fit.rds")
  if (!file.exists(fit_path) ||
      !identical(
        unname(tools::md5sum(fit_path)),
        result$metrics$serialized_model_md5[[1]]
      )) {
    stop("The discrete fit artifact is missing or has the wrong hash",
         call. = FALSE)
  }
  checkpoint <- list(
    complete = TRUE,
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_discrete_approximation",
    specification_id = "frozen-gam-grid40-discrete-computation-v1",
    split_sha256 = EXPECTED_SPLIT_SHA256,
    player_count = EXPECTED_ALL_PLAYERS,
    grid_width = GRID_WIDTH,
    fit_md5 = result$metrics$serialized_model_md5[[1]],
    result = result
  )
  save_new_atomic_rds(
    checkpoint,
    file.path(discrete_cache_dir, "benchmark_complete_checkpoint.rds")
  )
}

load_discrete_completion <- function() {
  checkpoint_path <- file.path(
    discrete_cache_dir, "benchmark_complete_checkpoint.rds"
  )
  if (!file.exists(checkpoint_path)) return(NULL)
  checkpoint <- tryCatch(
    readRDS(checkpoint_path),
    error = function(condition) {
      stop("Existing discrete benchmark checkpoint is unreadable and was preserved: ",
           conditionMessage(condition), call. = FALSE)
    }
  )
  fit_path <- file.path(discrete_cache_dir, "gam_discrete_grid_40_fit.rds")
  valid <- is.list(checkpoint) &&
    isTRUE(checkpoint$complete) &&
    identical(checkpoint$season, season) &&
    identical(checkpoint$scope, "all_318_eligible_players_training_only") &&
    identical(checkpoint$method, "aggregated_discrete_approximation") &&
    identical(
      checkpoint$specification_id,
      "frozen-gam-grid40-discrete-computation-v1"
    ) &&
    identical(checkpoint$split_sha256, EXPECTED_SPLIT_SHA256) &&
    identical(checkpoint$player_count, EXPECTED_ALL_PLAYERS) &&
    identical(checkpoint$grid_width, GRID_WIDTH) &&
    nrow(checkpoint$result$probabilities) == EXPECTED_ALL_PLAYERS * GRID_CELLS &&
    nrow(checkpoint$result$sparse_intervals) == 80L &&
    nrow(checkpoint$result$metrics) == 1L &&
    isTRUE(checkpoint$result$metrics$completed[[1]]) &&
    all(checkpoint$result$checks$passed) &&
    file.exists(fit_path) &&
    identical(checkpoint$fit_md5, unname(tools::md5sum(fit_path))) &&
    all(file.exists(discrete_result_paths()))
  if (!valid) {
    stop("Existing discrete benchmark checkpoint is inconsistent; artifacts were preserved",
         call. = FALSE)
  }
  checkpoint
}

acquire_discrete_lock <- function() {
  dir.create(discrete_cache_dir, recursive = TRUE, showWarnings = FALSE)
  lock_path <- file.path(discrete_cache_dir, "active_run.lock")
  if (!dir.create(lock_path, recursive = FALSE, showWarnings = FALSE)) {
    owner <- tryCatch(
      readRDS(file.path(lock_path, "owner.rds")),
      error = function(condition) NULL
    )
    owner_pids <- if (is.null(owner)) integer() else {
      unique(as.integer(c(owner$parent_pid, owner$child_pid)))
    }
    active <- vapply(owner_pids, function(pid) {
      length(system2("ps", c("-p", pid, "-o", "pid="), stdout = TRUE)) > 0L
    }, logical(1))
    if (any(active)) {
      stop("DUPLICATE RUN SAFEGUARD: a discrete GAM benchmark is active",
           call. = FALSE)
    }
    stop(
      "A stale discrete GAM run lock was preserved; inspect it before restarting",
      call. = FALSE
    )
  }
  owner <- list(
    parent_pid = Sys.getpid(),
    child_pid = NA_integer_,
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    season = season,
    mode = mode
  )
  saveRDS(owner, file.path(lock_path, "owner.rds"))
  list(path = lock_path, owner = owner)
}

update_discrete_lock <- function(lock, child_pid) {
  lock$owner$child_pid <- as.integer(child_pid)
  temporary <- tempfile(pattern = "owner.rds.partial-", tmpdir = lock$path)
  saveRDS(lock$owner, temporary)
  if (!file.rename(temporary, file.path(lock$path, "owner.rds"))) {
    stop("Could not atomically update the discrete benchmark lock",
         call. = FALSE)
  }
  lock
}

release_discrete_lock <- function(lock) {
  owner <- tryCatch(
    readRDS(file.path(lock$path, "owner.rds")),
    error = function(condition) NULL
  )
  if (!is.null(owner) && identical(owner$parent_pid, Sys.getpid())) {
    unlink(lock$path, recursive = TRUE)
  }
  invisible(NULL)
}

discrete_process_tree_snapshot <- function(root_pid, additional_pids = integer()) {
  output <- system2(
    "ps", c("-axo", "pid=,ppid=,rss=,time="), stdout = TRUE
  )
  process_table <- read.table(
    text = output,
    col.names = c("pid", "ppid", "rss_kb", "cpu_time"),
    colClasses = c("integer", "integer", "numeric", "character")
  )
  descendants <- unique(as.integer(c(root_pid, additional_pids)))
  repeat {
    children <- process_table$pid[process_table$ppid %in% descendants]
    expanded <- sort(unique(c(descendants, children)))
    if (identical(expanded, sort(unique(descendants)))) break
    descendants <- expanded
  }
  selected <- process_table |>
    filter(pid %in% descendants)
  list(
    pids = selected$pid,
    rss_mb = sum(selected$rss_kb) / 1024,
    cpu_seconds = setNames(
      parse_ps_cpu_seconds(selected$cpu_time),
      as.character(selected$pid)
    )
  )
}

terminate_discrete_worker <- function(worker_pid) {
  snapshot <- discrete_process_tree_snapshot(worker_pid)
  for (pid in rev(snapshot$pids)) {
    try(tools::pskill(pid, signal = 15L), silent = TRUE)
  }
  Sys.sleep(5)
  remaining <- discrete_process_tree_snapshot(worker_pid)$pids
  for (pid in rev(remaining)) {
    try(tools::pskill(pid, signal = 9L), silent = TRUE)
  }
  Sys.sleep(1)
  discrete_process_tree_snapshot(worker_pid)$pids
}

write_discrete_failure <- function(inputs, elapsed, cpu_seconds, peak_rss_mb,
                                   failure, timed_out) {
  stage_path <- file.path(discrete_cache_dir, "stage_heartbeat.rds")
  last_stage <- if (file.exists(stage_path)) {
    tryCatch(
      readRDS(stage_path)$stage,
      error = function(condition) "unreadable_stage_heartbeat"
    )
  } else {
    "unknown_no_stage_heartbeat"
  }
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_discrete_approximation",
    specification_id = "frozen-gam-grid40-discrete-computation-v1",
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = FALSE,
    timed_out = timed_out,
    failed = !timed_out,
    failure = failure,
    last_confirmed_stage = last_stage,
    runtime_ceiling_sec = DISCRETE_RUNTIME_CEILING_SEC,
    setup_elapsed_sec = inputs$setup_elapsed_sec,
    fit_elapsed_sec = NA_real_,
    prediction_elapsed_sec = NA_real_,
    uncertainty_elapsed_sec = NA_real_,
    total_wall_elapsed_sec = as.numeric(elapsed),
    approximate_process_tree_cpu_sec = as.numeric(cpu_seconds),
    approximate_peak_process_tree_rss_mb = as.numeric(peak_rss_mb),
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    smooth_count = EXPECTED_ALL_PLAYERS,
    basis_size = GAM_BASIS_SIZE,
    smoothing_parameter_count = 1L,
    smoothing_parameter = NA_real_,
    posterior_draws = POSTERIOR_DRAWS,
    gam_draw_seed = GAM_DRAW_SEED,
    predictive_seed = PREDICTIVE_SEED,
    model_object_bytes = NA_real_,
    serialized_model_bytes = NA_real_,
    serialized_model_md5 = NA_character_,
    warning_count = NA_integer_,
    warnings = failure,
    r_version = as.character(getRversion()),
    mgcv_version = as.character(packageVersion("mgcv")),
    arrow_version = as.character(packageVersion("arrow")),
    dplyr_version = as.character(packageVersion("dplyr")),
    tidyr_version = as.character(packageVersion("tidyr")),
    split_sha256 = EXPECTED_SPLIT_SHA256
  )
  write_new_atomic_parquet(
    result,
    file.path(discrete_result_dir, "benchmark_metrics.parquet")
  )
  result
}

write_discrete_termination_status <- function(elapsed, immediate_visible,
                                              final_active) {
  status <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_discrete_approximation",
    total_wall_elapsed_sec = as.numeric(elapsed),
    visible_processes_immediately_after_termination = as.integer(immediate_visible),
    active_benchmark_processes_after_followup = as.integer(final_active),
    fit_artifact_exists = file.exists(
      file.path(discrete_cache_dir, "gam_discrete_grid_40_fit.rds")
    ),
    completion_checkpoint_exists = file.exists(
      file.path(discrete_cache_dir, "benchmark_complete_checkpoint.rds")
    ),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE
  )
  write_new_atomic_parquet(
    status,
    file.path(discrete_result_dir, "termination_status.parquet")
  )
  status
}

audit_discrete_full_league <- function() {
  check_log <- new_discrete_check_log()
  inputs <- prepare_discrete_full_inputs(check_log)
  audit <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_discrete_approximation",
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    smooth_count = EXPECTED_ALL_PLAYERS,
    sparse_players = nrow(inputs$sparse_players),
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    reference_40_player_equivalence_passed = inputs$reference$passed[[1]],
    frozen_preflight_checks_passed = all(bind_rows(check_log$records)$passed),
    split_sha256 = inputs$split_sha256
  )
  print(audit, width = Inf)
  invisible(audit)
}

run_capped_discrete_full_league <- function() {
  completed <- load_discrete_completion()
  if (!is.null(completed)) {
    message("Reusing verified completed full-league discrete GAM benchmark")
    print(completed$result$metrics, width = Inf)
    return(invisible(completed))
  }
  existing_files <- c(
    file.path(discrete_cache_dir, "gam_discrete_grid_40_fit.rds"),
    list.files(
      discrete_cache_dir,
      pattern = "partial|checkpoint|stage",
      full.names = TRUE
    ),
    if (dir.exists(discrete_result_dir)) {
      list.files(discrete_result_dir, full.names = TRUE)
    } else {
      character()
    }
  )
  if (any(file.exists(existing_files))) {
    stop(
      "Incomplete discrete benchmark artifacts were preserved; inspect before restarting",
      call. = FALSE
    )
  }

  wall_started <- proc.time()[["elapsed"]]
  check_log <- new_discrete_check_log()
  inputs <- prepare_discrete_full_inputs(check_log)
  lock <- acquire_discrete_lock()
  on.exit(release_discrete_lock(lock), add = TRUE)
  job <- parallel::mcparallel(
    fit_full_league_discrete_gam(inputs, check_log),
    detached = FALSE,
    silent = FALSE
  )
  lock <- update_discrete_lock(lock, job$pid)
  peak_rss_mb <- 0
  cpu_by_pid <- numeric()
  next_report_seconds <- 60

  repeat {
    elapsed <- proc.time()[["elapsed"]] - wall_started
    snapshot <- discrete_process_tree_snapshot(Sys.getpid())
    peak_rss_mb <- max(peak_rss_mb, snapshot$rss_mb)
    if (length(snapshot$cpu_seconds) > 0L) {
      for (pid in names(snapshot$cpu_seconds)) {
        previous <- unname(cpu_by_pid[pid])
        if (length(previous) == 0L || is.na(previous)) previous <- 0
        cpu_by_pid[pid] <- max(previous, snapshot$cpu_seconds[[pid]])
      }
    }
    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      value <- collected[[1]]
      total_cpu <- sum(cpu_by_pid, na.rm = TRUE)
      if (inherits(value, "try-error")) {
        failure <- paste("discrete GAM benchmark child failed:", value)
        result <- write_discrete_failure(
          inputs, elapsed, total_cpu, peak_rss_mb, failure, FALSE
        )
        print(result, width = Inf)
        stop(failure, call. = FALSE)
      }
      value$metrics <- value$metrics |>
        mutate(
          total_wall_elapsed_sec = elapsed,
          approximate_process_tree_cpu_sec = total_cpu,
          approximate_peak_process_tree_rss_mb = peak_rss_mb,
          cpu_measurement = paste(
            "sum of maximum one-second sampled CPU time for each visible",
            "R process-tree PID"
          ),
          memory_measurement = paste(
            "maximum one-second sampled resident memory across the parent",
            "R process and its visible descendants"
          )
        )
      write_discrete_results(value, inputs$reference)
      save_discrete_completion(value)
      print(value$metrics, width = Inf)
      return(invisible(value))
    }
    if (elapsed >= DISCRETE_RUNTIME_CEILING_SEC) {
      remaining <- terminate_discrete_worker(job$pid)
      parallel::mccollect(job, wait = FALSE)
      Sys.sleep(1)
      final_active <- length(discrete_process_tree_snapshot(job$pid)$pids)
      result <- write_discrete_failure(
        inputs,
        elapsed,
        sum(cpu_by_pid, na.rm = TRUE),
        peak_rss_mb,
        "wall-time ceiling reached",
        TRUE
      )
      termination <- write_discrete_termination_status(
        elapsed,
        length(remaining),
        final_active
      )
      print(result, width = Inf)
      print(termination, width = Inf)
      return(invisible(result))
    }
    if (elapsed >= next_report_seconds) {
      message(
        "WATCHDOG elapsed_sec=", round(elapsed, 1),
        " approximate_cpu_sec=", round(sum(cpu_by_pid, na.rm = TRUE), 1),
        " peak_rss_mb=", round(peak_rss_mb, 1)
      )
      next_report_seconds <- (floor(elapsed / 60) + 1) * 60
    }
    Sys.sleep(1)
  }
}

# Recoverable, no-timeout runner for the frozen exact full-league GAM. The
# statistical model below deliberately mirrors fit_full_league_discrete_gam();
# only discrete=FALSE and the already-verified two-worker PSOCK cluster differ.
new_exact_check_log <- function() {
  new.env(parent = emptyenv())
}

exact_check <- function(log, check, condition, detail) {
  row <- tibble(
    check = check,
    passed = isTRUE(condition),
    detail = as.character(detail)
  )
  log$records <- c(log$records, list(row))
  if (!isTRUE(condition)) {
    stop("EXACT GAM SANITY CHECK FAILED: ", check, " — ", detail,
         call. = FALSE)
  }
  invisible(NULL)
}

write_exact_stage <- function(stage) {
  dir.create(exact_long_cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(exact_long_cache_dir, "stage_heartbeat.rds")
  temporary <- tempfile(pattern = "stage_heartbeat.rds.partial-",
                        tmpdir = exact_long_cache_dir)
  saveRDS(
    list(
      stage = stage,
      timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      process_id = Sys.getpid()
    ),
    temporary
  )
  if (!file.rename(temporary, path)) {
    stop("Could not publish the exact-run stage heartbeat", call. = FALSE)
  }
  invisible(path)
}

write_exact_metadata <- function(metadata) {
  dir.create(exact_long_cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(exact_long_cache_dir, "pid_metadata.rds")
  temporary <- tempfile(pattern = "pid_metadata.rds.partial-",
                        tmpdir = exact_long_cache_dir)
  saveRDS(metadata, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish exact-run PID metadata", call. = FALSE)
  }
  invisible(path)
}

exact_log_event <- function(...) {
  dir.create(exact_long_cache_dir, recursive = TRUE, showWarnings = FALSE)
  line <- paste0(
    format(Sys.time(), tz = "UTC", usetz = TRUE), " ", paste0(..., collapse = "")
  )
  cat(line, "\n", file = file.path(exact_long_cache_dir, "run_events.log"),
      append = TRUE)
  message(line)
  flush.console()
}

disk_free_gib <- function(path) {
  output <- system2("df", c("-Pk", path), stdout = TRUE)
  if (length(output) < 2L) {
    stop("Could not measure free disk space", call. = FALSE)
  }
  fields <- strsplit(trimws(tail(output, 1L)), "[[:space:]]+")[[1]]
  if (length(fields) < 4L || !is.finite(as.numeric(fields[[4]]))) {
    stop("Could not parse free disk space", call. = FALSE)
  }
  as.numeric(fields[[4]]) / 1024^2
}

parent_pid <- function(pid = Sys.getpid()) {
  output <- system2("ps", c("-p", as.integer(pid), "-o", "ppid="), stdout = TRUE)
  value <- suppressWarnings(as.integer(trimws(output[[1]])))
  if (length(value) != 1L || is.na(value)) {
    stop("Could not determine the process parent", call. = FALSE)
  }
  value
}

process_command <- function(pid) {
  output <- system2(
    "ps", c("-p", as.integer(pid), "-o", "command="), stdout = TRUE
  )
  paste(output, collapse = " ")
}

verify_caffeinate_guard <- function() {
  pid <- suppressWarnings(as.integer(Sys.getenv("SPATIAL_EXACT_CAFFEINATE_PID")))
  if (length(pid) != 1L || is.na(pid)) {
    stop(
      "SLEEP-PREVENTION SAFEGUARD: use R/run_spatial_exact_gam_long.sh",
      call. = FALSE
    )
  }
  command <- process_command(pid)
  expected_wait <- paste0("-w ", Sys.getpid(), "([[:space:]]|$)")
  if (!grepl("(^|/)caffeinate([[:space:]]|$)", command) ||
      !grepl(expected_wait, command)) {
    stop("SLEEP-PREVENTION SAFEGUARD: caffeinate guard is absent or mismatched",
         call. = FALSE)
  }
  list(pid = pid, command = command)
}

prepare_exact_full_inputs <- function(check_log, write_signature = FALSE) {
  inputs <- prepare_discrete_full_inputs(check_log)
  exact_check(
    check_log, "frozen_training_shot_count",
    inputs$training_shots == 116955L,
    paste(inputs$training_shots, "folds-1-to-3 shots")
  )
  exact_check(
    check_log, "frozen_observed_player_cell_count",
    nrow(inputs$data$aggregated) == 19475L,
    paste(nrow(inputs$data$aggregated), "observed player-cells")
  )
  exact_check(
    check_log, "frozen_lattice_dimensions",
    nrow(inputs$data$lattice) == EXPECTED_ALL_PLAYERS * GRID_CELLS,
    paste(nrow(inputs$data$lattice), "player-cell lattice rows")
  )
  signature <- list(
    season = season,
    split_sha256 = inputs$split_sha256,
    player_ids = inputs$player_ids,
    aggregated = inputs$data$aggregated,
    lattice = select(
      inputs$data$lattice, PLAYER_ID, cell_id, x_ft, y_ft, player_factor,
      validation_attempts
    )
  )
  signature_path <- file.path(exact_long_cache_dir, "input_signature.rds")
  if (write_signature) {
    save_new_atomic_rds(signature, signature_path)
  } else {
    temporary <- tempfile(fileext = ".rds")
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(signature, temporary, compress = FALSE)
    signature_path <- temporary
  }
  inputs$input_sha256 <- sha256_file(signature_path)
  inputs
}

acquire_exact_lock <- function() {
  dir.create(exact_long_cache_dir, recursive = TRUE, showWarnings = FALSE)
  lock_path <- file.path(exact_long_cache_dir, "active_run.lock")
  if (!dir.create(lock_path, recursive = FALSE, showWarnings = FALSE)) {
    owner <- tryCatch(
      readRDS(file.path(lock_path, "owner.rds")),
      error = function(condition) NULL
    )
    owner_pids <- if (is.null(owner)) integer() else {
      unique(as.integer(c(owner$runner_pid, owner$model_pid, owner$worker_pids)))
    }
    active <- vapply(owner_pids, function(pid) {
      length(system2("ps", c("-p", pid, "-o", "pid="), stdout = TRUE)) > 0L
    }, logical(1))
    if (any(active)) {
      stop("DUPLICATE RUN SAFEGUARD: an exact GAM run is active", call. = FALSE)
    }
    stop("A stale exact GAM lock was preserved; inspect it before any restart",
         call. = FALSE)
  }
  owner <- list(
    runner_pid = Sys.getpid(), model_pid = NA_integer_, worker_pids = integer(),
    started_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    season = season, mode = mode
  )
  saveRDS(owner, file.path(lock_path, "owner.rds"))
  list(path = lock_path, owner = owner)
}

update_exact_lock <- function(lock, model_pid = NULL, worker_pids = NULL) {
  if (!is.null(model_pid)) lock$owner$model_pid <- as.integer(model_pid)
  if (!is.null(worker_pids)) lock$owner$worker_pids <- as.integer(worker_pids)
  temporary <- tempfile(pattern = "owner.rds.partial-", tmpdir = lock$path)
  saveRDS(lock$owner, temporary)
  if (!file.rename(temporary, file.path(lock$path, "owner.rds"))) {
    stop("Could not atomically update the exact-run lock", call. = FALSE)
  }
  lock
}

release_exact_lock <- function(lock) {
  owner <- tryCatch(
    readRDS(file.path(lock$path, "owner.rds")),
    error = function(condition) NULL
  )
  if (!is.null(owner) && identical(owner$runner_pid, Sys.getpid())) {
    unlink(lock$path, recursive = TRUE)
  }
  invisible(NULL)
}

fit_full_league_exact_gam <- function(inputs, check_log) {
  formula <- gam_formula("aggregated")
  expected_formula <- paste(deparse(formula), collapse = " ")
  worker_pid_path <- file.path(exact_long_cache_dir, "psock_worker_pids.rds")
  write_exact_stage("creating_two_worker_psock_cluster")
  cluster <- parallel::makeCluster(EXACT_LONG_WORKERS, type = "PSOCK")
  cluster_stopped <- FALSE
  on.exit({
    if (!cluster_stopped) parallel::stopCluster(cluster)
  }, add = TRUE)
  worker_pids <- as.integer(unlist(parallel::clusterCall(cluster, Sys.getpid)))
  save_new_atomic_rds(worker_pids, worker_pid_path)

  write_exact_stage("fitting_exact_gam")
  fit_started <- proc.time()[["elapsed"]]
  fit_cpu_started <- process_cpu_seconds()
  captured <- capture_conditions(mgcv::bam(
    formula,
    family = binomial(link = "logit"),
    data = inputs$data$aggregated,
    method = "fREML",
    discrete = FALSE,
    select = FALSE,
    gamma = 1,
    nthreads = MODEL_THREADS,
    cluster = cluster,
    na.action = na.fail
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  fit_child_cpu <- process_cpu_seconds() - fit_cpu_started
  fit <- captured$value
  parallel::stopCluster(cluster)
  cluster_stopped <- TRUE
  write_exact_stage("exact_fit_returned_workers_stopped")

  edf <- smooth_edf(fit)
  exact_check(
    check_log, "gam_formula_unchanged",
    paste(deparse(fit$formula), collapse = " ") == expected_formula,
    expected_formula
  )
  exact_check(
    check_log, "exact_nondiscrete_computation",
    !isTRUE(fit$dinfo$para.discrete),
    "mgcv fit is not discrete"
  )
  exact_check(
    check_log, "two_worker_psock_structure",
    length(worker_pids) == EXACT_LONG_WORKERS &&
      length(unique(worker_pids)) == EXACT_LONG_WORKERS,
    paste(worker_pids, collapse = ",")
  )
  exact_check(
    check_log, "gam_converged", isTRUE(fit$converged),
    paste("converged =", fit$converged)
  )
  exact_check(
    check_log, "gam_no_model_warnings", length(captured$warnings) == 0L,
    if (length(captured$warnings)) paste(captured$warnings, collapse = " | ") else "none"
  )
  exact_check(
    check_log, "gam_finite_coefficients", all(is.finite(coef(fit))),
    paste(length(coef(fit)), "finite coefficients")
  )
  exact_check(
    check_log, "gam_coefficient_count",
    length(coef(fit)) == EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    paste(length(coef(fit)), "coefficients")
  )
  exact_check(
    check_log, "gam_one_shared_smoothing_parameter", length(fit$sp) == 1L,
    paste(length(fit$sp), "smoothing parameter")
  )
  exact_check(
    check_log, "gam_one_smooth_per_player",
    length(fit$smooth) == EXPECTED_ALL_PLAYERS,
    paste(length(fit$smooth), "player-specific smooths")
  )
  exact_check(
    check_log, "gam_basis_ceiling_not_exhausted",
    all(edf < 0.95 * (GAM_BASIS_SIZE - 1L)),
    paste("maximum smooth EDF", format(max(edf), digits = 10))
  )

  write_exact_stage("drawing_and_predicting_full_lattice")
  prediction_started <- proc.time()[["elapsed"]]
  covariance <- vcov(fit, unconditional = TRUE)
  exact_check(
    check_log, "gam_finite_unconditional_covariance",
    all(is.finite(covariance)),
    paste(nrow(covariance), "by", ncol(covariance), "finite covariance")
  )
  set_frozen_rng(GAM_DRAW_SEED)
  coefficient_draws <- mgcv::rmvn(
    POSTERIOR_DRAWS, mu = coef(fit), V = covariance
  )
  player_levels <- levels(inputs$data$lattice$player_factor)
  probabilities <- numeric(nrow(inputs$data$lattice))
  centered_links <- numeric(nrow(inputs$data$lattice))
  sparse_draws <- vector("list", nrow(inputs$sparse_players))
  names(sparse_draws) <- as.character(inputs$sparse_players$PLAYER_ID)
  for (player_position in seq_along(player_levels)) {
    player_level <- player_levels[[player_position]]
    rows <- which(inputs$data$lattice$player_factor == player_level)
    player_lattice <- inputs$data$lattice[rows, ]
    design <- predict(
      fit, newdata = player_lattice, type = "lpmatrix", discrete = FALSE
    )
    active <- which(colSums(abs(design)) > 0)
    eta_draws <- design[, active, drop = FALSE] %*%
      t(coefficient_draws[, active, drop = FALSE])
    probability_draws <- plogis(eta_draws)
    probabilities[rows] <- rowMeans(probability_draws)
    plugin_link <- as.numeric(
      design[, active, drop = FALSE] %*% coef(fit)[active]
    )
    centered_links[rows] <- plugin_link - mean(plugin_link)
    sparse_name <- as.character(player_level)
    if (sparse_name %in% names(sparse_draws)) {
      used <- player_lattice$validation_attempts > 0L
      sparse_draws[[sparse_name]] <- list(
        probabilities = probability_draws[used, , drop = FALSE],
        attempts = player_lattice$validation_attempts[used]
      )
    }
  }
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started
  exact_check(
    check_log, "gam_finite_predictions", all(is.finite(probabilities)),
    paste(length(probabilities), "finite draw-averaged probabilities")
  )
  exact_check(
    check_log, "gam_probability_bounds",
    all(probabilities >= 0 & probabilities <= 1),
    paste("range", paste(range(probabilities), collapse = " to "))
  )
  minimum_rmse <- minimum_discrete_surface_rmse(centered_links)
  exact_check(
    check_log, "gam_distinct_player_surfaces",
    is.finite(minimum_rmse) && minimum_rmse > SURFACE_TOLERANCE,
    paste("minimum centered-surface RMSE", format(minimum_rmse, digits = 10))
  )

  write_exact_stage("simulating_sparse_player_uncertainty")
  uncertainty_started <- proc.time()[["elapsed"]]
  set_frozen_rng(PREDICTIVE_SEED)
  sparse_intervals <- lapply(names(sparse_draws), function(player_id) {
    values <- sparse_draws[[player_id]]
    if (is.null(values) || nrow(values$probabilities) == 0L) {
      stop("A sparse player has no fold-4 metadata support", call. = FALSE)
    }
    total_draws <- simulate_discrete_totals(values$probabilities, values$attempts)
    tibble(
      PLAYER_ID = as.integer(player_id),
      validation_attempts = sum(values$attempts),
      interval_lower = as.numeric(quantile(total_draws, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(total_draws, 0.95, names = FALSE))
    ) |>
      mutate(interval_width = interval_upper - interval_lower)
  }) |>
    bind_rows() |>
    arrange(PLAYER_ID)
  uncertainty_elapsed <- proc.time()[["elapsed"]] - uncertainty_started
  exact_check(
    check_log, "gam_sparse_uncertainty_dimensions",
    nrow(sparse_intervals) == 80L && n_distinct(sparse_intervals$PLAYER_ID) == 80L,
    paste(nrow(sparse_intervals), "sparse-player intervals")
  )
  exact_check(
    check_log, "gam_sparse_uncertainty_finite_ordered",
    all(is.finite(sparse_intervals$interval_lower)) &&
      all(is.finite(sparse_intervals$interval_upper)) &&
      all(is.finite(sparse_intervals$interval_width)) &&
      all(sparse_intervals$interval_lower >= 0) &&
      all(sparse_intervals$interval_lower <= sparse_intervals$interval_upper) &&
      all(sparse_intervals$interval_upper <= sparse_intervals$validation_attempts),
    "all 90% posterior-predictive intervals are finite, ordered, and feasible"
  )
  checks <- bind_rows(check_log$records)
  exact_check(
    check_log, "all_applicable_checks_passed", all(checks$passed),
    paste(nrow(checks), "prior checks passed")
  )
  checks <- bind_rows(check_log$records)

  write_exact_stage("all_checks_passed_serializing_fit")
  fit_path <- file.path(exact_long_cache_dir, "gam_exact_grid_40_fit.rds")
  model_object_bytes <- as.numeric(object.size(fit))
  save_new_atomic_rds(fit, fit_path)
  metrics <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_exact_nondiscrete_two_worker_psock",
    specification_id = "frozen-gam-grid40-exact-long-v1",
    formula = expected_formula,
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = TRUE, timed_out = FALSE, failed = FALSE,
    runtime_ceiling_sec = NA_real_,
    setup_elapsed_sec = inputs$setup_elapsed_sec,
    fit_elapsed_sec = fit_elapsed,
    fit_child_cpu_sec = fit_child_cpu,
    prediction_elapsed_sec = prediction_elapsed,
    uncertainty_elapsed_sec = uncertainty_elapsed,
    worker_count = EXACT_LONG_WORKERS,
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = length(coef(fit)),
    smooth_count = length(fit$smooth),
    basis_size = GAM_BASIS_SIZE,
    smoothing_parameter_count = length(fit$sp),
    smoothing_parameter = unname(fit$sp),
    maximum_smooth_edf = max(edf),
    minimum_centered_surface_rmse = minimum_rmse,
    minimum_probability = min(probabilities),
    maximum_probability = max(probabilities),
    posterior_draws = POSTERIOR_DRAWS,
    gam_draw_seed = GAM_DRAW_SEED,
    predictive_seed = PREDICTIVE_SEED,
    model_object_bytes = model_object_bytes,
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    message_count = length(captured$messages),
    messages = paste(captured$messages, collapse = " | "),
    r_version = as.character(getRversion()),
    mgcv_version = as.character(packageVersion("mgcv")),
    arrow_version = as.character(packageVersion("arrow")),
    dplyr_version = as.character(packageVersion("dplyr")),
    tidyr_version = as.character(packageVersion("tidyr")),
    split_sha256 = EXPECTED_SPLIT_SHA256,
    input_sha256 = inputs$input_sha256
  )
  rm(coefficient_draws, covariance, sparse_draws, fit)
  gc()
  list(
    metrics = metrics,
    probabilities = tibble(
      PLAYER_ID = inputs$data$lattice$PLAYER_ID,
      cell_id = inputs$data$lattice$cell_id,
      probability = probabilities
    ),
    sparse_intervals = sparse_intervals,
    checks = checks,
    worker_pids = worker_pids
  )
}

exact_result_paths <- function() {
  file.path(
    exact_long_result_dir,
    c(
      "benchmark_metrics.parquet", "uncertainty_summary.parquet",
      "sanity_checks.parquet", "environment_notices.parquet"
    )
  )
}

write_exact_results <- function(result) {
  paths <- exact_result_paths()
  uncertainty_summary <- result$sparse_intervals |>
    summarise(
      sparse_player_count = n(),
      minimum_interval_width = min(interval_width),
      mean_interval_width = mean(interval_width),
      maximum_interval_width = max(interval_width),
      all_intervals_finite_ordered_feasible = TRUE
    ) |>
    mutate(
      season = season,
      scope = "all_318_eligible_players_training_only",
      method = "aggregated_exact_nondiscrete_two_worker_psock",
      grid_width = GRID_WIDTH,
      fold4_outcomes_read = FALSE,
      fold5_outcomes_read = FALSE,
      .before = 1
    )
  checks <- result$checks |>
    mutate(
      season = season,
      scope = "all_318_eligible_players_training_only",
      method = "aggregated_exact_nondiscrete_two_worker_psock",
      grid_width = GRID_WIDTH,
      fold4_outcomes_read = FALSE,
      fold5_outcomes_read = FALSE,
      .before = 1
    )
  environment_notices <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    severity = "compatibility_warning",
    source = "arrow package startup",
    notice = paste(
      "arrow was built under R 4.6.1 while the frozen runtime is R 4.6.0;",
      "all completed exact-GAM checks passed"
    ),
    package_build = packageDescription("arrow")$Built,
    model_warning_count = result$metrics$warning_count,
    model_message_count = result$metrics$message_count,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE
  )
  tables <- list(result$metrics, uncertainty_summary, checks, environment_notices)
  for (index in seq_along(paths)) {
    write_new_atomic_parquet(tables[[index]], paths[[index]])
  }
}

save_exact_completion <- function(result) {
  if (!all(result$checks$passed)) {
    stop("Refusing to publish exact completion before every check passes",
         call. = FALSE)
  }
  fit_path <- file.path(exact_long_cache_dir, "gam_exact_grid_40_fit.rds")
  if (!file.exists(fit_path) ||
      !identical(
        unname(tools::md5sum(fit_path)),
        result$metrics$serialized_model_md5[[1]]
      )) {
    stop("The exact fit artifact is missing or has the wrong hash",
         call. = FALSE)
  }
  checkpoint <- list(
    complete = TRUE,
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_exact_nondiscrete_two_worker_psock",
    specification_id = "frozen-gam-grid40-exact-long-v1",
    split_sha256 = EXPECTED_SPLIT_SHA256,
    input_sha256 = result$metrics$input_sha256[[1]],
    player_count = EXPECTED_ALL_PLAYERS,
    grid_width = GRID_WIDTH,
    fit_md5 = result$metrics$serialized_model_md5[[1]],
    result = result
  )
  save_new_atomic_rds(
    checkpoint,
    file.path(exact_long_cache_dir, "benchmark_complete_checkpoint.rds")
  )
}

load_exact_completion <- function() {
  checkpoint_path <- file.path(
    exact_long_cache_dir, "benchmark_complete_checkpoint.rds"
  )
  if (!file.exists(checkpoint_path)) return(NULL)
  checkpoint <- tryCatch(
    readRDS(checkpoint_path),
    error = function(condition) {
      stop("Existing exact checkpoint is unreadable and was preserved: ",
           conditionMessage(condition), call. = FALSE)
    }
  )
  fit_path <- file.path(exact_long_cache_dir, "gam_exact_grid_40_fit.rds")
  signature_path <- file.path(exact_long_cache_dir, "input_signature.rds")
  valid <- is.list(checkpoint) && isTRUE(checkpoint$complete) &&
    identical(checkpoint$season, season) &&
    identical(checkpoint$scope, "all_318_eligible_players_training_only") &&
    identical(
      checkpoint$method, "aggregated_exact_nondiscrete_two_worker_psock"
    ) &&
    identical(checkpoint$specification_id, "frozen-gam-grid40-exact-long-v1") &&
    identical(checkpoint$split_sha256, EXPECTED_SPLIT_SHA256) &&
    identical(checkpoint$player_count, EXPECTED_ALL_PLAYERS) &&
    identical(checkpoint$grid_width, GRID_WIDTH) &&
    nrow(checkpoint$result$probabilities) == EXPECTED_ALL_PLAYERS * GRID_CELLS &&
    nrow(checkpoint$result$sparse_intervals) == 80L &&
    nrow(checkpoint$result$metrics) == 1L &&
    isTRUE(checkpoint$result$metrics$completed[[1]]) &&
    all(checkpoint$result$checks$passed) &&
    file.exists(fit_path) && file.exists(signature_path) &&
    identical(checkpoint$fit_md5, unname(tools::md5sum(fit_path))) &&
    identical(checkpoint$input_sha256, sha256_file(signature_path)) &&
    all(file.exists(exact_result_paths()))
  if (!valid) {
    stop("Existing exact checkpoint is inconsistent; artifacts were preserved",
         call. = FALSE)
  }
  checkpoint
}

active_pids <- function(pids) {
  pids <- unique(as.integer(pids[is.finite(pids)]))
  pids[vapply(pids, function(pid) {
    length(system2("ps", c("-p", pid, "-o", "pid="), stdout = TRUE)) > 0L
  }, logical(1))]
}

terminate_exact_processes <- function(root_pid, extra_pids = integer()) {
  tree <- discrete_process_tree_snapshot(root_pid)$pids
  targets <- unique(c(tree, active_pids(extra_pids)))
  for (pid in rev(targets)) {
    try(tools::pskill(pid, signal = 15L), silent = TRUE)
  }
  Sys.sleep(5)
  remaining <- active_pids(targets)
  for (pid in rev(remaining)) {
    try(tools::pskill(pid, signal = 9L), silent = TRUE)
  }
  Sys.sleep(1)
  active_pids(targets)
}

write_exact_failure <- function(inputs, elapsed, cpu_seconds, peak_rss_mb,
                                failure, orphan_count) {
  stage_path <- file.path(exact_long_cache_dir, "stage_heartbeat.rds")
  last_stage <- if (file.exists(stage_path)) {
    tryCatch(readRDS(stage_path)$stage,
             error = function(condition) "unreadable_stage_heartbeat")
  } else {
    "unknown_no_stage_heartbeat"
  }
  result <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_exact_nondiscrete_two_worker_psock",
    specification_id = "frozen-gam-grid40-exact-long-v1",
    grid_width = GRID_WIDTH,
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = FALSE, timed_out = FALSE, failed = TRUE,
    failure = failure,
    last_confirmed_stage = last_stage,
    runtime_ceiling_sec = NA_real_,
    total_wall_elapsed_sec = as.numeric(elapsed),
    approximate_process_tree_cpu_sec = as.numeric(cpu_seconds),
    approximate_peak_process_tree_rss_mb = as.numeric(peak_rss_mb),
    remaining_orphan_processes = as.integer(orphan_count),
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    smooth_count = EXPECTED_ALL_PLAYERS,
    basis_size = GAM_BASIS_SIZE,
    smoothing_parameter_count = 1L,
    posterior_draws = POSTERIOR_DRAWS,
    gam_draw_seed = GAM_DRAW_SEED,
    predictive_seed = PREDICTIVE_SEED,
    r_version = as.character(getRversion()),
    mgcv_version = as.character(packageVersion("mgcv")),
    split_sha256 = EXPECTED_SPLIT_SHA256,
    input_sha256 = inputs$input_sha256
  )
  write_new_atomic_parquet(
    result, file.path(exact_long_result_dir, "benchmark_failure.parquet")
  )
  result
}

other_full_gam_processes <- function() {
  output <- suppressWarnings(system2(
    "ps", c("-axo", "pid=,command="), stdout = TRUE, stderr = TRUE
  ))
  if (length(output) == 0L || !is.null(attr(output, "status"))) {
    stop("Could not inspect the process table for duplicate GAM runs",
         call. = FALSE)
  }
  pid <- suppressWarnings(as.integer(sub("^ *([0-9]+).*$", "\\1", output)))
  table <- tibble(
    pid = pid,
    command = trimws(sub("^ *[0-9]+ +", "", output))
  ) |>
    filter(!is.na(pid))
  ancestors <- integer()
  ancestor <- Sys.getpid()
  for (index in seq_len(10L)) {
    ancestor <- parent_pid(ancestor)
    ancestors <- c(ancestors, ancestor)
    if (ancestor <= 1L) break
  }
  table |>
    filter(
      !pid %in% c(Sys.getpid(), ancestors),
      grepl("spatial_gam_aggregation_benchmark[.]R", command),
      grepl(
        "exact318-long-run|discrete318-run|benchmark318_parallel|benchmark318",
        command
      )
    )
}

audit_exact_long_run <- function() {
  check_log <- new_exact_check_log()
  inputs <- prepare_exact_full_inputs(check_log, write_signature = FALSE)
  reference <- read_parquet(parallel_equivalence_path) |>
    as_tibble()
  exact_check(
    check_log, "verified_two_worker_equivalence_reference",
    nrow(reference) == 1L && reference$worker_count[[1]] == EXACT_LONG_WORKERS &&
      isTRUE(reference$passed[[1]]) &&
      identical(reference$fold4_outcomes_read[[1]], FALSE) &&
      identical(reference$fold5_outcomes_read[[1]], FALSE),
    "40-player exact two-worker PSOCK comparison passed"
  )
  exact_check(
    check_log, "no_other_full_league_gam_process",
    nrow(other_full_gam_processes()) == 0L,
    "no exact or discrete full-league GAM R process is active"
  )
  audit <- tibble(
    season = season,
    scope = "all_318_eligible_players_training_only",
    method = "aggregated_exact_nondiscrete_two_worker_psock",
    players = inputs$players,
    training_shots = inputs$training_shots,
    observed_player_cells = nrow(inputs$data$aggregated),
    full_lattice_rows = nrow(inputs$data$lattice),
    coefficient_count = EXPECTED_ALL_PLAYERS * GAM_BASIS_SIZE,
    smooth_count = EXPECTED_ALL_PLAYERS,
    smoothing_parameter_count = 1L,
    worker_count = EXACT_LONG_WORKERS,
    posterior_draws = POSTERIOR_DRAWS,
    fitting_folds = inputs$folds,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    input_sha256 = inputs$input_sha256,
    split_sha256 = inputs$split_sha256,
    frozen_preflight_checks_passed = all(bind_rows(check_log$records)$passed)
  )
  print(audit, width = Inf)
  invisible(audit)
}

run_launchagent_smoke <- function() {
  if (!identical(Sys.getenv("SPATIAL_EXACT_SMOKE_ONLY"), "1")) {
    stop("SMOKE SAFEGUARD: audit-only environment flag is required",
         call. = FALSE)
  }
  expected_label <- "com.narayanlekhi.nba-shot-analytics.exact-gam-smoke"
  smoke_label <- Sys.getenv("SPATIAL_EXACT_SMOKE_LABEL")
  smoke_run_id <- Sys.getenv("SPATIAL_EXACT_SMOKE_RUN_ID")
  smoke_dir <- Sys.getenv("SPATIAL_EXACT_SMOKE_DIR")
  if (!identical(smoke_label, expected_label)) {
    stop("SMOKE SAFEGUARD: unexpected LaunchAgent label", call. = FALSE)
  }
  if (!grepl("^[0-9]{8}T[0-9]{6}Z-[0-9]+$", smoke_run_id)) {
    stop("SMOKE SAFEGUARD: invalid smoke run identifier", call. = FALSE)
  }
  expected_dir <- file.path(
    exact_smoke_root_dir, paste0("attempt=", smoke_run_id)
  )
  if (!dir.exists(smoke_dir) ||
      normalizePath(smoke_dir, mustWork = TRUE) !=
        normalizePath(expected_dir, mustWork = TRUE)) {
    stop("SMOKE SAFEGUARD: attempt directory does not match the runner",
         call. = FALSE)
  }

  write_smoke_rds <- function(value, filename) {
    path <- file.path(smoke_dir, filename)
    if (file.exists(path)) {
      stop("SMOKE SAFEGUARD: refusing to overwrite ", path, call. = FALSE)
    }
    temporary <- tempfile(
      pattern = paste0(filename, ".partial-"), tmpdir = smoke_dir
    )
    saveRDS(value, temporary)
    if (!file.rename(temporary, path)) {
      stop("Could not atomically publish smoke artifact: ", filename,
           call. = FALSE)
    }
    invisible(path)
  }
  write_smoke_stage <- function(stage) {
    path <- file.path(smoke_dir, "stage_heartbeat.rds")
    temporary <- tempfile(
      pattern = "stage_heartbeat.rds.partial-", tmpdir = smoke_dir
    )
    saveRDS(list(
      stage = stage,
      timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      process_id = Sys.getpid(),
      model_fitting_allowed = FALSE
    ), temporary)
    if (!file.rename(temporary, path)) {
      stop("Could not atomically publish smoke stage", call. = FALSE)
    }
    invisible(path)
  }

  lock_path <- file.path(exact_smoke_root_dir, "active_smoke.lock")
  if (!dir.create(lock_path, recursive = FALSE, showWarnings = FALSE)) {
    stop("DUPLICATE SMOKE SAFEGUARD: active smoke lock exists",
         call. = FALSE)
  }
  smoke_succeeded <- FALSE
  on.exit({
    if (dir.exists(lock_path)) {
      closed_name <- if (smoke_succeeded) {
        "closed_smoke.lock"
      } else {
        "failed_smoke.lock"
      }
      if (!file.rename(lock_path, file.path(smoke_dir, closed_name))) {
        warning("Could not preserve and close the smoke lock", call. = FALSE)
      }
    }
  }, add = TRUE)

  caffeinate <- verify_caffeinate_guard()
  owner <- list(
    label = smoke_label,
    run_id = smoke_run_id,
    runner_pid = Sys.getpid(),
    caffeinate_pid = caffeinate$pid,
    caffeinate_command = caffeinate$command,
    r_mode = mode,
    arguments = commandArgs(trailingOnly = TRUE),
    started_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    model_fitting_allowed = FALSE,
    fitting_started = FALSE,
    prediction_started = FALSE,
    uncertainty_started = FALSE
  )
  saveRDS(owner, file.path(lock_path, "owner.rds"))
  write_smoke_rds(owner, "pid_metadata.rds")
  write_smoke_stage("audit_preflight")

  audit <- audit_exact_long_run()
  if (
    nrow(audit) != 1L || audit$players[[1L]] != EXPECTED_ALL_PLAYERS ||
    audit$training_shots[[1L]] != 116955L ||
    !identical(audit$fold4_outcomes_read[[1L]], FALSE) ||
    !identical(audit$fold5_outcomes_read[[1L]], FALSE) ||
    !isTRUE(audit$frozen_preflight_checks_passed[[1L]])
  ) {
    stop("SMOKE SAFEGUARD: audit result did not match the frozen preflight",
         call. = FALSE)
  }

  write_smoke_stage("audit_passed_writing_completion")
  completion <- list(
    label = smoke_label,
    run_id = smoke_run_id,
    completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    exit_expected = 0L,
    players = audit$players[[1L]],
    training_shots = audit$training_shots[[1L]],
    observed_player_cells = audit$observed_player_cells[[1L]],
    full_lattice_rows = audit$full_lattice_rows[[1L]],
    fitting_folds = audit$fitting_folds[[1L]],
    input_sha256 = audit$input_sha256[[1L]],
    split_sha256 = audit$split_sha256[[1L]],
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    model_fitting_allowed = FALSE,
    fitting_started = FALSE,
    prediction_started = FALSE,
    uncertainty_started = FALSE,
    psock_workers_started = 0L,
    checks_passed = TRUE
  )
  write_smoke_rds(completion, "completion_marker.rds")
  write_smoke_stage("smoke_complete")
  smoke_succeeded <- TRUE
  print(completion)
  invisible(completion)
}

run_exact_long_full_league <- function() {
  completed <- load_exact_completion()
  if (!is.null(completed)) {
    message("Reusing verified completed full-league exact GAM checkpoint")
    print(completed$result$metrics, width = Inf)
    return(invisible(completed))
  }
  existing_files <- c(
    if (dir.exists(exact_long_cache_dir)) {
      list.files(exact_long_cache_dir, all.files = TRUE, full.names = TRUE) |>
        setdiff(c(
          file.path(exact_long_cache_dir, "."),
          file.path(exact_long_cache_dir, "..")
        ))
    } else {
      character()
    },
    if (dir.exists(exact_long_result_dir)) {
      list.files(exact_long_result_dir, all.files = TRUE, full.names = TRUE) |>
        setdiff(c(
          file.path(exact_long_result_dir, "."),
          file.path(exact_long_result_dir, "..")
        ))
    } else {
      character()
    }
  )
  current_console_log <- Sys.getenv("SPATIAL_EXACT_CONSOLE_LOG")
  if (nzchar(current_console_log)) {
    existing_files <- setdiff(existing_files, current_console_log)
  }
  if (length(existing_files) > 0L) {
    stop(
      "Incomplete exact-run artifacts were preserved; inspect before restarting",
      call. = FALSE
    )
  }

  caffeinate <- verify_caffeinate_guard()
  free_gib <- disk_free_gib(".")
  if (free_gib < EXACT_LONG_MIN_FREE_GIB) {
    stop(
      "DISK SAFEGUARD: fewer than ", EXACT_LONG_MIN_FREE_GIB,
      " GiB are free; exact fit was not started", call. = FALSE
    )
  }
  if (nrow(other_full_gam_processes()) > 0L) {
    stop("DUPLICATE RUN SAFEGUARD: another full-league GAM is active",
         call. = FALSE)
  }

  wall_started_time <- Sys.time()
  lock <- acquire_exact_lock()
  on.exit(release_exact_lock(lock), add = TRUE)
  check_log <- new_exact_check_log()
  inputs <- prepare_exact_full_inputs(check_log, write_signature = TRUE)
  metadata <- list(
    season = season,
    mode = mode,
    specification_id = "frozen-gam-grid40-exact-long-v1",
    runner_pid = Sys.getpid(),
    model_pid = NA_integer_,
    worker_pids = integer(),
    caffeinate_pid = caffeinate$pid,
    caffeinate_command = caffeinate$command,
    started_at_utc = format(wall_started_time, tz = "UTC", usetz = TRUE),
    last_updated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stage_path = file.path(exact_long_cache_dir, "stage_heartbeat.rds"),
    console_log_path = current_console_log,
    event_log_path = file.path(exact_long_cache_dir, "run_events.log"),
    resource_samples_path = file.path(exact_long_cache_dir, "resource_samples.rds"),
    free_disk_gib_at_start = free_gib,
    runtime_ceiling_sec = NA_real_,
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    input_sha256 = inputs$input_sha256,
    split_sha256 = inputs$split_sha256
  )
  write_exact_metadata(metadata)
  write_exact_stage("launching_exact_model_child")
  exact_log_event(
    "START runner_pid=", Sys.getpid(), " caffeinate_pid=", caffeinate$pid,
    " free_disk_gib=", round(free_gib, 2), " no_runtime_ceiling"
  )

  job <- parallel::mcparallel(
    fit_full_league_exact_gam(inputs, check_log),
    detached = FALSE,
    silent = FALSE
  )
  lock <- update_exact_lock(lock, model_pid = job$pid)
  metadata$model_pid <- as.integer(job$pid)
  metadata$last_updated_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  write_exact_metadata(metadata)

  samples <- tibble()
  cpu_by_pid <- numeric()
  peak_rss_mb <- 0
  next_persisted_sample <- 0
  worker_pids <- integer()

  repeat {
    elapsed <- as.numeric(difftime(Sys.time(), wall_started_time, units = "secs"))
    worker_pid_path <- file.path(exact_long_cache_dir, "psock_worker_pids.rds")
    if (file.exists(worker_pid_path) && length(worker_pids) == 0L) {
      worker_pids <- tryCatch(
        as.integer(readRDS(worker_pid_path)),
        error = function(condition) integer()
      )
      if (length(worker_pids) > 0L) {
        lock <- update_exact_lock(lock, worker_pids = worker_pids)
        metadata$worker_pids <- worker_pids
        metadata$last_updated_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
        write_exact_metadata(metadata)
        exact_log_event("PSOCK workers published: ", paste(worker_pids, collapse = ","))
      }
    }
    snapshot <- discrete_process_tree_snapshot(Sys.getpid(), worker_pids)
    peak_rss_mb <- max(peak_rss_mb, snapshot$rss_mb)
    for (pid in names(snapshot$cpu_seconds)) {
      previous <- unname(cpu_by_pid[pid])
      if (length(previous) == 0L || is.na(previous)) previous <- 0
      cpu_by_pid[pid] <- max(previous, snapshot$cpu_seconds[[pid]])
    }

    if (elapsed >= next_persisted_sample) {
      stage_path <- file.path(exact_long_cache_dir, "stage_heartbeat.rds")
      stage <- if (file.exists(stage_path)) {
        tryCatch(readRDS(stage_path)$stage,
                 error = function(condition) "unreadable_stage")
      } else {
        "stage_not_yet_published"
      }
      pressure <- tryCatch(
        paste(system2("memory_pressure", "-Q", stdout = TRUE), collapse = " | "),
        error = function(condition) conditionMessage(condition)
      )
      current_free_gib <- disk_free_gib(".")
      samples <- bind_rows(samples, tibble(
        timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
        elapsed_sec = elapsed,
        stage = stage,
        visible_process_count = length(snapshot$pids),
        visible_pids = paste(snapshot$pids, collapse = ","),
        process_tree_rss_mb = snapshot$rss_mb,
        cumulative_sampled_cpu_sec = sum(cpu_by_pid, na.rm = TRUE),
        free_disk_gib = current_free_gib,
        memory_pressure = pressure
      ))
      save_atomic_rds(
        samples, file.path(exact_long_cache_dir, "resource_samples.rds")
      )
      metadata$last_updated_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
      metadata$last_stage <- stage
      metadata$last_elapsed_sec <- elapsed
      metadata$last_process_tree_rss_mb <- snapshot$rss_mb
      metadata$last_sampled_cpu_sec <- sum(cpu_by_pid, na.rm = TRUE)
      metadata$last_free_disk_gib <- current_free_gib
      write_exact_metadata(metadata)
      exact_log_event(
        "RESOURCE elapsed_sec=", round(elapsed, 1), " stage=", stage,
        " cpu_sec=", round(sum(cpu_by_pid, na.rm = TRUE), 1),
        " rss_mb=", round(snapshot$rss_mb, 1),
        " free_disk_gib=", round(current_free_gib, 2)
      )
      next_persisted_sample <- elapsed + EXACT_LONG_SAMPLE_INTERVAL_SEC
      if (current_free_gib < 2) {
        remaining <- terminate_exact_processes(job$pid, worker_pids)
        result <- write_exact_failure(
          inputs, elapsed, sum(cpu_by_pid, na.rm = TRUE), peak_rss_mb,
          "critical disk safeguard: fewer than 2 GiB remained",
          length(remaining)
        )
        print(result, width = Inf)
        stop("Exact GAM stopped because disk space became critically low",
             call. = FALSE)
      }
      if (length(active_pids(caffeinate$pid)) != 1L) {
        remaining <- terminate_exact_processes(job$pid, worker_pids)
        result <- write_exact_failure(
          inputs, elapsed, sum(cpu_by_pid, na.rm = TRUE), peak_rss_mb,
          "macOS caffeinate sleep-prevention guard exited unexpectedly",
          length(remaining)
        )
        print(result, width = Inf)
        stop("Exact GAM stopped because sleep prevention was lost",
             call. = FALSE)
      }
    }

    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      value <- collected[[1]]
      elapsed <- as.numeric(difftime(Sys.time(), wall_started_time, units = "secs"))
      if (inherits(value, "try-error")) {
        remaining <- terminate_exact_processes(job$pid, worker_pids)
        failure <- paste("exact GAM model child failed:", value)
        result <- write_exact_failure(
          inputs, elapsed, sum(cpu_by_pid, na.rm = TRUE), peak_rss_mb,
          failure, length(remaining)
        )
        exact_log_event("FAILURE ", failure)
        print(result, width = Inf)
        stop(failure, call. = FALSE)
      }
      remaining <- active_pids(worker_pids)
      if (length(remaining) > 0L) {
        remaining <- terminate_exact_processes(job$pid, remaining)
      }
      orphan_check <- tibble(
        check = "no_orphan_psock_workers_after_completion",
        passed = length(remaining) == 0L,
        detail = paste(length(remaining), "workers remained")
      )
      if (!orphan_check$passed[[1]]) {
        failure <- "EXACT GAM SANITY CHECK FAILED: PSOCK workers remained"
        result <- write_exact_failure(
          inputs, elapsed, sum(cpu_by_pid, na.rm = TRUE), peak_rss_mb,
          failure, length(remaining)
        )
        print(result, width = Inf)
        stop(failure, call. = FALSE)
      }
      value$checks <- bind_rows(value$checks, orphan_check)
      value$metrics <- value$metrics |>
        mutate(
          total_wall_elapsed_sec = elapsed,
          approximate_process_tree_cpu_sec = sum(cpu_by_pid, na.rm = TRUE),
          approximate_peak_process_tree_rss_mb = peak_rss_mb,
          resource_sample_count = nrow(samples),
          free_disk_gib_at_start = free_gib,
          free_disk_gib_at_completion = disk_free_gib("."),
          caffeinate_pid = caffeinate$pid,
          sleep_prevention_verified = TRUE,
          orphan_process_count_after_completion = length(remaining),
          cpu_measurement = paste(
            "sum of maximum five-second sampled CPU time for each visible",
            "R process-tree PID"
          ),
          memory_measurement = paste(
            "maximum sampled resident memory across runner, model child,",
            "and visible PSOCK workers"
          )
        )
      write_exact_results(value)
      save_exact_completion(value)
      write_exact_stage("complete_checkpoint_published")
      exact_log_event(
        "COMPLETE elapsed_sec=", round(elapsed, 1),
        " fit_md5=", value$metrics$serialized_model_md5[[1]]
      )
      print(value$metrics, width = Inf)
      return(invisible(value))
    }
    Sys.sleep(5)
  }
}

if (mode == "exact318-long-audit") {
  audit_exact_long_run()
} else if (mode == "exact318-launchagent-smoke") {
  run_launchagent_smoke()
} else if (mode == "exact318-long-run") {
  run_exact_long_full_league()
} else if (mode == "discrete318-audit") {
  audit_discrete_full_league()
} else if (mode == "discrete318-run") {
  run_capped_discrete_full_league()
} else if (mode == "audit") {
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
} else if (mode == "compare40_parallel") {
  compare_parallel(worker_count)
} else if (mode == "benchmark318") {
  benchmark_full_league(discrete = method == "discrete")
} else if (mode == "benchmark318_parallel") {
  run_capped_parallel_benchmark(worker_count)
} else if (mode == "record_timeout") {
  if (length(args) != 4L) {
    stop("record_timeout requires method and elapsed seconds", call. = FALSE)
  }
  record_timeout(method, as.numeric(args[[4]]))
} else if (mode == "record_parallel_timeout") {
  if (length(args) != 6L) {
    stop(paste(
      "record_parallel_timeout requires workers, elapsed seconds, CPU seconds,",
      "and peak memory MB"
    ),
         call. = FALSE)
  }
  record_parallel_timeout(
    worker_count,
    as.numeric(args[[4]]),
    as.numeric(args[[5]]),
    as.numeric(args[[6]])
  )
}
