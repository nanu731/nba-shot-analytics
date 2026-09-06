# Deterministic 2025-26 targeted-relocation calculation and website v2 export.
# Reuses the verified production CAR fit and its frozen 4,000-draw contract.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1L) args[[1]] else "2025-26"
mode <- if (length(args) >= 2L) args[[2]] else "audit"
target_assert(season == "2025-26", "only the approved 2025-26 release may run")
target_assert(mode %in% c("audit", "run", "recover", "verify"),
              "mode must be audit, run, recover, or verify")

SCHEMA_VERSION <- "2.0.0"
DATA_VERSION <- "2025-26-targeted-v2"
METHOD_ID <- "car-targeted-weak-location-relocation-v2"
EXPORT_METHOD_ID <- "spatial-targeted-website-export-v2"
SLIDERS <- c(0, 0.05, 0.10, 0.15, 0.20, 0.25)
MIN_ATTEMPTS <- 10L
MIN_CERTAINTY <- 0.90
MIN_DESTINATIONS <- 2L
POSTERIOR_DRAWS <- 4000L
POSTERIOR_SEED <- 20260902L
EXPECTED_PLAYERS <- 318L
CELLS_PER_PLAYER <- 156L
EXPECTED_SHOTS <- 194987L
EXPECTED_LATTICE_ROWS <- EXPECTED_PLAYERS * CELLS_PER_PLAYER
TOLERANCE <- 1e-12

EXPECTED_HASHES <- c(
  input = "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6",
  fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  raw = "20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498"
)

production_cache <- file.path("data", "cache", "spatial_car_production",
                              paste0("season=", season))
paths <- c(
  input = file.path(production_cache, "production_input.rds"),
  fit = file.path(production_cache, "car_production_fit.rds"),
  surface = file.path(production_cache, "player_probability_surfaces.parquet"),
  raw = file.path("data", "raw", "shots", paste0("season=", season), "shots.parquet")
)
bundle_dir <- file.path("export", "spatial-shot-selection", "v2")
cache_dir <- file.path("data", "cache", "spatial_targeted_website_export",
                       paste0("season=", season))
completion_path <- file.path(cache_dir, "complete.rds")
lock_path <- file.path(cache_dir, "run.lock")

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  target_assert(length(value) == 1L, paste("could not hash", path))
  strsplit(value, "[[:space:]]+")[[1]][[1]]
}

git_value <- function(arguments) {
  system2("git", arguments, stdout = TRUE, stderr = TRUE)
}

verify_sources <- function() {
  target_assert(all(file.exists(paths)), "a frozen production source is missing")
  hashes <- vapply(paths, sha256_file, character(1))
  target_assert(identical(hashes, EXPECTED_HASHES), "a frozen production hash changed")
  input <- readRDS(paths[["input"]])
  target_assert(isTRUE(input$complete), "production input is incomplete")
  target_assert(identical(input$season, season), "production season changed")
  target_assert(identical(input$player_count, EXPECTED_PLAYERS), "player count changed")
  target_assert(identical(input$shot_count, EXPECTED_SHOTS), "production shot count changed")
  target_assert(identical(input$lattice_rows, EXPECTED_LATTICE_ROWS), "lattice count changed")
  list(hashes = hashes, input = input)
}

load_minimal_shots <- function(player_ids) {
  raw <- open_dataset(paths[["raw"]])
  required <- c("PLAYER_ID", "LOC_X", "LOC_Y", "SHOT_TYPE", "SHOT_MADE_FLAG")
  target_assert(all(required %in% names(raw)), "raw input lacks a required minimal field")
  shots <- raw |>
    filter(PLAYER_ID %in% player_ids, LOC_Y <= 397.5) |>
    select(all_of(required)) |>
    collect() |>
    as_tibble() |>
    mutate(stable_source_row = row_number(), .by = PLAYER_ID) |>
    target_assign_cells() |>
    arrange(PLAYER_ID, stable_source_row)
  target_assert(nrow(shots) == EXPECTED_SHOTS, "eligible shot count changed")
  target_assert(all(shots$SHOT_MADE_FLAG %in% c(0L, 1L)), "invalid made/missed value")
  target_assert(
    setequal(unique(shots$SHOT_TYPE), c("2PT Field Goal", "3PT Field Goal")),
    "invalid point-value field"
  )
  shots
}

extract_predictors <- function(samples, expected_indices) {
  labels <- rownames(samples[[1]]$latent)
  parsed <- suppressWarnings(as.integer(sub("^Predictor:", "", labels)))
  target_assert(
    !is.null(labels) && !anyNA(parsed) && setequal(parsed, expected_indices),
    "posterior predictor selection differs from the production lattice"
  )
  values <- vapply(samples, function(sample) as.numeric(sample$latent),
                   numeric(length(expected_indices)))
  values[match(expected_indices, parsed), , drop = FALSE]
}

