# Runs stages 2 through 5 for one season or several. Ingestion is not included: it is
# Python, it is slow, and it only needs re-running when a season is first collected.
#
#   Rscript R/run_pipeline.R                 # every collected season
#   Rscript R/run_pipeline.R 2025-26
#   Rscript R/run_pipeline.R 2021-22 2022-23

library(glue)

for (stage in c("R/02_build_zone_stats.R", "R/03_compute_scores.R",
                "R/04_charts.R", "R/05_export_json.R")) {
  source(stage)
}

# Charts are rendered for one named player so the committed zone chart stays reproducible
# from the pipeline. Any other player is available on demand through zone_chart().
run_pipeline <- function(seasons = available_seasons(), zone_chart_player = "Stephen Curry") {
  stopifnot(length(seasons) > 0)
  started <- Sys.time()
  cat(glue("\n### pipeline: {str_c(seasons, collapse = ', ')}\n"), "\n")

  for (season in seasons) {
    build_zone_stats(season)
    compute_scores(season)

    cat(glue("\n=== stage 4: {season} ==="), "\n\n")
    write_chart(score_volume_chart(season), "score_vs_volume", season, 14, 5.8)
    write_chart(leaderboard_chart(season), "leaderboard", season, 13, 5.2)

    qualifies <- zone_chart_player %in%
      read_scores(season)$PLAYER_NAME
    if (qualifies) {
      write_chart(zone_chart(zone_chart_player, season), "zones_curry", season, 8.5, 7)
    } else {
      cat(glue("  {zone_chart_player} did not qualify in {season}; zone chart skipped"), "\n")
    }
  }

  # Stage 5 runs once at the end over every season present on disk, so a single-season
  # run still leaves meta.json consistent with the season files beside it.
  cat("\n=== stage 5: export ===\n")
  export_json()

  cat(glue("\n### done in {round(difftime(Sys.time(), started, units = 'mins'), 1)} min"), "\n")
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  run_pipeline(if (length(args)) args else available_seasons())
}
