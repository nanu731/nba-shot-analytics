library(tidyverse)
library(arrow)
library(glue)
library(jsonlite)

source("R/zone_model.R")

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

# Zones are keyed by their stable string id, never by position. A positional index would
# be more compact, but if the zone model ever changed the same integer would silently mean
# a different zone, and the website -- a separate repository that keys its SVG paths off
# this value -- would draw the wrong shape with nothing raising an error anywhere.
zone_index <- function() {
  source("R/02_build_zone_stats.R")
  ZONE_REF |>
    arrange(zone_order) |>
    transmute(zone, name = zone_label, value = zone_value)
}

r <- function(x, digits) round(x, digits)

season_block <- function(season, zidx) {
  zs <- read_parquet(glue("data/processed/zone_stats/season={season}/zone_stats.parquet")) |>
    mutate(known = zone %in% zidx$zone)
  ps <- read_parquet(glue("data/processed/player_scores/season={season}/player_scores.parquet"))
  pr <- read_parquet(glue("data/processed/zone_priors/season={season}/zone_priors.parquet")) |>
    mutate(known = zone %in% zidx$zone)

  if (!all(zs$known) || !all(pr$known)) {
    stop(glue("{season}: a zone id is absent from the model: ",
              "{str_c(setdiff(c(zs$zone, pr$zone), zidx$zone), collapse = ', ')}"), call. = FALSE)
  }

  # Canonical basket-outward ordering, applied by id rather than by row position.
  zone_rank <- set_names(seq_len(nrow(zidx)), zidx$zone)

  baselines <- zs |>
    summarise(freq_pooled = first(freq_pooled), freq_unweighted = first(freq_unweighted),
              .by = zone) |>
    arrange(zone_rank[zone])

  flat <- zs |>
    arrange(PLAYER_ID, zone_rank[zone]) |>
    transmute(PLAYER_ID, zone, makes, attempts,
              fg_pct = r(fg_pct, 4), pps = r(pps_raw, 4), freq = r(shot_freq, 4),
              fg_pct_shrunk = r(fg_pct_shrunk, 4), pps_shrunk = r(pps_shrunk, 4),
              contrib = r(score_contrib, 5))
  zone_rows <- split(select(flat, -PLAYER_ID), as.character(flat$PLAYER_ID))

  players <- ps |>
    arrange(desc(score_pooled)) |>
    transmute(
      player_id = PLAYER_ID, name = PLAYER_NAME,
      position = POSITION, pos3 = POS3,
      pos3_display = POS3_DISPLAY, pos3_derived = POS3_DERIVED,
      listed_height = listed_height,
      games, attempts = total_attempts, zones_used,
      pps = r(pps_overall_raw, 4),
      score = r(score_pooled, 5),
      score_unweighted = r(score_unweighted, 5),
      herfindahl = r(herfindahl, 4)
    ) |>
    mutate(zones = unname(zone_rows[as.character(player_id)]))

  list(
    priors = pr |> arrange(zone_rank[zone]) |>
      transmute(zone, alpha = r(alpha, 3), beta = r(beta, 3), k = r(k, 2),
                prior_mean = r(prior_mean, 4), qualifying_attempts, converged, method),
    baselines = baselines |>
      transmute(zone, freq_pooled = r(freq_pooled, 5),
                freq_unweighted = r(freq_unweighted, 5)),
    players = players
  )
}

# The picker must search every player without downloading a season file, so meta.json
# carries one entry per player keyed by PLAYER_ID. Names are display text only: two
# players change spelling between seasons, so the most recent is kept and every join
# goes on the id.
player_index <- function(blocks) {
  imap(blocks, \(b, s) transmute(b$players, player_id, name, season = s)) |>
    list_rbind() |>
    arrange(player_id, season) |>
    summarise(name = last(name), seasons = list(season), .by = player_id) |>
    arrange(player_id)
}

export_json <- function(seasons = exportable_seasons(), dir = OUT_DIR) {
  zidx <- zone_index()
  blocks <- set_names(map(seasons, \(s) {
    b <- season_block(s, zidx)
    cat(glue("  {s}: {nrow(b$players)} players, {nrow(b$priors)} zones"), "\n")
    b
  }), seasons)

  pidx <- player_index(blocks)

  meta <- list(
    generated = format(Sys.Date()),
    # The geometry fingerprint. zone_polygons.json carries the same field, and the site
    # must assert the two are equal at build time and fail if either is missing or they
    # differ -- a missing field is how a pre-2026-08-27 file would otherwise pass. See
    # ASSUMPTIONS entry 35: three zone ids survived the model change and two of them are
    # safe, so a stale outline would draw a wrong court without erroring.
    zone_model = zone_model_version(),
    # Placeholder display copy is in the build. The site must refuse to publish while this
    # is true; R/06 refuses to sync. Removed when the author's wording lands.
    zone_labels_provisional = ZONE_LABELS_PROVISIONAL,
    # I() marks these AsIs so jsonlite's auto_unbox leaves them as arrays. Without it a
    # length-1 vector serialises as a bare scalar, and a consumer iterating the field
    # would walk the characters of a string. See ASSUMPTIONS entry 25.
    seasons = I(seasons),
    eligibility = list(min_games = 20, min_attempts = 250),
    metric = list(
      score = paste("Sum over zones of (player frequency - league pooled frequency)",
                    "x shrunk PPS. Units are points per shot."),
      pps = "Points per field goal attempt. Made 2 = 2, made 3 = 3, miss = 0.",
      shrinkage = "Beta-binomial empirical Bayes, fitted per zone and per season on the qualifying pool.",
      note = paste("zone fields are stable string ids; resolve them through meta.zones.",
                   "fg_pct and pps are null where attempts = 0. Summing zones[].contrib",
                   "does not reproduce score exactly; both are rounded independently.",
                   "See export/SCHEMA.md.")
    ),
    zones = zidx |> select(zone, name, value),
    players = set_names(
      map2(pidx$name, pidx$seasons, \(n, ss) list(name = n, seasons = I(ss))),
      as.character(pidx$player_id))
  )

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write <- function(x, file) {
    path <- file.path(dir, file)
    write_json(x, path, auto_unbox = TRUE, null = "null", na = "null", pretty = FALSE)
    path
  }

  # meta is its own file so the site loads zone definitions, eligibility and the player
  # search index once rather than repeating them in every season payload.
  paths <- c(write(meta, "meta.json"),
             imap_chr(blocks, \(b, s) write(c(list(season = s), b), glue("season-{s}.json"))))

  cat("\n")
  for (path in paths) {
    cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  }
  cat(glue("  total {round(sum(file.size(paths)) / 1024^2, 2)} MB across {length(paths)} files"), "\n")

  m <- fromJSON(file.path(dir, "meta.json"), simplifyVector = FALSE)
  one <- fromJSON(file.path(dir, glue("season-{seasons[length(seasons)]}.json")), simplifyVector = FALSE)
  cat(glue("  reads back: meta has {length(m$zones)} zones, {length(m$players)} players, ",
           "{length(m$seasons)} seasons; ",
           "{one$season} has {length(one$players)} players, ",
           "{length(one$players[[1]]$zones)} zone rows on the first"), "\n")
  invisible(paths)
}

if (sys.nframe() == 0L) export_json()
