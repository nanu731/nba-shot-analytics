# Location sensitivity execution

Study: `location_sensitivity_v0.1.0`. The immutable preregistration is commit
`e8cc2704b59a99862204276945a83982dec956e3`. Narayan authorized implementation
and execution in the attached request `d6d76981-c3dd-4b7a-8286-b3a815613ffa`.
The older planning-only authorization language describes the earlier freeze;
this later authorization permits the registered calculation, not a design change.

## Implementation and lock

`R/location_edition_sensitivity.R` has explicit `audit`, `authorize`, `run`, and
`verify` modes. Sourcing it defines functions without running the study. The
pure calculation helpers reuse the frozen production allocation functions.
The reporting file creates private keyed records and identifier-free aggregates.
The tests use invented inputs only.

The execution JSON starts with `pre_result_implementation_commit: PENDING`.
After the complete implementation and tests reach origin, a separate lock
commit replaces that value with the verified full implementation SHA. The
runner checks that only this field changed, that code still matches that
implementation, and that HEAD matches upstream and GitHub on the named branch.
Real execution rejects a pending lock or a dirty tracked tree.

Private authorization names the same frozen configuration, code hashes,
implementation commit and five authorized seasons. An exclusive directory lock
records the process ID. A live owner blocks another run. Recovery preserves a
dead owner's lock by rename. An unexplained failure blocks execution pending
separate authorization; no automatic retry or post-result correction is allowed.

## Source verification and baseline gate

Before loading any model, the runner checks the five anchored production
completions, their input/configuration/model/surface/uncertainty/checkpoint
payload hashes, raw hashes, runtime versions and the v4 payload inventory.
It uses the production lattice and verifies eligible shot counts, direct cell
counts, makes, games and point values. No make/miss value enters movement.

Each season's saved CAR fit supplies the registered 4,000 joint predictor
draws once, with seed `20260902` and the production sampling arguments. A
started marker prevents repeating an incomplete recovery without a decision.
Complete private draw caches include input and draw payload hashes. Draw means
must reproduce saved production draw means within `1e-12`.

The runner reconstructs all five production baselines before alternatives.
It compares coverage, exact evidence/support identities, availability, weak
source counts/capacity, effective values, all slider quantities, allocations,
scores, intervals and nulls against v4. Numeric tolerance remains `1e-12`.
Fractional boundaries and source order receive independent analytic checks.
Failure preserves draws and evidence and publishes no sensitivity results.

## Calculation, reporting and recovery

The ordered 27-condition CSV and six registered shares remain unchanged.
Movement uses full-precision posterior draw means, fixed support, weakest-first
removal, proportional capped additions and fractional attempt equivalents.
Intervals retain negative lower bounds. Paired differences use matching draw
columns. Unavailable gains and scores stay null, including at zero request.

Condition checkpoints contain private player-condition, player-slider and cell
allocation records. Season summaries contain private stability and nine-pair
factor contrasts. Recovery verifies payload hashes before reuse. Interrupted
partial directories remain intact and do not count as complete checkpoints.

Categorical stability reports exact modal and baseline agreement counts out of
27, including ties. Numeric summaries report ranges without a binary stability
cutoff. The private `all_27_agree` field applies only to categorical endpoints;
numeric endpoints use a non-applicable false placeholder and omit that metric
from aggregate reporting. Matched contrasts retain the other factors' levels to expose interactions.
High-volume membership uses the preregistered attempt-rank quarter in each season.

Two clean builds reuse identical verified draws and inputs. Their sorted
inventories, including private analytic checkpoints, must have identical bytes.
Only after both builds pass may aggregate Parquet payloads publish by directory
rename. Private completion files never enter the tracked output directory.
The public table uses the preregistered column allowlist; no player identifier,
cell identifier, shot row, fitted model, draw matrix, authorization or log enters it.

