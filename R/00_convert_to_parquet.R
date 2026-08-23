library(tidyverse)
library(arrow)

raw_csv     <- "data/raw/shots_2025_26.csv"
raw_parquet <- "data/raw/shots_2025_26.parquet"

# GAME_ID must stay character — leading zeros are meaningful
shots <- read_csv(
  raw_csv,
  col_types = cols(GAME_ID = col_character())
)

write_parquet(shots, raw_parquet)

# Verify: row count, column count, and the size difference
cat("Rows:   ", nrow(shots), "\n")
cat("Cols:   ", ncol(shots), "\n")
cat("CSV:    ", round(file.size(raw_csv) / 1024^2, 1), "MB\n")
cat("Parquet:", round(file.size(raw_parquet) / 1024^2, 1), "MB\n")