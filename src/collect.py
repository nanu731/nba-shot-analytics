"""Collect NBA shot logs and rosters into the partitioned Parquet store.

The only Python in this project. Everything downstream is R.

Shots are collected one team at a time with player_id=0, which returns that team's
entire season in a single call: 30 calls per season rather than one per player.
Never pass team_id=0 -- it silently caps at 102,400 rows and returns a plausible
half-season with no error.
"""

import argparse
import random
import sys
import time
from pathlib import Path

import pandas as pd
from nba_api.stats.endpoints import commonteamroster, shotchartdetail
from nba_api.stats.static import teams

SEASONS = ["2021-22", "2022-23", "2023-24", "2024-25", "2025-26"]

ATTEMPTS = 3
DELAY = (3.0, 5.0)      # randomized so the request pattern is not metronomic
TIMEOUT = 60

# The one season collected by the abandoned per-player pipeline. Re-collecting it
# through this script must reproduce the count exactly, which is the acceptance test
# for the whole team-based approach.
KNOWN_ROWS = {"2025-26": 219160}

# An 82-game team takes roughly 7,000 to 7,500 field goal attempts. Anything outside
# this is either a short season or a truncated response, and both need a human.
TEAM_ROWS_RANGE = (6300, 7900)
CAP_ROWS = 102400       # the team_id=0 truncation signature

ROOT = Path(__file__).resolve().parent.parent


def sleep_between():
    time.sleep(random.uniform(*DELAY))


def fetch_with_retry(fn, label):
    """Call fn(), retrying on any exception. Raises on the third failure rather than
    returning a short table -- a silent partial pull is the failure mode that would
    corrupt every downstream stage."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return fn()
        except Exception as exc:
            if attempt == ATTEMPTS:
                raise RuntimeError(f"{label}: failed after {ATTEMPTS} attempts") from exc
            wait = random.uniform(*DELAY) * attempt
            print(f"    {label}: attempt {attempt} failed ({type(exc).__name__}), "
                  f"retrying in {wait:.1f}s", flush=True)
            time.sleep(wait)


def cached(kind, season, team_id):
    return ROOT / "data" / "cache" / kind / f"season={season}" / f"team_{team_id}.parquet"


def fetch_team_shots(season, team_id):
    return shotchartdetail.ShotChartDetail(
        player_id=0,
        team_id=team_id,
        season_nullable=season,
        context_measure_simple="FGA",
        season_type_all_star="Regular Season",
        timeout=TIMEOUT,
    ).get_data_frames()[0]


def fetch_team_roster(season, team_id):
    return commonteamroster.CommonTeamRoster(
        team_id=team_id, season=season, timeout=TIMEOUT
    ).get_data_frames()[0]


def collect(kind, season, force):
    """Fetch every team for one season, checkpointing each to data/cache/ so an
    interrupted run resumes without re-fetching."""
    fetcher = fetch_team_shots if kind == "shots" else fetch_team_roster
    all_teams = teams.get_teams()
    frames, fetched = [], 0

    print(f"\n=== {kind} {season} ===", flush=True)
    for i, team in enumerate(all_teams, 1):
        tid, abbr = team["id"], team["abbreviation"]
        path = cached(kind, season, tid)

        if path.exists() and not force:
            df = pd.read_parquet(path)
            src = "cache"
        else:
            df = fetch_with_retry(lambda: fetcher(season, tid), f"{abbr} {season} {kind}")
            path.parent.mkdir(parents=True, exist_ok=True)
            df.to_parquet(path, index=False)
            src, fetched = "api", fetched + 1
            if i < len(all_teams):
                sleep_between()

        flag = ""
        if kind == "shots":
            if len(df) == CAP_ROWS:
                raise RuntimeError(f"{abbr} {season}: {CAP_ROWS} rows, the row cap was hit")
            if not TEAM_ROWS_RANGE[0] <= len(df) <= TEAM_ROWS_RANGE[1]:
                flag = "  <-- outside expected range"
        print(f"  {i:2d}/30 {abbr:4s} {len(df):5d} rows  ({src}){flag}", flush=True)
        frames.append(df)

    combined = pd.concat(frames, ignore_index=True)
    print(f"  fetched {fetched} of 30 from the API, {30 - fetched} from cache", flush=True)
    return combined


def verify_shots(df, season):
    print(f"\n  rows          {len(df):,}")
    print(f"  columns       {len(df.columns)}")
    print(f"  teams         {df.TEAM_ID.nunique()}")
    print(f"  players       {df.PLAYER_ID.nunique()}")

    gid = df.GAME_ID.iloc[0]
    if not isinstance(gid, str) or not gid.startswith("0"):
        raise RuntimeError(f"GAME_ID lost its leading zero: {gid!r} ({type(gid).__name__})")
    print(f"  GAME_ID       {gid!r}, character with leading zero intact")

    if df.TEAM_ID.nunique() != 30:
        raise RuntimeError(f"{df.TEAM_ID.nunique()} teams, expected 30")

    expected = KNOWN_ROWS.get(season)
    if expected is not None:
        delta = len(df) - expected
        status = "MATCH" if delta == 0 else f"DIFFERS by {delta:+,}"
        print(f"  vs known      {expected:,}  {status}")
        if delta != 0:
            raise RuntimeError(
                f"{season} re-collection gives {len(df):,} rows against a known "
                f"{expected:,}. The two collection methods disagree; stopping."
            )
    return df


def verify_roster(df, season):
    print(f"\n  rows          {len(df)}")
    print(f"  teams         {df.TeamID.nunique()}")
    print(f"  players       {df.PLAYER_ID.nunique()}")
    print(f"  per team      {df.groupby('TeamID').size().min()} to "
          f"{df.groupby('TeamID').size().max()}")
    print(f"  POSITION      {sorted(df.POSITION.dropna().unique())}")

    if df.PLAYER_ID.isna().any():
        raise RuntimeError("null PLAYER_ID in roster")
    if df.TeamID.nunique() != 30:
        raise RuntimeError(f"{df.TeamID.nunique()} teams, expected 30")

    multi = df.PLAYER_ID.value_counts()
    multi = multi[multi > 1]
    if len(multi):
        print(f"  on 2+ rosters {len(multi)} players (traded; stage 3 deduplicates)")
    return df


def write_season(df, table, season):
    out_dir = ROOT / "data" / "raw" / table / f"season={season}"
    out_dir.mkdir(parents=True, exist_ok=True)
    # season is carried by the directory name, so it is not a column in the file.
    path = out_dir / f"{table}.parquet"
    df.to_parquet(path, index=False)
    print(f"  written       {path.relative_to(ROOT)}  "
          f"{path.stat().st_size / 1024**2:.1f} MB")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seasons", nargs="+", default=SEASONS)
    ap.add_argument("--what", choices=["shots", "rosters", "both"], default="both")
    ap.add_argument("--force", action="store_true", help="refetch, ignoring the cache")
    args = ap.parse_args()

    for season in args.seasons:
        if args.what in ("shots", "both"):
            df = collect("shots", season, args.force)
            write_season(verify_shots(df, season), "shots", season)
        if args.what in ("rosters", "both"):
            df = collect("roster", season, args.force)
            write_season(verify_roster(df, season), "roster", season)

    print("\ndone", flush=True)


if __name__ == "__main__":
    sys.exit(main())
