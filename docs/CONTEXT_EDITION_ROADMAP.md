# NBA Shot Selection: Context Edition roadmap

Status: living project context for Codex

Last updated: 2026-09-29

## How Codex must use this file

Read this file before planning or executing any Context Edition task. Then read
the committed preregistration and execution document for the active stage. The
stage-specific preregistration controls exact formulas, thresholds, seeds,
features, and stop conditions when it is more specific than this roadmap.

At the start of a task:

1. Recover the named branch, commit, private checkpoints, locks, and active
   processes before starting new work.
2. Verify source, configuration, fit, prediction, and completion hashes.
3. Respect the outcome-access table and feature allowlist.
4. Reuse a valid checkpoint instead of refitting.
5. Commit and push implementation before opening an authorized outcome.

At the end of a completed stage, update the current-state section of this file
in the same feature branch. Record measured facts only. Do not rewrite the
historical preregistration documents.

## Project question

The Context Edition asks:

> Which broad, publicly observable features of an NBA field-goal attempt add
> stable future predictive information about make probability and expected
> field-goal points after accounting for the player's history, and how can that
> information describe a player's shot profile without claiming that the player
> can freely choose or exchange attempts?

This project builds a predictive description of shot selection. It does not
estimate the causal effect of telling a player to take a different shot.

## Why the project changed

The completed Location Edition estimates player-specific shooting surfaces and
hypothetical relocation gains. It remains a valid location study, but location
alone does not describe how an attempt was created, how it was defended, or why
it was available.

The Context Edition adds one defensible factor family at a time. Each model must
beat the preceding model under frozen future-game rules before the project adds
more complexity. This ladder identifies which information improves prediction
and prevents one large model from hiding where its value comes from.

## Current measured state

### Canonical data

- Five seasons: 2021-22 through 2025-26.
- 6,150 games and 1,091,329 field-goal attempts.
- Canonical schema: `context_field_goal_v0.1.2`.
- Taxonomy: `context_taxonomy_v0.1.0`.
- Join specification: `shotchart_espn_exact_clock_player_v0.1.1`.
- Finish taxonomy has seven registered families with complete coverage.
- Creation taxonomy has four levels. `other_or_unknown` covers about 50.37% of
  attempts and must remain explicit rather than guessed.

### Selected M1 result

M1 adds broad finish and creation type to point value and a partially pooled
player baseline. It qualified in all three historical rolling-origin seasons.

- Pooled validation shots: 657,387.
- M0 log loss: `0.6732749661`.
- M1 log loss: `0.6511742771`.
- M1-minus-M0: `-0.0221006890`; negative favors M1.
- The pooled one-standard-error, calibration, and season-breadth gates passed.

Interpretation: broad shot type carries repeatable future predictive information
beyond two-versus-three status and player history. The result does not establish
causality, total offensive value, defensive adjustment, or superiority over a
location model.

### Completed stage: M2 historical development evaluation; retain M1

M2 keeps M1 unchanged and adds one shared nonlinear smooth of canonical
`shot_distance_feet`. D1 is a distance-only diagnostic and cannot win model
selection.

Frozen formulas:

```r
# D1: diagnostic only
cbind(makes, misses) ~
  point_value_factor +
  s(player_id_factor, bs = "re") +
  s(shot_distance_feet, bs = "cr", k = 10, m = 2)

# M2: formal candidate
cbind(makes, misses) ~
  point_value_factor +
  finish_family +
  creation_family +
  s(player_id_factor, bs = "re") +
  s(shot_distance_feet, bs = "cr", k = 10, m = 2)
```

Current execution state at this update:

- Approved design commit: `5b54ebf6354198b2111fba084e55a9a473802eac`.
- Pre-fit implementation commit: `18cbe2ffcd85641214419d88a5520f0b55e561da`.
- Recovery implementation commit: `669e48ae4270d8448fe460b19baa291f159f09e0`.
- Training-preflight result commit: `a0d8ae71a89cbd5b1b6ee5a6ebf2341eaefe9846`.
- D1 was fitted once on 2021-22 and 2022-23, preserved privately, and recovered
  without refitting.
