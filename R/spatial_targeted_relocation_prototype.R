# Isolated LeBron James prototype for targeted weak-location relocation.
#
# This script reuses the verified production CAR fit and its frozen posterior
# sampling contract. It does not fit a model, modify production results, or
# calculate any other player.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

SEASON <- "2025-26"
PLAYER_ID <- 2544L
PLAYER_NAME <- "LeBron James"
METHOD_ID <- "car-targeted-weak-location-prototype-v1"
SLIDERS <- c(0, 0.05, 0.10, 0.15, 0.20, 0.25)
MIN_ATTEMPTS <- 10L
MIN_CERTAINTY <- 0.90
MIN_DESTINATIONS <- 2L
POSTERIOR_DRAWS <- 4000L
POSTERIOR_SEED <- 20260902L
GRID_WIDTH <- 40L
COURT_X_MIN <- -250
COURT_X_MAX <- 250
COURT_Y_MIN <- -52.5
COURT_Y_MAX <- 397.5
TOLERANCE <- 1e-12
PLANNING_COMMIT <- "8d92b16"

EXPECTED_HASHES <- c(
  input = "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6",
  fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  raw = "20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498"
)

production_cache <- file.path(
  "data", "cache", "spatial_car_production", paste0("season=", SEASON)
)
input_path <- file.path(production_cache, "production_input.rds")
fit_path <- file.path(production_cache, "car_production_fit.rds")
surface_path <- file.path(production_cache, "player_probability_surfaces.parquet")
raw_path <- file.path(
  "data", "raw", "shots", paste0("season=", SEASON), "shots.parquet"
)
output_dir <- file.path(
  "data", "cache", "spatial_targeted_relocation_prototype",
  paste0("season=", SEASON), paste0("player=", PLAYER_ID)
)
output_path <- file.path(output_dir, "prototype.json")

check <- function(condition, message) {
  if (!isTRUE(condition)) stop("PROTOTYPE CHECK FAILED: ", message, call. = FALSE)
}

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  check(length(output) == 1L, paste("could not hash", path))
  strsplit(output, "[[:space:]]+")[[1]][[1]]
}

quantile_value <- function(x, probability) {
  as.numeric(stats::quantile(x, probability, names = FALSE, type = 7))
}

summary_values <- function(x) {
  list(
    mean = mean(x),
    lower_90 = quantile_value(x, 0.05),
    upper_90 = quantile_value(x, 0.95)
  )
}

assign_cells <- function(shots) {
  nx <- as.integer(ceiling((COURT_X_MAX - COURT_X_MIN) / GRID_WIDTH))
  ny <- as.integer(ceiling((COURT_Y_MAX - COURT_Y_MIN) / GRID_WIDTH))
  shots |>
    mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - COURT_X_MIN) / GRID_WIDTH)) + 1L, nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - COURT_Y_MIN) / GRID_WIDTH)) + 1L, ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    )
}

extract_predictors <- function(samples, expected_indices) {
  labels <- rownames(samples[[1]]$latent)
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  check(
    !is.null(labels) && !anyNA(parsed) && setequal(parsed, expected_indices),
    "posterior predictor selection does not match LeBron's lattice"
  )
  values <- vapply(
    samples, function(sample) as.numeric(sample$latent),
    numeric(length(expected_indices))
  )
  values[match(expected_indices, parsed), , drop = FALSE]
}

remove_from_sources <- function(baseline_share, source_order, requested_share) {
  removed <- numeric(length(baseline_share))
  remaining <- min(requested_share, sum(baseline_share[source_order]))
  actual <- remaining
  for (index in source_order) {
    if (remaining <= TOLERANCE) break
    amount <- min(baseline_share[[index]], remaining)
    removed[[index]] <- amount
    remaining <- remaining - amount
  }
  check(abs(sum(removed) - actual) <= TOLERANCE, "source removal mass")
  list(removed = removed, actual = actual)
}

git_head <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
git_origin <- system2(
  "git", c("rev-parse", "origin/codex/spatial-shot-selection"), stdout = TRUE
)
check(length(git_head) == 1L && identical(git_head, git_origin),
      "analytics branch must match its pushed upstream")
check(system2("git", c("merge-base", "--is-ancestor", PLANNING_COMMIT, "HEAD")) == 0L,
      "approved amendment commit is not in history")