cell_bounds <- function(cell_id) {
  column <- (cell_id - 1L) %% 13L
  row <- (cell_id - 1L) %/% 13L
  data.frame(
    x_min_ft = pmax(-25, -25 + column * 4),
    x_max_ft = pmin(25, -25 + (column + 1L) * 4),
    y_min_ft = pmax(-5.25, -5.25 + row * 4),
    y_max_ft = pmin(39.75, -5.25 + (row + 1L) * 4)
  )
}

write_json_file <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(object, path, auto_unbox = TRUE, pretty = TRUE, digits = 15,
             na = "null")
}

json_scalar <- function(value) {
  if (length(value) == 0L || is.na(value)) NA_real_ else value
}

make_shot_plan <- function(player_shots, player_lattice, source_order,
                           supported, destination_weights) {
  source_rank <- rep(NA_integer_, nrow(player_lattice))
  source_rank[source_order] <- seq_along(source_order)
  ordered <- player_shots |>
    mutate(cell_source_rank = source_rank[match(cell_id, player_lattice$cell_id)]) |>
    filter(!is.na(cell_source_rank)) |>
    arrange(cell_source_rank, stable_source_row)
  ordered$move_order <- seq_len(nrow(ordered))
  if (sum(supported) < MIN_DESTINATIONS || nrow(ordered) == 0L) {
    return(player_shots |>
      transmute(x_ft = LOC_X / 10, y_ft = LOC_Y / 10,
                made = SHOT_MADE_FLAG == 1L,
                move_order = NA_integer_, after_x_ft = NA_real_,
                after_y_ft = NA_real_))
  }

  destination_indices <- which(supported)
  sequence <- target_destination_sequence(
    nrow(ordered), destination_indices, destination_weights
  )
  positions <- lapply(destination_indices, function(index) {
    player_shots |>
      filter(cell_id == player_lattice$cell_id[[index]]) |>
      arrange(LOC_X, LOC_Y, SHOT_TYPE, stable_source_row) |>
      select(LOC_X, LOC_Y)
  })
  names(positions) <- as.character(destination_indices)
  used <- integer(length(destination_indices))
  after_x <- after_y <- numeric(nrow(ordered))
  for (i in seq_len(nrow(ordered))) {
    destination_index <- sequence[[i]]
    slot <- match(destination_index, destination_indices)
    used[[slot]] <- used[[slot]] + 1L
    available <- positions[[as.character(destination_index)]]
    position <- ((used[[slot]] - 1L) %% nrow(available)) + 1L
    after_x[[i]] <- available$LOC_X[[position]] / 10
    after_y[[i]] <- available$LOC_Y[[position]] / 10
  }
  player_shots |>
    left_join(
      ordered |>
        transmute(stable_source_row, move_order,
                  after_x_ft = after_x, after_y_ft = after_y),
      by = "stable_source_row"
    ) |>
    transmute(x_ft = LOC_X / 10, y_ft = LOC_Y / 10,
              made = SHOT_MADE_FLAG == 1L, move_order,
              after_x_ft, after_y_ft)
}

make_heatmap <- function(player_surface, player_lattice, supported) {
  bounds <- cell_bounds(player_surface$cell_id)
  lapply(seq_len(nrow(player_surface)), function(i) {
    list(
      cell_id = as.integer(player_surface$cell_id[[i]]),
      center_x_ft = player_surface$x_ft[[i]],
      center_y_ft = player_surface$y_ft[[i]],
      x_min_ft = bounds$x_min_ft[[i]], x_max_ft = bounds$x_max_ft[[i]],
      y_min_ft = bounds$y_min_ft[[i]], y_max_ft = bounds$y_max_ft[[i]],
      modeled_make_probability = player_surface$probability[[i]],
      make_probability_lower_90 = player_surface$probability_lower_90[[i]],
      make_probability_median = player_surface$probability_median[[i]],
      make_probability_upper_90 = player_surface$probability_upper_90[[i]],
      observed_attempts = as.integer(player_lattice$attempts[[i]]),
      effective_point_value = json_scalar(player_lattice$point_value[[i]]),
      supported_destination = isTRUE(supported[[i]])
    )
  })
}

