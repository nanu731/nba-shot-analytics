# Five-season spatial shot selection production plan

## Status and purpose

This plan was frozen before any earlier-season CAR result was viewed. It extends
the verified 2025-26 v3 release to five separate regular-season analyses. The
model, relocation rules, score, and public-shot privacy contract stay fixed.
The earlier-season outputs are descriptive production analyses that reuse the
CAR specification selected during the 2025-26 evaluation. They do not provide
new evidence that CAR outperforms the GAM in each earlier season.

The verified seasons, newest first, are `2025-26`, `2024-25`, `2023-24`,
`2022-23`, and `2021-22`. Each raw Parquet file has the same 24 columns and the
same types. `GAME_ID` is text in every file.

| Season | Raw rows | In-play rows | Games | Raw players | Eligible players | Eligible shots | Occupied player-cells | Date coverage | Raw SHA-256 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 2025-26 | 219,160 | 219,122 | 1,230 | 582 | 318 | 194,987 | 22,447 | 2025-10-21 to 2026-04-12 | `20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498` |
| 2024-25 | 219,527 | 218,972 | 1,230 | 566 | 304 | 194,526 | 21,598 | 2024-10-22 to 2025-04-13 | `7a956039fd85ecb8207a3ea8ce1d9383a838432c902085e314cf7b06759067fd` |
| 2023-24 | 218,700 | 218,235 | 1,230 | 568 | 281 | 192,608 | 20,292 | 2023-10-24 to 2024-04-14 | `d9f26182a8e49c4cb0d919f0d1a9e8b4320e3b48423f31831846a4e4c9ef7f6f` |
| 2022-23 | 217,220 | 216,761 | 1,230 | 537 | 292 | 192,897 | 20,850 | 2022-10-18 to 2023-04-09 | `f5cb83ce1d8142ceb1e75997967aeb78266adbf2ae006a995ae916441ae90276` |
| 2021-22 | 216,722 | 216,247 | 1,230 | 596 | 312 | 193,577 | 22,280 | 2021-10-19 to 2022-04-10 | `14faa8fdc46d95490f474e863a285116caeac1be97815b1727b518e92916b5f2` |

`In-play` means the shot lies at or below `LOC_Y = 397.5`, matching the frozen
half-court boundary. Eligibility requires at least 20 distinct games and at
least 250 in-play attempts in that season. Seasons are never pooled.

## Frozen production model

Each earlier season receives one independent all-data fit. The runner must use:

- the fixed 40-coordinate-unit, four-foot grid with 13 columns, 12 rows, and
  156 cells;
- the same binary symmetric rook graph, zero diagonal, connected lattice, and
  player-replicated `besagproper2` CAR structure;
- one player fixed intercept, binomial cell makes with attempts as trials, the
  same fixed-effect, precision, and dependence priors, and no extra covariates;
- R-INLA `simplified.laplace`, automatic integration, one thread, `safe = FALSE`,
  and the package-version checks used by the verified production runner;
- 4,000 joint posterior predictor draws with seed `20260902` and the unchanged
  posterior-predictive seed `20260903`.

The deterministic game-fold seed `20260830` remains part of input provenance,
although the production fit uses all five folds. For each season the runner
sorts distinct game IDs, shuffles them with that seed, and assigns folds 1-5 in
order. It derives the eligible player registry from metadata without reading
make or miss, then reads outcomes only after the registry and input hashes are
frozen.

## Frozen relocation and score rules

The v3 targeted calculation remains unchanged. It ranks occupied source cells
from lowest to highest posterior-mean expected points per attempt, with cell ID
as the tie-breaker. Eligible sources fall below the player's current weighted
posterior-mean baseline. The calculation removes mass weakest first, permits a
fractional final source cell, and records requested and actual shares for 0%,
5%, 10%, 15%, 20%, and 25%. Made or missed outcomes never determine which shots
move.

A destination needs at least 10 observed attempts and at least 90% joint
posterior certainty that its expected points per attempt exceed the player's
current mix. Zero, one, or multiple destinations are valid evidence states.
Moved mass starts proportional to existing destination usage and redistributes
when necessary. No destination may finish above 50% of the player's attempts.
The self-relative score remains the median of the draw-level value
`100 * baseline EPPA / feasible targeted-25% EPPA`, clipped to 0-100. Scores and
gains remain null when relocation is unavailable.

## Staged execution and interruption safety

One season-configured runner will replace season-specific copies. It must expose
`audit`, `prepare`, `run`, and `verify` modes and refuse unsupported labels.
`prepare` writes new atomic, ignored input and configuration artifacts and
reports their hashes. Those hashes must be committed before `run` can fit.
Every season has its own directory, directory lock, stage checkpoints, fit,
surface, aggregate QA tables, manifest, and completion marker. A completed
season is verified before the next starts. The 2024-25 season is the pilot;
only after it passes do 2023-24, 2022-23, and 2021-22 run sequentially. A valid
completion marker is reused after interruption. A live lock stops duplicates.

Tests must cover grid construction, eligibility, deterministic folds, season
isolation, relocation states, fractional removal, the 50% cap, nested markers,
null handling, cross-season ID mapping, and outcome-independent movement.
Verification must record shots, games, players, occupied cells, fit status,
warnings, finite probabilities, ordered 90% intervals, distinct player
surfaces, destination-state counts, cap compliance, requested and actual
relocation, score and gain ranges, and public-shot privacy.

## Version-four website contract

The new export is `export/spatial-shot-selection/v4`. It contains a root
manifest, a root cross-season player availability catalog, and one folder per
verified season with a player index and one JSON file per eligible player.
Stable NBA player IDs join seasons. The availability catalog distinguishes:

- `no_recorded_shots`: no row for that player ID in that season;
- `model_ineligible`: recorded shots exist, but the player missed the 20-game
  or 250-attempt threshold;
- `insufficient_evidence`: the player has an eligible CAR surface but no
  supported relocation destination;
- `single_destination` or `multiple_destinations`: an eligible surface with a
  relocation estimate.

The verified `v3/seasons/2025-26` index and player files must be copied into v4
byte for byte. The v4 root files may describe all five seasons, but no 2025-26
player value or serialization may change. Two independent staging builds must
produce identical file lists and hashes before atomic publication.

The existing public-shot exception already covers all five seasons. Player
payloads may contain only court coordinates, made or missed status, the required
point-value-derived fields, and hypothetical relocation coordinates/order.
Player and season identity belong to the containing payload and folder. No game
or event ID, date, opponent, game situation, contextual field, or private row
identifier may be published.
