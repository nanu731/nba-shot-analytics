# Context Edition: second rolling-origin validation

Status: second of three retrospective validations completed; M1 passed the 2024–25 season gates, but no final model has been selected

Protocol: `context_m0_m1_protocol_v0.1.0`

## Question and unchanged models

This is a direct replication of the first future-season check. It asks whether the frozen finish and creation categories improve field-goal make and expected-point predictions beyond two-versus-three status and a partially pooled player baseline.

M0 is the registered grouped-binomial `mgcv::gam()` with point value and `s(player_id_factor, bs = "re")`. M1 adds the same seven finish families and four creation families, including `other_or_unknown` as an ordinary level. Both use REML, the registered optimizer, exact non-discrete fitting, stable factor levels, and identical unseen-player handling. No location, distance, clock, score, team, text, interaction, future volume, or other M2-or-later feature is allowed.

## Frozen second split

The expanding training window contains complete 2021–22, 2022–23, and 2023–24 games. The one-time validation season is 2024–25. The 2025–26 outcomes and all 2026–27 data remain analytically sealed.

Outcome-free metadata checks found 652,642 training shots in 3,690 games from 808 players and 219,527 intended validation shots in 1,230 games from 566 players. Training and validation game identifiers do not overlap. The 2024–25 partition SHA-256 is `f3211f4ff35db032f1150b5b3f9fcd0a1eef07d29652f5d694c70658fe4eef27`.

The training window changed, so M0 and M1 will each be fit once under the unchanged specification. Each fit publishes an isolated atomic component before the combined training checkpoint, allowing a completed model to be recovered without refitting if the other fit is interrupted.

## Frozen evaluation and safeguards

The evaluation reuses the first comparison’s code paths and definitions: pooled Bernoulli log loss is primary; differences are M1 minus M0; probabilities are clipped to `[1e-15, 1-1e-15]` only inside logarithms; expected-point, calibration, subgroup, Brier, and rank-AUC summaries remain secondary. Safe double-precision AUC count arithmetic is required.

The paired uncertainty calculation uses 2,000 whole-game bootstrap samples, seed `20260914`, the same games for both models, the percentile 95% interval, and the existing `0.005` material-calibration margin. M1 must lower log loss by more than one bootstrap standard error without triggering the calibration gate to count as a qualifying season-level result.

The complete code, tests, output schema, and split configuration were committed and pushed at `78a44ef0c32dafb06e18c5f5fab0826ffd9394fb` before 2024–25 outcomes were loaded. Immediately before the sole outcome read, the runner creates an exclusive marker containing code, configuration, canonical, partition, and fit hashes. A pre-existing marker or result blocks a fresh run. Private shot predictions, outcomes, game/player identifiers, bootstrap draws, fits, logs, locks, and checkpoints remain ignored.

The first result manifest remains fixed at SHA-256 `ca1c7d9bffa5ed7b0b3cad96c1339538f44d43a1286bab583deacfee7d7aff4c`. This second result can update only the transparent season-level count. It cannot select a final model: the registered 2025–26 comparison and pooled three-season rule still remain.

## Verified training fits

The expanding window contained 652,642 shots in 3,690 complete games from 808 players. Grouping reproduced every make, miss, and attempt: M0 used 1,571 player-by-point-value rows and M1 used 10,852 player-by-point-value-by-finish-by-creation rows. Each frozen model was fit once and then reused for validation; neither was tuned or refit after the outcome was opened.

M0 fit in 42.62 seconds and M1 in 159.71 seconds. The complete training run took 216.40 wall seconds and about 214.28 CPU seconds. Both fits reported full convergence, one positive player smoothing parameter, finite coefficients and covariance, no model warnings, and all 18 fit checks passing. Maximum absolute gradients were `5.20e-8` and `8.88e-6`. The serialized fits were 17.90 MB and 19.38 MB; the largest recorded point-in-time R memory reading was about 1.31 GB. The combined checkpoint manifest SHA-256 is `42091175741269e241f5fa654216199823731c35c9d6c2f7b434fadfd18fb5a4`.

## Verified 2024–25 result

The exclusive access marker was published at `2026-09-15 01:25:58 UTC`, after the pushed pre-result commit and outcome-free predictions passed. It records one source read and false access flags for 2025–26 and 2026–27. The comparison scored all 219,527 registered shots from 1,230 games and 566 players. There were 461 returning and 105 unseen players; unseen players contributed 18,677 shots and received zero player deviation as registered.

M0 log loss was `0.6725909`; M1 was `0.6509035`. The signed M1-minus-M0 difference was `-0.0216874`, with bootstrap standard error `0.0004052` and 95% interval `[-0.0224630, -0.0208762]`. The improvement exceeded one standard error. Overall observed make rate was `0.4672136`; M0 predicted `0.4669802` and M1 `0.4667843`. Absolute biases were `0.0002334` and `0.0004293`. Equal-count-decile expected calibration error was `0.0052214` for M0 and `0.0047571` for M1. Neither paired calibration interval triggered the frozen `0.005` material-worsening gate.

Basketball-scale secondary measures also improved under M1. Shot expected-points RMSE fell from `1.2021889` to `1.1855414`; whole-game point MAE fell from `13.3041` to `12.9661`; whole-game RMSE fell from `16.6557` to `16.2791`. Bias per 100 attempts was `-0.0223` points for M0 and `0.1346` for M1. These measures diagnose practical behavior but do not control the season decision.

M1 improved absolute calibration for both two- and three-point attempts; every finish family; and the three explicit creation families. The largest finish improvements occurred for dunks, fadeaways or turnarounds, floaters, and hooks, where M0 cannot distinguish shot type. `other_or_unknown` remained a weakness: its absolute gap rose from `0.00723` to `0.00972`. Unseen-player calibration also worsened from `0.0143` to `0.0279`, and the returning-player volume groups showed smaller mixed degradations. These registered subgroup summaries have no paired uncertainty and cannot override the primary result.

The second season therefore counts as a qualifying M1 result under the registered log-loss, one-standard-error, and calibration gates. The transparent running record is two qualifying M1 seasons from two completed comparisons. This is not a final selection. The untouched 2025–26 comparison and the frozen pooled three-season decision rule are still required.

The direction and size are consistent with 2023–24, when M1-minus-M0 log loss was `-0.0221985`; the 2024–25 improvement is slightly smaller by about `0.00051`. This shows that creation and finish labels carried forward predictive information again. It does not show that changing a player’s shot type would cause better shooting, measure defense or total offense, compare M1 with a location model, or justify changing M1 before the third test.

All 25 execution checks passed, including exact row alignment, finite interior probabilities, exact expected-point conversion, deterministic whole-game bootstrap reproduction, immutable first-result hashes, and aggregate-only tracked output. Evaluation took 355.71 wall seconds and about 348.48 CPU seconds, with sampled peak R memory of 953.0 MB. The only environment notice was that Arrow was built under R 4.6.1 while the frozen runtime is R 4.6.0; no Arrow operation or statistical check failed. The private completion-manifest SHA-256 is `9f9779026dc63a181660df24a0efe06d9f8b3dd1c42a0afe100add84d45fe4fc`; the tracked aggregate manifest SHA-256 is `a10db5ef9fcf93801c76975d83b317e95769ecdf6b5dbd22050781159fd06cb1`.
