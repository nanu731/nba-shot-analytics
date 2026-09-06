suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("TEST FAILED: ", label, call. = FALSE)
}

seasons <- c("2025-26", "2024-25", "2023-24", "2022-23", "2021-22")
expected <- tibble(
  season = seasons,
  raw_rows = c(219160L, 219527L, 218700L, 217220L, 216722L),
  games = rep(1230L, 5L),
  eligible_players = c(318L, 304L, 281L, 292L, 312L),
  eligible_shots = c(194987L, 194526L, 192608L, 192897L, 193577L)
)

schemas <- character()
eligible_ids <- list()
for (season in seasons) {
  path <- file.path("data", "raw", "shots", paste0("season=", season),
                    "shots.parquet")
  shots <- read_parquet(
    path,
    col_select = c("GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_X", "LOC_Y",
                   "SHOT_ATTEMPTED_FLAG", "SHOT_MADE_FLAG")
  ) |>
    as_tibble()
  row <- filter(expected, .data$season == .env$season)
  expect_true(nrow(shots) == row$raw_rows, paste(season, "raw row count"))
  expect_true(is.character(shots$GAME_ID) &&
                n_distinct(shots$GAME_ID) == row$games,
              paste(season, "text game ids"))
  in_play <- filter(shots, LOC_Y <= 397.5)
  eligibility <- in_play |>
    summarise(games = n_distinct(GAME_ID), attempts = n(), .by = PLAYER_ID) |>
    filter(games >= 20L, attempts >= 250L) |>
    arrange(PLAYER_ID)
  eligible_ids[[season]] <- eligibility$PLAYER_ID
  expect_true(nrow(eligibility) == row$eligible_players,
              paste(season, "eligible player count"))
  expect_true(sum(in_play$PLAYER_ID %in% eligibility$PLAYER_ID) ==
                row$eligible_shots,
              paste(season, "eligible shot count"))
  schemas[[season]] <- paste(names(read_parquet(path, as_data_frame = FALSE)$schema),
                             collapse = "|")
}
expect_true(length(unique(schemas)) == 1L, "raw season schemas match")
expect_true(all(vapply(eligible_ids, function(ids) 2544L %in% ids, logical(1))),
            "LeBron James is eligible in all five seasons")

split_games <- function(game_ids) {
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(20260830L)
  shuffled <- sample(sort(unique(game_ids)), length(unique(game_ids)),
                     replace = FALSE)
  tibble(GAME_ID = shuffled, fold = rep(1:5, length.out = length(shuffled))) |>
    arrange(GAME_ID)
}
pilot_games <- read_parquet(
  file.path("data", "raw", "shots", "season=2024-25", "shots.parquet"),
  col_select = "GAME_ID"
)$GAME_ID
expect_true(identical(split_games(pilot_games), split_games(rev(pilot_games))),
            "game folds are deterministic and input-order independent")

# Season isolation: the same player ID is present in multiple registries, but
# each registry is derived from only one season's shots.
expect_true(length(intersect(eligible_ids[["2024-25"]],
                             eligible_ids[["2023-24"]])) > 0L,
            "stable player IDs map across seasons")
expect_true(!identical(eligible_ids[["2024-25"]], eligible_ids[["2023-24"]]),
            "season registries remain distinct")

# Frozen relocation helpers cover zero, one, and multiple destinations, plus
# the universal cap and fractional weakest-first removal.
expect_true(identical(target_evidence_status(0L), "insufficient_evidence") &&
              identical(target_evidence_status(1L), "single_destination") &&
              identical(target_evidence_status(2L), "multiple_destinations"),
            "three evidence states")
allocation <- target_capped_allocation(
  baseline_share = c(0.30, 0.40, 0.30),
  supported = c(TRUE, FALSE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.40,
  destination_cap = 0.50
)
expect_true(abs(allocation$actual - 0.20) <= 1e-12 &&
              max(c(0.30, 0.40, 0.30) + allocation$added) <= 0.50 + 1e-12,
            "single destination respects 50 percent cap")
removal <- target_remove_mass(c(0.20, 0.30, 0.50), c(1L, 2L), 0.25)
expect_true(max(abs(removal$removed - c(0.20, 0.05, 0))) <= 1e-12,
            "fractional final source cell")

cat("All multiseason production tests passed.\n")
