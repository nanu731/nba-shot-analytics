# Provisional CAR Relocation Plan

**Status:** Planning only. This document does not implement relocation, report
player gains, define a 0-100 score, or change the selected production model.

The final one-time prediction test selected Bayesian CAR, and the verified
all-data production fit now provides a separate 156-cell probability surface
for each of 318 players. Those results are immutable. The next question is how
to use each player's own surface to describe a limited, evidence-supported
change in shot mix without pretending that the model creates real shot
opportunities.

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

## Decisions Narayan must make before implementation

1. **Relocation rule:** approve proportional reallocation with at least two
   destinations, or choose constrained optimization. Recommendation:
   proportional, because it is clearer and makes fewer unsupported assumptions.
2. **Evidence thresholds:** choose the minimum attempts `m` and posterior
   certainty `c`. Practical options are `m = 5` or `10` and `c = 80%`, `90%`, or
   `95%`. Recommendation: `m = 10` and `c = 90%`; this is a moderate evidence
   standard, but it must be approved before gains are viewed.
3. **Variety safeguard:** use only the two-destination minimum and proportional
   weights, or also impose a maximum destination share. Recommendation: start
   without an extra cap, inspect concentration before gain calculation, and
   pre-register a cap only if that audit shows it is needed.
4. **Cell point value:** use the player's observed two/three-point mix within
   each cell or a geometry rule. Recommendation: observed mix, because it
   handles boundary cells and preserves demonstrated shot type.
5. **Displayed uncertainty:** choose an 80%, 90%, or 95% interval.
   Recommendation: 90%, matching the production CAR summaries.
