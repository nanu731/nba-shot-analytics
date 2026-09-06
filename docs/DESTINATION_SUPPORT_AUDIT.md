# Destination Support Evidence Audit

**Status:** Evidence review only. This audit does not change the production
thresholds, CAR model, version-one or version-two exports, portfolio, or live
site.

## Question and frozen inputs

This audit asks why high-volume players can lack enough supported relocation
destinations. It reuses the verified 2025-26 production CAR fit and the frozen
4,000 joint posterior draws with seed `20260902`. It does not fit a model.

The audit matched these production SHA-256 values before calculation:

- production input: `395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6`
- CAR fit: `a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0`
- probability surface: `a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f`
- raw shot source: `20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498`
- v2 manifest: `7dc2a65df883d458b198b763d3072f067cff9ea5997c95e55f6748607925595c`
- v2 player index: `1a267881b46bf2de41ca46152c6374ed96832c807ce8ba65d7a51e560abda4b6`

The regenerated draw means matched the saved surface with maximum difference
zero. The current-rule player results also matched the published v2 status,
supported-cell count, 25% gain, and score values with maximum difference zero.

## Victor Wembanyama trace

The verified player index identifies Victor Wembanyama as NBA player ID
`1641705`.

| Eligibility step | Verified result |
|---|---:|
| Eligible 2025-26 attempts | 1,080 |
| Makes | 553 |
| Misses | 527 |
| Occupied four-foot cells | 93 |
| Cells with at least 10 attempts | 29 |
| Occupied cells with at least 90% certainty above his current mix | 1 |
| Cells passing both requirements | 1 |
| Final supported destinations | 1 |

Cell 20, centered at `(1, 0.75)` feet, is the one supported destination. It
contains 297 attempts, 239 makes, and 58 misses. All 4,000 posterior draws put
its modeled expected points per attempt above Wembanyama's current weighted
shot mix.

Wembanyama has enough direct-use cells. The 90% posterior-certainty gate leaves
only one destination, so the two-destination rule assigns
`insufficient_evidence`. The 5-shot, 7-shot, and neighborhood attempt rules
also leave him with one certainty-qualified destination. His weak-source mass
could supply the requested 25%, but the evidence rule publishes no
relocation, gain, or score while he lacks a second destination.

## Current unsupported players

For this audit, "high volume" means the top quartile of the 318 eligible
players by total attempts. The fixed cutoff is 777 attempts. This definition
produces 80 high-volume players, of whom 32 are unsupported.

All 196 unsupported players have at least three cells with 10 attempts. The
attempt minimum alone does not leave any player below the two-cell requirement.
The rule-by-rule breakdown is:

| Failure reason | All unsupported | High volume |
|---|---:|---:|
| Fewer than two 90%-certainty cells despite at least two 10-shot cells | 158 | 26 |
| At least two cells pass each gate on its own, but fewer than two pass both | 38 | 6 |
| Fewer than two 10-shot cells with at least two certainty cells | 0 | 0 |
| Fewer than two cells under each gate on its own | 0 | 0 |

Twenty-nine unsupported players have zero cells passing both rules. The other
167 have one. Total season volume cannot overcome a rule that evaluates
evidence one location at a time.

## Sensitivity results

Each alternative keeps 90% certainty, two destinations, the targeted weakest
source order, proportional destination allocation, and the 25% request. The
neighborhood rule counts the observed focal cell plus shared-edge CAR neighbors;
it excludes diagonal cells and requires at least one focal-cell attempt.

| Rule | Qualified | Unsupported | Wembanyama | Newly qualified | Newly qualified high volume | Supported destinations, min / median / max |
|---|---:|---:|---|---:|---:|---:|
| Current, 10 focal attempts | 122 | 196 | No | 0 | 0 | 2 / 2 / 7 |
| Alternative A, 5 focal attempts | 149 | 169 | No | 27 | 6 | 2 / 2 / 8 |
| Alternative B, 7 focal attempts | 135 | 183 | No | 13 | 2 | 2 / 2 / 8 |
| Alternative C, 10 neighborhood attempts | 156 | 162 | No | 34 | 6 | 2 / 3 / 9 |

The six high-volume players added by the 5-shot and neighborhood rules are
Karl-Anthony Towns, Shai Gilgeous-Alexander, Payton Pritchard, Jaime Jaquez Jr.,
Stephon Castle, and VJ Edgecombe. The 7-shot rule adds Castle and Edgecombe.

Every qualified player can relocate the full requested 25% under all four
rules. No qualified player runs out of eligible weak-source mass.