calculate_players <- function(input, shots, surface, probability_draws) {
  cell_values <- shots |>
    summarise(
      point_value_attempts = n(),
      makes_from_shots = sum(SHOT_MADE_FLAG),
      three_point_attempts = sum(SHOT_TYPE == "3PT Field Goal"),
      .by = c(PLAYER_ID, cell_id)
    ) |>
    mutate(point_value = 2 + three_point_attempts / point_value_attempts)
  lattice <- input$lattice |>
    arrange(PLAYER_ID, cell_id) |>
    left_join(cell_values, by = c("PLAYER_ID", "cell_id")) |>
    mutate(
      baseline_share = attempts / sum(attempts),
      point_value_for_calculation = coalesce(point_value, 0),
      .by = PLAYER_ID
    )
  target_assert(
    all(lattice$attempts[lattice$attempts > 0] ==
          lattice$point_value_attempts[lattice$attempts > 0]) &&
      all(lattice$makes[lattice$attempts > 0] ==
            lattice$makes_from_shots[lattice$attempts > 0]),
    "minimal shot rows do not reproduce production cells"
  )

  surface <- surface |> arrange(PLAYER_ID, cell_id)
  mean_probability <- rowMeans(probability_draws)
  maximum_draw_mean_difference <- max(abs(
    mean_probability - surface$draw_mean_probability
  ))
  target_assert(maximum_draw_mean_difference <= TOLERANCE,
                "joint draws do not reproduce the production surface")

  players <- vector("list", length(input$player_ids))
  qualified_scores <- numeric()
  qualified_gains <- numeric()
  capped_players <- 0L
  total_source_cells <- 0L

  for (player_index in seq_along(input$player_ids)) {
    player_id <- input$player_ids[[player_index]]
    rows <- which(lattice$PLAYER_ID == player_id)
    player_lattice <- lattice[rows, , drop = FALSE]
    player_surface <- surface[rows, , drop = FALSE]
    player_shots <- shots |> filter(PLAYER_ID == player_id) |>
      arrange(stable_source_row)
    draws <- probability_draws[rows, , drop = FALSE]
    baseline_draws <- colSums(
      draws * player_lattice$baseline_share *
        player_lattice$point_value_for_calculation
    )
    baseline_mean <- mean(baseline_draws)
    expected_points <- mean_probability[rows] * player_lattice$point_value
    observed <- player_lattice$attempts > 0L
    support_probability <- rep(NA_real_, CELLS_PER_PLAYER)
    support_probability[observed] <- rowMeans(
      sweep(draws[observed, , drop = FALSE] * player_lattice$point_value[observed],
            2L, baseline_draws, `>`)
    )
    supported <- player_lattice$attempts >= MIN_ATTEMPTS &
      coalesce(support_probability >= MIN_CERTAINTY, FALSE)
    qualified <- sum(supported) >= MIN_DESTINATIONS
    destination_weights <- numeric(CELLS_PER_PLAYER)
    if (qualified) {
      destination_weights[supported] <-
        player_lattice$baseline_share[supported] /
        sum(player_lattice$baseline_share[supported])
    }
    source_order <- target_source_order(
      player_lattice$attempts, expected_points, baseline_mean,
      player_lattice$cell_id
    )
    source_share <- sum(player_lattice$baseline_share[source_order])
    total_source_cells <- total_source_cells + length(source_order)

    slider_objects <- vector("list", length(SLIDERS))
    relocated_25_draws <- NULL
    for (slider_index in seq_along(SLIDERS)) {
      requested <- SLIDERS[[slider_index]]
      if (qualified) {
        removal <- target_remove_mass(
          player_lattice$baseline_share, source_order, requested
        )
        relocated_share <- player_lattice$baseline_share - removal$removed +
          removal$actual * destination_weights
        target_assert(abs(sum(relocated_share) - 1) <= TOLERANCE,
                      "relocated mass changed")
        target_assert(min(relocated_share) >= -TOLERANCE,
                      "relocated share became negative")
        relocated_draws <- if (requested == 0) baseline_draws else
          colSums(draws * relocated_share *
                    player_lattice$point_value_for_calculation)
        gain_per_100 <- 100 * (relocated_draws - baseline_draws)
        season_gain <- nrow(player_shots) * (relocated_draws - baseline_draws)
        slider_objects[[slider_index]] <- list(
          requested_share = requested,
          actual_relocated_share = removal$actual,
          actual_relocated_attempt_equivalents = removal$actual * nrow(player_shots),
          relocated_expected_points_per_attempt = target_summary(relocated_draws),
          season_gain = target_summary(season_gain),
          gain_per_100 = target_summary(gain_per_100)
        )
        if (slider_index == length(SLIDERS)) relocated_25_draws <- relocated_draws
      } else {
        slider_objects[[slider_index]] <- list(
          requested_share = requested,
          actual_relocated_share = 0,
          actual_relocated_attempt_equivalents = 0,
          relocated_expected_points_per_attempt = list(
            mean = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_
          ),
          season_gain = list(
            mean = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_
          ),
          gain_per_100 = list(
            mean = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_
          )
        )
      }
    }
    if (qualified) {
      score <- target_score(baseline_draws, relocated_25_draws)
      qualified_scores <- c(qualified_scores, score$point)
      qualified_gains <- c(qualified_gains,
                           slider_objects[[length(SLIDERS)]]$gain_per_100$mean)
      if (source_share < max(SLIDERS) - TOLERANCE) capped_players <- capped_players + 1L
    } else {
      score <- list(point = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_)
    }

    shot_plan <- make_shot_plan(
      player_shots, player_lattice, source_order, supported,
      destination_weights
    )
    potential <- shot_plan$move_order[!is.na(shot_plan$move_order)]
    if (qualified) {
      target_assert(identical(sort(potential), seq_len(length(potential))),
                    "move order is not a contiguous nested sequence")
      target_assert(length(potential) == sum(player_lattice$attempts[source_order]),
                    "move order does not cover every weak-source attempt")
    } else {
      target_assert(length(potential) == 0L,
                    "insufficient-evidence player received movable shots")
    }

    players[[player_index]] <- list(
      schema_version = SCHEMA_VERSION,
      data_version = DATA_VERSION,
      player_id = as.character(player_id),
      player_name = player_lattice$PLAYER_NAME[[1]],
      season = season,
      method_id = METHOD_ID,
      evidence_status = if (qualified) "qualified" else "insufficient_evidence",
      relocation_available = qualified,
      score_available = qualified,
      observed_attempts = nrow(player_shots),
      makes = sum(player_shots$SHOT_MADE_FLAG),
      misses = sum(player_shots$SHOT_MADE_FLAG == 0L),
      source_cell_count = length(source_order),
      eligible_source_share = source_share,
      supported_destination_count = sum(supported),
      baseline_expected_points_per_attempt = target_summary(baseline_draws),
      score = score,
      sliders = slider_objects,
      heatmap_cells = make_heatmap(player_surface, player_lattice, supported),
      shots = shot_plan
    )
  }
  names(players) <- vapply(players, `[[`, character(1), "player_id")
  list(
    players = players,
    maximum_draw_mean_difference = maximum_draw_mean_difference,
    qualified_scores = qualified_scores,
    qualified_gains = qualified_gains,
    capped_players = capped_players,
    total_source_cells = total_source_cells
  )
}

