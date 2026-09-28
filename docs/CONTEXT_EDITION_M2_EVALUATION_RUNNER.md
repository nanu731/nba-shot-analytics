# Context Edition M2 historical evaluation runner

Status: all three development windows and pooled historical selection complete.
The frozen rule retains M1 because M2 is materially worse calibrated.
The prospective 2026-27 outcome remains sealed.

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
| `development_2` | 2021–22 through 2023–24 | 2024–25 | opened once; aggregate result complete |
| `development_3` | 2021–22 through 2024–25 | 2025–26 | opened once; aggregate result complete |

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
| `development_2` | `17d31cb4c157f31d262f079f1a3703acb0f8cc7de21f9009a691cfca97fa2576` | `f004bf912ef292c8fd1f263ab9766249af6b4b4d3928356e3c889ec078985a8c` | reuse both |
| `development_3` | `24bf051f847825bb835fda7025aea119b89b5e9a2a93b252f3a5eeb0b765db4f` | `a1cf2afe399f04403f52570ae70b75c3127f53abd7ebdcdf1f43c679d4c00bd4` | reuse both; training verification passed |

The completed first-window M2 training checkpoint has input hash
`07c541d645e8336a64f2d2266c52eb9077707cb6dd991d08597731d2429139a1`,
configuration hash
`eada61728298b97d42f5df3edf30a109009d98c3c9d7b8b973fa0fe62247357a`,
and completion-manifest hash
`5a3e3265284bd97d050246adf4d6c0ac5552575ba47490058821f65de5d6ae29`.
Its verification mode passed again during this freeze without refitting.

Fit accounting is split-specific. Six formal model-window fits are required in
total: three M1 and three M2. All six now exist and are reusable. Evaluation
itself must report zero fits.

## Execution order and authorization boundary

The runner supports six modes:

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
6. `supplement <comparison>` reconstructs registered training-volume diagnostics
   from existing private checkpoints without refitting or predicting.

Before `fit` or `evaluate`, the runner requires all of the following:

- a 40-character pre-result implementation commit recorded in the frozen
  configuration;
- that commit in current history;
- local HEAD equal to its upstream;
- a clean tracked tree;
- a private, ignored authorization record naming one comparison and the same
  pre-result commit.

The comparison-specific authorizations remain private. Narayan's attached
repair request authorized `development_3` training and evaluation. After the
execution approval system rejected the first evaluation launch, Narayan supplied
direct chat authorization and confirmed the corrected 64-character M2 hash.
The runner then completed the third-window evaluation under the unchanged rules.

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

### Authorized preregistration-compliance repairs before `development_3`

Predictor support is now checked before creating an outcome-access marker or
reading make/miss values. The separate Parquet read selects only season, player,
point value, finish, creation, and recorded distance. It verifies the frozen
factor levels and the existing distance guard against the saved M2 training
range. The prediction function retains its original guard and behavior.

Training-volume diagnostics now use the registered four training-player
quartiles plus unseen players. Counts are recovered from the verified M1 fit's
grouped makes-plus-misses response. The existing frozen helper sorts by training
attempt count and then player ID, and assigns rank-based groups using
`floor((rank - 1) * 4 / number_of_training_players) + 1`. Ties can cross a
quartile boundary in player-ID order. No validation volume or outcome enters
this assignment, and the diagnostic does not enter model selection.

The `supplement` mode reconstructs only this diagnostic for `development_1`
and `development_2` from verified saved training counts and prediction
checkpoints. It publishes separately labeled aggregate supplements, with source
hashes and zero-fit, zero-prediction, zero-canonical-validation-read audit fields.
It never replaces the original result files or changes their primary,
calibration, expected-points, or game-total results.

