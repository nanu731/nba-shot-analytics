# NBA Shot Selection Analysis

Sections A, B and C are **rules**. Follow them exactly.
Sections 1 through 23 are **reference**. Consult them when the task touches them.

**This file is committed to git.** An earlier version was gitignored, was lost when
`pps-rebuild` was squash-merged into `main`, and cost a full session to reconstruct from
code — a reconstruction that contained errors. Do not re-add it to `.gitignore`.

Last corrected 2026-08-26, folding in all nineteen entries of `ASSUMPTIONS.md`.

---

# A. HARD RULES

Violating any of these breaks the project. There are no exceptions and no
situations where a rule is "probably fine to skip."

**A1. `main` is the active branch. Commit there.** The old `pps-rebuild` branch was
squash-merged into `main` and is now historical; `main` no longer holds the abandoned
eFG% version. Check with `git branch --show-current` before any commit. Do not commit to
`pps-rebuild`.

**A2. NEVER read the dead files.** `src/zones.py`, `src/metrics.py`,
`src/court.py`, `src/viz.py`, `src/fetch.py`, `archive/`, `outputs/`, or any old
notebook. They are deleted. Finding them in git history is not permission.

**A3. NEVER use eFG%, true shooting, or any metric other than PPS.**

**A4. NEVER define a zone boundary outside `R/zone_model.R`.** Zones are computed from
shot coordinates, and every number that places a boundary lives in that one constants
block. No second classifier, no boundary hardcoded in a stage script, a chart, or the
export. `classify_zone()` and `zone_polygon()` both read those constants, so a boundary
change is a one-line edit that moves the classifier and the outline together.

*Superseded 2026-08-27.* A4 previously read "NEVER write your own zone classifier. Zones
come from concatenating `SHOT_ZONE_BASIC` and `SHOT_ZONE_AREA`." That ban existed because
an early version of this project wasted sessions deriving radial boundaries and checking
them against a hand-written classifier, and the league's labels were both less work and a
stronger claim. It was lifted because the labels turned out to encode two things that are
not basketball distinctions: the scheme mixes a rectangular lane with a polar grid, so the
two disagree along the lane walls and leave slivers, and it changes its angular thresholds
at 16 feet, which puts a step in the middle of a zone. What A4 protected against was two
definitions drifting apart. The rule above protects against the same thing by a different
route. See `ASSUMPTIONS.md`.

**A5. NEVER add a minimum-attempt filter at the zone level.** Every zone with one
or more attempts is included. Thin cells are handled by shrinkage, not exclusion.

**A6. NEVER add an eligibility gate beyond 20 games and 250 attempts.** No
shots-per-game, no minutes-per-game.

**A7. NEVER edit a `.qmd` file directly.** Give the user labeled blocks to paste.

**A8. NEVER assume.** If a fact is unknown, unverified, or ambiguous, stop and ask.
Do not fill gaps with plausible defaults. Do not state inference as fact. This includes
claims about repository or remote state: query the remote before describing it. See
Section 21.

**A9. NEVER silently coerce, drop, or NA.** If a join loses rows, an MLE fails to
converge, or a value is unexpected: warn or stop.

**A10. NEVER build anything in Section 12 (Deliberately out of scope).**

**A11. ALWAYS verify before proceeding.** After each step, print something
checkable and wait for the user to confirm. Verify a build criterion from the state it
claims to build from — a run against existing output is a regression test, not a
reproducibility test. See Section 21.

**A12. ALWAYS split responses over ~200 lines of code.** Say so up front. A
previous session hit the output ceiling mid-task and lost the work.

**A13. ALWAYS write Parquet, never CSV.** `GAME_ID` stays character end to end.

**A14. ALWAYS pass `season` as an argument.** Nothing hardcodes a season string.

**A15. NEVER write a large file to `data/processed/`.** Only the three small output
tables belong there. Large intermediates go to `data/cache/`; shot-level data stays in
`data/raw/`. **That directory is committed to git** (Section 13), so anything written
there is permanent repository weight.

**A16. NEVER commit raw NBA data in any form.** `data/raw/` and `data/cache/`
stay gitignored permanently. Do not commit shot-level Parquet, CSV, or JSON. Do
not copy raw rows into `data/processed/` or `export/`. Do not suggest committing
them for reproducibility, for convenience, or for any other reason. Only derived
aggregates leave this machine.

---

# B. BEFORE YOU ACT

Run this checklist mentally before every substantive response. It takes seconds
and it is the mechanism that makes Section A hold.

**B1. Am I about to add complexity?** A package, an endpoint, a column, a modeling
stage, a file. If yes: name the specific problem it solves, out loud, before
writing anything. If you cannot name one, do not add it. This project's guiding
principle is Occam's razor and the user has stated it as overriding.

**B2. Am I about to state something I have not verified?** Check it instead.
Confident claims that turned out false when tested: that `CLOSE_DEF_DIST` was in the raw
data; that renormalizing would advantage narrow players; that defenses would depress a
specialist's zone efficiency; that the score's correlation with raw PPS came from scale
amplification (entry 10); that split-half `k` would diverge in the thinnest zones (entry
18); that family-pooling correlations of 0.36–0.68 were meaningful when they included the
zone being predicted. Each was plausible. Each was wrong.

**B3. Does what I am about to do touch a rule in Section A?** Reread that rule.

**B4. Does the data contradict this document?** Say so. Do not reconcile silently.
Several conclusions here were reached by correcting earlier errors and this
document can be wrong again.

**B5. Am I writing a comment that restates the code?** Delete it. See Section 20.

---

# C. SELF-AUDIT

The user cannot watch every action and has said so directly. These make your work
inspectable.

**C1. At the end of each work session, state plainly:** what you changed, what you
assumed, and anything you were unsure about. Do not omit the third one because
everything seemed to work. Handoff blocks must stand alone for a reader with no context
on the session; they get forwarded.

**C2. Maintain `ASSUMPTIONS.md` at the project root.** Every time you make a
choice the brief does not explicitly cover, append an entry: the choice, the
reason, and the date. Name the sections of this file it amends. This is the audit trail.
It remains gitignored; this file no longer is.

**C3. If you catch yourself having violated a Section A rule, say so immediately**
and unprompted. A reported violation is recoverable. A hidden one compounds.

---

# REFERENCE

Everything below is context, not commands. Read what the current task needs.

---

## 2. The question

**Do NBA players take most of their shots from the zones where they generate the
most points?**

For each player, compare where they actually shoot against where a league-typical
player shoots, holding that player's own zone-by-zone shooting ability fixed. The
difference is attributable to allocation rather than skill.

Three consequences drive every decision below. The unit of analysis is the
player-zone cell, not the shot. The efficiency measure must be per-attempt, since
raw point totals would just measure volume. And the comparison must hold ability
constant, since the question is about allocation, not about who shoots better.

---

## 3. Core metric: Points Per Shot

PPS is total points generated in a zone divided by total field goal attempts in
that zone. Made two-pointer = 2, made three-pointer = 3, miss = 0.

This is the only efficiency metric in the project. **eFG% is not used anywhere.**
An earlier version used it and it was replaced: eFG% is a rescaled shooting
percentage, and the research question is about points.

### Point-homogeneity

After cleaning, every zone contains shots of exactly one point value. All two-point
zones contain only two-pointers; all three-point zones contain only three-pointers.
Therefore:

    PPS[p,z] = v[z] * FG_pct[p,z]        where v[z] is 2 or 3

