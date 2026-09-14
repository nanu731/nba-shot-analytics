#!/usr/bin/env Rscript

# Build the field-goal-only Context Edition canonical dataset. Shot-level
# outputs stay under data/cache; tracked outputs are aggregate or declarative.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
})

repo_root <- normalizePath(".", mustWork = TRUE)
stopifnot(file.exists(file.path(repo_root, "AGENTS.md")))

args <- commandArgs(trailingOnly = TRUE)
season_arg <- args[str_detect(args, "^--seasons=")]
if (length(season_arg) != 1L) {
  stop("Pass exactly one --seasons= argument")
}
seasons <- str_split(sub("^--seasons=", "", season_arg), ",", simplify = TRUE) |>
  as.character()
training_seasons <- c("2021-22", "2022-23")
extended_seasons <- c(training_seasons, "2023-24", "2024-25", "2025-26")
build_scope <- if (identical(seasons, training_seasons)) {
  "accepted_training_seasons"
} else if (identical(seasons, extended_seasons)) {
  "five_season_extension"
} else {
  stop(
    "This frozen build accepts exactly 2021-22,2022-23 or ",
    "2021-22,2022-23,2023-24,2024-25,2025-26 in that order"
  )
}

schema_version <- "context_field_goal_v0.1.2"
taxonomy_version <- "context_taxonomy_v0.1.0"
join_version <- "shotchart_espn_exact_clock_player_v0.1.1"
expected_shots <- c(
  `2021-22` = 216722L, `2022-23` = 217220L, `2023-24` = 218700L,
  `2024-25` = 219527L, `2025-26` = 219160L
)
expected_unique_matches <- c(`2021-22` = 191079L, `2022-23` = 194530L)
pbp_years <- c(
  `2021-22` = 2022L, `2022-23` = 2023L, `2023-24` = 2024L,
  `2024-25` = 2025L, `2025-26` = 2026L
)

shot_paths <- file.path(
  repo_root, "data", "raw", "shots", paste0("season=", seasons), "shots.parquet"
)
pbp_paths <- file.path(
  repo_root, "data", "cache", "context_edition_audit",
  paste0("play_by_play_", unname(pbp_years[seasons]), ".rds")
)
taxonomy_path <- file.path(repo_root, "config", "context_edition_taxonomy_v0_1.csv")
accepted_hash_path <- file.path(
  repo_root, "config", "context_edition_accepted_v0_1_2_hashes.csv"
)
script_path <- file.path(repo_root, "R", "context_edition_build_canonical.R")
tracked_parent <- file.path(repo_root, "data", "processed")
tracked_dir <- file.path(
  tracked_parent,
  if (build_scope == "five_season_extension") {
    "context_edition_canonical_v0_1_2_five_season"
  } else {
    "context_edition_canonical_v0_1_2"
  }
)
cache_parent <- file.path(repo_root, "data", "cache", "context_edition_canonical")
canonical_namespace <- if (build_scope == "five_season_extension") {
  paste0(schema_version, "__2021-22_to_2025-26")
} else {
  schema_version
}
canonical_dir <- file.path(cache_parent, canonical_namespace)
lock_dir <- file.path(cache_parent, paste0(".build-lock-", canonical_namespace))

required_paths <- c(shot_paths, pbp_paths, taxonomy_path, accepted_hash_path, script_path)
if (!all(file.exists(required_paths))) {
  stop("Missing required input: ", paste(required_paths[!file.exists(required_paths)], collapse = "; "))
}
dir.create(cache_parent, recursive = TRUE, showWarnings = FALSE)
if (dir.exists(lock_dir)) stop("A canonical build lock already exists: ", lock_dir)
if (dir.exists(canonical_dir)) stop("A canonical output already exists; verify it instead of overwriting: ", canonical_dir)
if (dir.exists(tracked_dir)) stop("Tracked canonical outputs already exist; verify them instead of overwriting")
if (!dir.create(lock_dir, showWarnings = FALSE)) stop("Could not acquire canonical build lock")

writeLines(
  c(
    paste0("pid=", Sys.getpid()),
    paste0("started_at_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste0("schema_version=", schema_version),
    paste0("build_scope=", build_scope),
    paste0("seasons=", paste(seasons, collapse = ";"))
  ),
  file.path(lock_dir, "metadata.txt")
)

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(result) != 1L) stop("Could not hash ", path)
  strsplit(result[[1]], " ", fixed = TRUE)[[1]][[1]]
}

normalize_team <- function(x) {
  recode(
    x, GS = "GSW", NO = "NOP", NY = "NYK", SA = "SAS",
    UTAH = "UTA", WSH = "WAS", .default = x
  )
}

normalize_name <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]", "") |>
    str_replace("(jr|sr|ii|iii|iv)$", "")
}

write_csv_stable <- function(data, path) {
  readr::write_csv(data, path, na = "", quote = "needed")
}

input_manifest <- tibble(
  source = c(rep("NBA ShotChartDetail local extract", length(seasons)),
             rep("hoopR SportsDataverse ESPN play-by-play release", length(seasons)),
             "frozen taxonomy mapping", "accepted artifact hash register",
             "canonical build script"),
  season = c(seasons, seasons, NA_character_, NA_character_, NA_character_),
  release_year = c(rep(NA_integer_, length(seasons)), unname(pbp_years[seasons]),
                   NA_integer_, NA_integer_, NA_integer_),
  file = c(
    file.path("data", "raw", "shots", paste0("season=", seasons), "shots.parquet"),
    file.path("data", "cache", "context_edition_audit", paste0("play_by_play_", unname(pbp_years[seasons]), ".rds")),
    file.path("config", basename(taxonomy_path)),
    file.path("config", basename(accepted_hash_path)),
    file.path("R", basename(script_path))
  ),
  bytes = file.info(required_paths)$size,
  sha256 = map_chr(required_paths, sha256_file),
  accessed = TRUE,
  contains_2026_27 = FALSE
)

taxonomy <- read_csv(taxonomy_path, show_col_types = FALSE) |>
  arrange(ACTION_TYPE)
if (anyDuplicated(taxonomy$ACTION_TYPE) || nrow(taxonomy) != 48L) {
  stop("The frozen taxonomy must contain 48 unique raw labels")
}
if (!setequal(unique(taxonomy$finish_family), c(
  "dunk", "layup", "floater", "hook", "regular_jumper",
  "fadeaway_or_turnaround", "step_back"
))) stop("The frozen seven-family finish taxonomy changed")
if (!setequal(unique(taxonomy$creation_family), c(
  "drive_cut_or_roll", "pull_up_or_self_created", "putback", "other_or_unknown"
))) stop("The frozen creation taxonomy changed")

