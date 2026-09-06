# Sensitivity audit for the frozen targeted-relocation destination evidence rule.
# This script reuses the production CAR fit and draws. It cannot fit a model or
# overwrite the published v2 bundle.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(Matrix)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
season <- if (length(args) >= 1L) args[[1]] else "2025-26"
mode <- if (length(args) >= 2L) args[[2]] else "audit"
target_assert(season == "2025-26", "only the production 2025-26 season may be audited")
target_assert(mode %in% c("audit", "run", "verify", "recover-summary"),
              "mode must be audit, run, verify, or recover-summary")

AUDIT_ID <- "destination-support-sensitivity-v1"
POSTERIOR_DRAWS <- 4000L
POSTERIOR_SEED <- 20260902L
EXPECTED_PLAYERS <- 318L
EXPECTED_SHOTS <- 194987L
CELLS_PER_PLAYER <- 156L
EXPECTED_LATTICE_ROWS <- EXPECTED_PLAYERS * CELLS_PER_PLAYER
MIN_CERTAINTY <- 0.90
MIN_DESTINATIONS <- 2L
REQUESTED_SHARE <- 0.25
TOLERANCE <- 1e-12
WEMBANYAMA_NAME <- "Victor Wembanyama"

EXPECTED_HASHES <- c(
  input = "395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6",
  fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  raw = "20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498",
  v2_manifest = "7dc2a65df883d458b198b763d3072f067cff9ea5997c95e55f6748607925595c",
  v2_index = "1a267881b46bf2de41ca46152c6374ed96832c807ce8ba65d7a51e560abda4b6"
)

production_cache <- file.path("data", "cache", "spatial_car_production",
                              paste0("season=", season))
paths <- c(
  input = file.path(production_cache, "production_input.rds"),
  fit = file.path(production_cache, "car_production_fit.rds"),
  surface = file.path(production_cache, "player_probability_surfaces.parquet"),
  raw = file.path("data", "raw", "shots", paste0("season=", season),
                  "shots.parquet"),
  v2_manifest = file.path("export", "spatial-shot-selection", "v2", "manifest.json"),
  v2_index = file.path("export", "spatial-shot-selection", "v2", "seasons",
                       season, "players.json")
)
result_dir <- file.path("data", "processed", "spatial_destination_support_audit",
                        paste0("season=", season))
cache_dir <- file.path("data", "cache", "spatial_destination_support_audit",
                       paste0("season=", season))
completion_path <- file.path(cache_dir, "complete.rds")
lock_path <- file.path(cache_dir, "run.lock")
OUTPUT_FILES <- c(
  "scenario_summary.parquet",
  "player_scenario_summary.parquet",
  "current_unsupported_failure_breakdown.parquet",
  "wembanyama_cell_trace.parquet",
  "neighborhood_overlap_audit.parquet",
  "calculation_notices.parquet",
  "sanity_checks.parquet",
  "audit_manifest.parquet"
)

scenario_rules <- tibble(
  scenario = c("current_10", "alternative_a_5", "alternative_b_7",
               "alternative_c_neighborhood_10"),
  rule = c(
    "focal cell has at least 10 attempts",
    "focal cell has at least 5 attempts",
    "focal cell has at least 7 attempts",
    paste("observed focal cell plus shared-edge neighbors have at least 10",
          "combined attempts; focal cell has at least one attempt")
  )
)

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  target_assert(length(value) == 1L, paste("could not hash", path))
  strsplit(value, "[[:space:]]+")[[1]][[1]]
}

git_value <- function(arguments) {
  system2("git", arguments, stdout = TRUE, stderr = TRUE)
}

quantile_value <- function(values, probability) {
  as.numeric(stats::quantile(values, probability, names = FALSE, type = 7))
}

capture_conditions <- function(expression) {
  warnings <- messages <- character()
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
  list(value = value, warnings = warnings, messages = messages)
}

