# Spatial Shot Relocation: Living Plan

**Status:** Planning. An isolated training-only feasibility pilot exists; no
production spatial model or relocation simulation has been built.

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
  draws. Use `20260904` for fold-4 whole-game bootstrap resamples and `20260905`
  for fold-5 whole-game bootstrap resamples.
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

- Which of the pre-registered 3-, 4-, or 5-foot grids the training-only selection
  chooses, and whether that prediction grid remains appropriate for relocation.
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
