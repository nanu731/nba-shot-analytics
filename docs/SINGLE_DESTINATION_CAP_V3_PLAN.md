# Targeted Relocation Version Three Plan

**Status:** Narayan approved this specification on 2026-09-06. Commit and push
the analytics implementation and this document before calculating or viewing
any version-three player result.

## Scope and frozen inputs

Version three recalculates targeted relocation, uncertainty, and the
self-relative Shot Selection Score for the same 318 eligible players in
2025-26. It reuses the verified all-data CAR fit and the frozen 4,000 joint
posterior draws with seed `20260902`. The calculation cannot refit CAR or GAM,
change a probability surface, add a player, or read another season.

The production input, CAR fit, surface, and raw shot source must retain these
SHA-256 values:

- production input: `395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6`
- CAR fit: `a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0`
- probability surface: `a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f`
- raw shot source: `20034e6cc2d87cde6fa84a0258ef36fa39e66ee7e461f4889329d67de767a498`

Version one and version two remain immutable. Version three publishes only
under `export/spatial-shot-selection/v3`.

## Evidence status

A destination cell must contain at least 10 observed attempts and at least 90%
of posterior draws must put its expected points per attempt above the player's
current weighted shot mix in the same draw. The calculation assigns one of
three statuses from the number of cells that pass both rules:

- zero: `insufficient_evidence`
- one: `single_destination`
- two or more: `multiple_destinations`

The public label for `single_destination` is `single-destination estimate`.
The calculation sends no relocated mass to a cell that fails either evidence
rule. A player with supported cells but no positive capacity receives null
gains and a null score with `availability_reason` set to
`no_positive_supported_capacity`.

## Source order and feasible relocation

For player cell `j`, `f[j]` is the observed attempt share, `v[j]` is the
observed two-point and three-point mixture, and `p_mean[j]` is the production
CAR posterior-mean make probability. Define `e_mean[j] = v[j] * p_mean[j]` and
`baseline_mean = sum(f[j] * e_mean[j])`.

A source cell must contain observed attempts and satisfy
`e_mean[j] < baseline_mean`. Rank source cells from weakest to strongest
`e_mean[j]`, with ascending production `cell_id` as the exact-tie rule. Remove
mass from this fixed order. Permit fractional removal from the final boundary
cell. The made or missed result of an attempt cannot enter the source order,
the requested amount, the supported set, destination allocation, or marker
destination.

The slider requests `0`, `0.05`, `0.10`, `0.15`, `0.20`, or `0.25` of the
player's attempt mass. For a request `s`, calculate:

1. weak-source capacity as `sum(f[source])`;
2. each supported cell's added capacity as `max(0, 0.5 - f[j])`;
3. total destination capacity as the sum of those added capacities; and
4. `actual_relocated_share` as the minimum of `s`, weak-source capacity, and
   total destination capacity.

The implementation must verify that the frozen production inputs place no cell
in both the supported and weak-source sets. Stop before publication if those
sets overlap, because the registered capacity calculation starts from the
historical supported-cell shares. Record the requested and actual shares for
each slider setting. Any mass above the feasible amount stays in its historical
source cells.

## Universal destination cap and allocation

No destination may receive relocated mass that raises its final attempt share
above `0.5`, allowing only the registered numerical tolerance. For one
supported destination, allocate up to that cell's positive capacity.

For two or more supported destinations, start with weights proportional to
their observed attempt shares. Allocate moved mass in those proportions. If a
cell reaches 50%, remove it from the active set and redistribute the remaining
mass among uncapped supported cells in proportion to their original observed
shares. Continue until the feasible relocated mass is allocated or all
supported capacity is exhausted. The algorithm must produce the same result
for the same inputs and preserve unit mass.

The displayed shot markers must form nested sets across slider values. A
stable source-row order determines which source attempts move. A deterministic
marker sequence based on the feasible 25% allocation assigns historical
coordinates from supported cells and never exceeds a cell's added capacity.
Lower slider settings use prefixes of that sequence. A fractional final attempt
uses opacity to show its fractional mass. Marker rows contain no private
identifier.

## Uncertainty and score

The supported set, source order, capacities, and capped allocation use
posterior means and observed shot shares. Freeze that plan before evaluating
the 4,000 joint CAR draws. Each draw applies the same feasible distribution.
Report the posterior mean and 5th-to-95th-percentile interval for season gain,
gain per 100 attempts, and relocated expected points per attempt.

