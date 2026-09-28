# NBA Shot Selection Project Architecture

**Status:** Living project-boundary document
**Last updated:** 2026-09-28

## Purpose

This repository supports two related but analytically independent NBA
shot-selection projects:

1. **Location Edition** asks how a player's historical scoring could change if
   some attempts moved from weaker court locations to stronger supported
   locations.
2. **Context Edition** asks whether information available before a shot—such as
   finish type, creation type, distance, game context, workload, and later
   defensible contextual factors—improves expected-value prediction.

They may share source handling, privacy rules, identifiers, validation
utilities, and reproducibility infrastructure. They must not share or blur
models, scores, results, exports, conclusions, limitations, or public claims.

This document defines that boundary and the expected order of work. It does not
authorize model execution, outcome access, data publication, dependency
changes, merges, or deployment.

## Repository decision

Keep both projects in this repository for now. Do not create a new repository,
copy the codebase, or reorganize existing files merely to express the split.

For new work, prefer clear `location` and `context` names where practical. Do
not move or rename established files without separate approval. Reconsider
separate repositories only if the projects develop materially different
dependencies, release schedules, access policies, maintainers, or standalone
products.

## Location Edition

### Question

How could a player's expected scoring change if a limited share of historical
attempts moved from weaker court locations to stronger locations supported by
that player's own history?

### Current status

The Location Edition is the completed, deployed five-season project. Its CAR
model, location cells, relocation rules, universal destination cap, score,
uncertainty calculations, exports, public explorer, definitions, and
limitations are protected existing work.

The model is descriptive and counterfactual, not causal or prescriptive. It
does not claim that a player can freely choose locations or reproduce
historical efficiency after volume moves. It does not fully observe defense,
game situation, shot creation, teammate and coaching constraints, fatigue,
injuries, or strategic responses.

### Approved future expansion themes

These are separate Location Edition improvements. They do not change the
Context Edition model and require their own preregistration or implementation
approval.

1. **Sensitivity analysis**
   - Minimum destination attempts: 5, 10, and 20.
   - Posterior evidence threshold: 80%, 90%, and 95%.
   - Destination cap: 30%, 50%, and 70%.
   - Report how conclusions change across the full registered grid.
   - Never choose the setting that produces the most favorable gain.
2. **Relocation flow visualization**
   - Show aggregate movement from original areas to receiving areas.
   - Preserve the existing before-and-after court view.
   - Do not publish identifying shot-level movement records beyond the
     repository's narrow public shot-chart policy.
3. **Two-player comparison**
   - Compare current and relocated expected points per 100 attempts, potential
     improvement, the Location Edition score, uncertainty, and location maps.
   - State prominently that the score is self-relative and is not an overall
     player ranking or talent grade.
4. **Location-oriented archetypes**
   - Consider only after the sensitivity, flow, and comparison work is stable.
   - Keep archetype claims tied to observed location profiles rather than
     treating them as causal player identities.

### Public presentation

The existing public NBA Shot Selection Analytics page remains the Location
Edition. Its current results should remain available while later features are
developed and reviewed.

## Context Edition

### Question

Before a shot is taken, how much predictive information do shot type, creation
type, distance, verified game context, workload, and other defensible pre-shot
factors add to expected field-goal value?

This is not a rewrite of the Location Edition. It is a separate research
project with its own formulas, validation, model selection, results, exports,
definitions, limitations, and eventual portfolio page.

### Frozen model ladder

- **M0 — Player baseline:** point value plus a partially pooled player
  intercept.
- **M1 — Shot taxonomy:** M0 plus finish family and creation family. M1 is the
  selected current baseline.
- **M2 — Nonlinear distance:** M1 plus the preregistered nonlinear distance
  smooth. M2 is the active evaluation stage.
- **M3 — Audited pre-shot context:** add only context fields shown to be
  available before the attempt and reliable enough for future-season use.
- **M4 — Player shot fit:** consider partially pooled player-by-family effects
  only after simpler fixed taxonomy and context effects are stable.
- **M5 — Restricted shot-trip value:** incorporate verified and-one and
  ordinary shooting-foul trip value only after the linkage and reconciliation
  gates pass.
- **M6 — Historical volume and capacity:** add conservative workload or
  capacity constraints without claiming causal volume-efficiency curves from
  five seasons of observational data.

Direct defense belongs behind a separate data-quality gate. Distance, score,
clock, and other proxies must not be labeled as defense. Do not add defender
distance, matchup, tracking, injury, role, or opportunity variables until the
same-attempt source, timing, coverage, missingness, and leakage risks are
audited.

Do not reuse the Location Edition score as the Context Edition's primary metric
unless a later preregistration gives it a defensible new meaning.

### Current evaluation state

- `development_1` compared frozen M2 with M1 on 2023–24 and is committed at
  `c57ced37e97e9f06fbb18232b743fea68c8034d6`.
- M2 improved 2023–24 pooled log loss, but calibration worsened on the
  registered ECE check.
