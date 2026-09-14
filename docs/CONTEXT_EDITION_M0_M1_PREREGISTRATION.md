# Context Edition M0 versus M1 preregistration

Status: frozen proposal for Narayan's review; no model or validation outcome has been opened

Protocol version: `context_m0_m1_protocol_v0.1.0`

Canonical schema: `context_field_goal_v0.1.2`

Taxonomy: `context_taxonomy_v0.1.0`

Join specification: `shotchart_espn_exact_clock_player_v0.1.1`

## Basketball question

> Given information known about a player's field-goal attempt before release, how well can we estimate its scoring value, and does a compact description of how the player created and finished the shot improve that estimate beyond a pooled player baseline?

M0 measures the forward value of point value and a player's historical make tendency. M1 asks whether the frozen finish and explicit-creation taxonomy adds stable information. Neither model measures overall player quality, offensive impact, causal shot choice, or the value of free throws.

## Recovered foundation

The canonical branch and its remote both pointed to commit `69610c3` before this branch was created. The accepted local canonical file still has 433,942 rows and SHA-256 `292eba28ce0a37788945312169c0986c60bc9db5c6308d322bf5f8e073b2ded7`. The private review sample and all four source files also match their recorded hashes. All 18 tracked aggregate payloads passed their manifest hashes.

This task does not rebuild the canonical dataset. The 2021-22 and 2022-23 rows establish the initial training source. Later seasons require separate canonical builds under an approved version before execution.

## Candidate structures

| Candidate | Basketball meaning | Sparse and new players | Decision |
|---|---|---|---|
| League intercept plus point value | One league make rate for twos and threes | New players work, but known players receive no history | Reject because it makes M0 artificially weak |
| Point value plus unpooled player fixed effects | Each known player gets an independent baseline | Low-volume estimates can become extreme; new players have no coefficient | Reject |
| Point value plus one pooled player intercept | Each player receives a stabilized historical baseline | REML shrinks low-volume players toward the league baseline; new players use zero player deviation | Select for M0 |
| Add a training-season coefficient | Adjusts for historical calendar shifts | A future season has no fitted level or honest extrapolation rule | Reject; diagnose drift by validation season instead |
| Additive finish and creation effects | Measures the average value carried by each taxonomy axis after point value and player baseline | Uses league support for each category | Select for M1 |
| Finish by creation interaction | Assigns a separate adjustment to each observed combination | Sparse combinations become unstable and interpretation changes | Reject until forward evidence supports a later model |
| Player by family effects | Gives each player a taxonomy profile | Adds many weakly supported effects | Reject because this is M4, not M1 |

The selected pair answers one narrow comparison. M0 is credible because it uses point value and partial pooling. M1 differs only by the two taxonomy axes.

## Symbols and targets

For shot \(i\):

- \(y_i\) equals one for a make and zero for a miss.
- \(v_i\) equals two or three and is known from the attempt definition.
- \(j[i]\) identifies the shooter.
- \(f[i]\) identifies one of seven finish families.
- \(c[i]\) identifies one of four creation families, including `other_or_unknown`.
- \(p_i\) is the predicted make probability.
- \(e_i = v_i p_i\) is predicted field-goal points.
- \(r_i = v_i y_i\) is realized field-goal points.

The model uses a Bernoulli likelihood at shot level:

\[
y_i \sim \operatorname{Bernoulli}(p_i), \qquad
\operatorname{logit}(p_i) = \eta_i.
\]

Execution may group shots with identical model inputs into makes and misses. The grouped binomial likelihood differs from the repeated Bernoulli likelihood only by a parameter-independent combinatorial constant, so it produces the same coefficient and variance estimates for this model.

## Frozen M0

\[
\eta_i = \beta_0 + \beta_3 I(v_i=3) + b_{j[i]},
\qquad b_j \sim N(0, \sigma^2_{player}).
\]

`two` is the point-value reference. The three-point coefficient belongs in the make-probability formula because two- and three-point attempts have different baseline make rates. Point value also multiplies probability after prediction. Leaving it out of the formula would force equal make probabilities and would weaken M0 by design.

The executable formula is:

```r
cbind(makes, misses) ~
  point_value_factor +
  s(player_id_factor, bs = "re")
```

Aggregate training rows by player and point value. The player term uses a full-rank ridge penalty, which corresponds to independent zero-centered Normal effects. REML estimates its variance from training outcomes only.

## Frozen M1

\[
\eta_i = \beta_0 + \beta_3 I(v_i=3) + b_{j[i]}
  + \alpha_{f[i]} + \gamma_{c[i]}.
\]

`regular_jumper` is the finish reference. `other_or_unknown` is the creation reference. Treatment coding sets both reference coefficients to zero. The player effects follow the same pooled structure as M0.

