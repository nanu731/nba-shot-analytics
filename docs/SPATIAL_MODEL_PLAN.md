# Spatial Shot Relocation: Living Plan

**Status:** CAR won the frozen final prediction test and the verified all-data
CAR production model now exists. The relocation method and slider calculation
are frozen in code, but no production relocation result has been published: the
latest authorized run stopped at a pre-publication numerical tolerance check.
The 0-100 score remains unbuilt.

This document records the current direction without treating the design as
finished. Move decisions as evidence changes.

## Settled

### Question

How many additional points could a player score by relocating a limited share of
shots from weaker locations toward locations where that player has demonstrated
stronger ability, while preserving shot variety?

### Meaning

- Compare the player's observed shot mix with a realistic alternative built from
  that player's own demonstrated strengths.
- Do not use league-average shooting as the counterfactual.
- Measure location-based skill utilization, not overall player value or complete
  decision quality.

### Model and presentation

- Remove zones from the replacement model and its presentation.
- Estimate a smooth make-probability surface across the half court.
- Compare simple GAM and Bayesian CAR surfaces on identical data.
- Choose GAM unless CAR clearly improves unseen-shot prediction or uncertainty.
- Later, the website will use a searchable player selector, court heat map, and
  relocation slider.

### Relocation experiment

- Use slider settings of 0%, 5%, 10%, 15%, 20%, and 25%.
- At 10%, 90% of the observed distribution remains in place.
- Move shots only toward locations supported by evidence of personal ability.
- Spread relocated shots across supported strong locations.
- Report points gained per 100 shots and over the observed season.
- Report an uncertainty range that widens where evidence is weaker.

### First-version scope

Use location, make or miss, and two- or three-point value. Exclude defender
distance, actual shot-clock time, complete pass sequences, fatigue, and detailed
game context because public shot rows do not provide them reliably at the same
level.

## Proposed first implementation

These are starting choices, not final commitments.

1. Prototype on the complete 2025-26 season.
2. Keep the existing 20-game and 250-attempt eligibility rule provisionally.
3. Run the pre-registered prediction experiment below before building any
   relocation logic.
4. Choose between player-specific GAM and CAR make-probability surfaces using
   only that experiment.
5. Apply shot value only after the make-probability model is chosen.
6. Define supported destinations using nearby attempts and model uncertainty,
   not raw percentage alone.
7. Move attempts from weaker supported locations toward multiple stronger
   supported locations at each slider setting.
8. Repeat calculations across plausible ability surfaces to produce the
   uncertainty range.
9. Inspect stars, specialists, high-volume creators, low-volume finishers, and
   players near the eligibility cutoff.
10. Expand to 2021-22 through 2025-26 only after the prototype passes.

## Pre-registered first prediction experiment

**Status:** The experiment and outcome rules are pre-registered before either
production spatial model is implemented. Stable R-INLA and shared GAM smoothing
across players are approved and frozen for the first comparison. The test games
are a sealed final check. Any change made after looking at their results must be
recorded as a new experiment rather than folded into this one.

This experiment answers only which model estimates make probability better. It
does not relocate attempts, apply the slider, calculate points gained, or define
the 0-100 score.

### Data boundary

- Use only the complete 2025-26 season.
- Keep the existing 20-game and 250-attempt eligibility rule for this comparison.
  Reconsidering eligibility is a later experiment and must not change the players
  during this model comparison.
- Freeze one zone-free modeling table containing player id, game id, location,
  and make or miss. Point value is not needed for this experiment.
- Apply one documented cleaning rule before splitting. Both models receive every
  remaining row; neither model may silently drop a difficult shot, player, or
  cell.

### Split games before making choices

1. Sort the distinct `GAME_ID` values, then use base R with the fixed seed
   `20260830` to shuffle them once and assign them in order to five folds.
2. Keep every shot from one game in the same fold.
3. Use folds 1-3 for fitting candidate grids, fold 4 for selecting the common
   grid, and fold 5 as the sealed test set. This is a 60% / 20% / 20% split by
   games, not by shots.
4. Create and save the fold assignment locally before inspecting cell support,
   model fit, calibration, or log loss. Do not export or commit game ids.
5. Stop and report if any eligible player has no fitting shots or no test shots.
   Do not silently move that player's games between folds.

The same fold assignment is used for every grid and both models.

### Select one common grid without using the test fold

An earlier read-only audit used the full season to learn that half-foot through
two-foot cells are too sparse and to motivate the candidates below. It did not
use make rates or choose a winning grid. The formal choice starts only after the
game split and uses folds 1-4 as described here.

- Compare square cells 30, 40, and 50 NBA coordinate units wide, approximately
  3, 4, and 5 feet. Anchor every grid at the same fixed court origin and use
  shared-edge neighbours for CAR adjacency.
- For each grid, aggregate the same fitting shots into player-cell makes and
  attempts. Cells with no fitting attempts contribute no observed outcome to
  either model, but remain available for prediction under each model's smoothing
  assumptions.
- Fit both GAM and CAR on folds 1-3 and calculate per-shot log loss on fold 4.
- Give the two model families equal weight: for each grid, average its GAM and
  CAR validation log losses, then choose the grid with the lowest average.
- Estimate normal validation noise by resampling whole fold-4 games and
  recalculating the paired log-loss differences. If the leading grids cannot be
  separated by a 95% bootstrap interval, choose the coarser grid.
- Freeze the selected grid, then refit both models on folds 1-4. Do not revisit
  grid size after opening fold 5.

This chooses a shared resolution without allowing the final test data, one model
family, or runtime to choose the grid.

### Fair model comparison

GAM and CAR must use the exact same:

- 2025-26 shots and eligible players;
- grid cells and court boundary;
- fitting, validation, and test games;
- player-cell makes and attempts; and
- held-out shots used for scoring.

Both models estimate make probability. Neither receives relocation targets,
shot value, league-average counterfactual weights, or the eventual score formula.
Use the frozen formulas, priors, approximation, prediction, and diagnostic rules
below for every grid. Fold 4 may select only the common grid; it may not tune a
model setting. Fold 5 may not select or tune anything. If a model failure requires
a material change, report it and treat the revision as a new experiment rather
than repairing only the affected fit.

### Bayesian player representation

One model-data row represents one player in one grid cell, aggregated over the
allowed fitting games. It contains that player's makes and attempts in that
cell. A player-cell with no fitting attempts stays in the common prediction
lattice but contributes no outcome to the likelihood.

