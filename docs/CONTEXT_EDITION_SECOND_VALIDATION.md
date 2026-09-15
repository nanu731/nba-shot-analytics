# Context Edition: second rolling-origin validation

Status: frozen before 2024–25 analytical outcome access; no second-season result yet

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

The complete code, tests, output schema, and split configuration must be committed and pushed before 2024–25 outcomes are loaded. Immediately before the sole outcome read, the runner creates an exclusive marker containing code, configuration, canonical, partition, and fit hashes. A pre-existing marker or result blocks a fresh run. Private shot predictions, outcomes, game/player identifiers, bootstrap draws, fits, logs, locks, and checkpoints remain ignored.

The first result manifest remains fixed at SHA-256 `ca1c7d9bffa5ed7b0b3cad96c1339538f44d43a1286bab583deacfee7d7aff4c`. This second result can update only the transparent season-level count. It cannot select a final model: the registered 2025–26 comparison and pooled three-season rule still remain.
