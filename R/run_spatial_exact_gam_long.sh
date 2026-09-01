#!/bin/sh

# Launch the frozen exact full-league GAM with a separate caffeinate guard.
# caffeinate watches this shell's PID; exec preserves that PID for the R runner.

set -eu
umask 077

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: R/run_spatial_exact_gam_long.sh <season> [--audit-only]" >&2
  exit 2
fi

season="$1"
if [ "$season" != "2025-26" ]; then
  echo "The frozen experiment is registered only for 2025-26" >&2
  exit 2
fi

run_mode="exact318-long-run"
cache_dir="data/cache/spatial_gam_exact_full_league_benchmark/season=$season"
unset SPATIAL_EXACT_SMOKE_ONLY SPATIAL_EXACT_SMOKE_RUN_ID
unset SPATIAL_EXACT_SMOKE_DIR SPATIAL_EXACT_SMOKE_LABEL
if [ "$#" -eq 2 ]; then
  if [ "$2" != "--audit-only" ]; then
    echo "The only supported optional mode is --audit-only" >&2
    exit 2
  fi
  run_mode="exact318-launchagent-smoke"
  smoke_run_id="$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
  cache_dir="data/cache/spatial_gam_exact_launchagent_smoke/season=$season/attempt=$smoke_run_id"
  SPATIAL_EXACT_SMOKE_ONLY="1"
  SPATIAL_EXACT_SMOKE_RUN_ID="$smoke_run_id"
  SPATIAL_EXACT_SMOKE_DIR="$cache_dir"
  SPATIAL_EXACT_SMOKE_LABEL="com.narayanlekhi.nba-shot-analytics.exact-gam-smoke"
  export SPATIAL_EXACT_SMOKE_ONLY SPATIAL_EXACT_SMOKE_RUN_ID
  export SPATIAL_EXACT_SMOKE_DIR SPATIAL_EXACT_SMOKE_LABEL
fi

mkdir -p "$cache_dir"
SPATIAL_EXACT_CONSOLE_LOG="$cache_dir/runner_console.$$.log"
export SPATIAL_EXACT_CONSOLE_LOG

/usr/bin/caffeinate -dimsu -w "$$" &
SPATIAL_EXACT_CAFFEINATE_PID="$!"
export SPATIAL_EXACT_CAFFEINATE_PID

exec /usr/local/bin/Rscript \
  R/spatial_gam_aggregation_benchmark.R \
  "$season" "$run_mode" \
  >> "$SPATIAL_EXACT_CONSOLE_LOG" 2>&1
