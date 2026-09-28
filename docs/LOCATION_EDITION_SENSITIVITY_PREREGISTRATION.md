# Location Edition sensitivity preregistration

Protocol: `location_sensitivity_v0.1.0`.
Date: 2026-09-28. Status: frozen planning specification; calculation not authorized.
Source revision: `f22d150558273a426c828900f246f5552cc81746`.
Branch: `codex/location-edition-sensitivity-preregistration`.

## Question, scope, and prior knowledge

Are Location Edition conclusions robust to reasonable alternative evidence and
receiving-capacity rules, or do evidence eligibility, achievable relocation,
scores, and estimated gains depend heavily on the baseline assumptions?

This study varies three relocation assumptions after model selection. It cannot
choose a new model, establish predictive accuracy, or tune production defaults.
The baseline remains 10 focal-cell attempts, 90% posterior evidence, and a 50%
final receiving-cell share. Alternatives remain sensitivity conditions even if
they produce larger gains or cover more players. Do not rank settings by gain,
apparent accuracy, or portfolio appeal. Freeze this grid before calculation;
do not revise it after viewing results.

Read together with `FIVE_SEASON_V4_PLAN.md`, `SINGLE_DESTINATION_CAP_V3_PLAN.md`,
`RELOCATION_PLAN.md`, `SPATIAL_WEBSITE_EXPORT.md`, and `SPATIAL_MODEL_PLAN.md`.
The current v3/v4 implementation, not the older proportional v1/two-destination
v2 sections, supplies the baseline. `DESTINATION_SUPPORT_AUDIT.md` already
reported selected 2025-26 alternatives under the older two-destination rule.
Those findings are prior knowledge, not new results or independent confirmation
of this grid. No preliminary result from this registered grid was inspected.

Context historical selection is complete: M2 improved log loss but failed the
pooled calibration gate; M1 remains selected. Preserve Context code, data,
artifacts, configurations, and documentation. No M3 or 2026-27 access is allowed.
Some historical passages in the living spatial/export/score documents predate
the completed releases; they do not supersede v3/v4 or reopen Context work.

## Registered grid and population

The machine-readable table is
`config/location_edition_sensitivity_grid_v0_1.csv`. It contains exactly the
Cartesian product below, sorted by attempts, evidence, then cap:

| Minimum focal attempts | Posterior evidence | Final receiving cap |
|---|---|---|
| 5, 10, 20 | 0.80, 0.90, 0.95 | 0.30, 0.50, 0.70 |

There are 27 conditions, including baseline `A10_E90_C50`. Evaluate all six
requests `0, 0.05, 0.10, 0.15, 0.20, 0.25` within each condition, not 27
independent model fits. Report seasons separately in newest-first order.

| Season | Fixed eligible players | Fixed eligible attempts | Cells/player |
|---|---:|---:|---:|
| 2025-26 | 318 | 194987 | 156 |
| 2024-25 | 304 | 194526 | 156 |
| 2023-24 | 281 | 192608 | 156 |
| 2022-23 | 292 | 192897 | 156 |
| 2021-22 | 312 | 193577 | 156 |

Retain all 1,507 eligible player-seasons, including unavailable estimates. Do
not add model-ineligible players when evidence thresholds loosen. The existing
eligibility set uses at least 20 in-play games and 250 in-play attempts per
season. Court bounds, cleaning, cell IDs, and four-foot grid remain unchanged.
No season pooling in the CAR model or relocation calculation is allowed. Preserve
the source shot-type taxonomy and point-value mapping; import no Context taxonomy
or predictor into Location calculations.

## Exact existing parameter semantics

These definitions were checked against `R/spatial_targeted_relocation_helpers.R`
and `R/spatial_targeted_capped_website_export.R` at the source revision.

For a player-season, `N` is the retained season attempt count, `n[j]` the number
of observed attempts in focal cell `j`, and `f[j] = n[j]/N` its share. Both makes
and misses count once, across that season's complete production sample. No
neighboring-cell counts, pseudo-attempts, posterior effective sample sizes,
other seasons, or Context records enter the minimum-attempt rule.

For an occupied cell, `v[j] = 2 + three_point_attempts[j]/n[j]`. This preserves
the player's observed two/three-point mixture, including boundary cells. Empty
cells have no destination support and contribute zero to the current mix.