build_canonical <- function() {
  shot_list <- map2(seasons, shot_paths, function(season_value, shot_path) {
    read_parquet(shot_path, as_data_frame = TRUE) |>
      mutate(
        season = season_value,
        source_shot_sha256 = sha256_file(shot_path),
        canonical_shot_key = paste(season_value, GAME_ID, GAME_EVENT_ID, sep = "|"),
        game_date_parsed = as.Date(GAME_DATE, format = "%Y%m%d"),
        player_name_normalized = normalize_name(PLAYER_NAME),
        point_value = if_else(SHOT_TYPE == "3PT Field Goal", 3L, 2L),
        field_goal_made = as.integer(SHOT_MADE_FLAG),
        realized_field_goal_points = field_goal_made * point_value
      ) |>
      left_join(taxonomy, by = "ACTION_TYPE", relationship = "many-to-one")
  })
  shots <- bind_rows(shot_list)

  observed_labels <- sort(unique(shots$ACTION_TYPE))
  if (!identical(observed_labels, sort(taxonomy$ACTION_TYPE))) {
    stop("Observed raw labels do not match the frozen taxonomy")
  }

  pbp_list <- map2(seasons, pbp_paths, function(season_value, pbp_path) {
    readRDS(pbp_path) |>
      filter(season_type == 2L) |>
      mutate(
        season_label = season_value,
        source_pbp_sha256 = sha256_file(pbp_path),
        home_team = normalize_team(home_team_abbrev),
        away_team = normalize_team(away_team_abbrev)
      ) |>
      arrange(game_id, game_play_number, sequence_number) |>
      group_by(game_id) |>
      mutate(
        score_home_before_raw = lag(home_score, default = 0L),
        score_away_before_raw = lag(away_score, default = 0L)
      ) |>
      ungroup()
  })
  pbp <- bind_rows(pbp_list)

  shot_games <- shots |>
    distinct(
      season, shot_game_id = GAME_ID, game_date_parsed,
      home_team = HTM, away_team = VTM
    )
  nba_teams <- sort(unique(c(shot_games$home_team, shot_games$away_team)))
  pbp_games <- pbp |>
    filter(home_team %in% nba_teams, away_team %in% nba_teams) |>
    distinct(
      season = season_label, pbp_game_id = game_id,
      game_date_parsed = game_date, home_team, away_team
    )
  game_crosswalk <- inner_join(
    shot_games, pbp_games,
    by = c("season", "game_date_parsed", "home_team", "away_team"),
    relationship = "many-to-many"
  )
  if (anyDuplicated(game_crosswalk$shot_game_id) || anyDuplicated(game_crosswalk$pbp_game_id)) {
    stop("Game crosswalk is not one-to-one")
  }

  same_clock_context <- pbp |>
    filter(game_id %in% game_crosswalk$pbp_game_id) |>
    group_by(game_id, period_number, clock_minutes, clock_seconds) |>
    summarise(
      same_clock_ft_one_of_one = any(str_detect(type_text, "^Free Throw - 1 of 1"), na.rm = TRUE),
      same_clock_shooting_foul = any(type_text == "Shooting Foul", na.rm = TRUE),
      .groups = "drop"
    )

  pbp_field_goals <- pbp |>
    semi_join(game_crosswalk, by = c("game_id" = "pbp_game_id")) |>
    filter(shooting_play %in% TRUE, !str_detect(type_text, "^Free Throw")) |>
    transmute(
      pbp_game_id = game_id,
      PERIOD = as.integer(period_number),
      MINUTES_REMAINING = as.integer(clock_minutes),
      # Preserve fractional provider seconds. Converting them to whole seconds
      # creates false matches against ShotChartDetail's whole-second clock.
      SECONDS_REMAINING = clock_seconds,
      player_name_normalized = normalize_name(athlete_name_1),
      pbp_event_id = as.character(id),
      pbp_event_order = as.integer(game_play_number),
      pbp_sequence_number = as.integer(sequence_number),
      pbp_team_id = as.integer(team_id),
      pbp_home_team_id = as.integer(home_team_id),
      pbp_away_team_id = as.integer(away_team_id),
      pbp_made = as.integer(scoring_play),
      pbp_score_value = as.integer(score_value),
      pbp_type_text = type_text,
      pbp_raw_description = text,
      pbp_distance = suppressWarnings(as.integer(str_match(text, "([0-9]+)-foot")[, 2])),
      pbp_x_raw = coordinate_x_raw,
      pbp_y_raw = coordinate_y_raw,
      score_home_before_raw,
      score_away_before_raw,
      score_home_after_raw = as.integer(home_score),
      score_away_after_raw = as.integer(away_score),
      source_pbp_sha256,
      pbp_point_observed = case_when(
        scoring_play %in% TRUE & score_value %in% c(2L, 3L) ~ as.integer(score_value),
        str_detect(str_to_lower(text), "three point|3-pt") ~ 3L,
        !is.na(pbp_distance) & pbp_distance <= 21L ~ 2L,
        TRUE ~ NA_integer_
      )
    ) |>
    left_join(
      same_clock_context,
      by = c(
        "pbp_game_id" = "game_id", "PERIOD" = "period_number",
        "MINUTES_REMAINING" = "clock_minutes", "SECONDS_REMAINING" = "clock_seconds"
      ),
      relationship = "many-to-one"
    ) |>
    add_count(
      pbp_game_id, PERIOD, MINUTES_REMAINING, SECONDS_REMAINING,
      player_name_normalized, name = "pbp_candidate_count"
    )

  shot_keyed <- shots |>
    left_join(
      game_crosswalk |> select(season, shot_game_id, pbp_game_id),
      by = c("season", "GAME_ID" = "shot_game_id"),
      relationship = "many-to-one"
    ) |>
    add_count(
      pbp_game_id, PERIOD, MINUTES_REMAINING, SECONDS_REMAINING,
      player_name_normalized, name = "shot_clock_player_count"
    )

  candidate_counts <- pbp_field_goals |>
    distinct(
      pbp_game_id, PERIOD, MINUTES_REMAINING, SECONDS_REMAINING,
      player_name_normalized, pbp_candidate_count
    )

  unique_pbp <- pbp_field_goals |>
    filter(pbp_candidate_count == 1L) |>
    select(-pbp_candidate_count)

  canonical <- shot_keyed |>
    left_join(
      candidate_counts,
      by = c(
        "pbp_game_id", "PERIOD", "MINUTES_REMAINING", "SECONDS_REMAINING",
        "player_name_normalized"
      ),
      relationship = "many-to-one"
    ) |>
    mutate(pbp_candidate_count = coalesce(pbp_candidate_count, 0L)) |>
    left_join(
      unique_pbp,
      by = c(
        "pbp_game_id", "PERIOD", "MINUTES_REMAINING", "SECONDS_REMAINING",
        "player_name_normalized"
      ),
      relationship = "many-to-one"
    ) |>
    mutate(
      linkage_status = case_when(
        is.na(pbp_game_id) ~ "unmatched_game",
        pbp_candidate_count == 0L ~ "unmatched_event",
        shot_clock_player_count > 1L | pbp_candidate_count > 1L ~ "ambiguous_candidate",
        TRUE ~ "unique_exact"
      ),
      shooter_side = case_when(
        linkage_status == "unique_exact" & pbp_team_id == pbp_home_team_id ~ "home",
        linkage_status == "unique_exact" & pbp_team_id == pbp_away_team_id ~ "away",
        TRUE ~ NA_character_
      ),
      home_score_delta = score_home_after_raw - score_home_before_raw,
      away_score_delta = score_away_after_raw - score_away_before_raw,
      score_sequence_agrees = case_when(
        linkage_status != "unique_exact" | is.na(shooter_side) ~ NA,
        shooter_side == "home" & field_goal_made == 1L ~
          home_score_delta == point_value & away_score_delta == 0L,
        shooter_side == "away" & field_goal_made == 1L ~
          away_score_delta == point_value & home_score_delta == 0L,
        field_goal_made == 0L ~ home_score_delta == 0L & away_score_delta == 0L,
        TRUE ~ FALSE
      ),
      result_disagreement = linkage_status == "unique_exact" & !is.na(pbp_made) & field_goal_made != pbp_made,
      point_value_disagreement = linkage_status == "unique_exact" & !is.na(pbp_point_observed) & point_value != pbp_point_observed,
      coordinate_comparable = linkage_status == "unique_exact" & is.finite(pbp_x_raw) & is.finite(pbp_y_raw) &
        abs(pbp_x_raw) < 1000 & abs(pbp_y_raw) < 1000,
      coordinate_disagreement = coordinate_comparable & (
        abs(LOC_X - (pbp_x_raw - 25) * 10) > 10 |
          abs(LOC_Y - pbp_y_raw * 10) > 10
      ),
      pre_shot_score_verified = coalesce(score_sequence_agrees, FALSE) &
        !result_disagreement & !point_value_disagreement & !coordinate_disagreement,
      score_home_before = if_else(pre_shot_score_verified, score_home_before_raw, NA_integer_),
      score_away_before = if_else(pre_shot_score_verified, score_away_before_raw, NA_integer_),
      score_margin_before = case_when(
        pre_shot_score_verified & shooter_side == "home" ~ score_home_before - score_away_before,
        pre_shot_score_verified & shooter_side == "away" ~ score_away_before - score_home_before,
        TRUE ~ NA_integer_
      ),
      and_one_candidate = linkage_status == "unique_exact" & field_goal_made == 1L &
        coalesce(same_clock_ft_one_of_one, FALSE) & coalesce(same_clock_shooting_foul, FALSE),
      unusual_description = str_detect(
        coalesce(pbp_type_text, ""), regex("heave|no shot", ignore_case = TRUE)
      ) | str_detect(coalesce(pbp_raw_description, ""), regex("heave|no shot", ignore_case = TRUE)),
      creation_other_unknown = creation_family == "other_or_unknown",
      join_method = join_version,
      schema_version = .env$schema_version,
      taxonomy_version = .env$taxonomy_version,
      m0_exclusion_reason = NA_character_,
      m1_exclusion_reason = NA_character_
    ) |>
    arrange(season, GAME_ID, GAME_EVENT_ID) |>
    transmute(
      schema_version,
      taxonomy_version,
      canonical_shot_key,
      season,
      source_game_id = GAME_ID,
      source_event_id = GAME_EVENT_ID,
      player_id = PLAYER_ID,
      player_name = PLAYER_NAME,
      team_id = TEAM_ID,
      home_team_abbrev = HTM,
      away_team_abbrev = VTM,
      period = PERIOD,
      minutes_remaining = MINUTES_REMAINING,
      seconds_remaining = SECONDS_REMAINING,
      field_goal_made,
      point_value,
      realized_field_goal_points,
      shot_distance_feet = SHOT_DISTANCE,
      location_x_tenths_feet = LOC_X,
      location_y_tenths_feet = LOC_Y,
      raw_action_type = ACTION_TYPE,
      finish_family,
      creation_family,
      creation_other_unknown,
      shooter_home_away = shooter_side,
      score_home_before,
      score_away_before,
      score_margin_before,
      pre_shot_score_verified,
      join_method,
      linkage_status,
      pbp_candidate_count,
      shot_clock_player_count,
      pbp_event_id,
      pbp_event_order,
      pbp_sequence_number,
      pbp_type_text,
      raw_pbp_description = pbp_raw_description,
      pbp_made,
      pbp_point_observed,
      result_disagreement,
      point_value_disagreement,
      coordinate_comparable,
      coordinate_disagreement,
      score_sequence_agrees,
      and_one_candidate,
      unusual_description,
      source_shot_sha256,
      source_pbp_sha256,
      m0_exclusion_reason,
      m1_exclusion_reason
    )

  list(canonical = canonical, game_crosswalk = game_crosswalk)
}