Both earlier-window supplements completed using those verified private sources.
Each contains ten rows (five groups for each model), stored separately in
`results/development_1_training_volume_supplement` and
`results/development_2_training_volume_supplement`. First-window validation shot
counts for Q1/Q2/Q3/Q4/unseen are 3,711/14,679/48,397/133,944/17,969; second-window
counts are 3,772/16,874/44,744/135,460/18,677. All five groups exceed the registered
200-shot reporting threshold. In the first window M2 has larger absolute
calibration gaps in each returning quartile and a smaller gap for unseen players.
In the second it has smaller gaps in Q1, Q2, and unseen players, but larger gaps
in Q3 and Q4. These supplemental diagnostics do not alter model selection.
Both audits record zero refits, new predictions, and canonical validation reads;
the original result files remain byte-for-byte unchanged.

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

## Verified initial freeze checks (historical)

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

## Measured `development_2` result

The first attempt stopped before outcome access because the grouped-row check
did not parenthesize its existing inline `if`/`else` expression. R therefore
absorbed the later Boolean checks into the M2 `else` branch and falsely rejected
matching metadata. Repair commit `528d65538e909a18e629f7aa2f3fb6e2daa8c02f`
added only those parentheses and a focused regression test, then was pushed
before 2024-25 was opened. The preserved M2 artifact retained SHA-256
`f004bf912ef292c8fd1f263ab9766249af6b4b4d3928356e3c889ec078985a8c`;
neither M1 nor M2 was refit.

The runner opened 2024-25 once and evaluated 219,527 shots from 1,230 games and
566 players. M1 log loss was `0.6509035230`; M2 log loss was `0.6431333748`.
The registered M2-minus-M1 difference was `-0.0077701483`, with bootstrap
standard error `0.0003353791` and 95% interval
`[-0.0084216476, -0.0071371329]`. The improvement exceeded one standard error.

M1 and M2 absolute calibration errors were `0.0004293000` and `0.0039214602`;
their ten-bin ECE values were `0.0047571077` and `0.0121388468`. The paired
M2-minus-M1 intervals were `[0.0001311615, 0.0043478717]` for absolute error and
`[0.0043734351, 0.0091782846]` for ECE. Because neither lower bound exceeded
`0.005`, the registered material-calibration gate passed, although M2 was
descriptively less calibrated. M2 improved expected-points RMSE by
`0.0066289507`, while its whole-game points MAE and RMSE were worse by
`0.7826944368` and `1.1124742577`; these remain diagnostics only.

Evaluation took `310.5869` wall seconds and `304.9110` recorded CPU seconds.
The post-evaluation RSS sample was 1,139,916,800 bytes. The private prediction
checkpoint is 2.3 MB, its payload hash is
`6950f6172b9cdd2f4683f8a1ed5188993ad71a6af2cbdf137a72c6ced3635ac0`,
and the private and tracked aggregate result directories are each 44 KB. The
frozen verification mode passed without reopening canonical outcomes.

## Resolved authorization boundary before evaluation

Narayan directly authorized using both preserved fits, opening only 2025-26 once,
completing the registered three-window decision, and publishing aggregate
results. A subsequent confirmation corrected an extra trailing character in the
authorized M2 hash. Neither model was refitted. This authorization does not
permit M3 or prospective confirmation; 2026-27 remains sealed.

## Verified `development_3` training and earlier safe stop

Repair commit `da1dfd3a584acca2a65ad6334ec46fc670c9e74c` was pushed and checked
against HEAD, upstream, remote tracking, and GitHub before training. It moved
predictor-support checks before outcome access and restored registered
training-volume quartiles without changing formulas, prediction behavior, or
selection rules. Ninety-two outcome-free tests passed: 21 evaluation tests,
21 M2 protocol tests, 17 training-preflight tests, 21 baseline tests, and 12
first-validation tests. The previous verifier-parentheses regression passed.
After fitting, 12 second-validation, 12 third-validation, and 19 validation-data
preflight tests also passed without real outcome access. Parsing and the compact
audit's agreement with private fit metadata passed; 135 outcome-free tests
passed across these suites.

