# Spatial website export specification

Status: frozen before export. This document and `R/spatial_website_export.R`
must be committed and pushed before the version 1 bundle is generated.

Narayan approved a separate version-three targeted export on 2026-09-06. The
frozen contract in `docs/SINGLE_DESTINATION_CAP_V3_PLAN.md` governs that work.
It publishes beside the immutable version-one and version-two bundles.

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
then publishes the first build by one directory rename. `verify` independently
rechecks the published JSON against all source values and the atomic completion
hashes without writing files.

The first attempted run after the schema freeze could not create its ignored
cache directory because the task sandbox did not grant write access to the
relocated repository. It stopped before producing a bundle. A pre-export
infrastructure correction now requires successful lock and staging-directory
creation explicitly; it does not change the schema or any analytical value.

The exporter must verify all frozen source hashes, reproduce exported values
within `1e-12`, parse all JSON, resolve every index path, and reject invalid
probabilities, intervals, duplicate keys, median-gain names, private paths,
shot/game identifiers, posterior draws, fits, or logs. It stops before
publication if any individual file reaches 90 MiB or the bundle exceeds 50 MiB.
The static website will load `players.json`, then fetch only the selected
player's file. Portfolio integration is a later, separately approved task.

## Verified bundle

Version 1 was generated from pushed pre-export commit `f35b2bd`. The source
audit, two independent builds, source-value reproduction at `1e-12`, JSON
parsing, eligibility/null checks, and file-hash comparison all passed. The
published bundle contains 320 JSON files: one manifest, one 318-player index,
and 318 player files. It contains 49,608 heatmap cells and 1,908 slider rows.
Exactly 122 players have scores and gains; 196 have the required null values.

The index is 76,423 bytes. The complete bundle is 19,846,371 bytes (18.93 MiB),
the median player file is 61,921 bytes, the largest player file is 62,391
bytes, and the largest file overall is the 76,423-byte index. These are well
below the frozen stop thresholds.

The publishing process created an atomic completion marker with hashes for all
320 files. The task runner returned before its final console line and cleanup,
leaving an ignored stale lock, but the already-published completion marker and
bundle passed an independent read-only verification. The marker's file hashes,
counts, and deterministic-build flag are valid. Two optional size-summary
fields in that ignored marker were blank because its size vector had lost file
names; `verify` now computes those labels correctly from the hashed bundle.
This correction changes no JSON field or analytical value.

The analytics repository is ready for a separately approved static-site
integration. No portfolio repository was accessed or modified during export.

## Approved targeted version two

Narayan approved a second export that replaces proportional source removal with
the frozen targeted weak-location rule. Version two does not alter version one,
refit a model, or change the destination evidence rule. Its root is
`export/spatial-shot-selection/v2`, with a manifest and a season namespace at
`seasons/2025-26`. The season directory contains the 318-player index and one
file per player. This layout can accept four more season directories later;
the current release contains only 2025-26.

Each player file retains the 156-cell production CAR heatmap and adds the
de-identified historical shot chart allowed by the repository's narrow public
website exception. Shot records contain coordinates, made or missed status,
movement order, and hypothetical destination coordinates. They contain no game,
event, date, opponent, score, context, or private row identifiers.

The exporter calculates requested and actual relocated shares separately,
permits a fractional final attempt, and leaves scores and gains null when fewer
than two destinations pass the existing 10-attempt and 90%-certainty rules. It
builds the complete bundle twice, compares every SHA-256 hash, and publishes by
one directory rename only after counts, ordering, source ranking, mass,
destination, interval, null, and shot-total checks pass.

The verified targeted bundle contains 320 JSON files and occupies 56,847,516
bytes. It contains one 318-player season index, 318 player files, 194,987 shot
records, 49,608 heatmap cells, and 1,908 slider rows. Exactly 122 players have
targeted scores and gains; 196 retain shot charts and heatmaps with null result
fields. The manifest SHA-256 is
`7dc2a65df883d458b198b763d3072f067cff9ea5997c95e55f6748607925595c`.
The season-index SHA-256 is
`1a267881b46bf2de41ca46152c6374ed96832c807ce8ba65d7a51e560abda4b6`.

The initial complete staging build stopped during player-index validation
because mixed score values and JSON nulls remained a list rather than a table.
The recovery preserved all 318 player payload bytes, generated the corrected
index and manifest twice, matched every file hash, and published the first
verified recovery build. The independent verify mode matched the completion
hashes, payload inventory, counts, ordering, null handling, approved shot-field
allowlist, and destination restrictions.

## Verified capped version three

Version three publishes the approved single-destination evidence states and
universal 50% destination cap beside versions one and two. Its season-ready
layout contains one manifest, one 318-player index for 2025-26, and 318 player
files. `docs/SINGLE_DESTINATION_CAP_V3_PLAN.md` records the full method,
verification results, hashes, distributions, and recovery history.

The bundle contains 320 JSON files and 57,418,128 bytes. Its manifest SHA-256 is
`521a4fe25638464bfe7625552ad95535f25dc395c7337df7fb56848e6428ce58`;
the season-index SHA-256 is
`851db0d10d75691a69d1c9daf9030504e714fc04d2df4e82b22fe58323669dfa`.
Independent verification found 29 zero-support, 167 single-support, and 122
multiple-support players. It publishes relocation estimates for 276 players;
13 single-support players have no positive capacity under the cap and retain
null gains and scores.
