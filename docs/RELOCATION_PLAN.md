# CAR Relocation Plan and Results

**Status:** The frozen proportional relocation calculation completed and passed
verification for the production CAR surface. Results remain descriptive model
estimates. The project has not defined a 0-100 score or started website
integration.

The final one-time prediction test selected Bayesian CAR, and the verified
all-data production fit now provides a separate 156-cell probability surface
for each of 318 players. Those results are immutable. The next question is how
to use each player's own surface to describe a limited, evidence-supported
change in shot mix without pretending that the model creates real shot
opportunities.

## Frozen implementation specification

Narayan approved the first relocation method on 2026-09-04. The implementation
uses the verified all-data CAR production fit and its 4,000 joint posterior
draws; it does not fit a model or run another prediction comparison.

- Slider fractions are exactly `0`, `0.05`, `0.10`, `0.15`, `0.20`, and `0.25`.
- A cell is supported only if the player attempted at least 10 shots there and
  at least 90% of posterior draws put its expected points per shot above that
  player's current-mix expected points per shot.
- A player needs at least two supported cells. Otherwise the status is
  `insufficient_supported_destinations`, and gains stay missing rather than
  being reported as zero or used as an efficiency ranking.
- The supported set is calculated once and is unchanged across slider values.
- The point value in a player-cell is `2 + observed three-point-attempt share`.
  Thus a cell containing only twos is worth 2, one containing only threes is
  worth 3, and a boundary cell uses the player's observed mixture.
- For player `i`, cell `j`, and draw `b`, cell expected points are
  `e[i,j,b] = p[i,j,b] * v[i,j]`. The current-mix level in the same draw is
  `sum(f[i,j] * e[i,j,b])`. This joint-draw comparison preserves uncertainty
  shared across cells.
- If `S[i]` is the supported set, its allocation weights are
  `w[i,j] = f[i,j] / sum(f[i,S[i]])` inside the set and zero elsewhere. At
  slider `s`, the new distribution is `q[i,j] = (1-s)f[i,j] + s*w[i,j]`.
  There is no additional destination cap in version one.
- Each draw's gain is the expected-points difference between `q` and `f`.
  Results report its posterior mean and 5th-to-95th-percentile interval both
  across the player's observed season attempt total and per 100 shots. Negative
  lower interval bounds are retained.

The calculation is registered as `car-proportional-relocation-v1`, uses seed
`20260902`, and is tied to the production fit and completion hashes. It writes
new files atomically and refuses to overwrite or compete with an incomplete
run. Tracked outputs are limited to player-cell support, player evidence status,
six slider rows per player, a concentration audit, calculation notices, sanity
checks, and a method manifest. They contain no posterior draws or shot-level
records.

The first execution attempt stopped before support classification or gain
calculation because a full-lattice posterior-mean vector was evaluated inside a
player-grouped data operation. The correction computes that unchanged vector
before entering the grouped operation. This is an execution-shape fix only: it
does not change a threshold, formula, draw, seed, input, or output definition.
The failed lock is preserved separately, and a corrected pre-result revision
must be pushed before another attempt.

The one authorized recovery execution also stopped before support classification
or gain calculation. A second full-lattice vector, containing the support
probabilities, was still assigned inside that grouped operation. The follow-up
correction completes the same separation: all row-level posterior summaries are
attached before the player-level allocation calculation begins. It also fixes
the names used to place already-computed output hashes into the manifest. No
player result was published, no model was refit, and no approved method rule
changed. Another calculation requires a new explicit authorization.

Before the next production attempt, a deterministic two-player technical smoke
test exercised the corrected grouped-vector operations, both evidence-status
paths, all six sliders, proportional allocation, uncertainty summaries,
concentration diagnostics, manifest hash naming and verification, and atomic
publication. All 17 checks passed. The smoke namespace is separate and marked
as non-production; it loaded no production artifact and called no model-fitting
function.