verify_sources <- function() {
  expected_versions <- c(
    R = "4.6.0", arrow = "25.0.0", dplyr = "1.2.1",
    Matrix = "1.7.5", INLA = "26.8.7"
  )
  observed_versions <- c(
    R = as.character(getRversion()),
    vapply(names(expected_versions)[-1], function(package) {
      as.character(utils::packageVersion(package))
    }, character(1))
  )
  target_assert(identical(observed_versions, expected_versions),
                "the frozen R or package versions changed")
  target_assert(all(file.exists(paths)), "a frozen source artifact is missing")
  hashes <- vapply(paths, sha256_file, character(1))
  target_assert(identical(hashes, EXPECTED_HASHES), "a frozen source hash changed")
  input <- readRDS(paths[["input"]])
  target_assert(
    isTRUE(input$complete) && identical(input$season, season) &&
      identical(input$player_count, EXPECTED_PLAYERS) &&
      identical(input$shot_count, EXPECTED_SHOTS) &&
      identical(input$lattice_rows, EXPECTED_LATTICE_ROWS),
    "production input metadata changed"
  )
  target_assert(
    identical(dim(input$graph), c(CELLS_PER_PLAYER, CELLS_PER_PLAYER)) &&
      isSymmetric(input$graph) && all(Matrix::diag(input$graph) == 0),
    "production adjacency graph changed"
  )
  manifest <- fromJSON(paths[["v2_manifest"]], simplifyVector = TRUE)
  index <- fromJSON(paths[["v2_index"]], simplifyVector = TRUE)$players
  target_assert(
    identical(manifest$counts$players, EXPECTED_PLAYERS) &&
      identical(manifest$counts$qualified, 122L) &&
      identical(manifest$counts$insufficient_evidence, 196L) &&
      nrow(index) == EXPECTED_PLAYERS,
    "published v2 counts changed"
  )
  wembanyama <- index |> filter(player_name == WEMBANYAMA_NAME)
  target_assert(nrow(wembanyama) == 1L, "verified player index lacks one Wembanyama row")
  list(hashes = hashes, versions = observed_versions, input = input, index = index,
       wembanyama_id = as.numeric(wembanyama$player_id))
}

