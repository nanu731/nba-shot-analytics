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
