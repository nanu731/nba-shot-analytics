# Location sensitivity results

Study `location_sensitivity_v0.1.0` completed on 2026-09-29 UTC.
The [preregistration](LOCATION_EDITION_SENSITIVITY_PREREGISTRATION.md) defines
the unchanged design; the [runner record](LOCATION_EDITION_SENSITIVITY_RUNNER.md)
documents recovery, equivalence tests and the reporting-memory correction.

## Completion and recovery

Both builds contain all 135 season-condition checkpoints and five season
summaries. Their complete sorted file inventories and SHA-256 hashes match
byte for byte. All five production baselines passed before alternatives.
The study covers 1,507 player-seasons, 27 conditions and six requested shares:
40,689 private player-condition rows and 244,134 private player-slider rows.

The single corrected resume reused 135 first-build conditions, five first-build
summaries, 27 second-build conditions, five draw caches and five baselines.
It calculated only the missing 108 second-build conditions and five summaries.
All 177 earlier atomic checkpoint seals remain unchanged. Model refits,
posterior regenerations and baseline recalculations during this recovery: zero.

Original calculation revision: `52bc0b45d4809a96e743c12976bdf728fe478ac6`.
Reporting correction: `08326d8fd3c7b4de6b322b61d4530e425e5b3f05`.
Execution lock: `7a49935ee9534f5a547208670dfd1df89dcda592`.
The original checkpoint provenance remains intact; the separate correction
audit identifies the later execution code.

The corrected run exited with code 0 after 1,182.96 seconds. Measured CPU was
1,048.71 user seconds and 116.14 system seconds. Maximum resident memory was
3,020,996,608 bytes; peak footprint was 5,320,659,480 bytes (4.96 GiB).
The isolated summary checks peaked at 0.91-1.02 GiB, compared with 15.92 GiB
during the unchanged interrupted resume. The severe reporting-memory problem
did not recur. Resource figures describe computation, not predictive accuracy.

A task interruption occurred after calculation and publication. Recovery found
the completed final-verification record and continued documentation only; it
did not start another calculation. Private logs retain the Arrow/R build-version
notice and the expected nonzero `ps` lookup for the dead prior lock owner.
No numerical, baseline or statistical failure occurred in the corrected run.

## Coverage and achievable relocation

Each range below covers all 27 conditions at the 25% request, without choosing
a preferred condition. Counts use the full eligible population. Baseline means
`A10_E90_C50`. Availability and full-request achievement are different endpoints.

| Season | Eligible | Available: baseline; grid range | Full 25%: baseline; grid range | Cap-limited: grid range |
|---|---:|---|---|---|
| 2025-26 | 318 | 276; 190-317 | 221; 45-305 | 13-273 |
| 2024-25 | 304 | 267; 189-303 | 214; 36-285 | 19-268 |
| 2023-24 | 281 | 234; 169-279 | 199; 38-262 | 19-243 |
| 2022-23 | 292 | 248; 173-287 | 187; 47-268 | 24-245 |
| 2021-22 | 312 | 267; 177-309 | 206; 42-291 | 21-270 |

The median supported-cell count ranges from one to three in each season.
Single-destination counts range from 55-191, 51-189, 53-176, 68-185 and 77-200,
respectively. The complete tables retain all three evidence categories,
availability reasons, transitions, actual movement and receiving-cap summaries
for all six requests. Evidence support does not guarantee enough capacity.

## Gain, score and uncertainty distributions

These are ranges of condition-specific medians among available estimates.
Their contributing players can differ across conditions, so these ranges are
not paired treatment effects or intervals for a common population.

| Season | Gain/100: baseline; grid median range | Score: grid median range | Gain/100 90% interval-width median range |
|---|---|---|---|
| 2025-26 | 12.61; 7.95-13.33 | 89.16-92.81 | 5.36-8.94 |
| 2024-25 | 12.22; 7.53-12.74 | 89.56-93.42 | 5.01-8.95 |
| 2023-24 | 12.93; 7.38-13.28 | 89.23-93.62 | 4.64-8.48 |
| 2022-23 | 11.95; 7.50-12.90 | 89.33-93.51 | 4.75-8.48 |
| 2021-22 | 12.45; 7.61-13.17 | 89.10-93.23 | 4.92-8.54 |

The full output includes season gains, relocated expected points, quartiles,
paired baseline differences and interval widths. Unavailable estimates remain
null with explicit missing counts. Negative paired interval bounds remain in
the output, including a lower bound of about -28.01 points per 100. The score
remains self-relative and does not rank overall player quality.

## Stability, factors and interactions

At the 25% request, evidence category agrees across all 27 conditions for
97/318, 87/304, 79/281, 106/292 and 106/312 player-seasons, newest season first.
Full-request achievement agrees across all 27 for 58, 55, 57, 71 and 63 players.
Availability or gain-interval category changes for 127, 114, 111, 114 and 132.
These are endpoint-specific counts, not a new binary robustness score. Uniform
unavailability is not evidence of benefit. The output retains exact modal and
baseline agreement distributions from 0/27 through 27/27, including tied modes.

For gain/100, the median player-level mean absolute matched contrast ranges
across seasons from 0.11-0.28 for attempts, 0.88-1.28 for posterior evidence,
and 1.56-1.99 for destination cap. Each profile uses available matched pairs;
those populations differ. Under the registered complete-nine-pair attribution
rule, cap has the unique largest contrast for 136, 138, 116, 119 and 117 players.
Another 128, 115, 112, 119 and 135 lack sufficient paired coverage for attribution.
Do not assign a dominant factor to those missing cases.

Capacity effects depend on the evidence rules: across the nine fixed-other-level
contrasts, median signed cap effects range from zero to 4.27-5.11 points per
100, depending on season. Attempt/evidence contrasts also vary with the other
settings. The matched-pair output preserves those interactions and intermediate
grid levels; a single marginal label does not describe the whole grid.

High-volume players retain comparatively broad availability, but achievable
movement still changes. Full-25% counts range from 23-80 of 80, 22-76 of 76,
22-71 of 71, 30-73 of 73 and 25-78 of 78. Membership uses the frozen season-volume
rank rule; it never depends on estimated gain.

## Output, checks and interpretation

`data/processed/location_edition_sensitivity_v0_1/` contains 13 Parquet files,
1,867,105 bytes total: 165,780 aggregate-summary rows, 96,400 stability-summary
rows, and 42 provenance/audit rows. All 27 conditions and six shares remain
available. Private keyed tables, models, draws, logs, locks and authorizations
stay ignored. The public column allowlists and final published hashes passed.

Registered mass, support, cap, fractional-boundary, nesting, interval, null,
outcome-independence, baseline, coverage and determinism checks passed. Published
invalid, impossible, failed and unexecuted case counts are zero. The 40
preregistration checks and 64 execution/correction checks passed before execution.

The conclusions depend on evidence and capacity assumptions. Broader coverage
does not establish greater accuracy, and a higher estimated gain does not justify
changing production defaults. Results describe same-season, location-only
counterfactuals; they omit defensive response, opportunity constraints and game
context. Posterior ranges describe ability uncertainty conditional on the model
and allocation, not causal or coaching effects.

Production v1-v4 export hashes remain unchanged. Context M1, 2026-27, M3,
portfolio and deployment remain untouched. No dependency was added. Any next
feature or production-default change requires separate authorization.