load_point_values <- function(player_ids) {
  raw <- open_dataset(paths[["raw"]])
  required <- c("PLAYER_ID", "LOC_X", "LOC_Y", "SHOT_TYPE")
  target_assert(all(required %in% names(raw)), "raw input lacks a required field")
  rows <- raw |>
    filter(PLAYER_ID %in% player_ids, LOC_Y <= 397.5) |>
    select(all_of(required)) |>
    collect() |>
    as_tibble() |>
    target_assign_cells()
  target_assert(nrow(rows) == EXPECTED_SHOTS, "eligible shot count changed")
  values <- rows |>
    summarise(
      point_value_attempts = n(),
      three_point_attempts = sum(SHOT_TYPE == "3PT Field Goal"),
      .by = c(PLAYER_ID, cell_id)
    ) |>
    mutate(point_value = 2 + three_point_attempts / point_value_attempts)
  list(rows = rows, values = values)
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

failure_reason <- function(attempt_count, certainty_count, supported_count) {
  if (supported_count >= MIN_DESTINATIONS) return("qualified")
  attempt_has_two <- attempt_count >= MIN_DESTINATIONS
  certainty_has_two <- certainty_count >= MIN_DESTINATIONS
  if (!attempt_has_two && certainty_has_two) return("per_cell_attempt_minimum")
  if (attempt_has_two && !certainty_has_two) return("posterior_certainty")
  if (!attempt_has_two && !certainty_has_two) return("both_evidence_gates")
  "intersection_of_attempt_and_certainty_gates"
}

summarize_draws <- function(values) {
  c(
    mean = mean(values),
    lower_90 = quantile_value(values, 0.05),
    upper_90 = quantile_value(values, 0.95)
  )
}

pair_overlap <- function(supported_cells, attempts, neighborhood) {
  if (length(supported_cells) < 2L) {
    return(c(max_overlap = NA_real_, pair_adjacent = NA_real_))
  }
  pairs <- utils::combn(supported_cells, 2L)
  overlap <- apply(pairs, 2L, function(pair) {
    first <- which(neighborhood[pair[[1]], ] > 0)
    second <- which(neighborhood[pair[[2]], ] > 0)
    shared <- sum(attempts[intersect(first, second)])
    denominator <- min(sum(attempts[first]), sum(attempts[second]))
    if (denominator == 0) 0 else shared / denominator
  })
  chosen <- which.max(overlap)
  pair <- pairs[, chosen]
  c(
    max_overlap = overlap[[chosen]],
    pair_adjacent = as.numeric(neighborhood[pair[[1]], pair[[2]]] > 0 &&
                                 pair[[1]] != pair[[2]])
  )
}

make_scenario_summary <- function(player_results) {
  player_results |>
    summarise(
      qualified_players = sum(qualified),
      unsupported_players = sum(!qualified),
      wembanyama_qualifies = qualified[PLAYER_NAME == WEMBANYAMA_NAME],
      newly_qualified_player_count = sum(newly_qualified_vs_current),
      newly_qualified_high_volume = sum(newly_qualified_vs_current & high_volume),
      minimum_supported_destinations = min(supported_destination_count[qualified]),
      median_supported_destinations = stats::median(supported_destination_count[qualified]),
      maximum_supported_destinations = max(supported_destination_count[qualified]),
      requested_share = REQUESTED_SHARE,
      minimum_actual_relocated_share = min(actual_relocated_share_under_rule[qualified]),
      median_actual_relocated_share = stats::median(actual_relocated_share_under_rule[qualified]),
      maximum_actual_relocated_share = max(actual_relocated_share_under_rule[qualified]),
      players_source_limited_below_25 = sum(qualified &
        achievable_source_share_at_25 < REQUESTED_SHARE - TOLERANCE),
      median_largest_destination_share = stats::median(
        largest_destination_allocation_share[qualified]
      ),
      maximum_largest_destination_share = max(
        largest_destination_allocation_share[qualified]
      ),
      players_above_50_percent_destination_concentration = sum(
        qualified & largest_destination_allocation_share > 0.50
      ),
      gain_per_100_minimum = min(gain_per_100_mean[qualified]),
      gain_per_100_maximum = max(gain_per_100_mean[qualified]),
      gain_interval_width_median = stats::median(
        gain_per_100_interval_width[qualified]
      ),
      gain_interval_width_maximum = max(gain_per_100_interval_width[qualified]),
      players_with_nonpositive_gain_lower_bound = sum(
        qualified & gain_per_100_lower_90 <= 0
      ),
      score_minimum = min(score_point[qualified]),
      score_maximum = max(score_point[qualified]),
      score_interval_width_median = stats::median(score_interval_width[qualified]),
      score_interval_width_maximum = max(score_interval_width[qualified]),
      players_with_exactly_two_destinations = sum(
        qualified & supported_destination_count == 2L
      ),
      .by = scenario
    ) |>
    left_join(scenario_rules, by = "scenario") |>
    arrange(match(scenario, scenario_rules$scenario))
}

write_outputs <- function(outputs, staging) {
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  for (name in names(outputs)) {
    write_parquet(outputs[[name]], file.path(staging, name))
  }
}

verify_outputs <- function(directory, expected_hashes = NULL) {
  files <- file.path(directory, OUTPUT_FILES)
  target_assert(all(file.exists(files)), "an audit output is missing")
  hashes <- setNames(vapply(files, sha256_file, character(1)), OUTPUT_FILES)
  if (!is.null(expected_hashes)) {
    target_assert(identical(hashes, expected_hashes), "an audit output hash changed")
  }
  hashes
}

audit <- verify_sources()
cat("Verified frozen CAR and v2 sources; Wembanyama player ID is",
    audit$wembanyama_id, ".\n")
if (mode == "audit") quit(save = "no", status = 0L)

if (mode == "verify") {
  target_assert(file.exists(completion_path), "audit completion marker is missing")
  completion <- readRDS(completion_path)
  target_assert(isTRUE(completion$complete) &&
                  identical(completion$source_hashes, EXPECTED_HASHES),
                "audit completion marker is invalid")
  verify_outputs(result_dir, completion$output_hashes)
  cat("Verified destination-support audit outputs.\n")
  quit(save = "no", status = 0L)
}

if (mode == "recover-summary") {
  target_assert(dir.exists(result_dir) && file.exists(completion_path),
                "completed audit outputs are required for summary recovery")
  original_completion <- readRDS(completion_path)
  target_assert(isTRUE(original_completion$complete),
                "original audit completion is invalid")
  verify_outputs(result_dir, original_completion$output_hashes)
  players <- read_parquet(file.path(result_dir, "player_scenario_summary.parquet"))
  corrected_summary <- make_scenario_summary(players)
  target_assert(
    identical(corrected_summary$newly_qualified_player_count,
              c(0L, 27L, 13L, 34L)) &&
      identical(corrected_summary$newly_qualified_high_volume,
                c(0L, 6L, 2L, 6L)),
    "recovered aggregate counts are unexpected"
  )
  original_checks <- read_parquet(file.path(result_dir, "sanity_checks.parquet"))
  corrected_checks <- bind_rows(
    original_checks,
    tibble(
      check = "scenario_aggregate_counts",
      passed = TRUE,
      detail = paste(
        "newly qualified 0,27,13,34; newly qualified high-volume 0,6,2,6"
      )
    )
  )
  archive_root <- file.path(cache_dir, "invalid-summary-shadow")
  archive_results <- file.path(archive_root, "results")
  archive_completion <- file.path(archive_root, "complete.rds")
  target_assert(!dir.exists(archive_root),
                "summary-recovery archive already exists")
  dir.create(archive_root, recursive = TRUE, showWarnings = FALSE)
  target_assert(file.rename(result_dir, archive_results),
                "could not preserve the original result bundle")
  target_assert(file.rename(completion_path, archive_completion),
                "could not preserve the original completion checkpoint")
  if (dir.exists(lock_path)) {
    target_assert(file.rename(lock_path, file.path(archive_root,
                                                   "verified-run-stale.lock")),
                  "could not preserve the stale success lock")
  }
  staging <- tempfile("destination-support-summary-recovery-", dirname(result_dir))
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  unchanged_files <- setdiff(OUTPUT_FILES,
                             c("scenario_summary.parquet", "sanity_checks.parquet"))
  copied <- file.copy(file.path(archive_results, unchanged_files), staging,
                      overwrite = FALSE)
  target_assert(all(copied), "could not preserve unchanged audit outputs")
  write_parquet(corrected_summary, file.path(staging, "scenario_summary.parquet"))
  write_parquet(corrected_checks, file.path(staging, "sanity_checks.parquet"))
  corrected_hashes <- verify_outputs(staging)
  dir.create(dirname(result_dir), recursive = TRUE, showWarnings = FALSE)
  target_assert(file.rename(staging, result_dir),
                "could not publish corrected audit outputs")
  target_assert(identical(verify_outputs(result_dir), corrected_hashes),
                "published recovery differs from staging")
  corrected_completion <- original_completion
  corrected_completion$recovered_summary_shadow <- TRUE
  corrected_completion$original_output_hashes <- original_completion$output_hashes
  corrected_completion$output_hashes <- corrected_hashes
  corrected_completion$checks <- corrected_checks
  pending <- tempfile("destination-support-recovered-complete-", cache_dir,
                      fileext = ".rds")
  saveRDS(corrected_completion, pending)
  target_assert(file.rename(pending, completion_path),
                "could not publish recovered completion checkpoint")
  cat("Recovered the scenario aggregate from verified per-player results;",
      "posterior draws were not regenerated.\n")
  quit(save = "no", status = 0L)
}

target_assert(!dir.exists(result_dir), "refusing to overwrite audit outputs")
target_assert(!file.exists(completion_path), "refusing to overwrite audit completion")
target_assert(!dir.exists(lock_path), "another destination-support audit is active")
head_commit <- git_value(c("rev-parse", "HEAD"))[[1]]
upstream_commit <- git_value(c("rev-parse", "@{upstream}"))[[1]]
target_assert(identical(head_commit, upstream_commit),
              "audit code must be pushed before results are calculated")
tracked_status <- git_value(c("status", "--porcelain", "--untracked-files=no"))
target_assert(length(tracked_status) == 0L, "tracked tree must be clean before audit")

dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
target_assert(dir.create(lock_path), "could not acquire audit lock")
success <- FALSE
on.exit({ if (success && dir.exists(lock_path)) unlink(lock_path, recursive = TRUE) },
        add = TRUE)
started <- proc.time()[["elapsed"]]

input <- audit$input
shot_values <- load_point_values(input$player_ids)
lattice <- input$lattice |>
  arrange(PLAYER_ID, cell_id) |>
  left_join(shot_values$values, by = c("PLAYER_ID", "cell_id")) |>
  mutate(
    baseline_share = attempts / sum(attempts),
    point_value_for_calculation = coalesce(point_value, 0),
    .by = PLAYER_ID
  )
target_assert(
  all(lattice$attempts[lattice$attempts > 0] ==
        lattice$point_value_attempts[lattice$attempts > 0]),
  "shot values do not reproduce production attempt counts"
)

fit <- readRDS(paths[["fit"]])
target_assert(isTRUE(fit$ok) && identical(as.numeric(fit$mode$mode.status), 0),
              "saved production fit is invalid")
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
set.seed(POSTERIOR_SEED)
captured <- capture_conditions(INLA::inla.posterior.sample(
  n = POSTERIOR_DRAWS,
  result = fit,
  selection = list(Predictor = lattice$predictor_index),
  seed = POSTERIOR_SEED,
  num.threads = 1L,
  parallel.configs = FALSE,
  add.names = FALSE
))
probability_draws <- plogis(extract_predictors(captured$value,
                                               lattice$predictor_index))
captured$value <- NULL
rm(fit)
gc()
target_assert(identical(dim(probability_draws),
                        c(EXPECTED_LATTICE_ROWS, POSTERIOR_DRAWS)) &&
                all(is.finite(probability_draws)),
              "posterior draw matrix is invalid")
surface <- read_parquet(paths[["surface"]]) |> arrange(PLAYER_ID, cell_id)
draw_mean_difference <- max(abs(rowMeans(probability_draws) -
                                  surface$draw_mean_probability))
target_assert(draw_mean_difference <= TOLERANCE,
              "frozen draws do not reproduce the production surface")

neighborhood <- input$graph
Matrix::diag(neighborhood) <- 1
player_ids <- input$player_ids
player_attempts <- lattice |>
  summarise(attempts = sum(attempts), makes = sum(makes),
            occupied_cells = sum(attempts > 0L), .by = c(PLAYER_ID, PLAYER_NAME)) |>
  arrange(PLAYER_ID)
high_volume_cutoff <- as.numeric(stats::quantile(
  player_attempts$attempts, 0.75, names = FALSE, type = 1
))

baseline_draws <- matrix(NA_real_, nrow = EXPECTED_PLAYERS,
                         ncol = POSTERIOR_DRAWS)
support_probability <- rep(NA_real_, EXPECTED_LATTICE_ROWS)
neighborhood_attempts <- integer(EXPECTED_LATTICE_ROWS)
posterior_mean_expected_points <- rep(NA_real_, EXPECTED_LATTICE_ROWS)
source_orders <- vector("list", EXPECTED_PLAYERS)
source_shares <- numeric(EXPECTED_PLAYERS)

for (player_index in seq_along(player_ids)) {
  rows <- which(lattice$PLAYER_ID == player_ids[[player_index]])
  player <- lattice[rows, , drop = FALSE]
  draws <- probability_draws[rows, , drop = FALSE]
  baseline_draws[player_index, ] <- colSums(
    draws * player$baseline_share * player$point_value_for_calculation
  )
  observed <- player$attempts > 0L
  support_probability[rows[observed]] <- rowMeans(
    sweep(draws[observed, , drop = FALSE] * player$point_value[observed],
          2L, baseline_draws[player_index, ], `>`)
  )
  neighborhood_attempts[rows] <- as.integer(round(
    as.numeric(neighborhood %*% player$attempts)
  ))
  posterior_mean_expected_points[rows[observed]] <-
    rowMeans(draws[observed, , drop = FALSE]) * player$point_value[observed]
  source_orders[[player_index]] <- target_source_order(
    player$attempts,
    posterior_mean_expected_points[rows],
    mean(baseline_draws[player_index, ]),
    player$cell_id
  )
  source_shares[[player_index]] <- sum(
    player$baseline_share[source_orders[[player_index]]]
  )
}

lattice <- lattice |>
  mutate(
    posterior_probability_above_current_mix = support_probability,
    certainty_pass = coalesce(support_probability >= MIN_CERTAINTY, FALSE),
    neighborhood_attempts = neighborhood_attempts,
    posterior_mean_expected_points = posterior_mean_expected_points
  )

player_results <- vector("list", nrow(scenario_rules) * EXPECTED_PLAYERS)
result_index <- 0L
overlap_rows <- vector("list", EXPECTED_PLAYERS)

for (scenario_index in seq_len(nrow(scenario_rules))) {
  scenario <- scenario_rules$scenario[[scenario_index]]
  for (player_index in seq_along(player_ids)) {
    result_index <- result_index + 1L
    player_id <- player_ids[[player_index]]
    rows <- which(lattice$PLAYER_ID == player_id)
    player <- lattice[rows, , drop = FALSE]
    attempt_pass <- switch(
      scenario,
      current_10 = player$attempts >= 10L,
      alternative_a_5 = player$attempts >= 5L,
      alternative_b_7 = player$attempts >= 7L,
      alternative_c_neighborhood_10 = player$attempts > 0L &
        player$neighborhood_attempts >= 10L
    )
    supported <- attempt_pass & player$certainty_pass
    destination_count <- sum(supported)
    qualified <- destination_count >= MIN_DESTINATIONS
    weights <- numeric(CELLS_PER_PLAYER)
    if (qualified) {
      weights[supported] <- player$baseline_share[supported] /
        sum(player$baseline_share[supported])
    }
    source_order <- source_orders[[player_index]]
    removal <- target_remove_mass(player$baseline_share, source_order,
                                  REQUESTED_SHARE)
    actual_share <- if (qualified) removal$actual else 0
    gain_summary <- season_summary <- c(
      mean = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_
    )
    score <- c(point = NA_real_, lower_90 = NA_real_, upper_90 = NA_real_)
    largest_post_share <- NA_real_
    if (qualified) {
      relocated_share <- player$baseline_share - removal$removed +
        removal$actual * weights
      relocated_draws <- colSums(
        probability_draws[rows, , drop = FALSE] *
          relocated_share * player$point_value_for_calculation
      )
      gains <- relocated_draws - baseline_draws[player_index, ]
      gain_summary <- summarize_draws(100 * gains)
      season_summary <- summarize_draws(sum(player$attempts) * gains)
      score <- unlist(target_score(baseline_draws[player_index, ], relocated_draws),
                      use.names = TRUE)
      largest_post_share <- max(relocated_share)
    }
    player_results[[result_index]] <- tibble(
      scenario = scenario,
      PLAYER_ID = player_id,
      PLAYER_NAME = player$PLAYER_NAME[[1]],
      attempts = sum(player$attempts),
      makes = sum(player$makes),
      misses = sum(player$attempts) - sum(player$makes),
      occupied_cells = sum(player$attempts > 0L),
      high_volume = sum(player$attempts) >= high_volume_cutoff,
      attempt_rule_pass_cell_count = sum(attempt_pass),
      certainty_pass_cell_count = sum(player$certainty_pass),
      supported_destination_count = destination_count,
      qualified = qualified,
      failure_reason = failure_reason(sum(attempt_pass),
                                      sum(player$certainty_pass),
                                      destination_count),
      eligible_source_share = source_shares[[player_index]],
      requested_relocated_share = REQUESTED_SHARE,
      achievable_source_share_at_25 = removal$actual,
      actual_relocated_share_under_rule = actual_share,
      largest_destination_allocation_share = if (qualified) max(weights) else NA_real_,
      largest_post_relocation_cell_share = largest_post_share,
      gain_per_100_mean = unname(gain_summary[["mean"]]),
      gain_per_100_lower_90 = unname(gain_summary[["lower_90"]]),
      gain_per_100_upper_90 = unname(gain_summary[["upper_90"]]),
      gain_per_100_interval_width = unname(gain_summary[["upper_90"]] -
                                             gain_summary[["lower_90"]]),
      season_gain_mean = unname(season_summary[["mean"]]),
      season_gain_lower_90 = unname(season_summary[["lower_90"]]),
      season_gain_upper_90 = unname(season_summary[["upper_90"]]),
      score_point = unname(score[["point"]]),
      score_lower_90 = unname(score[["lower_90"]]),
      score_upper_90 = unname(score[["upper_90"]]),
      score_interval_width = unname(score[["upper_90"]] - score[["lower_90"]])
    )

    if (scenario == "alternative_c_neighborhood_10") {
      supported_cells <- which(supported)
      overlap <- pair_overlap(supported_cells, player$attempts, neighborhood)
      overlap_rows[[player_index]] <- tibble(
        PLAYER_ID = player_id,
        PLAYER_NAME = player$PLAYER_NAME[[1]],
        qualified = qualified,
        supported_destination_count = destination_count,
        minimum_focal_attempts_among_supported = if (destination_count > 0L)
          min(player$attempts[supported]) else NA_integer_,
        supported_destinations_with_fewer_than_5_focal_attempts =
          sum(supported & player$attempts < 5L),
        maximum_pair_shared_evidence_share = unname(overlap[["max_overlap"]]),
        maximum_overlap_pair_is_adjacent = if (is.na(overlap[["pair_adjacent"]]))
          NA else as.logical(overlap[["pair_adjacent"]]),
        essentially_same_evidence_pair = if (is.na(overlap[["max_overlap"]]))
          NA else overlap[["max_overlap"]] >= 0.80
      )
    }
  }
}

player_results <- bind_rows(player_results)
current_status <- player_results |>
  filter(scenario == "current_10") |>
  select(PLAYER_ID, current_qualified = qualified)
player_results <- player_results |>
  left_join(current_status, by = "PLAYER_ID") |>
  mutate(newly_qualified_vs_current = qualified & !current_qualified) |>
  arrange(scenario, PLAYER_ID)
neighborhood_overlap <- bind_rows(overlap_rows) |> arrange(PLAYER_ID)

v2_player_dir <- file.path("export", "spatial-shot-selection", "v2", "seasons",
                           season, "players")
v2_current <- bind_rows(lapply(player_ids, function(player_id) {
  player <- fromJSON(file.path(v2_player_dir, paste0(player_id, ".json")),
                     simplifyVector = FALSE)
  slider_25 <- player$sliders[[length(player$sliders)]]
  tibble(
    PLAYER_ID = as.numeric(player$player_id),
    v2_evidence_status = player$evidence_status,
    v2_supported_destination_count = player$supported_destination_count,
    v2_actual_relocated_share = slider_25$actual_relocated_share,
    v2_gain_per_100_mean = slider_25$gain_per_100$mean,
    v2_score_point = player$score$point
  )
}))
current_comparison <- player_results |>
  filter(scenario == "current_10") |>
  left_join(v2_current, by = "PLAYER_ID")
current_numeric_difference <- max(c(
  abs(current_comparison$actual_relocated_share_under_rule -
        current_comparison$v2_actual_relocated_share),
  abs(current_comparison$gain_per_100_mean - current_comparison$v2_gain_per_100_mean),
  abs(current_comparison$score_point - current_comparison$v2_score_point)
), na.rm = TRUE)

scenario_summary <- make_scenario_summary(player_results)

current_unsupported <- player_results |>
  filter(scenario == "current_10", !qualified) |>
  transmute(
    PLAYER_ID, PLAYER_NAME, attempts, makes, misses, occupied_cells, high_volume,
    cells_with_at_least_10_attempts = attempt_rule_pass_cell_count,
    cells_with_at_least_90_percent_certainty = certainty_pass_cell_count,
    cells_passing_both = supported_destination_count,
    failure_reason,
    immediate_rule = "fewer_than_two_supported_destinations"
  ) |>
  arrange(desc(attempts), PLAYER_ID)

wembanyama_rows <- which(lattice$PLAYER_ID == audit$wembanyama_id)
wembanyama_cells <- lattice[wembanyama_rows, ] |>
  transmute(
    PLAYER_ID, PLAYER_NAME, cell_id, x_ft, y_ft, attempts, makes,
    misses = attempts - makes,
    occupied = attempts > 0L,
    neighborhood_attempts,
    posterior_mean_expected_points,
    posterior_probability_above_current_mix,
    certainty_pass,
    current_10_attempt_pass = attempts >= 10L,
    current_supported = attempts >= 10L & certainty_pass,
    alternative_a_5_attempt_pass = attempts >= 5L,
    alternative_a_supported = attempts >= 5L & certainty_pass,
    alternative_b_7_attempt_pass = attempts >= 7L,
    alternative_b_supported = attempts >= 7L & certainty_pass,
    neighborhood_10_attempt_pass = attempts > 0L & neighborhood_attempts >= 10L,
    neighborhood_supported = neighborhood_10_attempt_pass & certainty_pass
  ) |>
  arrange(cell_id)

notices <- bind_rows(
  tibble(type = rep("warning", length(captured$warnings)), message = captured$warnings),
  tibble(type = rep("message", length(captured$messages)), message = captured$messages)
)
if (nrow(notices) == 0L) notices <- tibble(type = "none", message = "none")

checks <- tibble(
  check = c(
    "source_hashes_match", "draws_reproduce_surface", "player_count",
    "current_counts_match_v2", "wembanyama_identity", "wembanyama_attempts",
    "current_results_match_v2", "all_scenarios_complete",
    "actual_share_never_exceeds_requested", "qualified_results_finite",
    "unsupported_results_missing", "no_model_fit_called"
  ),
  passed = c(
    identical(audit$hashes, EXPECTED_HASHES),
    draw_mean_difference <= TOLERANCE,
    n_distinct(player_results$PLAYER_ID) == EXPECTED_PLAYERS,
    sum(player_results$qualified[player_results$scenario == "current_10"]) == 122L,
    audit$wembanyama_id == 1641705,
    player_attempts$attempts[player_attempts$PLAYER_ID == audit$wembanyama_id] == 1080L,
    all(current_comparison$qualified ==
          (current_comparison$v2_evidence_status == "qualified")) &&
      all(current_comparison$supported_destination_count ==
            current_comparison$v2_supported_destination_count) &&
      current_numeric_difference <= TOLERANCE,
    nrow(player_results) == EXPECTED_PLAYERS * nrow(scenario_rules),
    all(player_results$actual_relocated_share_under_rule <= REQUESTED_SHARE + TOLERANCE),
    all(is.finite(as.matrix(player_results[player_results$qualified,
      c("gain_per_100_mean", "gain_per_100_lower_90", "gain_per_100_upper_90",
        "score_point", "score_lower_90", "score_upper_90")]))),
    all(is.na(player_results$gain_per_100_mean[!player_results$qualified])) &&
      all(is.na(player_results$score_point[!player_results$qualified])),
    TRUE
  ),
  detail = c(
    paste(audit$hashes, collapse = "; "),
    format(draw_mean_difference, scientific = TRUE),
    as.character(n_distinct(player_results$PLAYER_ID)),
    as.character(sum(player_results$qualified[player_results$scenario == "current_10"])),
    as.character(audit$wembanyama_id),
    as.character(player_attempts$attempts[player_attempts$PLAYER_ID == audit$wembanyama_id]),
    paste("maximum numeric difference", format(current_numeric_difference,
                                                scientific = TRUE)),
    as.character(nrow(player_results)),
    format(max(player_results$actual_relocated_share_under_rule), digits = 15),
    "all qualified gain and score summaries are finite",
    "unsupported gain and score summaries remain missing",
    "script contains posterior sampling but no model-fitting call"
  )
)
target_assert(all(checks$passed), "one or more audit checks failed")

manifest <- tibble(
  audit_id = AUDIT_ID,
  season = season,
  pre_result_commit = head_commit,
  posterior_draws = POSTERIOR_DRAWS,
  posterior_seed = POSTERIOR_SEED,
  minimum_certainty = MIN_CERTAINTY,
  minimum_destinations = MIN_DESTINATIONS,
  requested_share = REQUESTED_SHARE,
  high_volume_definition = "top quartile of production-eligible players by total attempts",
  high_volume_cutoff_attempts = high_volume_cutoff,
  adjacency_definition = "production shared-edge CAR graph; focal cell included; diagonals excluded",
  essentially_same_evidence_diagnostic = "maximum pair overlap at least 80% of the smaller neighborhood attempt total",
  production_v2_modified = FALSE,
  model_refit = FALSE,
  runtime_seconds = proc.time()[["elapsed"]] - started
)

outputs <- list(
  "scenario_summary.parquet" = scenario_summary,
  "player_scenario_summary.parquet" = player_results,
  "current_unsupported_failure_breakdown.parquet" = current_unsupported,
  "wembanyama_cell_trace.parquet" = wembanyama_cells,
  "neighborhood_overlap_audit.parquet" = neighborhood_overlap,
  "calculation_notices.parquet" = notices,
  "sanity_checks.parquet" = checks,
  "audit_manifest.parquet" = manifest
)
staging <- tempfile("destination-support-audit-", dirname(result_dir))
write_outputs(outputs, staging)
output_hashes <- verify_outputs(staging)
dir.create(dirname(result_dir), recursive = TRUE, showWarnings = FALSE)
target_assert(file.rename(staging, result_dir), "could not publish audit outputs")
target_assert(identical(verify_outputs(result_dir), output_hashes),
              "published audit outputs differ from staging")
completion <- list(
  complete = TRUE,
  audit_id = AUDIT_ID,
  source_hashes = EXPECTED_HASHES,
  pre_result_commit = head_commit,
  output_hashes = output_hashes,
  checks = checks
)
pending <- tempfile("destination-support-complete-", cache_dir, fileext = ".rds")
saveRDS(completion, pending)
target_assert(file.rename(pending, completion_path),
              "could not publish audit completion marker")
success <- TRUE
unlink(lock_path, recursive = TRUE)
target_assert(!dir.exists(lock_path), "could not release the completed audit lock")
cat("Completed destination-support sensitivity audit:",
    paste(scenario_summary$qualified_players, collapse = ", "),
    "qualified players across the four scenarios.\n")
