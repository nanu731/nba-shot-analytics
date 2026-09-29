# Context Edition M3 predictor-data audit results

Status: complete predictor-only audit

Protocol: `context_m3_data_audit_v0.1.0`

## Outcome

Period and game clock are complete across all 1,091,329 historical attempts.
Home/away status is unavailable for 117,560 attempts, or 10.77%. Verified score
margin is unavailable for 120,416 attempts, or 11.03%.

The missing context comes from linkage availability. Every ambiguous or
unmatched attempt lacks both home/away status and score margin. All 973,769
unique exact matches have home/away status. Only 2,856 exact matches, or 0.29%,
lack a verified score margin because the independent score-sequence check did
not pass.

## Field decisions

- **Period:** go. It is complete in every season.
- **Period clock:** go. It is complete and ranges from 0 to 720 seconds. The
  later model preregistration must still freeze its functional form.
- **Home/away:** conditional go with an explicit unknown level for unmatched
  attempts.
- **Score margin:** conditional go using only verified lagged scores. The model
  candidate should use a neutral zero fill plus a missingness indicator so it
  can predict every shot without claiming that missing states were recovered.
- **Shot clock and direct defense:** no-go. No verified same-attempt source is
  available.

Score-margin coverage ranges from 87.74% to 90.01% by season. Its observed
median is zero or minus one point, while one-percent and 99-percent values range
from minus 32 to minus 29 and 27 to 31 points. These are predictor-support
descriptions, not shooting-performance results.

## Imputation decision

Complete cases remain a diagnostic because they preserve observed context but
discard about one shot in nine and change the evaluation sample. Silent mean or
median imputation is rejected.

Predictive mean matching does not advance. The missing values chiefly represent
failed or unavailable joins rather than an ordinary unobserved numeric
measurement. PMM would add complexity and fabricate plausible-looking game
states without resolving the source failure. A later preregistration may compare
the simple missingness treatment with complete cases, but it must not describe
filled values as observed or recovered context.

## Verification

The runner selected only the frozen predictor and join-quality columns. Timing,
season, schema, source-hash, leakage, deterministic calculation, and
byte-identical serialization checks passed. The committed bundle contains 12
small aggregate or declarative CSV files and no shot, player, game, or event
identifier.

No model was fit. No outcome column was read. No 2026-27 data was accessed. The
Location Edition and portfolio were unchanged.

## Interrupted publication recovery

On 29 September 2026, recovery found local HEAD, upstream and GitHub at
`942aedc7394d33591ad9959ac744924d8980c8c5`. The result documentation and complete
12-file aggregate bundle existed, but no result commit or staged change existed.
No active audit/model process or Git index lock remained. The existing verify
mode and synthetic checks passed; all output sizes, SHA-256 hashes, source hashes,
exact file inventory and aggregate-only schemas passed independent checks.
The recorded two-build determinism evidence was reused, not regenerated. The
only verification warning was the existing Arrow build-version notice (4.6.1
versus runtime 4.6.0). Recovery read no outcome and changed no audit calculation.

## Next gate

Freeze the smallest M3 formula and historical rolling-origin comparison against
M1. The recommended starting candidate adds period group, period seconds
remaining, home/away with an unknown level, verified score margin, and a score-
availability indicator. Keep the terms additive unless a preregistered
basketball reason justifies an interaction.

Location archetypes remain separate. Define them only from stable Location
Edition profile features, never from unfinished Context predictions.