Use the unchanged score formula at the 25% request:

`100 * baseline expected points per attempt / feasible relocated expected points per attempt`

Calculate the displayed point as the median of the capped `[0, 100]` draw-level
scores and the interval from their 5th and 95th percentiles. A player receives
a score only when the 25% request produces positive feasible relocation.
Zero-support and zero-capacity players retain null score and gain fields. A
single-destination score carries the `single-destination estimate` label.

## Export contract and verification

Schema version `3.0.0` and data version `2025-26-targeted-v3` publish:

- `export/spatial-shot-selection/v3/manifest.json`
- `export/spatial-shot-selection/v3/seasons/2025-26/players.json`
- one `players/{NBA_PLAYER_ID}.json` file per player

The index includes `evidence_status`, support count, relocation availability,
availability reason, and score fields, so the website can label search results
without fetching player payloads. Player files retain the approved v2 privacy
allowlist: coordinates, made or missed status, movement order, and hypothetical
destination coordinates. They exclude game, event, date, opponent, score,
context, and private row identifiers.

Before publication, focused tests must cover zero, one, and multiple supported
destinations; fractional source removal; source or destination capacity below
the request; proportional redistribution after a cap binds; the 50% final-share
limit; outcome-independent movement; slider nesting; and Victor Wembanyama's
verified 1,080-attempt case. The production exporter must build twice and match
all relative filenames and SHA-256 hashes. Independent verification must check
318 players, 194,987 shots, 156 cells and six sliders per player, privacy,
source order, supported destinations, requested and actual shares, mass, caps,
intervals, scores, evidence-specific nulls, and the Wembanyama regression.

## Verified production result

The version-three calculation reused the verified CAR fit and regenerated the
frozen 4,000 joint draws without fitting a model. It retained all 318 players,
194,987 shots, 49,608 heatmap cells, and 1,908 slider rows. Twenty-nine players
have zero supported destinations, 167 have one, and 122 have two or more.

Relocation estimates are available for 276 players. That group contains all 122
multiple-destination players and 154 single-destination players. Thirteen other
single-destination players already used their supported cell for at least half
of their historical attempts, so the universal cap left no positive capacity.
Their gains and scores remain null with
`no_positive_supported_capacity`. Fifty-five available players reached less
than the requested 25% at the largest slider setting because source or
destination capacity ended first. Actual 25% shares ranged from 2.73224% to
25%, with a median of 25%.

Victor Wembanyama retained 1,080 attempts and his one verified supported cell.
The cap permits 243 attempt-equivalents, or 22.5%, which raises that cell's final
share from 27.5% to 50%. His status is `single_destination`. His score is 87.00
with a 90% interval of 85.24 to 88.87. At the 25% request, the model estimates
184.19 season points, with interval 156.45 to 210.93, and 17.05 points per 100
attempts, with interval 14.49 to 19.53. These estimates remain descriptive and
non-causal.

Across the 276 available players, scores ranged from 83.94 to 98.70, with
quartiles 88.51, 89.70, and 91.17. Estimated gain per 100 attempts at the 25%
request ranged from 1.72 to 20.14, with quartiles 10.48, 12.61, and 14.15.
Season gains ranged from 6.30 to 224.47 points. No cell that received relocated
mass finished above 50%; the verified maximum was exactly 50%.

The first production process completed the calculation and wrote one full
staging bundle, then stopped during a source-order audit that tried to recreate
the draw-mean order from a different exported point estimate. The implementation
now checks the draw-mean source order before export. Recovery validated and
copied the complete staging bundle into two byte-identical builds without
regenerating draws or player results, then published one build atomically.

Independent verification matched every frozen source hash, file inventory,
payload hash, player and row count, evidence status, null rule, supported
destination, capped allocation, requested and actual share, slider order,
score, interval, shot count, and privacy restriction. The bundle contains 320
JSON files and 57,418,128 bytes. The manifest SHA-256 is
`521a4fe25638464bfe7625552ad95535f25dc395c7337df7fb56848e6428ce58`.
The player-index SHA-256 is
`851db0d10d75691a69d1c9daf9030504e714fc04d2df4e82b22fe58323669dfa`.