inventory_for <- function(root, relative_paths) {
  lapply(relative_paths, function(relative_path) {
    path <- file.path(root, relative_path)
    list(
      path = relative_path,
      bytes = unname(file.info(path)$size),
      sha256 = sha256_file(path)
    )
  })
}

index_entry <- function(player) {
  list(
    player_id = player$player_id,
    player_name = player$player_name,
    player_file = file.path("players", paste0(player$player_id, ".json")),
    evidence_status = player$evidence_status,
    relocation_available = player$relocation_available,
    score_available = player$score_available,
    shot_selection_score = player$score$point,
    score_lower_90 = player$score$lower_90,
    score_upper_90 = player$score$upper_90
  )
}

build_bundle <- function(root, result, pre_result_commit, source_hashes) {
  season_root <- file.path(root, "seasons", season)
  dir.create(file.path(season_root, "players"), recursive = TRUE,
             showWarnings = FALSE)
  player_ids <- sort(as.numeric(names(result$players)))
  ordered <- result$players[as.character(player_ids)]
  index <- list(
    schema_version = SCHEMA_VERSION,
    data_version = DATA_VERSION,
    season = season,
    players = unname(lapply(ordered, index_entry))
  )
  write_json_file(index, file.path(season_root, "players.json"))
  for (player in ordered) {
    write_json_file(
      player,
      file.path(season_root, "players", paste0(player$player_id, ".json"))
    )
  }
  payload_paths <- c(
    file.path("seasons", season, "players.json"),
    file.path("seasons", season, "players", paste0(player_ids, ".json"))
  )
  payload_inventory <- inventory_for(root, payload_paths)
  qualified <- sum(vapply(ordered, `[[`, logical(1), "relocation_available"))
  shot_count <- sum(vapply(ordered, `[[`, integer(1), "observed_attempts"))
  score_quantiles <- as.numeric(stats::quantile(
    result$qualified_scores, c(0, 0.25, 0.5, 0.75, 1), names = FALSE
  ))
  gain_quantiles <- as.numeric(stats::quantile(
    result$qualified_gains, c(0, 0.25, 0.5, 0.75, 1), names = FALSE
  ))
  manifest <- list(
    schema_version = SCHEMA_VERSION,
    data_version = DATA_VERSION,
    export_method = EXPORT_METHOD_ID,
    pre_result_commit = pre_result_commit,
    source_sha256 = as.list(source_hashes),
    seasons = list(list(
      season = season,
      player_index = file.path("seasons", season, "players.json")
    )),
    counts = list(
      seasons = 1L,
      players = length(ordered),
      qualified = qualified,
      insufficient_evidence = length(ordered) - qualified,
      shots = shot_count,
      heatmap_cells = length(ordered) * CELLS_PER_PLAYER,
      sliders = length(ordered) * length(SLIDERS)
    ),
    court = list(
      coordinate_units = "feet",
      basket_center = list(x = 0, y = 0),
      bounds = list(x_min = -25, x_max = 25,
                    y_min = -5.25, y_max = 39.75),
      grid = list(nominal_cell_width_ft = 4, columns = 13L,
                  rows = 12L, cells = CELLS_PER_PLAYER)
    ),
    relocation = list(
      method_id = METHOD_ID,
      requested_shares = as.list(SLIDERS),
      source_rule = paste(
        "Observed cells below the player's weighted posterior-mean expected-points",
        "baseline, ordered weakest first with cell_id as the tie-breaker."
      ),
      destination_rule = paste(
        "At least 10 attempts, at least 90% posterior certainty above the",
        "player's current mix, and at least two supported destinations."
      ),
      destination_allocation = "proportional to existing usage among supported destinations",
      posterior_draws = POSTERIOR_DRAWS,
      uncertainty_interval = "5th and 95th percentiles",
      score_formula = "100 * baseline expected points per attempt / targeted 25% expected points per attempt"
    ),
    shot_fields = list(
      included = c("x_ft", "y_ft", "made", "move_order",
                   "after_x_ft", "after_y_ft"),
      identity_scope = "player and season identity appear only in the containing player payload",
      excluded = c("game identifiers", "event identifiers", "dates and timestamps",
                   "opponents", "score and game situation", "shot clock",
                   "defender and passing context", "fatigue", "unnecessary identifiers")
    ),
    summary = list(
      score_five_number = as.list(score_quantiles),
      gain_per_100_at_25_five_number = as.list(gain_quantiles),
      players_capped_by_weak_source_mass_at_25 = result$capped_players,
      total_weak_source_cells = result$total_source_cells
    ),
    disclaimer = paste(
      "Results are modeled descriptive estimates based on past shots.",
      "They are not causal, do not guarantee improvement, and do not show",
      "that a gold relocated attempt would be made."
    ),
    future_expansion = paste(
      "The same frozen process may add four season folders and a season selector",
      "in a later phase; only 2025-26 is published now."
    ),
    payload_inventory_note = paste(
      "Hashes cover the season player index and 318 player files;",
      "the manifest cannot hash itself."
    ),
    payload_files = payload_inventory
  )
  write_json_file(manifest, file.path(root, "manifest.json"))
  invisible(c("manifest.json", payload_paths))
}