- M2 was fitted exactly once on the same training window.
- Both models passed the registered `k = 10` adequacy rule and every corrected
  frozen check.
- The private atomic checkpoint and both prediction hashes recovered without
  refitting either model.
- No validation outcome was opened during the M2 preflight.
- The historical M2-versus-M1 evaluation runner, split configuration, recovery
  rules, output schema, and structural/synthetic test suite are frozen on the
  isolated evaluation branch.
- The initial outcome-free audit reverified all three historical M1 fits and
  the first-window M2 fit. All six registered model-window fits now exist;
  each later M2 component was fitted once under the frozen runner.
- `development_1` reused the exact first-window M1 and M2 fits, opened the
  2023-24 outcome partition once, and fit no model during evaluation. Its 1,230
  games contained 218,700 shots from 568 players.
- M1 log loss was `0.6526580077`; M2 log loss was `0.6441082854`. The registered
  M2-minus-M1 difference was `-0.0085497223` with a paired whole-game bootstrap
  standard error of `0.0003190340` and 95% interval
  `[-0.0091846695, -0.0079310758]`. This first development window favors M2 on
  the primary metric but cannot select the final model by itself.
- M2's ten-bin ECE was worse by `0.0087576814`, with a paired 95% interval of
  `[0.0065030683, 0.0101974740]`. This registered calibration limitation remains
  diagnostic until the three-window pooled decision is available.
- The private result and prediction checkpoint hashes passed recovery
  verification without reopening the canonical outcome. The successful process
  left an empty ignored evaluation lock directory, which is preserved for an
  operational recovery decision before the next audit.
- `development_2` reused the verified M1 fit and the once-fitted M2 artifact,
  opened 2024-25 once, and fit no model during evaluation. Its 1,230 games
  contained 219,527 shots from 566 players.
- M1 log loss was `0.6509035230`; M2 log loss was `0.6431333748`. The registered
  M2-minus-M1 difference was `-0.0077701483`, with a paired whole-game bootstrap
  standard error of `0.0003353791` and 95% interval
  `[-0.0084216476, -0.0071371329]`. The second development window therefore
  favors M2 on the primary metric by more than one bootstrap standard error.
- M2's ten-bin ECE was worse by `0.0073817391`, with a paired 95% interval of
  `[0.0043734351, 0.0091782846]`. Its absolute calibration error was worse by
  `0.0034921603`, with interval `[0.0001311615, 0.0043478717]`. Neither lower
  bound exceeded the registered `0.005` material-worsening threshold, so the
  frozen calibration gate passed despite the descriptive calibration loss.
- The private M2 validation-access records are now true for 2023-24, 2024-25,
  and 2025-26, each opened once. The hard 2026-27 guard remains false and rejects
  access in every runner mode. The frozen configuration's pre-result access
  flags remain unchanged; they are not the current execution ledger.
- Reuse requires exact split, formula, factor, engine, configuration, manifest,
  and artifact hashes; a merely similar fit is rejected.
- Authorized repair `da1dfd3a584acca2a65ad6334ec46fc670c9e74c` moved predictor
  checks before outcome access and restored the exact training-volume quartiles
  plus unseen-player group. All 92 outcome-free tests passed. Separate
  supplements at `3238841` and `82cc785` restored the earlier-window quartile
  diagnostics without altering original results, refitting, predicting, or
  reopening canonical outcomes.
- The third-window M2 fit completed once on 872,169 training shots, 913 players,
  and 81,746 grouped rows. Its SHA-256 is
  `a1cf2afe399f04403f52570ae70b75c3127f53abd7ebdcdf1f43c679d4c00bd4`.
  Full convergence, finite covariance, registered `k=10` adequacy, deterministic
  training predictions, taxonomy, and 178-row synthetic checks passed. The
  predictor-only validation-support check also passed without reading outcomes.