The earlier-window supplements were committed at
`323884109d0956195762fc233301ba99e4faf685` and
`82cc7850f17c473fa9198220f56c3dede78bc956`. We preserved the previous empty locks
and authorization in an ignored dated archive, verified the moved authorization
hash, and created the authorized private third-window record. We changed no
original evaluation result.

Under execution commit `82cc7850f17c473fa9198220f56c3dede78bc956`, we reused M1
and fitted M2 once on 872,169 shots from 4,920 games and 913 players in 2021-22
through 2024-25. M1 has 12,415 grouped rows; M2 has 81,746 grouped rows and 933
coefficients. The atomic M2 component completed at 2026-09-28 19:43:44 UTC.
Its manifest, fit and metadata hashes passed verification before saved-fit QA.
The compact aggregate audit is `development_3_training_verification.csv` in
the established processed evaluation directory.

M2 reported full convergence, zero fitting warnings, finite coefficients and
covariance, and two positive smoothing parameters: 41.7784590361 for players
and 2.63089515537 for distance. The maximum absolute outer gradient was
0.0308397227. Distance EDF was 7.6139413572; total EDF was 543.8719529304.
The repeated frozen check gave k-index 0.9472851696 and p-value 0. The registered
conjunctive rule retained `k=10` because EDF was below its 8.55 near-ceiling
threshold; this does not mean the isolated k-test p-value was reassuring.

Saved-training probabilities ranged from 0.0046726515 to 0.9497516699.
Repeated predictions were identical, and expected points equaled point value
times probability. The 178-row 0-to-88-foot synthetic grid, 56 taxonomy
combinations, `other_or_unknown`, known-player effects, and unseen-player
zero effects passed. These are numerical checks, not predictive performance.

Fitting took 13,981.1117 wall seconds; component completion took 13,995.4786
seconds. Recorded fitting CPU was 2,737.577 user plus 65.286 system seconds.
Wall time contained substantial gaps in CPU progress, so it is not a continuous
compute-speed benchmark. Post-fit RSS was 1,220,575,232 bytes, not a measured
peak. The object occupied 58,039,816 bytes; its serialized file occupied
28,615,944 bytes. Available disk after completion was 107,554,111,488 bytes.
The frozen package-version checks passed. Arrow reported its existing build
notice (built under R 4.6.1; runtime R 4.6.0). A later sandboxed predictor-only
check also emitted three denied hardware-cache-query notices, then exited 0.

The saved-fit QA and predictor-only 2025-26 support check passed. The latter
selected no outcome column. The execution approval system rejected both
evaluation launch requests before creating a process, including the request
that quoted the attached authorization. It required direct chat authorization;
we did not bypass that denial. Thus the third-window outcome-read, validation
prediction, and bootstrap counts are zero. No access marker, prediction
checkpoint, result checkpoint, or pooled decision exists. The completed M2
artifact and empty inactive fit lock remain ignored and preserved. No model
process remains. The next task must reuse the fit and must not repeat training.

At that earlier stop, the full historical M2 decision was incomplete. M1
remained the selected baseline. The following execution reused the saved fit
after the direct authorization and hash correction; it did not repeat training.

## Measured `development_3` result

Execution commit `0c0a721d77274ca4e92334e6aa882378c8808af7` was identical to
upstream and GitHub before execution. Both supplied fit hashes matched their
manifests. The saved M2 QA passed again; the runner verified both saved models,
configuration, private authorization, prior results, and predictor support
before opening the 2025-26 canonical outcome partition once at
`2026-09-28 21:26:58 UTC`. M1 and M2 refit counts were zero.

The comparison covered 219,160 shots, 1,230 games, and 582 players. M1 log loss
was `0.6499648681705721`; M2 was `0.6433467898036227`. The M2-minus-M1 difference
was `-0.006618078366949387`, paired whole-game bootstrap SE
`0.00029939542742234593`, and percentile 95% interval
`[-0.007179753302567796, -0.00603636076125792]`. The improvement exceeded one SE.
The frozen 2,000 samples and deterministic repeat both used seed `20260914`.