paths <- c(input = input_path, fit = fit_path, surface = surface_path, raw = raw_path)
check(all(file.exists(paths)), "a verified production input is missing")
observed_hashes <- vapply(paths, sha256_file, character(1))
check(identical(observed_hashes, EXPECTED_HASHES), "production hashes changed")
check(!file.exists(output_path), "prototype output already exists; refusing replacement")

production_input <- readRDS(input_path)
lattice <- production_input$lattice |>
  filter(PLAYER_ID == .env$PLAYER_ID) |>
  arrange(cell_id)
check(nrow(lattice) == 156L, "LeBron must have 156 production cells")
check(identical(lattice$PLAYER_NAME, rep(PLAYER_NAME, 156L)), "player identity")

shots <- open_dataset(raw_path) |>
  filter(PLAYER_ID == .env$PLAYER_ID, LOC_Y <= COURT_Y_MAX) |>
  select(PLAYER_ID, PLAYER_NAME, LOC_X, LOC_Y, SHOT_TYPE,
         SHOT_ATTEMPTED_FLAG, SHOT_MADE_FLAG) |>
  collect() |>
  as_tibble() |>
  mutate(stable_source_row = row_number()) |>
  assign_cells()

check(nrow(shots) == sum(lattice$attempts), "shot count does not match production")
check(nrow(shots) == 919L, "LeBron eligible production shot count changed")
check(all(shots$SHOT_ATTEMPTED_FLAG == 1L), "non-attempt row present")
check(all(shots$SHOT_MADE_FLAG %in% c(0L, 1L)), "invalid made or missed value")
check(
  setequal(unique(shots$SHOT_TYPE), c("2PT Field Goal", "3PT Field Goal")),
  "invalid shot type"
)

cell_values <- shots |>
  summarise(
    point_value_attempts = n(),
    makes_from_shots = sum(SHOT_MADE_FLAG),
    three_point_attempts = sum(SHOT_TYPE == "3PT Field Goal"),
    .by = cell_id
  ) |>
  mutate(
    three_point_share = three_point_attempts / point_value_attempts,
    point_value = 2 + three_point_share
  )

lattice <- lattice |>
  left_join(cell_values, by = "cell_id") |>
  mutate(
    baseline_share = attempts / sum(attempts),
    point_value_for_calculation = coalesce(point_value, 0)
  )
observed <- lattice$attempts > 0L
check(
  all(lattice$attempts[observed] == lattice$point_value_attempts[observed]) &&
    all(lattice$makes[observed] == lattice$makes_from_shots[observed]),
  "shot rows do not reproduce production cell counts"
)
check(abs(sum(lattice$baseline_share) - 1) <= TOLERANCE, "baseline mass")

fit <- readRDS(fit_path)
check(isTRUE(fit$ok) && identical(as.numeric(fit$mode$mode.status), 0),
      "saved production fit is invalid")
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
set.seed(POSTERIOR_SEED)
samples <- INLA::inla.posterior.sample(
  n = POSTERIOR_DRAWS,
  result = fit,
  selection = list(Predictor = lattice$predictor_index),
  seed = POSTERIOR_SEED,
  num.threads = 1L,
  parallel.configs = FALSE,
  add.names = FALSE
)
probability_draws <- plogis(extract_predictors(samples, lattice$predictor_index))
rm(samples, fit)
gc()
check(
  identical(dim(probability_draws), c(156L, POSTERIOR_DRAWS)) &&
    all(is.finite(probability_draws)) &&
    all(probability_draws >= 0 & probability_draws <= 1),
  "posterior draw dimensions or bounds"
)

saved_surface <- read_parquet(surface_path) |>
  filter(PLAYER_ID == .env$PLAYER_ID) |>
  arrange(cell_id)
draw_mean_difference <- max(abs(
  rowMeans(probability_draws) - saved_surface$draw_mean_probability
))
check(draw_mean_difference <= TOLERANCE, "draws do not reproduce production means")

baseline_draws <- colSums(
  probability_draws * lattice$baseline_share * lattice$point_value_for_calculation
)
baseline_mean <- mean(baseline_draws)
cell_mean_expected_points <- rowMeans(probability_draws) * lattice$point_value
support_probability <- rep(NA_real_, nrow(lattice))
support_probability[observed] <- rowMeans(
  sweep(
    probability_draws[observed, , drop = FALSE] * lattice$point_value[observed],
    2L, baseline_draws, `>`
  )
)
supported <- lattice$attempts >= MIN_ATTEMPTS &
  coalesce(support_probability >= MIN_CERTAINTY, FALSE)