The executable formula is:

```r
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re")
```

Aggregate training rows by player, point value, finish family, and creation family. The model includes no interaction, player-family effect, location, distance, game state, score, or team effect.

## Engine and exact fit configuration

Use installed `mgcv` 1.9-4. It already supports the project's R workflow and represents an iid player random intercept as `s(player_id_factor, bs = "re")`. Its official local documentation states that REML gives a conventional likelihood-based random-effect treatment and that an unseen random-effect level receives a zero contribution.

Freeze these arguments for both models:

```r
mgcv::gam(
  formula = MODEL_FORMULA,
  family = stats::binomial(link = "logit"),
  data = training_counts,
  method = "REML",
  optimizer = c("outer", "newton"),
  control = mgcv::gam.control(),
  select = FALSE,
  gamma = 1,
  na.action = stats::na.fail,
  drop.unused.levels = FALSE,
  discrete = FALSE
)
```

The protocol file stores formulas but contains no fitting call. Set unordered factor levels and `options(contrasts = c("contr.treatment", "contr.poly"))` before a future fit. Sort aggregate rows by the grouping keys before fitting.

Lock execution to R 4.6.0, `mgcv` 1.9-4, `Matrix` 1.7-5, `arrow` 25.0.0, `dplyr` 1.2.1, `tidyr` 1.3.2, and `readr` 2.2.0. A version mismatch stops the comparison. Model fitting has no random initialization; the bootstrap uses the seed below. Hash every input and configuration before fitting, and require the same hashes for recovery.

`lme4` would offer a direct logistic mixed model, but it is not installed. A conjugate beta-binomial baseline would not provide the same additive M1 structure. A full Bayesian taxonomy model would add priors and computation without serving this first comparison. No dependency was added.

## Prediction rules

For known players, use `predict.gam(type = "link")` with their training-only random intercept, then apply `plogis()`. For a player absent from training, predict the fixed part while excluding `s(player_id_factor)` with `newdata.guaranteed = TRUE`; this sets the player deviation to zero without borrowing validation outcomes.

Every validation shot receives \(p_i\) and \(e_i=v_i p_i\). Predictions cannot update player effects within a validation season. A team or role change receives no special adjustment because neither model contains team or role.

M1 requires the frozen seven finish and four creation levels. A new raw finish label stops the outcome-free preparation before validation outcomes load. Narayan must approve a versioned mapping change. The builder cannot collapse it into an existing family after results appear. `other_or_unknown` remains an ordinary creation level and all such shots stay in the sample.

## Rolling-origin splits

The split specification freezes four chronological comparisons:

1. Train on 2021-22 and 2022-23; validate on 2023-24.
2. Train through 2023-24; validate on 2024-25.
3. Train through 2024-25; validate on 2025-26.
4. Train through 2025-26; reserve 2026-27 for prospective confirmation.

Each season contributes complete games. No shot from a validation game can enter training. The first three comparisons form the retrospective model decision. Report each one and their pooled out-of-fold predictions. The fourth comparison cannot change the protocol selected from the first three.

The tracked split file contains season and game rules but no game IDs or outcomes. A future private manifest may contain `season`, text `game_id`, comparison assignment, source hash, and row count. It must derive from metadata before selecting the make/miss column. The execution audit must record false outcome-access flags until all input, formula, and prediction checks pass.

## Eligibility and support

- Retain every valid canonical field-goal attempt. The first training source remains all 433,942 accepted shots.
- Include every player with at least one training attempt. Do not impose a minimum that favors established players.
- Score all validation players. Returning players use their pooled training effect; unseen players use a zero player deviation.
- Keep players who appear in one season and players who change teams.
- Keep shots without a verified ESPN join because M0 and M1 use the primary shot record and frozen taxonomy.
- Keep `other_or_unknown` creation shots.
- Ignore score-context fields in both models.
- Require positive training support for every frozen taxonomy family before fitting M1. Zero support stops execution. A family with fewer than 1,000 training shots or under 1% training share receives a rare-family flag but stays intact.
- Report subgroup calibration only at 200 or more validation shots. Smaller groups keep their counts and predictions but receive no standalone precision claim.

Define player-volume groups within each comparison from training attempts only. Put returning players into four equal-count quartiles after sorting by attempt count and player ID; report unseen players as a fifth group. This keeps validation outcomes out of the grouping rule.

## Metrics

### Primary metric

Use pooled shot-level Bernoulli log loss on the three out-of-fold validation sets:

\[
L_m = -\frac{1}{N}\sum_i [y_i\log(p_{im})+(1-y_i)\log(1-p_{im})].
\]