bundle_hashes <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = FALSE))
  setNames(vapply(file.path(root, files), sha256_file, character(1)), files)
}

cell_id_from_feet <- function(x, y) {
  x_index <- pmin(as.integer(floor((round(x * 10) + 250) / 40)) + 1L, 13L)
  y_index <- pmin(as.integer(floor((round(y * 10) + 52.5) / 40)) + 1L, 12L)
  (y_index - 1L) * 13L + x_index
}

validate_bundle <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = FALSE))
  target_assert(length(files) == EXPECTED_PLAYERS + 2L,
                "v2 must contain 320 JSON files")
  target_assert(all(tools::file_ext(files) == "json"),
                "v2 contains a non-JSON file")
  manifest <- fromJSON(file.path(root, "manifest.json"), simplifyVector = FALSE)
  index_path <- file.path(root, "seasons", season, "players.json")
  index <- fromJSON(index_path, simplifyVector = FALSE)
  entries <- index$players
  target_assert(length(entries) == EXPECTED_PLAYERS,
                "season index does not contain 318 players")
  index_ids <- as.numeric(vapply(entries, `[[`, character(1), "player_id"))
  target_assert(identical(index_ids, sort(index_ids)),
                "season index is not sorted by numeric player ID")
  total_shots <- total_cells <- qualified <- insufficient <- 0L
  for (entry in entries) {
    player_path <- file.path(dirname(index_path), entry$player_file)
    target_assert(file.exists(player_path), "season index path does not resolve")
    player <- fromJSON(player_path, simplifyVector = TRUE, flatten = TRUE)
    target_assert(identical(names(player$shots),
                            c("x_ft", "y_ft", "made", "move_order",
                              "after_x_ft", "after_y_ft")),
                  "shot rows contain an unapproved field")
    target_assert(nrow(player$shots) == player$observed_attempts,
                  "player shot total changed")
    target_assert(nrow(player$heatmap_cells) == CELLS_PER_PLAYER &&
                    !anyDuplicated(player$heatmap_cells$cell_id),
                  "player heatmap is incomplete")
    target_assert(nrow(player$sliders) == length(SLIDERS) &&
                    identical(player$sliders$requested_share, SLIDERS),
                  "player slider rows changed")
    target_assert(all(diff(player$sliders$actual_relocated_share) >= -TOLERANCE) &&
                    all(player$sliders$actual_relocated_share <=
                          player$sliders$requested_share + TOLERANCE),
                  "actual slider shares are invalid")
    total_shots <- total_shots + nrow(player$shots)
    total_cells <- total_cells + nrow(player$heatmap_cells)
    if (identical(player$evidence_status, "qualified")) {
      qualified <- qualified + 1L
      score_values <- unlist(player$score, use.names = FALSE)
      target_assert(all(is.finite(score_values)) &&
                      player$score$lower_90 <= player$score$point &&
                      player$score$point <= player$score$upper_90,
                    "qualified score is invalid")
      target_assert(
        identical(unname(unlist(player$sliders[1, c("season_gain.mean",
          "season_gain.lower_90", "season_gain.upper_90",
          "gain_per_100.mean", "gain_per_100.lower_90",
          "gain_per_100.upper_90")])), rep(0, 6)),
        "zero slider gain is not exactly zero"
      )
      orders <- player$shots$move_order[!is.na(player$shots$move_order)]
      target_assert(identical(sort(orders), seq_len(length(orders))),
                    "move orders are not deterministic and nested")
      active <- which(!is.na(player$shots$move_order) &
                        player$shots$move_order <=
                        ceiling(max(player$sliders$actual_relocated_attempt_equivalents)))
      if (length(active) > 0L) {
        destination_ids <- cell_id_from_feet(
          player$shots$after_x_ft[active], player$shots$after_y_ft[active]
        )
        supported_ids <- player$heatmap_cells$cell_id[
          player$heatmap_cells$supported_destination
        ]
        target_assert(all(destination_ids %in% supported_ids),
                      "a marker uses an unsupported destination")
      }
    } else {
      insufficient <- insufficient + 1L
      target_assert(all(is.na(unlist(player$score, use.names = FALSE))),
                    "insufficient-evidence score must be null")
      target_assert(all(player$sliders$actual_relocated_share == 0) &&
                      all(is.na(player$sliders$season_gain.mean)) &&
                      all(is.na(player$sliders$gain_per_100.mean)) &&
                      all(is.na(player$shots$move_order)),
                    "insufficient-evidence relocation must stay null")
    }
  }
  target_assert(total_shots == EXPECTED_SHOTS, "bundle shot total changed")
  target_assert(total_cells == EXPECTED_LATTICE_ROWS, "bundle heatmap total changed")
  target_assert(qualified + insufficient == EXPECTED_PLAYERS,
                "bundle eligibility totals changed")
  target_assert(identical(manifest$counts$shots, EXPECTED_SHOTS) &&
                  identical(manifest$counts$heatmap_cells, EXPECTED_LATTICE_ROWS),
                "manifest counts changed")
  payload_files <- files[files != "manifest.json"]
  inventory_paths <- vapply(manifest$payload_files, `[[`, character(1), "path")
  inventory_hashes <- vapply(manifest$payload_files, `[[`, character(1), "sha256")
  inventory_bytes <- vapply(manifest$payload_files, `[[`, numeric(1), "bytes")
  observed_hashes <- bundle_hashes(root)[inventory_paths]
  observed_bytes <- file.info(file.path(root, inventory_paths))$size
  target_assert(
    !anyDuplicated(inventory_paths) &&
      setequal(inventory_paths, payload_files) &&
      identical(unname(inventory_hashes), unname(observed_hashes)) &&
      identical(as.numeric(inventory_bytes), as.numeric(observed_bytes)),
    "manifest payload inventory differs from the published files"
  )
  collect_keys <- function(value) {
    own <- names(value)
    nested <- if (is.list(value)) unlist(lapply(value, collect_keys),
                                         use.names = FALSE) else character()
    c(own, nested)
  }
  parsed <- lapply(file.path(root, files), fromJSON, simplifyVector = FALSE)
  keys <- unique(unlist(lapply(parsed, collect_keys), use.names = FALSE))
  forbidden_keys <- c(
    "GAME_ID", "game_id", "event_id", "GAME_DATE", "game_date",
    "date", "timestamp", "opponent", "SHOT_CLOCK", "shot_clock",
    "DEFENDER", "defender", "pass", "fatigue", "stable_source_row"
  )
  target_assert(!any(keys %in% forbidden_keys),
                "v2 contains a forbidden shot-context field")
  all_text <- paste(vapply(file.path(root, files), function(path) {
    paste(readLines(path, warn = FALSE), collapse = "")
  }, character(1)), collapse = "\n")
  target_assert(!grepl("/Users/|data/cache|NaN|Infinity", all_text),
                "v2 contains a private path or invalid number")
  list(
    files = files,
    hashes = bundle_hashes(root),
    sizes = setNames(file.info(file.path(root, files))$size, files),
    qualified = qualified,
    insufficient = insufficient,
    shots = total_shots,
    cells = total_cells
  )
}

