library(tidyverse)
library(arrow)
library(glue)
library(jsonlite)

season_dirs <- function(root) {
  if (!dir.exists(root)) return(character(0))
  dirs <- list.dirs(root, recursive = FALSE, full.names = FALSE)
  sort(str_remove(dirs[str_starts(dirs, "season=")], "^season="))
}

# What the pipeline can process: the collected raw shot logs. This is the pipeline's
# input. Discovering from data/processed would be circular -- the pipeline would only run
# if it had already run, which is exactly the bug a clean-state rebuild exposes.
available_seasons <- function() season_dirs("data/raw/shots")

# What the export can write: seasons that have been through stages 2 and 3. This is stage
# 5's own input, so it is not circular, and it keeps meta.json listing exactly the season
# files sitting beside it after a partial run.
exportable_seasons <- function() season_dirs("data/processed/zone_stats")
OUT_DIR <- "export/data"

# Rule A16: derived aggregates only. Nothing here reaches below the player-zone cell, and
# no shot-level column (LOC_X, LOC_Y, GAME_ID, ACTION_TYPE) is exported.

# Zones are referenced by integer index into meta$zones rather than by name. The names run
# to 41 characters and would otherwise repeat in all ~21,000 zone objects.
zone_index <- function() {
  source("R/02_build_zone_stats.R")
  ZONE_REF |>
    arrange(zone_order) |>
    transmute(zone, value = zone_value) |>
    mutate(idx = row_number() - 1L)
}

r <- function(x, digits) round(x, digits)

season_block <- function(season, zidx) {
  zs <- read_parquet(glue("data/processed/zone_stats/season={season}/zone_stats.parquet")) |>
    left_join(select(zidx, zone, idx), by = "zone")
  ps <- read_parquet(glue("data/processed/player_scores/season={season}/player_scores.parquet"))
  pr <- read_parquet(glue("data/processed/zone_priors/season={season}/zone_priors.parquet")) |>
    left_join(select(zidx, zone, idx), by = "zone")

  if (anyNA(zs$idx) || anyNA(pr$idx)) stop(glue("{season}: a zone failed to match ZONE_REF"), call. = FALSE)

  baselines <- zs |>
    summarise(freq_pooled = first(freq_pooled), freq_unweighted = first(freq_unweighted),
              .by = c(idx)) |>
    arrange(idx)

  flat <- zs |>
    arrange(PLAYER_ID, idx) |>
    transmute(PLAYER_ID, zone = idx, makes, attempts,
              fg_pct = r(fg_pct, 4), pps = r(pps_raw, 4), freq = r(shot_freq, 4),
              fg_pct_shrunk = r(fg_pct_shrunk, 4), pps_shrunk = r(pps_shrunk, 4),
              contrib = r(score_contrib, 5))
  zone_rows <- split(select(flat, -PLAYER_ID), as.character(flat$PLAYER_ID))

  players <- ps |>
    arrange(desc(score_pooled)) |>
    transmute(
      player_id = PLAYER_ID, name = PLAYER_NAME,
      position = POSITION, pos3 = POS3,
      games, attempts = total_attempts, zones_used,
      pps = r(pps_overall_raw, 4),
      score = r(score_pooled, 5),
      score_unweighted = r(score_unweighted, 5),
      herfindahl = r(herfindahl, 4)
    ) |>
    mutate(zones = unname(zone_rows[as.character(player_id)]))

  list(
    priors = pr |> arrange(idx) |>
      transmute(zone = idx, alpha = r(alpha, 3), beta = r(beta, 3), k = r(k, 2),
                prior_mean = r(prior_mean, 4), league_attempts, converged, method),
    baselines = baselines |>
      transmute(zone = idx, freq_pooled = r(freq_pooled, 5),
                freq_unweighted = r(freq_unweighted, 5)),
    players = players
  )
}

export_json <- function(seasons = exportable_seasons(), dir = OUT_DIR) {
  zidx <- zone_index()
  blocks <- set_names(map(seasons, \(s) {
    b <- season_block(s, zidx)
    cat(glue("  {s}: {nrow(b$players)} players, {nrow(b$priors)} zones"), "\n")
    b
  }), seasons)

  meta <- list(
      generated = format(Sys.Date()),
      seasons = seasons,
      eligibility = list(min_games = 20, min_attempts = 250),
      metric = list(
        score = paste("Sum over zones of (player frequency - league pooled frequency)",
                      "x shrunk PPS. Units are points per shot."),
        pps = "Points per field goal attempt. Made 2 = 2, made 3 = 3, miss = 0.",
        shrinkage = "Beta-binomial empirical Bayes, fitted per zone and per season on the qualifying pool.",
        note = "zone fields index into meta.zones. fg_pct and pps are null where attempts = 0."
      ),
      zones = zidx |> transmute(index = idx, zone, value)
    )

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write <- function(x, file) {
    path <- file.path(dir, file)
    write_json(x, path, auto_unbox = TRUE, null = "null", na = "null", pretty = FALSE)
    path
  }

  # meta is its own file so the site loads zone definitions and eligibility once rather
  # than repeating them in every season payload.
  paths <- c(write(meta, "meta.json"),
             imap_chr(blocks, \(b, s) write(c(list(season = s), b), glue("season-{s}.json"))))

  cat("\n")
  for (path in paths) {
    cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  }
  cat(glue("  total {round(sum(file.size(paths)) / 1024^2, 2)} MB across {length(paths)} files"), "\n")

  m <- fromJSON(file.path(dir, "meta.json"), simplifyVector = FALSE)
  one <- fromJSON(file.path(dir, glue("season-{seasons[length(seasons)]}.json")), simplifyVector = FALSE)
  cat(glue("  reads back: meta has {length(m$zones)} zones and {length(m$seasons)} seasons; ",
           "{one$season} has {length(one$players)} players, ",
           "{length(one$players[[1]]$zones)} zone rows on the first"), "\n")
  invisible(paths)
}

if (sys.nframe() == 0L) export_json()
