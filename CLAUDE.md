# NBA Shot Analytics — Project Brief for Claude Code

## Project goal
Evaluate NBA players' shot tendencies vs shot efficiency to determine 
whether players take the majority of their shots from zones where they 
generate the most points, or waste attempts in zones where they struggle.

## Core question
Are players shooting from zones where they generate high Points Per Shot, 
or are they over-relying on zones where they are inefficient?

## Core metric
Points Per Shot (PPS) — total points generated in a zone divided by total 
shots taken in that zone. Made 2-pointer = 2 points, made 3-pointer = 3 
points, any miss = 0 points. This is the only efficiency metric used 
throughout the project. eFG% is not used anywhere.

## Player pool
All active NBA players from the 2025-26 season with a minimum of 300 total 
shot attempts. Players below this threshold are excluded from all analysis. 
This filter is applied in Notebook 02 and carried through every subsequent 
notebook.

## Court zones
11 standard NBA zones with strict separation at the 3-point line. The 
SHOT_TYPE column from the raw data is used as the final arbiter for whether 
a shot is a 2-point attempt or 3-point attempt at zone boundaries — 
coordinates alone are not sufficient. Corner 3 zones sit at 22 feet, 
above-break 3 zones at 23.75 feet, with the baseline boundary at approximately 
8.95 feet, calculated as the square root of (23.75 squared minus 22 squared) 
per standard NBA court geometry.

## Shot selection score
Each qualifying player receives a single summary score equal to the weighted 
average of their zone PPS values weighted by their shot frequency per zone. 
Formula: sum of (zone frequency x zone PPS) across all zones where the 
player has at least 1 attempt. Every zone with any attempts is included 
regardless of volume — low volume in a zone is itself an analytical signal 
and should not be excluded.

## What is NOT used
Per-shot defender proximity (CLOSE_DEF_DIST) is not available through the 
public NBA Stats API at the individual shot level. Contest level has been 
removed from the project entirely. The analysis is purely spatial. eFG% 
is not used anywhere in this project.

## Tech stack
Python 3.11 via Anaconda (env name: nba-analytics), Jupyter Notebook, 
nba_api, pandas, numpy, matplotlib, seaborn, plotly, scipy, tqdm, GitHub.

## Folder structure
nba-shot-analytics/
├── data/
│   ├── raw/          # Raw API pulls — shots_2025_26.csv
│   ├── processed/    # shots_cleaned.csv and zone_stats_2025_26.csv
│   └── cache/        # Per-player cached API responses
├── notebooks/        # All Jupyter notebooks
├── src/
│   ├── court.py      # Reusable court drawing utility
│   ├── metrics.py    # PPS and shot selection score functions
│   ├── fetch.py      # NBA API wrappers with caching
│   └── viz.py        # Chart helpers
├── outputs/
│   ├── charts/       # Exported PNGs
│   └── reports/      # Summary CSVs and final tables
├── requirements.txt
└── README.md

## GitHub structure
This project uses two branches. The main branch contains the original 
project attempt which used eFG% as the core metric and has since been 
abandoned. All active development happens on the pps-rebuild branch which 
reflects the correct project direction using PPS as the sole metric. All 
new work must be committed to pps-rebuild only. Never commit to main. 
When the project is fully complete and verified, pps-rebuild will be 
merged into main. CLAUDE.md is intentionally excluded from GitHub via 
.gitignore — it lives on the local machine only and should never be 
committed or pushed to either branch.

## Notebooks current state and what needs to happen
Before starting any new work, Claude Code must read every existing notebook 
from top to bottom. For each notebook perform the following checks and 
balances before writing a single new cell.

First identify and flag any cells that reference eFG%, CLOSE_DEF_DIST, 
contest level, or any metric other than PPS — these must be removed or 
rewritten. Second identify any cells with redundant or duplicate logic 
that can be consolidated. Third identify any markdown cells that are 
poorly formatted, incomplete, or do not clearly explain what the 
following code cell does — suggest rewrites for these. Fourth identify 
any hardcoded values that should be constants defined at the top of the 
notebook. Fifth check that all file paths follow the correct project 
folder structure. Sixth check that all imports are consolidated at the 
top of each notebook and no imports are scattered mid-notebook.

After completing the checks and balances review for a notebook, present 
a clear written summary of every issue found and every suggested change 
before touching any cells. Wait for user confirmation before making any 
changes. Then provide all changes as labeled MARKDOWN CELL or CODE CELL 
blocks for the user to paste manually — never edit notebook files directly.

## Notebooks roadmap
Notebook 01 — Data collection: pulls shot logs for all active 2025-26 
players with retry logic, randomized delays, and checkpoint caching. 
Saves combined data to data/raw/shots_2025_26.csv. Considered mostly 
complete but must be reviewed for checks and balances before proceeding.

Notebook 02 — Data cleaning and metric computation: cleans coordinates, 
assigns zones with strict 2pt/3pt separation using SHOT_TYPE as the final 
arbiter, applies 300-shot minimum filter at the player level only, computes 
PPS and shot frequency per player per zone, computes league average PPS per 
zone, includes every zone where the player has at least 1 attempt with no 
zone-level minimum filter applied, saves to data/processed/shots_cleaned.csv 
and data/processed/zone_stats_2025_26.csv. Partially built — must be 
reviewed and rebuilt around PPS only with all eFG% references removed.

Notebook 03 — Shot charts: builds draw_court() in src/court.py, produces 
a make/miss scatter chart and a zone overlay chart using Stephen Curry as 
the test case. The zone overlay chart draws each of the 11 named zones 
as filled polygons colored by PPS, built as a reusable function 
draw_zone_overlay() in src/zones.py so later notebooks can call it for 
any qualifying player. There is no hex-bin chart in this project.

Notebook 04 — Hot zones: zone efficiency grid and hot zone overlay charts 
for any qualifying player on demand, league-wide zone summary. Not yet 
built.

Notebook 05 — Tendency vs efficiency: frequency vs PPS scatter, shot 
selection score computation, full player ranking, mismatch story 
identification. Not yet built.

Notebook 06 — Player comparison and final report: side by side comparisons, 
final rankings table, best and worst shot selector highlights, export all 
outputs. Not yet built.

## Coding conventions
All reusable functions go in src/ and are imported by notebooks. Cache all 
API responses to data/cache/ before processing. Export final charts to outputs/charts/ as PNG at 150 
DPI. Keep notebook cells short and well commented. Never edit notebook 
files directly — always provide MARKDOWN CELL and CODE CELL blocks for 
the user to paste manually. Never use bullet points in responses as they 
do not paste cleanly into the terminal.

## Approach
This is a beginner-friendly project. Write clear comments in all code. 
Explain what each function does and why, not just what the syntax means. 
Always show cells labeled as MARKDOWN CELL or CODE CELL for manual pasting. 
Do not proceed to the next cell until the user confirms the previous one 
is working correctly.