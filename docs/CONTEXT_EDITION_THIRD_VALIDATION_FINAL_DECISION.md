# Context Edition: third rolling-origin validation and final decision

Status: third rolling-origin validation and frozen pooled decision completed; M1 selected

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

## Verified four-season fits

The implementation was committed and pushed at `e29e255badcf8ed823f547a58367b419e6a07164`, then locked in pushed commit `1905ee34f33ca72d48a8c30f0409a481166080b9`, before 2025–26 was opened. M0 and M1 were each fit once on 872,169 shots. Grouping reproduced every attempt and make: M0 used 1,774 grouped rows and M1 used 12,415.

M0 fit in 49.23 seconds and M1 in 274.55 seconds. The full training run took 343.32 wall seconds and about 310.20 CPU seconds. Sampled R memory peaked at 682.0 MB. Both fits reported full convergence, finite coefficients and covariance, one positive player smoothing parameter, deterministic interior training probabilities, and no warnings. The M0 and M1 fit hashes are `69d4af142d4407e406463ff4c27e56f3064c3187837a0b65c58559733db9da9a` and `24bf051f847825bb835fda7025aea119b89b5e9a2a93b252f3a5eeb0b765db4f`.

## Verified 2025–26 result

The exclusive access marker was created at `2026-09-20 20:47:26 UTC`. The source was read once, after both pushed freezes and all outcome-free checks passed. All 219,160 registered shots from 1,230 games and 582 players were evaluated. There were 478 returning and 104 unseen players; unseen players contributed 21,561 shots and received zero player deviation as registered.

M0 log loss was `0.6723819641`; M1 was `0.6499648682`. The signed M1-minus-M0 difference was `-0.0224170959`, with paired whole-game bootstrap standard error `0.0004327559` and 95% interval `[-0.0232691911, -0.0215610730]`. M1 therefore improved by more than one standard error.

Overall absolute bias was `0.00421095` for M0 and `0.00727275` for M1. The paired increase was below the frozen `0.005` material-worsening margin; equal-count-bin ECE improved from `0.00853` to `0.00787`. The calibration gate passed. M1 also lowered shot expected-points RMSE from `1.19902` to `1.18188`, game-total MAE from `13.4148` to `13.0959`, and game-total RMSE from `16.6034` to `16.2827`. These secondary measures did not control the decision.

The `other_or_unknown` absolute calibration gap worsened from `0.0101` to `0.0123`, while the unseen-player gap improved from `0.00833` to `0.00548`. Point-value calibration was mixed. These are descriptive diagnostics without paired subgroup uncertainty and do not override the registered gates. The third season counts as a qualifying M1 result, making the season record three of three.

## Verified pooled decision

The pooled calculation covered 657,387 untouched out-of-sample shots from 3,690 games across the three validation seasons. Hash verification passed for both earlier public results and their original split-specific private prediction checkpoints. No earlier source partition was reread and no prediction was regenerated with a later fit.

Pooled M0 log loss was `0.6732749661`; pooled M1 was `0.6511742771`. The signed difference was `-0.0221006890`, with stratified paired-game bootstrap standard error `0.0002445270` and 95% interval `[-0.0225790677, -0.0216387522]`. Pooled absolute bias increased from `0.00298268` to `0.00394046`, but the paired lower interval bound was only `0.00063890`, below the material threshold. Pooled ECE improved from `0.00668` to `0.00548`, and its paired interval was entirely below zero. The pooled calibration gate passed.

M1 had lower log loss in all three seasons. It therefore passed the pooled one-standard-error, calibration, and two-of-three breadth gates. The frozen rule mechanically selects M1.

This supports a narrow conclusion: broad creation and finish categories add repeatable out-of-sample predictive information beyond shot value and a pooled player baseline. It does not establish causality, measure total offense or defense, compare against a location model, resolve unknown creation types, or make unseen-player predictions fully satisfactory. In the pooled unseen-player diagnostic, M1's absolute gap was `0.01616` versus `0.01009` for M0.

The evaluation took 1,761.56 wall seconds and about 1,707.01 CPU seconds, including exact reproducibility repeats for both bootstraps. Sampled R memory peaked at about 1.19 GB. All 25 execution checks passed; there were no model or evaluation warnings or errors. The Arrow build-version notice was the same environment notice seen previously and did not fail an operation or statistical check.

The private completion-manifest SHA-256 is `3f6bb79ad229617a0bd756a6d5b80874d3c12bc2401b9bf69d877999e4a632dd`; the tracked aggregate manifest SHA-256 is `fcc7b6002c8fdb31d70a2b284f534c72339be41dda6f21784c20f8e8f2f0b5ed`. The 2026–27 access flag remains false, and the prospective season was not accessed.