message("Building canonical dataset pass 1")
build_one <- build_canonical()
canonical <- build_one$canonical

message("Building canonical dataset pass 2 for determinism")
build_two <- build_canonical()
if (!identical(canonical, build_two$canonical)) {
  stop("Two clean in-memory canonical builds were not identical")
}
rm(build_two)
gc(verbose = FALSE)

accepted_hashes <- read_csv(accepted_hash_path, show_col_types = FALSE)
accepted_paths <- file.path(repo_root, accepted_hashes$path)
if (!all(file.exists(accepted_paths))) {
  stop("An accepted v0.1.2 artifact is missing")
}
accepted_hashes$observed_sha256 <- map_chr(accepted_paths, sha256_file)
if (any(accepted_hashes$sha256 != accepted_hashes$observed_sha256)) {
  stop("An accepted v0.1.2 artifact hash changed")
}

accepted_canonical_path <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  schema_version, "canonical_shots.parquet"
)
accepted_training <- read_parquet(accepted_canonical_path, as_data_frame = TRUE)
rebuilt_training <- canonical |>
  filter(season %in% training_seasons) |>
  arrange(season, source_game_id, source_event_id)
accepted_training <- accepted_training |>
  arrange(season, source_game_id, source_event_id)
training_rows_identical <- identical(rebuilt_training, accepted_training)
if (!training_rows_identical) {
  stop("Generalized pipeline did not exactly reproduce accepted training rows")
}

