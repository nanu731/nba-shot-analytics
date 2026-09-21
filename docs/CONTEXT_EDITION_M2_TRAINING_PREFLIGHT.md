# Context Edition M2 first-window training preflight

Status: approved partial recovery frozen before the one-time M2 fit

Approved design: `5b54ebf6354198b2111fba084e55a9a473802eac`

Pre-fit implementation commit: `18cbe2ffcd85641214419d88a5520f0b55e561da`

Preflight version: `context_m2_training_preflight_v0.1.0`

## Purpose

This task checks only whether the frozen D1 and M2 models can be fitted,
recovered, and used safely on the 2021-22 and 2022-23 training window. It cannot
compare predictive performance, rank models, or advance M2.

The runner reads make/miss outcomes only from the two named training partitions.
It contains no path to a 2023-24, 2024-25, 2025-26, or 2026-27 partition. It
creates no validation predictions or performance metrics.

## Frozen implementation

- D1 is M0 plus `s(shot_distance_feet, bs = "cr", k = 10, m = 2)`.
- M2 is immutable M1 plus the identical smooth.
- Both use grouped binomial logit `mgcv::gam()`, REML, `discrete = FALSE`, no
  shrinkage, and the exact registered factor and unseen-player rules.
- D1 groups by player, point value, and whole-foot distance.
- M2 additionally groups by finish and creation family.
- The runner has `audit`, `run`, and `verify` modes. Only `run` can fit.
- `run` requires this isolated branch to be clean and pushed, refuses an active
  lock or duplicate R process, checks disk space, and fits each model once.
- A child process performs each unchanged single-threaded fit so the parent can
  sample the process tree's memory and CPU use. This is operational isolation,
  not a parallel or statistical change.
- Fits, grouped outcomes, logs, PID metadata, and resource samples remain under
  ignored `data/cache/`. Only compact aggregate checks may enter Git.
- The private checkpoint directory is published atomically only after both fits
  pass every frozen check. Recovery verifies hashes and reproduces prediction
  hashes without refitting.

## Basis-dimension behavior

For each training fit, set seed `20260916` and run
`mgcv::k.check(subsample = 5000, n.rep = 400)`. The registered `k = 10` is
adequate unless distance EDF is at least `0.95 * (k - 1)` **and** the k-index is
below `0.9` with `p < 0.05`.

If either model triggers the registered `k = 20` escalation, this runner records
the diagnostic and stops. It does not silently refit at `k = 20`; Narayan will
receive the evidence and can authorize the already-preregistered correction in
a separate execution task. No validation outcome may be opened.

## Outputs after execution

The tracked result namespace will contain only training totals, grouped-row
checks, formula and feature checks, fit/convergence/resource diagnostics,
smooth adequacy, checkpoint verification, package versions, seal flags, and a
readiness decision. It will contain no shot, game, or player identifier and no
training or validation performance comparison.

## Stop condition

Stop when both `k = 10` fits pass and the checkpoint recovers without refitting,
or when a genuine fit, sanity, or basis-dimension blocker is preserved. Do not
open 2023-24.

## Approved partial recovery

The first execution fitted D1 once and saved it before its checker stopped on
an omitted import for the already-frozen expected-points helper. A second
checker defect expanded all retained player factor levels when it intended to
construct a one-player, 178-row distance boundary grid. Neither defect changed
the fitted D1 model or exposed a validation outcome.

Narayan approved one infrastructure-only recovery. It verifies the exact saved
D1 fit and grouped-count hashes, imports the existing expected-points helper,
constructs the boundary grid from one character value before restoring all
training factor levels, and permits only M2 to enter the fitting loop. The D1
warning count remains unavailable because the interrupted parent process did
not persist its returned warning metadata. The recovery does not interpret that
missing metadata as zero.

The recovered D1 artifact may be promoted only after every corrected frozen
check passes. M2 may then be fitted exactly once. The final two-model checkpoint
is published atomically only if both models pass and its recovery prediction
hashes reproduce without refitting.