- That result is one historical-development window, not a final model decision.
- The frozen M2 process still requires the remaining registered development
  windows and all decision gates before M2 can replace M1.
- `development_2` is complete at `63febf4`; it also favors M2 on log loss,
  but cannot determine the pooled historical choice.
- Registered training-volume quartile diagnostics for both earlier windows
  now have separately labeled supplements. The original results are unchanged.
- `development_3` training is verified: M1 was reused and M2 was fitted once.
  The 2025-26 predictor-only support check passed, but the execution approval
  system blocked evaluation before outcome access and requires direct chat
  authorization. Recover the saved fits, frozen configuration, authorization,
  and inactive lock state; do not repeat training.
- The next operational action is the frozen third-window evaluation followed
  by the registered pooled decision, once the execution block is resolved.
  M1 remains the selected baseline. No final M2 decision exists.
- Do not treat this architecture document as outcome-access authorization.
- Preserve the 2026–27 prospective season as sealed confirmation data.

For exact formulas, access flags, hashes, evaluation rules, and current
execution state, read `docs/CONTEXT_EDITION_ROADMAP.md` and the stage-specific
preregistration and runner documentation.

## Overfitting and model-selection policy

The project controls overfitting; it does not claim overfitting is impossible.

Required safeguards include:

- rolling future-season validation rather than random shot splits;
- partial pooling for player effects;
- limited, preregistered model complexity;
- whole-game resampling for uncertainty;
- calibration checks alongside predictive accuracy;
- the registered one-standard-error and breadth rules;
- adding one justified predictor family at a time; and
- preserving 2026–27 for prospective confirmation.

Sensitivity analysis is a robustness exercise. It must not be used to tune
assumptions toward larger gains or a preferred story.

## Missing data and imputation policy

### Current M0–M2 position

Do not add mean imputation or predictive mean matching to M0–M2. The current
predictors are modeled under their frozen data contract.

`other_or_unknown` is an honest creation category for labels that do not
provide enough evidence. It is not a numeric missing value and must not be
silently imputed into a more specific basketball action.

### Required audit before M3

Before fitting M3, distinguish:

- true missing values;
- failed joins;
- structurally unavailable fields;
- context that cannot be verified as pre-shot; and
- honest unknown categories.

Only then compare, where statistically appropriate:

1. complete-case analysis;
2. training-set mean or median imputation plus a missingness indicator; and
3. multiple imputation using predictive mean matching for suitable numeric
   predictors.

Fit every imputation procedure inside each training window. Never use
validation outcomes or future-season information to impute training or
validation predictors. Do not impute unavailable defense, injury, role, or
opportunity data as though it had been observed.

Use predictive mean matching only if its future-season predictive or
calibration benefit justifies the added complexity. Otherwise retain the
simpler defensible treatment.

## Shared infrastructure and strict boundaries

The projects may share:

- source acquisition and hash verification;
- season, game, event, team, and player conventions;
- privacy and public-export rules;
- deterministic build and manifest utilities;
- generic calibration, validation, and audit helpers; and
- documentation and reproducibility standards.

The projects must keep separate:

- research questions and estimands;
- model formulas and selection decisions;
- scores and interpretation;
- results and uncertainty;
- production exports and public assets;
- limitations and claims; and
- portfolio pages and presentation narratives.

A shared repository is not permission to combine conclusions or let one
project's result silently change the other.

## Website architecture

1. Keep the current Location Edition page live and identifiable as the
   location-based project.
2. Create a separate Context Edition page only after its model and results pass
   the registered evaluation process and receive presentation approval.
3. Give the Context Edition its own question, explanation, visuals,
   definitions, methodology, formulas, limitations, and result language.
4. An umbrella shot-selection page may later link both projects, but it should
   explain that they answer different questions.
5. Do not replace the Location Edition page with unfinished Context Edition
   work.

## Foreseeable work order

Unless a later approved preregistration changes the sequence:

1. Preserve the completed Context `development_1` and `development_2` results
   and their separately labeled training-volume supplements.
2. Resolve the `development_3` execution-approval block and complete its frozen
   evaluation using both saved fits, without refitting.
3. Apply all frozen gates and make the historical M2-versus-M1 decision.
4. Preregister and run the Location Edition sensitivity audit.
5. Add the Location Edition aggregate relocation-flow view.
6. Add the Location Edition two-player comparison.
7. Audit Context M3 data availability, missingness, joins, timing, and leakage
   before choosing any imputation approach.
8. Revisit archetypes after the relevant location and context predictors are
   stable.

## Working rule for future Codex tasks

At the start of any NBA shot-selection task:

1. Read this document.
2. Identify whether the task belongs to Location Edition, Context Edition,
   shared infrastructure, or the future umbrella presentation.
3. Read the authoritative project-specific plan and the latest handoff.
4. State which project is in scope and which project is protected.
5. Do not infer that approval for one project authorizes changes to the other.
6. Preserve outcome seals, privacy restrictions, frozen specifications, and
   the current deployed Location Edition unless the user explicitly changes
   them.
