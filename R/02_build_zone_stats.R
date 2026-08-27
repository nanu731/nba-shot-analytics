library(tidyverse)
library(arrow)
library(duckdb)
library(DBI)
library(glue)

source("R/zone_model.R")

# Zones come from R/zone_model.R, which is the only place a boundary is defined (rule A4).
# This table adds nothing but presentation: display order and a human label.
#
# zone is the stable public identifier and the join key. It is derived from what the zone
# means, never from its position, because the JSON export and the website key off it: a
# positional index would silently point at a different zone if the model changed, and the
# site would draw the wrong shape with nothing raising an error.
#
# Two ids survive the 14-zone model: corner3_left and corner3_right, whose membership is
# identical across both models shot for shot, so a stale outline still draws them
# correctly. The one id whose geometry changed under an unchanged name was arc3_center,
# renamed to arc3_top in R/zone_model.R for that reason. Everything else is either new or
# gone, so a stale lookup misses loudly. Step 7 still owes a model version asserted at site
# build time, because a missing lookup is not guaranteed to be a visible failure.
#
# TODO_ZONE_LABELS: zone_label below is PLACEHOLDER COPY written by the assistant, not by
# the author, and must not reach the export or any chart a reader sees. The author is
# supplying wording before the export step. ZONE_LABELS_PROVISIONAL exists so stage 5 can
# refuse to run while it is TRUE -- wire that assertion in when stage 5 is rewired.
ZONE_LABELS_PROVISIONAL <- TRUE

ZONE_REF <- tibble(
  zone       = ZONE_IDS,
  zone_value = unname(ZONE_VALUE[ZONE_IDS]),
  zone_label = c("Restricted Area", "Paint (non-RA)",
                 "Mid-Range Left", "Mid-Range Center", "Mid-Range Right",
                 "Left Corner 3", "Above the Break 3 Left", "Above the Break 3 Center",
                 "Above the Break 3 Right", "Right Corner 3"),
  zone_order = seq_along(ZONE_IDS)
)

MIN_GAMES <- 20

# 250 is the 25th percentile of total attempts among players with 20+ games (235.75 in
# 2025-26), rounded. A shots-per-game gate was tried and dropped: it deleted rim-running
# centres rather than low-impact players.
MIN_ATTEMPTS <- 250

# Two kinds of number live here and they are not interchangeable.
#
# Pre-registered in ZONE_MODEL_ACCEPTANCE.md before this model produced anything: raw rows
# and qualifying players, every season. Redrawing zones must not change how many shots or
# players exist, so a mismatch is a bug and stops the run.
#
# Carried on trust from the session that drafted the model: the 2025-26 backcourt drop and
# the grid size. Also asserted, because if they are wrong the right response is a stop and
# a report, not a quiet absorption.
#
# The cell-thinness counts are neither. The draft session's table gave 3,087 / 60 / 197 and
# the build gives 3,089 / 61 / 198. Its 60 and 197 reproduce exactly if the tally is taken
# before the point-value clashes are dropped, so that table was measured one stage early;
# its 3,087 reproduces under nothing tested -- not the mid-ray inclusivity difference (no
# 2025-26 shot lies on a mid ray), nor rim, lane, free-throw-line, corner or arc
# inclusivity, nor either backcourt treatment. Two cells in 3,089 is 0.06 percent and none
# of these figures is pre-registered. The values below are measured from this build and
# stand as a drift guard, not as an independent check -- raw rows, qualifying players and
# grid size are what actually test the model.
#
# after_anomaly and qualifying_shots are deliberately absent. The point-value clash set
# changes under coordinate classification, so no per-season figure exists to assert yet.
# They print, and the five-season clash total is reconciled against 407 by the caller.
EXPECTED <- list(
  "2021-22" = list(raw = 216722, backcourt = 475, players_qualify = 312),
  "2022-23" = list(raw = 217220, backcourt = 459, players_qualify = 292),
  "2023-24" = list(raw = 218700, backcourt = 465, players_qualify = 281),
  "2024-25" = list(raw = 219527, backcourt = 555, players_qualify = 304),
  "2025-26" = list(
    raw              = 219160,
    backcourt        = 38,
    after_backcourt  = 219122,
    players_all      = 582,
    players_qualify  = 318,
    grid_rows        = 3180,
    cells_ge1        = 3089,
    cells_eq1        = 61,
    cells_le3        = 198
  )
)

