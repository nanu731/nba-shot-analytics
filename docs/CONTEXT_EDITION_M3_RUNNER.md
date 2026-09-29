# Context M3 outcome-free runner and training boundary

Status: preregistration implementation; no M3 fit or validation execution.
Exact model and evaluation rules: `CONTEXT_EDITION_M3_PREREGISTRATION.md`.

## Modes and scope

Run from the repository root with the existing R installation:

- `R/context_edition_m3_tests.R`: invented predictors, responses and mock
  predictions only. It does not fit even a synthetic model.
- `R/context_edition_m3_runner.R audit`: verify configuration, inherited helper
  hashes, existing M1 artifact/manifest hashes and predictor-only dimensions.
- `publish-audit`: the same check, with new atomic aggregate dimension bundle;
  refuses any existing output instead of overwriting it.
- `fit development_1`: dormant, separately authorized first-window M3 fit. It
  reuses M1, checks clean pushed code, a locked pre-result revision and a private
  record with comparison ID, authorization=true, pre-result commit, action=fit,
  model_id=M3. No authorization record exists from this task.
- `verify development_1`: hash-only verification of a completed private M3 fit.

The runner has no `evaluate` or `finalize` command. They fail before data access.
Implementing the future validation execution stage requires separate approval;
the model, metrics, bootstrap, support checks and decision rule are frozen here.
The pure bootstrap/selection adapters call unchanged M2 helpers and rename only
the candidate. No Context M1/M2 file is edited.

## Recovery and privacy

An exclusive per-window attempt directory prevents concurrent or repeated fits.
It retains PID/start metadata, a fit-start marker, warnings and failure evidence.
A model returned by R is first saved as private partial evidence. Only passing
checks allow a staged bundle to publish by one directory rename. No deletion,
automatic cleanup, refit or automatic retry is performed. A completed bundle
contains fit, metadata, checks and their SHA-256 completion manifest. Recovery
verifies exact inventory, hashes, configuration, window, input hashes and fit
accounting before reuse. An incomplete attempt requires a recovery decision.

All runtime state stays under ignored `data/cache/context_edition_m3/`; inherited
M1 artifacts stay where they are. The public preregistration bundle contains
only window-level dimensions and declarative hashes. Canonical reads select an
exact column allowlist. Training responses are accessible only after the fit
authorization; validation predictors never include make/miss. A prospective
season fails the guard before path construction. Current M3 access flags are
false; prior M2 historical access remains immutable history, not a new M3 read.

## Outcome-free measured checks

All three predictor-support checks passed, including period-specific clock
bounds, exact score verification, training fixed-design rank 20, factor support,
and validation score-range support. No nonlinear correction was warranted.

| Window | Shots | Players | Exact grouped rows | Coefficients | Estimated working GiB |
|---|---:|---:|---:|---:|---:|
| development_1 | 433,942 | 700 | 430,698 | 720 | 10.2 |
| development_2 | 652,642 | 808 | 646,241 | 828 | 16.9 |
| development_3 | 872,169 | 913 | 862,149 | 933 | 25.0 |

Counts are measured from selected predictor columns. Memory is a conservative
estimate (four dense designs plus 1 GiB), not peak RSS. Physical memory is
16 GiB; later windows therefore fail the current resource gate before fitting.
Do not silently substitute bam, round predictors, drop terms or change grouping.
First-window execution still requires safe current memory pressure and separate
authorization. The Arrow package emits its existing build-version notice.

The new suite has 45 passing checks; the unchanged M2 evaluation, M2 protocol
and baseline suites add 63 passing checks. Parsing passed. The first formula
test compared R formula environments as well as expressions; it was corrected
to compare the exact deparsed formulas. This test-only defect changed no model.
Recovery tests include a synthetic completed bundle, wrong configuration/window,
corrupted fit bytes, duplicate locks, no-overwrite publication and hash checks.

Known limitation inherited without changing results: the M2 metric register
describes points bias as predicted minus realized, while its frozen helper and
published results use observed minus predicted. M3 preserves the helper's
observed-minus-predicted diagnostic sign and labels it explicitly; this is not
a selection metric. Distance bands remain inherited diagnostic-only reporting,
not model inputs. Predictor-side checks do not establish outcome-linearity.

## Next authorization

Authorize only a monitored `development_1` training feasibility run: reuse the
hash-verified M1, fit frozen M3 once on 2021–22/2022–23, verify and preserve the
atomic checkpoint, and publish aggregate training QA. This does not authorize
historical validation outcomes, later-window fits or 2026–27. Later windows need
a resource plan on sufficient hardware without changing the frozen model.
