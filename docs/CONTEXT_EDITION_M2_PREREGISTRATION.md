# Context Edition M2 nonlinear-distance preregistration

Status: complete frozen design for Narayan's review; no D1 or M2 model has been fitted

Protocol: `context_m2_protocol_v0.1.0`

Foundation: selected M1 at commit `24125f7c38d2189bd7401eda8f8c25a84f46ae10`

Canonical schema: `context_field_goal_v0.1.2`

## Recommendation in plain language

Keep the selected M1 exactly as it is and add one league-wide curved effect of
recorded shot distance. Continue telling the model whether the attempt is worth
two or three points. This lets distance describe how difficulty changes from the
rim to long range without pretending the three-point line is a circular distance
cutoff. Use D1 only to explain how much distance contributes without taxonomy;
the only formal advancement comparison is M2 against M1.

This is the smallest useful next model. It adds one interpretable dimension,
uses an existing stable predictor, and does not become a second spatial model.

## Evidence status

M1 was mechanically selected after qualifying in the 2023-24, 2024-25, and
2025-26 forward comparisons. Its pooled log loss was `0.6511742771`, compared
with `0.6732749661` for M0; the M1-minus-M0 difference was `-0.0221006890`.
The one-standard-error, calibration, and season-breadth gates passed.

Those three outcomes have already been viewed. Although the original ladder
named M2, its exact distance formula was not frozen then. Therefore all three
M2 rolling-origin comparisons are **historical model-development evidence**, not
untouched confirmation. They can decide whether M2 advances, but cannot be
described as prospective evidence. The untouched 2026-27 season is reserved for
one genuinely prospective confirmation and was not accessed or prepared here.

## Central question

> After accounting for point value, pooled player history, and broad creation
> and finish type, does nonlinear shot distance add useful forward predictive
> information about make probability and expected field-goal points?

An M2 win would establish that the frozen distance representation adds broad,
forward predictive information beyond M1 under the registered historical
development splits. It would not establish that moving a player closer causes
better shooting, that distance captures defense or game state, that the model
values complete possessions, or that the result is prospectively confirmed.

## Predictor-only distance audit

The audit selected only season, player, point value, taxonomy, recorded distance,
and coordinates from the five canonical partitions. It did not select make/miss
outcomes. The committed outputs contain aggregates only.

| Check | Result |
|---|---:|
| Seasons | 2021-22 through 2025-26 |
| Predictor rows | 1,091,329 |
| Players across five seasons | 1,017 |
| Missing recorded distances | 0 |
| Missing coordinate pairs | 0 |
| Recorded range | 0-88 whole feet |
| Coordinate-derived range | 0-88.3125 feet |
| Recorded equals floor of coordinate-derived | 1,091,329 / 1,091,329 |
| Mean absolute difference | 0.4794 feet |
| 95th-percentile absolute difference | 0.9401 feet |
| Maximum absolute difference | 0.9997 feet |
| Attempts at 30 feet or longer | 10,794 |

The relationship is stable by season: every row in every season matches the
floor of Euclidean coordinate distance, the average absolute gap is 0.4784 to
0.4809 feet, and every gap is below one foot. Recorded maxima vary from 73 to 88
feet because rare heaves vary, not because the measurement rule changes.

The selected predictor is canonical `shot_distance_feet`, the integer
ShotChartDetail field in whole feet. It is complete, stable, already governed by
the canonical contract, and supports efficient exact grouping. Coordinate-
derived distance adds decimal precision but no independent information: the
recorded field is exactly its floor in this source. No canonical schema change
is needed.

### Three-point boundary and corner geometry

Point value and distance overlap rather than duplicate each other. The audit
found 34,064 three-point attempts at recorded 22 feet in corner-like geometry
(`|x| >= 22` feet), while 4,022 two-point attempts were at least 22 feet and the
longest recorded two was 24 feet. Across the full sample, threes begin at 21
recorded feet and twos extend through 24 feet.

Distance therefore cannot define the three-point line. The point indicator
handles the scoring-rule boundary and its make-probability shift; the shared
smooth handles the common change in difficulty with distance. Expected points
remain:

\[
\widehat{EP}_i = v_i\widehat{p}_i,
\]

where `v` is the known two- or three-point value. This is not a two-dimensional
court model: x and y are audit fields only and never enter a candidate formula.

## Frozen candidates

### M0: existing reference