training_reproduction <- tibble(
  check = c(
    "accepted_artifact_hashes", "accepted_training_rows",
    "accepted_training_row_count", "accepted_canonical_hash"
  ),
  status = "pass",
  measured_value = c(
    paste0(nrow(accepted_hashes), " frozen artifact hashes matched"),
    "all columns, types, values, and deterministic row order identical",
    as.character(nrow(rebuilt_training)),
    sha256_file(accepted_canonical_path)
  ),
  required_value = c(
    "all registered hashes match", "identical", "433942",
    "292eba28ce0a37788945312169c0986c60bc9db5c6308d322bf5f8e073b2ded7"
  )
)

source_coverage <- canonical |>
  group_by(season) |>
  summarise(
    games = n_distinct(source_game_id),
    shots = n(),
    players = n_distinct(player_id),
    two_point_attempts = sum(point_value == 2L),
    three_point_attempts = sum(point_value == 3L),
    raw_action_labels = n_distinct(raw_action_type),
    .groups = "drop"
  ) |>
  mutate(expected_games = 1230L, expected_shots = unname(.env$expected_shots[season]))

raw_label_coverage <- canonical |>
  count(season, raw_action_type, finish_family, creation_family, name = "shots") |>
  group_by(season) |>
  mutate(share = shots / sum(shots)) |>
  ungroup() |>
  arrange(season, raw_action_type)

taxonomy_coverage <- bind_rows(
  canonical |> count(season, dimension = "finish", family = finish_family, name = "shots"),
  canonical |> count(season, dimension = "creation", family = creation_family, name = "shots")
) |>
  group_by(season, dimension) |>
  mutate(share = shots / sum(shots)) |>
  ungroup() |>
  arrange(season, dimension, family)

predictor_fields <- c(
  "point_value", "finish_family", "creation_family", "period",
  "minutes_remaining", "seconds_remaining", "shot_distance_feet",
  "location_x_tenths_feet", "location_y_tenths_feet",
  "shooter_home_away", "score_margin_before"
)
predictor_missingness <- map_dfr(seasons, function(season_value) {
  season_data <- canonical |> filter(season == season_value)
  map_dfr(predictor_fields, function(field) {
    tibble(
      season = season_value,
      field = field,
      rows = nrow(season_data),
      missing_rows = sum(is.na(season_data[[field]])),
      missing_share = mean(is.na(season_data[[field]]))
    )
  })
}) |>
  arrange(season, field)

source_drift <- canonical |>
  group_by(season) |>
  summarise(
    schema_version_matches = all(schema_version == .env$schema_version),
    taxonomy_version_matches = all(taxonomy_version == .env$taxonomy_version),
    join_version_matches = all(join_method == .env$join_version),
    frozen_raw_label_set_matches = setequal(unique(raw_action_type), taxonomy$ACTION_TYPE),
    finish_levels_match = setequal(unique(finish_family), c(
      "dunk", "layup", "floater", "hook", "regular_jumper",
      "fadeaway_or_turnaround", "step_back"
    )),
    creation_levels_match = setequal(unique(creation_family), c(
      "drive_cut_or_roll", "pull_up_or_self_created", "putback", "other_or_unknown"
    )),
    .groups = "drop"
  ) |>
  mutate(status = if_else(
    schema_version_matches & taxonomy_version_matches & join_version_matches &
      frozen_raw_label_set_matches & finish_levels_match & creation_levels_match,
    "pass", "fail"
  ))

validation_seal <- tibble(
  season = seasons,
  mechanical_canonicalization_access = TRUE,
  analytical_outcome_access = FALSE,
  model_fit_outcome_access = FALSE,
  prediction_outcome_access = FALSE,
  performance_metric_access = FALSE,
  access_note = if_else(
    season %in% training_seasons,
    "outcomes may be used only by the separately committed training preflight",
    "outcomes preserved mechanically; no analytical use authorized"
  )
)

join_quality <- canonical |>
  count(season, linkage_status, name = "shots") |>
  group_by(season) |>
  mutate(share = shots / sum(shots)) |>
  ungroup() |>
  arrange(season, linkage_status)

reconciliation <- canonical |>
  group_by(season) |>
  summarise(
    unique_matches = sum(linkage_status == "unique_exact"),
    ambiguous_matches = sum(linkage_status == "ambiguous_candidate"),
    unmatched_events = sum(linkage_status == "unmatched_event"),
    unmatched_games = sum(linkage_status == "unmatched_game"),
    duplicate_candidate_matches = sum(pbp_candidate_count > 1L | shot_clock_player_count > 1L),
    result_comparable = sum(linkage_status == "unique_exact" & !is.na(pbp_made)),
    result_disagreements = sum(result_disagreement, na.rm = TRUE),
    point_value_comparable = sum(linkage_status == "unique_exact" & !is.na(pbp_point_observed)),
    point_value_disagreements = sum(point_value_disagreement, na.rm = TRUE),
    coordinate_comparable = sum(coordinate_comparable),
    coordinate_disagreements_over_one_foot = sum(coordinate_disagreement, na.rm = TRUE),
    .groups = "drop"
  )

pre_shot_context <- canonical |>
  group_by(season) |>
  summarise(
    unique_matches = sum(linkage_status == "unique_exact"),
    shooter_side_identified = sum(linkage_status == "unique_exact" & !is.na(shooter_home_away)),
    score_sequence_comparable = sum(!is.na(score_sequence_agrees)),
    score_sequence_agreements = sum(score_sequence_agrees, na.rm = TRUE),
    score_sequence_disagreements = sum(score_sequence_agrees %in% FALSE, na.rm = TRUE),
    verified_pre_shot_score_rows = sum(pre_shot_score_verified),
    verified_pre_shot_score_share_all_shots = mean(pre_shot_score_verified),
    and_one_candidates = sum(and_one_candidate),
    .groups = "drop"
  )

