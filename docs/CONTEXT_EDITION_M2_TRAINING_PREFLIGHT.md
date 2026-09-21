# Context Edition M2 first-window training preflight

Status: complete; D1 recovered without refitting and M2 fitted exactly once

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

## Measured result

The approved recovery completed on commit
`669e48ae4270d8448fe460b19baa291f159f09e0`. D1 retained its original
SHA-256 `e7632292dd9a8c0d2b223430862efa9bf0216d7d16d171e37d9f2752c24b3fb9`
and was not refitted. M2 was fitted once and has SHA-256
`5c71318fc300b2f5a77ab41656a69af895a111280f26a1e3fe6035b1259ff43f`.
The completed private-manifest SHA-256 is
`5a3e3265284bd97d050246adf4d6c0ac5552575ba47490058821f65de5d6ae29`.

Both models used 433,942 shots from 2,460 games and 700 players. D1 used
18,396 grouped rows and 711 coefficients; M2 used 57,190 grouped rows and 720
coefficients. M2 fitting took 1,161.984 seconds and serialization took 15.191
seconds. Its exact child CPU accounting was 1,126.176 user seconds plus 18.933
system seconds. The recovery wall time was 1,192.200 seconds. Adding the
preserved D1 fit-and-serialization interval gives 1,687.759 seconds of measured
active wall time. Peak sampled process-tree resident memory was 2,596,306,944
bytes. D1's fit and serialized sizes were 30,653,296 and 29,759,296 bytes; M2's
were 35,624,272 and 34,134,228 bytes.

Both fits reported full convergence, finite coefficients and covariance,
deterministic predictions, valid known- and unseen-player behavior, finite
interior probabilities, exact expected-points conversion, and valid predictions
on the corrected 178-row distance boundary grid. M2 also predicted all 56
taxonomy combinations, including `other_or_unknown`. D1's distance EDF was
7.5551 with k-index 0.9101; M2's was 7.3584 with k-index 0.9670. Both retained
the registered `k = 10`. M2 captured no model warning or message. D1 warning
and message counts remain unavailable because the interrupted parent did not
persist them.

The private manifest and prediction hashes reproduced without refitting either
model. No performance metric was calculated, and outcomes from 2023-24 through
2026-27 remained unopened. The implementation is operationally ready for the
separately pre-registered historical M2-versus-M1 development evaluation.