For each existing joint posterior draw `b`:

`e[j,b] = v[j] * p[j,b]`; `B[b] = sum(f[j] * e[j,b])`.

In words, compare the cell's expected points with the player's own observed
mix under the same plausible ability surface, not with league-average shooting.
The posterior evidence is the fraction of the 4,000 draws where
`e[j,b] > B[b]` (strictly greater). Support requires `n[j] >= m` AND that
fraction `>= c`. Inclusive thresholds of 0.80/0.90/0.95 correspond to at least
3,200/3,600/3,800 successful comparisons. Do not round probabilities first.

Zero supported cells means `insufficient_evidence`, one means
`single_destination`, two or more means `multiple_destinations`. These statuses
describe evidence; they do not guarantee receiving capacity or a score.

### Source ordering, cap, and allocation

Use **means of the frozen joint draws**, as the current exporter does. Do not
substitute INLA's separate marginal fitted mean for `rowMeans(probability_draws)`.
Sources are occupied cells with `mean(e[j,]) < mean(B)`, ordered by that mean
ascending, then by integer `cell_id`. The order and source capacity are fixed
across all conditions. Posterior support changes with `m,c`, not with the cap or
slider. Verify source and support sets are disjoint for each condition; if not,
stop rather than dropping overlap cells or altering the rule.

With final receiving cap `h`, added capacity is `max(0, h-f[j])` for a supported
cell and zero elsewhere. Let `D` be total added capacity and `W` weak-source
share. Actual moved share is `a = min(requested_share, W, D)`.

The cap limits a cell's **final share of all season attempts**, not its share
of moved attempts. A historical cell already at or above `h` gets no addition;
its historical share remains intact. Do not force the whole distribution below
`h`. Check the cap only for cells receiving more than tolerance. This distinction
matters especially for the 30% condition.

Remove `a` weakest-first, with fractional removal in the final source cell.
For one destination, add at most its positive capacity. For multiple destinations,
start proportional to their original `f[j]`. When a proposed addition reaches
remaining capacity (within `1e-12`), fill that cell, remove it from the active
set, and redistribute remaining mass proportional to the original shares of
uncapped destinations. Preserve the helper's order, comparisons, and tolerance.
Final shares are `q = f - removed + added`. Unmoved mass stays in place.

Attempts remain continuous attempt-equivalents: `N*a` and `N*q[j]` need not be
integers. Never round before gains, intervals, caps, or scores. Existing display
markers use stable source-row order, prefixes of the feasible 25% movement
sequence, and fractional opacity at a boundary. That ordering is protected;
this study needs no new public shot markers or shot-level export. Analytical
destination allocations are recomputed for each request using the same capped
rule; a display prefix is not a substitute for those allocations.

The rule does not inspect which candidate attempt was made or missed to decide
movement. CAR ability does depend on historical outcomes; outcome-independence
here means holding those fitted surfaces fixed and not favoring misses when
choosing source attempts, ordering them, or assigning destinations.

### Availability, gain, and displayed score

Availability requires support count > 0, `W > 1e-12`, and `D > 1e-12`.
Preserve reasons in this priority: `no_supported_destinations`,
`no_positive_supported_capacity`, `no_eligible_weak_source_mass`, `available`.
If unavailable, actual share and moved attempt-equivalents are zero at all
requests; gain, relocated EPPA, and score fields are null, including at 0%.
Do not convert missing evidence to zero gain or a score of 100.

Available players have zero gain at request 0 and their baseline EPPA as relocated
EPPA. For positive requests, retain feasible partial relocation rather than
discarding a player who cannot reach the full request. Evidence status remains
based on supported cells even when all their capacities are exhausted.

For each draw, `R[b] = sum(q[j]*e[j,b])`, gain/100 = `100*(R[b]-B[b])`, and
season gain = `N*(R[b]-B[b])`. Report posterior means and type-7 5th/95th
percentiles. Keep negative interval bounds. Do not add new binomial shot noise.