build_recovered_bundle <- function(root, failed_root) {
  source_player_dir <- file.path(failed_root, "seasons", season, "players")
  source_files <- list.files(source_player_dir, pattern = "^[0-9]+\\.json$",
                             full.names = TRUE)
  target_assert(length(source_files) == EXPECTED_PLAYERS,
                "failed staging does not contain 318 player results")
  players <- lapply(source_files, fromJSON, simplifyVector = FALSE)
  ids <- as.numeric(vapply(players, `[[`, character(1), "player_id"))
  players <- players[order(ids)]
  ids <- sort(ids)
  target_player_dir <- file.path(root, "seasons", season, "players")
  dir.create(target_player_dir, recursive = TRUE, showWarnings = FALSE)
  copied <- file.copy(
    file.path(source_player_dir, paste0(ids, ".json")),
    file.path(target_player_dir, paste0(ids, ".json")),
    overwrite = FALSE
  )
  target_assert(all(copied), "could not preserve recovered player payload bytes")
  entries <- unname(lapply(players, index_entry))
  index <- list(
    schema_version = SCHEMA_VERSION,
    data_version = DATA_VERSION,
    season = season,
    players = entries
  )
  write_json_file(index, file.path(root, "seasons", season, "players.json"))
  payload_paths <- c(
    file.path("seasons", season, "players.json"),
    file.path("seasons", season, "players", paste0(ids, ".json"))
  )
  manifest <- fromJSON(file.path(failed_root, "manifest.json"),
                       simplifyVector = FALSE)
  manifest$payload_files <- inventory_for(root, payload_paths)
  write_json_file(manifest, file.path(root, "manifest.json"))
  invisible(c("manifest.json", payload_paths))
}

