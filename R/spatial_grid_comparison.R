# Frozen training/validation comparison of player-specific GAM and CAR surfaces.
#
# This script is separate from the production zone pipeline. Audit mode never
# reads make/miss outcomes. Run mode permits outcomes from folds 1-4 only; the
# guarded outcome loader stops before collecting data if fold 5 is requested.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    paste(
      "Usage: Rscript R/spatial_grid_comparison.R <season>",
      "<audit|run|car-benchmark-audit|car-benchmark>"
    ),
    call. = FALSE
  )
}

season <- args[[1]]
mode <- args[[2]]
if (!grepl("^[0-9]{4}-[0-9]{2}$", season)) {
  stop("season must look like 2025-26", call. = FALSE)
}
if (!mode %in% c("audit", "run", "car-benchmark-audit", "car-benchmark")) {
  stop("Unknown comparison mode", call. = FALSE)
}
if (season != "2025-26") {
  stop("The frozen first comparison is registered only for 2025-26", call. = FALSE)
}

# Frozen values from docs/SPATIAL_MODEL_PLAN.md. Changing one requires a new
# pre-registered experiment, not an edit after validation has been viewed.
FITTING_FOLDS <- 1:3
VALIDATION_FOLD <- 4L
SEALED_TEST_FOLD <- 5L
GRID_WIDTHS <- c(30L, 40L, 50L)
# Execution order is operational only. Coarser-first creates useful, validated
# checkpoints sooner without changing grid scoring or any model setting.
RUN_ORDER <- rev(GRID_WIDTHS)
GRID_EXPECTED_CELLS <- c(`30` = 255L, `40` = 156L, `50` = 90L)
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
GAM_BASIS_SIZE <- 20L
POSTERIOR_DRAWS <- 4000L
BOOTSTRAP_DRAWS <- 2000L
MODEL_THREADS <- 1L
CAR_BENCHMARK_GRID <- 40L
CAR_BENCHMARK_CEILING_SEC <- 1800
SPLIT_SEED <- 20260830L
FALLBACK_SAMPLE_SEED <- 20260831L
GAM_DRAW_SEED <- 20260901L
CAR_DRAW_SEED <- 20260902L
PREDICTIVE_SEED <- 20260903L
VALIDATION_BOOTSTRAP_SEED <- 20260904L
LOG_EPSILON <- 1e-15
SURFACE_TOLERANCE <- 1e-8
GAM_EDF_LIMIT <- 0.95 * (GAM_BASIS_SIZE - 1L)

EXPECTED_VERSIONS <- c(
  mgcv = "1.9.4",
  INLA = "26.8.7",
  Matrix = "1.7.5",
  fmesher = "0.8.0",
  arrow = "25.0.0",
  dplyr = "1.2.1",
  tidyr = "1.3.2"
)
EXPECTED_R_VERSION <- "4.6.0"
EXPECTED_SPLIT_SHA256 <- "aaee94c1e8380999190aea5f00f8c02c738db6438ffe7b7a1a761d19c5a6ee33"
EXPECTED_SAMPLE_SHA256 <- "bba00938e29c2a365c668d337067f3958e849db9957c8b2d259629e50c78ae84"
EXPECTED_ALL_ELIGIBLE_PLAYERS <- 318L
EXPECTED_FALLBACK_PLAYERS <- 40L
EXPECTED_SPARSE_PLAYERS <- 10L
EXPECTED_ALL_SPARSE_PLAYERS <- 80L
IS_CAR_BENCHMARK <- mode %in% c("car-benchmark-audit", "car-benchmark")
ACTIVE_PLAYER_COUNT <- if (IS_CAR_BENCHMARK) {
  EXPECTED_ALL_ELIGIBLE_PLAYERS
} else {
  EXPECTED_FALLBACK_PLAYERS
}
ACTIVE_SPARSE_PLAYER_COUNT <- if (IS_CAR_BENCHMARK) {
  EXPECTED_ALL_SPARSE_PLAYERS
} else {
  EXPECTED_SPARSE_PLAYERS
}
ACTIVE_SAMPLE_SHA256 <- if (IS_CAR_BENCHMARK) NA_character_ else EXPECTED_SAMPLE_SHA256
EXPERIMENT_SCOPE <- if (IS_CAR_BENCHMARK) {
  "all_318_players_training_only_car_benchmark"
} else {
  "predeclared_40_player_fallback"
}
MODEL_SPECIFICATION_ID <- if (IS_CAR_BENCHMARK) {
  "frozen-car-full-league-grid40-training-v1"
} else {
  "frozen-spatial-grid-comparison-v1-fallback40"
}

raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", season), "shots.parquet"
)
cache_dir <- if (IS_CAR_BENCHMARK) {
  file.path(
    "data", "cache", "spatial_car_full_league_benchmark",
    paste0("season=", season)
  )
} else {
  file.path(
    "data", "cache", "spatial_grid_comparison", paste0("season=", season)
  )
}
result_dir <- if (IS_CAR_BENCHMARK) {
  file.path(
    "data", "processed", "spatial_car_full_league_benchmark",
    paste0("season=", season)
  )
} else {
  file.path(
    "data", "processed", "spatial_grid_comparison", paste0("season=", season)
  )
}
fold_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "game_folds.parquet"
)
sample_path <- file.path(
  "data", "cache", "spatial_pilot", paste0("season=", season),
  "player_sample.parquet"
)

METADATA_COLUMNS <- c(
  "GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y",
  "SHOT_ATTEMPTED_FLAG"
)
OUTCOME_COLUMNS <- c(METADATA_COLUMNS, "SHOT_MADE_FLAG")

set_frozen_rng <- function(seed) {
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
}

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) {
    stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  }
  strsplit(output, "[[:space:]]+")[[1]][[1]]
}

same_table <- function(x, y) {
  identical(as.data.frame(x), as.data.frame(y))
}