The displayed score uses the **requested 25% scenario's feasible distribution**:
`score[b] = min(100, max(0, 100*B[b]/R25[b]))`.
Report the median and type-7 5th/95th percentiles of these draw-level scores.
It is one score per player-season-condition, unchanged as the displayed slider
moves. Do not substitute a ratio of means or use actual 25% movement when capacity
allows less. The score is self-relative; it cannot rank overall player quality.

## Model, draw, and source lock

Reuse the five independent season-specific selected CAR fits: binomial makes
and attempts, player intercepts, replicated `besagproper2` surfaces, two shared
hyperparameters, frozen priors/graph/package versions and 156-cell lattice.
No CAR/GAM refit or new model comparison is part of this study.

The production exporter regenerates 4,000 joint predictor draws from the saved
fit's retained posterior configuration; it does not retain a standalone draw
matrix. Preserve RNG kind Mersenne-Twister/Inversion/Rejection, seed `20260902`,
one INLA thread, `parallel.configs=FALSE`, the existing predictor selection and
row mapping, then apply `plogis`. Before any condition, require regenerated draw
means to match saved `draw_mean_probability` within `1e-12`. Generate once per
season, hash and preserve the private matrix and use the exact same columns for
all 27 conditions and paired comparisons. If an identical verified draw cache
already exists, reuse it. Never substitute independent draws per condition.

The existing posterior distribution covers every cell. The three parameters
only change support and allocation, so the same draws suffice for all conditions;
none requires a model refit. This is mathematical/input-contract sufficiency,
not a claim that newly relaxed support cells passed an unrun sensitivity check.
Stop if draw recovery fails or a requested condition would require refitting.
Do not infer joint gain uncertainty from marginal surface intervals alone.

The following SHA-256 anchors identify the existing completion metadata. Each
contains hashes for its input, configuration, model, surface, and uncertainty
artifacts. At execution, hash every referenced artifact before loading it;
require identity with these anchored records, the raw hashes in the v4 plan,
and published baseline inventories. Record the resolved hashes privately and
only aggregate/hash provenance publicly.

| Season | Production completion SHA-256 |
|---|---|
| 2025-26 | `c2d6c92b36981feaf5870a58fb7eca84eff399ddd7ed1c7ed39d649c932f923c` |
| 2024-25 | `4fb0bfa85e9fcbedbd5fe90e234669299004f58e0e3b639a115b7a14dedc1693` |
| 2023-24 | `155c00905d97ea78d0a184c7381e629c6e66b5f891f8891136ce60a3a94a77d2` |
| 2022-23 | `7cae9c1ddc496fd996cfe4070212892a4721dee852f50ab5fde730eec303d8b2` |
| 2021-22 | `ff36d971000e239e60c57ece21abec4b5569dc08fb73849688d3cb50e404dec5` |

Metadata inspection confirmed all five complete flags, passing saved checks,
player/shot counts, 4,000 draws and seed. No fit, posterior matrix, or shot table
was loaded for this preregistration. Full payload verification is a future
execution prerequisite, not a completed analytical check in this task.

Frozen implementation SHA-256:

- relocation helpers: `bc23d4738fa19c15c0571754698ef2456c175f1e8d74ccab1d9030f1a6198aa7`;
- capped exporter: `bc4b761d0dad35ebc5584a2b773020591c17caa93d569ea8db61f26042f1c113`;
- multiseason exporter: `99edeb6622b18f57fecd83143cb44c4fed4fe67b23a7b05ece90676a96c7e211`.

Baseline v4 manifest SHA-256:
`685aa02b5003cb292fbe0926b242a351200f0cd785a169c31942f8518ac03242`.
The v3 manifest remains
`521a4fe25638464bfe7625552ad95535f25dc395c7337df7fb56848e6428ce58`.
Keep v1-v4 files unchanged. Future baseline reconstruction must match published
v4 evidence, availability, scores, gains, intervals, and allocations within
`1e-12`; a mismatch stops the study before alternatives.

## Output contract, fixed before calculation

Future private namespace: `data/cache/location_edition_sensitivity_v0_1/`.
Future aggregate namespace: `data/processed/location_edition_sensitivity_v0_1/`.
Do not create either during this planning task. Use Parquet for data, not CSV;
the small configuration CSV follows the repository's existing config convention.
Private keys may join player-season-cell records; none enter tracked outputs.
No new shot rows, player identifiers, coordinates, or marker files are published.

