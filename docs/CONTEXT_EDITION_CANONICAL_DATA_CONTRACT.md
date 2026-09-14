# Context Edition field-goal canonical data contract

Status: frozen for the 2021–22 and 2022–23 M0/M1 preparation stage

Schema version: `context_field_goal_v0.1.2`

Taxonomy version: `context_taxonomy_v0.1.0`

Join version: `shotchart_espn_exact_clock_player_v0.1.1`

## Purpose and boundary

This dataset gives M0 and M1 one trustworthy row per recorded field-goal attempt. It does not reconstruct free throws, fit a model, revise the completed Location Edition, or supply website data.

The build uses 2021–22 and 2022–23 only. The project reserves 2026–27 for prospective confirmation and prohibits this builder from accepting another season list.

## Settled methodology

Narayan approved four rules from the feasibility audit:

1. M0 through M4 use realized field-goal points: zero for a miss, two for a made two-pointer, and three for a made three-pointer.
2. The creation taxonomy assigns a family only from explicit wording. `other_or_unknown` remains a valid category.
3. The project will use 2026–27 for prospective confirmation, so this stage cannot access it.
4. A future M5 audit may consider `pbpstats`. This build does not install or use it.

## Source contract

The primary source is the existing local NBA `ShotChartDetail` Parquet file for each approved season. It supplies the attempt identity, shooter, team, result, point value, clock, distance, coordinates, and raw action label.

The secondary source is the cached hoopR SportsDataverse ESPN play-by-play release for the matching season. It supplies an independent event description, event order, team side, and scoreboard state for auditable unique matches. The secondary source does not replace the primary result or geometry.

The tracked input manifest records relative paths, byte sizes, release years, and SHA-256 hashes. Raw source files remain ignored.

## Canonical row and identifiers

One row represents one `ShotChartDetail` field-goal attempt. The internal key combines season, source game ID, and source event ID. The key and its source fields remain local because they identify a specific event.

The local dataset preserves player and team identity for joins and future grouped splits. Git receives no shot rows, game IDs, event IDs, dates, opponents, or player-level event records.

[`canonical_schema.csv`](../data/processed/context_edition_canonical_v0_1_2/canonical_schema.csv) lists every local field, type, role, requirement, public status, and definition after the verified build runs.

## Target

The canonical row stores three separate target fields:

- `field_goal_made`: zero or one;
- `point_value`: two or three, known from the attempt definition;
- `realized_field_goal_points`: `field_goal_made × point_value`.

M0 through M4 will not attach later free throws. M5 retains the separate restricted shot-trip question.

## Taxonomy

The builder joins raw action labels to the frozen declarative mapping in [`context_edition_taxonomy_v0_1.csv`](../config/context_edition_taxonomy_v0_1.csv). The build stops unless the observed 48-label set matches that file.

The seven finish families are dunk, layup, floater, hook, regular jumper, fadeaway/turnaround, and step-back.

The creation families are drive/cut/roll, pull-up/self-created, putback, and `other_or_unknown`. Driving, cutting, alley-oop, pull-up, step-back, putback, and tip wording provide the supported cues. Generic jumper, running, hook, turnaround, and fadeaway wording do not establish creation context.

The raw label remains beside both derived fields. A future provider label such as `Heave Jump Shot` would require an explicit mapping version change; the builder cannot absorb it through a fallback rule.

## Play-by-play join

The builder first crosswalks games by season, date, home team, and away team. It then matches a shot to a field-goal event by crosswalked game, period, displayed minute, exact provider second, and normalized player name. It preserves fractional play-by-play seconds; rounding or truncating them would create false links to whole-second ShotChartDetail records.

Each shot receives one of four statuses:

- `unique_exact`: each source has one row on the event key;
- `ambiguous_candidate`: either source has more than one candidate on that key;
- `unmatched_event`: the game crosswalk exists but no event candidate matches;
- `unmatched_game`: no game crosswalk exists.

The canonical dataset retains all four groups. It records candidate counts and reports result, point-value, coordinate, and score-sequence disagreements as separate aggregate checks.

## Pre-shot score

ESPN score fields describe the state after an ordered event. The builder sorts events by game play number and provider sequence number, then lags both team scores by one event.

The builder independently checks the matched event’s score change. A made shot must add its two or three points to the shooter’s team and zero to the opponent. A miss must change neither score. The builder also requires no observed make/miss, point-value, or coordinate disagreement between providers. It exposes score-before fields only when all checks pass; other rows receive missing score context and a false verification flag.

