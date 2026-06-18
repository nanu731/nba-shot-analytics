# NBA Shot Analytics — Project Brief for Claude Code

## Project goal
Evaluate NBA players' shot tendencies vs. shot efficiency to determine whether
players mostly take the shots they are actually best at.

## Core question
Are players shooting from zones where they are efficient,
or are they over-relying on zones where they struggle?

## Tech stack
- Python 3.11 via Anaconda (env name: nba-analytics)
- Jupyter Notebook (notebooks live in /notebooks)
- Libraries: nba_api, pandas, numpy, matplotlib, seaborn, plotly, scipy, tqdm
- Version control: GitHub

## Folder structure
nba-shot-analytics/
├── data/
│   ├── raw/          # Raw API pulls
│   ├── processed/    # Cleaned DataFrames
│   └── cache/        # Cached API responses (avoid re-fetching)
├── notebooks/        # All Jupyter notebooks
├── src/
│   ├── court.py      # Reusable court drawing utilities
│   ├── metrics.py    # Custom metric functions (eFG%, shot selection score)
│   ├── fetch.py      # NBA API wrappers with caching logic
│   └── viz.py        # Chart helpers (hex bins, zone overlays)
├── outputs/
│   ├── charts/       # Exported PNGs
│   └── reports/      # Summary CSVs and tables
├── requirements.txt
└── README.md

## Notebooks roadmap
01_data_collection.ipynb     — Pull shot logs and player stats from NBA API
02_data_cleaning.ipynb       — Clean coordinates, assign court zones, compute base metrics
03_shot_charts.ipynb         — Hex-bin and make/miss shot charts using matplotlib
04_hot_zones.ipynb           — Zone efficiency grid and hot zone overlay
05_tendency_vs_efficiency.ipynb — Core analysis: frequency vs eFG% per zone, selection score
06_player_comparison.ipynb   — Side-by-side player comparisons and final ranking

## Key metrics
- eFG% = (FGM + 0.5 × 3PM) / FGA
- Points per shot (PPS) per zone
- Shot frequency per zone vs league average
- Shot selection score = Σ(zone_frequency × zone_eFG%)

## Court zones (14-zone NBA model)
Restricted area, paint (non-RA), mid-range left, mid-range center,
mid-range right, left corner 3, right corner 3, above-break 3 (left, center, right),
backcourt

## Coding conventions
- All reusable functions go in src/ — notebooks import from there
- Cache all API responses to data/cache/ before processing
- Minimum 20 attempts before reporting zone efficiency (small sample filter)
- Export final charts to outputs/charts/ as PNG
- Keep notebook cells short and well-commented

## This is a beginner-friendly project
Assume the user is new to sports analytics. Write clear comments in all code.
Explain what each function does and why, not just what the syntax means.