### Private player-season outputs

One `player_condition` record per season/player/condition, and six
`player_slider` records keyed additionally by request. Fields below define the
schema; booleans are non-null, counts integers, quantities finite doubles when
available, reasons/statuses strings. Apply the explicit null rules below for
unavailable estimates, paired estimates and empty receiver summaries. Numeric
output retains full precision.

| Table | Required fields besides private keys |
|---|---|
| player_condition | attempts; evidence_status; supported_count; availability; availability_reason; weak_source_capacity; destination_capacity; high_volume; score, score_lower_90, score_upper_90; baseline_evidence_status; evidence_category_changed; availability_transition; score_delta; score_delta_lower_90; score_delta_upper_90 |
| player_slider | requested_share; actual_share; moved_attempt_equivalents; cap_limited; receiving_cap_reached; receiving_count; receiving_final_shares_sorted; receiving_share_min, median, max; relocated_eppa mean/lower_90/upper_90; season_gain mean/lower_90/upper_90; gain_per_100 mean/lower_90/upper_90; actual_share_delta; moved_attempt_equivalents_delta; season_gain_delta mean/lower_90/upper_90; gain_per_100_delta mean/lower_90/upper_90; full_request_achieved |
| player_stability | endpoint; baseline_value; modal_categories; modal_count; baseline_agreement_count; valid_condition_count; unavailable_condition_count; all_27_agree; value_min, median, max; paired_baseline_delta_min, median, max; availability_or_sign_mixed |

The stability key is season/player/request/endpoint, with no condition key
because it summarizes the grid. Score stability uses request 0.25 only.
Private `factor_contrasts` rows use season/player/request/endpoint/factor/fixed
other-factor-levels as keys, plus low_condition_id, high_condition_id,
paired_available, category_changed, availability_transition, signed_difference.
Publish only grouped contrast summaries and counts, never these private keys.

Availability transitions are `gained`, `lost`, `available_both`, or
`unavailable_both`, relative to the production baseline. Evidence-category
transitions retain both categories even when availability does not change.

`receiving_final_shares_sorted` lists final shares only for cells with added
share > `1e-12`, descending, without cell identifiers. Empty list and null
min/median/max mean no receiver. Retain the private cell-keyed allocation for
mass/cap verification, but do not commit it. At 0% the receiver list is empty.

`cap_limited` is the existing helper's strict rule:
`D < min(requested_share,W) - 1e-12`. Separately record
`receiving_cap_reached` when any receiving cell is within `1e-12` of `h`;
reaching one cap need not limit total movement. `full_request_achieved` is
`abs(actual_share-requested_share) <= 1e-12`. At 0% this is trivially true,
including unavailable players; report full-25% counts as the headline.

### Aggregate outputs

For each season/condition/request and for all/high-volume/single-destination/
multiple-destination groups, publish a long-form `aggregate_summary` table:
`protocol_id, season, condition_id, requested_share, group, metric_id,
denominator_n, available_n, missing_n, count, proportion, minimum, q25, median,
q75, maximum`. Non-applicable summary fields are null.

Single/multiple-destination group membership follows the current condition's
evidence status, not baseline status. High-volume membership stays fixed.

Include:

- counts/percentages for all three evidence categories, all availability
  reasons, gained/lost/retained/unavailable-both estimates relative to baseline;
- full-25% achievement counts among all eligible and among available players;
- actual shares, moved equivalents, cap-limited and cap-reached frequency,
  support counts, receiving counts and maximum final receiving share;
- score (25%-request only), season gain, gain/100, relocated EPPA, their 90%
  interval widths, and paired baseline changes;
- each evidence-category transition and stability summary defined below;
- invalid, impossible, failed, and unexecuted case counts, distinct from null
  evidence. A failed run publishes only a failure audit, never a success table.

For numeric distributions use type-7 quartiles and equal weight per player-season,
excluding null estimates while showing their counts. No shot weighting, player
quality ranks, or favorable-subset selection. Report both all eligible coverage
and paired-available numeric comparisons, whose sample can change by condition.
An empty valid group has count zero and null distribution/proportion when its
denominator is zero. A season-total pooled gain is not a primary output.

