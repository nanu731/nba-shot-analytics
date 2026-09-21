# Context Edition M2 historical evaluation runner

Status: `development_1` complete; `development_2`, `development_3`, and the
prospective 2026-27 outcome remain sealed

Protocol: `context_m2_protocol_v0.1.0`

Runner: `context_m2_historical_evaluation_v0.1.0`

## Purpose

The runner will test whether adding one shared nonlinear distance curve to M1
improves future-shot prediction. It prepares three rolling-origin comparisons
without changing M1, M2, the taxonomy, or the canonical data contract.

This document records machinery and rules, not performance. The formal choice is
M2 versus M1. D1 remains useful for interpreting distance, but it cannot select
a model or override the formal comparison.

## Immutable windows

| Comparison | Training outcomes | Validation outcomes | Current access |
|---|---|---|---|
| `development_1` | 2021–22 and 2022–23 | 2023–24 | opened once; aggregate result complete |
| `development_2` | 2021–22 through 2023–24 | 2024–25 | sealed |
| `development_3` | 2021–22 through 2024–25 | 2025–26 | sealed |

The 2026–27 season is not a runner window. A hard season guard rejects it in
every mode. It remains reserved for one prospective confirmation after the
historical development decision.

## Frozen models

M1 is the selected broad-shot-type baseline:

```r
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re")
```

M2 adds only the registered distance smooth:

```r
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re") +
  s(shot_distance_feet, bs = "cr", k = 10, m = 2)
```

Both models use grouped binomial makes and misses, logit link,
`mgcv::gam()`, REML, `optimizer = c("outer", "newton")`, exact
`discrete = FALSE` fitting, `select = FALSE`, `gamma = 1`, `na.fail`, frozen
factor levels, and no dropped unused levels. A player unseen in a training
window receives the fixed-effects prediction with the player random effect set
to zero.

The registered training-only `k = 10` adequacy check is repeated for a newly
fit M2 component. Failure stops the run before validation access; the runner
does not silently change `k`.

## Exact artifact reuse

A fit is reusable only when its file hash, manifest, training seasons, training
partition hashes, grouped dimensions, coefficient dimensions, formula, factor
structure, package environment, convergence state, covariance, and smoothing
parameters match the registered split. A mismatch stops execution. A verified
artifact is never refit.

Frozen reusable fit hashes:

| Window | M1 SHA-256 | M2 SHA-256 | Decision |
|---|---|---|---|
| `development_1` | `a856e98b376cc0a3d5291c6e6599578dbaea04c6cb0aeb1bf6ce83ad0608f7ac` | `5c71318fc300b2f5a77ab41656a69af895a111280f26a1e3fe6035b1259ff43f` | reuse both |
| `development_2` | `17d31cb4c157f31d262f079f1a3703acb0f8cc7de21f9009a691cfca97fa2576` | not fit | reuse M1; fit M2 once later |
| `development_3` | `24bf051f847825bb835fda7025aea119b89b5e9a2a93b252f3a5eeb0b765db4f` | not fit | reuse M1; fit M2 once later |

The completed first-window M2 training checkpoint has input hash
`07c541d645e8336a64f2d2266c52eb9077707cb6dd991d08597731d2429139a1`,
configuration hash
`eada61728298b97d42f5df3edf30a109009d98c3c9d7b8b973fa0fe62247357a`,
and completion-manifest hash
`5a3e3265284bd97d050246adf4d6c0ac5552575ba47490058821f65de5d6ae29`.
Its verification mode passed again during this freeze without refitting.

Fit accounting is split-specific. At freeze time, six formal model-window fits
are required in total: three M1 and three M2. Four already exist and are
reusable; the later two M2 fits have not started. Evaluation itself must report
zero fits.

## Execution order and authorization boundary

The runner supports five modes:

1. `audit` verifies configuration and reusable artifacts without reading a
   validation outcome or fitting a model.
2. `fit <comparison>` fits only a missing M2 training component once, after
   pushed-code and separate-authorization checks.
3. `evaluate <comparison>` verifies both exact fits, then opens only that
   authorized validation season once.
4. `verify <comparison>` hash-verifies a completed atomic result without
   reopening canonical outcomes.
5. `finalize` combines the three original split-specific private prediction
   checkpoints and applies the pooled decision rule without rereading canonical
   outcomes.

Before `fit` or `evaluate`, the runner requires all of the following:

- a 40-character pre-result implementation commit recorded in the frozen
  configuration;
- that commit in current history;
- local HEAD equal to its upstream;
- a clean tracked tree;
- a private, ignored authorization record naming one comparison and the same
  pre-result commit.

The authorization record is intentionally absent now. Creating it requires a
new explicit instruction from Narayan. Therefore the frozen runner cannot open
2023–24 merely because its code has been committed.

## Metrics and decision

Pooled shot-level Bernoulli log loss is primary. Probabilities are clipped to
`[1e-15, 1-1e-15]` only inside logarithms. Every paired difference is M2 minus
M1, so negative favors M2.

