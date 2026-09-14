# NBA Shot Selection: Context Edition — Feasibility and Methodology Audit

Status: provisional methodology only

Audit date: 2026-09-14

Audit branch: `codex/context-edition-feasibility-audit`

## Boundary with the completed project

The completed five-season Bayesian CAR work remains the **Location Edition**. Its models, results, relocation rules, score, and website bundle are historical facts, not inputs to be revised here. This audit does not refit them, change their interpretation, or create a Context Edition production export.

The Context Edition asks a different question. Location is still useful, but it is no longer the entire definition of a shot.

## Recommended basketball question

> For each player, which broad, publicly observable shot families have delivered the most stable scoring value after accounting for point value, distance, location, and verified pre-release game context—and which parts of the player’s current profile have produced less value when that player has historically generated credible alternatives at similar volume?

This wording is deliberately descriptive. It does not claim that a player can exchange one attempt for another at will, or that changing volume would cause efficiency to remain fixed.

## Bottom line

The project is feasible in a narrower form than the original ambition.

- A finish-family model is feasible from the existing shot data.
- A complete two-axis creation/finish taxonomy is **not** feasible from `ShotChartDetail` alone. Half of the shots lack an explicit creation cue, and catch-and-shoot, transition, and post creation cannot be recovered honestly from separate season summaries.
- Opportunity Quality, Shot Making, and Shot Fit are conditional go decisions if the first version uses only verified shot-level fields and keeps “unknown creation” as a real category.
- True Shot-Trip Value is suitable for a restricted pilot, not full inclusion. The automated rule linked 78.24% of all candidate first-free-throw sequences unambiguously, or 86.16% after explicit special-foul exclusions.
- Player-specific Volume-Efficiency Curves are a no-go for version one. Five seasons contain volume movement, but not enough clean, within-player identification to separate volume from role, team, health, development, and opportunity difficulty. Historical-capacity limits are more honest.
- Shot type should supplement location now. It should not replace location until creation context is reliable at the same-attempt grain.

## What was audited

The reproducible audit code is [`R/context_edition_audit.R`](../R/context_edition_audit.R). It reads five local `ShotChartDetail` extracts and five cached public play-by-play releases, then writes aggregate-only files under [`data/processed/context_edition_audit`](../data/processed/context_edition_audit). It does not fit a model or save shot-level rows.

The detailed deliverables are:

- [`source_field_inventory.csv`](../data/processed/context_edition_audit/source_field_inventory.csv)
- [`canonical_shot_trip_schema.csv`](../data/processed/context_edition_audit/canonical_shot_trip_schema.csv)
- [`audit_sanity_checks.csv`](../data/processed/context_edition_audit/audit_sanity_checks.csv)
- [`shotchart_coverage.csv`](../data/processed/context_edition_audit/shotchart_coverage.csv)
- [`shotchart_field_missingness.csv`](../data/processed/context_edition_audit/shotchart_field_missingness.csv)
- [`raw_action_labels.csv`](../data/processed/context_edition_audit/raw_action_labels.csv)
- [`raw_label_drift.csv`](../data/processed/context_edition_audit/raw_label_drift.csv)
- [`taxonomy_coverage.csv`](../data/processed/context_edition_audit/taxonomy_coverage.csv)
- [`finish_family_support.csv`](../data/processed/context_edition_audit/finish_family_support.csv)
- [`taxonomy_family_support.csv`](../data/processed/context_edition_audit/taxonomy_family_support.csv)
- [`manual_taxonomy_review.csv`](../data/processed/context_edition_audit/manual_taxonomy_review.csv)
- [`pbp_source_coverage.csv`](../data/processed/context_edition_audit/pbp_source_coverage.csv)
- [`shotchart_pbp_reconciliation.csv`](../data/processed/context_edition_audit/shotchart_pbp_reconciliation.csv)
- [`shot_trip_linkage.csv`](../data/processed/context_edition_audit/shot_trip_linkage.csv)
- [`manual_shot_trip_review.csv`](../data/processed/context_edition_audit/manual_shot_trip_review.csv)
- [`volume_variation.csv`](../data/processed/context_edition_audit/volume_variation.csv)
- [`volume_context_proxy.csv`](../data/processed/context_edition_audit/volume_context_proxy.csv)
- [`leakage_register.csv`](../data/processed/context_edition_audit/leakage_register.csv)
- [`model_ladder.csv`](../data/processed/context_edition_audit/model_ladder.csv)
- [`output_go_no_go.csv`](../data/processed/context_edition_audit/output_go_no_go.csv)
- [`computation_storage_estimate.csv`](../data/processed/context_edition_audit/computation_storage_estimate.csv)

## Source findings

### Existing local shot chart

The local source has one row per recorded field-goal attempt and the 24 documented `ShotChartDetail` fields. Across all five seasons, every source field is populated. Game ID plus event ID is unique.