source_audit <- verify_sources()
shots_audit <- load_minimal_shots(source_audit$input$player_ids)
cat("Verified frozen sources and", nrow(shots_audit),
    "minimal public-shot candidates across", EXPECTED_PLAYERS, "players.\n")

if (mode == "audit") quit(save = "no", status = 0L)

if (mode == "recover") {
  target_assert(!dir.exists(bundle_dir), "refusing to overwrite v2")
  target_assert(!file.exists(completion_path), "refusing to overwrite v2 completion")
  target_assert(dir.exists(lock_path), "the preserved failed-run lock is missing")
  failed_roots <- Sys.glob(file.path(cache_dir, "v2-first-*"))
  failed_roots <- failed_roots[
    file.exists(file.path(failed_roots, "manifest.json"))
  ]
  target_assert(length(failed_roots) == 1L,
                "expected one complete failed staging bundle")
  first <- tempfile("v2-recovery-first-", cache_dir)
  second <- tempfile("v2-recovery-second-", cache_dir)
  target_assert(dir.create(first), "could not create first recovery staging directory")
  target_assert(dir.create(second), "could not create second recovery staging directory")
  build_recovered_bundle(first, failed_roots[[1]])
  first_check <- validate_bundle(first)
  build_recovered_bundle(second, failed_roots[[1]])
  second_check <- validate_bundle(second)
  target_assert(identical(first_check$files, second_check$files) &&
                  identical(first_check$hashes, second_check$hashes),
                "two recovered v2 builds are not byte-for-byte identical")
  unlink(second, recursive = TRUE)
  dir.create(dirname(bundle_dir), recursive = TRUE, showWarnings = FALSE)
  target_assert(file.rename(first, bundle_dir), "could not publish recovered v2")
  final_check <- validate_bundle(bundle_dir)
  target_assert(identical(first_check$hashes, final_check$hashes),
                "published recovered v2 differs from staging")
  calculation_seconds <- as.numeric(difftime(
    file.info(file.path(failed_roots[[1]], "manifest.json"))$mtime,
    file.info(lock_path)$ctime,
    units = "secs"
  ))
  completion <- list(
    complete = TRUE,
    recovered_after_validator_failure = TRUE,
    data_version = DATA_VERSION,
    method_id = METHOD_ID,
    pre_result_commit = fromJSON(
      file.path(bundle_dir, "manifest.json"), simplifyVector = TRUE
    )$pre_result_commit,
    source_hashes = source_audit$hashes,
    file_hashes = final_check$hashes,
    deterministic_regeneration = TRUE,
    calculation_runtime_seconds_approximate = calculation_seconds,
    maximum_draw_mean_difference_at_most = TOLERANCE,
    qualified = final_check$qualified,
    insufficient = final_check$insufficient,
    shots = final_check$shots,
    cells = final_check$cells,
    total_bytes = sum(final_check$sizes)
  )
  pending <- tempfile("v2-complete-", cache_dir, fileext = ".rds")
  saveRDS(completion, pending)
  target_assert(file.rename(pending, completion_path),
                "could not publish recovered completion marker")
  unlink(lock_path, recursive = TRUE)
  cat("Recovered and published v2 without recalculating posterior draws:",
      length(final_check$files), "files,", final_check$shots, "shots,",
      final_check$qualified, "qualified players,", sum(final_check$sizes),
      "bytes.\n")
  quit(save = "no", status = 0L)
}

