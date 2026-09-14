#!/usr/bin/env Rscript

# Audit-only feasibility pipeline for NBA Shot Selection: Context Edition.
# This script produces aggregate diagnostics. It does not fit a model or emit
# shot-level records.

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

seasons <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
pbp_years <- setNames(2022:2026, seasons)
shot_paths <- file.path(repo_root, "data", "raw", "shots", paste0("season=", seasons), "shots.parquet")
pbp_paths <- file.path(repo_root, "data", "cache", "context_edition_audit", paste0("play_by_play_", pbp_years, ".rds"))
output_dir <- file.path(repo_root, "data", "processed", "context_edition_audit")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

stopifnot(all(file.exists(shot_paths)))
stopifnot(all(file.exists(pbp_paths)))

write_atomic_csv <- function(data, name) {
  target <- file.path(output_dir, name)
  temporary <- tempfile(pattern = paste0(name, "."), tmpdir = output_dir)
  readr::write_csv(data, temporary, na = "")
  if (!file.rename(temporary, target)) stop("Atomic write failed for ", target)
  invisible(target)
}

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  sub(" .*", "", value[[1]])
}

safe_spearman <- function(x, y) {
  if (length(unique(x[is.finite(x)])) < 2L || length(unique(y[is.finite(y)])) < 2L) return(NA_real_)
  cor(x, y, method = "spearman", use = "complete.obs")
}

normalize_team <- function(x) {
  dplyr::recode(x, GS = "GSW", NO = "NOP", NY = "NYK", SA = "SAS", UTAH = "UTA", WSH = "WAS", .default = x)
}

normalize_name <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]", "") |>
    str_replace("(jr|sr|ii|iii|iv)$", "")
}

creation_family <- function(action_type) {
  case_when(
    str_detect(action_type, regex("putback|tip", ignore_case = TRUE)) ~ "putback",
    str_detect(action_type, regex("cutting|alley oop", ignore_case = TRUE)) ~ "drive_cut_or_roll",
    str_detect(action_type, regex("driving", ignore_case = TRUE)) ~ "drive_cut_or_roll",
    str_detect(action_type, regex("pullup|pull-up|step back", ignore_case = TRUE)) ~ "pull_up_or_self_created",
    TRUE ~ "other_or_unknown"
  )
}

finish_family <- function(action_type) {
  case_when(
    str_detect(action_type, regex("dunk", ignore_case = TRUE)) ~ "dunk",
    str_detect(action_type, regex("float", ignore_case = TRUE)) ~ "floater",
    str_detect(action_type, regex("hook", ignore_case = TRUE)) ~ "hook",
    str_detect(action_type, regex("layup|finger roll|tip", ignore_case = TRUE)) ~ "layup",
    str_detect(action_type, regex("step back", ignore_case = TRUE)) ~ "step_back",
    str_detect(action_type, regex("fadeaway|turnaround", ignore_case = TRUE)) ~ "fadeaway_or_turnaround",
    str_detect(action_type, regex("jump|bank", ignore_case = TRUE)) ~ "regular_jumper",
    TRUE ~ "other_or_unknown"
  )
}

field_missingness <- list()
coverage <- list()
action_counts <- list()
taxonomy_counts <- list()
player_family <- list()
taxonomy_player_family <- list()
reconciliation <- list()
pbp_coverage <- list()
shot_trip_linkage <- list()
pbp_type_counts <- list()
pbp_qualifier_counts <- list()