| Diagnostic | M1 | M2 |
|---|---:|---:|
| Observed minus predicted make rate | 0.0072727454 | 0.0076211228 |
| Calibration intercept | 0.0316559163 | 0.0336300983 |
| Calibration slope | 1.0090994970 | 1.0093017411 |
| Ten-bin ECE | 0.0078681887 | 0.0114306283 |
| Brier score | 0.2298219824 | 0.2267310351 |
| ROC AUC | 0.6431525770 | 0.6534720226 |
| Shot expected-points RMSE | 1.1818826105 | 1.1764054722 |
| Whole-game field-goal-points MAE | 13.0958943845 | 13.6339987938 |
| Whole-game field-goal-points RMSE | 16.2827090480 | 17.0298469088 |
| Observed minus predicted points per 100 attempts | 1.5887231995 | 1.5973639159 |

Each equal-count calibration bin contains 21,916 shots. The M2-minus-M1
absolute-bias difference was `0.0003483773`, with paired 95% interval
`[-0.0004859651, 0.0011916652]`. ECE worsened by `0.0035624396`, with interval
`[0.0010894907, 0.0054678177]`. Neither lower bound exceeded `0.005`, so this
window passed the registered material-calibration gate. M2's lower shot-level
log loss and expected-points RMSE do not erase its worse ECE or game-total errors.

Training-volume Q1/Q2/Q3/Q4/unseen groups contained
4,360/21,137/44,397/127,705/21,561 validation shots. M2 had smaller absolute
calibration gaps in Q3 and unseen players, and larger gaps in Q1, Q2, and Q4.
The 197,599 returning-player shots had signed gaps of 0.008664503 for M1 and
0.008902246 for M2; unseen-player absolute gaps were 0.005482223 and 0.004119926.
No validation volume entered quartile assignment.

M2 reduced absolute calibration gaps in four of five distance bands, including
30-plus-foot shots (0.0693614 to 0.0089769), but worsened the 10-to-under-22-foot
gap (0.0014075 to 0.0290917). It improved the three-point gap but worsened the
two-point gap. Finish and creation diagnostics were mixed; `other_or_unknown`
remained explicit with 107,628 shots. All reported groups exceeded 200 shots.
These diagnostics cannot override the pooled selection rule.

Outcome reading took 0.0883 seconds, one prediction pass per model took 4.1241
seconds in total, point metrics took 0.6732 seconds, and the bootstrap plus
deterministic repeat took 289.8714 seconds. Total measured evaluation wall time
was 295.2772 seconds; CPU was 279.194 user plus 8.744 system seconds. Post-run
RSS was 1,394,737,152 bytes (a sample, not peak), with 106,248,286,208 bytes of
available disk. The private prediction payload is 2,395,084 bytes, SHA-256
`3556892daaeec4d72b5f72cc34568a007528ea7ad30e76f42f9632aaf980f375`.
Private and tracked aggregate result directories each occupy 44 KiB on disk.

All 14 execution checks passed. The frozen recovery verifier rechecked the
atomic result without reopening outcomes or predicting again. Models,
predictions, authorization, access records, and inactive locks remain ignored;
only aggregate tables and documentation are published. The existing Arrow
build-version notice was the only warning reported by evaluation and recovery.
The runtime and dependencies remained frozen. Location Edition, portfolio,
2026-27, and M3 were untouched.

## Frozen three-window historical decision

The unchanged `finalize` mode hash-verified the three private result and
prediction checkpoints, combined 657,387 unique shots from 3,690 games, and ran
2,000 season-stratified paired whole-game bootstrap samples plus an identical
repeat. It read no canonical outcome partition and fitted no model. All five
pooled checks passed, including row uniqueness, bootstrap determinism, D1
exclusion, and the prospective seal.