if (mode == "verify") {
  target_assert(dir.exists(bundle_dir), "published v2 bundle is missing")
  target_assert(file.exists(completion_path), "v2 completion marker is missing")
  verified <- validate_bundle(bundle_dir)
  completion <- readRDS(completion_path)
  target_assert(isTRUE(completion$complete), "v2 completion is not valid")
  target_assert(identical(verified$hashes, completion$file_hashes),
                "v2 files differ from the completion hashes")
  cat("Verified v2:", length(verified$files), "files,", verified$shots,
      "shots,", verified$cells, "heatmap cells,", verified$qualified,
      "qualified players,", sum(verified$sizes), "bytes.\n")
  quit(save = "no", status = 0L)
}

head_commit <- git_value(c("rev-parse", "HEAD"))[[1]]
upstream_commit <- git_value(c("rev-parse", "@{upstream}"))[[1]]
target_assert(identical(head_commit, upstream_commit),
              "HEAD must match its upstream before production")
tracked_status <- git_value(c("status", "--porcelain", "--untracked-files=no"))
target_assert(length(tracked_status) == 0L,
              "tracked tree must be clean before production")
target_assert(!dir.exists(bundle_dir), "refusing to overwrite v2")
target_assert(!file.exists(completion_path), "refusing to overwrite v2 completion")
target_assert(!dir.exists(lock_path), "another targeted production run is active")
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
target_assert(dir.create(lock_path), "could not acquire targeted production lock")
success <- FALSE
on.exit({ if (success && dir.exists(lock_path)) unlink(lock_path, recursive = TRUE) },
        add = TRUE)

started <- proc.time()[["elapsed"]]
fit <- readRDS(paths[["fit"]])
target_assert(isTRUE(fit$ok) && identical(as.numeric(fit$mode$mode.status), 0),
              "saved production fit is invalid")
lattice <- source_audit$input$lattice |> arrange(PLAYER_ID, cell_id)
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
target_assert(identical(dim(probability_draws),
                        c(EXPECTED_LATTICE_ROWS, POSTERIOR_DRAWS)),
              "posterior draw dimensions changed")
surface <- read_parquet(paths[["surface"]])
result <- calculate_players(
  source_audit$input, shots_audit, surface, probability_draws
)
rm(probability_draws, surface)
gc()

first <- tempfile("v2-first-", cache_dir)
second <- tempfile("v2-second-", cache_dir)
target_assert(dir.create(first), "could not create first v2 staging directory")
target_assert(dir.create(second), "could not create second v2 staging directory")
build_bundle(first, result, head_commit, source_audit$hashes)
first_check <- validate_bundle(first)
build_bundle(second, result, head_commit, source_audit$hashes)
second_check <- validate_bundle(second)
target_assert(identical(first_check$files, second_check$files) &&
                identical(first_check$hashes, second_check$hashes),
              "two v2 builds are not byte-for-byte identical")
unlink(second, recursive = TRUE)
dir.create(dirname(bundle_dir), recursive = TRUE, showWarnings = FALSE)
target_assert(file.rename(first, bundle_dir), "could not publish v2 atomically")
final_check <- validate_bundle(bundle_dir)
target_assert(identical(first_check$hashes, final_check$hashes),
              "published v2 differs from its verified staging build")

runtime <- proc.time()[["elapsed"]] - started
completion <- list(
  complete = TRUE,
  data_version = DATA_VERSION,
  method_id = METHOD_ID,
  pre_result_commit = head_commit,
  source_hashes = source_audit$hashes,
  file_hashes = final_check$hashes,
  deterministic_regeneration = TRUE,
  runtime_seconds = runtime,
  maximum_draw_mean_difference = result$maximum_draw_mean_difference,
  qualified = final_check$qualified,
  insufficient = final_check$insufficient,
  shots = final_check$shots,
  cells = final_check$cells,
  total_bytes = sum(final_check$sizes)
)
pending <- tempfile("v2-complete-", cache_dir, fileext = ".rds")
saveRDS(completion, pending)
target_assert(file.rename(pending, completion_path),
              "could not publish v2 completion marker")
success <- TRUE
cat(toJSON(list(
  output = bundle_dir,
  runtime_seconds = runtime,
  files = length(final_check$files),
  bytes = sum(final_check$sizes),
  players = EXPECTED_PLAYERS,
  qualified = final_check$qualified,
  insufficient_evidence = final_check$insufficient,
  shots = final_check$shots,
  heatmap_cells = final_check$cells,
  maximum_draw_mean_difference = result$maximum_draw_mean_difference,
  score_five_number = as.numeric(stats::quantile(
    result$qualified_scores, c(0, 0.25, 0.5, 0.75, 1), names = FALSE
  )),
  gain_per_100_at_25_five_number = as.numeric(stats::quantile(
    result$qualified_gains, c(0, 0.25, 0.5, 0.75, 1), names = FALSE
  )),
  players_capped_by_weak_source_mass = result$capped_players,
  deterministic_regeneration = TRUE
), auto_unbox = TRUE, pretty = TRUE, digits = 15), "\n")
