# Self-Relative Shot Selection Score Plan

**Status:** Narayan approved this specification before any score calculation.
The frozen implementation was committed and pushed as `67916a9`, then the score
calculation completed and passed verification. The website remains out of scope.

## Definition

For each qualified player and each of the frozen 4,000 CAR posterior draws:

`raw score = 100 * baseline expected points per shot / expected points per shot after 25% relocation`

The calculation uses the approved 25% proportional-relocation distribution. It
does not search for a global optimum or score any other slider setting. The
player's own modeled ability surface supplies both expected-points values, so
league averages, ranks, percentiles, and cross-player rescaling do not enter the
formula.

The displayed point estimate is the median of the 4,000 draw-level scores. The
displayed 90% interval uses their 5th and 95th percentiles. The implementation
stores full numerical precision. A future website may show one decimal place.

## Meaning

A score of 100 means the approved 25% relocation scenario finds no remaining
modeled improvement. A lower score means the scenario finds more room to improve
the player's shot mix within areas where that player has demonstrated ability.
The score measures one constrained, self-relative scenario. It does not measure
perfect basketball decisions, overall offensive quality, or a player's standing
in the league.

## Eligibility

The frozen relocation evidence status controls score eligibility. The 122
players with at least two supported destinations receive scores. The output
retains the other 196 players with status `insufficient_evidence`; their
relocated efficiency, raw score, displayed score, and score intervals remain
missing. The implementation cannot substitute zero, 100, a rank, or a model
estimate for missing evidence.

## Raw and displayed values

The implementation preserves every uncapped draw-level ratio for diagnostics.
It caps only the displayed draw-level score to `[0, 100]`, then calculates the
display median and interval. A raw score above 100 means that draw estimated a
worse result under relocation. The diagnostic output reports the number and
share of such draws; it does not discard them or alter the formula.

## Frozen inputs and output

The score uses the verified all-data CAR fit, production lattice, relocation
completion, player evidence table, and published support weights. It regenerates
the same 4,000 joint predictor draws with seed `20260902` because the compact
relocation outputs do not store draw-level values. It must reproduce the saved
production surface means and the published baseline and 25%-relocation means
within `1e-12`. This regeneration does not refit CAR or rerun the relocation
pipeline.

The tracked score namespace contains five small Parquet files: one 318-row score
table, one aggregate diagnostic row, calculation notices, sanity checks, and a
method manifest. The script saves no draws, shot rows, ranks, or labels. It uses
an ignored lock and atomic completion marker and refuses to overwrite partial or
completed output.

## Verification rules

Before publication, the implementation must confirm:

- all production and relocation hashes match their frozen values;
- all 318 players remain present, with 122 qualified and 196 marked
  `insufficient_evidence`;
- each qualified draw uses the approved ratio and positive expected-points
  inputs;
- equal baseline and relocated efficiency gives 100, while positive modeled
  gain gives a score below 100;
- qualified raw values are finite, displayed values stay within 0 to 100, and
  both 90% intervals are ordered;
- all score fields remain missing for insufficient-evidence players; and
- the schema contains no rank, percentile, league normalization, performance
  label, other-slider score, or website field.

The compression audit reports the qualified score minimum, quartiles, median,
maximum, interquartile range, and counts at or above 95 and 99. It also reports
the count at 100. These diagnostics cannot change the approved formula after
results appear.

## Verified result

The calculation retained all 318 players. Scores and intervals exist for the
122 qualified players; the other 196 rows are marked `insufficient_evidence`
and keep every score field missing. Across qualified players, displayed scores
ranged from 91.05 to 97.69. The first quartile, median, and third quartile were
93.02, 93.99, and 94.87, and the interquartile range was 1.85 points. Twenty-nine
players were at or above 95; none were at or above 99 or exactly 100. The scores
therefore occupy a fairly narrow part of the public scale, but the frozen
formula was not changed after this audit.

The median raw 90% interval width was 4.62 points; widths ranged from 2.58 to
12.68. Every qualified interval was finite and ordered. Before display capping,
1,815 of 488,000 draw-level scores (0.372%) exceeded 100, spread across 58
players. No player's median raw score exceeded 100, and no displayed point or
interval bound required a visible cap at 100.

The atomic result reproduced the saved CAR surface means and the published
baseline and 25%-relocation means with maximum absolute difference zero. It
reported no posterior warnings. Independent verification matched all output
hashes, row counts, missing-value rules, bounds, interval order, and the absence
of ranking fields. A post-result audit found that the first aggregate diagnostic
file reported one affected player because a summary variable shadowed the input
column. The order of those two summaries was corrected without regenerating
draws or changing any player score; the original files remain preserved in the
ignored cache.

## Limitations

The score inherits the relocation model's assumptions. It treats the player's
modeled make probability as stable after shifting attempts and omits defensive
response, shot creation, fatigue, and game context. Posterior intervals describe
uncertainty within the CAR model; they do not cover those missing real-world
effects or prove that relocation would cause added points.

## Roadmap after score verification

1. Prepare compact website-ready exports.
2. Review the portfolio integration design.
3. Obtain Narayan's approval before modifying `portfolio-site`.