| Window | M1 log loss | M2 log loss | M2 minus M1 |
|---|---:|---:|---:|
| 2023-24 | 0.6526580077 | 0.6441082854 | -0.0085497223 |
| 2024-25 | 0.6509035230 | 0.6431333748 | -0.0077701483 |
| 2025-26 | 0.6499648682 | 0.6433467898 | -0.0066180784 |
| Pooled | 0.6511742771 | 0.6435288572 | -0.0076454199 |

The pooled paired-bootstrap standard error is `0.00018135102618663278`.
M2 passed the log-loss and one-SE gates and improved log loss in all three
seasons. However, it failed the registered material-calibration gate. The
frozen decision is **retain M1**, with reason `M2 is materially worse calibrated`.
Pooled M2-minus-M1 absolute calibration error increased by `0.0016907377033295815`
and ECE increased by `0.006980480467932546`.

The frozen publisher retained the decision and standard error but did not save
the numerical pooled intervals. One additional reporting-verification pass used
the same hash-verified saved predictions, unchanged bootstrap helper, 2,000
samples, and seed. Its standard error matched the published value to the
`1e-14` comparison tolerance, and the frozen selection function returned the
identical model and reason. This was not a new analysis or a larger bootstrap;
the original decision files remain unchanged. A separate aggregate
`pooled_reporting_verification.csv` records the recovered summaries.

| Pooled M2-minus-M1 quantity | Difference | Bootstrap SE | 95% interval |
|---|---:|---:|---|
| Log loss | -0.0076454199 | 0.0001813510 | [-0.0079871425, -0.0072691795] |
| Absolute calibration error | 0.0016907377 | 0.0002579125 | [0.0012050559, 0.0021921232] |
| ECE | 0.0069804805 | 0.0006408037 | [0.0057229897, 0.0082350598] |

The ECE lower bound exceeds the frozen `0.005` margin; the absolute-bias lower
bound does not. Pooled absolute calibration errors are 0.0039404590 for M1 and
0.0056311967 for M2. Pooled ECE values are 0.0054763204 and 0.0124568009.
These pooled equal-count-bin calculations are not averages of season-specific
ECE values. The reporting pass took 667.3886 wall seconds and 646.695 user plus
7.345 system CPU seconds. It performed zero canonical reads, fits, or predictions.

Distance helped predict individual makes and misses, but M2 did not satisfy the
registered probability-calibration requirement. This is a historical model
selection result. It does not make M1 superior on log loss, establish causality,
or provide prospective confirmation. The frozen protocol does not permit using
2026-27 to rescue M2 after failed historical advancement.

The original aggregate results and earlier-window supplements remain unchanged.
The private pooled checkpoint and matching tracked aggregate directory each
occupy 16 KiB on disk. Its three payload hashes and five checks passed. The
existing Arrow build-version notice remained the only reported warning. The
frozen publisher does not record separate pooled runtime or peak memory; those
measurements are unavailable, not zero.

Execution accounting is explicit: third-window prediction ran once per model;
the third-window bootstrap ran once plus its deterministic repeat; pooled
selection ran once plus its deterministic repeat; the omitted pooled summaries
required one further identical reporting pass. Each bootstrap pass contained
2,000 replicates, not a combined 10,000-replicate inference. Recovery hash checks
performed no fitting or prediction. The 21 frozen evaluation structural and
synthetic tests passed again after evaluation, without loading real outcomes.

The configuration's `FALSE` access fields describe the original pre-result
freeze. Current access is recorded by private access markers and execution
manifests: each historical M2 validation partition was opened once, and 2026-27
was never accessed. Do not revise the frozen configuration to overwrite history.

## Next authorization boundary

Stop after recording this historical decision. No M3 or prospective work is
authorized. Under the current project architecture, the next planned task is a
separately approved Location Edition sensitivity preregistration. Any later
Context M3 audit must start from retained M1 and receive its own authorization;
it cannot silently restore M2's rejected distance term.