The source contains reliable attempt identity, shooter, team, period, clock, point value, coordinates, distance, raw action label, and result. Opponent and home/road can be derived from the home and visitor teams. The endpoint schema is documented by [`nba_api`](https://github.com/swar/nba_api/blob/master/docs/nba_api/stats/endpoints/shotchartdetail.md), which is an access wrapper rather than an independent data source.

It does not contain score before the attempt, shot clock, closest defender, lineup, transition, second chance, or a complete creation label.

### Event play-by-play

[`PlayByPlayV3`](https://github.com/swar/nba_api/blob/master/docs/nba_api/stats/endpoints/playbyplayv3.md) exposes event order, period, clock, team, player, score, description, action/subtype, result, and coordinates. Score fields describe the event state and must be lagged to create score **before** the attempt.

Direct official NBA requests did not succeed in this environment: the Stats request timed out and the live CDN returned 403. For feasibility only, the audit used installed `hoopR` 3.0.0 and its public SportsDataverse ESPN play-by-play releases. The [`hoopR` loader source](https://github.com/sportsdataverse/hoopR/blob/main/R/load_nba.R) confirms that these are season release files. This archive is a second provider, not official ground truth.

The five cached releases occupy 111 MB compressed. Their hashes are recorded in `pbp_source_coverage.csv`; the raw files remain ignored.

### Tracking and Synergy summaries

NBA tracking dashboards publish catch-and-shoot, pull-up, dribble, touch-time, shot-clock, and closest-defender summaries. The NBA’s [statistics glossary](https://www.nba.com/stats/help/glossary) defines these as tracking/shooting measures. [`PlayerDashPtShots`](https://github.com/swar/nba_api/blob/master/docs/nba_api/stats/endpoints/playerdashptshots.md) exposes player-season bins, not joint shot rows.

The [`SynergyPlayTypes`](https://github.com/swar/nba_api/blob/master/docs/nba_api/stats/endpoints/synergyplaytypes.md) endpoint likewise exposes player/team-season play-type aggregates such as possessions, points, FGA, and shooting-foul frequency. Those tables are useful for descriptive checks. They cannot reveal whether a particular catch-and-shoot attempt was also open, late-clock, or guarded at a given distance.

The audit therefore prohibits converting marginal summaries into synthetic joint observations.

### `pbpstats`

`pbpstats` is a parser, not a source. Its [enhanced play-by-play documentation](https://pbpstats.readthedocs.io/_/downloads/en/latest/pdf/) includes explicit flags for shooting, technical, take, clear-path, and away-from-play fouls; free-throw sequence position; possession endings; placeholder rebounds; and replay rulings. It is not installed and was not added. It is a reasonable later benchmark for the project’s own linkage rules, subject to Narayan’s approval.

## Five-season coverage and reconciliation

| Season | Shot-chart games | Shot rows | Players | Raw labels | Missing/duplicate event keys |
|---|---:|---:|---:|---:|---:|
| 2021–22 | 1,230 | 216,722 | 596 | 46 | 0 / 0 |
| 2022–23 | 1,230 | 217,220 | 537 | 48 | 0 / 0 |
| 2023–24 | 1,230 | 218,700 | 568 | 48 | 0 / 0 |
| 2024–25 | 1,230 | 219,527 | 566 | 48 | 0 / 0 |
| 2025–26 | 1,230 | 219,160 | 582 | 48 | 0 / 0 |

Measured total: 1,091,329 shots, 6,150 games, and 2,849 player-seasons. These are coverage counts, not a new eligibility rule.

The date/home/away crosswalk matched all games through 2024–25 and 1,229 of 1,230 games in 2025–26. Exact player-plus-clock matching linked 973,769 attempts, or 89.24% of crosswalked shot-chart attempts. Among those unique matches:

- result agreement was 100% in every season;
- point value agreed on more than 99.99% of rows where the second provider made point value observable;
- provider coordinates, after the audited axis/unit transform, were within one foot on both axes for more than 99.9%;
- named distance agreement improved sharply after 2022–23, evidence of provider-description drift.

The audit found 1,099 ESPN `Heave Jump Shot` events in 2025–26 and none in earlier releases. Those events explain almost all of that season’s field-goal count excess over `ShotChartDetail`. This is a concrete label/coverage change that a versioned source rule must address.

Box-score reconciliation remains unfinished because no independent five-season box-score archive was acquired in this task. The strong event-level result and geometry agreement supports feasibility, but does not replace box-score checks.

## Canonical shot and shot-trip schema

The proposed schema is audit-only. One canonical row would represent either one field-goal attempt or one validated shot trip. Raw source fields remain intact; derived fields live beside them.

The full schema is in `canonical_shot_trip_schema.csv`. Its core rules are:

1. Keep immutable provider game/event IDs, event order, source hash, acquisition time, mapping version, and linkage status.
2. Preserve raw action type, subtype, description, and qualifiers.
3. Store creation and finish as separate versioned fields. Unknown is a valid result.
4. Store score before the attempt, never the post-event score.
5. Store field-goal result and attributable free throws as target components, not predictors.
6. Never populate shot clock, defense, transition, second chance, or lineup from an aggregate table.
7. Retain ambiguous and excluded trip statuses rather than forcing a link.

## Taxonomy audit

### Finish family: workable, still provisional

All 48 local action labels can be mapped without an “unknown finish” into seven compact families: dunk, layup, floater, hook, regular jumper, fadeaway/turnaround, and step-back. Every family has meaningful support, although hooks, dunks, fadeaways, and step-backs have many low-volume player-seasons. Representative raw labels from every proposed finish and creation family were inspected and recorded in `manual_taxonomy_review.csv`.

Only two labels changed presence: `Turnaround Bank shot` and `Fadeaway Bank shot` first appear in 2022–23. All other local labels appear in all five seasons. The mapping must still be reviewed against representative video or provider definitions before it becomes final.

### Creation family: incomplete

The conservative mapping recognizes only explicit wording:

- driving, cutting, and alley-oop → drive/cut/roll;
- pull-up and step-back → pull-up/self-created;
- tip and putback → putback;
- everything else → other/unknown.

This leaves 549,729 shots, or 50.37%, as other/unknown. `Running` does not prove transition. A hook or turnaround does not prove a post-up. A generic jumper does not prove spot-up. These are basketball distinctions, not string-cleaning problems.

Conclusion: the finish axis works as version 0.1. The creation axis works only as a partial, high-precision taxonomy. It cannot support the originally named spot-up, transition, or post categories without a same-attempt source.

## True Shot-Trip audit

The automated audit examined 156,070 first-free-throw sequence candidates across five seasons. Its conservative same-game, same-period, same-clock rules found:

- 29,334 unambiguous and-ones;
- 92,782 unambiguous ordinary two- or three-shot shooting-foul trips;
- 14,335 explicitly excluded technical, flagrant, clear-path, take, away-from-play, or otherwise special-foul sequences;
- 19,619 ambiguous or unrelated sequences.

Unambiguous linkage was 78.24% of every candidate and 86.16% after explicit exclusions. The season rate after exclusions ranged from 84.96% to 87.07%.

The manual sequence review covered ordinary makes and misses, two-shot fouls, and-ones, three-shot fouls, technicals, clear paths, take fouls, interleaved team rebounds/substitutions, a period-ending shot, and a `No Shot` correction. It exposed three rules that a production linker needs:

- substitutions and placeholder team rebounds cannot break a free-throw sequence;
- special and nonshooting fouls must remain excluded even when they share a clock with ordinary free throws;
- replay and `No Shot` records require final-feed adjudication before target construction.

Recommendation: **restricted inclusion with explicit rules**, but only at M5. M0–M4 should use expected field-goal points. Before M5, expand the hand audit, reconcile to box scores, confirm event corrections, and require every included trip to satisfy one deterministic rule. Full inclusion is rejected.

## Volume-Efficiency feasibility

The data do contain volume movement. Across finish families there are 1,229 to 1,749 adjacent-season player-family pairs. Median absolute year-to-year attempt changes range from 4 for hooks to 57.5 for regular jumpers; median relative changes are about 41% to 50%.

That variation does not identify an efficiency curve. Each player-family has at most five seasonal observations. Many player-seasons involve multiple teams. Local data do not jointly provide minutes, usage, injury, role, defender quality, or a complete opportunity-quality estimate. Simple volume correlations with mean distance are weak (absolute Spearman correlations no larger than 0.134), but distance is not contextual difficulty and those correlations do not solve confounding.

Recommendation: use conservative historical-capacity rules in version one, such as staying within a predeclared range of the player’s observed family volume. Do not fit or publish player-specific volume-efficiency curves. Reconsider broad population curves only after player-game or player-month volume, minutes, usage, team/role, and opportunity-quality data are assembled and forward validation shows incremental value.

## Leakage controls

The full register is `leakage_register.csv`. The non-negotiable controls are:

- no result, assist, post-shot score, final game state, or later event in Opportunity Quality predictors;
- no test-period player effect in training;
- no game split across training and evaluation;
- no synthetic shot rows created from separate aggregate dashboards;
- no taxonomy or model changes after the final evaluation is inspected;
- no special free throw assigned to an ordinary shot trip;
- no eligibility rule based on future outcomes.

## Validation design

The five seasons are not untouched. They were used in the Location Edition, and this audit has now inspected their coverage and label behavior. The Context Edition must not call any of them a pristine final test.

Recommended design:

1. Freeze source rules, taxonomy version, target, features, metrics, and model ladder first.
2. Keep whole games intact in every split.
3. Use rolling-origin evaluation: train through 2022–23 and test 2023–24; train through 2023–24 and test 2024–25; train through 2024–25 and test 2025–26.
4. Treat 2025–26 as the last retrospective forward test, not an untouched final test.
5. Reserve 2026–27 as the first prospective confirmation after all choices are frozen.
6. Report new-player performance separately; do not silently drop players without training history.

Primary selection metric: future-game log loss. Also report Brier score, calibration, discrimination, player-family stability, season stability, uncertainty quality, runtime, interpretability, and low-volume behavior. Choose the simplest model within one standard error of the best log loss if calibration is not materially worse.

## Future model ladder

No model was fit in this audit.

- **M0:** empirical-Bayes averages by point value and broad finish family.
- **M1:** creation family, finish family, and point value using penalized logistic or a simple hierarchical binomial model.
- **M2:** add a predeclared nonlinear distance effect and only necessary location context; a GAMM is the natural simple candidate.
- **M3:** add the small set of reliable shot-level pre-shot fields that survives the data audit.
- **M4:** add partially pooled player and player-by-family effects for Shot Fit.
- **M5:** switch to the restricted shot-trip target only after linkage validation.
- **M6:** add historical-capacity rules. Curves remain off unless new identification evidence changes the no-go decision.

Hierarchical Bayesian models are strongest for uncertainty and low volume at M4. GAMMs are attractive for M2–M4 because they keep nonlinear distance interpretable. Penalized logistic regression is the simplest M1 benchmark. Gradient boosting should be a predictive benchmark only. BART is optional and should be attempted only if simpler models miss stable, held-out nonlinear structure.

Interactions need a basketball reason. The only initial candidates are family × distance, family × shot clock if shot clock becomes genuinely available, player × family, and—only after identification—volume × family.

## Computation and storage

Measured compressed audit inputs are 11 MB of shot Parquet plus 111 MB of play-by-play RDS. Aggregate tracked outputs are about 150 KB. A warmed audit pass took about one minute; peak memory was not measured.

Planning estimates are deliberately broad:

- canonical field-goal data: roughly 0.1–0.5 GB compressed;
- M0–M2: minutes to a few hours and roughly 2–8 GB peak memory;
- M3–M4 hierarchical work: hours to a day and roughly 8–32 GB peak memory;
- M5: similar or moderately larger once restricted trips are added.

Posterior draws and shot-level predictions should remain ignored. Git should contain schemas, manifests, aggregate diagnostics, and reproducible code only.

## Go/no-go decisions

| Output | Decision | Meaning |
|---|---|---|
| Opportunity Quality | Conditional go | Use verified shot-level pre-release fields only; omit unavailable defense and shot clock. |
| Shot Making | Conditional go | Add partial pooling only after Opportunity Quality passes forward validation. |
| Shot Fit | Conditional go | Present historical, evidence-weighted fit; do not imply free substitution. |
| True Shot-Trip Value | Restricted pilot only | Include deterministic ordinary shooting-foul links at M5; exclude special and ambiguous cases. |
| Volume-Efficiency Curves | No-go for v1 | Use historical-capacity limits; do not publish player-specific curves. |

## Decisions needed from Narayan

1. **First-version target.** Options: expected field-goal points now, or delay all modeling until shot-trip linkage is production-ready. Tradeoff: field-goal points omit foul value, while waiting blocks the defensible parts of the project. **Recommendation: use field-goal points for M0–M4 and keep shot trips for M5.**
2. **Creation taxonomy scope.** Options: retain a large honest unknown group, or delay until a richer same-attempt source is acquired. Tradeoff: the first option is narrower but valid; the second may improve basketball meaning but adds uncertain acquisition and linkage work. **Recommendation: keep only explicit creation cues and never backfill from marginal tracking summaries.**
3. **Prospective confirmation.** Options: treat 2025–26 as the last retrospective forward test, or call it a final test. The second description would be misleading because those outcomes and labels have already been examined. **Recommendation: reserve 2026–27 for prospective confirmation.**
4. **Shot-trip tool benchmark.** Options: implement the deterministic linker with existing tools only, or later approve installation of `pbpstats` as an independent parser benchmark. Tradeoff: the benchmark adds a dependency but exposes mature edge-case rules. **Recommendation: approve it only for a later isolated linkage audit, not as unquestioned truth.**

## Exact next step

After Narayan settles the four decisions, build an isolated, field-goal-only canonical dataset for the first two historical seasons. Preserve raw labels, implement the conservative finish and partial-creation mapping, derive only pre-shot score from audited event order, and hand-check a stratified sample of game/event joins. Freeze that data contract before fitting M0 or M1.
