# NBA Shot Analytics

## Purpose

This repository asks:

> How many additional points could a player score by relocating a limited share
> of shots from weaker locations toward locations where that player has
> demonstrated stronger ability, while preserving shot variety?

The analysis is being redesigned. Treat the plan as living, explain statistics
and code briefly in plain language, and follow Occam's razor.

## Current authority

- Read `docs/SPATIAL_MODEL_PLAN.md` before changing the model.
- `CLAUDE.md`, `ZONE_MODEL_ACCEPTANCE.md`, and `docs/METRIC_REFRAME.md` are
  earlier designs. Use them as evidence, not current model instructions.
- `ASSUMPTIONS.md` is a historical audit log. Do not rewrite old entries.
- Report conflicts between documentation, data, and code.
- Never present a proposed decision as settled.

## Settled direction

- Replace the 10-zone beta-binomial model with a continuous spatial surface.
- Do not use zones in the new model, exports, charts, or website presentation.
- Compare a simple GAM with a Bayesian CAR model on identical data.
- Prefer GAM unless CAR produces a clear practical improvement on unseen shots
  or uncertainty for sparse players.
- Estimate each player's own ability. League information may stabilize uncertain
  estimates, but league-average shooting is not the counterfactual.
- Simulate relocating 0%, 5%, 10%, 15%, 20%, or 25% of attempts.
- Relocate only toward supported personal strengths and spread changes across
  supported strong areas to preserve variety.
- Report estimated points gained per 100 shots and over the observed season,
  with an uncertainty range.
- Treat results as optimistic, location-only estimates. They exclude defensive
  response, actual shot-clock pressure, passes, fatigue, and full game context.
- Define the 0-100 score only after raw relocation results are stable.
- Validate the analytics before integrating them into the portfolio.

## Engineering rules

- Never commit raw NBA shot data. Keep `data/raw/` and `data/cache/` ignored.
- Use Parquet, never CSV, and keep `GAME_ID` as text.
- Pass `season` as an argument. Do not hardcode a season in analysis logic.
- Python handles NBA API collection. R handles analysis, models, charts, and
  export unless evidence justifies changing that split.
- Fail loudly on missing columns, failed joins, unexpected values, or model
  failures. Never silently drop, replace, or coerce data.
- Explain a dependency's specific purpose and get approval before adding it.
- Never export or commit shot-level rows. Only derived aggregates may leave the
  machine.
- Preserve the working zone pipeline until the spatial replacement passes.
  Remove superseded code only as a separate reviewed change.

## Working method

- Make one logical change at a time and verify it.
- Record assumptions, comparisons, and acceptance checks before implementation.
- Test models on games or shots they did not train on.
- Prefer interpretable raw outputs before constructing a composite score.
- Update `docs/SPATIAL_MODEL_PLAN.md` after meaningful modeling decisions.
- At handoff, state what changed, what was verified, what remains open, and what
  is uncertain.

## Existing baseline commands

These run the existing zone pipeline until the spatial pipeline replaces it:

```bash
conda activate nba-analytics
python src/collect.py --seasons 2025-26
Rscript R/run_pipeline.R 2025-26
Rscript R/validation.R
```

Collection is slow. Run it only when raw data is missing.