The single production calculation authorized after that smoke test stopped at
the frozen `attempt_totals_unchanged` check. The largest floating-point
difference between implied relocated and original attempt totals was
`2.04636307898909e-12`, just above the absolute tolerance of `1e-12`. The run
ended in about 62 seconds and published no atomic result or partial output.
This is a numerical acceptance-check failure, not evidence that the CAR model
or relocation method failed statistically. The stale lock and exact error
evidence remain preserved. No automatic retry occurred, and no threshold,
formula, draw, seed, or allocation rule changed.

**Approved numerical amendment, 2026-09-04:** compare each relocated attempt
total with its original total using
`1e-12 * max(1, abs(original), abs(relocated))`. This replaces the fixed
absolute `1e-12` tolerance for that redundant equality check only. It accounts
for floating-point error after multiplying a unit-mass distribution by a
player's attempt count. The unit-mass tolerance and every other verification
tolerance remain unchanged. The code tests exact equality, the observed
`2.04636307898909e-12` rounding difference at the minimum eligible-player
attempt scale, a meaningful mismatch, and non-finite values before it reads a
production artifact. Narayan approved this rule before any relocation result
was published or viewed.

## Verified production relocation result

The one authorized calculation from pre-result commit `4382a19` completed on
2026-09-04 in 101.966 seconds. It used 318 players, 194,987 attempts, 156 cells
per player, the 49,608-row production surface, and 4,000 joint CAR posterior
draws. It did not refit a model or run a prediction test. The atomic completion
checkpoint has SHA-256
`e06f32b9da196feb9692b66c7c821a0bbaa3aa38d3927990c7afda3c6fc045d4`,
and all seven published artifact hashes matched it.

The evidence rule supported relocation estimates for 122 players. The other
196 players had fewer than two destinations meeting both the 10-attempt and
90%-certainty requirements. Their gain fields remain missing, so readers cannot
mistake insufficient evidence for a zero-gain estimate. Each player has one row
for every slider value, for 1,908 rows in total.

The following aggregate table covers the 122 supported players. The interval
columns show the median of the player-specific 90% lower and upper bounds; they
do not form an uncertainty interval for the group median.

| Relocated share | Median season gain | Median gain per 100 shots | Median player lower bound | Median player upper bound |
|---:|---:|---:|---:|---:|
| 0% | 0.0 | 0.00 | 0.0 | 0.0 |
| 5% | 9.7 | 1.41 | 5.2 | 14.2 |
| 10% | 19.3 | 2.81 | 10.5 | 28.3 |
| 15% | 29.0 | 4.22 | 15.7 | 42.5 |
| 20% | 38.7 | 5.63 | 20.9 | 56.6 |
| 25% | 48.3 | 7.03 | 26.2 | 70.8 |

All 47 frozen checks passed. The largest shot-share mass error was
`2.220446049250313e-15`. The largest implied attempt-total difference was
`2.046363078989089e-12`, or `2.207511412070209e-15` relative to its comparison
scale. Unsupported cells received no added share, and supported-cell allocation
matched the player's existing supported-cell proportions with zero recorded
error. Slider zero produced exact zero gains. All reported estimates and 90%
intervals were finite and ordered; no estimated gain had a negative 90% lower
bound. Posterior sampling produced no captured warning or message. R printed the
known Arrow build-version notice at startup.

The concentration audit found no supported player above 50% in one cell at any
slider value. At 25%, the median, 90th-percentile, and maximum largest-cell
shares were 29.3%, 39.6%, and 48.6%. The median effective cell count fell from
23.7 at 0% to 9.54 at 25%. Narayan pre-registered this audit as evidence only,
so these results do not add a destination cap.

The gains assume the player can shift attempts while retaining the modeled
make probability and observed within-cell shot-value mix. They omit defensive
response, shot creation, fatigue, and game context. Treat them as optimistic
location-only estimates rather than promises of added points.

Before publication, the implementation verified 318 players, 156 cells per
player, the frozen production hashes, exact reproduction of the saved posterior
draw means, valid probabilities and intervals, fixed support, proportional
allocation, nonnegative shares, unit mass, unchanged attempts, zero gain at
slider zero, explicit missing results for unsupported players, and consistent
season and per-100 units. The concentration results did not change the frozen
no-cap rule.