Uncertainty uses 2,000 paired whole-game bootstrap samples with seed
`20260914`. Pooled resampling is stratified by validation season: complete games
are sampled within each season, and the same multiplicities weight both models.
The percentile 95% interval and sample standard deviation are recorded.

M2 advances only when all gates pass:

1. M2 has lower pooled log loss.
2. Its improvement is greater than one paired-bootstrap standard error.
3. The lower 95% bound for neither M2-minus-M1 absolute calibration-in-large
   error nor ECE exceeds `0.005`.
4. M2 has lower log loss in at least two of three validation seasons.

A tie, failed check, failed gate, or incomplete comparison retains M1.
Calibration bins, Brier score, AUC, expected-points error, game-total error,
points bias, distance bands, shot-type groups, and player-history groups are
diagnostics only. Expected points are `point_value * make_probability`; they do
not replace log loss.

## Recovery and publication

Fit components, prediction checkpoints, and final results each publish by
renaming a completed staging directory. Their manifests hash every payload and
mark checks complete. Per-stage locks prevent duplicate work.

If a completed result exists, recovery verifies it. If an access marker and a
valid prediction checkpoint exist, recovery resumes from predictions without a
second outcome read or prediction pass. If an access marker exists without a
complete prediction checkpoint, the runner stops for a manual recovery
decision. It never guesses that reopening an outcome partition is safe.

Private fits, shot predictions, outcomes, identifiers, bootstrap draws, logs,
locks, authorizations, and checkpoints live under ignored `data/cache/` paths.
Git receives only configurations, code, documentation, and compact aggregate
tables. No tracked output schema permits shot, game, or player identifiers.

## Verified freeze checks

The outcome-free audit verified the three exact M1 artifacts and the first M2
artifact. It confirmed that the later two M2 components do not exist, all three
validation-access flags are false, no evaluation lock or result exists, and the
prospective flag is false.

Seventeen structural and synthetic tests passed. They cover the windows,
outcome-authorization order, 2026–27 rejection, formulas and settings, sign,
stratified whole-game bootstrap determinism, one-standard-error/calibration/
two-of-three gates, D1 isolation, exact-hash acceptance and mismatch rejection,
interruption recovery, atomic publication, unseen players, taxonomy support,
expected points, and private-output exclusion.

No M1, D1, or M2 model was fit or refit. No 2023–24, 2024–25, 2025–26, or
2026–27 make/miss outcome was loaded. No performance comparison was calculated.

## Measured `development_1` result

Narayan separately authorized `development_1` after the frozen pre-result
commit was pushed. The runner reused the verified M1 and M2 fits, fit no model,
and opened the 2023-24 outcome partition once. The comparison covered 218,700
shots from 1,230 games and 568 players.

M1 log loss was `0.6526580077`; M2 log loss was `0.6441082854`. The registered
M2-minus-M1 difference was `-0.0085497223`, with paired whole-game bootstrap
standard error `0.0003190340` and percentile 95% interval
`[-0.0091846695, -0.0079310758]`. This first window therefore favors M2 on the
primary metric by more than one bootstrap standard error. It is not a final
selection because two registered development windows remain.

M2's absolute calibration-in-the-large error was `0.0053532870`, compared with
`0.0041256001` for M1. Its ten-bin ECE was worse by `0.0087576814`; the paired
95% interval for that difference was `[0.0065030683, 0.0101974740]`. These
calibration diagnostics are limitations, not grounds to change the frozen
models or evaluation rules. M2 improved Brier score by `0.0037916178`, ROC AUC
by `0.0137228310`, and expected-points RMSE by `0.0072533553`, while its
whole-game points MAE was `0.5357043803` higher. Secondary metrics cannot
override the primary rule.

The evaluation took `290.7524` wall seconds and `287.9030` recorded CPU seconds;
the point-in-time post-evaluation RSS sample was 846,118,912 bytes. The paired
bootstrap and its deterministic repeat used `286.1296` seconds. The private
prediction checkpoint is 2.3 MB and its prediction payload SHA-256 is
`65d5d2c18f596063a4c4bd8e379b1fe7829db7a81000b905d81c690086631336`.
The private result checkpoint and tracked aggregate result directory are each
44 KB. Hash verification passed without reopening canonical outcomes.

The only warning observed was the existing environment notice that Arrow
25.0.0 was built under R 4.6.1 while the locked runtime is R 4.6.0; no model was
fit and the evaluation exited successfully. The successful R process left its
empty ignored `development_1` evaluation lock directory behind. It is preserved
as execution evidence and must be handled as an operational recovery issue
before a later outcome-free audit; it does not invalidate the atomic result.

## Next authorization boundary

Stop here. The next action requires Narayan to authorize `development_2`. That
stage must first preserve and resolve the stale private `development_1` lock,
then fit the frozen second-window M2 component once before opening 2024-25.
The 2025-26 and 2026-27 outcomes must remain sealed.