leakage_register <- tribble(
  ~field, ~classification, ~first_model_use, ~control,
  "season", "approved pre-shot predictor", "candidate after M1", "source season fixed before the attempt",
  "period", "approved pre-shot predictor", "candidate after M1", "ShotChartDetail clock field",
  "minutes_remaining", "approved pre-shot predictor", "candidate after M1", "ShotChartDetail clock field",
  "seconds_remaining", "approved pre-shot predictor", "candidate after M1", "ShotChartDetail clock field",
  "shooter_home_away", "approved pre-shot predictor when matched", "candidate after M1", "derived only from the matched event team",
  "score_margin_before", "approved pre-shot predictor when verified", "candidate after M1", "lagged event score retained only when the scoring delta agrees",
  "point_value", "approved pre-shot predictor", "M0", "known from the attempt definition",
  "shot_distance_feet", "approved pre-shot predictor", "candidate after M1", "raw attempt geometry",
  "location_x_tenths_feet", "approved pre-shot predictor", "candidate after M1", "raw attempt geometry",
  "location_y_tenths_feet", "approved pre-shot predictor", "candidate after M1", "raw attempt geometry",
  "raw_action_type", "ambiguous timing; audit only", "none", "preserved for taxonomy review; models use frozen families",
  "finish_family", "approved pre-shot shot descriptor", "M0", "versioned mapping from the attempt label",
  "creation_family", "approved only for explicit cues", "M1", "other/unknown remains a model category when no cue exists",
  "field_goal_made", "outcome", "target only", "excluded from predictor allow-lists",
  "realized_field_goal_points", "outcome", "target only", "excluded from predictor allow-lists",
  "raw_pbp_description", "post-shot leakage", "none", "local audit only; may contain result and assist",
  "pbp_made", "post-shot leakage", "none", "cross-provider audit only",
  "pbp_point_observed", "post-shot leakage", "none", "cross-provider audit only",
  "score_home_after_raw", "post-shot leakage", "none", "never written to canonical predictor fields",
  "score_away_after_raw", "post-shot leakage", "none", "never written to canonical predictor fields",
  "subsequent_free_throws", "post-shot leakage", "M5 target construction only", "not attached in this dataset",
  "rebound_result", "post-shot leakage", "none", "not stored",
  "final_game_outcome", "post-shot leakage", "none", "not stored",
  "player_id", "identifier or audit-only field", "M4 at earliest", "not an M0-M3 Opportunity Quality predictor",
  "player_name", "identifier or audit-only field", "none", "local audit only",
  "source_game_id", "identifier or audit-only field", "split key only", "local and ignored",
  "source_event_id", "identifier or audit-only field", "none", "local and ignored",
  "raw_pbp_description_for_prediction", "unavailable", "none", "no leakage-safe parsed context approved",
  "shot_clock_remaining", "unavailable", "none", "no verified same-attempt source",
  "defender_distance", "unavailable", "none", "no verified same-attempt source",
  "lineup", "unavailable", "none", "not constructed in this stage",
  "transition_flag", "unavailable", "none", "running wording is insufficient evidence"
)

schema <- tribble(
  ~field, ~type, ~role, ~required, ~public, ~definition,
  "schema_version", "character", "provenance", TRUE, FALSE, "field-goal canonical schema version",
  "taxonomy_version", "character", "provenance", TRUE, FALSE, "taxonomy mapping version",
  "canonical_shot_key", "character", "stable internal key", TRUE, FALSE, "season plus provider game and event key; local only",
  "season", "character", "pre-shot context", TRUE, FALSE, "NBA season label",
  "source_game_id", "character", "audit identifier", TRUE, FALSE, "raw ShotChartDetail game ID",
  "source_event_id", "integer", "audit identifier", TRUE, FALSE, "raw ShotChartDetail event ID",
  "player_id", "integer", "identity", TRUE, FALSE, "raw player identifier",
  "player_name", "character", "identity", TRUE, FALSE, "raw player name",
  "team_id", "integer", "identity", TRUE, FALSE, "raw shooting-team identifier",
  "home_team_abbrev", "character", "audit context", TRUE, FALSE, "raw home-team abbreviation",
  "away_team_abbrev", "character", "audit context", TRUE, FALSE, "raw away-team abbreviation",
  "period", "integer", "pre-shot context", TRUE, FALSE, "period containing the attempt",
  "minutes_remaining", "integer", "pre-shot context", TRUE, FALSE, "whole clock minutes before the attempt",
  "seconds_remaining", "integer", "pre-shot context", TRUE, FALSE, "clock seconds before the attempt",
  "field_goal_made", "integer", "outcome", TRUE, FALSE, "one for made field goal and zero for miss",
  "point_value", "integer", "shot definition", TRUE, FALSE, "two or three points",
  "realized_field_goal_points", "integer", "outcome", TRUE, FALSE, "zero for a miss; two or three for a make",
  "shot_distance_feet", "integer", "pre-shot geometry", TRUE, FALSE, "ShotChartDetail distance",
  "location_x_tenths_feet", "integer", "pre-shot geometry", TRUE, FALSE, "ShotChartDetail x coordinate",
  "location_y_tenths_feet", "integer", "pre-shot geometry", TRUE, FALSE, "ShotChartDetail y coordinate",
  "raw_action_type", "character", "raw taxonomy", TRUE, FALSE, "unmodified ShotChartDetail action label",
  "finish_family", "character", "derived taxonomy", TRUE, FALSE, "seven-family provisional finish mapping",
  "creation_family", "character", "derived taxonomy", TRUE, FALSE, "explicit-cue creation mapping with other/unknown",
  "creation_other_unknown", "logical", "taxonomy quality", TRUE, FALSE, "true when no explicit supported creation cue exists",
  "shooter_home_away", "character", "pre-shot context", FALSE, FALSE, "matched event team side",
  "score_home_before", "integer", "pre-shot context", FALSE, FALSE, "score before the event after sequence verification",
  "score_away_before", "integer", "pre-shot context", FALSE, FALSE, "score before the event after sequence verification",
  "score_margin_before", "integer", "pre-shot context", FALSE, FALSE, "shooter-relative margin before the event",
  "pre_shot_score_verified", "logical", "context quality", TRUE, FALSE, "score delta independently agrees with the matched attempt",
  "join_method", "character", "linkage provenance", TRUE, FALSE, "versioned game and event join rule",
  "linkage_status", "character", "linkage quality", TRUE, FALSE, "unique exact, ambiguous, or unmatched",
  "pbp_candidate_count", "integer", "linkage quality", TRUE, FALSE, "play-by-play candidates on the match key",
  "shot_clock_player_count", "integer", "linkage quality", TRUE, FALSE, "shot-chart rows on the match key",
  "pbp_event_id", "character", "audit identifier", FALSE, FALSE, "matched play-by-play event ID",
  "pbp_event_order", "integer", "audit ordering", FALSE, FALSE, "matched play-by-play order",
  "pbp_sequence_number", "integer", "audit ordering", FALSE, FALSE, "matched provider sequence number",
  "pbp_type_text", "character", "raw audit taxonomy", FALSE, FALSE, "matched play-by-play type",
  "raw_pbp_description", "character", "post-shot audit", FALSE, FALSE, "matched raw description; forbidden as predictor",
  "pbp_made", "integer", "cross-source audit", FALSE, FALSE, "matched play-by-play result",
  "pbp_point_observed", "integer", "cross-source audit", FALSE, FALSE, "auditable point value when observable",
  "result_disagreement", "logical", "quality", TRUE, FALSE, "providers disagree on make or miss",
  "point_value_disagreement", "logical", "quality", TRUE, FALSE, "providers disagree on observed point value",
  "coordinate_comparable", "logical", "quality", TRUE, FALSE, "play-by-play coordinates support comparison",
  "coordinate_disagreement", "logical", "quality", TRUE, FALSE, "either transformed coordinate differs by more than one foot",
  "score_sequence_agrees", "logical", "quality", FALSE, FALSE, "score change equals the shot outcome and value",
  "and_one_candidate", "logical", "M5 audit flag", TRUE, FALSE, "same-clock made shot, shooting foul, and one free throw",
  "unusual_description", "logical", "manual-review flag", TRUE, FALSE, "heave or no-shot wording",
  "source_shot_sha256", "character", "provenance", TRUE, FALSE, "source shot-file hash",
  "source_pbp_sha256", "character", "provenance", FALSE, FALSE, "source play-by-play hash for a unique match",
  "m0_exclusion_reason", "character", "eligibility", FALSE, FALSE, "null because all canonical rows support M0",
  "m1_exclusion_reason", "character", "eligibility", FALSE, FALSE, "null because other/unknown remains valid for M1"
)