check(sum(supported) >= MIN_DESTINATIONS, "LeBron lacks two supported destinations")
destination_weights <- numeric(nrow(lattice))
destination_weights[supported] <-
  lattice$baseline_share[supported] / sum(lattice$baseline_share[supported])
check(abs(sum(destination_weights) - 1) <= TOLERANCE, "destination weights")

source <- observed & cell_mean_expected_points < baseline_mean
source_order <- which(source)[order(cell_mean_expected_points[source], lattice$cell_id[source])]
source_mass <- sum(lattice$baseline_share[source_order])
check(length(source_order) > 0L && source_mass > 0, "no eligible source mass")

slider_rows <- lapply(SLIDERS, function(requested_share) {
  removal <- remove_from_sources(
    lattice$baseline_share, source_order, requested_share
  )
  relocated_share <- lattice$baseline_share - removal$removed +
    removal$actual * destination_weights
  check(min(relocated_share) >= -TOLERANCE, "negative relocated share")
  check(abs(sum(relocated_share) - 1) <= TOLERANCE, "relocated mass")
  relocated_draws <- if (requested_share == 0) baseline_draws else colSums(
    probability_draws * relocated_share * lattice$point_value_for_calculation
  )
  gain_per_100 <- 100 * (relocated_draws - baseline_draws)
  season_gain <- nrow(shots) * (relocated_draws - baseline_draws)
  list(
    requested_share = requested_share,
    actual_relocated_share = removal$actual,
    actual_relocated_attempt_equivalents = removal$actual * nrow(shots),
    relocated_expected_points_per_attempt = summary_values(relocated_draws),
    season_gain = summary_values(season_gain),
    gain_per_100 = summary_values(gain_per_100)
  )
})

check(
  all(vapply(slider_rows, function(x) {
    x$actual_relocated_share <= x$requested_share + TOLERANCE
  }, logical(1))),
  "actual share exceeds requested share"
)
check(
  all(vapply(slider_rows[[1]][c("season_gain", "gain_per_100")], function(x) {
    identical(unname(unlist(x)), c(0, 0, 0))
  }, logical(1))),
  "zero slider must produce exact zero gain"
)

relocated_25 <- slider_rows[[length(slider_rows)]]$relocated_expected_points_per_attempt
removal_25 <- remove_from_sources(lattice$baseline_share, source_order, 0.25)
relocated_distribution_25 <- lattice$baseline_share - removal_25$removed +
  removal_25$actual * destination_weights
relocated_draws_25 <- colSums(
  probability_draws * relocated_distribution_25 * lattice$point_value_for_calculation
)
raw_score_draws <- 100 * baseline_draws / relocated_draws_25
display_score_draws <- pmin(100, pmax(0, raw_score_draws))
prototype_score <- list(
  point = stats::median(display_score_draws),
  lower_90 = quantile_value(display_score_draws, 0.05),
  upper_90 = quantile_value(display_score_draws, 0.95),
  formula = "100 * baseline expected points per attempt / targeted 25% expected points per attempt"
)

source_rank <- rep(NA_integer_, nrow(lattice))
source_rank[source_order] <- seq_along(source_order)
ordered_shots <- shots |>
  mutate(cell_source_rank = source_rank[match(cell_id, lattice$cell_id)]) |>
  filter(!is.na(cell_source_rank)) |>
  arrange(cell_source_rank, stable_source_row)
ordered_shots$move_order <- seq_len(nrow(ordered_shots))

destination_indices <- which(supported)
assigned_counts <- integer(length(destination_indices))
destination_for_move <- integer(nrow(ordered_shots))
for (move_index in seq_len(nrow(ordered_shots))) {
  deficits <- move_index * destination_weights[destination_indices] - assigned_counts
  choice <- which.max(deficits)
  destination_for_move[[move_index]] <- destination_indices[[choice]]
  assigned_counts[[choice]] <- assigned_counts[[choice]] + 1L
}