## Settled requirements

- The comparison is within a player. Judge a destination against that player's
  own scoring options. League-average shooting plays no role.
- The slider limits the share of attempts that may move: 0%, 5%, 10%, 15%, 20%,
  or 25%. Total attempts never change.
- A destination must contain at least one real attempt by that player. The
  first version cannot invent a new shooting area.
- The CAR posterior uncertainty must distinguish demonstrated ability from a
  high but unreliable estimate.
- Two-point and three-point value must enter expected points.
- The result must preserve meaningful shot variety. Even at the 25% slider
  setting, at least 75% of the real distribution remains in place.
- The first version excludes defender distance, shot clock, fatigue, game
  situation, and whether a relocated attempt could exist.
- Estimated gains describe model output and carry no causal claim.
- Relocation, the slider, and the eventual 0-100 score remain separate stages.

## Two candidate approaches

### 1. Proportional reallocation

Let `f[j]` be the player's real share of attempts in cell `j`, let `r` be the
slider fraction, and let `S` be the supported strong cells. For cells in `S`,
set `w[j] = f[j] / sum(f[S])`; for other cells, set `w[j] = 0`. The proposed
shot share is:

`q[j] = (1 - r) * f[j] + r * w[j]`

In plain language, keep the non-relocated share in its real locations,
then distribute the movable share across proven strong areas in the same
proportions in which the player already uses those areas. This preserves total
attempts, keeps every original area represented, and does not create a new
destination.

This approach is transparent and stable. It does not chase tiny differences
between neighbouring cells, and the largest slider setting still leaves 75% of
every original cell's share in place. Its limitation is that it may reinforce a
strong cell the player uses often rather than finding the theoretical
maximum.

### 2. Constrained optimization

This approach would choose the new cell shares that maximize posterior expected
points while imposing rules such as: move no more than `r`, use only supported
destinations, retain minimum source shares, cap each destination, and keep a
minimum number of active areas.

It can find a higher modeled total, but the answer depends on several
caps that have no natural value in the data. It is also sensitive to small
differences between cell estimates. The method is harder to explain and makes
the result look more achievable than the public shot data can justify.

Unrestricted optimization is not defensible here. Because expected points add
linearly across attempts, it sends every movable attempt to the single cell
with the highest estimate. That produces a one-location specialist, ignores how
defenses and shot availability would change, and overreacts to estimation
noise.

## Recommendation

Use proportional reallocation for the first version. It answers the project
question with the fewest new assumptions and preserves the player's actual shot
identity. Require at least two supported strong destination cells; if fewer
than two qualify, show zero supported relocation for that player and slider
setting. With at least two positive historical shares, proportional allocation
sends some of the movable share to each. Skip an additional destination cap in
the first version.

Before implementation, report the largest destination's share of the moved
attempts as a diagnostic. If that diagnostic reveals unacceptable concentration,
Narayan can pre-register one simple cap and redistribute any excess
proportionally. Do not add a cap after seeing player gain results.

## Supported destinations

A cell must first have actual attempts. Three simple evidence rules remain
possible:

1. **Minimum attempts only.** Require at least `m` attempts. This is easy to
   explain, but attempt count alone does not prove that the cell is a strong
   option and duplicates some work already done by posterior uncertainty.
2. **Posterior certainty only.** Require the posterior probability that the
   cell's expected points per attempt exceed the player's own current-mix
   expected points per attempt to be at least `c`. This measures
   personal advantage, but could admit a cell with very little direct evidence
   if neighbouring cells drive the CAR estimate.
3. **Combination.** Require both at least `m` attempts and posterior certainty
   of at least `c`. This is the recommended rule because it demands direct use
   and evidence of personal advantage.

For posterior draw `b`, define cell expected points as
`e[j,b] = v[j] * p[j,b]`. Here `p[j,b]` is the player's CAR make probability,
and `v[j]` is the cell's point value. The simplest proposed value is the
player's observed two/three-point mix within that cell: `v[j] = 2 + three_share[j]`.
The player's comparison level in the same draw is `sum(f[j] * e[j,b])`. A cell
is strong when it exceeds that personal current-mix level in at least fraction
`c` of the 4,000 draws.