This matters because shrinking PPS reduces exactly to shrinking a binomial
proportion, which is a solved problem. **Do not build a custom shrinkage scheme
for PPS.** Shrink FG% and multiply by the zone's point value.

### The twenty-shot exception, dropped in cleaning

Point-homogeneity is **not true of the raw data**. In 2025-26, twenty shots carry a
`SHOT_TYPE` that contradicts their zone's point value: twelve labelled `Above the
Break 3` were scored as 2PT field goals, eight labelled `Mid-Range` as 3PT. All twenty
sit between 21 and 24 feet and all are jump shots, so they are boundary cases where the
NBA's coordinate-derived zone label disagrees with the value actually scored.

**Stage 2 drops them.** The identity above is load-bearing, and the alternatives were
worse: valuing by `SHOT_TYPE` breaks it in six zones, valuing by zone knowingly
misvalues twenty shots. Twenty of 219,160 is 0.009 percent and moves no player's score
measurably. The filter is a join against the 14-zone reference keeping only rows where
`zone_value` matches the `SHOT_TYPE`-implied value.

Row counts through cleaning: 219,160 raw, minus 38 backcourt, minus 20 clashes, leaving
**219,102**. State the drop in the writeup.

---

## 4. Zone model: 14 zones, taken directly from the NBA

Zones are **not derived, not computed, not classified**. The NBA already
classified every shot. The raw data contains `SHOT_ZONE_BASIC` and
`SHOT_ZONE_AREA`, and the zone key is those two columns concatenated:

    zone = SHOT_ZONE_BASIC || ' | ' || SHOT_ZONE_AREA

Verified against 2025-26 data. Counts below are **post-cleaning** and sum to 219,102.
Add the 38 backcourt shots and the 20 point-value clashes of Section 3 to reach the
219,160 total in the raw file.

| SHOT_ZONE_BASIC | SHOT_ZONE_AREA | Points | 2025-26 shots |
|---|---|---|---|
| Restricted Area | Center(C) | 2 | 62,253 |
| In The Paint (Non-RA) | Center(C) | 2 | 39,141 |
| In The Paint (Non-RA) | Left Side(L) | 2 | 2,253 |
| In The Paint (Non-RA) | Right Side(R) | 2 | 2,514 |
| Mid-Range | Left Side(L) | 2 | 5,819 |
| Mid-Range | Left Side Center(LC) | 2 | 2,861 |
| Mid-Range | Center(C) | 2 | 4,718 |
| Mid-Range | Right Side Center(RC) | 2 | 2,806 |
| Mid-Range | Right Side(R) | 2 | 5,813 |
| Left Corner 3 | Left Side(L) | 3 | 12,210 |
| Right Corner 3 | Right Side(R) | 3 | 11,360 |
| Above the Break 3 | Left Side Center(LC) | 3 | 26,511 |
| Above the Break 3 | Center(C) | 3 | 17,219 |
| Above the Break 3 | Right Side Center(RC) | 3 | 23,624 |

An earlier version of this table counted `SHOT_ZONE_BASIC || SHOT_ZONE_AREA` alone and so
absorbed the clashes into six of these rows. Those six are the ones that changed.

These 14 zones reproduce the NBA.com shot chart, which is the visual reference for this
project. The twenty dropped clashes are the one documented departure.

**Backcourt is excluded entirely.** Drop rows where `SHOT_ZONE_BASIC = 'Backcourt'`
or `SHOT_ZONE_AREA = 'Back Court(BC)'`. Both columns must be tested; they do not
perfectly overlap. That is 38 shots in 2025-26, all buzzer heaves. The NBA's own charts
exclude them.

`SHOT_ZONE_RANGE` is a third column that subdivides four zones by distance. **It is
not used.** It would push the model to 18 zones and create cells too thin to
estimate. The column stays in the Parquet file, so a distance breakdown remains a
`GROUP BY` addition later rather than a re-collection.

### Why this replaced the old approach

The previous version spent multiple sessions deriving radial zone boundaries,
constructing polygon vertices, and verifying them against a hand-written classifier
using random point sampling. All of it was unnecessary. Using the NBA's own labels
is less work and a stronger claim.

### No zone-level minimum

Every zone where a player has at least one attempt is included. There is no
minimum-attempt filter at the zone level, and none should be added.

The reasoning is that **low volume in a zone is itself the signal the metric
measures.** A player taking few shots from a zone is precisely the observation the
project is about. Filtering thin zones would discard the data most relevant to the
question. Sample-size noise in thin cells is handled by shrinkage (Section 6), not
by exclusion.

Build a full 14-row grid per player, including zero-attempt cells.

---

## 5. Player eligibility

A player qualifies within a season if:

- **games >= 20**, where games = `COUNT(DISTINCT GAME_ID)`
- **total field goal attempts >= 250**

Both gates apply, and both are computed **after cleaning**.

| Season | Raw | After cleaning | Qualifying | Their shots | Grid rows |
|---|---|---|---|---|---|
| 2021-22 | 216,722 | 216,037 | 312 | 193,393 | 4,368 |
| 2022-23 | 217,220 | 216,617 | 292 | 192,772 | 4,088 |
| 2023-24 | 218,700 | 218,214 | 281 | 192,590 | 3,934 |
| 2024-25 | 219,527 | 218,960 | 304 | 194,516 | 4,256 |
| 2025-26 | 219,160 | 219,102 | 318 | 194,967 | 4,452 |

For 2025-26, 436 players clear the games gate and 319 clear the attempts gate; 318 clear
both, out of 582 who took any shot.

### Where 250 came from

Among players with 20 or more games, the 25th percentile of total attempts is 235.75.
250 is that rounded. The derivation belongs in the writeup.

### The gate that was removed

A shots-per-game gate of 5.0 was designed and then **deliberately dropped.**
Inspecting the 23 players it excluded showed roughly half were rim-running centers
and power forwards playing genuine rotation minutes: Kornet, Robert Williams III,
Jaxson Hayes, Missi, Kalkbrenner, Ighodaro, Diabaté, Thomas Bryant, Gueye, Wade.
Shots per game correlates with position, so the gate deleted a position group
rather than low-impact players. Total attempts already establishes a real role.

That matters especially here: a center taking 4.5 shots a game that are nearly all
dunks has excellent shot selection, and those are among the most interesting cases
in the analysis. **Four of the five top scorers in 2025-26 are on that excluded list**
(Kalkbrenner, Hayes, Robert Williams III, Kornet). Keeping them was correct; they are the
headline result.

**Do not reintroduce a rate gate.** A minutes-per-game gate was also considered and
rejected: it trades a positional bias for a team-context bias, since a starter on a
tanking team plays more minutes than a sixth man on a contender, and it requires a
second endpoint for no analytical gain.

### Documented caveat

`games` counts games in which the player attempted at least one shot, not true
games played. A deep-bench player who appeared without shooting is undercounted.
This is a deliberate simplification, it affects only the 20-game gate in edge
cases, and it must be stated in the writeup. **Do not "fix" it by pulling a games
endpoint.**

---

## 6. Shrinkage: beta-binomial empirical Bayes, per zone

### The problem

Among the 318 qualifying players in 2025-26 there are **4,184** player-zone cells **with
at least one attempt**. Of those, **228** contain a single attempt and **629** contain
three or fewer. The fewest zones any qualifying player uses is **4**.

These are measured on the true qualifying pool after cleaning, replacing earlier
estimates of 4,200 / 227 / 630 that came from a 319-player pool filtered on attempts
without the 20-game gate.

Do not confuse this with the size of the `zone_stats` table. That table has 14 rows
per player including zero-attempt cells, so 318 x 14 = **4,452** rows. The 4,184 figure
counts only cells where the player actually shot.

A one-attempt cell produces a PPS of either 0 or 2 on a coin flip, which moves that
player's selection score by roughly 0.02, about a third of the league standard deviation
of 0.061. Without shrinkage the score partly measures luck.

The scale of the problem is established in the literature. Three-point percentage
takes roughly 750 attempts to stabilize (Blackport 2014); the largest zone here
averages about 200 attempts per player. Franks et al. (2016) showed that most
observed differences in 3PT% reflect sampling variability rather than ability, and
that hierarchical shrinkage produces estimates that are both more stable and more
discriminative than raw rates.

### The method

For each of the 14 zones independently, fit a beta-binomial to the `(makes,
attempts)` pairs across qualifying players, yielding `alpha[z]` and `beta[z]`.
Then:

    FG_pct_shrunk[p,z] = (makes[p,z] + alpha[z]) / (attempts[p,z] + alpha[z] + beta[z])
    PPS_shrunk[p,z]    = v[z] * FG_pct_shrunk[p,z]
    k[z]               = alpha[z] + beta[z]

Use `alpha[z]` and `beta[z]` directly rather than computing `k[z]` plus a
separately-derived league mean. The fitted prior mean may differ slightly from the
raw pooled FG% in that zone, and the fitted value is the correct one.

**At zero attempts this returns exactly the prior mean.** The zero-coverage case
therefore needs no special handling. Earlier designs considered dropping empty
zones and renormalizing the baseline; that was abandoned because shrinkage
dissolves the problem without a special branch.

### Fit on the qualifying pool only

The prior must describe the population being scored, not all 582 players. Easy to
get wrong.

### Per zone, and per season

Different zones have different between-player variance, so a single `k` would
over-shrink some and under-shrink others. This follows established practice: EPM
assigns a higher decay factor to 3PT% than 2PT% for exactly this reason. Fit per season
as well — both the qualifying pool and the league shooting environment change year to
year.

### Fitted values, 2025-26

| Zone | alpha | beta | k | prior mean |
|---|---|---|---|---|
| Restricted Area C | 55.7 | 27.9 | 83.6 | 0.667 |
| Paint L / C / R | 28.2 / 42.4 / 13.4 | 37.0 / 53.5 / 17.7 | 65.2 / 95.8 / 31.1 | 0.432 / 0.442 / 0.431 |
| Mid-Range L | 38.0 | 55.2 | 93.2 | 0.408 |
| Mid-Range LC | 59.1 | 90.3 | 149 | 0.396 |
| Mid-Range C | 33.9 | 45.7 | 79.6 | 0.426 |
| Mid-Range RC | 38.1 | 56.5 | 94.6 | 0.403 |
| Mid-Range R | 77.8 | 104 | 182 | 0.427 |
| Left Corner 3 | 50.8 | 79.7 | 131 | 0.389 |
| ATB3 LC | 83.3 | 153 | 237 | 0.352 |
| ATB3 C | 198 | 362 | 560 | 0.354 |
| ATB3 RC | 137 | 258 | 395 | 0.347 |
| Right Corner 3 | 44.4 | 70.3 | 115 | 0.387 |

Three-point zones shrink far harder than paint zones, which independently reproduces the
published stabilization findings.

### Implementation

Use `VGAM::vglm` with `betabinomial`, parameterised by mean `mu` and intra-cluster
correlation `rho`, where `k = (1 - rho)/rho`. `vglm` can fail to converge on thin zones.
**A method-of-moments fallback exists and emits a warning** so a convergence failure
surfaces rather than silently producing a bad `k`, per rule A9.

**Fallbacks actually used: 3 of 70 zone-seasons.** 2022-23 `In The Paint (Non-RA) | Left
Side(L)` and `Mid-Range | Left Side Center(LC)`; 2024-25 `Mid-Range | Right Side
Center(RC)`. 2025-26 needed none — 14 of 14 by MLE. The fallback path is deterministic: a
clean rebuild reproduces exactly the same three.

---

## 7. Selection score: shift-share decomposition

### The formula

    S[p] = SUM over z of ( f[p,z] - f_league[z] ) * PPS_shrunk[p,z]

where `f[p,z] = attempts[p,z] / total_attempts[p]`.

Equivalently: the difference between what the player actually generates per shot
and what they would generate with their own zone abilities but a league-typical
shot diet. Because `PPS_shrunk[p,z]` appears identically in both counterfactuals,
shooting skill differences out and only allocation remains.

Units are points per shot. A score of +0.06 means the player's shot choices are
worth six extra points per hundred attempts given their abilities.

This is a shift-share decomposition, the structure economists use to separate
composition effects from rate effects. Name that lineage in the writeup.

### Retain the per-zone terms

Each zone contributes independently. Store `(f[p,z] - f_league[z]) * PPS_shrunk[p,z]`
per cell. This is the mismatch story on player pages: "his corner-three overweight
is worth +0.03, his mid-range overweight costs 0.05." The per-cell terms sum exactly to
the player's score.

### The formula this replaced — do not revert

An earlier design used `SUM of f[p,z] * PPS[p,z]`. That collapses algebraically:

    f[p,z] * PPS[p,z] = (A[p,z]/A[p]) * (P[p,z]/A[p,z]) = P[p,z]/A[p]

Summed across zones it equals total points over total attempts, which is just
overall points per shot. It would have ranked players by scoring efficiency rather
than shot selection, answering the wrong question entirely. Measured on real data it
correlates **1.000** with raw overall PPS; the shift-share version correlates 0.577. **If
a formula appears to simplify to overall PPS, it is wrong.**

### Two baselines, both computed

    f_pooled[z]     = SUM over p of attempts[p,z] / SUM over p of total_attempts[p]
    f_unweighted[z] = mean over p of f[p,z]

**Pooled is primary.** It describes a real distribution, it is robust to changes in
the eligibility threshold, and it is standard. Unweighted is a mean of ratios
corresponding to no actual shot distribution, and it shifts whenever the threshold
changes, since marginal players shoot differently from the rest.

The honest counterargument, worth a sentence in the writeup: pooled is mildly
self-referential for high-volume players, who help define the baseline they are
measured against.

Both are computed. **Result: r = 0.9996 to 0.9998 across seasons**, reported as a
robustness result.

---

## 8. Concentration: Herfindahl index

    H[p] = SUM over z of f[p,z]^2

Ranges from about 0.071 (perfectly even across 14 zones) to 1.0 (pure specialist).

Concentration is **not the second axis of the primary chart.** Measured against the
selection score it correlates r = 0.833 in 2025-26, and 0.77 to 0.85 across seasons, so
the two are largely the same measurement and the scatter is close to a diagonal.

Worse for the framing, the redundancy **increases within position**, which is where the
comparison is supposed to be meaningful: r = 0.913 for centres, 0.798 for forwards, 0.667
for guards. An axis that becomes less informative exactly where it is needed does not earn
its place.

The four quadrants are not empty, but they are lopsided. On median splits the diagonal
holds 124 players per cell against 35 in each off-diagonal cell. The "efficient
generalist" was described as the rarest and most valuable case; it is one of those
35-player cells and is not a distinct population.

**Do not build score against concentration.** Section 8a has the replacement.

Herfindahl stays computed and stored per Section 15. That shot diet breadth and allocation
quality turn out to be nearly the same measurement is itself a result worth a sentence in
the writeup: players do not reach good allocation by being broadly good, they reach it by
concentrating on their best zone.

### Known confound, labeled rather than corrected

Concentration correlates with position. Centers shoot from few zones because their
role forbids the others; wings shoot from many. Shot-log data contains no signal
distinguishing a chosen specialty from an assigned one. A stretch shooter and a
rim-running center both show high concentration, but only one chose it.

**Do not correct this with positional baselines.** That was considered and rejected
as over-engineering, and it would require position labels reliable enough to build
a baseline on.

Instead: label any breadth axis "shot diet breadth" rather than "specialization," color
scatters by position so the pattern is visible rather than hidden, and note in the
writeup that within-position comparisons are the meaningful ones.

---

## 8a. The primary visual: score against shot volume

x is `total_attempts`, y is `score_pooled`, faceted into panels by `POS3`, with the
extremes labelled.

**The axes are independent enough to carry a scatter**, and unlike concentration the
relationship does not degrade within position: r = -0.386 overall, -0.485 for centres,
-0.477 for forwards, -0.350 for guards, stable at -0.37 to -0.39 across all five seasons.

**All four quadrants populate in every position group.** Median splits within position
give 7/15/15/7 for centres, 19/37/37/19 for forwards, and 31/48/48/32 for guards.

**It makes the volume confound visible.** Mean score falls monotonically as volume rises:
+0.046 at 250-400 attempts, +0.022 at 400-600, +0.011 at 600-900, -0.022 above 900. The
top 20 by score have a median of 364 attempts against a league median of 542; the bottom
20 have a median of 981. Eight of the top 20 sit within 100 shots of the 250-attempt gate.
See Section 17 for the two readings and why the data cannot separate them.

The quadrants carry meaning under this pairing. High score with high volume is the
genuinely valuable case; low score with high volume is the headline problem.

The within-position ranked dot plot — one axis, stacked panels — is the companion ranking
view for the Section 18 leaderboards, not the primary.

**Zone charts default to colouring by shrunk PPS, not by score contribution.** A colour
ramp laid over a court is read as efficiency regardless of what the legend says, so
contribution colouring makes a claim the visual grammar contradicts: a player's best zone
renders darkest red whenever he is underweight there. Curry's restricted area is the worked
example — his best zone at 1.38 PPS, rendered darkest red. Labels cannot repair that,
because colour is processed before the label is read. Contribution remains available as a
toggle for the player-page mismatch story, where surrounding text can frame it.

---

## 9. Position

Used **only as a display variable** for coloring charts. Never a modeling input.

### Source

`CommonTeamRoster`, one call per team, 30 calls total. Do not use
`CommonPlayerInfo`, which requires one call per player.

### Constraint discovered during design

The NBA does not publish five-position labels. `POSITION` returns single-letter codes and
hyphenated pairs: `C`, `C-F`, `F`, `F-C`, `F-G`, `G`, `G-F`. PG/SG/SF/PF/C exists on
Basketball Reference and ESPN, but neither is NBA-backed, and joining across sources on
player names introduces mismatch problems. The user requires an NBA-official source, so
three buckets is what is available.

An earlier version of this section claimed the API returns full words — "Guard",
"Forward", "Guard-Forward" — and warned that the abbreviations were input-only. That is
backwards. Verified across all five seasons and all 30 teams: the returned values are
always abbreviations, never full words.

### Handling

Store the raw `POSITION` value exactly as returned. Derive `POS3`:

1. Take the text before any hyphen. `G-F` becomes `G`.
2. That token is already the bucket: `C`, `F`, or `G`.
3. Flag anything unexpected with a warning. Never silently produce NA.

The primary position is the token before the hyphen, so the split is doing the real
work and no mapping table is needed.

### Missing positions: an explicit Unknown bucket

`CommonTeamRoster` returns each team's roster as of the **end of the season**, not every
player who appeared for it. Verified across all five seasons: the roster row count equals
the distinct player count exactly, so no player is ever listed twice and **no
traded-player deduplication is needed.**

The cost is coverage — 530 rostered players for 2025-26 against 582 who took a shot,
leaving three of the 318 qualifying players with no `POSITION`: **Cam Thomas** (460
attempts), **Vince Williams Jr.** (292), and **Jaden Ivey** (256).

**`POS3` becomes `Unknown` for these, as a fourth displayed category.** Position is a
display variable only, so an honest fourth bucket costs nothing and keeps those players
visible on the primary chart rather than dropping them from it. Dropping them would
silently shrink the pool; imputing a position would invent data.

`Unknown` applies only to a player absent from the roster join. A `POSITION` that is
present but unrecognised is a different failure and must still warn loudly. Do not
collapse the two cases.

Storing the raw value costs nothing and allows revisiting the binning without
re-fetching.

---

## 10. Seasons

**2021-22 through 2025-26. Five seasons. All five are collected.**

Three constraints converge on this range.

**Season length.** 2019-20 ended in the bubble with a reduced field; 2020-21 ran 72
games. A fixed 250-shot threshold means something different in those years, so the
qualifying pool would be a different population and cross-season comparison would
quietly compare different groups. 2021-22 forward is all 82-game seasons.

**Rule environment.** The NBA changed foul-drawing enforcement in 2021-22, cracking
down on unnatural shooting motions. That directly affected shot selection
incentives at the rim, which is what this metric measures.

**Statistical need.** Five seasons gives four consecutive year-over-year pairs,
enough to see whether the metric's stability holds rather than reading a single
correlation with no context. **That check is now runnable and has not been run.** See
Section 16.

Roughly 1.09 million shots total. Trivial for Parquet and DuckDB.

---

## 11. Stack

### Ingestion: Python, and why

**Tested and settled. Do not revisit without new evidence.**

`hoopR` was evaluated as a way to eliminate Python. It failed four ways: its own
documented example returned an empty list, `nba_commonteamroster` failed
identically, a different season failed, and injecting browser headers via
`httr::add_headers` did not help. Raw curl to the same endpoints returned HTTP 000
on two independent networks. Minutes later, `nba_api` pulled 1,445 rows for the
same player and season from the same machine. The API was fine; `hoopR` could not
reach it. The mechanism is unknown and was not investigated because the decision
was already clear.

**Python does ingestion only.** `nba_api`, proven against this endpoint. Nothing
else in the project is Python.

Environment: conda, named `nba-analytics`, Python 3.11. Activate with
`conda activate nba-analytics` before running anything in `src/`. Required
packages are `nba_api`, `pandas`, and `pyarrow`. The last is what lets pandas
write Parquet; without it the ingestion script fails at the write step.

There is no `requirements.txt` and none is needed for three packages.

### Everything else: R

Cleaning, analysis, shrinkage, scoring, charts, export.

| Package | Role |
|---|---|
| `tidyverse` | dplyr, tidyr, ggplot2, purrr, readr |
| `arrow` | Parquet read and write |
| `duckdb` + `DBI` | SQL over the Parquet store |
| `VGAM` | Beta-binomial MLE |
| `jsonlite` | JSON export for Astro |
| `svglite` | SVG export from ggplot |
| `ggrepel` | Non-overlapping point labels on the scatter charts |
| `glue` | String interpolation for seasons and paths |

### Storage

Parquet, Hive-partitioned by season. The 2025-26 shot log went from 46 MB as CSV to
2.1 MB as Parquet, a 22x reduction from dictionary encoding of repeated strings.

DuckDB queries Parquet **in place**. There is no database file, no import step,
nothing to keep in sync. `SELECT ... FROM 'data/raw/shots/**/*.parquet'` reads all
seasons and derives the `season` column from the directory name.

**Caution with globs across `data/processed/`.** DuckDB unions schemas across a glob, so
reading every season at once breaks mid-pipeline when some seasons are stage-2 shaped and
others are stage-3 enriched. Read one season's file directly where the stage operates on
one season.

### The Python-to-R handoff

Ingestion writes **Parquet, never CSV**. Parquet stores types in the file, so
nothing is guessed on either side.

`GAME_ID` is the one field that could break silently: it is a string with leading
zeros like `"0022500038"`, and if either side reads it as a number those zeros are
gone permanently and `COUNT(DISTINCT GAME_ID)` changes without an error. Verified
working: R reads it back as character with zeros intact. Keep it character end to end.

The original 2025-26 CSV had a `NAME` column duplicating `PLAYER_NAME`, added by the old
pipeline. That file has been superseded — `src/collect.py` re-collected 2025-26 with the
native 24-column schema and reproduced 219,160 rows exactly.

---

## 12. Deliberately out of scope

Each of these was considered and rejected. Do not build them.

- **Hex-bin charts.** An arbitrary hexagon grid ignores the 14 zone boundaries the
  entire pipeline uses, so the chart would visually disagree with the published
  numbers. The previous version built one and it was removed.
- **A second zone definition of any kind.** Retired as an out-of-scope entry on
  2026-08-27, when A4 changed: the project now computes its own zones. What stays banned
  is a *duplicate* — a boundary restated in SQL, a chart, or the export, or a classifier
  living anywhere but `R/zone_model.R`. `court_layer()` in `R/04_charts.R` draws a hoop,
  paint, free-throw arc and three-point line as chart furniture and assigns no shot to
  anything.
- **eFG%, true shooting, or any efficiency metric other than PPS.**
- **Defender proximity / `CLOSE_DEF_DIST`.** Not available per-shot through the
  public NBA Stats API. Confirmed by testing `ShotChartDetail` across all
  `context_measure_simple` values; the 24-column schema contains location and
  outcome only. `PlayerDashPtShots` offers bucketed player-level aggregates that
  cannot be joined to individual shot rows. This avenue is closed.
- **Bootstrap confidence intervals on the score.** Rejected as over-engineering.
  Instead round scores to two decimals and present extremes as tiers rather than
  ranking all 318 players 1 through 318.
- **Garbage-time filtering.** Requires score margin, which is not in the shot log.
  No demonstrated effect.
- **Positional baselines for the score.** Position is a display variable only.
- **Minutes-per-game or shots-per-game eligibility gates.**
- **Zone-level minimum attempt filters.**
- **`hoopR`.** Tested, failed, documented above.
- **Conditional autoregressive spatial priors.** A genuinely better model (Franks
  and Cervone used a CAR prior to capture similarity in shooting ability across
  nearby court locations) and a reasonable v2. Not now: it requires MCMC via Stan
  or brms and fits take minutes rather than seconds. Note that adjacency was later
  tested directly and carries no information here: Left Corner 3 correlates 0.295 with
  Right Corner 3 and 0.262 with its own physical neighbour.

---

## 13. Folder structure

```
nba-shot-analytics/
├── R/                          # All analysis scripts, numbered by pipeline order
├── src/                        # Python ingestion only — collect.py
├── data/
│   ├── raw/shots/season=YYYY-YY/shots.parquet
│   ├── raw/roster/season=YYYY-YY/roster.parquet
│   ├── processed/              # The three output tables, partitioned by season
│   └── cache/                  # Per-team API response cache
├── export/
│   ├── data/                   # JSON for the Astro site
│   ├── charts/                 # SVG assets
│   └── SCHEMA.md               # Field-by-field description of the JSON export
├── CLAUDE.md                   # This file. COMMITTED.
├── ASSUMPTIONS.md              # Decision log. Gitignored, local only.
├── README.md                   # The public writeup
└── nba-shot-analytics.Rproj
```

`.gitignore` contains `/site` from a Python template, which is why the export
directory is `export/` and not `site/`.

### What is committed and what is not, as of 2026-08-26

**Gitignored:** `data/raw/`, `data/cache/`, `export/data/`, `ASSUMPTIONS.md`.

**Committed:** `R/`, `src/`, `data/processed/`, `export/charts/`, `export/SCHEMA.md`,
`README.md`, and **this file**.

`export/charts/` is committed because the SVGs are small, change only when a chart design
changes rather than on every run, and are what a repository visitor actually wants to see.
`export/data/` is excluded because it is roughly 3 MB rewritten in full on every run.

**Raw NBA data is never committed.** `data/raw/` and `data/cache/` stay gitignored
permanently. This is a redistribution boundary, not a file-size decision: the shot log is
pulled from the NBA Stats API, and republishing it is not this project's call to make.
Derived aggregates are a different thing. The practical line: if a file contains one row
per shot, it does not leave this machine. If it contains one row per player-zone or per
player, it can.

### `data/processed/` is committed, deliberately

The three output tables are tracked in git. This is a decision, not an oversight, and it
was reaffirmed on 2026-08-26 after `.gitignore` was found to contradict it.

**The reason is reproducibility.** All five seasons together are about 1 MB as Parquet.
Committing them means anyone who clones the repository can rebuild every chart, rerun
every validation check, and verify every number in the writeup **without an API collection
run**. That is a stated portfolio goal: the analysis should be inspectable by someone who
does not have NBA Stats API access and does not want to spend hours collecting.

**It does not breach A16.** The finest grain in these tables is the player-zone cell —
`zone_stats` is 4,452 rows for 2025-26, `player_scores` 318, `zone_priors` 14. There are no
shot-level rows and no `GAME_ID`, `LOC_X`, `LOC_Y`, or `ACTION_TYPE` columns. These are the
output of analysis, not a copy of the source feed. The redistribution boundary A16 draws is
between shot-level data and derived aggregates, and these fall on the permitted side of it.

**The consequence for A15.** Because the directory is committed, anything written there
inflates the repository permanently. Keep it to the three small tables. A stage needing a
large intermediate writes to `data/cache/` instead.

---

## 14. Pipeline

Scripts in `R/`, numbered, each runnable top to bottom. The whole pipeline rebuilds
with one command.

**No notebooks in the pipeline.** The previous version put the pipeline in
notebooks, which meant every change required manually re-running six notebooks in
the right order. That is the structural failure this fixes.

**Every function takes `season` as an argument.** Nothing hardcodes "2025-26".
The canonical season string format is `"2025-26"`, matching what the NBA API expects and
what the Hive partition directories use.

**`R/run_pipeline.R`** takes a season or a vector of seasons and sources the numbered
stages in order. Ingestion stays separate since it is Python and slow; the master script
covers stages 2 through 5. A full clean rebuild of all five seasons takes about six
seconds.

Stages:

1. Ingest shots and rosters (Python, writes partitioned Parquet)
2. Clean, filter to qualifying players, build the 14-row-per-player zone grid
3. Fit priors, compute shrunk PPS, baselines, scores, concentration
4. Charts
5. Export JSON

**Isolate shrinkage in a single function** taking `(makes, attempts, zone)` and
returning shrunk estimates. Everything downstream consumes the output without
knowing how it was produced. This makes a future CAR upgrade a one-function swap.

### Season discovery must follow data flow, not output

A stage decides what to process by listing the directory it **consumes**, never one it
**produces**. Listing `data/processed/zone_stats/` to decide which seasons to run was
circular — on a clean checkout the list is empty and the pipeline fails its own
precondition, so it would only run if it had already run. Current arrangement:

    available_seasons()   -> data/raw/shots              # what the pipeline can process
    exportable_seasons()  -> data/processed/zone_stats   # what stage 5 can export

The second is correct rather than circular: that directory is stage 5's input.

### Collection: by team, not by player

`ShotChartDetail` with `player_id=0` and a real `team_id` returns that team's entire
season, so collection is **30 calls per season, not roughly 550** — about three minutes
instead of several hours. The checkpoint unit is therefore `(season, team)`.

Verified exact against the independently collected 2025-26 file: Golden State 7,280 rows,
Boston 7,398, LA Lakers 6,863, all matching row for row. Curry's 799 rows inside the
Golden State pull equal his 799 from an individual player call. Team pulls also include
players who passed through mid-season, so nobody is missed.

**Never pass `team_id=0`.** It looks like a one-call whole-season pull and returns exactly
102,400 rows — 100 x 1024 — with the dates stopping in late January of an April season. It
is a silent row cap that serves a plausible half-season with no error. `src/collect.py`
raises if any pull returns exactly that number.

### Ingestion specifics

Three retry attempts per request, randomized delays of 3 to 5 seconds between requests,
and per-team checkpoint caching to `data/cache/` so an interrupted run resumes without
re-fetching.

**API availability.** During design testing, raw curl to `stats.nba.com` endpoints
returned HTTP 000 (connection established, zero bytes received) on two independent
networks, while `nba_api` succeeded from the same machine minutes later. The API appears
to refuse requests from some clients and not others, intermittently. If a collection run
starts failing, retry later before concluding anything is broken, and test with `nba_api`
specifically rather than curl.

---

## 15. Output tables

All in `data/processed/`, partitioned by season.

**`zone_stats`** — one row per player-zone, 14 rows per player including zeros:
`PLAYER_ID`, `PLAYER_NAME`, `zone`, `zone_value`, `makes`, `attempts`, `fg_pct`,
`pps_raw`, `shot_freq`, `fg_pct_shrunk`, `pps_shrunk`, `freq_pooled`, `freq_unweighted`,
`score_contrib`.

**`player_scores`** — one row per player: `PLAYER_ID`, `PLAYER_NAME`, `total_attempts`,
`games`, `zones_used`, `pps_overall_raw`, `score_pooled`, `score_unweighted`,
`herfindahl`, `POSITION`, `POS3`.

**`zone_priors`** — one row per zone: `zone`, `zone_value`, `alpha`, `beta`, `k`,
`prior_mean`, `league_attempts`, `converged`, `method`. `method` records `vglm` or
`moments` so a fallback is visible downstream, not just at runtime.

Note `league_attempts` counts **qualifying-pool** attempts, not all players. For 2025-26
restricted area that is 54,217, against 62,253 league-wide. The name is misleading and is
documented as such in `export/SCHEMA.md`.

### Zero-attempt cells carry NA, not zero

`fg_pct` and `pps_raw` are `NA` where `attempts = 0`, not `0`. A player who never shot
from a zone has no observed rate, and a zero would be a measurement claim rather than an
absence. Stage 3's shrinkage returns exactly the prior mean at zero attempts, so
`fg_pct_shrunk` and `pps_shrunk` are always populated. `makes`, `attempts`, and
`shot_freq` are genuinely zero and are stored as zero.

### `season` is a directory, not a column

Both processed tables and the raw tables are written **without** a `season` column,
matching `data/raw/shots/season=YYYY-YY/shots.parquet`. Reading with
`hive_partitioning = 1` restores it. Writing it in both places would produce a duplicate
column on read.

---

## 16. Validation

Run once as a separate script (`R/validation.R`, `R/k_comparison.R`), not part of the
recurring pipeline. Report in the writeup.

### Score checks

1. Correlate pooled score against unweighted score. Expect r > 0.95.
   **Result: 0.9996 to 0.9998 across five seasons.** Passes.
2. Correlate score against raw overall PPS. Expect **weak** correlation. A strong
   one means the metric has collapsed back into an efficiency measure.
   **Result: 0.476 to 0.662 (0.577 in 2025-26). Moderate, not weak.** It is *not* the
   rejected formula — that gives exactly 1.000 on the same players. The driver is rim
   concentration raising both quantities, since the restricted area is simultaneously the
   highest-PPS zone and the one most overweighted relative to the league. Whether 0.58
   satisfies "weak" is an open judgment call; if not, the answer is within-position
   comparison, not a formula change.
3. Correlate score against `zones_used`. **Do not assume a direction** — during design
   this was argued both ways and the reasoning was wrong at least once.
   **Result: negative, r = -0.635 to -0.724.** Players using all 14 zones average -0.007;
   the player using 4 scores +0.251. Confounded with concentration rather than independent
   of it.
4. Check whether centers cluster at one end of the score distribution.
   **Result: yes, but position explains only R2 = 0.178 (0.156-0.204 across seasons),**
   F(2,312) = 33.7, p < 1e-13. **82% of the variance is within position.** See Section 8a
   and the finding below.
5. **Removed as invalid.** An earlier version correlated score against restricted-area
   frequency as an indirect proxy for the free-throw bias. Overweighting the restricted
   area is close to the single largest positive term in the score by construction, so a
   high correlation is what the formula guarantees rather than evidence about free throws.
   Measured at r = 0.86 in 2025-26 and 0.78 to 0.86 across seasons, indistinguishable from
   that structural floor. The free-throw limitation is documented in Section 17 and is
   **not testable from shot-log data alone.**

### The central finding: within-position discrimination

Centres have SD **0.0848**, which is **139% of the league-wide SD of 0.061**, spanning
-0.053 to +0.286.

| POS3 | n | mean | SD | range |
|---|---|---|---|---|
| C | 44 | +0.0754 | 0.0848 | -0.053 to +0.286 |
| F | 112 | +0.0256 | 0.0584 | -0.118 to +0.183 |
| G | 159 | -0.0010 | 0.0418 | -0.117 to +0.145 |
| Unknown | 3 | -0.0235 | 0.0334 | -0.062 to -0.002 |

The within-position extremes are basketball-interpretable, which is the strongest evidence
the metric measures allocation rather than role. Centres run Kalkbrenner, Gobert, Hayes at
the top against Vučević, Adebayo, Embiid at the bottom. Forwards run Gafford,
Antetokounmpo, Diabaté against Dončić, Murray, Durant. Guards run Payton II, Champagnie,
Braun against Nembhard, McConnell, DeRozan.

**The metric works. The positional clustering is a display problem**, and Section 8 already
prescribes the remedy. No metric change.

### Shrinkage checks, once only — done

Fit `k[z]` three ways and report a per-zone comparison table: beta-binomial MLE (production
method), split-half reliability, and cross-validation.

**Result: they diverge.** Median k is 105 (MLE), 157 (split-half), 140 (CV).

    cor(k_cv,    k_mle)   = 0.896   rank 0.838
    cor(k_split, k_mle)   = -0.081  rank 0.327
    cor(k_cv,    k_split) = -0.139  rank 0.246

MLE and cross-validation agree closely and rank the zones almost identically. Split-half
agrees with neither on levels. All three disagree most in the three-point zones, **which
are not the thinnest zones** — a prediction that they would be was tested and failed.

**The cross-validated loss surface there is flat, not merely unbounded.** Extending the
grid to 20,000 removed every boundary hit, so a nominal minimum exists, but held-out loss
stays within 0.01% of it across 450-20,000 for `ATB3 | Center(C)` and 500-20,000 for the
right-side-centre equivalent. Two orders of magnitude. `k` is not identified there, and the
MLE's values sit inside every such interval, so cross-validation does not contradict the
MLE — it cannot discriminate.

**No favourite is picked.** Production stays the beta-binomial MLE, which Section 6
specifies and which cross-validation independently corroborates.

### Score sensitivity to the shrinkage weight

Rebuilding every player's score under each of the three k vectors, holding the fitted prior
mean fixed so only k varies:

Rank correlations 0.995 to 0.9985, Pearson 0.9976 to 0.9994. **No player moves more than
one league SD (0.061); the largest shift under any pairing is 0.015**, a quarter of an SD.
Between 20 and 52 players move more than 10 rank places, all mid-distribution. **The top
five and bottom five are identical under all three weightings.**

A score sums across 14 zones, and each zone's term is weighted by `(f - f_league)`, which
is small wherever k is uncertain. Cell-level sensitivity does not propagate to the player
score. **The headline findings are robust to the shrinkage disagreement.**

### Year-over-year stability — runnable, not yet run

Whether a player's selection score predicts his next-season score. This was previously
blocked on having only one season. **All five seasons are now collected, giving four
consecutive adjacent pairs, and the check has not been run.**

For each adjacent pair, correlate each player's pooled score in season N against N+1,
restricted to players qualifying in both, and report the correlation and n **for all four
pairs together** so the pattern is visible rather than reduced to one number. **Also report
it within `POS3`**, because a strong overall correlation could be position persisting
rather than the metric measuring a player trait — if guards correlate weakly and the
overall number is carried by centres staying centres, that is a different finding and needs
saying. Report plainly, including if it is weak.

This is the check that determines whether the metric measures a stable trait or
circumstance.

---

## 17. Known limitations, documented not fixed

**Free throws.** PPS counts field goal attempts only. A drive that draws a shooting
foul often records no FGA at all, so restricted-area PPS understates the value of
attacking the rim and the metric may penalize foul-drawing players. This is why
True Shooting exists. **It is not testable from shot-log data**, which carries no
free-throw records. Validation check 5 was designed for this and has been withdrawn as
invalid, since restricted-area frequency is mechanically tied to the score. Document the
limitation in the writeup and **do not add a free-throw endpoint.** The "rim pressure"
column that earlier versions made conditional on that check is not warranted by any
evidence currently available.

**Shot volume.** The selection score falls monotonically as volume rises: +0.046 at
250-400 attempts, +0.022 at 400-600, +0.011 at 600-900, -0.022 above 900. Overall
r = -0.386, stable across all five seasons, and it holds within position.

**Eight of the top 20 scorers sit within 100 shots of the 250-attempt gate**, with a median
of 364 attempts against a league median of 542. The bottom 20 have a median of 981. That
bears directly on whether the eligibility threshold is doing more work than intended.

Two readings, and the shot log cannot separate them. Either high-usage players genuinely
face harder shots by necessity — creating late in the clock, from everywhere, against a set
defence, while a role player shoots only when open at the rim — in which case the gradient
is a real basketball effect the score is measuring correctly. Or the score is partly
measuring offensive usage rather than allocation quality. Both mechanisms predict the same
correlation. Distinguishing them needs usage rates, shot-clock state, or defender distance,
none of which the shot log carries.

**Partial evidence.** Correlating score against volume *within* each volume quartile, as
slope per 1000 attempts:

| Season | pooled | Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|---|---|
| 2021-22 | -0.080 | +0.329 | -0.068 | -0.198 | -0.047 |
| 2022-23 | -0.076 | -0.090 | +0.005 | -0.100 | -0.028 |
| 2023-24 | -0.067 | +0.146 | +0.145 | -0.041 | -0.026 |
| 2024-25 | -0.065 | +0.189 | -0.040 | +0.019 | -0.049 |
| 2025-26 | -0.081 | -0.150 | -0.141 | -0.117 | -0.115 |

Q4 is negative in all five seasons; the lower three flip sign. The effect is a **level
difference between volume bands rather than a smooth gradient through them**, and it sits
among high-volume players — the opposite end of the distribution from the 250-attempt gate,
which weakens the threshold-artifact reading specifically.

**Do not correct for volume.** Section 8a puts it on the x-axis so the pattern is visible,
the same treatment Section 8 gives the position confound.

**Concentration is nearly redundant with the score.** r = 0.833, worsening within position.
See Section 8.

**Shrinkage weight is not sharply identified in the three-point zones**, though the
rankings are. See Section 16.

**Endogeneity of PPS and frequency.** The formula treats zone PPS as a fixed skill
parameter, but ability and frequency are not independent. Research using marked
spatial point processes found a significant positive association between shot
accuracy and shot intensity for about 80% of players studied — players shoot better
where they shoot more, which may be selection rather than causation. Note this as
an assumption. During design the opposite was asserted (that defenses would depress
a specialist's efficiency) and the literature contradicted it.

**Games played.** As described in Section 5.

**Position granularity.** Three buckets, not five, because the NBA does not publish
five. Plus an `Unknown` bucket for three players absent from end-of-season rosters.

**Pooled baseline self-reference.** High-volume players partly define the baseline
they are measured against.

---

## 18. Website output

The Astro site is maintained separately by the user. This project writes JSON and
SVG into `export/`. **Do not write Astro components or discuss site construction.**

Three views, all served by one export:

1. A narrative section: five best and five worst shot selectors, chosen at build
   time from the full export.
2. A player picker with search, covering all qualifying players.
3. Separate leaderboards for zone PPS, zone FGA, and selection score, shown
   distinctly so a user can see they rank differently.

Because the picker needs every player, the narrative is a curated subset of the
same file. One export, three uses.

The JSON carries **season as a top-level dimension**: one `meta.json` plus one
`season-YYYY-YY.json` per season, so a visitor loading one season does not download the
others. `export/SCHEMA.md` documents every field, its type, its units, and what a missing
value means. Keep that file current when the export changes.

**Zones are keyed by stable string id** (`restricted_area`, `arc3_center`, and so on),
never by positional index. The site keys its SVG paths off these, and a positional index
would silently point at a different zone if the model changed. `meta.zones` carries the id,
the full NBA name for display, and the point value.

**`meta.json` also carries a player search index** keyed by player id, so the picker can
search all 538 players without downloading a season file. Names are display text only —
two players change spelling across seasons — and every join goes on the id.

**`R/06_sync_to_site.R` copies the export to the website repository.** The destination
comes from `SHOT_SELECTION_SITE_DIR`, defaulting to the author's local path. It refuses to
create a missing destination, because a typo would otherwise produce a folder nothing
serves. It only copies; committing on the site side is manual.

**Zone geometry now originates here**, in `R/zone_model.R`, and the site consumes it
rather than authoring its own. This reverses what this section said before 2026-08-27,
when zones came from the NBA's labels and A4 forbade deriving them.

What this project does provide is verification. `R/07_zone_geometry.R` writes
`export/reference/zone_grid.csv`, a half-foot spatial histogram of every labelled shot
across five seasons, which the outlines can be traced from, and checks a candidate set of
polygons against every labelled shot, reporting label disagreements, orphans and overlaps
separately with the coordinates of each defect. A binned grid rather than a point cloud
because A16 forbids shot-level data leaving the machine; see ASSUMPTIONS entry 26.
`export/reference/` is a development aid and is not fetched at runtime.

---

## 19. Working conventions

**File editing.** Edit files in `R/` and `src/` directly. Ask before creating new
top-level directories.

**The `.qmd` scratchpad is different.** No `.qmd` file exists yet; create one only
if the user asks. When it exists, do not edit it directly. Give the user labeled
blocks to paste.

**No bullet points in terminal responses.** They do not paste cleanly. Write in
flowing prose.

**Keep responses under the output limit.** A previous session hit the 32,000-token
ceiling mid-response and lost the work. If a task will produce more than roughly
200 lines of code, split it and say so up front. Never attempt an entire pipeline
stage in one response.

**State assumptions out loud.** If a spec is ambiguous, say so and propose an
interpretation rather than picking one silently.

**Reasoning over compliance.** If something in this document appears wrong, or the
data contradicts it, say so. Several conclusions here were reached by correcting
earlier mistakes. It can be wrong again.

---

## 20. Code style

### Skill level

The user has working R competence and is not a beginner. **Do not constrain
yourself to any assumed vocabulary.** Use whatever produces the best result,
including `purrr`, `across()`, `nest()`, or anything else idiomatic. Do not write
tutorial-register code or explain basic R.

### Naming

NBA-delivered columns keep their original names exactly: `PLAYER_NAME`, `LOC_X`,
`SHOT_ZONE_BASIC`, `GAME_ID`. Do not rename them. Every derived column uses
`snake_case`: `zone`, `pps_shrunk`, `shot_freq`, `score_pooled`. The case
difference signals where a column came from.

Functions are verbs in `snake_case`. Scripts in `R/` are numbered by pipeline
order.

**`zone` is a reserved word in DuckDB's parser** and fails as a bare column alias. Quote
it as `"zone"` in SQL. The column name itself is unchanged.

### Comments

Comment the reasoning, not the mechanics. Clear R does not need narration.

Write comments explaining why a threshold is 250 and not 300, why a fallback
exists, what units a column is in, a non-obvious data quirk, or why an obvious
simpler approach was rejected. Those save real time.

Never write comments that restate the line below them, announce what a well-named
function does, or narrate structure the code already makes obvious. Examples never
to write:

    # Loop over each player
    # Group by zone and summarise
    # Read the parquet file
    # Now we compute the score

**No decorative section banners** built from box-drawing characters or long dash
runs. A plain `# Fit the priors` suffices when a header is needed at all.