- Direct chat authorization and confirmation of the corrected M2 hash resolved
  the earlier pre-access stops. Execution from `0c0a721` reused both models and
  opened 2025-26 once at 2026-09-28 21:26:58 UTC. No M1 or M2 refit occurred.
- `development_3`, committed at `7e58153`, contains 219,160 shots from 1,230
  games and 582 players. M1/M2 log losses are 0.6499648682/0.6433467898;
  difference -0.0066180784, SE 0.0002993954, 95% interval
  [-0.0071797533, -0.0060363608]. Its calibration gate passed despite higher
  M2 ECE. The private atomic result passed recovery verification.
- The pooled comparison contains 657,387 shots from 3,690 games. M1/M2 log
  losses are 0.6511742771/0.6435288572; difference -0.0076454199 and paired SE
  0.0001813510. M2 improved all three seasons and exceeded one SE, but failed
  the registered material-calibration gate. The mechanical result is **retain
  M1**. M2's pooled ECE increased by 0.0069804805 and absolute calibration
  error by 0.0016907377. No diagnostic overrode or changed a selection rule.
- The pooled log-loss 95% interval is [-0.0079871425, -0.0072691795]. The ECE
  difference interval is [0.0057229897, 0.0082350598], whose lower bound exceeds
  the frozen 0.005 margin. One extra identical bootstrap reporting pass recovered
  intervals omitted by the frozen publisher and reproduced its SE and decision;
  it reopened no canonical outcomes and changed no rule or original result.
- This completes historical development selection, not prospective
  confirmation. M2 does not advance and cannot use 2026-27 as a rescue test.
  M1 remains the immutable Context baseline. Future work requires separate
  authorization; no M3 model or prospective analysis has begun.

### Completed stage: M3 predictor-data audit

The predictor-only audit is complete under
`docs/CONTEXT_EDITION_M3_DATA_AUDIT_PREREGISTRATION.md`, with measured results
in `docs/CONTEXT_EDITION_M3_DATA_AUDIT_RESULTS.md`.

- Period and period clock are complete across 1,091,329 historical attempts.
- Home/away is unavailable for 10.77% of attempts; verified score margin is
  unavailable for 11.03%.
- Missingness is concentrated in ambiguous and unmatched play-by-play joins.
  All unique exact matches have home/away status, and 99.71% have verified score
  margin.
- The simplest defensible model candidate uses explicit unknown home/away,
  neutral score-margin fill plus a missingness indicator, and a complete-case
  diagnostic. Predictive mean matching does not advance because join failure is
  not an ordinary unobserved numeric measurement.
- Shot clock and direct defense remain blocked without a verified same-attempt
  source.
- No outcome column was read, no model was fit, and 2026-27 remained sealed.

## Model ladder and stage gates

### Active next stage: frozen M3 preregistration, no execution

Audit result `ce042f3` preserves the interrupted aggregate audit publication.
`docs/CONTEXT_EDITION_M3_PREREGISTRATION.md` freezes M1 plus period (1–4/OT),
linear period time, home/away/unknown, linear verified score margin with neutral
zero fill and its missingness indicator. PMM does not advance. The complete-case
diagnostic uses the same saved predictions, without another model fit.

`docs/CONTEXT_EDITION_M3_RUNNER.md` records the outcome-free implementation,
predictor dimensions and resource estimates. All predictor-side gates passed.
M3 has not been fit; no validation outcome was read in this stage. The runner
has no validation execution mode. It reuses unchanged M2 evaluation helpers and
freezes the same rolling windows, primary metric, bootstrap and selection gates
for M3 versus retained M1. Distance is excluded from the model.

