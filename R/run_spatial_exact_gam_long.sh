#!/bin/sh

# Launch the frozen exact full-league GAM with a separate caffeinate guard.
# caffeinate watches this shell's PID; exec preserves that PID for the R runner.

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: R/run_spatial_exact_gam_long.sh <season>" >&2
  exit 2
fi

season="$1"
if [ "$season" != "2025-26" ]; then
  echo "The frozen experiment is registered only for 2025-26" >&2
  exit 2
fi

cache_dir="data/cache/spatial_gam_exact_full_league_benchmark/season=$season"
mkdir -p "$cache_dir"
SPATIAL_EXACT_CONSOLE_LOG="$cache_dir/runner_console.$$.log"
export SPATIAL_EXACT_CONSOLE_LOG

/usr/bin/caffeinate -dimsu -w "$$" &
SPATIAL_EXACT_CAFFEINATE_PID="$!"
export SPATIAL_EXACT_CAFFEINATE_PID

exec /usr/local/bin/Rscript \
  R/spatial_gam_aggregation_benchmark.R \
  "$season" exact318-long-run \
  >> "$SPATIAL_EXACT_CONSOLE_LOG" 2>&1
