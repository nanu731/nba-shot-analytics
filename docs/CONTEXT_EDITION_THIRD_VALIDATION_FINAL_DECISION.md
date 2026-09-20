# Context Edition: third rolling-origin validation and final decision

Status: pre-result implementation frozen; 2025–26 outcomes remain unopened

Protocol: `context_m0_m1_protocol_v0.1.0`

## Question and fixed scope

This final retrospective check asks whether broad finish and creation categories add repeatable future-season predictive information beyond shot value and a partially pooled player baseline. It does not test location, distance, total offense, defense, causal coaching advice, or M2 features.

M0 is the registered grouped-binomial `mgcv::gam()` with two-versus-three status and `s(player_id_factor, bs = "re")`. M1 adds the frozen seven-level finish family and four-level creation family. `other_or_unknown` remains an ordinary level. Both use REML, the registered optimizer, exact non-discrete fitting, stable factor levels, and zero player deviation for players unseen in training.

## Frozen third split

The expanding training window contains complete 2021–22 through 2024–25 games. It has 872,169 shots in 4,920 games from 913 players. The one-time 2025–26 validation population has 219,160 shots in 1,230 games from 582 players. Training and validation game identifiers do not overlap. The validation partition SHA-256 is `3cc2c2e6b62b7d87c15965639052da62ef909e49e2b8ea09ef6f2a9f8b370ee7`.

The 2026–27 season remains fully sealed for prospective confirmation. The runner contains no 2026–27 data path or outcome loader.

## Frozen evaluation

The third comparison keeps the earlier definitions unchanged: pooled shot-level Bernoulli log loss is primary; differences are M1 minus M0, so negative values favor M1; probabilities are clipped to `[1e-15, 1-1e-15]` only for logarithms. Expected-points, game-total, calibration, subgroup, Brier, and AUC summaries remain secondary.

The third-season uncertainty calculation uses 2,000 paired whole-game bootstrap draws with seed `20260914`. M1 must lower log loss by more than one bootstrap standard error and avoid material calibration worsening beyond `0.005` to count as a qualifying season result.

## Frozen pooled decision

The final calculation combines only the original out-of-sample prediction checkpoints:

- 2023–24 predictions from fits trained through 2022–23;
- 2024–25 predictions from fits trained through 2023–24;
- 2025–26 predictions from fits trained through 2024–25.

The first two canonical sources are not reread. Their private prediction files and completion manifests must pass their frozen hashes. The pooled bootstrap again uses 2,000 draws and seed `20260914`, resampling complete games separately inside each validation season so every draw retains all three seasons.

The registered decision is mechanical. M1 is selected only when it has lower pooled log loss by more than one pooled bootstrap standard error, does not trigger either material calibration gate, and has lower log loss in at least two of the three validation seasons. Otherwise M0 is retained. Secondary metrics cannot override this rule.

## Safeguards and publication

Before 2025–26 can be opened, the complete runner, configuration, structural tests, outcome-free population manifest, output schema, and this document must be committed and pushed. The pushed commit is then written into the frozen configuration in a second pushed lock commit. Each four-season model fit is published as an atomic private component and is reused after interruption. An exclusive access marker blocks a second 2025–26 source read.

Only compact aggregate tables are tracked. Fits, private predictions, outcomes, identifiers, bootstrap draws, logs, locks, and checkpoints remain ignored. The first and second public results are immutable, and their split-specific predictions cannot be replaced by predictions from later fits.

## Result placeholder

The verified 2025–26 result, three-season pooled metrics, gate outcomes, and final selected model will be added only after the pre-result implementation and lock commit are pushed and the one-time evaluation completes.