The first fit needs separate training-only authorization. Exact grouping leaves
430,698 first-window rows; the conservative working-memory estimate is 10.2 GiB.
Later windows exceed the current 16 GiB machine's registered memory-headroom
gate. No engine or statistical change is authorized to address that limitation.
2026–27 remains sealed. Location Edition, portfolio and M1/M2 results are protected.

### M0: pooled player baseline — complete

Features:

- Two-versus-three status.
- One partially pooled player intercept.

Purpose: establish a fair, simple player-history baseline.

### M1: broad shot type — selected

Adds:

- Finish: dunk, layup, floater, hook, regular jumper,
  fadeaway/turnaround, and step-back.
- Explicit creation: drive/cut/roll, pull-up/self-created, putback, and
  `other_or_unknown`.

Purpose: test whether broad creation and finish information improves future
prediction. Do not relabel unknown creation as catch-and-shoot, transition, or
post play without a validated same-attempt source.

### M2: nonlinear distance — complete; not advanced

Adds one league-wide natural cubic distance smooth to M1. D1 supplies the
distance-only diagnostic.

Purpose: test whether exact distance adds information after broad shot type.
Two-dimensional coordinates remain outside M2 because they duplicate the
separate Location Edition question.

The three registered historical comparisons are complete. M2 improved pooled
log loss but failed the material-calibration gate, so the frozen rule retains
M1. These are development results because their outcomes were already viewed
during M0/M1, not prospective confirmation.

### M3: verified pre-shot game context — data audit complete

Candidate fields must be available before release and pass a timing and linkage
audit. Likely candidates include period, time remaining, score before the shot,
home/away status, and other fields supported at the same-attempt grain.

Before M3 fitting:

1. Audit field availability and missingness by season.
2. Prove that each value represents the state before the shot.
3. Define honest missing or unmatched handling.
4. Freeze a small feature set and an M3-versus-retained-M1 decision rule. Do not
   reintroduce the rejected M2 distance term without separate preregistration.
5. Keep post-shot score, result descriptions, later events, rebounds, and final
   game outcomes outside the predictors.

M3 must remain small. Game context should enter because it answers a basketball
question, not because a large feature search finds a better retrospective fit.

### Defense: separate data gate — not implemented

The current ShotChartDetail and ESPN play-by-play sources do not reliably supply
same-attempt closest-defender distance, contest intensity, defender identity,
help position, or whether the shooter was open.

Do not call location, shot type, clock, score, or play descriptions "defense."
A defensive extension requires a validated same-attempt tracking or matchup
source, source rights compatible with the project, a leakage audit, and a frozen
join contract. If those requirements fail, omit direct defense and state the
limitation.

### M4: player Shot Fit — planned

Add partially pooled player-by-family effects only after M2/M3 stabilize.

Purpose: estimate whether a player performs differently from the league pattern
for a specific shot family while protecting low-volume players through
shrinkage.

Required gates:

- Stable player-family support.
- Low-volume simulation and recovery tests.
- Honest unseen-player behavior.
- No fixed unpooled player-family estimates.
- Forward comparison against the preceding selected model.

### M5: True Shot-Trip Value — restricted pilot

Change the target from field-goal points to validated shot-trip value only after
linkage work passes.

The feasibility audit found unambiguous and-one and ordinary shooting-foul
sequences, but special fouls, corrections, and ambiguous sequences remain.
Before M5:

- Expand manual sequence review.
- Reconcile field goals and free throws to independent box-score totals.
- Handle replay and `No Shot` corrections.
- Include only deterministic approved link classes.
- Keep technical, take, clear-path, away-from-play, and ambiguous trips excluded
  unless a later frozen rule validates them.

`pbpstats` may be used only as an approved isolated parser benchmark. It is not
automatic ground truth.

### M6: volume and capacity — historical limits first

The current five seasons cannot identify reliable player-specific
volume-efficiency curves apart from role, health, team, development, and shot
quality.

