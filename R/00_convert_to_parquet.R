library(tidyverse)
library(arrow)
library(glue)

# One-off conversion of the original collection run. Later seasons are written straight
# to Parquet by the Python ingestion, so this exists only to reproduce data/raw/shots
# from the CSV that survives from the first collection.
convert_season <- function(season) {
  raw_csv <- glue("data/raw/shots_{str_replace(season, '-', '_')}.csv")
  out_dir <- glue("data/raw/shots/season={season}")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_parquet <- glue("{out_dir}/shots.parquet")

  # GAME_ID must stay character. It has leading zeros, and read as a number they are
  # gone permanently, which silently changes any COUNT(DISTINCT GAME_ID) downstream.
  shots <- read_csv(raw_csv, col_types = cols(GAME_ID = col_character()))

  # season is carried by the directory name, so it is not a column in the file.
  write_parquet(shots, out_parquet)

  cat("Rows:   ", nrow(shots), "\n")
  cat("Cols:   ", ncol(shots), "\n")
  cat("CSV:    ", round(file.size(raw_csv) / 1024^2, 1), "MB\n")
  cat("Parquet:", round(file.size(out_parquet) / 1024^2, 1), "MB\n")
  cat("Path:   ", out_parquet, "\n")
  invisible(out_parquet)
}

if (sys.nframe() == 0L) convert_season("2025-26")
