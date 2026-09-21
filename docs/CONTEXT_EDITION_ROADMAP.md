# NBA Shot Selection: Context Edition roadmap

Status: living project context for Codex

Last updated: 2026-09-21

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

### Active stage: M2 distance preflight

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
- D1 was fitted once on 2021-22 and 2022-23 and preserved privately.
- D1 passed the registered `k = 10` adequacy rule and corrected frozen checks.
- M2 training-only fitting and atomic two-model checkpoint verification remain
  unfinished at the time of this update.
- No validation outcome was opened during the M2 preflight.

Update this subsection after the next verified M2 handoff. Do not infer success
from a stale lock or partial fit.

## Model ladder and stage gates

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

### M2: nonlinear distance — active

Adds one league-wide natural cubic distance smooth to M1. D1 supplies the
distance-only diagnostic.

Purpose: test whether exact distance adds information after broad shot type.
Two-dimensional coordinates remain outside M2 because they duplicate the
separate Location Edition question.

Gate: complete the training-only preflight, freeze execution, and compare M2
with M1 over the three registered historical rolling-origin splits. These are
development results because their outcomes were already viewed during M0/M1.

### M3: verified pre-shot game context — planned

Candidate fields must be available before release and pass a timing and linkage
audit. Likely candidates include period, time remaining, score before the shot,
home/away status, and other fields supported at the same-attempt grain.

Before M3 fitting:

1. Audit field availability and missingness by season.
2. Prove that each value represents the state before the shot.
3. Define honest missing or unmatched handling.
4. Freeze a small feature set and M3-versus-M2 decision rule.
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

1. Finish and verify the M2 first-window training preflight.
2. Freeze the historical M2 runner before outcome evaluation.
3. Run the three M2-versus-M1 historical development comparisons unchanged.
4. Apply the frozen M2 advancement rule.
5. Preregister and audit M3 game-context fields.
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