Prefer a good name over a comment. If a comment explains what a variable holds,
rename the variable.

### Code

Use dplyr and pipes for manipulation. Use DuckDB SQL where the work is a genuine
aggregation over the Parquet store, dplyr where it is reshaping something already
in memory. Do not mix both in one step without reason.

Avoid clever one-liners compressing three ideas. Three readable lines beat one
dense one.

**Fail loudly.** If a join drops rows, an MLE fails to converge, or a value is
unexpected, warn or stop. Never silently coerce, drop, or produce NA. The previous
version lost hours to failures that produced plausible-looking output.

---

## 21. Starting a fresh session

Sessions have been lost twice in this project, once to a terminal closing and once
to an editor update. Assume no memory of prior conversations.

Read this file. Run `git status` and `git log --oneline -5`. Look at what exists in
`R/`, `src/`, and `data/processed/`. Then state your understanding of where the
project stands and ask the user to confirm before writing anything.

Do not read the dead files listed in rule A2 even when reconstructing state.
Their presence in git history is not a reason to consult them.

### Git

**Active branch is `main`.** `pps-rebuild` was squash-merged into it and is now
historical; both still exist locally and on the remote. All work goes on `main`.

Two standing rules earned the hard way:

**Query the remote before describing it.** A claim that this file was "tracked and pushed
to origin" was half-verified — tracked was checked with `git ls-files`, pushed was inferred
from `git status` reporting the branch up to date. That is inference stated as fact, which
rule A8 forbids. Run `git ls-tree -r origin/<branch> --name-only` before making any claim
about the remote.