```r
cbind(makes, misses) ~
  point_value_factor +
  s(player_id_factor, bs = "re")
```

### M1: immutable selected baseline

```r
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re")
```

M1 keeps seven additive finish levels, four additive creation levels,
`other_or_unknown` as the creation reference, and one partially pooled player
intercept. No subgroup finding may revise it.

### D1: non-selection diagnostic

```r
cbind(makes, misses) ~
  point_value_factor +
  s(player_id_factor, bs = "re") +
  s(shot_distance_feet, bs = "cr", k = 10, m = 2)
```

D1 versus M0 describes distance signal beyond point value and the pooled player
baseline. M2 versus D1 describes whether taxonomy retains signal after distance.
D1 cannot be selected or promoted under this protocol, and neither secondary
comparison can override M2 versus M1.

Keeping D1 preserves the useful two-by-two interpretation—without/with taxonomy
and without/with distance—without adding selection complexity. Removing it would
save one diagnostic fit per split but lose the clearest answer to whether
distance and taxonomy each retain descriptive signal.

### M2: only formal candidate

```r
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re") +
  s(shot_distance_feet, bs = "cr", k = 10, m = 2)
```

The primary comparison is M2 versus M1. The smooth is additive and shared by all
attempts and players. M2 stays understandable to a basketball audience: it asks
whether otherwise comparable broad shot types become systematically harder or
easier at different distances.

## Why this nonlinear form

| Form | Meaning and strengths | Decision |
|---|---|---|
| One shared penalized smooth | One flexible league-wide distance curve after point value, player, and taxonomy; corner overlap remains handled by point value | Select: smallest model matching the question |
| Separate two/three smooths | Allows distance difficulty to change differently within twos and threes; this is a point-value-by-distance interaction | Reject for M2: different question, twice the smooth complexity, weaker boundary support |
| Linear distance | One constant log-odds change per foot | Reject: basketball difficulty need not change at a constant rate from rim to heave |
| Fixed distance bins | Easy labels but arbitrary jumps and discarded order within bands | Reject: bands remain diagnostics, not model terms |
| Coordinate-derived decimal distance | More precision but exactly reproduces the source field before flooring | Reject: no independent geometry and much worse grouping |
| Two-dimensional x/y smooth | Models court location, including angle and corner effects | Reject: duplicates the separate Location Edition and broadens the question |

Finish families already contain some distance information—for example, dunks
usually occur near the rim—but they do not encode exact distance. The nested
M2-versus-M1 comparison measures whether distance adds predictive information
after that correlation. It does not claim causal or statistically independent
basketball mechanisms.

## Frozen smooth

- Variable: `shot_distance_feet` in canonical whole feet.
- Basis: one natural cubic regression spline, `bs = "cr"`.
- Initial basis dimension: `k = 10`; the centered smooth contributes nine
  coefficients.
- Penalty: the cubic spline's integrated squared second derivative.
- Smoothing selection: REML, jointly with the player random-effect variance.
- Term selection: `select = FALSE`, `gamma = 1`, no shrinkage basis.
- Identifiability: the usual mgcv sum-to-zero smooth constraint; M1 treatment
  references remain unchanged.
- Knots: none supplied. mgcv places ten knots evenly through ordered training
  covariate values. The natural spline has zero second derivative at its two end
  knots.
- Range guard: canonical values must be integer and within 0-100 feet. Each
  validation predictor range must also lie inside that split's observed training
  range before outcomes are opened. Otherwise stop; do not extrapolate.
- Missing distance: stop. Do not impute or silently drop rows.
- Heaves: retain every valid distance, including 30-plus feet. Do not cap,
  winsorize, or downweight them.

The training-only `k` check uses `mgcv::k.check(subsample = 5000, n.rep = 400)`
under seed `20260916`. Refit exactly once at `k = 20` only when both conditions
hold: distance EDF is at least `0.95 * (k - 1)`, and `k-index < 0.9` with
`p < 0.05`. This conjunction prevents a random low p-value alone from changing
the model. If the `k = 20` fit still meets both failure conditions, stop before
validation; do not try more values. No validation metric may select `k`.

## Engine and predictions

Use the existing `mgcv::gam()` workflow with R 4.6.0 and mgcv 1.9-4:

