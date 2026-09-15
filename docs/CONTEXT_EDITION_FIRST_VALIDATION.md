# Context Edition: first rolling-origin validation

Status: pre-result implementation frozen; 2023–24 outcomes remain analytically sealed until the recorded implementation is committed and pushed

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

Shot predictions, game and player identifiers, bootstrap draws, logs, locks, and fitted models remain ignored. Git receives only compact aggregate tables and manifests. Results are published atomically and hash-verified.

## Result

Not run. This section may be completed only after the pre-result implementation is committed, pushed, and verified against origin.