The following table is descriptive only. It uses all-data player-cell attempt
counts and applies no ability filter, gain calculation, or player ranking.

| Minimum attempts | Eligible player-cells | Share of observed cells | Share of attempts retained | Players with 2+ cells | Median cells per player |
|---:|---:|---:|---:|---:|---:|
| 1 | 22,447 | 100.0% | 100.0% | 318 | 73.5 |
| 5 | 10,068 | 44.9% | 87.1% | 318 | 31 |
| 10 | 5,372 | 23.9% | 71.2% | 318 | 15 |
| 20 | 2,047 | 9.1% | 48.2% | 289 | 5 |

This supports considering 5 or 10 attempts; 20 is restrictive before the
posterior-certainty rule removes any additional cells. The table does not by
itself choose `m`. For `c`, 80%, 90%, and 95% are understandable candidates:
80% admits more destinations, 95% demands stronger evidence, and 90% is the
middle choice.

## Variety and point value

Proportional allocation plus the two-destination minimum is the smallest
variety rule. The formula preserves `(1 - r)` of every real cell and divides
the moved share among multiple cells using the player's own history. Audit
concentration before calculating gains. The first version does not need a more
complex optimizer or several simultaneous caps.

Using the player's observed two/three-point mix within a cell is also the
simplest way to respect shot value near the three-point line. A geometry-only
cell label would misclassify boundary cells; treating every cell as either all
twos or all threes would discard real within-cell information.

## Uncertainty in additional points

Use the retained R-INLA posterior configuration to reproduce the frozen 4,000
joint CAR draws. Freeze the supported set and relocation weights from the
approved evidence rule. For each draw, calculate expected points under the real
mix and under the proposed mix, then subtract:

`gain[b] = attempts * sum((q[j] - f[j]) * v[j] * p[j,b])`

The middle and chosen interval of the 4,000 gain values describe uncertainty
about shooting ability under the model. They do not include future defensive
responses, shot creation, game context, or a guarantee that moving attempts
causes the estimated improvement. Show those limitations beside the result;
do not widen the model interval as if it covered them.

## Invented example

Suppose a fictional player's real mix is 50% in **Blue**, 30% in **Green**, and
20% in **Gold**. Blue and Green pass the approved support and certainty rules;
Gold does not. At a 20% slider setting, 80% of the real mix stays put. Allocate
the moved 20% between Blue and Green in their original 5-to-3 ratio: 12.5
percentage points go to Blue and 7.5 to Green. The proposed mix is 52.5% Blue,
31.5% Green, and 16% Gold. Total attempts and all three existing areas remain.
These labels illustrate the rule and are not player results.

## Limitations

- The same season supplies the production surface, support evidence, and real
  shot mix. Posterior uncertainty addresses estimation error inside the CAR
  model; it does not turn this exercise into an out-of-sample or causal test.
- Four-foot cells combine nearby coordinates and can cross the three-point
  boundary. The proposed observed shot-value mix preserves what the player did
  in that cell but cannot say which exact relocated shot would remain a two or
  become a three.
- A player with fewer than two supported strong cells receives no modeled
  relocation. That protects against concentration but can make the slider less
  informative for players with narrow shot profiles.
- Proportional reallocation describes a counterfactual mix. It does not supply
  the play design, spacing, defensive response, or physical opportunity needed
  to create those attempts.

## Approved decisions and remaining roadmap

Narayan approved proportional reallocation, the 10-attempt and 90%-certainty
thresholds, a two-destination minimum, no extra destination cap, observed
two/three-point mixture for cell value, and 90% posterior intervals. Narayan
froze these choices before calculating player results.

The self-relative 0-100 score was pre-registered separately and has now passed
verification. The remaining stages are separate:

1. create compact website-ready exports;
2. review the portfolio integration design; and
3. request Narayan's approval before modifying `portfolio-site`.