rare_labels <- canonical |>
  count(raw_action_type, name = "label_shots") |>
  filter(label_shots < 500L) |>
  pull(raw_action_type)

review_strata <- list(
  two_point = canonical |> filter(point_value == 2L),
  three_point = canonical |> filter(point_value == 3L),
  finish_dunk = canonical |> filter(finish_family == "dunk"),
  finish_layup = canonical |> filter(finish_family == "layup"),
  finish_floater = canonical |> filter(finish_family == "floater"),
  finish_hook = canonical |> filter(finish_family == "hook"),
  finish_regular_jumper = canonical |> filter(finish_family == "regular_jumper"),
  finish_fadeaway_turnaround = canonical |> filter(finish_family == "fadeaway_or_turnaround"),
  finish_step_back = canonical |> filter(finish_family == "step_back"),
  creation_drive_cut_roll = canonical |> filter(creation_family == "drive_cut_or_roll"),
  creation_pull_up_self_created = canonical |> filter(creation_family == "pull_up_or_self_created"),
  creation_putback = canonical |> filter(creation_family == "putback"),
  creation_other_unknown = canonical |> filter(creation_family == "other_or_unknown"),
  rare_raw_labels = canonical |> filter(raw_action_type %in% rare_labels),
  ambiguous_join = canonical |> filter(linkage_status == "ambiguous_candidate"),
  unmatched_event = canonical |> filter(linkage_status == "unmatched_event"),
  close_clock_collision = canonical |> filter(pbp_candidate_count > 1L | shot_clock_player_count > 1L),
  and_one_candidate = canonical |> filter(and_one_candidate),
  heave_or_unusual_description = canonical |> filter(unusual_description),
  coordinate_disagreement = canonical |> filter(coordinate_disagreement),
  point_value_disagreement = canonical |> filter(point_value_disagreement)
)

for (season_value in seasons) {
  review_strata[[paste0("season_", str_replace_all(season_value, "-", "_"))]] <-
    canonical |> filter(season == season_value)
}

review_population <- imap_dfr(review_strata, function(data, stratum) {
  tibble(review_stratum = stratum, population_rows = nrow(data))
})

private_review_sample <- imap_dfr(review_strata, function(data, stratum) {
  data |>
    arrange(canonical_shot_key) |>
    slice_head(n = 8L) |>
    mutate(review_stratum = stratum, .before = 1L)
}) |>
  select(
    review_stratum, canonical_shot_key, season, source_game_id, source_event_id,
    player_id, player_name, field_goal_made, point_value, period,
    minutes_remaining, seconds_remaining, raw_action_type, finish_family,
    creation_family, linkage_status, pbp_candidate_count, shot_clock_player_count,
    pbp_type_text, raw_pbp_description, result_disagreement,
    point_value_disagreement, coordinate_disagreement, score_sequence_agrees,
    and_one_candidate, unusual_description
  )

review_design <- review_population |>
  left_join(
    private_review_sample |> count(review_stratum, name = "selected_rows"),
    by = "review_stratum",
    relationship = "one-to-one"
  ) |>
  mutate(selected_rows = coalesce(selected_rows, 0L))

feature_allow_list <- c(
  "season", "period", "minutes_remaining", "seconds_remaining",
  "shooter_home_away", "score_margin_before", "point_value",
  "shot_distance_feet", "location_x_tenths_feet", "location_y_tenths_feet",
  "finish_family", "creation_family"
)
prohibited_predictors <- c(
  "field_goal_made", "realized_field_goal_points", "raw_pbp_description",
  "pbp_made", "pbp_point_observed", "subsequent_free_throws",
  "rebound_result", "final_game_outcome"
)

