# Context Edition M2 first-window training preflight

Status: implementation frozen before fitting; execution pending

Approved design: `5b54ebf6354198b2111fba084e55a9a473802eac`

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