destination_positions <- lapply(destination_indices, function(index) {
  shots |>
    filter(cell_id == lattice$cell_id[[index]]) |>
    arrange(LOC_X, LOC_Y, stable_source_row) |>
    select(LOC_X, LOC_Y)
})
names(destination_positions) <- as.character(destination_indices)
destination_use <- integer(length(destination_indices))
after_x <- after_y <- numeric(nrow(ordered_shots))
for (move_index in seq_len(nrow(ordered_shots))) {
  destination_index <- destination_for_move[[move_index]]
  destination_slot <- match(destination_index, destination_indices)
  destination_use[[destination_slot]] <- destination_use[[destination_slot]] + 1L
  positions <- destination_positions[[as.character(destination_index)]]
  position_index <- ((destination_use[[destination_slot]] - 1L) %% nrow(positions)) + 1L
  after_x[[move_index]] <- positions$LOC_X[[position_index]] / 10
  after_y[[move_index]] <- positions$LOC_Y[[position_index]] / 10
}

shots_for_export <- shots |>
  left_join(
    ordered_shots |>
      transmute(
        stable_source_row,
        move_order,
        after_x_ft = after_x,
        after_y_ft = after_y
      ),
    by = "stable_source_row"
  ) |>
  transmute(
    x_ft = LOC_X / 10,
    y_ft = LOC_Y / 10,
    made = SHOT_MADE_FLAG == 1L,
    move_order,
    after_x_ft,
    after_y_ft
  )

selection_without_outcomes <- shots |>
  transmute(stable_source_row, cell_id) |>
  mutate(cell_source_rank = source_rank[match(cell_id, lattice$cell_id)]) |>
  filter(!is.na(cell_source_rank)) |>
  arrange(cell_source_rank, stable_source_row) |>
  pull(stable_source_row)
check(
  identical(selection_without_outcomes, ordered_shots$stable_source_row),
  "outcome-independent shot ordering"
)

max_moved_markers <- ceiling(slider_rows[[length(slider_rows)]]$actual_relocated_attempt_equivalents)
check(max_moved_markers <= nrow(ordered_shots), "insufficient source dots")

payload <- list(
  schema_version = "prototype-1.0.0",
  method_id = METHOD_ID,
  status = "one-player visual prototype",
  season = SEASON,
  player_id = as.character(PLAYER_ID),
  player_name = PLAYER_NAME,
  eligible_production_attempts = nrow(shots),
  makes = sum(shots$SHOT_MADE_FLAG),
  misses = sum(shots$SHOT_MADE_FLAG == 0L),
  source_cell_count = sum(source),
  eligible_source_share = source_mass,
  supported_destination_count = sum(supported),
  baseline_expected_points_per_attempt = summary_values(baseline_draws),
  score = prototype_score,
  sliders = slider_rows,
  moved_marker_rule = paste(
    "At each slider, ceil(actual attempt-equivalents) markers are gold;",
    "the final marker opacity shows its fractional mass."
  ),
  shots = shots_for_export,
  checks = list(
    production_hashes_match = TRUE,
    draw_mean_maximum_absolute_difference = draw_mean_difference,
    production_shot_count_matches = TRUE,
    outcomes_used_for_selection = FALSE,
    nested_source_order = TRUE,
    car_refit = FALSE,
    gam_refit = FALSE,
    all_player_calculation = FALSE
  )
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile("prototype-", output_dir, fileext = ".json")
write_json(payload, temporary, auto_unbox = TRUE, pretty = TRUE, digits = 15,
           na = "null")
check(file.rename(temporary, output_path), "could not publish prototype JSON")

cat(toJSON(list(
  output = output_path,
  output_sha256 = sha256_file(output_path),
  shots = nrow(shots),
  makes = sum(shots$SHOT_MADE_FLAG),
  misses = sum(shots$SHOT_MADE_FLAG == 0L),
  source_cells = sum(source),
  eligible_source_share = source_mass,
  supported_destinations = sum(supported),
  requested_25 = 0.25,
  actual_25 = slider_rows[[6]]$actual_relocated_share,
  season_gain_25 = slider_rows[[6]]$season_gain,
  gain_per_100_25 = slider_rows[[6]]$gain_per_100,
  score = prototype_score,
  draw_mean_maximum_absolute_difference = draw_mean_difference
), auto_unbox = TRUE, pretty = TRUE, digits = 15), "\n")