**Verify a build criterion from the state it claims to build from.** "The pipeline runs end
to end from one command" was once reported as satisfied after running it against a working
tree that already held five seasons of output. That tests re-running, not building. A test
run against existing output is a regression test, not a reproducibility test, and the two
must not be reported interchangeably. To verify: `rm -rf data/processed export/data
export/charts`, then a bare `Rscript R/run_pipeline.R`.

---

## 22. Definition of done

The project is complete when:

- [x] The pipeline runs end to end from one command for a given season — verified from a
      genuinely clean state, all five seasons in about six seconds
- [x] `zone_stats`, `player_scores`, and `zone_priors` exist for all five seasons
- [x] All score validation checks have been run and reported — four run, check 5 withdrawn
      as invalid with the reason recorded in Section 16
- [x] The three-method `k` comparison table exists, plus the score-sensitivity analysis
- [x] The primary chart renders, colored by position — **score against shot volume per
      Section 8a**, which replaced the four-quadrant chart the original criterion named
- [x] Zone charts match the NBA's classification
- [x] The JSON export loads and covers every qualifying player, and `export/SCHEMA.md`
      documents it
- [x] Known limitations are written up — Section 17 and `README.md`
- [ ] **Year-over-year stability check** — now runnable on four adjacent pairs, not yet run

Beyond that, stop. Do not propose enhancements unless the user asks.

---

## 23. What the project produces

One interpretable metric, in points per shot, saying whether a player's shot
allocation adds or subtracts value relative to a league-typical diet given their
own demonstrated abilities. Alongside it: a breadth measure, per-zone contribution
breakdowns showing which zones drive each score, and zone charts matching the NBA's
official classification.

The intended finding is named players at both extremes. **The primary visual is score
against shot volume, faceted by position**, because within-position comparison is where
the metric discriminates and because volume is the confound most worth making visible.

---

# RULES, REPEATED

You have read a long document. These are the parts that matter most.

Commit to `main`, not `pps-rebuild`. Never read the dead files. Never use eFG%. Never
place a zone boundary outside `R/zone_model.R`. Never filter zones by attempt count.
Never add an eligibility gate. Never edit `.qmd` directly. Never assume. Never fail
silently. Never write a large file to `data/processed/`. Never commit raw NBA data in any
form. Never build anything in Section 12.

Always verify before proceeding. Always split long responses. Always write
Parquet. Always pass `season` as an argument.

Before adding complexity, name the problem it solves. Before stating a fact,
verify it. When the data contradicts this document, say so.

At the end of each session: what you changed, what you assumed, what you were
unsure about.
