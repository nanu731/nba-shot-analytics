# Context Edition: first rolling-origin validation

Status: first of three retrospective validations completed; provisional 2023–24 evidence favors M1, but no final model has been selected

Protocol: `context_m0_m1_protocol_v0.1.0`

## Question

This comparison asks whether two simple descriptions of an NBA field-goal attempt—how it was created and how it was finished—improve next-season scoring predictions beyond shot value and the shooter’s stabilized historical baseline.

M0 knows whether the attempt is worth two or three points and gives returning players a partially pooled shooting baseline. M1 adds the seven frozen finish families and four frozen creation families. It remains an additive model: it does not learn player-specific shot-type effects.

This is a test of the forward value of the frozen taxonomy. It is not a comparison between location and shot type, and it does not measure causal basketball improvement, complete offensive value, defense, free throws, or future shot volume.

## Frozen split and fit reuse

Both models were trained only on 2021–22 and 2022–23. Their completed preflight objects, source hashes, formulas, factors, package version, grouped counts, and convergence records match the first registered split exactly, so the evaluation reuses them without refitting. A player absent from those training seasons receives the population-level prediction with the player random effect fixed at zero.

Every valid 2023–24 canonical field-goal attempt is registered for scoring. Shots without a verified ESPN join remain included because both models use the primary shot record and frozen taxonomy. `other_or_unknown` is an ordinary creation category, not an exclusion.

## Frozen evaluation

Pooled shot-level Bernoulli log loss is primary. Probabilities are clipped to `[1e-15, 1-1e-15]` only inside logarithms. The paired difference is M1 minus M0, so a negative value favors M1. Secondary summaries cover Brier score, AUC, shot-level expected-points RMSE, whole-game point MAE and RMSE, points bias per 100 attempts, overall calibration, ten equal-count calibration bins, and registered basketball subgroups.

The uncertainty calculation uses 2,000 paired whole-game bootstrap samples with seed `20260914`. The same sampled games weight both models in each draw. M1 must improve by more than one bootstrap standard error for M0 not to receive the simplicity preference in this season. M1 also fails this season’s calibration gate if the lower 95% bound for either registered M1-minus-M0 calibration error exceeds `0.005`.

This first result cannot select the final model. The registered breadth rule requires separate evaluations on 2023–24, 2024–25, and 2025–26, with M1 improving log loss in at least two seasons. No model may be revised after seeing this result.

## Outcome access and publication

The runner first performs an outcome-free audit using validation metadata. Before its single authorized outcome read, it requires a clean pushed branch, verified input and fit hashes, a recorded pre-result implementation commit, and no existing marker or result. It then publishes an exclusive private access marker. The code has no model-fitting call and no input path for 2024–25, 2025–26, or 2026–27.

The recorded pre-result implementation commit is `5c1fc498d009c3a78efe0ccd09e615b4aadee1ed`. It contains the complete evaluation code, tests, output schema, and outcome-free population hashes. This later declarative edit records that already-pushed commit without changing an evaluation rule.

Shot predictions, game and player identifiers, bootstrap draws, logs, locks, and fitted models remain ignored. Git receives only compact aggregate tables and manifests. Results are published atomically and hash-verified.

## Result

The implementation was pushed before outcome access. The complete runner was frozen at `5c1fc498d009c3a78efe0ccd09e615b4aadee1ed`; the declarative commit record and an outcome-free recovery correction were then pushed before execution. The exclusive access marker records one 2023–24 outcome read at `2026-09-15 00:49:14 UTC`. The completed run reused both training fits and made no model call.

The evaluation covered all 218,700 registered field-goal attempts from 1,230 games and 568 players. Of those players, 460 returned from the 700-player training population and 108 were unseen; unseen players accounted for 17,969 validation shots and received zero player deviation as registered.

M0 pooled log loss was `0.6748565`; M1 was `0.6526580`. The M1-minus-M0 difference was `-0.0221985`, so M1 was better in this season. Its paired whole-game bootstrap standard error was `0.0004227`, and the percentile 95% interval was `[-0.0230446, -0.0214092]`. The improvement therefore exceeded one standard error.

Overall calibration remained close. Observed make rate was `0.4743439`. M0 predicted `0.4698324`, for absolute bias `0.0045115`; M1 predicted `0.4702182`, for absolute bias `0.0041256`. Equal-count-decile expected calibration error was `0.0083543` for M0 and `0.0055299` for M1. Neither registered M1-minus-M0 calibration interval had a lower endpoint above `0.005`, so the material-worsening gate did not trigger. Calibration slopes were `0.9534` and `0.9740`.

The basketball-scale diagnostics point in the same direction but do not control selection. Expected-points RMSE was `1.1927` for M0 and `1.1758` for M1. Whole-game point MAE was `13.1421` and `13.0065`; whole-game RMSE was `16.4274` and `16.2297`. Signed underprediction was `1.1526` and `1.1075` points per 100 attempts. Brier scores were `0.240945` and `0.231150`; rank AUC was `0.602491` and `0.637088`.

M1 sharply improved finish-family calibration for dunks, fadeaways or turnarounds, floaters, hooks, layups, and step-backs; regular jumpers were similar. It improved explicit drive/cut/roll, pull-up/self-created, and putback groups. The large `other_or_unknown` group was less well calibrated under M1 (`0.00990` absolute gap versus `0.00555`), as were unseen players (`0.01680` versus `0.00779`). These are subgroup diagnostics without paired uncertainty and cannot override the primary result.

## Recovery note

The first atomic result produced two `NAs produced by integer overflow` warnings in the non-selecting rank-AUC diagnostic. The positive and negative shot counts had been multiplied as 32-bit integers. Log loss, expected-points results, calibration, and bootstrap calculations used separate numeric paths and were valid.

The original result is preserved byte-for-byte in the ignored source checkpoint and dated recovery archive. A recovery-only script verified that checkpoint, read its ignored prediction table instead of reopening the canonical outcome source, cast the two AUC counts to double precision, and published finite AUC values. It did not refit a model or change an evaluation rule. Source outcome-read count remains one. The recovered result and original archive hashes both pass.

## Interpretation and next boundary

For 2023–24, adding the frozen finish and creation taxonomy produced clearly better future make-probability estimates than point value and pooled player history alone. It does not establish that changing shot type causes better shooting, that M1 measures total offense, or that the taxonomy will remain better across seasons.

This is only the first breadth observation. The final registered decision still requires separately authorized 2024–25 and 2025–26 evaluations, with M1 winning at least two of the three seasons and passing the pooled one-standard-error and calibration gates. Those later outcomes remain analytically sealed, and M0 and M1 may not be revised in response to this result.