Clip probabilities to `[1e-15, 1-1e-15]` only inside logarithms. Log loss is strictly proper for make probability. Point value does not change whether the make probability is honest; expected-point diagnostics handle the two-versus-three consequence separately.

Report Brier score as a probability diagnostic. It cannot select the model.

Report rank-based ROC AUC as a discrimination diagnostic. AUC is not a proper probability score and cannot select the model.

### Expected field-goal points

Report shot-level expected-points RMSE, whole-game field-goal-points MAE and RMSE, and signed points bias per 100 attempts. Squared error targets the conditional mean. Game totals translate errors into basketball units. These measures remain secondary so a model cannot win by exploiting one point-value mix while degrading probability quality.

For any game, player, or taxonomy family \(G\):

\[
\widehat{P}_G=\sum_{i\in G}v_i p_i, \qquad
P_G=\sum_{i\in G}v_i y_i.
\]

Expected points per shot equals \(\widehat{P}_G/n_G\). Report predicted and realized values by season, point value, finish, creation, and player-volume group.

## Calibration

Report overall predicted make rate, observed make rate, signed calibration-in-the-large, and absolute calibration-in-the-large error. Fit the standard diagnostic calibration intercept with `qlogis(p)` as an offset and the calibration slope with `qlogis(p)` as a predictor. Report `NA` with the failure reason if either diagnostic cannot be estimated.

Create ten equal-count bins separately for each model after pooling the three out-of-fold prediction sets. Sort by probability and original deterministic row order to break ties. Report count, mean prediction, observed rate, signed gap, and expected calibration error. Freeze those bin memberships for paired bootstrap calculations.

Repeat mean-prediction versus observed-rate summaries for two- and three-point attempts; seven finish families; four creation families; `other_or_unknown`; each validation season; and training-volume groups. Subgroup findings diagnose where a change occurs. They cannot override the primary metric.

M1 is materially worse calibrated when the lower endpoint of the paired 95% bootstrap interval for either of these M1-minus-M0 errors exceeds `0.005`:

- absolute calibration-in-the-large error;
- equal-count-decile expected calibration error.

The margin equals half a percentage point in make probability. Calibration intercept and slope remain reported diagnostics because their scales do not share that margin.

## Paired whole-game bootstrap

Use 2,000 resamples with seed `20260914` and `RNGkind("Mersenne-Twister", "Inversion", "Rejection")`. Within each of the three validation seasons, sample that season's games with replacement until the original game count is reached. Apply the same game multiplicities to both models, then pool all sampled shots.

Report percentile 95% intervals for M1-minus-M0 log loss and calibration errors. The standard error for the simplicity rule is the sample standard deviation of the 2,000 paired log-loss differences. Two thousand replicates provide stable interval endpoints for this two-model decision at modest cost because each replicate reweights saved game summaries rather than refitting a model.

Do not trim, cap, or downweight games with unusual shot counts. The primary metric is shot-weighted, while the bootstrap unit remains the whole game. Report game-count and shot-count distributions so a large game stays visible.

## Mechanical model decision

Let \(L_0\) and \(L_1\) be pooled out-of-fold log losses. Let \(SE_\Delta\) be the paired-bootstrap standard error of \(L_1-L_0\).

Apply these rules in order:

1. Select M0 if \(L_1\ge L_0\).
2. Select M0 if \(L_0-L_1\le SE_\Delta\). M0 is then within one standard error of the empirical best.
3. Select M0 if M1 is materially worse calibrated under the frozen `0.005` rule.
4. Select M0 if M1 has lower log loss in fewer than two of the three retrospective validation seasons.
5. Select M1 only if it passes all four gates.

This rule uses the pooled result for the main decision and individual seasons as a breadth guard. Secondary expected-point, subgroup, discrimination, runtime, and interpretability summaries cannot reverse it.

## Leakage and artifact controls

The feature matrix allows point value and a pooled player intercept in both models, then finish and creation in M1. It blocks coordinates, distance, clock, score, home/away, team, raw play-by-play text, player-family terms, free throws, capacity, and every post-shot field.

A future execution must enforce these boundaries:

1. Read season and game metadata first and publish private split manifests.
2. Filter training seasons before selecting training outcomes.
3. Build validation predictors without selecting validation outcomes.
4. Fit both models and pass formula, support, convergence, level, row, and prediction checks.
5. Create an exclusive access marker before one authorized validation-outcome read.
6. Save aggregate and player-level results only.

Keep grouped training data, fit objects, shot predictions, bootstrap draws, game IDs, player IDs, and access markers ignored. Git may contain formulas, configuration, source hashes, package versions, aggregate metrics, deidentified support summaries, sanity checks, and manifests that contain no private keys.

Freeze the future tracked result schema to these small tables:

- `execution_manifest.csv`: protocol, source, split, formula, package, and artifact hashes;
- `fit_diagnostics.csv`: convergence, variance, dimensions, timing, memory, sizes, and warnings;
- `pooled_metrics.csv` and `season_metrics.csv`: registered probability and point metrics;
- `calibration_bins.csv` and `subgroup_calibration.csv`: counts and aggregate calibration only;
- `bootstrap_summary.csv`: point estimate, standard error, and interval endpoints without draw rows;
- `model_selection.csv` and `execution_checks.csv`: mechanical decision and pass/fail evidence.

Sort every table by its explicit key and serialize it with fixed column order, UTF-8 text, `.` decimal notation, and missing values as empty fields. The manifest records each payload's byte size and SHA-256. Private game-level and player-level rows stay outside Git.

## Fit checks for the next stage

Stop before validation outcomes if either model fails to converge, returns non-finite coefficients or smoothing parameters, has a zero or boundary player variance that prevents the planned interpretation, loses a required factor level, uses different shots, or produces missing or out-of-range probabilities. Record expected unseen-player zero effects separately from errors.

The future execution must record setup, aggregation, fitting, prediction, evaluation, and bootstrap time; peak sampled memory where available; object and serialized sizes; warnings; convergence status; row counts; player counts; family support; hashes; and package versions. Runtime describes feasibility and cannot select the model.

## Structural and synthetic test plan

`R/context_edition_m0_m1_structural_tests.R` uses only configuration and invented rows. It checks formula construction, config agreement, reference levels, unknown and rare categories, pooled-player policies, expected-point conversion, whole-game chronology, sealed outcome flags, deterministic seeds, toy metrics, calibration, paired bootstrap behavior, the decision rule, invalid-value rejection, and the M2 feature block.

The test publishes one small aggregate table. It does not read the canonical Parquet file, any later-season file, any game ID, or any real outcome. It contains no fitting function.

## Computation estimate and recovery

The accepted two-season source has 700 players. M0 can contain at most 1,400 grouped rows. M1 can contain at most 39,200 grouped rows before absent player-point-family combinations reduce it. Each fit estimates one player coefficient per training player, a small fixed-effect block, and one player-variance parameter.

Expect each grouped `mgcv::gam` fit to take minutes rather than the multi-hour spatial GAM workload, with memory in the hundreds of megabytes to low single-digit gigabytes. This is a planning estimate, not a benchmark. The next task should run a training-only timing and convergence preflight before it reads validation outcomes. If the exact fit proves impractical, Narayan must approve a computational amendment based only on training evidence.

Write fit and prediction stages atomically. A completion manifest must hash inputs, config, fit, predictions, and checks. Recovery may reuse a hash-verified completed stage but cannot restart automatically or alter a model after validation access.

## Review answers and claims

- M0 is a fair baseline because it includes point value and a pooled player effect.
- M1 isolates the joint addition of the finish and explicit-creation taxonomy. It does not isolate creation alone.
- Point value is an attempt property known before the result. It enters both make probability and expected-point conversion.
- M1 contains no player-family term and therefore does not become M4.
- Low-volume players receive shrinkage. Unseen players receive the population fixed part for their point and taxonomy levels.
- Log loss checks honest probabilities; expected-point and game-total errors supply basketball units.
- The selection table executes without judgment after results appear.
- An M1 win would support a descriptive claim that the frozen taxonomy adds stable forward predictive information beyond point value and pooled player history.
- An M1 win would not show causal value from changing shot type, overall offensive impact, defense-adjusted skill, free-throw value, or future efficiency at a different volume.

## Earlier-document conflicts

The feasibility audit labeled M0 as point value plus broad finish and reserved player effects for M4. The canonical leakage register repeats those provisional ladder labels, and the canonical contract's next-stage sentence frames creation as the only M1 addition. The current project request instead defines M0 as a pooled player baseline and M1 as the first finish-plus-creation model. This preregistration follows the current request without editing the historical audit, contract, taxonomy, or canonical rows. Narayan should confirm that ladder change before fitting.

## Decisions for Narayan

1. Approve or reject the revised ladder boundary: M0 uses point value plus a pooled player intercept; M1 adds both taxonomy axes. Recommendation: approve because it gives M0 a credible player baseline and gives M1 one clear increment.
2. Approve or amend the calibration and season-breadth gates: a `0.005` paired calibration margin and M1 wins in at least two of three seasons. Recommendation: approve because the rules block a narrow or visibly miscalibrated M1 gain without letting secondary metrics choose the winner.

## Next stage after approval

Canonicalize 2023-24 through 2025-26 under a separate, versioned task using outcome-blind taxonomy and split checks. Then run a training-only engine preflight. Freeze any necessary computational amendment before the first validation outcome is opened. Do not touch 2026-27.