Period and game clock come from `ShotChartDetail` and remain available for every row. Home/away and score margin require a unique play-by-play match. M0 and M1 do not require play-by-play enrichment.

## Leakage boundary

[`leakage_register.csv`](../data/processed/context_edition_canonical_v0_1_2/leakage_register.csv) classifies each candidate as a pre-shot predictor, outcome, post-shot leakage, ambiguous-timing field, identifier, or unavailable field.

The model feature allow-list excludes make/miss, realized points, raw play-by-play text, play-by-play result, later free throws, rebound result, and final game outcome. The raw description stays in the ignored local dataset for auditing because it can contain the result and an assist.

Shot clock, defender distance, lineup, and a verified transition flag remain unavailable. The project will not manufacture these fields from season summaries or action-label guesses.

## Manual review design

The builder creates an ignored private sample with eight deterministic examples per populated stratum. Strata cover both seasons; makes and misses; two- and three-point attempts; each finish and creation family; rare labels; ambiguous and unmatched joins; close-clock collisions; and-one candidates; unusual descriptions; and coordinate or point-value disagreements.

The tracked review summary contains only stratum counts, checks, pass totals, failure types, and whether the review changed a rule. It cannot contain event keys, names, dates, or descriptions.

An empty heave stratum is evidence for these seasons, not a reason to invent examples. The reviewer records the absence and examines any other unusual descriptions that the source supplies.

## Required checks

The build stops for a failed required check. Checks cover:

- the exact two-season input and expected 1,230 games per season;
- 216,722 and 217,220 source attempts;
- unique internal and source keys;
- valid outcomes, point values, geometry, period, and clock values;
- complete raw labels and complete frozen taxonomy joins;
- consistent `other_or_unknown` indicators;
- an empty intersection between allowed predictors and leakage fields;
- no later-season or 2026–27 input;
- identical canonical rows across two clean in-memory builds;
- byte-identical tracked aggregate bundles across two serializations.

The exact join must also reproduce the feasibility audit's 191,079 unique matches in 2021–22 and 194,530 in 2022–23. This regression check prevents a clock conversion from inflating coverage.

The aggregate manifest hashes each tracked payload. The ignored local completion manifest hashes the canonical Parquet file and private manual-review sample. The builder writes the completion manifest last and renames the completed directory into place as one atomic publication.

## M0 and M1 readiness gates

M0 can receive a `go` only if the field-goal outcome, point value, finish mapping, keys, and leakage checks pass for every row.

M1 can receive a `go` only if M0 passes, the creation mapping covers every row, the explicit cues survive manual review, and `other_or_unknown` remains unchanged when the sources lack evidence. High play-by-play coverage supports future context models but does not control M0 or M1 readiness.

Neither decision authorizes model fitting. The next task must pre-register the model inputs, splits, metrics, and acceptance rules before M0 or M1 runs.

## Storage and reproducibility

The ignored canonical namespace is `data/cache/context_edition_canonical/context_field_goal_v0.1.2/`. It contains the Parquet dataset, private review sample, and completion manifest.

The tracked aggregate namespace is `data/processed/context_edition_canonical_v0_1_2/`. It contains schemas, mappings, manifests, coverage, join results, leakage checks, review summaries, quality checks, and readiness decisions.

The rejected `v0.1.0` and `v0.1.1` attempts remain preserved and ignored. Version 0.1.0 truncated fractional play-by-play seconds. Version 0.1.1 corrected the join but exposed score-before context without rejecting observed point-value or coordinate disagreements. The project must not use either attempt.

Run the frozen build from the repository root with:

```bash
Rscript R/context_edition_build_canonical.R --seasons=2021-22,2022-23
```

The script refuses to overwrite a completed namespace or proceed through a lock for the same schema version. A failed run keeps its lock and partial namespace for recovery review. A successful run clears its versioned lock after atomic publication.

## Known limits

The ESPN archive is an independent provider, not official ground truth. Player-plus-clock linkage leaves some attempts ambiguous or unmatched. Scoreboard corrections can make an otherwise unique event fail the pre-shot score check.

The finish taxonomy remains provisional pending provider-definition or video review. The creation taxonomy cannot identify spot-up, transition, or post attempts from the available shot-level fields. Box-score reconciliation remains unfinished.

These limits narrow the claims that M1 can support. They do not justify filling missing context with assumptions.