**Revised proposed CAR structure:** fit all players jointly in one R-INLA model,
with a separate replicated CAR field and a separate intercept for every player.
The player fields are independent conditional on shared smoothing
hyperparameters. Sharing smoothing strength lets the league stabilize how noisy
a surface may be; it does not give players the same spatial pattern. The first
experiment does not add a league-average ability surface. A shared league
surface plus player deviations is possible, but it adds a second spatial layer
and an identification problem before evidence shows it is needed.

For the current half-court bounds, the approximate dimensions are:

| Grid | Cells per player | Player-cell spatial effects | Joint R-INLA unknowns, approximately |
|---|---:|---:|---:|
| 3 feet | 255 | 81,090 | 81,410 |
| 4 feet | 156 | 49,608 | 49,928 |
| 5 feet | 90 | 28,620 | 28,940 |

The last column adds 318 player intercepts and two shared CAR hyperparameters.
It is an order-of-magnitude count, not a memory or runtime measurement.

**Approved:** the replicated CAR shares its smoothing hyperparameters across
players, and the GAM shares one smoothing parameter across its player-specific
smooths. This gives both models a comparable cross-player smoothing rule while
preserving a different spatial surface for every player.

### Frozen model specification

These settings were fixed using training-only feasibility work and official
package documentation. They may not be tuned from fold-4 or fold-5 results.

#### GAM

Use one aggregated row for every observed player-cell and fit this exact model:

```r
cbind(makes, attempts - makes) ~ 0 + player_factor +
  s(
    x_ft, y_ft,
    by = player_factor,
    bs = "tp",
    m = 2,
    k = 20,
    id = 1
  )
```

- `player_factor` is an unordered factor with one level per eligible player.
  `0 + player_factor` gives every player a separate unpenalized intercept.
- `bs = "tp"` is an isotropic thin-plate regression spline. Cell-centre x and y
  coordinates are expressed in feet so both axes use the same scale. `m = 2`
  applies the usual second-derivative smoothness penalty.
- `k = 20` is fixed for every player and all three candidate grids. It allows at
  most 19 effective degrees of freedom after the centering constraint; grid size
  may not alter it.
- A factor `by` variable creates a different smooth for every player. `id = 1`
  gives those smooths one shared smoothing parameter while retaining separate
  coefficients and therefore separate surfaces.
- Fit with `mgcv::bam()`, `family = binomial(link = "logit")`,
  `method = "fREML"`, `discrete = FALSE`, `select = FALSE`, `gamma = 1`,
  `nthreads = 1`, and `na.action = na.fail`. The non-discrete fit is deliberate:
  `mgcv` documents that discrete fitting cannot guarantee identical linked bases
  when smooths share an `id`.

For point prediction, build the full player-grid lattice in the same row order
for every model and call `predict.bam(type = "lpmatrix", discrete = FALSE)`.
Draw 4,000 coefficient vectors with `mgcv::rmvn()` from the fitted coefficient
mean and `vcov(fit, unconditional = TRUE)`, which includes the available
smoothing-parameter uncertainty correction. Transform each linear predictor
with `plogis()` and average the 4,000 probabilities for the log-loss prediction.
Use those same draws, plus binomial shot noise, for predictive intervals. Do not
use `predict(..., type = "response")` as a substitute for the draw-averaged
probability.

