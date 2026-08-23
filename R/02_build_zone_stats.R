library(tidyverse)
library(arrow)
library(duckdb)
library(DBI)
library(glue)

# The NBA's own classification, hardcoded rather than read off the data with DISTINCT.
# A typo or a new label combination in a future season should stop the run, not quietly
# become a fifteenth zone.
ZONE_REF <- tribble(
  ~SHOT_ZONE_BASIC,        ~SHOT_ZONE_AREA,         ~zone_value, ~zone_order,
  "Restricted Area",       "Center(C)",                       2,           1,
  "In The Paint (Non-RA)", "Left Side(L)",                    2,           2,
  "In The Paint (Non-RA)", "Center(C)",                       2,           3,
  "In The Paint (Non-RA)", "Right Side(R)",                   2,           4,
  "Mid-Range",             "Left Side(L)",                    2,           5,
  "Mid-Range",             "Left Side Center(LC)",            2,           6,
  "Mid-Range",             "Center(C)",                       2,           7,
  "Mid-Range",             "Right Side Center(RC)",           2,           8,
  "Mid-Range",             "Right Side(R)",                   2,           9,
  "Left Corner 3",         "Left Side(L)",                    3,          10,
  "Above the Break 3",     "Left Side Center(LC)",            3,          11,
  "Above the Break 3",     "Center(C)",                       3,          12,
  "Above the Break 3",     "Right Side Center(RC)",           3,          13,
  "Right Corner 3",        "Right Side(R)",                   3,          14
) |>
  mutate(zone = str_c(SHOT_ZONE_BASIC, " | ", SHOT_ZONE_AREA), .before = zone_value)

MIN_GAMES <- 20

# 250 is the 25th percentile of total attempts among players with 20+ games (235.75 in
# 2025-26), rounded. A shots-per-game gate was tried and dropped: it deleted rim-running
# centres rather than low-impact players.
MIN_ATTEMPTS <- 250

# Verified counts for the one collected season. Asserted for 2025-26, printed for
# comparison otherwise, so the script stays reusable across the other four seasons.
EXPECTED <- list(
  "2025-26" = list(
    raw              = 219160,
    after_backcourt  = 219122,
    after_anomaly    = 219102,
    players_all      = 582,
    players_qualify  = 318,
    qualifying_shots = 194967,
    grid_rows        = 4452,
    cells_ge1        = 4184,
    cells_eq1        = 228,
    cells_le3        = 629
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
  dbWriteTable(con, "zone_ref", ZONE_REF, temporary = TRUE)

  src <- glue("read_parquet('data/raw/shots/**/*.parquet', hive_partitioning = 1)")
  dbExecute(con, glue("CREATE TEMP VIEW raw_shots AS
    SELECT * FROM {src} WHERE season = '{season}'"))

  cat("filter chain\n")
  n_raw <- dbGetQuery(con, "SELECT COUNT(*) n FROM raw_shots")$n
  check("raw rows", n_raw, exp$raw, strict)

  # Backcourt heaves are excluded entirely, as they are on the NBA's own charts. Two
  # label combinations carry them, so both columns have to be tested.
  dbExecute(con, "CREATE TEMP VIEW in_play AS
    SELECT * FROM raw_shots
    WHERE SHOT_ZONE_BASIC <> 'Backcourt' AND SHOT_ZONE_AREA <> 'Back Court(BC)'")
  n_in_play <- dbGetQuery(con, "SELECT COUNT(*) n FROM in_play")$n
  check("after dropping backcourt", n_in_play, exp$after_backcourt, strict)

  found <- dbGetQuery(con, 'SELECT DISTINCT SHOT_ZONE_BASIC, SHOT_ZONE_AREA FROM in_play')
  unknown <- anti_join(found, ZONE_REF, by = c("SHOT_ZONE_BASIC", "SHOT_ZONE_AREA"))
  missing <- anti_join(ZONE_REF, found, by = c("SHOT_ZONE_BASIC", "SHOT_ZONE_AREA"))
  if (nrow(unknown) > 0 || nrow(missing) > 0) {
    stop(glue("zone labels do not match ZONE_REF.\n",
              "unknown in data: {paste(unknown$SHOT_ZONE_BASIC, unknown$SHOT_ZONE_AREA, collapse = '; ')}\n",
              "absent from data: {paste(missing$SHOT_ZONE_BASIC, missing$SHOT_ZONE_AREA, collapse = '; ')}"),
         call. = FALSE)
  }
  cat(glue("  {format('zone labels matched ZONE_REF', width = 34)} {nrow(found)} of 14"), "\n")

  # A handful of boundary shots carry a SHOT_TYPE that contradicts their zone's point
  # value. They are dropped so that every zone holds exactly one point value, which is
  # what lets stage 3 shrink FG% and multiply rather than shrink PPS directly.
  dbExecute(con, 'CREATE TEMP VIEW clean_shots AS
    SELECT s.PLAYER_ID, s.PLAYER_NAME, s.GAME_ID, s.SHOT_MADE_FLAG,
           z."zone", z.zone_value
    FROM in_play s
    JOIN zone_ref z USING (SHOT_ZONE_BASIC, SHOT_ZONE_AREA)
    WHERE z.zone_value = CASE WHEN s.SHOT_TYPE = \'3PT Field Goal\' THEN 3 ELSE 2 END')
  n_clean <- dbGetQuery(con, "SELECT COUNT(*) n FROM clean_shots")$n
  check("after dropping point-value clashes", n_clean, exp$after_anomaly, strict)
  cat(glue("  {format('  clashes dropped', width = 34)} {n_in_play - n_clean}"), "\n\n")

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

  readback <- dbGetQuery(con, "
    SELECT season, COUNT(*) AS rows, COUNT(DISTINCT PLAYER_ID) AS players
    FROM read_parquet('data/processed/zone_stats/**/*.parquet', hive_partitioning = 1)
    GROUP BY season ORDER BY season")
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