| Rule | Largest destination allocation, median / max | Players above 50% | Gain per 100 range | Gain interval width, median / max | Score range | Score interval width, median / max |
|---|---:|---:|---:|---:|---:|---:|
| Current | 69.9% / 96.7% | 109 | 8.81 to 18.89 | 7.52 / 17.81 | 84.89 to 93.36 | 5.77 / 12.88 |
| 5 shots | 72.0% / 98.6% | 129 | 7.99 to 18.89 | 7.85 / 21.29 | 84.89 to 93.56 | 5.96 / 14.48 |
| 7 shots | 69.8% / 96.7% | 117 | 8.81 to 18.89 | 7.85 / 18.09 | 84.89 to 93.36 | 5.95 / 12.88 |
| Neighborhood 10 | 71.5% / 98.6% | 136 | 8.23 to 19.17 | 7.96 / 23.08 | 84.33 to 93.46 | 6.08 / 16.15 |

The concentration column measures the share of moved attempts assigned to one
destination. After combining relocated and retained shots, the largest one-cell
shares stay below 60%. Five current players exceed 50% in one post-relocation
cell, compared with eight under the 5-shot and neighborhood rules and six under
the 7-shot rule.

All qualified 90% gain intervals have positive lower bounds. The alternatives
do not create impossible probabilities or negative point estimates. They do
increase concentration and maximum uncertainty. The widest gain interval under
the neighborhood rule spans 23.08 points per 100 shots for Julian Strawther,
who has two supported destinations.

## Neighborhood evidence reuse

The neighborhood rule can count overlapping evidence twice. Among 156 qualified
players, 59 have at least one destination pair whose neighborhoods reuse at
least 80% of the smaller neighborhood's attempts. Twenty-six of the 77 players
with exactly two destinations meet that overlap diagnostic, and every flagged
pair is adjacent. The maximum overlap is 100%.

Among the 34 newly qualified players, 19 have exactly two destinations. Three
of those players meet the 80% overlap diagnostic: Shai Gilgeous-Alexander at
99.2%, Darius Garland at 82.4%, and Julian Strawther at 80.0%. Sixteen newly
qualified players have at least one supported focal cell with fewer than five
direct attempts. The tested neighborhood rule can therefore satisfy the
two-location safeguard with nearly the same shots twice.

## Recommendation

Keep the current production rule until Narayan approves and audits a revised
neighborhood rule. Lowering the focal-cell minimum to five or seven adds
players, but it leaves the grid-boundary problem intact and does not change
Wembanyama's status. The tested neighborhood rule addresses boundary splitting
and weakens the variety safeguard through overlapping evidence.

The next proposed audit should use the 10-attempt closed neighborhood and count
two destinations only when their contributing cell neighborhoods do not share
an observed source cell. It should retain the 90% certainty threshold and
require focal-cell use. This rule treats shots split across one grid edge as one
evidence area while requiring two distinct evidence areas for relocation. Run
the same concentration and uncertainty checks before adopting it.

## Search normalization specification

The website should display each original `player_name` with accents unchanged.
Search should create two hidden keys for every name and query:

1. Normalize Unicode to NFD, remove combining marks, convert to lowercase,
   replace Unicode punctuation and symbols with spaces, collapse whitespace,
   and trim.
2. Remove spaces from the first key to create a compact key.

Match when either normalized key contains the corresponding normalized query.
Rank prefix matches before contains matches, then use stable alphabetical order.
This makes `luka doncic` match `Luka Dončić` and `nikola jokic` match
`Nikola Jokić`; it also handles apostrophes, hyphens, periods, capitalization,
and repeated spaces.

Append ` (insufficient evidence for relocation)` to unsupported autocomplete
results. Keep the original name unchanged before that suffix.

Do not add a limited-evidence category from this audit. If Narayan later wants
one, define it as exactly one distinct destination evidence area passing the
approved attempt and certainty rules. Use the label `Limited evidence: one
supported relocation area`, and keep gain and score values unavailable.

## Limits and recovery record

Posterior intervals cover uncertainty inside the CAR model. They omit defensive
response, shot creation, fatigue, and game context. The same season supplies
the surface, current mix, and evidence counts.

The first audit attempt stopped before publication because missing gain fields
used the wrong internal names. A pushed correction fixed that initializer. The
next attempt stopped when the Codex app quit and left no result. The completed
run took 91.5 seconds and published eight aggregate or player-level Parquet
files. A post-run check found one shadowed aggregate count; recovery rebuilt
that summary from the verified per-player table without regenerating posterior
draws. The ignored cache preserves both failed locks and the original aggregate
bundle. The final completion checkpoint verifies all corrected output hashes.