Operational event records stay private and outside deterministic payloads.
They contain stage wall/CPU clocks, point-in-time RSS, disk snapshots and draw
warnings. Maximum sampled RSS is not a continuous peak-memory measurement.
The runner rechecks full source hashes and unchanged production-export bytes
before publication. The protected Context decision remains **retain M1**.

## Outcome-free verification

The original 40 preregistration checks pass. The execution suite covers the
ordered grid, frozen code hashes, seal/configuration, source-independent
movement, thresholds, cap redistribution, fractional mass, nulls, exact zero
request, independent production-shaped baseline reproduction, paired deltas,
all-condition private cardinality, aggregate privacy, modal counts, matched
contrasts, byte determinism, locks and interrupted/corrupt checkpoint rejection.
No real source table, model or posterior enters those tests.

The existing Arrow build notice (built under R 4.6.1; installed R 4.6.0) remains
visible. A sandboxed audit can also report denied hardware-cache queries; an
unsandboxed execution uses the unchanged installed packages. No dependency is added.

## Interpretation boundary

This study measures sensitivity to evidence and capacity rules. It cannot
select a more accurate production threshold or establish causal improvement.
Production v1-v4, the Context M1 decision, 2026-27, M3 and the portfolio remain
outside the calculation. Any later production-default change needs a new decision.

## Reporting-memory correction and one corrected resume

Narayan authorized this recovery after one unchanged resume reproduced severe
memory pressure during season reporting. Both interrupted runs ended by an
authorized SIGINT, not by a statistical or baseline failure. The private active
recovery records preserve the original logs, locks and checkpoint inventories.

The original calculation revision remains
`52bc0b45d4809a96e743c12976bdf728fe478ac6`, with implementation `b0659c8`.
Only `ls_stability()` changes its reporting construction: preallocated columns
replace retained one-row tables. Its calculations, loop order and final table
contracts remain unchanged. No other reporting function changes.

Before execution, an isolated checker regenerated all six summary tables for
each season from preserved condition tables. Exact R-object and Parquet SHA-256
comparisons passed for schemas, types, keys, order, values and null positions.
The checker has a 600-second per-season bound and does not load models, draws
or raw shots. Its temporary files and resource logs remain private.

| Season | Verification wall seconds | Peak footprint bytes |
|---|---:|---:|
| 2025-26 | 56.52 | 1097320200 |
| 2024-25 | 55.28 | 1090570016 |
| 2023-24 | 51.70 | 973145768 |
| 2022-23 | 53.05 | 1028753112 |
| 2021-22 | 55.66 | 1060718344 |

These are summary-verification measurements, not full-study runtime estimates.
The unchanged interrupted resume reached 17096177008 bytes peak footprint.

`config/location_edition_sensitivity_reporting_correction.json` records the
original calculation revision and the separately pushed reporting-correction
commit. The original execution configuration, authorization and checkpoint
contexts remain untouched. Those contexts identify the original analytical
contract; the separate correction audit identifies subsequent execution code.
Do not relabel an old checkpoint as produced by the correction.

The runner requires all five byte-equivalence records, a pushed correction
lock, and existing draw/baseline caches. It preserves a private single-use
`corrected-resume-started.rds` containing execution provenance and the inventory
of prior atomic paths. This blocks another corrected resume without a new
decision. A separate aggregate `reporting_correction_audit.parquet` records the
two revisions without altering existing analytical output schemas.

Recovery starts from 135 first-build conditions, five first-build summaries,
27 second-build conditions, five draw caches and five baselines. Only missing
second-build work may be calculated. Full byte determinism and source/privacy
checks remain publication gates. Stop gracefully if severe memory pressure
recurs; no repeated restart or broader optimization is authorized.

The one corrected resume completed with exit code 0 and passed full two-build
byte equality. See [measured results](LOCATION_EDITION_SENSITIVITY_RESULTS.md)
for completion, resource measurements, aggregate findings and limitations.
The single-use record prevents another run; use `verify` for completed-output
recovery. Keep the private checks and old locks intact.
