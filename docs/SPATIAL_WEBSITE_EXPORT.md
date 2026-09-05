# Spatial website export specification

Status: frozen before export. This document and `R/spatial_website_export.R`
must be committed and pushed before the version 1 bundle is generated.

## Purpose and sources

The export is a static, deterministic view of already verified 2025-26
results. It does not fit a model, regenerate posterior draws, rerun relocation,
or recalculate the Shot Selection Score. Its sources are the production CAR
surface, proportional-relocation tables, and Shot Selection Score table.

Relocation point estimates use posterior means. The two public gain fields are
`posterior_mean_season_point_gain` and
`posterior_mean_gain_per_100_shots`; their lower and upper bounds are the
existing 5th and 95th percentiles. No median-gain field or claim is allowed.
The score keeps its separately frozen convention: its displayed estimate is
the median of 4,000 draw-level scores and its interval is the 5th and 95th
percentiles.

## Versioned files

Schema version `1.0.0` and data version `2025-26-v1` publish to:

- `export/spatial-shot-selection/v1/manifest.json` for global metadata and a
  payload inventory;
- `export/spatial-shot-selection/v1/players.json` for the 318-player index; and
- `export/spatial-shot-selection/v1/players/{NBA_PLAYER_ID}.json` for one file
  per player.

Players sort by numeric NBA player ID, slider rows sort numerically, and cells
sort by integer cell ID. Player IDs are JSON strings so browsers cannot change
identifier semantics. Numbers retain R/JSON full practical precision with no
display rounding. Missing public values are JSON `null`; `NaN` and infinity
are forbidden. Object keys and file layout are frozen by the exporter.

The frozen JSON types are:

| Content | Type |
|---|---|
| versions, IDs, names, season, status, method IDs, paths, explanations | string |
| availability and supported-destination flags | boolean |
| cell IDs, attempts, row/column/file counts, byte sizes | integer |
| coordinates, probabilities, interval bounds, slider shares, scores, gains | number or `null` only where stated below |
| player index, sliders, heatmap cells, file inventory | array of objects |
| methods, score, court, grid, counts, loading instructions | object |

All other numeric fields are required and non-null. File hashes are lowercase
64-character SHA-256 strings. Relative paths use forward slashes; filenames
are the decimal NBA player ID plus `.json`.

The global manifest inventories and hashes the 319 payload files: the player
index and 318 player files. It cannot include its own hash because that would
be self-referential. The ignored atomic completion marker hashes all 320 files,
including the manifest.

## Player index and player files

Each index entry contains the player ID, verified name, relative player-file
path, evidence status, score availability, score, and score interval.

Each player file contains identity, season, method versions, evidence status,
observed attempts, posterior-mean baseline expected points per shot, the score
object, six slider objects, and 156 heatmap cells. Slider objects contain the
relocated share, both approved posterior-mean gains, and their verified 90%
interval bounds. Cell objects contain stable ID; center and boundary coordinates
in feet; modeled make-probability mean, median, and 90% interval; attempts;
effective point value where observed; and supported-destination status.

The 122 qualified players have score and gain values. The 196
`insufficient_evidence` players remain in every public index and heatmap, but
their score and every relocation-gain field are `null`. Their baseline expected
points per shot and shooting surface remain available because those are not
relocation claims.

## Court and grid meaning

The basket center is `(0, 0)`. Coordinates are feet: `x` spans -25 to 25 and
`y` increases from the baseline-side edge at -5.25 toward half court at 39.75.
The nominal four-foot grid has 13 columns and 12 rows, or 156 cells. Boundary
cells are clipped to the court limits. Explicit cell boundaries are exported
so a website does not need to reconstruct clipped edges.

## Meaning and limitations

The slider values are 0%, 5%, 10%, 15%, 20%, and 25%. Gains describe the
approved proportional counterfactual using supported destinations; they are
not causal forecasts. The score is self-relative: lower values mean more
modeled room to improve under the frozen 25% scenario. It is not a league rank,
grade, or overall player-quality measure. `insufficient_evidence` means fewer
than two destinations passed the frozen direct-attempt and posterior-certainty
rules, so no gain or score is published.

## Generation and verification

`Rscript R/spatial_website_export.R 2025-26 audit` performs a read-only source
audit. `run` requires a clean tracked tree synchronized with origin, refuses an
existing bundle or partial completion, generates twice in ignored temporary
directories, and requires identical relative filenames and SHA-256 hashes. It
then publishes the first build by one directory rename.

The exporter must verify all frozen source hashes, reproduce exported values
within `1e-12`, parse all JSON, resolve every index path, and reject invalid
probabilities, intervals, duplicate keys, median-gain names, private paths,
shot/game identifiers, posterior draws, fits, or logs. It stops before
publication if any individual file reaches 90 MiB or the bundle exceeds 50 MiB.
The static website will load `players.json`, then fetch only the selected
player's file. Portfolio integration is a later, separately approved task.