```r
mgcv::gam(
  formula = MODEL_FORMULA,
  family = stats::binomial(link = "logit"),
  data = training_counts,
  method = "REML",
  optimizer = c("outer", "newton"),
  control = mgcv::gam.control(),
  select = FALSE,
  gamma = 1,
  na.action = stats::na.fail,
  drop.unused.levels = FALSE,
  discrete = FALSE
)
```

The locked package set remains R 4.6.0, mgcv 1.9-4, Matrix 1.7-5, arrow 25.0.0,
dplyr 1.2.1, tidyr 1.3.2, and readr 2.2.0. A version mismatch stops execution.
No dependency is added.

Known players use their training-only random intercept. Unseen players exclude
`s(player_id_factor)` at prediction and receive zero player deviation while
retaining the fixed point, taxonomy, and distance terms. The seven finish and
four creation levels remain fixed; an unsupported future level stops
predictor-only preparation. `other_or_unknown` remains an ordinary level.

The model-matrix allowlist is exact: D1 permits point value, player ID, and
recorded distance; M2 permits those plus finish and creation family. Season and
game identify splits and resampling only. Coordinates, clock, score, home/away,
team, raw text, post-shot fields, defense, and every player interaction remain
blocked.

Fit objects, training aggregates, predictions, access records, and bootstrap
draws remain ignored. Each fit must publish atomically only after formula, input,
support, convergence, finite-coefficient, smoothing, range, level, and prediction
checks pass. A completion manifest hashes input, config, fit, prediction, and
checks. Recovery may reuse only a hash-verified completed stage.

## Exact grouping and computation

D1 groups training shots by player, point value, and recorded distance. M2 adds
finish and creation family to those keys. Within either group all model inputs
are identical, so makes and misses are exact binomial sufficient statistics;
grouping changes the Bernoulli likelihood only by a parameter-independent
combinatorial constant.

| Training through | Players | Shots | D1 rows | M2 rows | D1 coefficients | M2 coefficients |
|---|---:|---:|---:|---:|---:|---:|
| 2022-23 | 700 | 433,942 | 18,396 | 57,190 | 711 | 720 |
| 2023-24 | 808 | 652,642 | 21,636 | 69,649 | 819 | 828 |
| 2024-25 | 913 | 872,169 | 24,951 | 81,746 | 924 | 933 |

Each distance model has two smooth terms and two smoothing parameters: the
player random effect and the distance spline. The distance basis has dimension
10 and contributes nine centered coefficients.

Measured M1 fits took 104.7, 159.7, and 274.6 seconds. Because adding exact
distance raises grouped rows by roughly five to seven times but adds only nine
columns, the planning estimates for M2 are 5-20, 8-30, and 12-45 minutes across
the three windows; D1 is estimated at 2-8, 3-10, and 4-15 minutes. Estimated
peak memory is 1-6 GB and serialized checkpoints are 20-70 MB. These are
structure-based estimates, not benchmarks; runtime never selects a model. The
next execution begins with a training-only timing preflight.

## Historical development evaluation

Freeze three whole-game rolling-origin comparisons:

1. Train on 2021-22 and 2022-23; evaluate 2023-24.
2. Train through 2023-24; evaluate 2024-25.
3. Train through 2024-25; evaluate 2025-26.

All four models use identical eligible shots and games. Existing M0/M1 fit and
prediction artifacts should be reused only when their split, input, formula,
package, and prediction hashes prove statistical identity. Otherwise regenerate
the immutable references before opening that validation outcome. A regenerated
reference is not a model change.

Historical outcomes are read only after all required fits and predictor checks
pass. No result may change formulas, `k`, factors, eligibility, metrics, or the
decision table.

## Primary comparison and uncertainty

The formal comparison is pooled shot-level Bernoulli log loss for M2 versus M1.
Clip probability only inside logarithms to `[1e-15, 1-1e-15]`. Report
`M2 minus M1`; a negative value favors M2.

Use 2,000 paired whole-game bootstrap samples with seed `20260914` and
`RNGkind("Mersenne-Twister", "Inversion", "Rejection")`. Within each validation
season, resample that season's complete games to its original game count, apply
the same multiplicities to both models, then pool the three seasons. Report the
point estimate, bootstrap standard error, and percentile 95% interval.

Calibration repeats the established framework: predicted and observed make
rates, absolute calibration-in-the-large, intercept, slope, and ten deterministic
equal-count probability bins with ECE. M2 is materially worse only if the lower
95% paired-bootstrap bound for M2-minus-M1 absolute calibration error or ECE is
greater than `0.005`. Secondary metrics cannot reverse the primary decision.