for (season in seasons) {
  message("Auditing ", season)
  shots <- read_parquet(shot_paths[match(season, seasons)], as_data_frame = TRUE) |>
    mutate(
      season = season,
      creation_family = creation_family(ACTION_TYPE),
      finish_family = finish_family(ACTION_TYPE),
      point_value = if_else(SHOT_TYPE == "3PT Field Goal", 3L, 2L),
      game_date = as.Date(GAME_DATE, format = "%Y%m%d"),
      player_name_normalized = normalize_name(PLAYER_NAME)
    )
  source_shot_fields <- names(shots)[seq_len(24L)]
  message("  shot-chart aggregates")

  missing_rows <- map_dfr(source_shot_fields, function(field) {
    value <- shots[[field]]
    missing <- is.na(value)
    if (is.character(value)) missing <- missing | trimws(value) == ""
    tibble(
      season = season,
      source = "NBA ShotChartDetail local extract",
      field = field,
      storage_type = paste(class(value), collapse = "/"),
      rows = length(value),
      missing_rows = sum(missing),
      missing_pct = mean(missing)
    )
  })
  field_missingness[[season]] <- missing_rows

  coverage[[season]] <- shots |>
    summarise(
      season = first(season),
      expected_regular_season_games = 1230L,
      retrieved_games = n_distinct(GAME_ID),
      teams = n_distinct(TEAM_ID),
      players = n_distinct(PLAYER_ID),
      player_seasons = n_distinct(paste(season, PLAYER_ID)),
      shot_rows = n(),
      made_shots = sum(SHOT_MADE_FLAG == 1L),
      two_point_attempts = sum(point_value == 2L),
      three_point_attempts = sum(point_value == 3L),
      duplicate_game_event_keys = sum(duplicated(paste(GAME_ID, GAME_EVENT_ID))),
      missing_game_event_keys = sum(is.na(GAME_EVENT_ID)),
      raw_action_labels = n_distinct(ACTION_TYPE),
      unknown_finish_rows = sum(finish_family == "other_or_unknown"),
      unknown_creation_rows = sum(creation_family == "other_or_unknown")
    )

  action_counts[[season]] <- shots |>
    count(season, ACTION_TYPE, creation_family, finish_family, name = "shots") |>
    mutate(share = shots / sum(shots))

  taxonomy_counts[[season]] <- bind_rows(
    shots |> count(season, family = creation_family, name = "shots") |> mutate(dimension = "creation"),
    shots |> count(season, family = finish_family, name = "shots") |> mutate(dimension = "finish")
  ) |>
    group_by(season, dimension) |>
    mutate(share = shots / sum(shots)) |>
    ungroup() |>
    select(season, dimension, family, shots, share)

  player_family[[season]] <- shots |>
    group_by(season, PLAYER_ID, finish_family) |>
    summarise(
      attempts = n(),
      teams = n_distinct(TEAM_ID),
      mean_distance_feet = mean(SHOT_DISTANCE),
      three_point_share = mean(point_value == 3L),
      .groups = "drop"
    )

  taxonomy_player_family[[season]] <- bind_rows(
    shots |> count(season, PLAYER_ID, family = creation_family, name = "attempts") |> mutate(dimension = "creation"),
    shots |> count(season, PLAYER_ID, family = finish_family, name = "attempts") |> mutate(dimension = "finish")
  ) |>
    select(season, dimension, PLAYER_ID, family, attempts)

  pbp <- readRDS(pbp_paths[match(season, seasons)]) |>
    filter(season_type == 2L) |>
    select(
      game_id, season, season_type, game_date,
      home_team_abbrev, away_team_abbrev,
      period_number, clock_display_value, clock_minutes, clock_seconds,
      type_text, text, athlete_id_1, athlete_name_1,
      shooting_play, scoring_play, score_value,
      coordinate_x_raw, coordinate_y_raw
    ) |>
    mutate(
      season_label = .env$season,
      home_team = normalize_team(home_team_abbrev),
      away_team = normalize_team(away_team_abbrev)
    )
  message("  play-by-play loaded")

  pbp_type_counts[[season]] <- pbp |>
    count(season = season_label, type_text, name = "events") |>
    mutate(share = events / sum(events))

  pbp_field_goal_qualifiers <- pbp |>
    filter(shooting_play %in% TRUE, !str_detect(type_text, "^Free Throw"))
  pbp_qualifier_counts[[season]] <- tibble::tribble(
    ~season, ~qualifier, ~events, ~outcome_leakage,
    season, "made_result", sum(pbp_field_goal_qualifiers$scoring_play %in% TRUE), TRUE,
    season, "missed_result", sum(pbp_field_goal_qualifiers$scoring_play %in% FALSE), TRUE,
    season, "assist_named_in_description", sum(str_detect(pbp_field_goal_qualifiers$text, regex("assists", ignore_case = TRUE)), na.rm = TRUE), TRUE,
    season, "three_point_named_in_description", sum(str_detect(pbp_field_goal_qualifiers$text, regex("three point|3-pt", ignore_case = TRUE)), na.rm = TRUE), FALSE,
    season, "distance_named_in_description", sum(str_detect(pbp_field_goal_qualifiers$text, "[0-9]+-foot"), na.rm = TRUE), FALSE,
    season, "heave_label", sum(pbp_field_goal_qualifiers$type_text == "Heave Jump Shot", na.rm = TRUE), FALSE,
    season, "no_shot_default_label", sum(pbp_field_goal_qualifiers$type_text == "No Shot (Default Shot)", na.rm = TRUE), FALSE
  )
  rm(pbp_field_goal_qualifiers)

  nba_teams <- sort(unique(c(shots$HTM, shots$VTM)))
  pbp_games <- pbp |>
    filter(home_team %in% nba_teams, away_team %in% nba_teams) |>
    distinct(pbp_game_id = game_id, game_date, home_team, away_team)
  shot_games <- shots |>
    distinct(shot_game_id = GAME_ID, game_date, home_team = HTM, away_team = VTM)
  game_crosswalk <- inner_join(
    shot_games,
    pbp_games,
    by = c("game_date", "home_team", "away_team"),
    relationship = "many-to-many"
  )
  message("  game crosswalk")

  pbp_coverage[[season]] <- tibble(
    season = season,
    source = "hoopR SportsDataverse ESPN play-by-play release",
    release_year = unname(pbp_years[[season]]),
    cached_sha256 = sha256_file(pbp_paths[match(season, seasons)]),
    regular_season_like_games_in_release = n_distinct(pbp$game_id),
    nba_team_games_in_release = n_distinct(pbp_games$pbp_game_id),
    shot_chart_games = n_distinct(shot_games$shot_game_id),
    crosswalked_games = n_distinct(game_crosswalk$shot_game_id),
    ambiguous_crosswalk_rows = nrow(game_crosswalk) - n_distinct(game_crosswalk$shot_game_id)
  )

  pbp_field_goals <- pbp |>
    semi_join(game_crosswalk, by = c("game_id" = "pbp_game_id")) |>
    filter(shooting_play %in% TRUE, !str_detect(type_text, "^Free Throw")) |>
    transmute(
      pbp_game_id = game_id,
      PERIOD = period_number,
      MINUTES_REMAINING = clock_minutes,
      SECONDS_REMAINING = clock_seconds,
      player_name_normalized = normalize_name(athlete_name_1),
      pbp_made = as.integer(scoring_play),
      pbp_type_text = type_text,
      pbp_text = text,
      pbp_distance = suppressWarnings(as.integer(str_match(text, "([0-9]+)-foot")[, 2])),
      pbp_x_raw = coordinate_x_raw,
      pbp_y_raw = coordinate_y_raw,
      pbp_point_observed = case_when(
        scoring_play %in% TRUE & score_value %in% c(2L, 3L) ~ as.integer(score_value),
        str_detect(str_to_lower(text), "three point|3-pt") ~ 3L,
        !is.na(pbp_distance) & pbp_distance <= 21L ~ 2L,
        TRUE ~ NA_integer_
      )
    ) |>
    add_count(pbp_game_id, PERIOD, MINUTES_REMAINING, SECONDS_REMAINING, player_name_normalized, name = "pbp_key_rows")
  message("  play-by-play field goals")

  shot_match_rows <- shots |>
    inner_join(game_crosswalk |> select(shot_game_id, pbp_game_id), by = c("GAME_ID" = "shot_game_id")) |>
    transmute(
      pbp_game_id,
      PERIOD,
      MINUTES_REMAINING,
      SECONDS_REMAINING,
      player_name_normalized,
      shot_made = SHOT_MADE_FLAG,
      shot_point_value = point_value,
      shot_distance = SHOT_DISTANCE,
      shot_x = LOC_X,
      shot_y = LOC_Y
    ) |>
    add_count(pbp_game_id, PERIOD, MINUTES_REMAINING, SECONDS_REMAINING, player_name_normalized, name = "shot_key_rows")

  matched_shots <- inner_join(
    shot_match_rows,
    pbp_field_goals,
    by = c("pbp_game_id", "PERIOD", "MINUTES_REMAINING", "SECONDS_REMAINING", "player_name_normalized"),
    relationship = "many-to-many"
  ) |>
    filter(shot_key_rows == 1L, pbp_key_rows == 1L)
  message("  cross-source shot matches")

  valid_coordinates <- matched_shots |>
    filter(
      is.finite(pbp_x_raw), is.finite(pbp_y_raw),
      abs(pbp_x_raw) < 1000, abs(pbp_y_raw) < 1000
    )

  reconciliation[[season]] <- tibble(
    season = season,
    crosswalked_games = n_distinct(game_crosswalk$shot_game_id),
    shot_chart_attempts_in_crosswalked_games = nrow(shot_match_rows),
    pbp_field_goal_events_in_crosswalked_games = nrow(pbp_field_goals),
    pbp_heave_events_in_crosswalked_games = sum(pbp_field_goals$pbp_type_text == "Heave Jump Shot", na.rm = TRUE),
    unique_player_clock_matches = nrow(matched_shots),
    unique_match_rate_of_shot_chart = nrow(matched_shots) / nrow(shot_match_rows),
    result_agreement_rate = mean(matched_shots$shot_made == matched_shots$pbp_made),
    point_value_comparable_rows = sum(!is.na(matched_shots$pbp_point_observed)),
    point_value_agreement_rate = mean(
      matched_shots$shot_point_value[!is.na(matched_shots$pbp_point_observed)] ==
        matched_shots$pbp_point_observed[!is.na(matched_shots$pbp_point_observed)]
    ),
    distance_comparable_rows = sum(!is.na(matched_shots$pbp_distance)),
    distance_mean_absolute_error_feet = mean(abs(matched_shots$shot_distance - matched_shots$pbp_distance), na.rm = TRUE),
    coordinate_comparable_rows = nrow(valid_coordinates),
    coordinate_within_one_foot_both_axes_rate = mean(
      abs(valid_coordinates$shot_x - (valid_coordinates$pbp_x_raw - 25) * 10) <= 10 &
        abs(valid_coordinates$shot_y - valid_coordinates$pbp_y_raw * 10) <= 10
    ),
    coordinate_x_mean_absolute_error_tenths_feet = mean(abs(valid_coordinates$shot_x - (valid_coordinates$pbp_x_raw - 25) * 10)),
    coordinate_y_mean_absolute_error_tenths_feet = mean(abs(valid_coordinates$shot_y - valid_coordinates$pbp_y_raw * 10))
  )

  rm(pbp_field_goals, shot_match_rows, matched_shots, valid_coordinates)
  rm(shots)
  gc(verbose = FALSE)
  message("  reconciliation aggregates")

  context_events <- pbp |>
    filter(
      home_team %in% nba_teams,
      away_team %in% nba_teams,
      type_text == "Shooting Foul" |
        str_detect(type_text, regex("Technical|Flagrant|Clear Path|Take Foul|Away from Play", ignore_case = TRUE)) |
        (shooting_play %in% TRUE & scoring_play %in% TRUE & !str_detect(type_text, "^Free Throw"))
    ) |>
    select(game_id, period_number, clock_display_value, type_text, athlete_id_1, shooting_play, scoring_play)

  clock_context <- context_events |>
    group_by(game_id, period_number, clock_display_value) |>
    summarise(
      same_clock_has_shooting_foul = any(type_text == "Shooting Foul"),
      same_clock_has_excluded_foul = any(str_detect(type_text, regex("Technical|Flagrant|Clear Path|Take Foul|Away from Play", ignore_case = TRUE))),
      .groups = "drop"
    )

  made_field_goals <- context_events |>
    filter(shooting_play %in% TRUE, scoring_play %in% TRUE, !str_detect(type_text, "^Free Throw")) |>
    distinct(game_id, period_number, clock_display_value, athlete_id_1) |>
    mutate(same_clock_made_fg_by_shooter = TRUE)
  message("  shot-trip clock context")

  first_free_throws <- pbp |>
    filter(
      home_team %in% nba_teams,
      away_team %in% nba_teams,
      str_detect(type_text, "^Free Throw - (1 of [123]|Technical|Flagrant|Clear Path)")
    ) |>
    select(game_id, period_number, clock_display_value, type_text, athlete_id_1, season_label) |>
    left_join(clock_context, by = c("game_id", "period_number", "clock_display_value")) |>
    left_join(made_field_goals, by = c("game_id", "period_number", "clock_display_value", "athlete_id_1")) |>
    mutate(
      nominal_attempts = suppressWarnings(as.integer(str_match(type_text, "1 of ([123])")[, 2])),
      special_free_throw = str_detect(type_text, regex("Technical|Flagrant|Clear Path", ignore_case = TRUE)),
      same_clock_made_fg_by_shooter = coalesce(same_clock_made_fg_by_shooter, FALSE),
      linkage_class = case_when(
        special_free_throw | same_clock_has_excluded_foul ~ "excluded_special_or_nonshooting_foul",
        nominal_attempts == 1L & same_clock_has_shooting_foul & same_clock_made_fg_by_shooter ~ "unambiguous_and_one",
        nominal_attempts %in% c(2L, 3L) & same_clock_has_shooting_foul & !same_clock_made_fg_by_shooter ~ "unambiguous_shooting_foul_trip",
        TRUE ~ "ambiguous_or_unrelated"
      )
    )

  shot_trip_linkage[[season]] <- first_free_throws |>
    count(season = season_label, linkage_class, name = "candidate_sequences") |>
    mutate(share = candidate_sequences / sum(candidate_sequences))
  message("  shot-trip aggregates")

  rm(pbp, context_events, clock_context, made_field_goals, first_free_throws)
  gc(verbose = FALSE)
}

