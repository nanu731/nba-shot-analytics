# Context Edition M3 predictor-data audit preregistration

Status: frozen outcome-free audit design

Protocol: `context_m3_data_audit_v0.1.0`

Canonical schema: `context_field_goal_v0.1.2`

## Question

Which small set of verified pre-shot game-context fields is complete and stable
enough to justify a later M3-versus-M1 preregistration?

This audit does not fit M3, rank candidate formulas, inspect shooting outcomes,
or authorize validation. M1 remains the selected baseline. M2 distance remains
excluded.

## Protected scope

- Read only 2021-22 through 2025-26 predictor and join-quality columns from the
  verified canonical Parquet file.
- Keep 2026-27 sealed.
- Do not read `field_goal_made`, realized points, raw descriptions, later events,
  rebounds, final scores, model fits, or prediction files.
- Do not change Location Edition models, exports, scores, or portfolio files.
- Commit only aggregate or declarative tables. Never commit IDs or shot rows.

## Candidate fields

The audit covers period, period clock, shooter home/away status, and verified
shooter-relative score margin. The frozen field register is
`config/context_edition_m3_candidate_fields_v0_1.csv`.

Shot clock and direct defense remain blocked because no verified same-attempt
source exists. Raw play-by-play descriptions remain blocked because they contain
result and post-shot information.

## Registered checks

1. Verify the canonical file against its completion manifest before reading it.
2. Select only the frozen predictor and quality columns.
3. Require exactly five historical seasons and reject 2026-27.
4. Audit missingness by season and linkage status.
5. Audit period and game-clock support without choosing bins from outcomes.
6. Audit verified score-margin support and robust predictor-only quantiles.
7. Prove that every exposed score margin has a verified pre-shot score and that
   unverified rows expose no score margin.
8. Confirm that home/away and score missingness arise from linkage availability,
   not from numeric values eligible for silent imputation.
9. Write the aggregate bundle twice and require byte-identical files.

## Missing-data decision boundary

The audit compares three defensible strategies conceptually:

- complete-case analysis;
- a neutral score-margin fill plus a missingness indicator, with an explicit
  unknown home/away level; and
- predictive mean matching fitted inside each future training window.

No strategy wins from this audit alone. PMM may advance only if the missing
values represent an unobserved numeric measurement and a later preregistered
comparison shows enough future-season benefit to justify the added complexity.
If missingness chiefly reflects failed or unavailable joins, the simplest honest
candidate is the neutral fill plus indicator, with complete cases reported as a
diagnostic. Never present filled values as recovered game states.

## Outputs

The audit may publish only compact CSV files containing source hashes, field
coverage, missingness, support summaries, timing checks, method decisions, and
an output manifest. It must publish no shot, player, game, or event identifier.

## Stop conditions

Stop before publication if a source hash fails, a blocked or outcome column is
loaded, 2026-27 appears, timing checks fail, score values appear without the
verification flag, either deterministic build differs, or any aggregate output
contains a prohibited identifier.

## Next gate

After this audit, freeze the smallest defensible M3 feature set and its missing-
data treatment in a separate model preregistration. Do not fit M3 under this
authorization. Location archetypes remain a separate Location Edition task and
must not use unfinished Context predictors.