checks <- tibble(
  check = c(
    "exact_approved_season_scope", "expected_games", "expected_shots",
    "unique_canonical_keys", "no_duplicate_source_shots", "valid_make_values",
    "valid_point_values", "valid_realized_points", "valid_distance",
    "valid_coordinates", "valid_clock", "valid_period", "raw_labels_complete",
    "finish_mapping_complete", "creation_mapping_complete",
    "honest_creation_unknown", "taxonomy_stable", "deterministic_canonical_build",
    "no_predictor_leakage", "only_approved_seasons", "no_2026_27_access",
    "audited_exact_join_counts", "all_rows_m0_eligible", "all_rows_m1_eligible"
  ),
  status = c(
    if_else(identical(sort(unique(canonical$season)), sort(seasons)), "pass", "fail"),
    if_else(all(source_coverage$games == 1230L), "pass", "fail"),
    if_else(all(source_coverage$shots == source_coverage$expected_shots), "pass", "fail"),
    if_else(anyDuplicated(canonical$canonical_shot_key) == 0L, "pass", "fail"),
    if_else(anyDuplicated(paste(canonical$season, canonical$source_game_id, canonical$source_event_id)) == 0L, "pass", "fail"),
    if_else(all(canonical$field_goal_made %in% 0:1), "pass", "fail"),
    if_else(all(canonical$point_value %in% c(2L, 3L)), "pass", "fail"),
    if_else(all(canonical$realized_field_goal_points %in% c(0L, 2L, 3L)), "pass", "fail"),
    if_else(all(canonical$shot_distance_feet >= 0L & canonical$shot_distance_feet <= 100L), "pass", "fail"),
    if_else(all(canonical$location_x_tenths_feet >= -250L & canonical$location_x_tenths_feet <= 250L & canonical$location_y_tenths_feet >= -60L & canonical$location_y_tenths_feet <= 900L), "pass", "fail"),
    if_else(all(canonical$minutes_remaining %in% 0:12 & canonical$seconds_remaining %in% 0:59), "pass", "fail"),
    if_else(all(canonical$period %in% 1:10), "pass", "fail"),
    if_else(all(!is.na(canonical$raw_action_type) & canonical$raw_action_type != ""), "pass", "fail"),
    if_else(all(!is.na(canonical$finish_family)), "pass", "fail"),
    if_else(all(!is.na(canonical$creation_family)), "pass", "fail"),
    if_else(all(canonical$creation_other_unknown == (canonical$creation_family == "other_or_unknown")), "pass", "fail"),
    "pass",
    "pass",
    if_else(length(intersect(feature_allow_list, prohibited_predictors)) == 0L, "pass", "fail"),
    if_else(all(canonical$season %in% extended_seasons), "pass", "fail"),
    if_else(!any(input_manifest$contains_2026_27), "pass", "fail"),
    if_else(
      all(
        reconciliation$unique_matches[reconciliation$season %in% training_seasons] ==
          unname(.env$expected_unique_matches[reconciliation$season[reconciliation$season %in% training_seasons]])
      ) && all(
        reconciliation$unique_matches + reconciliation$ambiguous_matches +
          reconciliation$unmatched_events + reconciliation$unmatched_games == source_coverage$shots
      ),
      "pass", "fail"
    ),
    if_else(all(is.na(canonical$m0_exclusion_reason)), "pass", "fail"),
    if_else(all(is.na(canonical$m1_exclusion_reason)), "pass", "fail")
  ),
  measured_value = c(
    paste(sort(unique(canonical$season)), collapse = ";"),
    paste(source_coverage$games, collapse = ";"),
    paste(source_coverage$shots, collapse = ";"),
    as.character(n_distinct(canonical$canonical_shot_key)),
    as.character(sum(duplicated(paste(canonical$season, canonical$source_game_id, canonical$source_event_id)))),
    paste(sort(unique(canonical$field_goal_made)), collapse = ";"),
    paste(sort(unique(canonical$point_value)), collapse = ";"),
    paste(sort(unique(canonical$realized_field_goal_points)), collapse = ";"),
    paste(range(canonical$shot_distance_feet), collapse = ";"),
    paste(range(canonical$location_x_tenths_feet), collapse = ";"),
    paste(range(canonical$minutes_remaining), range(canonical$seconds_remaining), collapse = ";"),
    paste(range(canonical$period), collapse = ";"),
    as.character(sum(is.na(canonical$raw_action_type) | canonical$raw_action_type == "")),
    as.character(sum(is.na(canonical$finish_family))),
    as.character(sum(is.na(canonical$creation_family))),
    as.character(mean(canonical$creation_other_unknown)),
    sha256_file(taxonomy_path),
    "two in-memory builds were identical",
    paste(intersect(feature_allow_list, prohibited_predictors), collapse = ";"),
    paste(sort(unique(canonical$season)), collapse = ";"),
    paste(input_manifest$file, collapse = ";"),
    paste(reconciliation$unique_matches, collapse = ";"),
    as.character(sum(is.na(canonical$m0_exclusion_reason))),
    as.character(sum(is.na(canonical$m1_exclusion_reason)))
  ),
  required_value = c(
    paste(seasons, collapse = ";"), "1230 each", paste(unname(expected_shots[seasons]), collapse = ";"),
    as.character(sum(expected_shots[seasons])), "0",
    "0;1", "2;3", "0;2;3", "0 to 100 feet", "court bounds",
    "minutes 0-12 and seconds 0-59", "1-10", "0 missing", "0 missing",
    "0 missing", "indicator matches category", "frozen mapping hash",
    "identical", "empty intersection", "only approved seasons", "no 2026-27 source",
    "accepted training counts exact and every source row has one join status",
    as.character(sum(expected_shots[seasons])), as.character(sum(expected_shots[seasons]))
  )
)

if (any(checks$status == "fail")) {
  print(checks |> filter(status == "fail"))
  stop("One or more canonical data checks failed")
}

exclusions <- tibble(
  stage = c("canonical_dataset", "M0", "M1", "verified_pre_shot_score"),
  included_rows = c(nrow(canonical), nrow(canonical), nrow(canonical), sum(canonical$pre_shot_score_verified)),
  excluded_rows = c(0L, 0L, 0L, sum(!canonical$pre_shot_score_verified)),
  reason = c(
    "none; ambiguous and unmatched joins remain with quality flags",
    "none; field-goal outcome, point value, and finish are complete",
    "none; other/unknown is a valid creation category",
    "no unique independently score-consistent play-by-play match"
  )
)

readiness <- tibble(
  model_stage = c("M0", "M1"),
  decision = c("go", "go"),
  basis = c(
    "Complete field-goal outcome, point value, and seven-family finish mapping for both seasons; play-by-play enrichment is not required.",
    "Complete finish mapping and conservative creation mapping; other/unknown is retained rather than inferred."
  ),
  limitation = c(
    "Expected field-goal points omit free throws and M0 does not use richer context.",
    "Creation remains partial and cannot identify spot-up, transition, or post attempts."
  )
)

package_versions <- tibble(
  package = c("R", "arrow", "dplyr", "purrr", "readr", "stringr", "tidyr"),
  version = c(
    paste(R.version$major, R.version$minor, sep = "."),
    map_chr(c("arrow", "dplyr", "purrr", "readr", "stringr", "tidyr"),
            ~ as.character(packageVersion(.x)))
  )
)

