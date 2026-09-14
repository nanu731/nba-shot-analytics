# Context Edition validation-data preparation and training preflight

Status before execution: implementation frozen; no validation evaluation run.

This stage prepares the frozen canonical field-goal contract for five complete seasons and checks whether the frozen M0 and M1 engines work on training data. It does not compare their accuracy.

## Mechanical canonicalization

The generalized builder applies `context_field_goal_v0.1.2`, `context_taxonomy_v0.1.0`, and `shotchart_espn_exact_clock_player_v0.1.1` to 2021-22 through 2025-26. The private ignored namespace is `data/cache/context_edition_canonical/context_field_goal_v0.1.2__2021-22_to_2025-26/`. It retains a combined recoverable file and one explicit season partition per season. Publication is atomic and guarded by a versioned lock.

Canonicalization mechanically carries the frozen make/miss field and may use it for source-integrity reconciliation. For 2023-24 through 2025-26, this is not analytical outcome access: no model fit, prediction, metric, calibration summary, or model comparison is permitted. Tracked reports contain only aggregate contract, coverage, missingness, taxonomy, join-quality, integrity, and hash information.

The same transformation function handles every season. Before publication, the rebuilt 2021-22 and 2022-23 rows must be identical in columns, types, values, and deterministic order to the accepted private v0.1.2 file. The registered accepted private and aggregate hashes must also match. A new raw label, changed source shape, or failed hash stops the build; it does not change the taxonomy.

The first execution exposed a reporting-only false positive before fitting: the accepted 2021-22 source contains 46 of the 48 registered raw labels, so requiring every registered label in every season was stricter than the frozen contract. The corrected gate requires every observed label to be registered and still rejects any new label. The stopped artifact must remain preserved as recovery evidence; the corrected code must regenerate and re-verify the bundle before fitting. This correction does not change canonical rows, taxonomy, or outcomes.

## Training-only engine preflight

The runner loads only the 2021-22 and 2022-23 season partitions. It fits exactly two grouped-binomial models:

- M0: point value plus one partially pooled player intercept.
- M1: M0 plus additive seven-level finish and four-level creation effects, including `other_or_unknown`.

Both use `mgcv::gam()`, binomial-logit, REML, `optimizer = c("outer", "newton")`, `discrete = FALSE`, one worker, and the frozen formulas. No later-season row may enter fitting, smoothing, prediction construction, or metrics. The preflight reports operational diagnostics only; likelihood or deviance output is not evidence that either model is more accurate.

M0 groups by player and point value. M1 groups by player, point value, finish, and creation. Each grouped table must reproduce the complete training attempt, make, and miss totals. Checks cover formula identity, feature exclusions, factor support, convergence, finite coefficients and covariance, a positive player smoothing parameter, nonzero player-effect degrees of freedom, deterministic interior probabilities, expected-points conversion, all M1 taxonomy combinations, and zero random-effect contribution for a deliberately unseen player.

Each fit has a 1,800-second protective elapsed-time limit. This operational guard does not change the model. Private fits, logs, locks, and checkpoints stay ignored. Small aggregate diagnostics are published only after every check passes. A completed checkpoint can be hash-verified with `--verify-recovery` and must not refit.

## Frozen decision boundary

This stage may decide only whether execution is ready. A `go` requires five valid canonical seasons, exact training-season reproduction, an intact validation seal, two converged fits, valid predictions and expected-points conversion, no forbidden feature, verified recovery, no source drift, and no public shot rows.

The future first rolling-origin comparison remains separate: train on 2021-22 and 2022-23, then evaluate once on 2023-24 under the already frozen rules. No such evaluation is authorized here.