# season lives in the directory name rather than in the file, matching data/raw/shots.
# Reading with hive_partitioning = 1 puts the column back.
write_season_table <- function(df, table_name, season) {
  dir <- glue("data/processed/{table_name}/season={season}")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- glue("{dir}/{table_name}.parquet")
  write_parquet(select(df, -season), path)
  path
}

check <- function(label, actual, expected, strict) {
  if (is.null(expected)) {
    cat(glue("  {format(label, width = 34)} {format(actual, big.mark = ',')}"), "\n")
    return(invisible(actual))
  }
  ok <- identical(as.numeric(actual), as.numeric(expected))
  mark <- if (ok) "ok" else "MISMATCH"
  cat(glue("  {format(label, width = 34)} {format(actual, big.mark = ',')}  ",
           "(expected {format(expected, big.mark = ',')}) {mark}"), "\n")
  if (!ok && strict) {
    stop(glue("{label}: got {actual}, expected {expected}"), call. = FALSE)
  }
  invisible(actual)
}

build_zone_stats <- function(season) {
  exp    <- EXPECTED[[season]]
  strict <- !is.null(exp)
  cat(glue("\n=== stage 2: {season} ==="), "\n\n")

  con <- dbConnect(duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  src <- glue("read_parquet('data/raw/shots/**/*.parquet', hive_partitioning = 1)")

  # Classification happens in R, not SQL. Translating classify_zone() into a DuckDB
  # expression would restate every boundary a second time, which A4 forbids. A season is
  # about 219k rows, so pulling it into memory to classify and pushing it back is free.
  raw <- dbGetQuery(con, glue("
    SELECT PLAYER_ID, PLAYER_NAME, GAME_ID, SHOT_MADE_FLAG, SHOT_TYPE, LOC_X, LOC_Y,
           SHOT_ZONE_BASIC, SHOT_ZONE_AREA
    FROM {src} WHERE season = '{season}'")) |> as_tibble()

  cat("filter chain\n")
  check("raw rows", nrow(raw), exp$raw, strict)

  classified <- mutate(raw, zone = classify_zone(LOC_X, LOC_Y))

  # Backcourt heaves are excluded entirely, as they are on the NBA's own charts.
  # classify_zone() returns NA beyond Y_BACKCOURT and nowhere else, so this is the only
  # place a row can leave the partition without being counted.
  in_play <- filter(classified, !is.na(zone))
  check("backcourt dropped", nrow(classified) - nrow(in_play), exp$backcourt, strict)
  check("after dropping backcourt", nrow(in_play), exp$after_backcourt, strict)

  # A one-off equivalence proof, not a dependency. The coordinate cut has to remove exactly
  # the rows the retired SHOT_ZONE_BASIC / SHOT_ZONE_AREA filter removed -- per season, not
  # merely in total. Those label columns stay in data/raw forever, so this stays runnable.
  by_label <- with(classified,
                   SHOT_ZONE_BASIC == "Backcourt" | SHOT_ZONE_AREA == "Back Court(BC)")
  if (!identical(is.na(classified$zone), by_label)) {
    stop(glue("{season}: the coordinate cut and the retired label filter disagree on ",
              "{sum(xor(is.na(classified$zone), by_label))} rows"), call. = FALSE)
  }
  cat(glue("  {format('  agrees with retired label filter', width = 34)} row for row"), "\n")

  # Zone comes from the coordinate, point value from SHOT_TYPE. Where the two disagree the
  # shot is dropped, so that every zone holds exactly one point value -- which is what lets
  # stage 3 shrink FG% and multiply rather than shrink PPS directly. Valuing by coordinate
  # instead would keep the model purely geometric at the cost of counting points the player
  # did not score, and PPS meaning actual points is the metric's whole claim.
  valued <- left_join(in_play, select(ZONE_REF, zone, zone_value), by = "zone")

  # Before the filter, not after: filter() drops NA silently, so a zone id missing from
  # ZONE_REF would leave as a point-value clash and never be reported.
  if (anyNA(valued$zone_value)) {
    stop(glue("{season}: classify_zone() returned {n} rows with an id absent from ",
              "ZONE_REF: {ids}",
              n = sum(is.na(valued$zone_value)),
              ids = str_c(unique(valued$zone[is.na(valued$zone_value)]), collapse = ", ")),
         call. = FALSE)
  }

  clean <- valued |>
    filter(zone_value == if_else(SHOT_TYPE == "3PT Field Goal", 3, 2)) |>
    select(PLAYER_ID, PLAYER_NAME, GAME_ID, SHOT_MADE_FLAG, zone, zone_value)
  check("after dropping point-value clashes", nrow(clean), exp$after_anomaly, strict)
  cat(glue("  {format('  clashes dropped', width = 34)} {nrow(in_play) - nrow(clean)}"), "\n\n")

  dbWriteTable(con, "clean_shots", clean, temporary = TRUE)

  # GAME_ID is a string with leading zeros. If either side ever reads it as a number
  # those zeros are gone permanently, and the games gate silently changes.
  gid <- dbGetQuery(con, "SELECT GAME_ID FROM clean_shots LIMIT 1")$GAME_ID
  stopifnot(is.character(gid), str_detect(gid, "^0"))
  cat(glue("GAME_ID intact as character: {gid}"), "\n\n")

  cat("eligibility\n")
  players <- dbGetQuery(con, glue("
    SELECT PLAYER_ID, any_value(PLAYER_NAME) AS PLAYER_NAME,
           COUNT(*) AS total_attempts,
           COUNT(DISTINCT GAME_ID) AS games,
           COUNT(DISTINCT \"zone\") AS zones_used,
           SUM(zone_value * SHOT_MADE_FLAG) AS total_points
    FROM clean_shots GROUP BY PLAYER_ID")) |>
    as_tibble() |>
    mutate(qualifies = games >= MIN_GAMES & total_attempts >= MIN_ATTEMPTS)

  check("players with any shot", nrow(players), exp$players_all, strict)
  check("  pass games gate", sum(players$games >= MIN_GAMES), NULL, strict)
  check("  pass attempts gate", sum(players$total_attempts >= MIN_ATTEMPTS), NULL, strict)
  check("qualifying players", sum(players$qualifies), exp$players_qualify, strict)
  check("qualifying shots", sum(players$total_attempts[players$qualifies]),
        exp$qualifying_shots, strict)
  cat("\n")

  qualified <- players |>
    filter(qualifies) |>
    mutate(pps_overall_raw = total_points / total_attempts) |>
    select(PLAYER_ID, PLAYER_NAME, total_attempts, games, zones_used, pps_overall_raw)

  cat("zones used by qualifying players\n")
  print(count(qualified, zones_used), n = Inf)
  cat("\n")

  cells <- dbGetQuery(con, 'SELECT PLAYER_ID, "zone",
      COUNT(*) AS attempts, SUM(SHOT_MADE_FLAG) AS makes
    FROM clean_shots GROUP BY 1, 2') |> as_tibble()

  # Every zone a player could have shot from, not only the ones he used. Zero-attempt
  # cells stay because low volume in a zone is the signal the metric measures, and the
  # stage 3 prior supplies a value there without needing a special case.
  zone_stats <- qualified |>
    select(PLAYER_ID, PLAYER_NAME, total_attempts) |>
    cross_join(select(ZONE_REF, zone, zone_value, zone_order)) |>
    left_join(cells, by = c("PLAYER_ID", "zone")) |>
    mutate(
      across(c(makes, attempts), \(x) coalesce(x, 0)),
      fg_pct    = if_else(attempts > 0, makes / attempts, NA_real_),
      pps_raw   = zone_value * fg_pct,
      shot_freq = attempts / total_attempts,
      season    = .env$season
    ) |>
    arrange(PLAYER_NAME, zone_order) |>
    select(season, PLAYER_ID, PLAYER_NAME, zone, zone_value,
           makes, attempts, fg_pct, pps_raw, shot_freq)

  cat("grid\n")
  check("rows", nrow(zone_stats), nrow(qualified) * nrow(ZONE_REF), TRUE)
  check("rows against pre-registration", nrow(zone_stats), exp$grid_rows, strict)
  check("attempts across grid", sum(zone_stats$attempts), exp$qualifying_shots, strict)
  if (anyNA(zone_stats$makes) || anyNA(zone_stats$attempts)) {
    stop("NA in makes or attempts: the zero fill did not cover every cell", call. = FALSE)
  }

  drift <- zone_stats |>
    summarise(total = sum(shot_freq), .by = PLAYER_ID) |>
    pull(total) |>
    (\(x) max(abs(x - 1)))()
  if (drift > 1e-9) stop(glue("shot_freq does not sum to 1: drift {drift}"), call. = FALSE)
  cat(glue("  {format('shot_freq sums to 1, max drift', width = 34)} {signif(drift, 3)}"), "\n")

  used <- filter(zone_stats, attempts > 0)
  check("cells with 1+ attempts", nrow(used), exp$cells_ge1, strict)
  check("cells with exactly 1 attempt", sum(used$attempts == 1), exp$cells_eq1, strict)
  check("cells with 3 or fewer", sum(used$attempts <= 3), exp$cells_le3, strict)

  # zones_used was counted independently in SQL, so a disagreement means the cross join
  # or the zero fill went wrong rather than the count being merely stale.
  recount <- count(used, PLAYER_ID, name = "from_grid")
  if (!all(arrange(recount, PLAYER_ID)$from_grid == arrange(qualified, PLAYER_ID)$zones_used)) {
    stop("zones_used disagrees with the grid", call. = FALSE)
  }
  cat(glue("  {format('zones_used agrees with grid', width = 34)} all {nrow(qualified)} players"), "\n\n")

  player_scores <- mutate(qualified, season = .env$season, .before = 1)

  cat("written\n")
  for (path in c(write_season_table(zone_stats, "zone_stats", season),
                 write_season_table(player_scores, "player_scores", season))) {
    cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  }

  # Scoped to the season just written. Globbing the whole store would union schemas
  # across seasons, and mid-pipeline some are stage-2 shaped while others are already
  # stage-3 enriched.
  readback <- dbGetQuery(con, glue("
    SELECT '{season}' AS season, COUNT(*) AS rows, COUNT(DISTINCT PLAYER_ID) AS players
    FROM read_parquet('data/processed/zone_stats/season={season}/zone_stats.parquet')"))
  cat("\nread back from the partitioned store\n")
  print(as_tibble(readback))

  cat("\nStephen Curry\n")
  zone_stats |>
    filter(PLAYER_NAME == "Stephen Curry") |>
    mutate(across(c(fg_pct, pps_raw, shot_freq), \(x) round(x, 3))) |>
    select(zone, zone_value, makes, attempts, fg_pct, pps_raw, shot_freq) |>
    print(n = Inf)

  invisible(list(zone_stats = zone_stats, player_scores = player_scores))
}

if (sys.nframe() == 0L) build_zone_stats("2025-26")