field_missingness_out <- bind_rows(field_missingness)
coverage_out <- bind_rows(coverage)
action_counts_out <- bind_rows(action_counts)
taxonomy_counts_out <- bind_rows(taxonomy_counts)
player_family_out <- bind_rows(player_family)
taxonomy_player_family_out <- bind_rows(taxonomy_player_family)
reconciliation_out <- bind_rows(reconciliation)
pbp_coverage_out <- bind_rows(pbp_coverage)
shot_trip_linkage_out <- bind_rows(shot_trip_linkage)
pbp_type_counts_out <- bind_rows(pbp_type_counts)
pbp_qualifier_counts_out <- bind_rows(pbp_qualifier_counts)

label_drift_out <- action_counts_out |>
  group_by(ACTION_TYPE, creation_family, finish_family) |>
  summarise(
    seasons_present = n_distinct(season),
    first_season = min(season),
    last_season = max(season),
    total_shots = sum(shots),
    minimum_season_shots = min(shots),
    maximum_season_shots = max(shots),
    .groups = "drop"
  ) |>
  mutate(
    missing_seasons = length(seasons) - seasons_present,
    drift_flag = if_else(seasons_present == length(seasons), "present_all_five", "season_presence_changed")
  ) |>
  arrange(desc(total_shots), ACTION_TYPE)