Version one should use conservative historical capacity limits. Do not publish
player-specific volume-efficiency curves unless new player-game or player-month
data, minutes, usage, role, health proxies, and opportunity quality support
forward-validated identification.

### Prospective confirmation: 2026-27 — sealed

The project reserves 2026-27 for one prospective confirmation after the final
candidate formula, target, eligibility, metrics, calibration gate, and decision
rule are frozen.

Do not access, prepare, inspect, or summarize 2026-27 data before that freeze.
Historical development success does not substitute for prospective
confirmation.

## Outcome-access state

| Season | Current permitted role |
|---|---|
| 2021-22 | Training and development |
| 2022-23 | Training and development |
| 2023-24 | Historical rolling-origin development; outcomes already viewed |
| 2024-25 | Historical rolling-origin development; outcomes already viewed |
| 2025-26 | Historical rolling-origin development; outcomes already viewed |
| 2026-27 | Sealed prospective confirmation |

Each stage must still use expanding-window fits and whole-game validation. Never
replace split-specific historical predictions with predictions from a later
refit.

## Stable project rules

- Protect the completed Location Edition and its public website.
- Use expected field-goal points for M0 through M4:
  `predicted make probability * known point value`.
- Preserve raw labels and version every taxonomy mapping.
- Keep `other_or_unknown` as an honest category.
- Use only information known before the attempt as predictors.
- Keep games whole in training, validation, and bootstrap resampling.
- Prefer the simpler model unless the registered one-standard-error,
  calibration, and season-breadth gates pass.
- Preregister every new stage before fitting it.
- Commit and push execution code before opening an authorized outcome.
- Publish only compact aggregate results. Keep shot rows, predictions, fits,
  covariance matrices, IDs, logs, and bootstrap draws ignored.
- Treat historical results as predictive and descriptive, not causal.
- Do not claim that a player can consciously relocate or substitute attempts
  without changes in defense, role, teammates, play design, or game state.
- Add no dependency without Narayan's approval.
- Recover verified artifacts before recomputing expensive work.

## Foreseeable execution order

1. Preserve the completed three-window M2 evaluation and retained-M1 decision.
2. Keep 2026-27 sealed; historical selection does not authorize confirmation.
3. Preserve the completed Location sensitivity, relocation-flow, and two-player
   comparison work.
4. Preserve the completed M3 predictor-data audit and its aggregate outputs.
5. Preregister the smallest M3 formula and its M3-versus-M1 historical decision
   rule before fitting either model.
6. Decide whether a valid direct-defense data source exists. Omit defense if it
   does not pass the source and join gates.
7. Preregister and evaluate M4 player Shot Fit.
8. Complete the restricted M5 shot-trip linkage and reconciliation audit.
9. Add M6 historical capacity limits; retain the no-go on player-specific curves
   unless new identification evidence changes it.
10. Freeze the final candidate and run 2026-27 prospective confirmation once.
11. Only after model selection and confirmation, design public exports and a
    separate portfolio integration.

Do not skip ahead because a later stage sounds more actionable. Each selected
model becomes the immutable baseline for the next registered comparison.

## Handoff requirements

Every Context Edition handoff must state:

- Branch, commits, push state, and tracked-tree status.
- Exact stage and whether it completed.
- Source, configuration, and artifact hashes.
- Training and evaluation seasons.
- Outcome-access flags, especially 2026-27.
- Fit counts, checkpoint reuse, and duplicate-run status.
- Formulas, feature allowlist, and any rule change.
- Counts, convergence, resource use, and deterministic checks.
- Aggregate results only when the stage authorized them.
- Privacy confirmation and committed artifact inventory.
- Problems, limitations, decisions needed, and the next gated action.
- Confirmation that the Location Edition and portfolio were untouched unless a
  separate request explicitly authorized them.

Future prompts should say: "Read `AGENTS.md` and
`docs/CONTEXT_EDITION_ROADMAP.md` before acting, then read the active stage's
preregistration and latest handoff."