High volume means the top quarter of fixed eligible players in each season:
sort attempts descending, numeric player ID ascending to break ties, take
`ceiling(n_players/4)`. This gives 80/76/71/73/78 players in newest-first order.
Freeze membership across conditions; no gain or evidence result enters it.
This is an exact rank rule, not reuse of the older 2025-26 audit's 777-shot
cutoff for all seasons. A player can appear in several seasons; any optional
all-season count describes player-seasons and is not independent replication.

### Stability and sensitivity attribution

Primary robustness summaries use the requested 25% setting. Also supply
request-specific summaries for the five other settings; do not choose whichever
request looks most stable. Evaluate each endpoint separately, not a composite:

1. evidence category;
2. estimate availability;
3. full requested share achieved;
4. gain-interval interpretation: `positive` if lower_90 > 0, `negative` if
   upper_90 < 0, `includes_zero` otherwise, `unavailable` for null estimates.

"Stable across all 27" means identical category on that endpoint for all 27
completed conditions. Uniformly unavailable is explicitly labeled and is not
evidence of robust benefit. For "most combinations", use a **descriptive
presentation**, reporting modal categories, their exact `k/27`, and baseline
agreement `k/27`. Do not create a binary majority cutoff or a numerical
score-stability tolerance later. Return all tied modes. For continuous scores,
gains, shares, and interval widths, report ranges/quartiles and paired baseline
delta ranges with valid counts; categorical agreement does not prove numerical
stability.

For factor attribution, compare low versus high levels holding the other two
factors fixed, giving nine matched contrasts per factor per player-season/request.
For categorical endpoints report the number of changed pairs out of nine.
For continuous endpoints report signed contrasts and their mean absolute size
over paired-available comparisons, plus paired-available and null-transition
counts. Display all three factor profiles and the intermediate levels from the
full grid. Call an endpoint "mainly sensitive to attempts/evidence/capacity"
only in the limited descriptive sense of a unique largest contrast summary
with all nine numeric pairs available; otherwise label tied/mixed or insufficient
paired coverage. For categorical endpoints compare changed-pair counts. Do not
combine units or choose one factor label for the whole player.

Flag availability changes or differing gain-interval categories across the
grid as `availability_or_sign_mixed`: too unstable for one unconditional benefit
claim. A uniform includes-zero result also supports no strong positive-gain
claim. These interpretation rules do not pick a production parameter. Report
interactions visible in matched contrasts; marginal labels are not causal
attribution and need not explain the entire range.

## Paired uncertainty and repeated comparisons

Compare each alternative with baseline for the same player-season/request and
posterior draw index. Report differences in posterior-mean gains, median scores,
and actual shares. For gain-difference intervals subtract draw-level gains
before taking 5th/95th percentiles. For score differences report the difference
of displayed medians as the point delta and quantiles of paired draw-level
display-score differences as its interval; the point delta need not equal the
median of the draw differences. Do not require either point convention to lie
inside the interval. Require the interval itself to be ordered.

If one or both conditions lack a gain or score estimate, those paired
deltas/intervals are null; report the availability transition, never impute zero.
Actual-share and moved-attempt deltas remain defined from their recorded values,
including zero movement for unavailable estimates. Baseline
self-comparison has exact zero numeric deltas where defined. Freeze support,
ordering, and allocation once per condition before evaluating gain draws; do
not reselect destinations within each draw.

Publish the full structured grid with paired descriptive differences, not 27
discovery tests. No p-values, post-hoc tests, or claim of simultaneous 90%
coverage across conditions. Per-player posterior intervals quantify ability
uncertainty conditional on the fitted CAR and chosen allocation, not selection
uncertainty or future defensive responses. Aggregate quantiles of interval
widths are descriptive; they are not intervals for aggregate statistics.

## Safeguards and execution gates

Before future execution, commit and push a reviewed isolated calculation runner
that enforces this protocol, without changing production scripts. Require
separate authorization naming this protocol and its pushed commit. The runner
must reject all seasons outside the five listed, especially 2026-27, and have
no model-fitting entry point. Do not invoke existing exporter run modes.

Required checks before publishing a completed study:

1. Verify source revision, protocol/config/helper hashes, five completion
   anchors and their payloads, versions, source counts, grid, full lattice keys,
   and no duplicate/missing player-season records. No silent repair or refit.
2. Reproduce baseline v4 before alternatives. Stop on a baseline mismatch.
3. Assert finite probabilities in [0,1], 4,000 draw columns, positive baseline
   and relocated EPPA when available, valid point values and complete ordered
   intervals. Gains can have negative lower bounds; never truncate them.
4. Assert source-support disjointness, direct focal attempts, threshold logic,
   and no unsupported additions. Support must nest as attempts/evidence become
   stricter; support does not vary with cap or requested share.
5. Assert nonnegative final shares within `1e-12`, unit mass within `1e-12`, and
   unchanged N using `1e-12 * max(1, abs(original), abs(reconstructed))`.
   Assert moved mass equals added and removed mass; actual <= request, W, D.
6. Assert receiving-cell final cap, no additions to historical over-cap cells,
   proportional uncapped allocation and redistribution at each cap. Distinguish
   cap-limited from cap-reached and from weak-source limitation.
7. Across requests within a condition, actual mass, cellwise removals, and
   cellwise additions must be nondecreasing within `1e-12`. Source prefixes
   and fractional boundary rules remain nested. Verify posterior-mean gain
   does not fall, as required by the Location plan; negative posterior-draw
   differences alone are not failures. Never require scores or gains to be
   monotone across evidence/cap conditions, where the supported mix can change.
8. Change synthetic make/miss labels while holding fitted draws and metadata
   fixed: source order, allocation, and attempt selection must not change.
   No real per-shot result enters the future movement function's interface.
9. Check evidence/availability/null rules, exact zero-request gain when
   available, score formula at requested 25%, [0,100] score bounds, finite
   paired deltas, interval order, unique keys and complete output cardinality.
10. Build twice from identical verified draw/input caches into separate ignored
    staging directories. Require byte-identical sorted file inventories and
    SHA-256 payload hashes before atomic publication. Fix field/row order,
    package versions and serialization options; keep run times/timestamps in
    separate private operational logs, outside deterministic analytical payloads.
11. Enforce a tracked aggregate column allowlist and reject private identifiers,
    raw rows, coordinates, draws, fit objects, paths, logs, authorization/lock
    records and checkpoints. The public shot-chart exception is not used here.
12. Confirm production v1-v4, models, Context artifacts, and portfolio unchanged.
    Use exclusive private locks, pre-execution hashes, and atomic completion
    manifests. Recover verified completed work without recalculation; preserve
    partial evidence and never overwrite or auto-retry an unexplained failure.

An unexpected numerical, overlap, nesting, hash, privacy, or baseline failure
stops publication. Preserve the exact condition/stage and aggregate failure
counts, mark remaining cases unexecuted, and request direction. Do not discard
the failed condition, weaken checks, change the grid, or publish incomplete
results as a completed robustness study. Surprising but valid gains are reported
without tuning; they are not on their own an implementation failure.

## Interpretation limits and authorization boundary

Preregistration verification: 40 configuration, parsing, source-hash, boundary,
allocation, fractional-mass, nesting, score, privacy-contract, and deterministic
synthetic checks passed. The first test invocation exposed a missing closing
parenthesis in this task's new test file; it was fixed before freezing. No
production script changed. These tests load configuration/document text and
pure helpers only; they do not run the real grid or verify future result values.

More supported players can mean weaker evidence. Stricter gates trade coverage
for stronger support. Larger caps can allow more theoretical movement while
concentrating attempts; smaller caps can preserve variety and block the full
request. None establishes that an alternative is more accurate.

Gains remain location-only counterfactual estimates based on the same season's
ability and usage. They omit defense, shot creation, game situation, strategic
response, role, health, fatigue, opportunity constraints, free-throw value, and
causal effects. The score remains self-relative, not a player-quality ranking.

This task freezes documents/configuration and outcome-free tests only. No
sensitivity condition, posterior sampling, model fit, production rebuild, or
website change is authorized. Existing hashes/metadata and historical audits
establish provenance, not a result of the unrun grid. Narayan must separately
authorize implementing and executing this frozen study. Any later change to
production defaults requires another decision, even after a completed study.