taxonomy_support_out <- player_family_out |>
  group_by(season, finish_family) |>
  summarise(
    player_seasons = n(),
    player_seasons_10_plus = sum(attempts >= 10L),
    player_seasons_25_plus = sum(attempts >= 25L),
    player_seasons_50_plus = sum(attempts >= 50L),
    median_attempts = median(attempts),
    p90_attempts = as.numeric(quantile(attempts, 0.9, names = FALSE)),
    maximum_attempts = max(attempts),
    .groups = "drop"
  )

taxonomy_family_support_out <- taxonomy_player_family_out |>
  group_by(season, dimension, family) |>
  summarise(
    player_seasons = n(),
    player_seasons_10_plus = sum(attempts >= 10L),
    player_seasons_25_plus = sum(attempts >= 25L),
    player_seasons_50_plus = sum(attempts >= 50L),
    median_attempts = median(attempts),
    p90_attempts = as.numeric(quantile(attempts, 0.9, names = FALSE)),
    maximum_attempts = max(attempts),
    .groups = "drop"
  )

volume_variation_out <- player_family_out |>
  mutate(season_index = match(season, seasons)) |>
  arrange(PLAYER_ID, finish_family, season_index) |>
  group_by(PLAYER_ID, finish_family) |>
  mutate(
    previous_attempts = lag(attempts),
    previous_season_index = lag(season_index),
    adjacent = season_index - previous_season_index == 1L,
    absolute_change = if_else(adjacent, abs(attempts - previous_attempts), NA_integer_),
    relative_change = if_else(adjacent & previous_attempts > 0L, abs(attempts - previous_attempts) / previous_attempts, NA_real_)
  ) |>
  ungroup() |>
  group_by(finish_family) |>
  summarise(
    player_family_series = n_distinct(PLAYER_ID),
    adjacent_season_pairs = sum(adjacent, na.rm = TRUE),
    median_absolute_attempt_change = median(absolute_change, na.rm = TRUE),
    p90_absolute_attempt_change = as.numeric(quantile(absolute_change, 0.9, na.rm = TRUE, names = FALSE)),
    median_relative_attempt_change = median(relative_change, na.rm = TRUE),
    .groups = "drop"
  )