Report Brier score and ROC AUC diagnostically. Expected-point diagnostics remain
probability times known point value: shot RMSE, whole-game field-goal-points MAE
and RMSE, and signed points bias per 100 attempts. They translate errors into
basketball units but cannot select M2.

## Fixed diagnostics

Distance bands use recorded whole feet and are not model terms:

- 0 to under 4: restricted/shortest area;
- 4 to under 10: other paint distances;
- 10 to under 22: midrange distances;
- 22 to under 30: three-point distances, acknowledging some long twos;
- 30 or more: long shots and heaves.

Also retain two/three, finish-family, creation-family, `other_or_unknown`,
training-volume quartile, returning-player, and unseen-player summaries. A
subgroup needs 200 validation shots for standalone calibration reporting. Every
subgroup is diagnostic and cannot override pooled selection.

## Mechanical M2 decision

Apply in order:

1. Retain M1 if M2 pooled log loss is equal or higher.
2. Retain M1 if the pooled improvement is no larger than one paired-bootstrap
   standard error.
3. Retain M1 if M2 is materially worse calibrated under the `0.005` gate.
4. Retain M1 if M2 has lower log loss in fewer than two of three development
   seasons.
5. Advance M2 to prospective confirmation only if all four gates pass.

A failure, numerical tie, incomplete fit, range violation, or unresolved sanity
check retains M1 for selection purposes. D1 cannot win.

## Prospective 2026-27 confirmation

M1 always enters the prospective comparison. M2 enters only if it passes every
historical development gate. Before any 2026-27 data access, freeze the final
formulas, package versions, canonical eligibility, hashes, and computation rules;
fit on 2021-22 through 2025-26 complete eligible games.

The primary metric remains M2-minus-M1 pooled shot log loss. Confirmation
requires M2 to improve by more than one paired whole-game bootstrap standard
error without registered material calibration loss. If prospective evidence
disagrees, retain M1 and do not tune or rescue M2. If M2 does not advance from
development, 2026-27 cannot be used as a post-hoc rescue. No formula may be
revised after 2026-27 outcomes are viewed.

## Structural verification

Twenty-one structural and synthetic tests passed. They verified exact M0/M1
preservation; D1/M2 formulas; whole-foot and range guards; missing/impossible
distances; corner-three and longer-two examples; heaves; grouped likelihood;
cubic basis construction, dimension, penalty, and boundary guard; mechanical
`k` escalation; known/unseen players; expected points; frozen factor levels and
`other_or_unknown`; feature allowlists; no x/y or game-context terms;
deterministic splits and bootstrap; decision cases; historical-development
labels; prospective access prohibition; and fixed subgroups. The basis test used
invented predictors and `smoothCon()` only. No response was modeled.

## Scope and interpretation answers

- A single shared smooth adequately answers the intended M2 question: whether
  one-dimensional distance adds average predictive information after M1.
- Separate two/three smooths would answer a different interaction question and
  are not justified by a predictor-only audit.
- Distance overlaps with finish type but does not duplicate exact distance; the
  nested comparison quantifies incremental prediction, not causal separation.
- D1 distinguishes the descriptive value of distance from taxonomy while its
  non-selection status keeps the final choice simple.
- M2 remains interpretable: M1 plus one curved distance adjustment.
- A historical M2 win supports advancement, not untouched confirmation.
- The 2026-27 outcome must remain reserved to test the frozen winner prospectively.
- No smaller model answers both the formal incremental M2 question and the
  distance-versus-taxonomy interpretive concern as clearly.

## Artifacts and unresolved decisions

The configs separately freeze formulas, allowlists, smooth settings, grouping,
metrics, development splits, D1 policy, decision table, subgroups, and the
prospective plan. Aggregate audit and size tables are under
`data/processed/context_edition_m2_preregistration_v0_1`. No shot-level row,
player ID, game ID, outcome, fit, or prediction is committed.

Only one decision remains: Narayan must approve this frozen design before any
training-only preflight or D1/M2 fit. Approval authorizes execution of the
registered design, not access to 2026-27.

## Recommended next execution stage

After approval, implement the private, atomic runner and perform a training-only
timing, convergence, grouping, range, and `k`-adequacy preflight for D1 and M2 on
the first historical training window. Freeze any necessary operational recovery
details before opening a historical validation outcome. Do not fit now.