condition_capture <- function(expression) {
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

checkpoint_path <- function(grid_width, model) {
  file.path(
    cache_dir,
    paste0(tolower(model), "_grid_", grid_width, "_checkpoint.rds")
  )
}

load_verified_checkpoint <- function(path, grid_width, model, expected_rows,
                                     expected_sparse_rows) {
  if (!file.exists(path)) {
    return(NULL)
  }
  checkpoint <- tryCatch(
    readRDS(path),
    error = function(condition) {
      stop(
        "Existing checkpoint is unreadable and was preserved: ", path,
        " — ", conditionMessage(condition),
        call. = FALSE
      )
    }
  )
  valid_header <- is.list(checkpoint) &&
    isTRUE(checkpoint$complete) &&
    identical(checkpoint$season, season) &&
    identical(checkpoint$grid_width, as.integer(grid_width)) &&
    identical(checkpoint$model, model) &&
    identical(checkpoint$specification_id, MODEL_SPECIFICATION_ID) &&
    identical(checkpoint$split_sha256, EXPECTED_SPLIT_SHA256) &&
    identical(checkpoint$fallback_sample_sha256, ACTIVE_SAMPLE_SHA256) &&
    identical(checkpoint$player_count, ACTIVE_PLAYER_COUNT)
  if (!valid_header) {
    stop("Existing checkpoint has an invalid or stale header and was preserved: ",
         path, call. = FALSE)
  }
  result <- checkpoint$result
  valid_result <- is.list(result) &&
    nrow(result$probabilities) == expected_rows &&
    nrow(result$sparse) == expected_sparse_rows &&
    nrow(result$metrics) == 1L &&
    identical(result$metrics$grid_width[[1]], as.integer(grid_width)) &&
    identical(result$metrics$model[[1]], model) &&
    nrow(checkpoint$checks) > 0L &&
    all(checkpoint$checks$passed)
  if (!valid_result) {
    stop("Existing checkpoint is incomplete or internally inconsistent and was preserved: ",
         path, call. = FALSE)
  }
  fit_path <- if (model == "GAM") {
    file.path(cache_dir, paste0("gam_grid_", grid_width, "_fit.rds"))
  } else {
    file.path(cache_dir, paste0("car_grid_", grid_width, "_fit.rds"))
  }
  fit_valid <- file.exists(fit_path) &&
    identical(
      unname(tools::md5sum(fit_path)),
      result$metrics$serialized_model_md5[[1]]
    )
  if (!fit_valid) {
    stop("Checkpoint fit artifact is missing or has the wrong hash; files were preserved: ",
         path, call. = FALSE)
  }
  checkpoint
}

save_atomic_checkpoint <- function(path, checkpoint) {
  if (file.exists(path)) {
    stop("Refusing to replace an existing checkpoint: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path)
  )
  saveRDS(checkpoint, temporary, compress = FALSE)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish checkpoint; partial file preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

save_atomic_fit <- function(object, path) {
  if (file.exists(path)) {
    stop("Refusing to replace an existing fitted model: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path)
  )
  saveRDS(object, temporary, compress = FALSE)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish fitted model; partial file preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

run_or_reuse_model <- function(grid_width, model, expected_rows,
                               expected_sparse_rows, check_log, runner) {
  path <- checkpoint_path(grid_width, model)
  checkpoint <- load_verified_checkpoint(
    path, grid_width, model, expected_rows, expected_sparse_rows
  )
  if (!is.null(checkpoint)) {
    check_log$records <- c(
      check_log$records,
      split(checkpoint$checks, seq_len(nrow(checkpoint$checks)))
    )
    message("Reusing verified checkpoint: ", path)
    return(checkpoint$result)
  }

  before <- if (is.null(check_log$records)) 0L else length(check_log$records)
  result <- runner()
  after <- length(check_log$records)
  new_checks <- bind_rows(check_log$records[seq.int(before + 1L, after)])
  checkpoint <- list(
    complete = TRUE,
    season = season,
    grid_width = as.integer(grid_width),
    model = model,
    specification_id = MODEL_SPECIFICATION_ID,
    split_sha256 = EXPECTED_SPLIT_SHA256,
    fallback_sample_sha256 = ACTIVE_SAMPLE_SHA256,
    player_count = ACTIVE_PLAYER_COUNT,
    result = result,
    checks = new_checks
  )
  save_atomic_checkpoint(path, checkpoint)
  result
}

new_check_log <- function() {
  new.env(parent = emptyenv())
}

record_check <- function(log, scope, grid_width, model, check, passed, detail) {
  index <- if (is.null(log$records)) 1L else length(log$records) + 1L
  row <- tibble(
    scope = scope,
    grid_width = as.integer(grid_width),
    model = model,
    check = check,
    passed = isTRUE(passed),
    detail = as.character(detail)
  )
  log$records <- c(log$records, list(row))
  if (!isTRUE(passed)) {
    stop(
      "SANITY CHECK FAILED [", scope, "/", model, "/", grid_width,
      "]: ", check, " — ", detail,
      call. = FALSE
    )
  }
  invisible(index)
}

check_or_stop <- function(log, scope, grid_width = NA_integer_, model = "both",
                          check, condition, detail) {
  record_check(log, scope, grid_width, model, check, condition, detail)
}

verify_versions <- function(check_log) {
  check_or_stop(
    check_log, "configuration", check = "r_version",
    condition = getRversion() == EXPECTED_R_VERSION,
    detail = paste("expected", EXPECTED_R_VERSION, "found", getRversion())
  )
  for (package in names(EXPECTED_VERSIONS)) {
    installed <- as.character(packageVersion(package))
    check_or_stop(
      check_log, "configuration", check = paste0("package_", package),
      condition = installed == EXPECTED_VERSIONS[[package]],
      detail = paste("expected", EXPECTED_VERSIONS[[package]], "found", installed)
    )
  }
  check_or_stop(
    check_log, "configuration", check = "package_sn_available",
    condition = requireNamespace("sn", quietly = TRUE),
    detail = if (requireNamespace("sn", quietly = TRUE)) {
      paste("installed version", as.character(packageVersion("sn")))
    } else {
      "R-INLA posterior sampling requires the already-installed sn package"
    }
  )
}

verify_frozen_constants <- function(check_log) {
  checks <- list(
    fitting_folds = identical(FITTING_FOLDS, 1:3),
    validation_fold = identical(VALIDATION_FOLD, 4L),
    sealed_test_fold = identical(SEALED_TEST_FOLD, 5L),
    grids = identical(GRID_WIDTHS, c(30L, 40L, 50L)),
    run_order_is_same_grid_set = setequal(RUN_ORDER, GRID_WIDTHS),
    gam_basis_size = identical(GAM_BASIS_SIZE, 20L),
    posterior_draws = identical(POSTERIOR_DRAWS, 4000L),
    model_threads = identical(MODEL_THREADS, 1L),
    fallback_sample_seed = identical(FALLBACK_SAMPLE_SEED, 20260831L),
    active_player_count = identical(
      ACTIVE_PLAYER_COUNT,
      if (IS_CAR_BENCHMARK) 318L else 40L
    ),
    sparse_player_count = identical(
      ACTIVE_SPARSE_PLAYER_COUNT,
      if (IS_CAR_BENCHMARK) 80L else 10L
    ),
    experiment_scope = identical(
      EXPERIMENT_SCOPE,
      if (IS_CAR_BENCHMARK) {
        "all_318_players_training_only_car_benchmark"
      } else {
        "predeclared_40_player_fallback"
      }
    ),
    fixed_benchmark_grid = !IS_CAR_BENCHMARK ||
      identical(GRID_EXPECTED_CELLS[["40"]], 156L),
    gam_seed = identical(GAM_DRAW_SEED, 20260901L),
    car_seed = identical(CAR_DRAW_SEED, 20260902L),
    predictive_seed = identical(PREDICTIVE_SEED, 20260903L),
    bootstrap_seed = identical(VALIDATION_BOOTSTRAP_SEED, 20260904L)
  )
  for (check in names(checks)) {
    check_or_stop(
      check_log, "configuration", check = check,
      condition = checks[[check]], detail = "matches frozen plan"
    )
  }
}

read_metadata_without_outcomes <- function() {
  schema_names <- names(read_parquet(raw_path, as_data_frame = FALSE)$schema)
  missing <- setdiff(OUTCOME_COLUMNS, schema_names)
  if (length(missing) > 0L) {
    stop("Raw data is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  # SHOT_MADE_FLAG is deliberately absent. This is the only full-season read.
  read_parquet(raw_path, col_select = all_of(METADATA_COLUMNS)) |>
    as_tibble()
}

validate_metadata <- function(metadata) {
  if (!is.character(metadata$GAME_ID) || any(!grepl("^0", metadata$GAME_ID))) {
    stop("GAME_ID must remain text with leading zeros", call. = FALSE)
  }
  if (anyNA(metadata)) {
    stop("Required shot metadata contains missing values", call. = FALSE)
  }
  if (!identical(sort(unique(as.integer(metadata$SHOT_ATTEMPTED_FLAG))), 1L)) {
    stop("SHOT_ATTEMPTED_FLAG must contain only 1", call. = FALSE)
  }
  if (any(metadata$LOC_X < COURT_X_MIN | metadata$LOC_X > COURT_X_MAX)) {
    stop("Shot x-coordinate falls outside the frozen court boundary", call. = FALSE)
  }
  if (any(metadata$LOC_Y < COURT_Y_MIN)) {
    stop("Shot y-coordinate falls below the frozen baseline", call. = FALSE)
  }
  invisible(metadata)
}

read_fold_artifact <- function(check_log) {
  if (!file.exists(fold_path)) {
    stop("Missing frozen game split artifact: ", fold_path, call. = FALSE)
  }
  split_hash <- sha256_file(fold_path)
  check_or_stop(
    check_log, "split", check = "split_sha256",
    condition = split_hash == EXPECTED_SPLIT_SHA256,
    detail = paste("SHA-256", split_hash)
  )
  folds <- read_parquet(fold_path) |>
    as_tibble() |>
    arrange(GAME_ID)
  check_or_stop(
    check_log, "split", check = "fold_rows_unique",
    condition = nrow(folds) == 1230L && n_distinct(folds$GAME_ID) == 1230L,
    detail = paste(nrow(folds), "rows and", n_distinct(folds$GAME_ID), "games")
  )
  fold_counts <- count(folds, fold)
  check_or_stop(
    check_log, "split", check = "five_balanced_folds",
    condition = identical(fold_counts$fold, 1:5) && all(fold_counts$n == 246L),
    detail = paste(fold_counts$n, collapse = ",")
  )
  folds
}

read_verified_fallback_sample <- function(joined, all_eligible, check_log) {
  if (!file.exists(sample_path)) {
    stop("Missing pre-declared fallback sample artifact: ", sample_path, call. = FALSE)
  }
  sample_hash <- sha256_file(sample_path)
  check_or_stop(
    check_log, "sample", check = "fallback_sample_sha256",
    condition = sample_hash == EXPECTED_SAMPLE_SHA256,
    detail = paste("SHA-256", sample_hash)
  )

  saved <- read_parquet(sample_path) |>
    as_tibble() |>
    arrange(volume_group, PLAYER_ID)
  required <- c(
    "PLAYER_ID", "PLAYER_NAME", "season_attempts", "season_games",
    "training_attempts", "volume_group"
  )
  missing <- setdiff(required, names(saved))
  if (length(missing) > 0L) {
    stop("Fallback sample is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  training_volume <- joined |>
    filter(fold %in% FITTING_FOLDS, PLAYER_ID %in% all_eligible$PLAYER_ID) |>
    count(PLAYER_ID, name = "training_attempts")
  sampled_frame <- all_eligible |>
    inner_join(training_volume, by = "PLAYER_ID") |>
    arrange(training_attempts, PLAYER_ID) |>
    mutate(volume_group = ntile(row_number(), 4L))
  check_or_stop(
    check_log, "sample", check = "fallback_sampling_frame",
    condition = nrow(sampled_frame) == EXPECTED_ALL_ELIGIBLE_PLAYERS &&
      all(sampled_frame$training_attempts > 0L),
    detail = paste(nrow(sampled_frame), "eligible players with fitting attempts")
  )

  set_frozen_rng(FALLBACK_SAMPLE_SEED)
  expected <- sampled_frame |>
    group_by(volume_group) |>
    slice(sample.int(n(), 10L, replace = FALSE)) |>
    ungroup() |>
    arrange(volume_group, PLAYER_ID)
  group_counts <- count(saved, volume_group)
  check_or_stop(
    check_log, "sample", check = "fallback_sample_dimensions",
    condition = nrow(saved) == EXPECTED_FALLBACK_PLAYERS &&
      n_distinct(saved$PLAYER_ID) == EXPECTED_FALLBACK_PLAYERS &&
      identical(group_counts$volume_group, 1:4) &&
      all(group_counts$n == 10L),
    detail = paste(nrow(saved), "players; quartile counts", paste(group_counts$n, collapse = ","))
  )
  check_or_stop(
    check_log, "sample", check = "fallback_selection_reproduced",
    condition = same_table(expected, saved),
    detail = "seed 20260831 reproduced 10 players from each fitting-volume quartile"
  )
  saved
}

prepare_metadata <- function(metadata, folds, check_log) {
  validate_metadata(metadata)
  joined <- metadata |>
    filter(LOC_Y <= COURT_Y_MAX) |>
    left_join(folds, by = "GAME_ID")
  check_or_stop(
    check_log, "data", check = "all_in_play_shots_have_fold",
    condition = !anyNA(joined$fold),
    detail = paste(nrow(joined), "in-play shots")
  )
  all_eligible <- joined |>
    summarise(
      PLAYER_NAME = first(PLAYER_NAME),
      season_attempts = n(),
      season_games = n_distinct(GAME_ID),
      .by = PLAYER_ID
    ) |>
    filter(season_games >= MIN_GAMES, season_attempts >= MIN_ATTEMPTS) |>
    arrange(PLAYER_ID)
  check_or_stop(
    check_log, "data", check = "eligible_player_count",
    condition = nrow(all_eligible) == EXPECTED_ALL_ELIGIBLE_PLAYERS &&
      n_distinct(all_eligible$PLAYER_ID) == EXPECTED_ALL_ELIGIBLE_PLAYERS,
    detail = paste(nrow(all_eligible), "all-season eligible players")
  )
  if (IS_CAR_BENCHMARK) {
    fallback_sample <- tibble()
    eligible <- all_eligible |>
      select(PLAYER_ID, PLAYER_NAME, season_attempts, season_games) |>
      arrange(PLAYER_ID)
  } else {
    fallback_sample <- read_verified_fallback_sample(
      joined, all_eligible, check_log
    )
    eligible <- fallback_sample |>
      select(PLAYER_ID, PLAYER_NAME, season_attempts, season_games) |>
      arrange(PLAYER_ID)
  }
  check_or_stop(
    check_log, "data", check = if (IS_CAR_BENCHMARK) {
      "full_league_player_count"
    } else {
      "activated_fallback_player_count"
    },
    condition = nrow(eligible) == ACTIVE_PLAYER_COUNT &&
      n_distinct(eligible$PLAYER_ID) == ACTIVE_PLAYER_COUNT,
    detail = paste(nrow(eligible), if (IS_CAR_BENCHMARK) {
      "all-season eligible players"
    } else {
      "pre-declared fallback players"
    })
  )

  player_fold_counts <- joined |>
    filter(PLAYER_ID %in% eligible$PLAYER_ID) |>
    count(PLAYER_ID, fold, name = "attempts") |>
    complete(PLAYER_ID = eligible$PLAYER_ID, fold = 1:5, fill = list(attempts = 0L))
  fitting_counts <- player_fold_counts |>
    filter(fold %in% FITTING_FOLDS) |>
    summarise(fitting_attempts = sum(attempts), .by = PLAYER_ID)
  validation_counts <- player_fold_counts |>
    filter(fold == VALIDATION_FOLD) |>
    transmute(PLAYER_ID, validation_attempts = attempts)
  test_counts <- player_fold_counts |>
    filter(fold == SEALED_TEST_FOLD) |>
    transmute(PLAYER_ID, test_attempts_metadata_only = attempts)
  coverage <- eligible |>
    select(PLAYER_ID) |>
    left_join(fitting_counts, by = "PLAYER_ID") |>
    left_join(validation_counts, by = "PLAYER_ID") |>
    left_join(test_counts, by = "PLAYER_ID")
  check_or_stop(
    check_log, "data", check = "every_player_has_fitting_shots",
    condition = all(coverage$fitting_attempts > 0L),
    detail = paste(min(coverage$fitting_attempts), "minimum fitting attempts")
  )
  check_or_stop(
    check_log, "data", check = "every_player_has_validation_shots",
    condition = all(coverage$validation_attempts > 0L),
    detail = paste(min(coverage$validation_attempts), "minimum validation attempts")
  )
  # This uses metadata only and satisfies the pre-registered coverage stop rule
  # without ever loading fold-5 make/miss outcomes.
  check_or_stop(
    check_log, "data", check = "every_player_has_test_shots_metadata_only",
    condition = all(coverage$test_attempts_metadata_only > 0L),
    detail = paste(min(coverage$test_attempts_metadata_only), "minimum test attempts")
  )

  sparse_players <- coverage |>
    arrange(fitting_attempts, PLAYER_ID) |>
    mutate(volume_quarter = ntile(row_number(), 4L)) |>
    filter(volume_quarter == 1L) |>
    arrange(PLAYER_ID)
  check_or_stop(
    check_log, "data", check = "sparse_player_definition_pre_validation",
    condition = nrow(sparse_players) == ACTIVE_SPARSE_PLAYER_COUNT,
    detail = "bottom quarter by folds 1-3 attempt count; ties resolved by PLAYER_ID"
  )
  list(
    in_play_metadata = joined,
    eligible = eligible,
    coverage = coverage,
    sparse_players = sparse_players,
    fallback_sample = fallback_sample
  )
}

# Hard seal: every call is rejected before SHOT_MADE_FLAG can be selected if
# fold 5 appears in the requested set. The Arrow filter is applied before the
# outcome column is collected into R.
read_allowed_outcomes <- function(folds, requested_folds, eligible_players) {
  requested_folds <- sort(unique(as.integer(requested_folds)))
  if (SEALED_TEST_FOLD %in% requested_folds) {
    stop(
      "SEALED TEST SAFEGUARD: fold 5 outcomes may not be requested or read",
      call. = FALSE
    )
  }
  if (!all(requested_folds %in% c(FITTING_FOLDS, VALIDATION_FOLD))) {
    stop("Outcome request contains an undeclared fold", call. = FALSE)
  }
  allowed_games <- folds$GAME_ID[folds$fold %in% requested_folds]
  outcomes <- open_dataset(raw_path) |>
    filter(GAME_ID %in% allowed_games, PLAYER_ID %in% eligible_players) |>
    select(all_of(OUTCOME_COLUMNS)) |>
    collect() |>
    as_tibble() |>
    left_join(select(folds, GAME_ID, fold), by = "GAME_ID")
  if (anyNA(outcomes$fold) || any(!outcomes$fold %in% requested_folds)) {
    stop("Outcome loader returned a row outside the explicitly allowed folds", call. = FALSE)
  }
  if (any(outcomes$fold == SEALED_TEST_FOLD)) {
    stop("SEALED TEST SAFEGUARD: a fold 5 outcome reached memory", call. = FALSE)
  }
  if (anyNA(outcomes$SHOT_MADE_FLAG) ||
      !all(outcomes$SHOT_MADE_FLAG %in% c(0L, 1L))) {
    stop("SHOT_MADE_FLAG must contain only 0 or 1", call. = FALSE)
  }
  outcomes |>
    filter(LOC_Y <= COURT_Y_MAX)
}

make_grid <- function(grid_width) {
  nx <- as.integer(ceiling((COURT_X_MAX - COURT_X_MIN) / grid_width))
  ny <- as.integer(ceiling((COURT_Y_MAX - COURT_Y_MIN) / grid_width))
  grid <- expand_grid(x_index = seq_len(nx), y_index = seq_len(ny)) |>
    mutate(
      cell_id = (y_index - 1L) * nx + x_index,
      x_left = COURT_X_MIN + (x_index - 1L) * grid_width,
      x_right = pmin(x_left + grid_width, COURT_X_MAX),
      y_bottom = COURT_Y_MIN + (y_index - 1L) * grid_width,
      y_top = pmin(y_bottom + grid_width, COURT_Y_MAX),
      x_ft = ((x_left + x_right) / 2) / 10,
      y_ft = ((y_bottom + y_top) / 2) / 10
    ) |>
    select(x_index, y_index, cell_id, x_ft, y_ft) |>
    arrange(cell_id)
  expected <- GRID_EXPECTED_CELLS[[as.character(grid_width)]]
  if (nrow(grid) != expected) {
    stop("Grid ", grid_width, " has ", nrow(grid), " cells; expected ", expected,
         call. = FALSE)
  }
  attr(grid, "nx") <- nx
  attr(grid, "ny") <- ny
  grid
}

assign_grid_cells <- function(shots, grid_width, grid) {
  nx <- attr(grid, "nx")
  ny <- attr(grid, "ny")
  assigned <- shots |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / grid_width)) + 1L,
        nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / grid_width)) + 1L,
        ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    )
  if (any(!assigned$cell_id %in% grid$cell_id)) {
    stop("At least one shot was not assigned to grid ", grid_width, call. = FALSE)
  }
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
  n <- nrow(graph)
  visited <- rep(FALSE, n)
  queue <- 1L
  visited[[1]] <- TRUE
  while (length(queue) > 0L) {
    current <- queue[[1]]
    queue <- queue[-1L]
    neighbours <- which(graph[current, ] != 0)
    new_neighbours <- neighbours[!visited[neighbours]]
    if (length(new_neighbours) > 0L) {
      visited[new_neighbours] <- TRUE
      queue <- c(queue, new_neighbours)
    }
  }
  all(visited)
}

build_model_data <- function(training_shots, validation_shots, eligible, grid_width,
                             check_log) {
  grid <- make_grid(grid_width)
  training <- assign_grid_cells(training_shots, grid_width, grid)
  validation <- assign_grid_cells(validation_shots, grid_width, grid)
  player_levels <- sort(eligible$PLAYER_ID)

  observed <- training |>
    summarise(
      makes = sum(SHOT_MADE_FLAG),
      attempts = n(),
      .by = c(PLAYER_ID, cell_id)
    ) |>
    arrange(PLAYER_ID, cell_id)
  lattice <- tibble(PLAYER_ID = player_levels) |>
    crossing(grid) |>
    left_join(observed, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      makes = coalesce(as.integer(makes), 0L),
      attempts = coalesce(as.integer(attempts), 0L),
      player_factor = factor(PLAYER_ID, levels = player_levels),
      player_index = as.integer(player_factor),
      predictor_index = row_number()
    ) |>
    arrange(PLAYER_ID, cell_id)
  validation <- validation |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  validation_cell_counts <- validation |>
    count(PLAYER_ID, cell_id, name = "validation_attempts")
  lattice <- lattice |>
    left_join(validation_cell_counts, by = c("PLAYER_ID", "cell_id")) |>
    mutate(validation_attempts = coalesce(as.integer(validation_attempts), 0L)) |>
    arrange(PLAYER_ID, cell_id) |>
    mutate(predictor_index = row_number())

  expected_rows <- length(player_levels) * nrow(grid)
  check_or_stop(
    check_log, "fairness", grid_width, check = "full_lattice_dimensions",
    condition = nrow(lattice) == expected_rows,
    detail = paste(length(player_levels), "players x", nrow(grid), "cells")
  )
  check_or_stop(
    check_log, "fairness", grid_width, check = "training_attempts_preserved",
    condition = sum(lattice$attempts) == nrow(training),
    detail = paste(sum(lattice$attempts), "attempts")
  )
  check_or_stop(
    check_log, "fairness", grid_width, check = "training_makes_preserved",
    condition = sum(lattice$makes) == sum(training$SHOT_MADE_FLAG),
    detail = paste(sum(lattice$makes), "makes")
  )
  check_or_stop(
    check_log, "fairness", grid_width, check = "validation_rows_preserved",
    condition = nrow(validation) == nrow(validation_shots),
    detail = paste(nrow(validation), "validation shots")
  )
  check_or_stop(
    check_log, "fairness", grid_width, check = "player_levels_identical",
    condition = identical(levels(lattice$player_factor), as.character(player_levels)),
    detail = paste(length(player_levels), "sorted player levels")
  )

  graph_matrix <- make_graph(grid)
  degrees <- Matrix::rowSums(graph_matrix)
  check_or_stop(
    check_log, "fairness", grid_width, check = "graph_binary_symmetric_zero_diagonal",
    condition = all(graph_matrix@x == 1) &&
      isTRUE(all.equal(graph_matrix, Matrix::t(graph_matrix))) &&
      all(Matrix::diag(graph_matrix) == 0),
    detail = paste(Matrix::nnzero(graph_matrix) / 2, "undirected rook edges")
  )
  check_or_stop(
    check_log, "fairness", grid_width, check = "graph_connected_no_isolates",
    condition = all(degrees > 0) && graph_is_connected(graph_matrix),
    detail = paste("degree range", min(degrees), "to", max(degrees))
  )

  gam_observed <- lattice |>
    filter(attempts > 0L) |>
    select(PLAYER_ID, cell_id, makes, attempts) |>
    arrange(PLAYER_ID, cell_id)
  car_observed <- lattice |>
    filter(attempts > 0L) |>
    select(PLAYER_ID, cell_id, makes, attempts) |>
    arrange(PLAYER_ID, cell_id)
  check_or_stop(
    check_log, "fairness", grid_width, check = "identical_observed_player_cells",
    condition = same_table(gam_observed, car_observed),
    detail = paste(nrow(gam_observed), "identical observed player-cells")
  )

  list(
    grid = grid,
    lattice = lattice,
    validation = validation,
    graph_matrix = graph_matrix,
    player_levels = player_levels
  )
}

minimum_surface_rmse <- function(centered_surface, cells_per_player, n_players) {
  surface_matrix <- matrix(
    centered_surface,
    nrow = cells_per_player,
    ncol = n_players
  )
  distances <- as.matrix(dist(t(surface_matrix))) / sqrt(cells_per_player)
  distances[lower.tri(distances, diag = TRUE)] <- NA_real_
  min(distances, na.rm = TRUE)
}

simulate_totals <- function(probability_draws, attempts) {
  if (nrow(probability_draws) != length(attempts) ||
      ncol(probability_draws) != POSTERIOR_DRAWS) {
    stop("Posterior predictive dimensions do not match attempts", call. = FALSE)
  }
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

evaluate_predictions <- function(validation, probabilities, grid_width, model) {
  scored <- validation |>
    select(shot_id, GAME_ID, PLAYER_ID, cell_id, SHOT_MADE_FLAG) |>
    left_join(probabilities, by = c("PLAYER_ID", "cell_id"))
  if (anyNA(scored$probability) || nrow(scored) != nrow(validation)) {
    stop("Validation predictions failed to match every shot", call. = FALSE)
  }
  scored <- scored |>
    mutate(
      probability_for_log = pmin(
        pmax(probability, LOG_EPSILON),
        1 - LOG_EPSILON
      ),
      log_loss = -(
        SHOT_MADE_FLAG * log(probability_for_log) +
          (1 - SHOT_MADE_FLAG) * log(1 - probability_for_log)
      ),
      grid_width = as.integer(grid_width),
      model = model
    ) |>
    select(
      shot_id, GAME_ID, PLAYER_ID, cell_id, SHOT_MADE_FLAG,
      grid_width, model, probability, log_loss
    )
  calibration <- scored |>
    arrange(probability, GAME_ID, PLAYER_ID, shot_id) |>
    mutate(calibration_bin = ntile(row_number(), 10L)) |>
    summarise(
      attempts = n(),
      predicted_probability = mean(probability),
      observed_make_rate = mean(SHOT_MADE_FLAG),
      calibration_gap = observed_make_rate - predicted_probability,
      .by = calibration_bin
    ) |>
    mutate(grid_width = as.integer(grid_width), model = model, .before = 1)
  player_calibration <- scored |>
    summarise(
      attempts = n(),
      predicted_makes = sum(probability),
      actual_makes = sum(SHOT_MADE_FLAG),
      prediction_error = actual_makes - predicted_makes,
      .by = PLAYER_ID
    ) |>
    mutate(grid_width = as.integer(grid_width), model = model, .before = 1)
  list(scored = scored, calibration = calibration, player = player_calibration)
}

fit_gam <- function(model_data, sparse_players, grid_width, check_log) {
  lattice <- model_data$lattice
  observed <- lattice |>
    filter(attempts > 0L) |>
    arrange(PLAYER_ID, cell_id)
  gam_formula <- cbind(makes, attempts - makes) ~ 0 + player_factor +
    s(
      x_ft, y_ft,
      by = player_factor,
      bs = "tp",
      m = 2,
      k = 20,
      id = 1
    )

  fit_started <- proc.time()[["elapsed"]]
  captured <- condition_capture(mgcv::bam(
    gam_formula,
    family = binomial(link = "logit"),
    data = observed,
    method = "fREML",
    discrete = FALSE,
    select = FALSE,
    gamma = 1,
    nthreads = MODEL_THREADS,
    na.action = na.fail
  ))
  fit_elapsed <- proc.time()[["elapsed"]] - fit_started
  fit <- captured$value

  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_converged",
    isTRUE(fit$converged), paste("converged =", fit$converged)
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_finite_coefficients",
    all(is.finite(coef(fit))), paste(length(coef(fit)), "finite coefficients")
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_one_shared_smoothing_parameter",
    length(fit$sp) == 1L, paste(length(fit$sp), "smoothing parameters")
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_one_smooth_per_player",
    length(fit$smooth) == length(model_data$player_levels),
    paste(length(fit$smooth), "smooths")
  )
  smooth_edf <- vapply(
    fit$smooth,
    function(smooth) sum(fit$edf[smooth$first.para:smooth$last.para]),
    numeric(1)
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_basis_ceiling",
    all(smooth_edf < GAM_EDF_LIMIT),
    paste("maximum smooth EDF", format(max(smooth_edf), digits = 8),
          "must be below", GAM_EDF_LIMIT)
  )

  prediction_started <- proc.time()[["elapsed"]]
  covariance <- vcov(fit, unconditional = TRUE)
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_finite_unconditional_covariance",
    all(is.finite(covariance)), paste(dim(covariance), collapse = " x ")
  )
  set_frozen_rng(GAM_DRAW_SEED)
  coefficient_draws <- mgcv::rmvn(
    POSTERIOR_DRAWS,
    mu = coef(fit),
    V = covariance
  )

  probability_parts <- vector("list", length(model_data$player_levels))
  centered_links <- numeric(nrow(lattice))
  sparse_probability_draws <- list()
  sparse_ids <- sparse_players$PLAYER_ID

  for (player_position in seq_along(model_data$player_levels)) {
    player_id <- model_data$player_levels[[player_position]]
    rows <- which(lattice$PLAYER_ID == player_id)
    player_lattice <- lattice[rows, ]
    design <- predict(
      fit,
      newdata = player_lattice,
      type = "lpmatrix",
      discrete = FALSE
    )
    active <- which(colSums(abs(design)) > 0)
    eta_draws <- design[, active, drop = FALSE] %*%
      t(coefficient_draws[, active, drop = FALSE])
    probability_draws <- plogis(eta_draws)
    point_probability <- rowMeans(probability_draws)
    probability_parts[[player_position]] <- tibble(
      PLAYER_ID = player_id,
      cell_id = player_lattice$cell_id,
      probability = point_probability
    )
    plugin_link <- as.numeric(design[, active, drop = FALSE] %*%
                                coef(fit)[active])
    centered_links[rows] <- plugin_link - mean(plugin_link)
    if (player_id %in% sparse_ids) {
      used <- player_lattice$validation_attempts > 0L
      sparse_probability_draws[[as.character(player_id)]] <- list(
        probabilities = probability_draws[used, , drop = FALSE],
        attempts = player_lattice$validation_attempts[used]
      )
    }
  }
  probabilities <- bind_rows(probability_parts) |>
    arrange(PLAYER_ID, cell_id)
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_finite_predictions",
    all(is.finite(probabilities$probability)),
    paste(nrow(probabilities), "finite full-lattice probabilities")
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_probability_bounds",
    all(probabilities$probability >= 0 & probabilities$probability <= 1),
    paste("range", paste(range(probabilities$probability), collapse = " to "))
  )
  minimum_rmse <- minimum_surface_rmse(
    centered_links,
    nrow(model_data$grid),
    length(model_data$player_levels)
  )
  check_or_stop(
    check_log, "model", grid_width, "GAM", "gam_distinct_player_surfaces",
    is.finite(minimum_rmse) && minimum_rmse > SURFACE_TOLERANCE,
    paste("minimum centered-surface RMSE", format(minimum_rmse, digits = 8))
  )

  set_frozen_rng(PREDICTIVE_SEED)
  sparse_intervals <- lapply(sparse_ids, function(player_id) {
    values <- sparse_probability_draws[[as.character(player_id)]]
    total_draws <- simulate_totals(values$probabilities, values$attempts)
    tibble(
      PLAYER_ID = player_id,
      interval_lower = as.numeric(quantile(total_draws, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(total_draws, 0.95, names = FALSE)),
      interval_width = interval_upper - interval_lower
    )
  }) |>
    bind_rows() |>
    mutate(grid_width = as.integer(grid_width), model = "GAM", .before = 1)
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started

  fit_path <- file.path(cache_dir, paste0("gam_grid_", grid_width, "_fit.rds"))
  save_atomic_fit(fit, fit_path)
  metrics <- tibble(
    grid_width = as.integer(grid_width),
    model = "GAM",
    formula = paste(deparse(gam_formula), collapse = " "),
    fit_elapsed_sec = fit_elapsed,
    prediction_elapsed_sec = prediction_elapsed,
    model_object_bytes = as.numeric(object.size(fit)),
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    message_count = length(captured$messages),
    messages = paste(captured$messages, collapse = " | "),
    coefficient_count = length(coef(fit)),
    spatial_effect_count = length(model_data$player_levels) * nrow(model_data$grid),
    hyperparameter_count = length(fit$sp),
    maximum_smooth_edf = max(smooth_edf),
    minimum_centered_surface_rmse = minimum_rmse
  )
  rm(coefficient_draws, covariance, sparse_probability_draws, fit)
  gc()
  list(probabilities = probabilities, sparse = sparse_intervals, metrics = metrics)
}

extract_selected_predictors <- function(samples, expected_indices) {
  first <- samples[[1]]$latent
  labels <- rownames(first)
  if (is.null(labels)) {
    stop("R-INLA posterior sample did not label selected predictors", call. = FALSE)
  }
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  if (anyNA(parsed) || !setequal(parsed, expected_indices)) {
    stop("R-INLA posterior sample predictor selection did not match requested rows",
         call. = FALSE)
  }
  sample_matrix <- vapply(
    samples,
    function(sample) as.numeric(sample$latent),
    numeric(length(expected_indices))
  )
  sample_matrix[match(expected_indices, parsed), , drop = FALSE]
}

fit_car <- function(model_data, sparse_players, grid_width, check_log) {
  lattice <- model_data$lattice |>
    mutate(
      y = if_else(attempts > 0L, makes, NA_integer_),
      trials = if_else(attempts > 0L, attempts, 1L)
    )
  graph <- INLA::inla.read.graph(model_data$graph_matrix)
  n_players <- length(model_data$player_levels)
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

  fit_started <- proc.time()[["elapsed"]]
  captured <- condition_capture(INLA::inla(
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
  fit <- captured$value

  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_fit_ok",
    isTRUE(fit$ok), paste("fit$ok =", fit$ok)
  )
  mode_status <- fit$mode$mode.status
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_no_warning_or_retry",
    length(captured$warnings) == 0L && identical(as.numeric(mode_status), 0),
    paste(length(captured$warnings), "R warnings; mode status", mode_status,
          "; safe = FALSE")
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_fixed_effect_count",
    nrow(fit$summary.fixed) == n_players,
    paste(nrow(fit$summary.fixed), "fixed player intercepts")
  )
  expected_spatial <- n_players * nrow(model_data$grid)
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_replicated_spatial_count",
    nrow(fit$summary.random$cell_id) == expected_spatial,
    paste(nrow(fit$summary.random$cell_id), "spatial values")
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_hyperparameter_count",
    nrow(fit$summary.hyperpar) == 2L,
    paste(nrow(fit$summary.hyperpar), "shared CAR hyperparameters")
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_predictor_count",
    nrow(fit$summary.linear.predictor) == nrow(lattice),
    paste(nrow(fit$summary.linear.predictor), "full-lattice predictors")
  )
  posterior_values <- c(
    fit$summary.fixed$mean,
    fit$summary.random$cell_id$mean,
    fit$summary.hyperpar$mean,
    fit$summary.linear.predictor$mean,
    fit$summary.fitted.values$mean
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_finite_posterior_summaries",
    all(is.finite(posterior_values)),
    paste(length(posterior_values), "finite posterior summary values")
  )

  prediction_started <- proc.time()[["elapsed"]]
  probabilities <- lattice |>
    transmute(
      PLAYER_ID,
      cell_id,
      probability = fit$summary.fitted.values$mean
    ) |>
    arrange(PLAYER_ID, cell_id)
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_finite_predictions",
    all(is.finite(probabilities$probability)),
    paste(nrow(probabilities), "finite full-lattice probabilities")
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_probability_bounds",
    all(probabilities$probability >= 0 & probabilities$probability <= 1),
    paste("range", paste(range(probabilities$probability), collapse = " to "))
  )
  centered_links <- fit$summary.linear.predictor$mean -
    ave(fit$summary.linear.predictor$mean, lattice$PLAYER_ID, FUN = mean)
  minimum_rmse <- minimum_surface_rmse(
    centered_links,
    nrow(model_data$grid),
    n_players
  )
  check_or_stop(
    check_log, "model", grid_width, "CAR", "car_distinct_player_surfaces",
    is.finite(minimum_rmse) && minimum_rmse > SURFACE_TOLERANCE,
    paste("minimum centered-surface RMSE", format(minimum_rmse, digits = 8))
  )

  sparse_ids <- sparse_players$PLAYER_ID
  selected_lattice <- lattice |>
    filter(PLAYER_ID %in% sparse_ids, validation_attempts > 0L) |>
    arrange(predictor_index)
  selected_indices <- selected_lattice$predictor_index
  set_frozen_rng(CAR_DRAW_SEED)
  samples <- INLA::inla.posterior.sample(
    n = POSTERIOR_DRAWS,
    result = fit,
    selection = list(Predictor = selected_indices),
    seed = CAR_DRAW_SEED,
    num.threads = MODEL_THREADS,
    parallel.configs = FALSE,
    add.names = FALSE
  )
  predictor_draws <- extract_selected_predictors(samples, selected_indices)
  rm(samples)
  gc()
  set_frozen_rng(PREDICTIVE_SEED)
  sparse_intervals <- lapply(sparse_ids, function(player_id) {
    rows <- which(selected_lattice$PLAYER_ID == player_id)
    probability_draws <- plogis(predictor_draws[rows, , drop = FALSE])
    total_draws <- simulate_totals(
      probability_draws,
      selected_lattice$validation_attempts[rows]
    )
    tibble(
      PLAYER_ID = player_id,
      interval_lower = as.numeric(quantile(total_draws, 0.05, names = FALSE)),
      interval_upper = as.numeric(quantile(total_draws, 0.95, names = FALSE)),
      interval_width = interval_upper - interval_lower
    )
  }) |>
    bind_rows() |>
    mutate(grid_width = as.integer(grid_width), model = "CAR", .before = 1)
  prediction_elapsed <- proc.time()[["elapsed"]] - prediction_started

  fit_path <- file.path(cache_dir, paste0("car_grid_", grid_width, "_fit.rds"))
  save_atomic_fit(fit, fit_path)
  metrics <- tibble(
    grid_width = as.integer(grid_width),
    model = "CAR",
    formula = paste(deparse(car_formula), collapse = " "),
    fit_elapsed_sec = fit_elapsed,
    prediction_elapsed_sec = prediction_elapsed,
    model_object_bytes = as.numeric(object.size(fit)),
    serialized_model_bytes = as.numeric(file.size(fit_path)),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    warning_count = length(captured$warnings),
    warnings = paste(captured$warnings, collapse = " | "),
    message_count = length(captured$messages),
    messages = paste(captured$messages, collapse = " | "),
    coefficient_count = nrow(fit$summary.fixed),
    spatial_effect_count = nrow(fit$summary.random$cell_id),
    hyperparameter_count = nrow(fit$summary.hyperpar),
    maximum_smooth_edf = NA_real_,
    minimum_centered_surface_rmse = minimum_rmse
  )
  rm(predictor_draws, fit)
  gc()
  list(probabilities = probabilities, sparse = sparse_intervals, metrics = metrics)
}

write_atomic_parquet <- function(table, path) {
  if (file.exists(path)) {
    stop("Refusing to replace an existing benchmark result: ", path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = paste0(basename(path), ".partial-"),
    tmpdir = dirname(path),
    fileext = ".parquet"
  )
  write_parquet(table, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically publish benchmark result; partial file preserved: ",
         temporary, call. = FALSE)
  }
  invisible(path)
}

parse_ps_cpu_seconds <- function(values) {
  vapply(values, function(value) {
    day_parts <- strsplit(value, "-", fixed = TRUE)[[1]]
    days <- if (length(day_parts) == 2L) as.numeric(day_parts[[1]]) else 0
    clock <- as.numeric(strsplit(tail(day_parts, 1L), ":", fixed = TRUE)[[1]])
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
  process_table <- read.table(
    text = output,
    col.names = c("pid", "ppid", "rss_kb", "cpu_time"),
    colClasses = c("integer", "integer", "numeric", "character")
  )
  descendants <- as.integer(root_pid)
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

terminate_process_tree <- function(root_pid) {
  snapshot <- process_tree_snapshot(root_pid)
  for (pid in rev(snapshot$pids)) {
    try(tools::pskill(pid, signal = 15L), silent = TRUE)
  }
  Sys.sleep(5)
  remaining <- process_tree_snapshot(root_pid)$pids
  for (pid in rev(remaining)) {
    try(tools::pskill(pid, signal = 9L), silent = TRUE)
  }
  Sys.sleep(1)
  process_tree_snapshot(root_pid)$pids
}

acquire_benchmark_lock <- function() {
  lock_path <- file.path(cache_dir, "active_run.lock")
  if (!dir.create(lock_path, recursive = FALSE, showWarnings = FALSE)) {
    owner_path <- file.path(lock_path, "owner.rds")
    owner <- tryCatch(readRDS(owner_path), error = function(condition) NULL)
    owner_pids <- if (is.null(owner)) integer() else {
      unique(as.integer(c(owner$parent_pid, owner$child_pid)))
    }
    active <- vapply(owner_pids, function(pid) {
      length(system2("ps", c("-p", pid, "-o", "pid="), stdout = TRUE)) > 0L
    }, logical(1))
    if (any(active)) {
      stop(
        "DUPLICATE RUN SAFEGUARD: a full-league CAR benchmark is already active",
        call. = FALSE
      )
    }
    preserved <- paste0(
      lock_path, ".stale-", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(lock_path, preserved) ||
        !dir.create(lock_path, recursive = FALSE, showWarnings = FALSE)) {
      stop("Could not preserve the stale benchmark lock", call. = FALSE)
    }
  }
  owner <- list(
    parent_pid = Sys.getpid(),
    child_pid = NA_integer_,
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    mode = mode,
    season = season
  )
  saveRDS(owner, file.path(lock_path, "owner.rds"))
  list(path = lock_path, owner = owner)
}

update_benchmark_lock <- function(lock, child_pid) {
  lock$owner$child_pid <- as.integer(child_pid)
  temporary <- tempfile(pattern = "owner.rds.partial-", tmpdir = lock$path)
  saveRDS(lock$owner, temporary)
  if (!file.rename(temporary, file.path(lock$path, "owner.rds"))) {
    stop("Could not atomically update the benchmark lock", call. = FALSE)
  }
  lock
}

release_benchmark_lock <- function(lock) {
  owner_path <- file.path(lock$path, "owner.rds")
  owner <- tryCatch(readRDS(owner_path), error = function(condition) NULL)
  if (!is.null(owner) && identical(owner$parent_pid, Sys.getpid())) {
    unlink(lock$path, recursive = TRUE)
  }
  invisible(NULL)
}

car_benchmark_worker <- function(audit, check_log) {
  setup_started <- proc.time()[["elapsed"]]
  training_shots <- read_allowed_outcomes(
    audit$folds,
    FITTING_FOLDS,
    audit$metadata$eligible$PLAYER_ID
  )
  validation_metadata <- audit$metadata$in_play_metadata |>
    filter(
      fold == VALIDATION_FOLD,
      PLAYER_ID %in% audit$metadata$eligible$PLAYER_ID
    ) |>
    arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
  check_or_stop(
    check_log, "seal", check = "fitting_uses_only_folds_1_to_3",
    condition = identical(sort(unique(training_shots$fold)), FITTING_FOLDS),
    detail = paste("folds", paste(sort(unique(training_shots$fold)), collapse = ","))
  )
  check_or_stop(
    check_log, "seal", check = "fold4_metadata_contains_no_outcome",
    condition = identical(sort(unique(validation_metadata$fold)), VALIDATION_FOLD) &&
      !"SHOT_MADE_FLAG" %in% names(validation_metadata),
    detail = paste(nrow(validation_metadata), "fold-4 metadata rows; no outcomes")
  )
  check_or_stop(
    check_log, "seal", check = "only_fitting_outcomes_in_memory",
    condition = !any(training_shots$fold %in% c(VALIDATION_FOLD, SEALED_TEST_FOLD)),
    detail = paste(nrow(training_shots), "outcome rows from folds 1-3 only")
  )

  model_data <- build_model_data(
    training_shots,
    validation_metadata,
    audit$metadata$eligible,
    CAR_BENCHMARK_GRID,
    check_log
  )
  observed_player_cells <- sum(model_data$lattice$attempts > 0L)
  lattice_rows <- nrow(model_data$lattice)
  check_or_stop(
    check_log, "benchmark", CAR_BENCHMARK_GRID, "CAR",
    "full_league_dimensions",
    length(model_data$player_levels) == EXPECTED_ALL_ELIGIBLE_PLAYERS &&
      nrow(model_data$grid) == GRID_EXPECTED_CELLS[["40"]] &&
      lattice_rows == 49608L,
    paste(length(model_data$player_levels), "players x", nrow(model_data$grid),
          "cells =", lattice_rows, "lattice rows")
  )
  setup_elapsed <- proc.time()[["elapsed"]] - setup_started
  checkpoint_reused <- file.exists(checkpoint_path(CAR_BENCHMARK_GRID, "CAR"))
  car <- run_or_reuse_model(
    CAR_BENCHMARK_GRID,
    "CAR",
    lattice_rows,
    ACTIVE_SPARSE_PLAYER_COUNT,
    check_log,
    function() fit_car(
      model_data,
      audit$metadata$sparse_players,
      CAR_BENCHMARK_GRID,
      check_log
    )
  )
  sparse_limits <- model_data$lattice |>
    filter(PLAYER_ID %in% audit$metadata$sparse_players$PLAYER_ID) |>
    summarise(validation_attempts = sum(validation_attempts), .by = PLAYER_ID)
  verified_sparse <- car$sparse |>
    left_join(sparse_limits, by = "PLAYER_ID")
  check_or_stop(
    check_log, "model", CAR_BENCHMARK_GRID, "CAR",
    "car_sparse_uncertainty_dimensions",
    nrow(verified_sparse) == ACTIVE_SPARSE_PLAYER_COUNT &&
      n_distinct(verified_sparse$PLAYER_ID) == ACTIVE_SPARSE_PLAYER_COUNT,
    paste(nrow(verified_sparse), "pre-declared sparse-player intervals")
  )
  check_or_stop(
    check_log, "model", CAR_BENCHMARK_GRID, "CAR",
    "car_sparse_uncertainty_finite_ordered",
    all(is.finite(verified_sparse$interval_lower)) &&
      all(is.finite(verified_sparse$interval_upper)) &&
      all(is.finite(verified_sparse$interval_width)) &&
      all(verified_sparse$interval_lower >= 0) &&
      all(verified_sparse$interval_lower <= verified_sparse$interval_upper) &&
      all(verified_sparse$interval_upper <= verified_sparse$validation_attempts),
    "all 90% posterior-predictive intervals are finite, ordered, and feasible"
  )
  checks <- bind_rows(check_log$records)
  if (!all(checks$passed)) {
    stop("At least one frozen sanity check did not pass", call. = FALSE)
  }
  list(
    metrics = car$metrics |>
      mutate(
        season = season,
        experiment_scope = EXPERIMENT_SCOPE,
        specification_id = MODEL_SPECIFICATION_ID,
        fitting_folds = paste(FITTING_FOLDS, collapse = ","),
        fold4_outcomes_read = FALSE,
        fold5_outcomes_read = FALSE,
        completed = TRUE,
        timed_out = FALSE,
        failed = FALSE,
        runtime_ceiling_sec = CAR_BENCHMARK_CEILING_SEC,
        setup_elapsed_sec = setup_elapsed,
        player_count = length(model_data$player_levels),
        training_shot_count = nrow(training_shots),
        observed_player_cell_count = observed_player_cells,
        cells_per_player = nrow(model_data$grid),
        lattice_row_count = lattice_rows,
        approximate_unknown_count = lattice_rows +
          length(model_data$player_levels) + 2L,
        checkpoint_reused = checkpoint_reused,
        r_version = as.character(getRversion()),
        inla_version = as.character(packageVersion("INLA")),
        matrix_version = as.character(packageVersion("Matrix")),
        fmesher_version = as.character(packageVersion("fmesher")),
        sn_version = as.character(packageVersion("sn")),
        arrow_version = as.character(packageVersion("arrow")),
        dplyr_version = as.character(packageVersion("dplyr")),
        tidyr_version = as.character(packageVersion("tidyr")),
        split_sha256 = EXPECTED_SPLIT_SHA256,
        car_draw_seed = CAR_DRAW_SEED,
        predictive_seed = PREDICTIVE_SEED
      ),
    uncertainty = verified_sparse |>
      summarise(
        sparse_player_count = n(),
        minimum_interval_width = min(interval_width),
        mean_interval_width = mean(interval_width),
        maximum_interval_width = max(interval_width),
        all_intervals_finite_ordered_feasible = TRUE
      ) |>
      mutate(
        season = season,
        experiment_scope = EXPERIMENT_SCOPE,
        grid_width = CAR_BENCHMARK_GRID,
        fold4_outcomes_read = FALSE,
        fold5_outcomes_read = FALSE,
        .before = 1
      ),
    checks = checks |>
      mutate(
        season = season,
        experiment_scope = EXPERIMENT_SCOPE,
        fold4_outcomes_read = FALSE,
        fold5_outcomes_read = FALSE,
        .before = 1
      )
  )
}

write_car_benchmark_results <- function(result) {
  dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
  write_atomic_parquet(
    result$metrics,
    file.path(result_dir, "benchmark_metrics.parquet")
  )
  write_atomic_parquet(
    result$uncertainty,
    file.path(result_dir, "uncertainty_summary.parquet")
  )
  write_atomic_parquet(
    result$checks,
    file.path(result_dir, "sanity_checks.parquet")
  )
  environment_notices <- tibble(
    season = season,
    experiment_scope = EXPERIMENT_SCOPE,
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
  write_atomic_parquet(
    environment_notices,
    file.path(result_dir, "environment_notices.parquet")
  )
}

save_car_benchmark_completion_checkpoint <- function(result) {
  if (!all(result$checks$passed)) {
    stop("Refusing to publish benchmark completion before all checks pass",
         call. = FALSE)
  }
  model_checkpoint_path <- checkpoint_path(CAR_BENCHMARK_GRID, "CAR")
  fit_path <- file.path(
    cache_dir, paste0("car_grid_", CAR_BENCHMARK_GRID, "_fit.rds")
  )
  if (!file.exists(model_checkpoint_path) || !file.exists(fit_path)) {
    stop("Verified CAR fit artifacts are missing", call. = FALSE)
  }
  completion <- list(
    complete = TRUE,
    season = season,
    experiment_scope = EXPERIMENT_SCOPE,
    specification_id = MODEL_SPECIFICATION_ID,
    split_sha256 = EXPECTED_SPLIT_SHA256,
    player_count = ACTIVE_PLAYER_COUNT,
    grid_width = CAR_BENCHMARK_GRID,
    model_checkpoint_sha256 = sha256_file(model_checkpoint_path),
    serialized_model_md5 = unname(tools::md5sum(fit_path)),
    metrics = result$metrics,
    uncertainty = result$uncertainty,
    checks = result$checks
  )
  save_atomic_checkpoint(
    file.path(cache_dir, "benchmark_complete_checkpoint.rds"),
    completion
  )
}

load_verified_benchmark_completion <- function() {
  path <- file.path(cache_dir, "benchmark_complete_checkpoint.rds")
  if (!file.exists(path)) return(NULL)
  completion <- tryCatch(
    readRDS(path),
    error = function(condition) {
      stop("Existing benchmark completion checkpoint is unreadable and was preserved: ",
           conditionMessage(condition), call. = FALSE)
    }
  )
  model_checkpoint_path <- checkpoint_path(CAR_BENCHMARK_GRID, "CAR")
  fit_path <- file.path(
    cache_dir, paste0("car_grid_", CAR_BENCHMARK_GRID, "_fit.rds")
  )
  result_paths <- file.path(
    result_dir,
    c(
      "benchmark_metrics.parquet", "uncertainty_summary.parquet",
      "sanity_checks.parquet", "environment_notices.parquet"
    )
  )
  valid <- is.list(completion) &&
    isTRUE(completion$complete) &&
    identical(completion$season, season) &&
    identical(completion$experiment_scope, EXPERIMENT_SCOPE) &&
    identical(completion$specification_id, MODEL_SPECIFICATION_ID) &&
    identical(completion$split_sha256, EXPECTED_SPLIT_SHA256) &&
    identical(completion$player_count, ACTIVE_PLAYER_COUNT) &&
    identical(completion$grid_width, CAR_BENCHMARK_GRID) &&
    nrow(completion$metrics) == 1L &&
    isTRUE(completion$metrics$completed[[1]]) &&
    nrow(completion$checks) > 0L &&
    all(completion$checks$passed) &&
    file.exists(model_checkpoint_path) &&
    file.exists(fit_path) &&
    identical(
      completion$model_checkpoint_sha256,
      sha256_file(model_checkpoint_path)
    ) &&
    identical(
      completion$serialized_model_md5,
      unname(tools::md5sum(fit_path))
    ) &&
    all(file.exists(result_paths))
  if (!valid) {
    stop("Existing benchmark completion checkpoint is inconsistent; artifacts were preserved",
         call. = FALSE)
  }
  completion
}

write_car_timeout_result <- function(audit, elapsed, cpu_seconds, peak_rss_mb,
                                     failure = "wall-time ceiling reached") {
  dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
  grid <- make_grid(CAR_BENCHMARK_GRID)
  training_metadata <- audit$metadata$in_play_metadata |>
    filter(
      fold %in% FITTING_FOLDS,
      PLAYER_ID %in% audit$metadata$eligible$PLAYER_ID
    )
  observed_player_cells <- training_metadata |>
    assign_grid_cells(CAR_BENCHMARK_GRID, grid) |>
    distinct(PLAYER_ID, cell_id) |>
    nrow()
  result <- tibble(
    season = season,
    experiment_scope = EXPERIMENT_SCOPE,
    specification_id = MODEL_SPECIFICATION_ID,
    grid_width = CAR_BENCHMARK_GRID,
    model = "CAR",
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    fold4_outcomes_read = FALSE,
    fold5_outcomes_read = FALSE,
    completed = FALSE,
    timed_out = identical(failure, "wall-time ceiling reached"),
    failed = !identical(failure, "wall-time ceiling reached"),
    failure = failure,
    runtime_ceiling_sec = CAR_BENCHMARK_CEILING_SEC,
    watchdog_wall_elapsed_sec = as.numeric(elapsed),
    approximate_process_tree_cpu_sec = as.numeric(cpu_seconds),
    approximate_peak_process_tree_rss_mb = as.numeric(peak_rss_mb),
    player_count = nrow(audit$metadata$eligible),
    training_shot_count = nrow(training_metadata),
    observed_player_cell_count = observed_player_cells,
    cells_per_player = nrow(grid),
    lattice_row_count = nrow(grid) * nrow(audit$metadata$eligible),
    approximate_unknown_count = lattice_row_count + player_count + 2L,
    checkpoint_exists = file.exists(checkpoint_path(CAR_BENCHMARK_GRID, "CAR")),
    fit_artifact_exists = file.exists(
      file.path(cache_dir, paste0("car_grid_", CAR_BENCHMARK_GRID, "_fit.rds"))
    ),
    warning_count = NA_integer_,
    warnings = failure,
    r_version = as.character(getRversion()),
    inla_version = as.character(packageVersion("INLA")),
    split_sha256 = EXPECTED_SPLIT_SHA256
  )
  write_atomic_parquet(
    result,
    file.path(result_dir, "benchmark_metrics.parquet")
  )
  result
}

run_capped_car_benchmark <- function(audit, check_log) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  completed <- load_verified_benchmark_completion()
  if (!is.null(completed)) {
    message("Reusing verified completed full-league CAR benchmark")
    print(completed$metrics, width = Inf)
    return(invisible(completed))
  }
  lock <- acquire_benchmark_lock()
  on.exit(release_benchmark_lock(lock), add = TRUE)
  wall_started <- proc.time()[["elapsed"]]
  job <- parallel::mcparallel(
    car_benchmark_worker(audit, check_log),
    detached = FALSE,
    silent = FALSE
  )
  lock <- update_benchmark_lock(lock, job$pid)
  peak_rss_mb <- 0
  cpu_by_pid <- numeric()
  next_report_seconds <- 60

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
    collected <- parallel::mccollect(job, wait = FALSE)
    if (!is.null(collected)) {
      value <- collected[[1]]
      total_cpu <- sum(cpu_by_pid, na.rm = TRUE)
      if (inherits(value, "try-error")) {
        failure <- paste("benchmark child failed:", as.character(value))
        result <- write_car_timeout_result(
          audit, elapsed, total_cpu, peak_rss_mb, failure
        )
        print(result, width = Inf)
        stop(failure, call. = FALSE)
      }
      value$metrics <- value$metrics |>
        mutate(
          watchdog_wall_elapsed_sec = elapsed,
          approximate_process_tree_cpu_sec = total_cpu,
          approximate_peak_process_tree_rss_mb = peak_rss_mb,
          memory_measurement = paste(
            "maximum one-second sampled resident memory across the R worker",
            "and its visible descendants"
          ),
          cpu_measurement = paste(
            "sum of maximum sampled CPU time for each visible process-tree PID"
          )
        )
      save_car_benchmark_completion_checkpoint(value)
      write_car_benchmark_results(value)
      print(value$metrics, width = Inf)
      print(value$uncertainty, width = Inf)
      return(invisible(value))
    }
    if (elapsed >= CAR_BENCHMARK_CEILING_SEC) {
      remaining <- terminate_process_tree(job$pid)
      parallel::mccollect(job, wait = FALSE)
      result <- write_car_timeout_result(
        audit,
        elapsed,
        sum(cpu_by_pid, na.rm = TRUE),
        peak_rss_mb
      ) |>
        mutate(remaining_processes_after_termination = length(remaining))
      print(result, width = Inf)
      return(invisible(result))
    }
    if (elapsed >= next_report_seconds) {
      message(
        "WATCHDOG elapsed_sec=", round(elapsed, 1),
        " approximate_cpu_sec=", round(sum(cpu_by_pid, na.rm = TRUE), 1),
        " peak_rss_mb=", round(peak_rss_mb, 1)
      )
      next_report_seconds <- next_report_seconds + 60
    }
    Sys.sleep(1)
  }
}

attach_sparse_outcomes <- function(intervals, validation) {
  actual <- validation |>
    filter(PLAYER_ID %in% intervals$PLAYER_ID) |>
    summarise(
      validation_attempts = n(),
      actual_makes = sum(SHOT_MADE_FLAG),
      .by = PLAYER_ID
    )
  intervals |>
    left_join(actual, by = "PLAYER_ID") |>
    mutate(
      covered_90 = actual_makes >= interval_lower & actual_makes <= interval_upper
    )
}

bootstrap_grid_selection <- function(scored_predictions) {
  pairing <- scored_predictions |>
    summarise(
      model_count = n_distinct(model),
      row_count = n(),
      .by = c(grid_width, shot_id, GAME_ID)
    )
  if (any(pairing$model_count != 2L | pairing$row_count != 2L)) {
    stop("Each grid and validation shot must have exactly one GAM and one CAR score",
         call. = FALSE)
  }
  combined <- scored_predictions |>
    summarise(
      combined_log_loss = mean(log_loss),
      .by = c(grid_width, shot_id, GAME_ID)
    )
  grid_scores <- combined |>
    summarise(
      validation_log_loss = mean(combined_log_loss),
      .by = grid_width
    ) |>
    arrange(validation_log_loss, desc(grid_width))
  point_leader <- grid_scores$grid_width[[1]]

  game_grid <- combined |>
    summarise(
      loss_sum = sum(combined_log_loss),
      attempts = n(),
      .by = c(GAME_ID, grid_width)
    )
  games <- sort(unique(game_grid$GAME_ID))
  set_frozen_rng(VALIDATION_BOOTSTRAP_SEED)
  bootstrap_samples <- replicate(
    BOOTSTRAP_DRAWS,
    sample(games, length(games), replace = TRUE),
    simplify = FALSE
  )
  bootstrap_scores <- lapply(seq_along(bootstrap_samples), function(draw) {
    weights <- tibble(GAME_ID = bootstrap_samples[[draw]]) |>
      count(GAME_ID, name = "bootstrap_weight")
    game_grid |>
      inner_join(weights, by = "GAME_ID") |>
      summarise(
        validation_log_loss = sum(loss_sum * bootstrap_weight) /
          sum(attempts * bootstrap_weight),
        .by = grid_width
      ) |>
      mutate(bootstrap_draw = draw)
  }) |>
    bind_rows()
  leader_scores <- bootstrap_scores |>
    filter(grid_width == point_leader) |>
    select(bootstrap_draw, leader_log_loss = validation_log_loss)
  comparisons <- bootstrap_scores |>
    left_join(leader_scores, by = "bootstrap_draw") |>
    mutate(difference_from_point_leader = validation_log_loss - leader_log_loss) |>
    summarise(
      point_leader_grid_width = point_leader,
      mean_bootstrap_difference = mean(difference_from_point_leader),
      lower_95 = as.numeric(quantile(
        difference_from_point_leader, 0.025, names = FALSE
      )),
      upper_95 = as.numeric(quantile(
        difference_from_point_leader, 0.975, names = FALSE
      )),
      .by = grid_width
    ) |>
    mutate(
      tied_with_point_leader = lower_95 <= 0 & upper_95 >= 0
    ) |>
    arrange(grid_width)
  tied_grids <- comparisons$grid_width[comparisons$tied_with_point_leader]
  selected <- max(tied_grids)
  selected_score <- grid_scores$validation_log_loss[
    match(selected, grid_scores$grid_width)
  ]
  selected_record <- tibble(
    season = season,
    experiment_scope = EXPERIMENT_SCOPE,
    player_count = EXPECTED_FALLBACK_PLAYERS,
    fallback_sample_sha256 = EXPECTED_SAMPLE_SHA256,
    selected_grid_width = as.integer(selected),
    selected_grid_approx_feet = as.integer(selected / 10),
    selected_average_validation_log_loss = selected_score,
    point_leader_grid_width = as.integer(point_leader),
    selection_rule = if (selected == point_leader) {
      "lowest two-model average validation log loss; no coarser tied grid"
    } else {
      "coarsest grid whose paired whole-game bootstrap interval includes zero versus point leader"
    },
    bootstrap_seed = VALIDATION_BOOTSTRAP_SEED,
    bootstrap_draws = BOOTSTRAP_DRAWS,
    split_sha256 = EXPECTED_SPLIT_SHA256,
    fold5_outcomes_read = FALSE
  )
  list(scores = grid_scores, comparisons = comparisons, selected = selected_record)
}

write_result_tables <- function(results, check_log) {
  dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
  tables <- list(
    experiment_manifest = tibble(
      season = season,
      experiment_scope = EXPERIMENT_SCOPE,
      specification_id = MODEL_SPECIFICATION_ID,
      player_count = EXPECTED_FALLBACK_PLAYERS,
      fallback_sample_sha256 = EXPECTED_SAMPLE_SHA256,
      split_sha256 = EXPECTED_SPLIT_SHA256,
      fitting_folds = paste(FITTING_FOLDS, collapse = ","),
      validation_fold = VALIDATION_FOLD,
      fold5_outcomes_read = FALSE
    ),
    model_grid_metrics = results$model_metrics,
    calibration_bins = results$calibration,
    player_calibration = results$player_calibration,
    sparse_player_intervals = results$sparse_intervals,
    sparse_uncertainty_summary = results$sparse_summary,
    grid_scores = results$selection$scores,
    grid_bootstrap_comparisons = results$selection$comparisons,
    selected_grid = results$selection$selected,
    sanity_checks = bind_rows(check_log$records)
  )
  tables <- lapply(tables, function(table) {
    if (!"experiment_scope" %in% names(table)) {
      table <- mutate(table, experiment_scope = EXPERIMENT_SCOPE, .before = 1)
    }
    table
  })
  for (name in names(tables)) {
    write_parquet(
      arrange(tables[[name]], across(any_of(c("grid_width", "model", "PLAYER_ID")))),
      file.path(result_dir, paste0(name, ".parquet"))
    )
  }
  invisible(tables)
}

run_audit <- function(check_log) {
  if (!file.exists(raw_path)) {
    stop("Missing raw shot data: ", raw_path, call. = FALSE)
  }
  verify_versions(check_log)
  verify_frozen_constants(check_log)
  folds <- read_fold_artifact(check_log)
  metadata <- read_metadata_without_outcomes()
  prepared <- prepare_metadata(metadata, folds, check_log)
  seal_message <- tryCatch(
    {
      read_allowed_outcomes(folds, SEALED_TEST_FOLD, prepared$eligible$PLAYER_ID)
      "guard did not stop"
    },
    error = function(condition) conditionMessage(condition)
  )
  check_or_stop(
    check_log, "seal", check = "fold5_outcome_loader_guard_present",
    condition = grepl("SEALED TEST SAFEGUARD", seal_message, fixed = TRUE),
    detail = seal_message
  )
  list(folds = folds, metadata = prepared)
}

check_log <- new_check_log()
audit <- run_audit(check_log)

if (mode %in% c("audit", "car-benchmark-audit")) {
  audit_summary <- tibble(
    season = season,
    experiment_scope = EXPERIMENT_SCOPE,
    all_eligible_players = EXPECTED_ALL_ELIGIBLE_PLAYERS,
    eligible_players = nrow(audit$metadata$eligible),
    fitting_folds = paste(FITTING_FOLDS, collapse = ","),
    validation_fold = VALIDATION_FOLD,
    sealed_test_fold = SEALED_TEST_FOLD,
    split_sha256 = EXPECTED_SPLIT_SHA256,
    fallback_sample_sha256 = ACTIVE_SAMPLE_SHA256,
    frozen_settings_passed = all(bind_rows(check_log$records)$passed),
    fold5_outcomes_read = FALSE
  )
  print(audit_summary, width = Inf)
  quit(save = "no", status = 0L)
}

if (mode == "car-benchmark") {
  run_capped_car_benchmark(audit, check_log)
  quit(save = "no", status = 0L)
}

dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
training_shots <- read_allowed_outcomes(
  audit$folds,
  FITTING_FOLDS,
  audit$metadata$eligible$PLAYER_ID
)
validation_metadata <- audit$metadata$in_play_metadata |>
  filter(
    fold == VALIDATION_FOLD,
    PLAYER_ID %in% audit$metadata$eligible$PLAYER_ID
  ) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
check_or_stop(
  check_log, "seal", check = "fitting_uses_only_folds_1_to_3",
  condition = identical(sort(unique(training_shots$fold)), FITTING_FOLDS),
  detail = paste("folds", paste(sort(unique(training_shots$fold)), collapse = ","))
)
check_or_stop(
  check_log, "seal", check = "validation_metadata_uses_only_fold_4",
  condition = identical(sort(unique(validation_metadata$fold)), VALIDATION_FOLD),
  detail = paste("fold", paste(sort(unique(validation_metadata$fold)), collapse = ","),
                 "with no make/miss column")
)
check_or_stop(
  check_log, "seal", check = "only_fitting_outcomes_in_memory_before_sanity",
  condition = !any(training_shots$fold %in% c(VALIDATION_FOLD, SEALED_TEST_FOLD)),
  detail = paste(nrow(training_shots), "outcome rows from folds 1-3 only")
)

model_metrics <- list()
sparse_intervals <- list()
model_probabilities <- list()
grid_definitions <- list()

for (grid_width in RUN_ORDER) {
  model_data <- build_model_data(
    training_shots,
    validation_metadata,
    audit$metadata$eligible,
    grid_width,
    check_log
  )

  expected_rows <- nrow(model_data$lattice)
  expected_sparse_rows <- nrow(audit$metadata$sparse_players)
  gam <- run_or_reuse_model(
    grid_width,
    "GAM",
    expected_rows,
    expected_sparse_rows,
    check_log,
    function() fit_gam(
      model_data,
      audit$metadata$sparse_players,
      grid_width,
      check_log
    )
  )
  car <- run_or_reuse_model(
    grid_width,
    "CAR",
    expected_rows,
    expected_sparse_rows,
    check_log,
    function() fit_car(
      model_data,
      audit$metadata$sparse_players,
      grid_width,
      check_log
    )
  )
  model_metrics <- c(model_metrics, list(gam$metrics, car$metrics))
  sparse_intervals <- c(sparse_intervals, list(gam$sparse, car$sparse))
  model_probabilities[[paste(grid_width, "GAM", sep = "_")]] <- gam$probabilities
  model_probabilities[[paste(grid_width, "CAR", sep = "_")]] <- car$probabilities
  grid_definitions[[as.character(grid_width)]] <- model_data$grid
  rm(gam, car, model_data)
  gc()
}

# Fold-4 outcomes are opened only after every frozen fit and pre-registered
# sanity check above has passed. Fold 5 remains rejected by the same loader.
validation_outcomes <- read_allowed_outcomes(
  audit$folds,
  VALIDATION_FOLD,
  audit$metadata$eligible$PLAYER_ID
) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y, SHOT_MADE_FLAG) |>
  mutate(shot_id = row_number())
metadata_keys <- validation_metadata |>
  select(all_of(METADATA_COLUMNS), fold) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
outcome_keys <- validation_outcomes |>
  select(all_of(METADATA_COLUMNS), fold) |>
  arrange(GAME_ID, PLAYER_ID, LOC_X, LOC_Y)
check_or_stop(
  check_log, "seal", check = "validation_outcomes_loaded_after_all_model_checks",
  condition = same_table(metadata_keys, outcome_keys),
  detail = paste(nrow(validation_outcomes), "fold-4 outcomes match audited metadata")
)
check_or_stop(
  check_log, "seal", check = "no_fold5_outcomes_in_memory",
  condition = !any(validation_outcomes$fold == SEALED_TEST_FOLD),
  detail = "fold 5 remains sealed"
)

calibration <- list()
player_calibration <- list()
scored_predictions <- list()
evaluated_sparse <- list()
for (grid_width in GRID_WIDTHS) {
  validation_grid <- assign_grid_cells(
    validation_outcomes,
    grid_width,
    grid_definitions[[as.character(grid_width)]]
  )
  for (model in c("GAM", "CAR")) {
    key <- paste(grid_width, model, sep = "_")
    evaluation <- evaluate_predictions(
      validation_grid,
      model_probabilities[[key]],
      grid_width,
      model
    )
    interval_position <- which(vapply(
      sparse_intervals,
      function(table) table$grid_width[[1]] == grid_width && table$model[[1]] == model,
      logical(1)
    ))
    if (length(interval_position) != 1L) {
      stop("Could not identify one sparse interval table for ", key, call. = FALSE)
    }
    evaluated_sparse <- c(
      evaluated_sparse,
      list(attach_sparse_outcomes(sparse_intervals[[interval_position]], validation_grid))
    )
    metric_position <- which(vapply(
      model_metrics,
      function(table) table$grid_width[[1]] == grid_width &&
        table$model[[1]] == model,
      logical(1)
    ))
    if (length(metric_position) != 1L) {
      stop("Could not identify one model-metrics table for ", key, call. = FALSE)
    }
    model_metrics[[metric_position]]$validation_log_loss <-
      mean(evaluation$scored$log_loss)
    calibration <- c(calibration, list(evaluation$calibration))
    player_calibration <- c(player_calibration, list(evaluation$player))
    scored_predictions <- c(scored_predictions, list(evaluation$scored))
  }
}

model_metrics <- bind_rows(model_metrics) |>
  mutate(experiment_scope = EXPERIMENT_SCOPE, .before = 1) |>
  arrange(grid_width, model)
calibration <- bind_rows(calibration) |>
  mutate(experiment_scope = EXPERIMENT_SCOPE, .before = 1) |>
  arrange(grid_width, model, calibration_bin)
player_calibration <- bind_rows(player_calibration) |>
  mutate(experiment_scope = EXPERIMENT_SCOPE, .before = 1) |>
  arrange(grid_width, model, PLAYER_ID)
sparse_intervals <- bind_rows(evaluated_sparse) |>
  mutate(experiment_scope = EXPERIMENT_SCOPE, .before = 1) |>
  arrange(grid_width, model, PLAYER_ID)
sparse_summary <- sparse_intervals |>
  summarise(
    sparse_players = n(),
    coverage_90 = mean(covered_90),
    average_interval_width = mean(interval_width),
    .by = c(grid_width, model)
  ) |>
  mutate(experiment_scope = EXPERIMENT_SCOPE, .before = 1) |>
  arrange(grid_width, model)
scored_predictions <- bind_rows(scored_predictions)

selection <- bootstrap_grid_selection(scored_predictions)
results <- list(
  model_metrics = model_metrics,
  calibration = calibration,
  player_calibration = player_calibration,
  sparse_intervals = sparse_intervals,
  sparse_summary = sparse_summary,
  selection = selection
)
write_result_tables(results, check_log)

print(model_metrics, width = Inf)
print(sparse_summary, width = Inf)
print(selection$scores, width = Inf)
print(selection$comparisons, width = Inf)
print(selection$selected, width = Inf)
