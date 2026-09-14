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

## Measured completion on 2026-09-14

The corrected canonical regeneration passed and published atomically. It contains 1,091,329 shots, 6,150 games, and 1,017 distinct players across the five-season union. Season counts are:

| Season | Games | Shots | Players |
|---|---:|---:|---:|
| 2021-22 | 1,230 | 216,722 | 596 |
| 2022-23 | 1,230 | 217,220 | 537 |
| 2023-24 | 1,230 | 218,700 | 568 |
| 2024-25 | 1,230 | 219,527 | 566 |
| 2025-26 | 1,230 | 219,160 | 582 |

All observed raw labels are registered in the frozen taxonomy. Every season contains all seven finish families and all four creation families, including `other_or_unknown`. Unique exact joins number 191,079; 194,530; 196,152; 197,846; and 194,162 by season. The 2025-26 source has 184 unmatched games; those shots remain explicitly classified rather than inferred or dropped. This is a recorded source limitation, not a model-performance result.

The generalized pipeline reproduced all 433,942 accepted training rows exactly in columns, types, values, and deterministic order. All 22 registered accepted artifact hashes matched, including canonical SHA-256 `292eba28ce0a37788945312169c0986c60bc9db5c6308d322bf5f8e073b2ded7`. The corrected canonical completion-manifest SHA-256 is `5f8e294903701a3fb99511f060b1da269823c63fb350cda9a1fc15ca8cea20dc`.

The corrected canonical run took 153.87 seconds of wall time, 130.34 user CPU seconds, and 15.96 system CPU seconds. External measurement recorded 4,019,732,480 bytes maximum resident memory. Its ignored directory occupies about 61 MB. The first bundle remains in an ignored, hash-verified rejected-attempt archive; no file was deleted or overwritten.

The training-only preflight used 433,942 shots and 700 players. M0 reduced to 1,361 grouped rows and 702 coefficients. M1 reduced to 9,328 grouped rows and 711 coefficients. Both fits reported full convergence, zero warnings, finite coefficients and covariance, one positive smoothing parameter, and nonzero player-effect degrees of freedom. M0 fitting took 27.57 seconds; M1 took 104.72 seconds. Their maximum absolute gradients were `1.10e-6` and `4.52e-7`. Serialized fits are 13,484,116 and 14,627,288 bytes; in-memory fit sizes are 28,313,136 and 29,778,808 bytes.

The successful preflight took 142.66 seconds externally, including 140.01 user and 1.65 system CPU seconds. Maximum resident memory was 1,133,887,488 bytes. The runner's sampled peak was 1,059,536,896 bytes. The completed ignored checkpoint occupies about 29 MB and has manifest SHA-256 `b193baa10f9ef2a863f53a33d62429bc19f54a71a41bec99db25be1cef4dec85`.

All 24 frozen fit checks passed. Probabilities were finite, strictly inside zero and one, and identical on repeated prediction. Expected points equaled probability times two or three exactly within the registered tolerance. Every M1 taxonomy combination predicted successfully. Both models assigned 700 finite, nonzero player deviations. A deliberately unseen player received the fixed prediction with zero random-effect contribution. Direct predictions for all 1,361 M0 and 9,328 M1 representative groups matched grouped predictions with zero measured difference.

The first preflight execution ran both fits but hit a post-fit R variable-scoping error before any checkpoint was published. That inactive attempt and its lock were archived with byte-matching hashes. The correction at `81278a1` changed only the check implementation. The identical frozen fits were then rerun because no reusable fit existed. Recovery-only verification subsequently checked the published hashes and exited without refitting.

## Readiness decision

Decision: **go** for the separately authorized first rolling-origin comparison that will train on 2021-22 and 2022-23 and validate on 2023-24.

This is an operational decision, not an accuracy result. The 2023-24 through 2025-26 outcomes were mechanically preserved during canonicalization but were not used for fitting, smoothing, training prediction, calibration, comparison, or any performance metric. No 2026-27 source was accessed. The relative predictive accuracy of M0 and M1 remains unknown.