The official `mgcv` documentation explains the [factor-by and shared-`id`
construction](https://www.stat.ethz.ch/R-manual/R-devel/library/mgcv/html/factor.smooth.html),
[`bam()` fitting choices](https://stat.ethz.ch/R-manual/R-devel/library/mgcv/help/bam.html),
and [`lpmatrix` prediction](https://www.stat.ethz.ch/R-manual/R-devel/library/mgcv/html/predict.bam.html).

**Approved computational approximation, 2026-09-01:** because the frozen exact
full-league GAM was impractical, Narayan approved one training-only feasibility
run with `mgcv::bam(discrete = TRUE)` on the fixed approximately 4-foot grid.
The formula, 318 player intercepts, 318 player-specific `k = 20` smooths, shared
`id = 1` smoothing parameter, fREML method, seeds, 4,000 coefficient draws,
prediction lattice, and posterior-predictive uncertainty calculation remain
unchanged. Prediction uses `predict.bam(type = "lpmatrix", discrete = TRUE)`.
This is a computational approximation, not the frozen exact GAM, and must be
labeled that way in every later comparison.

#### Bayesian CAR

Use the same player-cell rows, adding `NA` outcome rows for zero-attempt cells so
the complete prediction lattice is present. For observed cells, `y = makes` and
`Ntrials = attempts`; for zero-attempt cells, `y = NA` and `Ntrials = 1` as an
ignored placeholder. Fit this exact model:

```r
y ~ 0 + player_factor +
  f(
    cell_id,
    model = "besagproper2",
    graph = graph,
    replicate = player_index,
    nrep = n_players,
    constr = FALSE,
    diagonal = 0,
    hyper = list(
      prec = list(
        prior = "pc.prec", param = c(1, 0.01),
        initial = 0, fixed = FALSE
      ),
      lambda = list(
        prior = "logitbeta", param = c(1, 1),
        initial = 0, fixed = FALSE
      )
    )
  )
```

- `0 + player_factor` creates one fixed intercept per player. Set
  `control.fixed = list(mean = 0, prec = 0.001,
  expand.factor.strategy = "model.matrix")`, an effectively flat
  Normal(0, 1000) prior on each player log-odds intercept.
- `replicate = player_index` creates independent player-specific CAR fields that
  share the two CAR hyperparameters. `nrep` equals the exact eligible-player
  count and is asserted rather than inferred.
- For each candidate grid, construct a binary, symmetric rook-adjacency graph:
  two cells are neighbours only when they share a full edge. The diagonal is
  zero. The graph must be connected and contain no isolated cell. Boundary cells
  clipped by the fixed court edge remain ordinary cells.
- `besagproper2` uses precision
  `tau * ((1 - lambda) * I + lambda * (D - W))`. It is proper, so no sum-to-zero
  constraint is imposed: `constr = FALSE`. R-INLA rejects `scale.model` for this
  latent model, so no graph scaling is applied. The same unscaled construction
  and priors are used at all three resolutions.
- The precision prior is `pc.prec` with `param = c(1, 0.01)`, meaning
  `P(1 / sqrt(tau) > 1) = 0.01` on the log-odds scale. It shrinks toward a flat
  player surface unless the data support spatial variation.
- The dependence prior is `logitbeta` with `param = c(1, 1)`, a uniform prior on
  `lambda` between zero and one. It does not pre-select independence or strong
  neighbour dependence. No CAR-prior sensitivity fit is planned for this first
  experiment.

Call `INLA::inla()` with `family = "binomial"`, the `Ntrials` vector above,
`control.predictor = list(compute = TRUE, link = 1)`,
`control.compute = list(config = TRUE, dic = FALSE, waic = FALSE, cpo = FALSE,
return.marginals.predictor = TRUE)`,
`control.inla = list(strategy = "simplified.laplace", int.strategy = "auto")`,
`num.threads = 1`, `safe = FALSE`, and `verbose = FALSE`. Disabling `safe`
prevents an undocumented automatic repair attempt from replacing a failed fit.

For point prediction, use `summary.fitted.values$mean` on the full lattice; the
explicit `link = 1` applies the binomial-logit link to `NA` prediction rows. For
uncertainty, draw 4,000 joint posterior samples with
`inla.posterior.sample(seed = 20260902, num.threads = 1,
parallel.configs = FALSE)`, transform the sampled linear predictors with
`plogis()`, and add binomial shot noise. The official R-INLA documentation gives
the [`besagproper2` precision](https://inla.r-inla-download.org/r-inla.org/doc/latent/besagproper2.pdf),
the [replication rule](https://inla.r-inla-download.org/r-inla.org/doc/vignettes/old-faq.html),
the [`pc.prec` interpretation](https://www.inla.r-inla-download.org/r-inla.org/doc/prior/pc.prec.pdf),
and the [`logitbeta` prior](https://inla.r-inla-download.org/r-inla.org/doc/prior/logitbeta.pdf).

#### Reproducibility lock

- Use R 4.6.0, `mgcv` 1.9-4, R-INLA 26.8.7, `Matrix` 1.7-5,
  `fmesher` 0.8.0, `arrow` 25.0.0, `dplyr` 1.2.1, and `tidyr` 1.3.2. Stop on a
  version mismatch; do not upgrade during the experiment.
- Before every random operation, set
  `RNGkind("Mersenne-Twister", "Inversion", "Rejection")`. Use seed
  `20260830` for the game split, `20260831` for the fallback player sample,
  `20260901` for GAM coefficient draws, `20260902` for R-INLA posterior draws,
  and reset seed `20260903` before each model's posterior-predictive binomial
  draws. Use `20260904` for fold-4 whole-game bootstrap resamples. The final-test
  amendment below explicitly reuses `20260904` for fold 5; the previously
  reserved `20260905` seed was never used and is retired.
- The local, ignored split artifact is
  `data/cache/spatial_pilot/season=2025-26/game_folds.parquet`, SHA-256
  `aaee94c1e8380999190aea5f00f8c02c738db6438ffe7b7a1a761d19c5a6ee33`.
  It contains 1,230 distinct text `GAME_ID` values, 246 per fold. Never
  regenerate it silently or commit it.
- The fallback-sample artifact is
  `data/cache/spatial_pilot/season=2025-26/player_sample.parquet`, SHA-256
  `bba00938e29c2a365c668d337067f3958e849db9957c8b2d259629e50c78ae84`.
  Use it only if the pre-declared fallback is invoked.
- Sort players by `PLAYER_ID` and cells by `cell_id` before fitting, prediction,
  posterior draws, or aggregation. Record formulas, versions, seeds, graph
  dimensions, hashes, warnings, wall time, and model-object hashes with results.

#### Fairness and non-competitive sanity checks

Across the 3-, 4-, and 5-foot candidates, do not change `k`, priors, initial
values, fitting methods, approximation strategy, thread count, posterior-draw
count, or prediction definition. Both models use the identical player set,
shots, observed player-cell rows, full prediction lattice, fold assignment,
court origin, cell boundaries, and scoring rows. Empty cells enter neither
likelihood. Fit each grid from the frozen initial settings rather than warm-starting
from another grid. Clip probabilities to `[1e-15, 1 - 1e-15]` only when taking
logs, identically for both models.

Before any validation outcome is read, stop the experiment if any of these
checks fails:

- data keys, attempt totals, makes, player levels, grid dimensions, or graph
  structure disagree between models;
- GAM does not converge, has non-finite coefficients or predictions, does not
  contain exactly one smoothing parameter and one smooth per player, or any
  player smooth uses at least 95% of its 19-degree basis ceiling;
- R-INLA does not return `fit$ok = TRUE`, reports a fit warning or retry, has the
  wrong counts of fixed, replicated spatial, or hyperparameter values, or
  returns non-finite posterior summaries or predictions;
- either model gives two players identical centered spatial surfaces within a
  root-mean-square tolerance of `1e-8`; or
- any predicted probability falls outside `[0, 1]` before log-loss clipping.

These checks decide only whether the implementation is trustworthy enough to
evaluate. They cannot select a grid or model. A failed check ends the run and is
reported; it cannot be fixed for only one grid or player.

**Configuration lock:** after any fold-4 outcome is viewed, none of the settings
in this section may change. A required change ends this experiment and requires
a separately pre-registered experiment with a holdout that was not used to
motivate the change. Fold-5 outcomes remain sealed until the common grid and
both final fits are frozen.

### Tests and winner rule

**Primary test: held-out log loss.** Calculate one probability for every shot in
fold 5 and pool the per-shot log loss over the full eligible population. Compare
models with paired bootstrap resampling of whole test games, using at least 2,000
resamples and a 95% interval for the CAR-minus-GAM difference.

**Secondary test: calibration.** Divide held-out predictions into ten
equal-count groups and compare average predicted probability with the observed
make rate. Also compare each player's predicted total makes with actual total
makes rather than relying only on the league-wide pool.

**Secondary test: sparse-player uncertainty.** Define sparse players as the
bottom quarter of eligible players by fitting-shot count, using folds 1-4 only.
For those players, compare 90% posterior-predictive intervals for total made
shots in fold 5. Both models' intervals must include parameter uncertainty and
binomial shot noise; a plug-in interval for one model is not comparable with a
full predictive interval for the other. Report coverage and average interval
width. CAR has a useful
uncertainty advantage only if its coverage is closer to 90% without simply
making every interval wider, or its intervals are narrower without losing
coverage. Check that conclusion by resampling whole test games.

**Runtime and failures.** On the same machine and core limit, report total wall
time, failed fits, warnings, and available model diagnostics. For a joint model,
also report time per candidate grid and the final refit. Runtime is descriptive
and does not determine the winner. A failed or unreliable fit must be reported
rather than repaired silently.

**Decision rule.** A tiny numerical CAR improvement is a tie. CAR wins only if:

1. its held-out log loss is lower and the entire 95% paired bootstrap interval
   is below zero, without materially worse calibration; or
2. held-out log loss is a tie and CAR shows the sparse-player uncertainty
   improvement defined above consistently across bootstrap resamples.

If neither condition holds, choose GAM. If CAR is clearly worse on held-out log
loss, an uncertainty difference does not override that failure.

### Frozen full-league fold-4 comparison

**Pre-evaluation freeze, 2026-09-02:** the representative 40-player fallback
selected the approximately 4-foot grid before the full-league fits were run.
That grid is fixed for this preliminary all-318-player comparison. The completed
exact GAM and CAR fits both use folds 1-3, so fold 4 may now measure full-league
predictive behavior without refitting either model. This is not the sealed final
test, and it cannot change the grid, formula, priors, smoothing, or prediction
rules.

- The primary metric is pooled per-shot binomial log loss. Probabilities are
  clipped to `[1e-15, 1 - 1e-15]` only inside logarithms. Lower is better.
- Report the paired difference as GAM minus CAR, so a positive value favors CAR.
  Use 2,000 paired whole-game bootstrap resamples, seed `20260904`, and the
  percentile 95% interval. This is the sign-reversed form of the existing
  CAR-minus-GAM rule, not a new decision rule.
- For calibration, create ten equal-count groups separately for each model and
  report each group's predicted probability, observed make rate, and gap. Also
  report weighted mean absolute decile gap, maximum absolute decile gap, and
  per-player predicted-versus-observed total-make error. Use the same bootstrap
  game weights to compare weighted mean absolute decile gap. CAR is materially
  worse calibrated only if the entire 95% interval for GAM-minus-CAR calibration
  error is below zero.
- For sparse-player uncertainty, use the already frozen bottom 80 players by
  folds-1-to-3 attempt count and evaluate the saved 90% posterior-predictive
  intervals for fold-4 total makes. Report coverage and average width. The saved
  checkpoints retain intervals but not joint cell-level draws, so these fold-4
  uncertainty results are descriptive: they cannot satisfy the planned
  whole-game uncertainty-bootstrap condition or override the primary metric.
- Evidence favors CAR only when the full log-loss interval is above zero and
  CAR is not materially worse calibrated under the rule above. Evidence favors
  GAM when the full log-loss interval is below zero. Otherwise the fold-4 result
  is practically tied. Secondary measures do not override the primary result.
- The evaluation output is frozen to eight small Parquet tables: one manifest,
  one model-level metric table, calibration bins, player-level calibration,
  sparse-player intervals, one aggregate bootstrap summary, one interpretation
  record, and sanity checks. No shot-level or bootstrap-draw rows are saved.
- `R/spatial_full_league_fold4_comparison.R` must pass audit mode and be
  committed and pushed before fold-4 outcomes are opened. Its only outcome
  loader accepts fold 4 exactly and rejects fold 5 before selecting the outcome
  column. Settings and output definitions may not change after the run begins.

**Measured preliminary result, 2026-09-02:** the committed evaluation at
`42b4038` scored the same 38,820 fold-4 shots from 246 games for both models,
covering all 318 eligible players. All 34 evaluation checks passed. Exact-GAM
log loss was `0.6666759`; CAR log loss was `0.6614211`. The GAM-minus-CAR
difference was `0.0052548`, with a paired whole-game bootstrap 95% interval of
`[0.0040694, 0.0064287]`. The interval is entirely positive, so this preliminary
fold-4 evidence favors CAR under the frozen primary rule. This is not a final
test or permission to alter either model.

Calibration did not provide evidence against that interpretation. Weighted
absolute decile error was `0.0271601` for GAM and `0.0260283` for CAR; their
GAM-minus-CAR difference was `0.0011318`, with bootstrap interval
`[-0.0028915, 0.0050552]`. Maximum absolute decile gaps were `0.0766147` and
`0.0591602`. Player-total mean absolute errors were nearly identical: `4.9903`
makes for GAM and `5.0054` for CAR. These secondary summaries do not override
the primary log-loss result.

Sparse-player uncertainty was also nearly identical. Both 90% interval sets
covered 77 of 80 players (`96.25%`); average widths were `15.1519` makes for GAM
and `15.1150` for CAR. This does not show a clear CAR uncertainty advantage, and
the saved interval-only artifacts do not support the planned whole-game
uncertainty bootstrap.

Fold 5 make/miss outcomes remain sealed. The result is preliminary for an
additional reason: the representative 40-player subset of fold 4 previously
selected the shared grid, so fold 4 is not an untouched final holdout even
though it did not tune either model after the full-league fits. Runtime remains
descriptive only: the training-only CAR fit took 125.206 seconds, whereas the
exact-GAM fit took 64,452.7 seconds under its no-timeout LaunchAgent method.
That computational difference did not determine the predictive conclusion.

### Frozen one-time full-league fold-5 final test

**Pre-evaluation amendment, 2026-09-02:** use the existing folds-1-to-3 exact
GAM and Bayesian CAR fits without refitting, repairing, or changing either
model. Fold 4 selected the approximately 4-foot shared grid on the
representative 40-player fallback and then supplied the provisional full-league
comparison above. Fold 5 is the one-time untouched final predictive test. The
approach selected by this test may later be refit on all available data for
website production; that later fit is not another evaluation.

- Reuse the fold-4 primary metric, direction, clipping, calibration summaries,
  player-total errors, output schema, and interpretation exactly: pooled
  shot-level binomial log loss; clip to `[1e-15, 1 - 1e-15]` only for logs;
  report GAM minus CAR, where positive favors CAR; and do not let secondary
  measures override the primary result.
- Use 2,000 paired whole-game bootstrap samples, the percentile 95% interval,
  and seed `20260904`. This explicit final-test instruction supersedes the
  unused `20260905` reservation above and does not use any fold-5 information.
- Recreate 90% posterior-predictive total-make intervals for the frozen bottom
  80 players by folds-1-to-3 volume. Use the saved fits, the frozen 4,000 joint
  parameter draws and seeds, the fold-5 attempt pattern, and added binomial shot
  noise. This is prediction from existing models, not refitting.
- Evidence favors CAR only when the entire paired interval for GAM-minus-CAR
  log loss is above zero and CAR is not materially worse on the frozen
  calibration comparison. Evidence favors GAM when that log-loss interval is
  entirely below zero. Otherwise record a practical tie. Uncertainty and other
  secondary measures cannot reverse the primary classification.
- `R/spatial_full_league_fold5_comparison.R` must pass audit mode and be
  committed and pushed before fold-5 outcomes are opened. The run creates an
  exclusive ignored access marker before its single outcome read and refuses
  to run if that marker or any result already exists. It cannot fit or alter a
  model and saves only eight small aggregate or player-level Parquet tables,
  never shot-level rows or bootstrap draws.
- No model, grid, prior, smoothing, prediction, uncertainty, scoring, or
  interpretation rule may change after the pre-evaluation commit is pushed or
  after fold 5 is opened.

**Pre-outcome recovery record, 2026-09-02:** the first execution from pre-test
commit `49d98bb` stopped during outcome-free GAM uncertainty setup. R selected
the generic linear-model covariance path because the evaluation process had not
attached the already-frozen `mgcv` package; the serialized exact GAM itself and
its stored covariance were intact. No fold-5 access marker or result was
created, no fold-5 make/miss outcome was read, and neither model was refit. The
recovery adds an explicit `library(mgcv)` declaration so the same frozen
`vcov(..., unconditional = TRUE)` calculation dispatches to `vcov.gam`. This is
an execution correction only; every model and evaluation rule above is
unchanged.

**Measured final result, 2026-09-02:** after recovery commit `5d47e6b` was
pushed, the one-time evaluation scored the same 39,212 fold-5 shots from 246
games for both models and represented all 318 eligible players. Neither model
was refit. All 46 frozen artifact, access, prediction, uncertainty, bootstrap,
and output checks passed. Exact-GAM log loss was `0.6639103`; CAR log loss was
`0.6596804`. The GAM-minus-CAR difference was `0.0042299`, with a 2,000-sample
paired whole-game bootstrap 95% interval of `[0.0030254, 0.0053456]`. Because
the interval is entirely positive and CAR was not materially worse calibrated,
the frozen final-test rule favors CAR.

Calibration was close and does not weaken that conclusion. Weighted absolute
decile error was `0.0250503` for GAM and `0.0262130` for CAR. The
GAM-minus-CAR calibration-error difference was `-0.0011627`, with bootstrap
interval `[-0.0039865, 0.0044110]`; that interval crosses zero. Maximum absolute
decile gaps were `0.0702017` for GAM and `0.0523686` for CAR. Player-total mean
absolute error was `5.0490` makes for GAM and `5.0200` for CAR; root-mean-square
error was `6.4290` and `6.3732`, respectively. Mean observed-minus-predicted
bias was `-0.3976` makes for GAM and `-0.3291` for CAR.

For the 80 sparse players, GAM's 90% posterior-predictive intervals covered 76
players (`95.0%`) with average width `14.8625` makes. CAR covered 75
(`93.75%`) with average width `14.9769`. This does not show a CAR uncertainty
advantage and does not override the primary metric. The bootstrap used the
precommitted RNG kind, seed `20260904`, and fixed 2,000-draw code path; no
second fold-5 outcome read was made merely to repeat the one-time final test.

This is the final predictive comparison for these folds-1-to-3 fits, not a
claim that the two approaches have similar computational cost. The recorded
training times remain about 17.9 hours for exact GAM and 125.2 seconds for CAR;
fold-5 uncertainty regeneration took 94.1 and 54.9 seconds, respectively. The
approximately 4-foot grid was selected earlier on the representative 40-player
fold-4 fallback, and the final comparison covers only one NBA season. A later
all-data CAR fit may be used for production, but it is not another evaluation
and must not be presented as one.

## Frozen all-data CAR production fit

**Pre-fit registration, 2026-09-02:** model selection and final predictive
testing ended immutably at result commit `f7d7a15`. CAR won under the frozen
rule. Fold 5 may now enter the production fit only because that one-time final
evaluation is complete; production diagnostics cannot revise the comparison,
select another model, or be reported as predictive accuracy.

The production fit uses the exact 318-player eligibility set stored in the
comparison input artifact with SHA-256
`9608cd06ef83ab0866ad1c81f8d25802326d3f91cc349a81c570f46103eaae47`.
The eligibility rule may be reproduced as a check, but it may not add or remove
a player. Metadata-only preparation establishes 194,987 qualifying shots in
1,230 games across folds 1 through 5, with fold counts 38,794, 38,827, 39,334,
38,820, and 39,212. On the fixed approximately 4-foot grid these shots occupy
22,447 player-cells. The full surface remains 318 players by 156 cells, or
49,608 rows.

The model is the selected frozen R-INLA specification above without any change:

- grouped binomial makes and attempts, with `NA` outcomes only for empty
  prediction cells;
- one Normal(0, 1000) intercept per player and one independent replicated
  `besagproper2` surface per player;
- shared precision and dependence parameters with the frozen `pc.prec(1,
  0.01)` and `logitbeta(1, 1)` priors;
- the same unscaled, connected binary rook graph, court boundaries,
  `constr = FALSE`, `diagonal = 0`, simplified-Laplace strategy, one thread,
  package versions, and `safe = FALSE` behavior; and
- 4,000 joint posterior draws with seed `20260902`, followed by seed `20260903`
  for posterior-predictive binomial shot noise.

`R/spatial_car_production.R` has three isolated modes. `audit` reads metadata
and verifies the final selection. `prepare` reads all five authorized folds,
builds the fixed aggregate lattice, and atomically freezes input and
configuration without fitting. `run` is the only mode containing the model
call; it requires committed hashes, a clean pushed pre-fit revision, and an
exclusive lock. It has no arbitrary runtime ceiling and will never overwrite
an incomplete or completed artifact.

The production namespace is
`data/cache/spatial_car_production/season=2025-26/`. It is separate from every
comparison, fallback, and benchmark namespace. The ignored atomic artifacts
are the input, configuration, fit, 49,608-row player-cell surface, 318-row
player uncertainty summary, hyperparameter summary, model checkpoint,
completion checkpoint, stages, PIDs, and resource samples. The fit retains the
R-INLA joint posterior configuration required to generate later relocation
uncertainty. The local surface records point probabilities plus 90% posterior
probability intervals for every player-cell. Player summaries use the same
draws plus binomial shot noise to form 90% intervals for total makes.

The small tracked output is frozen to six Parquet files: production manifest,
surface QA, player uncertainty summary, hyperparameter summary, sanity checks,
and environment notices. It contains no shot-level or posterior-draw records.
The prepared input SHA-256 is
`395fff094a138035e84d3f332da9c0058be10919a192d707f8bd275345422ec6`;
the configuration SHA-256 is
`fc072f03e0579f32eba941717c4c8767912b72f82584d7e4842c6dab2699a80e`.
Both were frozen before `run` was allowed to call R-INLA.

No prediction comparison, validation score, relocation, slider, point-gain
estimate, or 0-100 score is part of this production fit. The implementation and
these settings cannot change after production outputs are viewed.

**Verified production result, 2026-09-03:** the pre-fit implementation and
prepared hashes were committed and pushed at `13ba7f7` before the sole model
fit began. The atomic run then completed on all 194,987 eligible shots from
1,230 games across folds 1 through 5. It retained the frozen 318-player set,
22,447 observed player-cells, 156 cells per player, and the complete 49,608-row
surface. This all-data run is the production fit of the CAR approach selected
by the final test; it is not an additional evaluation.

Setup took 0.930 seconds, R-INLA fitting took 132.959 seconds, point prediction
took 0.241 seconds, 4,000-draw uncertainty processing took 83.068 seconds, and
atomic serialization took 15.441 seconds. Total wall time was 234.383 seconds.
Periodic process-tree sampling recorded approximately 183.85 CPU seconds and a
peak resident-memory total of 3,436.19 MB. Free disk space changed from 130.750
GiB to 124.778 GiB. The in-memory fit was 601,620,664 bytes and its ignored
serialized form was 2,086,868,948 bytes; CPU and memory values are sampled
approximations rather than exact operating-system accounting.

All 55 recorded checks and an independent recovery verification passed. R-INLA
returned `fit$ok = TRUE`, mode status zero, 318 player intercepts, 49,608
replicated spatial effects, two shared CAR hyperparameters, and no captured fit
or posterior-sampling warnings or messages. The fitted precision mean was
2.056 and the dependence mean was 0.949. Point probabilities ranged from
0.175846 to 0.819166. Every player had a distinct centered spatial surface; all
cell intervals and all 318 player-total posterior-predictive intervals were
finite, ordered, and within feasible bounds.

The ignored fit SHA-256 is
`a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0`.
The atomic completion checkpoint SHA-256 is
`c2d6c92b36981feaf5870a58fb7eca84eff399ddd7ed1c7ed39d649c932f923c`;
its referenced input, configuration, surface, uncertainty, hyperparameter, and
model-checkpoint hashes were independently matched before the fit was loaded.
Recovery reused this completion and did not refit the model. The only
environment notice remains Arrow having been built under R 4.6.1 while the
frozen runtime is R 4.6.0; every Arrow operation and check completed.

## Approved Bayesian CAR package

**Recommendation:** use R-INLA's `inla()` with a binomial likelihood and a
replicated `besagproper2` field, one replication per player. Narayan approved
the stable R-INLA release and its required dependencies for the feasibility
pilot.

The intended model has:

- one fixed intercept per player;
- one independent CAR field per player over the common court grid;
- two shared CAR hyperparameters controlling overall variation and neighbour
  similarity; and
- player-cell attempts supplied as binomial trials.

`besagproper2` uses a proper Leroux-style precision matrix, so it matches the
earlier Leroux proposal. R-INLA's `replicate` mechanism creates independent
copies of a latent field with shared hyperparameters. This gives every player a
different surface without estimating a full player-by-player covariance matrix.
R-INLA can also draw from its approximate joint posterior for the predictive
uncertainty check.

Official references: the [R-INLA replication tutorial](https://www.inla.r-inla-download.org/r-inla.org/doc/vignettes/old-faq.html),
[`besagproper2` model definition](https://inla.r-inla-download.org/r-inla.org/doc/latent/besagproper2.pdf),
and [posterior sampling documentation](https://www.r-inla.org/learnmore/docs/reference/posterior.sample.html).

The reasonable alternative is `CARBayes::S.CARleroux()` fitted separately for
each player. Its model is direct and well matched to one player's surface, but
R-INLA is preferred because the alternative multiplies fitting and MCMC
diagnostics across every player and grid.

### CARBayes function review

`CARBayes` remains a reasonable package for a small number of areal outcomes,
but none of its relevant functions is a practical joint 318-player model here.

| Function | Can it create player-specific surfaces? | Fits for this experiment | Decision |
|---|---|---:|---|
| `S.CARleroux()` | Yes, only by fitting each player separately | 1,272 | Usable but reject as the main plan |
| `S.CARmultilevel()` | No; it gives all individuals one shared areal CAR effect | 4 | Reject: every player gets the same spatial pattern |
| `MVS.CARleroux()` | Yes, if players are treated as 318 outcomes | 4 | Reject: the full between-player covariance is unrealistic |

The fit counts cover three candidate-grid fits plus one final refit. For
`S.CARleroux()`, that is 318 players times four fits, or 1,272 MCMC models and
3,816 chain runs if each model uses three chains. It has about 29,574 to 82,044
unknown values across players at one grid size. Even at an unrealistically quick
one minute per fit, serial runtime is 21 hours; five minutes per fit is 106
hours. Parallel work would reduce elapsed time but not the total computation or
diagnostic burden.

`S.CARmultilevel()` would need only about 410 to 575 unknown values when player
intercepts are included, because it estimates only one 90- to 255-cell spatial
field. That efficiency is exactly why it is wrong: the court pattern is shared
by all players.

`MVS.CARleroux()` would estimate 28,620 to 81,090 player-cell effects plus 318
intercepts and an unrestricted 318-player covariance matrix with 50,721 unique
covariance values. That is roughly 79,660 to 132,130 unknown values in an MCMC
model, including a dense covariance component. It is not realistic for this
prototype.

The [CARBayes manual](https://cran.r-project.org/web/packages/CARBayes/CARBayes.pdf)
documents the single areal field in `S.CARmultilevel()` and the unrestricted
between-variable covariance in `MVS.CARleroux()`.

### Measured feasibility and expected R-INLA workload

The replicated R-INLA option needs four joint fits: one for each candidate grid
and one final refit. Each fit has about 28,940 to 81,410 latent and fixed unknown
values but only two shared spatial hyperparameters. R-INLA uses sparse matrix
calculations rather than thousands of MCMC chains, making this the only reviewed
joint option that appears practical.

The training-only 5-foot pilot used the pre-declared 40-player sample, 14,910
shots, 1,797 observed player-cells, and one thread. Data preparation took 0.259
seconds. The matching GAM fit took 0.955 seconds and the R-INLA fit took 14.754
seconds. Approximate peak R heap use was 253 MB for GAM and 287 MB for R-INLA;
this does not include all memory used by R-INLA's external process. The saved
fit files were 19.7 MB and 31.4 MB respectively. Neither fit failed or raised an
R model warning, and all 40 players had distinct centered spatial surfaces. The
local environment did emit package-build-version and system-memory-probe
messages, including repeated missing `/bin/kstat` messages from R-INLA; the fit
still returned `fit$ok = TRUE`. Treat these as unresolved environment notices,
not model convergence evidence.

That pilot deliberately measured the smallest feasible structures: its GAM used
`k = 10` with `discrete = TRUE`, and its CAR used the package's default priors.
Its fit objects are not the frozen comparison models above, and its timings are
lower-bound feasibility evidence rather than production benchmarks.

Multiplying fit time by 318 / 40 gives a deliberately simple estimate of 7.6
seconds for the full-league 5-foot GAM and 117 seconds for the full-league
5-foot R-INLA fit. This replaces the earlier expectation that the full
experiment would necessarily take hours. It is not a benchmark for the 3- or
4-foot grids, the folds 1-4 refit, posterior sampling, or nonlinear scaling, so
the full experiment may take longer. Runtime may size the work but may not
choose the statistical winner.

**Measured full-league CAR feasibility, 2026-08-31:** after the representative
40-player fallback selected the approximately 4-foot grid, the frozen replicated
R-INLA model completed a training-only fit for all 318 eligible players within
the 30-minute ceiling. It used 116,955 fold-1-to-3 shots, 19,475 observed
player-cells, and a 49,608-row prediction lattice. Setup took 0.563 seconds,
fitting took 125.206 seconds, posterior prediction and the sparse-player
uncertainty calculation took 42.166 seconds, and watchdog wall time was 176.107
seconds. Sampled process-tree CPU time was approximately 148.88 seconds and peak
resident memory was approximately 4,135.55 MB. The latter two are one-second
process-tree samples, not exact operating-system accounting.

The in-memory R-INLA object was 602,114,256 bytes and its reusable serialized
fit was 2,152,684,399 bytes. The fit returned `fit$ok = TRUE`, mode status zero,
no captured R-INLA model warnings or messages, finite probabilities for all
49,608 player-cells, and a different centered spatial surface for every player.
All 61 applicable pre-validation checks passed. The runtime emitted one
environment compatibility warning because `arrow` was built under R 4.6.1 while
the frozen runtime is R 4.6.0; Arrow operations completed successfully. Fold-4
and fold-5 make/miss outcomes were not read, so this establishes computational
feasibility only and says nothing about predictive accuracy.

**Measured discrete-GAM evidence, 2026-09-01:** the existing 40-player,
folds-1-to-3 comparison showed the computational benefit and the approximation
cost. `discrete = TRUE` reduced fitting time from 29.9 seconds to 1.94 seconds,
but it failed every pre-declared exact-equivalence tolerance: the maximum
observed-cell probability difference was 0.00730, the maximum full-lattice
difference was 0.0207, the mean lattice difference was 0.00130, the absolute
log smoothing-parameter difference was 0.0172, and the maximum smooth-EDF
difference was 0.0363. The tolerances were 0.0001, 0.0005, 0.00001, 0.01, and
0.01 respectively. This evidence rules out calling the discrete computation
numerically equivalent to the exact GAM.

The first all-318-player discrete-GAM attempt used the same 116,955 fitting
shots, 19,475 observed player-cells, 49,608-row lattice, 6,360 coefficients,
318 smooths, and one shared smoothing parameter. The machine or task was
suspended during execution, so the watchdog observed 2,519 seconds of wall time
but only approximately 609 seconds of process-tree CPU time before enforcing the
pre-declared 1,800-second wall-time ceiling on wake. Sampled peak resident memory
was approximately 3,305 MB. No fit, probabilities, uncertainty result, or atomic
completion checkpoint was published, and model warnings or convergence could
not be assessed. A follow-up process check found no benchmark process alive.
Fold-4 and fold-5 make/miss outcomes remained sealed. Treat this as a
runtime-interrupted computation, not a statistical model failure; do not start
a replacement run without an explicit new decision.

**Exact-GAM operational recovery, 2026-09-01:** the interrupted exact-GAM attempt
was archived without deletion under the dated identifier
`attempt=20260901T054422Z`. Its tracked Parquet manifest records ten original
and archived paths, byte sizes, and matching pre/post SHA-256 hashes, and it
identifies the termination as external rather than a statistical model failure.

The active repository path is now
`/Users/narayanlekhi/projects/nba-shot-analytics`. It moved as one complete Git
directory from the macOS-protected Documents location. The generated
LaunchAgent files use absolute paths, so moving the repository back later is
supported only after regenerating and revalidating both plists.

The dedicated audit-only LaunchAgent
`com.narayanlekhi.nba-shot-analytics.exact-gam-smoke` completed one run from the
new path with launchd exit code zero. It used the shared exact-GAM wrapper and
R executable, verified all 318 players, 116,955 folds-1-to-3 shots, and the
frozen input hash, and preserved false fold-4/fold-5 outcome-access flags. The
atomic marker recorded zero PSOCK workers and confirmed that fitting,
prediction, and uncertainty simulation never started. The smoke LaunchAgent
was unloaded after verification; the real exact-GAM LaunchAgent was never
loaded or started.

**Measured full-league exact-GAM feasibility, 2026-09-02:** the real user
LaunchAgent completed one no-timeout training-only run for all 318 eligible
players and exited with status zero without restarting. The fixed approximately
4-foot grid contained 19,475 observed player-cells and 49,608 player-cell
prediction rows built from 116,955 fold-1-to-3 shots. The fit used the frozen
grouped-binomial formula, 318 player intercepts, 318 player-specific thin-plate
smooths with `k = 20`, one shared `id = 1` smoothing parameter, fREML,
`discrete = FALSE`, and two PSOCK workers. It then used the frozen 4,000 GAM
coefficient draws and posterior-predictive seed.

The atomic completion checkpoint has SHA-256
`eaeb947ec92e51f17b3c8273bb0584226a60f47fb84bd523f66152a2c7f3c453`.
It references serialized-fit MD5 `0c378a0eba332161f6a689bcf952f5a1` and the
frozen input SHA-256 `9608cd06ef83ab0866ad1c81f8d25802326d3f91cc349a81c570f46103eaae47`.
The existing recovery entry point revalidated those references before the fit
was loaded for independent structural checks.

Setup took 6.508 seconds, fitting took 64,452.7 seconds (17 hours, 54 minutes,
13 seconds), full-lattice prediction took 689.438 seconds, uncertainty took
1.444 seconds, and total wall time was 65,197.32 seconds (18 hours, 6 minutes,
37 seconds). Approximate sampled process-tree CPU time was 66,851.51 seconds
and peak resident memory was 3,416.453 MB. Free disk space changed from
134.493 GiB at startup to 128.787 GiB at completion. The in-memory model was
1,324,936,224 bytes and the ignored serialized fit was 4,611,989,583 bytes.
CPU and memory are periodic process-tree samples rather than exact operating-
system accounting.

All 28 applicable pre-validation checks passed. The fit reported full
convergence after four outer iterations, maximum absolute gradient
`1.964493e-09`, no captured model warnings or messages, smoothing parameter
`0.8724094`, and maximum player-smooth EDF `8.663187`. All 49,608 draw-averaged
probabilities were finite and between 0.00537 and 0.93584. Every player had a
distinct centered surface, and all 80 sparse-player 90% posterior-predictive
intervals were finite, ordered, and feasible. The only recorded environment
notice during fitting was that Arrow was built under R 4.6.1 while the frozen
runtime was R 4.6.0. Runner shutdown emitted two benign `ps` status-1 warnings
while confirming that the already-exited PSOCK worker PIDs were gone; the saved
no-orphan check passed. Fold-4 and fold-5 make-or-miss outcomes remained sealed.
This establishes that the exact full-league GAM is computationally feasible
through the LaunchAgent method; it does not measure held-out accuracy or choose
a winner.

R-INLA is not installed from ordinary CRAN. It uses its own repository, compiled
binaries, and depends on spatial and sparse-matrix infrastructure including
`fmesher` and `Matrix`. Stable R-INLA 26.8.7 and its required dependencies were
installed from the official repository for the pilot.

### Fallback player sample if all-player fitting is impractical

The first choice remains all 318 eligible players. If a timing-only pilot shows
that even the replicated R-INLA model is not practical, use this pre-declared
fallback for a preliminary experiment:

1. After the game split, rank players by fitting attempts in folds 1-3 and divide
   them into four equal-sized volume groups.
2. With fixed seed `20260831`, sample 10 players uniformly without replacement
   from each group, without inspecting names, makes, model output, or test games.
3. Analyze the resulting 40 players with equal weight within each volume group.

This is unbiased within the declared volume groups and guarantees representation
of lower-volume players. It does not test full-league runtime, rare fit failures,
all-player calibration, or whether the model winner generalizes to every player.
It is therefore a preliminary comparison, not enough by itself to select the
production model.

**Activated 2026-08-31:** Narayan approved this pre-declared fallback after the
frozen all-player 5-foot GAM remained active for 4 hours, 24 minutes, and 7
seconds without completing its first atomic checkpoint. The process was stopped
gracefully after 3 hours, 44 minutes, and 27 seconds of CPU time. This was a
practical runtime decision, not a statistical model failure; no GAM result was
available to judge. Fold-4 and fold-5 make-or-miss outcomes remained sealed.
The saved 40-player artifact above was independently reproduced from non-outcome
metadata using seed `20260831`, with exactly 10 players from each folds-1-3
attempt-volume quartile. The fallback keeps every frozen formula, prior, grid,
seed, split, fitting method, prediction rule, and sanity check unchanged. Its
validation result must be labeled preliminary and cannot establish full-league
performance.

## Acceptance checks before website work

- The chosen model predicts unseen makes and misses at least as well as the
  simpler comparison.
- Predictions are calibrated: estimates near 40% should make about 40% when
  pooled over enough held-out attempts.
- No attempt moves to an unsupported or nearly unobserved location.
- Estimated gain never falls when the allowed relocation percentage rises.
- At least 75% of the distribution remains unchanged at the largest setting.
- Changes remain spread across multiple locations when multiple strengths exist.
- Results make basketball sense across different roles.
- A clean run reproduces derived outputs without committing raw data.

## Open decisions

- Whether the fallback-selected approximately 4-foot prediction grid remains
  appropriate for relocation after the model comparison is complete.
- Exact definition of demonstrated ability.
- Exact rule for spreading relocated shots.
- Whether the public uncertainty range should be 80%, 90%, or 95%.
- Whether 20 games and 250 attempts remains appropriate.
- Metric name and eventual 0-100 formula.
- Whether limited context sensitivity tests are useful after version one works.

## Historical cleanup queue

These claims are evidence about the old project, not current instructions. Leave
the historical files intact during the prediction experiment; clean up active
documentation only as a separate reviewed change after the spatial model passes.

- `CLAUDE.md` says work belongs on `main`, CAR is out of scope, zones are central
  to the model and website, 20 games and 250 attempts can never be revisited, and
  uncertainty intervals are unnecessary. Those claims conflict with `AGENTS.md`
  and this plan.
- `docs/METRIC_REFRAME.md` rejects fixed relocation percentages, compares CAR
  with a Gaussian process, retains zones for reporting, and proposes 10%, 20%,
  and 30% checks. The current plan uses GAM versus CAR, removes zones from the
  replacement presentation, and uses 0% through 25% in five-point steps.
- `ZONE_MODEL_ACCEPTANCE.md` pre-registers only the completed 14-zone to 10-zone
  change. Its requirement that rankings remain similar must not be reused for a
  replacement metric intended to answer a different question.
- `README.md` and messages in `R/03_compute_scores.R` still describe 14 rows or
  14-element baselines even though the preserved pipeline now uses 10 zones.

## Known limitations

- Relocation cannot create a real shot opportunity.
- Accuracy may fall as volume rises and defenses adjust.
- Players often attempt shots only when conditions are favorable.
- Public shot charts lack defender distance and shot-clock state at the exact
  coordinate level.
- Field-goal logs do not fully capture the value of drawing free throws.
- The uncertainty range measures limited evidence, not every missing context or
  a guaranteed causal gain.

## Completed

- Created `codex/spatial-shot-selection` from the completed `zone-model-10`
  branch.
- Added repository-level Codex instructions.
- Preserved the zone pipeline and Claude-era documents as history.