volume_context_proxy_out <- player_family_out |>
  group_by(finish_family) |>
  summarise(
    player_season_rows = n(),
    multi_team_player_season_rows = sum(teams > 1L),
    spearman_attempts_vs_mean_distance = safe_spearman(attempts, mean_distance_feet),
    spearman_attempts_vs_three_point_share = safe_spearman(attempts, three_point_share),
    .groups = "drop"
  )

audit_sanity_checks_out <- tibble::tribble(
  ~check, ~status, ~measured_value, ~required_value,
  "five_seasons_present", if_else(nrow(coverage_out) == 5L, "pass", "fail"), as.character(nrow(coverage_out)), "5",
  "expected_games_each_season", if_else(all(coverage_out$retrieved_games == 1230L), "pass", "fail"), paste(coverage_out$retrieved_games, collapse = ";"), "1230 each",
  "thirty_teams_each_season", if_else(all(coverage_out$teams == 30L), "pass", "fail"), paste(coverage_out$teams, collapse = ";"), "30 each",
  "unique_shotchart_event_keys", if_else(all(coverage_out$duplicate_game_event_keys == 0L), "pass", "fail"), as.character(sum(coverage_out$duplicate_game_event_keys)), "0 duplicates",
  "complete_shotchart_event_keys", if_else(all(coverage_out$missing_game_event_keys == 0L), "pass", "fail"), as.character(sum(coverage_out$missing_game_event_keys)), "0 missing",
  "complete_24_field_shotchart_schema", if_else(nrow(field_missingness_out) == 120L && all(field_missingness_out$missing_rows == 0L), "pass", "fail"), paste0(nrow(field_missingness_out), " field-season rows; ", sum(field_missingness_out$missing_rows), " missing values"), "120 field-season rows; 0 missing values",
  "all_finish_labels_mapped", if_else(all(coverage_out$unknown_finish_rows == 0L), "pass", "fail"), as.character(sum(coverage_out$unknown_finish_rows)), "0 unknown finish rows",
  "play_by_play_game_crosswalk", if_else(all(pbp_coverage_out$crosswalked_games >= 1229L), "warning", "fail"), paste(pbp_coverage_out$crosswalked_games, collapse = ";"), "document any season below 1230",
  "matched_result_agreement", if_else(all(reconciliation_out$result_agreement_rate == 1), "pass", "fail"), paste(reconciliation_out$result_agreement_rate, collapse = ";"), "1 each season",
  "aggregate_outputs_only", "pass", "no shot-level writer exists", "all tracked audit outputs aggregate or declarative"
)