build_summary <- tibble(
  schema_version = schema_version,
  taxonomy_version = taxonomy_version,
  join_version = join_version,
  seasons = paste(seasons, collapse = ";"),
  games = n_distinct(canonical$source_game_id),
  shots = nrow(canonical),
  players = n_distinct(canonical$player_id),
  unique_matches = sum(canonical$linkage_status == "unique_exact"),
  creation_other_unknown = sum(canonical$creation_other_unknown),
  creation_other_unknown_share = mean(canonical$creation_other_unknown),
  m0_readiness = readiness$decision[readiness$model_stage == "M0"],
  m1_readiness = readiness$decision[readiness$model_stage == "M1"],
  model_fits_created = 0L,
  public_shot_rows_created = 0L
)

tables <- list(
  build_summary.csv = build_summary,
  canonical_schema.csv = schema,
  data_quality_checks.csv = checks,
  exclusions.csv = exclusions,
  input_manifest.csv = input_manifest,
  join_quality.csv = join_quality,
  leakage_register.csv = leakage_register,
  manual_review_design.csv = review_design,
  package_versions.csv = package_versions,
  pre_shot_context_verification.csv = pre_shot_context,
  predictor_missingness.csv = predictor_missingness,
  raw_label_coverage_by_season.csv = raw_label_coverage,
  readiness.csv = readiness,
  reconciliation_disagreements.csv = reconciliation,
  source_drift.csv = source_drift,
  source_coverage.csv = source_coverage,
  taxonomy_coverage_by_season.csv = taxonomy_coverage,
  training_reproduction.csv = training_reproduction,
  validation_seal_audit.csv = validation_seal,
  taxonomy_mapping.csv = taxonomy |>
    mutate(taxonomy_version = .env$taxonomy_version, .before = 1L)
)

write_aggregate_bundle <- function(directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  walk2(tables, names(tables), ~ write_csv_stable(.x, file.path(directory, .y)))
}

attempt_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
aggregate_a <- file.path(tracked_parent, paste0(".context-canonical-a-", attempt_id))
aggregate_b <- file.path(tracked_parent, paste0(".context-canonical-b-", attempt_id))
write_aggregate_bundle(aggregate_a)
write_aggregate_bundle(aggregate_b)

base_files <- sort(names(tables))
hashes_a <- map_chr(file.path(aggregate_a, base_files), sha256_file)
hashes_b <- map_chr(file.path(aggregate_b, base_files), sha256_file)
if (!identical(hashes_a, hashes_b)) stop("Two aggregate serializations were not byte-identical")

determinism <- tibble(
  check = c("two_clean_canonical_builds", "two_aggregate_serializations", "stable_taxonomy_mapping"),
  status = "pass",
  measured_value = c(
    "all canonical columns and rows identical in memory",
    paste0(length(base_files), " aggregate files byte-identical"),
    sha256_file(taxonomy_path)
  )
)
write_csv_stable(determinism, file.path(aggregate_a, "determinism_verification.csv"))
write_csv_stable(determinism, file.path(aggregate_b, "determinism_verification.csv"))

manifest_files <- sort(c(base_files, "determinism_verification.csv"))
make_manifest <- function(directory) {
  tibble(
    file = manifest_files,
    bytes = file.info(file.path(directory, manifest_files))$size,
    sha256 = map_chr(file.path(directory, manifest_files), sha256_file),
    contains_shot_level_rows = FALSE,
    declarative_or_aggregate = TRUE
  )
}
write_csv_stable(make_manifest(aggregate_a), file.path(aggregate_a, "aggregate_output_manifest.csv"))
write_csv_stable(make_manifest(aggregate_b), file.path(aggregate_b, "aggregate_output_manifest.csv"))

all_aggregate_files <- sort(c(manifest_files, "aggregate_output_manifest.csv"))
if (!identical(
  map_chr(file.path(aggregate_a, all_aggregate_files), sha256_file),
  map_chr(file.path(aggregate_b, all_aggregate_files), sha256_file)
)) stop("Completed aggregate bundles were not byte-identical")

canonical_stage <- file.path(cache_parent, paste0(".", schema_version, ".", attempt_id, ".partial"))
dir.create(canonical_stage, recursive = TRUE, showWarnings = FALSE)
canonical_path <- file.path(canonical_stage, "canonical_shots.parquet")
review_path <- file.path(canonical_stage, "manual_review_sample_private.csv")
write_parquet(canonical, canonical_path, compression = "zstd")
partition_paths <- character()
if (build_scope == "five_season_extension") {
  partition_paths <- map_chr(seasons, function(season_value) {
    partition_dir <- file.path(canonical_stage, paste0("season=", season_value))
    dir.create(partition_dir, recursive = TRUE, showWarnings = FALSE)
    partition_path <- file.path(partition_dir, "canonical_shots.parquet")
    write_parquet(
      canonical |> filter(season == season_value),
      partition_path,
      compression = "zstd"
    )
    partition_path
  })
}
write_csv_stable(private_review_sample, review_path)

completion_manifest <- tibble(
  artifact = c(
    "canonical_shots.parquet",
    if (build_scope == "five_season_extension") {
      file.path(paste0("season=", seasons), "canonical_shots.parquet")
    } else {
      character()
    },
    "manual_review_sample_private.csv"
  ),
  rows = c(
    nrow(canonical),
    if (build_scope == "five_season_extension") unname(expected_shots[seasons]) else integer(),
    nrow(private_review_sample)
  ),
  bytes = file.info(c(canonical_path, partition_paths, review_path))$size,
  sha256 = map_chr(c(canonical_path, partition_paths, review_path), sha256_file),
  schema_version = schema_version,
  taxonomy_version = taxonomy_version,
  join_version = join_version,
  build_scope = build_scope,
  input_hashes = paste(input_manifest$sha256, collapse = ";"),
  training_rows_identical_to_accepted = training_rows_identical,
  validation_outcomes_analytically_accessed = FALSE,
  checks_passed = TRUE,
  atomic_complete = TRUE
)
write_csv_stable(completion_manifest, file.path(canonical_stage, "completion_manifest.csv"))

if (!file.rename(canonical_stage, canonical_dir)) stop("Atomic canonical publication failed")
if (!file.rename(aggregate_a, tracked_dir)) stop("Atomic aggregate publication failed")

unlink(lock_dir, recursive = TRUE)
if (dir.exists(lock_dir)) stop("Completed build could not clear its versioned lock")
message("Canonical dataset published to ignored path: ", canonical_dir)
message("Aggregate audit bundle published to tracked path: ", tracked_dir)
message("Second aggregate bundle retained for byte comparison at: ", aggregate_b)
