# Context M3: verified pre-shot situation

Protocol `context_m3_protocol_v0.1.0`. Frozen before fitting or outcome access.
Authority: project architecture, M3 predictor-audit results and the retained-M1
decision. This is historical development, not prospective confirmation.

## Question and smallest candidate

Does verified pre-shot game situation improve future field-goal prediction beyond
selected baseline M1?

M1 is unchanged:

```r
cbind(makes, misses) ~ point_value_factor + finish_family + creation_family +
  s(player_id_factor, bs = "re")
```

M3 adds exactly nine fixed-effect coefficients:

```r
cbind(makes, misses) ~ point_value_factor + finish_family + creation_family +
  s(player_id_factor, bs = "re") + period_group + period_minutes_remaining +
  home_away + score_margin_tens + score_margin_missing
```

Period has treatment levels `1`, `2`, `3`, `4`, `OT`, reference `1`; periods
5–10 share OT. Different periods need not have equally spaced effects. Period
time is `(60 * minutes_remaining + seconds_remaining) / 60`, linear on log odds.
Home/away has treatment levels `home`, `away`, `unknown`, reference `home`.
Verified shooter-relative score margin is divided by 10, linear on log odds.
Scaling changes units only, not the model. No distance, coordinates, defense,
shot clock, team/opponent effects, interactions, descriptions or later events.

The only smooth is M1's pooled player random intercept. There is no numeric
smooth, spline dimension or `k` search. Use the unchanged M1 engine: grouped
binomial logit, `mgcv::gam`, REML, outer/newton, default `gam.control`,
`discrete=FALSE`, `select=FALSE`, `gamma=1`, `na.fail`,
`drop.unused.levels=FALSE`, treatment/poly contrasts, one worker. Freeze R 4.6.0,
mgcv 1.9-4, Matrix 1.7-5, arrow 25.0.0, dplyr 1.2.1, tidyr 1.3.2, readr 2.2.0.
Use seed 20260914 and Mersenne-Twister/Inversion/Rejection.

## Missingness and predictor-side adequacy

Missing margin becomes zero only alongside numeric `score_margin_missing=1`.
Observed tied games have margin zero and indicator zero. Missing home/away is
`unknown`. Filled zeros are neutral placeholders, never recovered game states.
PMM does not advance: the completed audit found mainly failed/unavailable event
joins. No imputation study or training-set mean/median replacement is added.

Complete cases mean known home/away AND verified nonmissing score margin. Report
the same saved M1/M3 predictions and frozen metrics on this identical subset,
including sample size and missing-context complement. No extra complete-case fit,
no selection on this subset, and no implication that missingness is random.

Before outcomes, require finite integer period/clock/margins, period 1–10,
seconds 0–59, time 0–720 in regulation and 0–300 in OT; margin verification and
score-sequence agreement; exact taxonomy; full rank of the 20-column fixed
design; all frozen factor levels represented in training; nonconstant numeric
predictors; and score-margin validation range within the training range.
Check the design in bounded chunks, never construct a full player design merely
for sizing. Apply guards to both training and validation predictors.

These checks assess measurement, support and identifiability, not linearity of
make probability. Predictor distributions alone cannot diagnose an outcome
curve. Keep the linear forms if these checks pass. A failed check stops before
fitting/outcomes; document it and request a narrowly justified correction. No
automatic transformation, bin search, smoothing search or outcome-driven repair.

## Inherited evaluation rules (unchanged except M3 replaces M2)

Use `config/context_edition_m2_evaluation_windows_v0_1.csv` verbatim for splits,
partition hashes and immutable M1 artifacts: train 2021–23/evaluate 2023–24;
train through 2023–24/evaluate 2024–25; train through 2024–25/evaluate 2025–26.
Every formal pair uses identical eligible validation shots and games.

Use the M2 preregistration's primary metric, calibration, expected-field-goal
points, whole-game bootstrap, diagnostics and simplicity gates verbatim. The
existing pure helpers are reused without editing them. Differences are M3 minus
M1, negative favoring M3. Primary: pooled shot-level Bernoulli log loss, clipping
inside logarithms to [1e-15, 1-1e-15]. Bootstrap: 2,000 paired whole-game samples
within validation season, seed 20260914, percentile 95% interval and sample SD;
repeat the identical procedure to check determinism, not to enlarge inference.

Calibration: signed and absolute observed-minus-predicted mean, intercept,
slope, ten deterministic equal-count bins, ECE. Material worsening means the
lower paired 95% bound for candidate-minus-M1 absolute bias OR ECE exceeds
0.005. Brier, AUC, shot expected-points RMSE, game-total MAE/RMSE and signed
points bias per 100 remain diagnostic. Preserve the inherited implementation's
sign and grouping conventions; do not reinterpret secondary metrics.

Retain M1 for equal/higher pooled loss, improvement no greater than one paired
SE, material calibration worsening, or improvement in fewer than two seasons.
Failed/incomplete checks retain M1. Secondary/subgroup/complete-case metrics
cannot override these gates. Preserve point-value, taxonomy, training-volume
quartile, returning/unseen-player diagnostics and 200-shot reporting minimum.
Inherited distance bands remain reporting-only diagnostics, never M3 predictors.
No D1 or M2 fit enters the new comparison.

Known players use their training intercept. Unseen players use zero random-effect
deviation and the same fixed terms. `other_or_unknown` stays a genuine taxonomy
level. No reclassification, imputation or silent level dropping.

## Grouping, safety and approval boundary

Group only by the exact model predictors, including missingness indicators.
Makes/misses are sufficient binomial counts; IDs for games/rows are private
alignment/resampling keys only. Do not round clock or margin to improve grouping.
M3 coefficient count is number of training players plus 20; M1 remains players
plus 11. One M3 fit per window, reuse M1. No refit after a failed check.

`R/context_edition_m3_runner.R` supplies outcome-free audit, separately authorized
training-only fit, and hash-only recovery modes. Evaluation is deliberately not
an executable mode in this release. The frozen evaluation adapters and rules are
tested synthetically; validation execution requires its own authorized stage.
No private authorization is created in this task. A later fit must name one
window, exact pre-result implementation hash and `action=fit` in the private
authorization record, with clean pushed code. Validation access is not implied.

Atomic private fit publication requires successful numerical, formula, factor,
covariance, convergence, prediction and determinism checks. Preserve failed or
interrupted staging directories and fit-start markers. Never restart automatically.
The runner refuses an existing incomplete attempt; only an intact completed
checkpoint may be reused. Logs, fits, metadata, access ledgers and predictions
stay ignored. Only aggregate dimensions, checks and declarative hashes may be
published. All M3 validation flags start false. 2026–27 is rejected before any
path construction or read, including predictor preparation.

Runtime and memory figures are planning bounds, not measurements or selection
criteria. Estimate dense design bytes as grouped rows × coefficients × 8;
report a conservative four-matrix working estimate plus 1 GiB. First-window
feasibility needs separate authorization; later windows do not inherit it.
Planning wall-time ranges are 1–8, 1.5–12 and 3–24 hours. They extrapolate the
recorded M1 fits (105/160/275 seconds) to many more grouped rows and allow broad
overhead; they are not runtime ceilings or guarantees. Before fitting, require
physical RAM to exceed the working estimate by 3 GiB and at least 10 GiB free
disk. This operational gate does not change the model. Actual memory pressure
must be monitored during an authorized first fit; no automatic retries.
If resources are impractical, stop and seek an operational decision without
changing the statistical model. No prospective confirmation is authorized.