if (any(audit_sanity_checks_out$status == "fail")) {
  stop("One or more Context Edition audit sanity checks failed")
}

write_atomic_csv(field_missingness_out, "shotchart_field_missingness.csv")
write_atomic_csv(audit_sanity_checks_out, "audit_sanity_checks.csv")
write_atomic_csv(coverage_out, "shotchart_coverage.csv")
write_atomic_csv(action_counts_out, "raw_action_labels.csv")
write_atomic_csv(label_drift_out, "raw_label_drift.csv")
write_atomic_csv(taxonomy_counts_out, "taxonomy_coverage.csv")
write_atomic_csv(taxonomy_support_out, "finish_family_support.csv")
write_atomic_csv(taxonomy_family_support_out, "taxonomy_family_support.csv")
write_atomic_csv(volume_variation_out, "volume_variation.csv")
write_atomic_csv(volume_context_proxy_out, "volume_context_proxy.csv")
write_atomic_csv(pbp_coverage_out, "pbp_source_coverage.csv")
write_atomic_csv(pbp_type_counts_out, "pbp_type_labels.csv")
write_atomic_csv(pbp_qualifier_counts_out, "pbp_shot_qualifiers.csv")
write_atomic_csv(reconciliation_out, "shotchart_pbp_reconciliation.csv")
write_atomic_csv(shot_trip_linkage_out, "shot_trip_linkage.csv")

output_files <- sort(list.files(output_dir, pattern = "\\.csv$", full.names = TRUE))
output_files <- output_files[basename(output_files) != "audit_output_manifest.csv"]
manifest <- tibble(
  file = basename(output_files),
  bytes = file.info(output_files)$size,
  sha256 = map_chr(output_files, sha256_file),
  contains_shot_level_rows = FALSE,
  audit_only = TRUE
)
write_atomic_csv(manifest, "audit_output_manifest.csv")

message("Context Edition audit outputs written to ", output_dir)
