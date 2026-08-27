# Assumptions and corrections

Local only, gitignored. Every entry records something the data contradicted, something
chosen where the brief was silent, or something asserted without verification.

---

## 1. Twenty shots dropped for point-value clash

**Date:** 2026-08-23 · **Stage:** 2 · **Amended in CLAUDE.md:** Sections 3, 4, 6

Section 3 asserted that every zone contains shots of exactly one point value. It does
not. Twenty shots in 2025-26 carry a `SHOT_TYPE` contradicting their zone's nominal
value: twelve labelled `Above the Break 3` scored as 2PT field goals, eight labelled
`Mid-Range` scored as 3PT. All twenty sit between 21 and 24 feet and all are jump
shots, so they are boundary cases where the NBA's coordinate-derived zone label and its
scored point value disagree.

**Decision: drop them.** Point-homogeneity is load-bearing for the Section 6 shrinkage
design, which shrinks a binomial proportion and multiplies by `v[z]`. Keeping the rows
would either break the `PPS = v[z] * FG_pct` identity (valuing by `SHOT_TYPE`) or
knowingly misvalue up to twenty shots (valuing by zone). Twenty rows out of 219,160 is
0.009 percent, and no player's score moves measurably.

Filter chain: 219,160 raw, minus 38 backcourt = 219,122, minus 20 clashes = **219,102**.

Consequence: the counts in Section 4 were computed from `SHOT_ZONE_BASIC ||
SHOT_ZONE_AREA` alone and so absorbed the clashes. Six of the fourteen rows changed.
CLAUDE.md now carries the post-drop numbers.

---

## 2. Section 6 thin-cell figures were computed on the wrong pool

**Date:** 2026-08-23 · **Stage:** 2 · **Amended in CLAUDE.md:** Section 6

Section 6 flagged its own figures as coming from a 319-player pool filtered on attempts
without the 20-game gate, and asked for recomputation on the true qualifying pool. Done,
after the clash drop: **4,184** cells with at least one attempt, **228** single-attempt
cells, **629** cells at three or fewer, grid **4,452** rows. Minimum zones used by any
qualifying player is **4**. The single-attempt count moved 227 to 228 and the
three-or-fewer count 630 to 629, because the pools differ in both directions.

---

## 3. Claimed CLAUDE.md was pushed to origin without checking the remote

**Date:** 2026-08-23 · **Stage:** planning · **Rule:** A8, never state inference as fact

The planning output said CLAUDE.md "is tracked and has been pushed to
`origin/pps-rebuild`." Tracked was verified by `git ls-files`, which listed it at that
moment. Pushed was **not** verified — no `git ls-tree origin/...` was run, and the claim
was reasoned from `git status` reporting the branch up to date. That is inference stated
as fact.

The user then committed `c3d1786 Untrack CLAUDE.md`, so the file is now untracked and
absent from the current tip of `origin/pps-rebuild`. It does remain in that branch's
history in commits `7e6ba33`, `50f9e7e`, `ca2650c`, and `3ba9c1f`, which is a separate
matter from whether it is tracked now.

**Standing correction:** query the remote before making any claim about it.

---

## 4. Zero-attempt cells carry NA rather than zero

**Date:** 2026-08-23 · **Stage:** 2 · **Brief was silent**

`fg_pct` and `pps_raw` are `NA` where `attempts = 0`, not `0`. A player who never shot
from a zone has no observed rate, and a zero would be a measurement claim rather than an
absence. Section 6's shrinkage returns exactly the prior mean at zero attempts, so
stage 3 fills these without a special branch. `makes`, `attempts`, and `shot_freq` are
genuinely zero and are stored as zero.

---

## 5. season is a directory, not a column

**Date:** 2026-08-23 · **Stage:** 2 · **Brief was silent**

Both processed tables are written without a `season` column, matching
`data/raw/shots/season=YYYY-YY/shots.parquet`. Reading with `hive_partitioning = 1`
restores it. Writing it in both places would produce a duplicate column on read.

---

## 6. DuckDB reserves `zone`

**Date:** 2026-08-23 · **Stage:** 2 · **Mechanical**

`zone` is a reserved word in DuckDB's parser and fails as a bare column alias. It is
quoted as `"zone"` throughout the SQL. The column name itself is unchanged, per
Section 15.

---

## 7. CommonTeamRoster returns abbreviations, not full words

**Date:** 2026-08-23 · **Stage:** 1 · **Amended in CLAUDE.md:** Section 9

Section 9 stated the API returns "Guard", "Forward", "Guard-Forward" and warned that
abbreviations were input-only. Backwards. Verified across all five seasons and all 30
teams: the vocabulary is exactly `C`, `C-F`, `F`, `F-C`, `F-G`, `G`, `G-F`, identical in
every season, never a full word.

The `POS3` rule is unchanged but simpler: split on the hyphen, take the first token,
which is already `C`, `F`, or `G`. No mapping table needed. Warn on anything else.

---

## 8. team_id=0 silently caps at 102,400 rows

**Date:** 2026-08-23 · **Stage:** 1 · **Amended in CLAUDE.md:** Section 14

`ShotChartDetail` with `player_id=0, team_id=0` looks like a one-call season pull. It
returns exactly 102,400 rows (100 x 1024) with dates stopping at 2026-01-29 against a
season running to 2026-04-12. No error, no warning, just a plausible half-season.

`src/collect.py` raises if any team pull returns exactly 102,400 rows.

Per-team pulls (`player_id=0`, real `team_id`) are exact: re-collecting 2025-26 by team
reproduced 219,160 rows, matching the independent per-player collection precisely.

---

## 9. Rosters are end-of-season, so three qualifying players have no POSITION

**Date:** 2026-08-23 · **Stage:** 1 · **Affects:** stage 3

`CommonTeamRoster` returns each team's roster as of the end of the season, not everyone
who appeared for it. Evidence: across all five seasons the roster row count equals the
distinct player count exactly, so no player is ever listed twice. The anticipated
traded-player duplication does not occur and needs no dedup rule.

The cost is coverage. Rosters carry 530 players for 2025-26 against 582 who took a shot.
Three of the 318 qualifying players are absent: **Cam Thomas** (460 attempts),
**Vince Williams Jr.** (292), **Jaden Ivey** (256).

Stage 3 must therefore handle a missing `POSITION` rather than assume the join is total.
Section 9 forbids silently producing NA, so the options are an explicit "Unknown" bucket
or a warning naming the players. Position is a display variable only, so three unlabelled
points on a scatter is not a correctness problem. **Decide this in stage 3, do not paper
over it in ingestion.**

---

## 10. Score correlates 0.48-0.66 with raw overall PPS. Not a collapse, but your call

**Date:** 2026-08-23 · **Stage:** 3 · **Section 16 check 2**

Section 16 expects a **weak** correlation between selection score and raw overall PPS,
warning that a strong one means the metric has collapsed into an efficiency measure.
Observed: 0.66 (2021-22), 0.62, 0.57, 0.48, 0.58 (2025-26). Moderate, not trivial.

**It is not the rejected formula.** Recomputing Section 7's discarded
`sum(f * PPS)` gives r = **1.000** against raw overall PPS, exactly as the algebra
predicts. Ours is 0.577 on the same players. The two are demonstrably different.

**My first explanation was wrong and is recorded as such.** I proposed that the
shift-share difference scales with a player's overall efficiency level, so uniformly
efficient players get amplified scores. Tested by dividing each score by that player's
mean shrunk PPS: the correlation moved 0.5773 to 0.5753. Essentially unchanged. The
scaling mechanism is not the cause. Asserted from a plausible mechanism, and false --
the exact pattern Section 1 warns about.

**What the data actually shows.** The top five for 2025-26 are all centres --
Kalkbrenner, Gobert, Hayes, Robert Williams III, Kornet -- with Herfindahl 0.59 to 0.76
and raw PPS 1.29 to 1.52. The bottom five are mid-range-heavy wings and guards with
Herfindahl 0.11 to 0.17. Rim concentration drives the score and raw PPS *both*, because
the restricted area is simultaneously the highest-PPS zone and the one most overweighted
relative to the league baseline. The correlation is a real feature of shot allocation,
not an artifact of the formula.

This is Section 16 check 4 answering itself: centres cluster hard at one end.

**Unresolved, and a judgment call for the user:** whether 0.58 satisfies "weak" as
Section 16 intended. If not, the fix is not a formula change but a within-position
comparison, which Section 8 already recommends for the concentration confound.

Note also that the top four are Kalkbrenner, Hayes, Kornet and Robert Williams III --
four of the ten players CLAUDE.md Section 5 names as excluded by the shots-per-game gate
that was deliberately dropped. Keeping them was correct; they are the headline result.

---

## 11. Three zone-seasons needed the method-of-moments fallback

**Date:** 2026-08-23 · **Stage:** 3

`VGAM::vglm` failed to converge on three of the 70 zone-season fits, all warned loudly at
runtime per rule A9, never silently substituted:

- 2022-23, `In The Paint (Non-RA) | Left Side(L)`
- 2022-23, `Mid-Range | Left Side Center(LC)`
- 2024-25, `Mid-Range | Right Side Center(RC)`

All three are low-volume zones. **2025-26 needed no fallback: 14 of 14 by MLE.** The
fallback decomposes observed variance in shooting percentage into true between-player
variance and expected binomial noise, then matches a Beta to the remainder.

Section 16's three-method `k` comparison is still outstanding and would test whether the
fallback values are close to what a converged MLE would have produced.

---

## 12. The metric discriminates within position. The positional pattern is presentation

**Date:** 2026-08-23 · **Stage:** validation · **Section 16 checks 3 and 4**

Position explains **R2 = 0.178** of score variance in 2025-26 (0.156-0.204 across
seasons). F(2,312) = 33.7, p < 1e-13, so the positional effect is real, but **82% of the
variance is within position.**

Within-group spread settles it. Centres have SD 0.0848, which is **139% of the
league-wide SD of 0.061**, spanning -0.053 to +0.286. The metric separates centres from
each other more sharply than it separates the league as a whole.

| POS3 | n | mean | SD | range |
|---|---|---|---|---|
| C | 44 | +0.0754 | 0.0848 | -0.053 to +0.286 |
| F | 112 | +0.0256 | 0.0584 | -0.118 to +0.183 |
| G | 159 | -0.0010 | 0.0418 | -0.117 to +0.145 |
| Unknown | 3 | -0.0235 | 0.0334 | -0.062 to -0.002 |

The within-position extremes are basketball-interpretable, which is the strongest
evidence the metric is measuring allocation rather than role. Centres run Kalkbrenner,
Gobert, Hayes at the top against Vucevic, Adebayo, Embiid at the bottom -- rim-runners
against centres who drift to mid-range and three. Forwards run Gafford, Giannis, Diabate
against Doncic, Murray, Durant. Guards run Payton II, Champagnie, Braun against
Nembhard, McConnell, DeRozan.

**Read: the metric works. The positional clustering is a display problem**, and Section 8
already prescribes the remedy -- colour by position, label the axis shot diet breadth,
and treat within-position comparison as the meaningful one. No metric change.

**Check 3, direction now measured rather than assumed:** score against `zones_used` is
**negative**, r = -0.68 (-0.64 to -0.72 across seasons). Players using all 14 zones average
-0.007; the player using 4 scores +0.251. Section 16 explicitly refused to predict this
sign, and it is confounded with concentration rather than independent of it.

---

## 13. Check 5 is near-tautological and cannot support its stated purpose

**Date:** 2026-08-23 · **Stage:** validation · **Section 16 check 5, Section 17**

Score against restricted-area frequency: **r = 0.862** (0.78-0.86 across seasons).

Section 17 says a strong result here triggers a displayed "rim pressure" column beside
the score. **I do not think this result licenses that conclusion**, and the reason should
go in the writeup rather than the remedy being applied automatically.

Section 16 already calls this an indirect proxy. The problem is sharper than indirect:
overweighting the restricted area relative to the league baseline is close to the single
largest positive contributor to the score by construction. A high correlation is what the
formula guarantees, not evidence about free throws. The check would need to be strong
*beyond* that structural floor to say anything, and there is no baseline here for what
that floor is.

**Resolved 2026-08-23:** the user accepted this and CLAUDE.md was corrected. Section 16
check 5 is now marked removed as invalid, and Section 17 no longer makes the rim-pressure
column conditional on it. The free-throw limitation is documented as not testable from
shot-log data alone.

---

## 14. The four-quadrant chart's two axes correlate 0.83

**Date:** 2026-08-23 · **Stage:** validation · **Affects:** stage 4

Herfindahl against pooled score: **r = 0.833** (0.77-0.85 across seasons).

Section 8 presents these as two axes giving four populated quadrants. At r = 0.83 the
scatter is close to a diagonal, so two quadrants will be dense and two nearly empty --
in particular "high score, low concentration", which Section 8 already anticipates as
"the rarest case".

**Resolved 2026-08-23:** the user accepted this and Section 8 was corrected. Concentration
is no longer the second axis. New Section 8a specifies score against shot volume instead.
Herfindahl stays computed and stored; the redundancy is reported as a finding.

One correction to my own earlier phrasing: the off-diagonal quadrants are not near-empty.
They hold 35 players each, 11% of the pool, against 124 on each diagonal cell. The
framing fails because the axes are redundant and the redundancy worsens within position,
not because the cells are unpopulated.

---

## 15. The score falls monotonically with shot volume

**Date:** 2026-08-23 · **Stage:** validation · **Now in CLAUDE.md Section 8a**

Mean pooled score by volume band, 2025-26: **+0.046** (250-400 attempts, n=92),
**+0.022** (400-600, n=92), **+0.011** (600-900, n=82), **-0.022** (900+, n=52). Overall
r = -0.386, and within position -0.485 (C), -0.477 (F), -0.350 (G).

The top 20 by score have a median of 364 attempts against a league median of 542. The
bottom 20 have a median of 981. Eight of the top 20 sit within 100 shots of the
250-attempt eligibility gate.

**Whether this is a finding or a bias is open and I did not resolve it.** The plausible
mechanism is that high-usage players must take contested shots from everywhere while role
players shoot only when open at the rim, so volume proxies for offensive role. That is a
hypothesis, not a measurement, and Section 1 is explicit about not stating one as the
other. Testing it would need usage or shot-clock data the shot log does not carry.

This is why Section 8a puts volume on the x-axis: the confound becomes visible rather than
hidden, which is what Section 8 already prescribes for the position confound.

---

## 16. The zone chart colours by contribution, which can read backwards

**Date:** 2026-08-23 · **Stage:** 4

`zone_chart()` defaults to `colour_by = "contribution"`, shading each zone by
`(f - f_league) * pps_shrunk`. That is the mismatch story Section 7 explicitly says to
store per cell, and it is what the project's question is about.

**It can be misread.** On Curry's chart the restricted area is the darkest red, which
looks like a weakness. It is his best zone at 1.38 PPS; it is red because he takes 15.3%
of his shots there against a much higher league share, so the underweight costs him. The
label prints PPS and attempt share alongside precisely so the colour is not read alone.

**Resolved 2026-08-24: the default is now `colour_by = "pps"`.** The reasoning is about
visual grammar rather than about the labels. A red-to-blue ramp laid over a basketball
court is universally read as efficiency -- that is what every shot chart a reader has ever
seen encodes -- so contribution colouring makes a claim the grammar contradicts. Curry's
best zone rendering darkest red is a real miscommunication, not a gap that annotation can
close, because the colour is processed before the label is read.

Contribution stays available as `colour_by = "contribution"` for the player-page mismatch
story, where the surrounding text can frame it.

## 17. The court outline is a drawing, not a classifier

**Date:** 2026-08-23 · **Stage:** 4

`court_layer()` draws a hoop, paint, restricted arc and three-point line in NBA
shot-chart units. Section 12 rejects derived zone geometry, and this does not reintroduce
it: no shot is assigned to anything by these coordinates. Every zone comes from
`SHOT_ZONE_BASIC` and `SHOT_ZONE_AREA`. The outline exists so the scatter reads as a
court.

Zone label anchors are median league shot positions per zone for the season, cached per
season, so every player's chart places each label identically -- including zones where
that player never shot.

---

## 18. The three k methods diverge, and the divergence is not where I predicted

**Date:** 2026-08-24 · **Stage:** validation · **Section 16 three-method comparison**

Median k across 14 zones: MLE 105, split-half 157, cross-validation 140. Agreement is
uneven:

    cor(k_cv,    k_mle)   = 0.880   rank 0.841
    cor(k_split, k_mle)   = -0.081  rank 0.327
    cor(k_cv,    k_split) = -0.135  rank 0.240

MLE and cross-validation agree closely and rank the zones almost identically, both putting
three-point zones at high k, which matches the literature -- 3PT% takes roughly 750
attempts to stabilise -- and matches EPM's practice of shrinking 3PT harder than 2PT.
Split-half agrees with neither on levels, though its rank correlation with the MLE is
weakly positive.

**My explanation was wrong, and testing killed it.** I predicted split-half would diverge
in the thinnest zones, since halving a 5-attempt cell leaves 2 or 3 shots and the
correlation is then dominated by binomial noise. Measured: the rank correlation between
disagreement and median attempts is only -0.185 for split-half and -0.302 for CV, and the
largest disagreements are in **thick** zones. `Above the Break 3 | Center(C)` has a median
of 39 attempts per cell and gives 560 (MLE), 130 (split-half), 1200 (CV) -- a 9x spread
with plenty of data.

**What is actually happening.** The divergence concentrates in the zones where k is large,
which are precisely the zones where the data cannot pin k down: between-player variance in
true three-point ability is small against binomial noise, so the likelihood and the
held-out loss are both nearly flat over a wide range of k. Cross-validation hit the grid
endpoint in exactly the two worst-disagreeing zones, which is the flat-loss-surface problem
the RAPM literature is candid about, and is a finding rather than an estimate.

**What the disagreement costs, which is the question that matters.** Recomputing shrunk PPS
under each candidate k:

| Zone | cell | spread in shrunk PPS |
|---|---|---|
| ATB3 Center | median (39 att) | 0.012 |
| ATB3 Center | p90 (109 att) | 0.097 |
| ATB3 RC | median (60 att) | 0.002 |
| ATB3 RC | p90 (132 att) | 0.084 |
| Restricted Area | median (144 att) | 0.000 |
| Mid-Range Left | median (11 att) | 0.008 |

For a typical cell the choice of k is worth 0.00 to 0.01 points per shot and is
immaterial. **For the highest-volume three-point shooters it reaches 0.08 to 0.10**, which
is larger than the league standard deviation of the selection score (0.061). So the
disagreement is harmless for most players and matters for the high-volume specialists at
the top of the three-point leaderboards.

**No favourite is picked.** The production method stays the beta-binomial MLE, which
Section 6 specifies and which cross-validation independently corroborates. The honest
statement for the writeup is that two of three methods agree closely, the third disagrees
on levels, all three disagree most where the data least constrains the answer, and the
practical consequence is confined to high-volume three-point cells.

---

## 19. Season discovery was circular, and the earlier one-command verification was not a clean-state test

**Date:** 2026-08-24 · **Stage:** pipeline · **Bug**

`available_seasons()` in `R/05_export_json.R` listed `data/processed/zone_stats/` to decide
which seasons the pipeline should run. That directory is something the pipeline **produces**,
not something it consumes. On a clean checkout the list is empty and `run_pipeline()` fails
its own `stopifnot(length(seasons) > 0)`. The pipeline would only run if it had already run.

**The verification that missed it was mine, and the flaw was in the method rather than the
result.** Section 22's first criterion was checked by running `Rscript R/run_pipeline.R
2025-26` against a working tree that already held five seasons of processed output. That
tests re-running, not building. A criterion phrased as "the pipeline runs end to end from
one command" can only be verified from a state where the end has not already been reached.
It was reported as satisfied on that basis and should not have been.

**Fix.** Discovery is split so each function lists the directory its stage consumes:

    available_seasons()   -> data/raw/shots        # what the pipeline can process
    exportable_seasons()  -> data/processed/zone_stats  # what stage 5 can export

The second still reads `data/processed`, which is correct rather than circular: that
directory is stage 5's input. It also keeps `meta.json` listing exactly the season files
beside it after a partial run.

**Audit of the same pattern.** One other instance, latent rather than firing: stage 2's
post-write verification globbed `data/processed/zone_stats/**/*.parquet` across every
season. Mid-pipeline some seasons are stage-2 shaped and others stage-3 enriched, and
DuckDB unions schemas across a glob, which is the failure that already bit stage 3 once.
Scoped to the single season just written. No other stage decides what to do from its own
output; the remaining `data/processed` reads in stages 3, 4, 5, `validation.R` and
`k_comparison.R` are all consuming a prior stage's output, which is the intended direction.

**Clean-state result.** After `rm -rf data/processed export/data export/charts`, a bare
`Rscript R/run_pipeline.R` rebuilt all five seasons in 0.1 minutes. Every figure reproduced
the values established earlier, including the two method-of-moments fallbacks in 2022-23 and
the one in 2024-25, so the fallback path is deterministic rather than incidental.

**Standing rule:** verify a build criterion from the state it claims to build from. A test
run against existing output is a regression test, not a reproducibility test, and the two
must not be reported interchangeably.

---

## 20. `data/processed/` is committed; `.gitignore` was wrong

**Date:** 2026-08-26 · **Stage:** repository · **Amended in CLAUDE.md:** Sections 13, A15

The brief has stated since the rebuild that the three output tables under
`data/processed/` are committed deliberately, so that a clone can reproduce every chart
and finding without an API collection run. `.gitignore` ignored the directory anyway, and
zero files under it were tracked. Nothing recorded a decision to reverse the policy, so
the ignore rule appears to have been inherited from the earlier Python-template
`.gitignore` rather than chosen.

**Resolved: the brief was right and `.gitignore` was wrong.** The ignore rule is removed
and the 15 Parquet files (1.0 MB, five seasons x three tables) are now tracked.
`.gitignore` carries a comment explaining why the directory is absent from it, so the
rule is not silently reintroduced later.

**Checked against rule A16 before committing.** A16 forbids raw NBA data leaving the
machine in any form. These tables do not breach it: the finest grain is the player-zone
cell (`zone_stats` 4,452 rows, `player_scores` 318, `zone_priors` 14 for 2025-26), and
none of the three carries `GAME_ID`, `LOC_X`, `LOC_Y`, `ACTION_TYPE`, or any per-shot
column. The boundary A16 draws is between shot-level data and derived aggregates, and
these are aggregates.

`data/raw/` and `data/cache/` remain gitignored permanently and that is unchanged.

**Consequence for A15:** the directory being committed is exactly why A15 forbids writing
large files there. Anything written to `data/processed/` is now permanent repository
weight.

---

## 21. Summing `contrib` in the JSON export does not reproduce `score`

**Date:** 2026-08-26 · **Stage:** 5 · **Documented in:** `export/SCHEMA.md`

In `data/processed/zone_stats` the per-zone `score_contrib` values sum to the player's
`score_pooled` exactly — zero difference at double precision, verified across all 318
qualifying players in 2025-26.

**In `export/data/season-*.json` they do not.** `R/05_export_json.R` rounds each of the 14
`contrib` values to 5 decimal places independently and rounds `score` separately, so the
two disagree in the fourth decimal. Measured across all 1,507 player-seasons the maximum
disagreement is **3.0e-04** (Trayce Jackson-Davis, 2023-24), and it is nonzero for most
players. `freq` has the same property at 4 dp: the 14 values sum to 1 only to about
2e-04.

**No change to the export.** The discrepancy is a rounding artifact three orders of
magnitude below the league standard deviation of the score (0.061), and it affects no
ranking. The risk is presentational rather than numerical: a consuming site that renders a
per-zone contribution breakdown and totals it will show a number that disagrees with the
headline score it sits beside.

`export/SCHEMA.md` now says plainly to display the shipped `score` and to use `contrib`
only for the per-zone breakdown. If exact reconciliation is ever wanted, the fix belongs in
the export — emit unrounded values, or derive `score` from the rounded contributions so the
two agree by construction — not in the site.

---

## 22. Zones are keyed by stable string id, not by positional index

**Date:** 2026-08-26 · **Stage:** 5 · **Amended in CLAUDE.md:** Section 18 · **Also:** `export/SCHEMA.md`

The JSON export previously identified zones by an integer 0-13, assigned by row order from
`ZONE_REF`. `meta.zones` carried an `index` field and every `players[].zones[]` and
`priors[]` entry keyed off it.

**What that would have cost.** The website is a separate repository that keys its
hand-authored SVG zone outlines off whatever the export provides. A positional index is not
an identity: it means "whatever is currently fourth in the reference table." The planned
14-to-12 zone merge would renumber everything after the paint zones, so `4` would stop
meaning `Mid-Range | Left Side(L)` and start meaning something else. Nothing would raise an
error. The pipeline would export valid JSON, the site would render a valid chart, and the
shape labelled mid-range-left would be filled with another zone's numbers. The failure is
silent, cross-repository, and visual — the worst combination to debug, because the only
symptom is a chart that looks plausible and is wrong.

**Fix.** `ZONE_REF` in `R/02_build_zone_stats.R` gains a `zone_id` column derived from
meaning rather than position: `restricted_area`, `paint_left`, `midrange_left_center`,
`arc3_center`, `corner3_right`, and so on. That column is the single source of truth. The
export uses it as the key everywhere and carries the full NBA label alongside it as `name`,
for display only. **No positional index appears in the export at all.** Array order is
retained as display order and documented as not being an identity.

Under the 14-to-12 merge, the three paint ids collapse to one and the other eleven are
untouched — so a site keyed on ids loses one shape and keeps eleven correct, instead of
silently mis-drawing eleven.

Cost: season files grew about 10 percent (3.03 MB to 3.38 MB across all six files) because
the id strings are longer than integers. That is the right trade against a silent
cross-repository correctness bug.

---

## 23. `league_attempts` renamed to `qualifying_attempts`

**Date:** 2026-08-26 · **Stage:** 3 and 5 · **Amended in CLAUDE.md:** Section 15

The `zone_priors` field counted attempts by qualifying players only, not the league. For
2025-26 restricted area that is 54,217 against a true league-wide 62,253 — a 15 percent
difference. The website will print the number under a chart, where the old label would have
been a false statement rather than merely an imprecise one.

Renamed in both the Parquet table and the JSON export, along with the internal
`league_makes`, so the two do not disagree. Row counts and every computed value are
unchanged; `pooled_fg_pct` is still the same ratio.

---

## 24. meta.json carries a player search index

**Date:** 2026-08-26 · **Stage:** 5 · **Amended in CLAUDE.md:** Section 18

The website's player picker must search all 538 players across five seasons without
downloading a season payload. `meta.json` now carries a `players` object keyed by player id,
each entry holding a display name and the seasons that player qualifies in.

Names are display text only and joins go on the id. Two players change spelling between
seasons — `202685` from "Jonas Valančiūnas" to "Jonas Valanciunas", and `1626171` from
"Bobby Portis" to "Bobby Portis Jr." — so the index keeps the most recent name and
`export/SCHEMA.md` states the rule explicitly.

This grew `meta.json` from 1.4 KB to 41 KB, which is still far below the ~700 KB of a single
season file and is the whole point: the picker loads one small file.

---

## 25. jsonlite's auto_unbox silently scalarises any length-1 field

**Date:** 2026-08-26 · **Stage:** 5 · **Pattern, not just an instance**

`R/05_export_json.R` writes with `write_json(..., auto_unbox = TRUE)`. That flag exists so
single values serialise as `"2025-26"` rather than `["2025-26"]`, which is what almost every
scalar field in the export wants. **It applies to every atomic vector, including ones that
are semantically lists.**

The instance: `meta.players[].seasons` shipped as a bare string for the 162 of 538 players
who qualify in exactly one season, and as an array for the other 376. A consumer iterating
that field would walk the characters of a string for roughly a third of the league. The
schema had documented it as "array of string" with no exceptions, which was wrong.

A second case was latent and would have fired on the next single-season export:
`meta.seasons` collapses to a bare string when `export_json()` is called with one season,
which is a normal thing to do.

**Fix:** wrap the vector in `I()`. That marks it AsIs and auto_unbox leaves it alone, at
both length 1 and length many. Applied to `meta.seasons` and `meta.players[].seasons`.

**The rule for anything added later.** Any field that is conceptually a list must be wrapped
in `I()` even when it is currently always longer than one, because the day it has one element
its type changes and nothing errors. Data frames are not affected — `auto_unbox` only touches
atomic vectors, so `zones`, `priors`, `baselines` and the season `players` array serialise as
arrays of objects regardless of row count.

The failure mode is worth naming: it is a **type that varies with the data**, which no schema
check on a single sample will catch. Both cases here produced valid JSON and would have
passed any test written against a multi-season player.

---

## 26. Zone drawing reference is a binned grid, not a point cloud, because of A16

**Date:** 2026-08-26 · **Stage:** 7 · **Rule tension:** A16

The website must hand-author 14 zone outlines and cannot reach `data/raw/`, so it needs
something to trace from. The obvious artifact is the labelled point cloud: every shot's
coordinates plus the NBA's zone label for it.

**That would breach A16.** A16 forbids raw NBA data leaving this machine in any form and
names shot-level CSV and JSON explicitly; Section 13 draws the line as "if a file contains
one row per shot, it does not leave this machine." A labelled point cloud is exactly one
row per shot. The request did not ask me to breach the rule and the conflict was flagged
rather than resolved silently.

**Resolution: a spatial histogram at half-foot resolution.** `export/reference/zone_grid.csv`
carries one row per cell per zone with a count — 7,902 rows over 7,508 cells covering
1,089,337 shots. It is a derived aggregate in exactly the sense `zone_stats` is: no per-shot
record, no player, no game, no outcome, and no coordinate finer than the bin. It sits on the
permitted side of A16 and is committed.

**It is also the better artifact**, which is why this is not a grudging compromise. The zones
are non-convex — the three arc zones are annular sectors — so convex hulls would be actively
wrong. A grid traces a non-convex boundary directly.

**A measurement that changed the design.** On 2025-26 alone, every cell was pure: no cell
contained shots from two zones, at cell sizes down to a quarter foot. That reading was a
sparsity artifact and I nearly reported it as a finding. Pooling all five seasons, 387 cells
at half a foot hold two zones. Those are the boundary cells, and they are the most
informative rows in the file — they show where an edge runs rather than only where a zone is.
The single-season result was not wrong so much as underpowered, and it would have supported a
false claim that the partition aligns to any grid you choose.

If the full point cloud is ever needed locally, `labelled_shots()` in `R/07_zone_geometry.R`
returns it in memory. Write it under `data/cache/` if it must be on disk. Never commit it and
never copy it into `export/`.

---

## 27. The corner / above-the-break break is at y = 87.5, not where the arc meets the corner line

**Date:** 2026-08-26 · **Stage:** 8 · **Zone geometry**

Drawing the 14 zone outlines needed the y value at which a three-pointer stops being a
corner three and becomes an above-the-break three.

**Geometry gives the wrong answer.** The three-point arc has radius 237.5 and the corner
segments are straight lines at x = +/- 220. Those meet at
y = sqrt(237.5^2 - 220^2) = **89.478**. That is the obvious value and it is not the one the
NBA uses.

**The labels give 87.5.** Among shots at |x| >= 220, corner threes reach a maximum y of
**87** and above-the-break threes start at a minimum y of **88**, with no overlap anywhere
in 1,089,337 shots across five seasons. The cut is flat and sits between them. Using the
geometric 89.478 would have mislabelled every shot in the two-unit strip at y = 88 and 89,
which is 850 shots in the 2025-26 data alone.

The corner line itself is also not exactly 220: mid-range reaches |x| = 219 and corner
threes start at |x| = 220, so the boundary is placed at 219.5.

**The general pattern, which cost the first checker pass.** Shot coordinates are integers.
Any threshold placed exactly on an integer leaves shots sitting on the boundary, where
point-in-polygon is undefined and the result depends on floating-point noise. Pass 1
returned 321 defects and every one was a shot lying exactly on a nominal court line:
131 at x = 80 on the paint wall, 166 at y = 138 on the free-throw line, 7 at x = 250 on
the sideline, 6 on the restricted-area circle, 1 at r = 160 exactly.

The fix was to measure each threshold rather than assume it: take the last coordinate on
one side and the first on the other, and place the boundary in the gap. That is recorded
in the constants block of `R/08_zone_polygons.R`, with the nominal court value noted beside
each measured one. Pass 2 returned zero defects.

**Do not "correct" these constants back to their nominal values.** PAINT is 80.5 and not 80,
FT is 138.5 and not 137.5, R_RA is 39.98 and not 40. Each looks wrong against a court
diagram and each is right against the data.

---

## 28. Eight positions derived from listed height, kept in a separate field

**Date:** 2026-08-26 · **Stage:** 3 · **Affects:** `player_scores`, the JSON export

Positions come from `CommonTeamRoster`, an end-of-season snapshot, so a player waived or
traded late qualifies on shots but appears on no roster. Eight player-seasons of 1,507 had
`POS3 = "Unknown"`: James Johnson and Drew Eubanks (2021-22), John Wall (2022-23), Killian
Hayes (2023-24), Orlando Robinson (2024-25), and Jaden Ivey, Vince Williams Jr. and Cam
Thomas (2025-26).

**Listed height was available for all eight**, from a roster in an adjacent season. Nobody
was left Unknown and nothing was inferred from any other source.

The rule, applied only where `POS3` is `Unknown`: 6 ft 5.5 in and under is a guard, 6 ft 6
to 6 ft 10 a forward, 6 ft 11 and over a centre. Killian Hayes is the only player with
conflicting listings, 6-5 and 6-4, and both fall in the same bucket.

**The values live in `POS3_DISPLAY` with a `POS3_DERIVED` flag. `POSITION` and `POS3` are
untouched and remain reported-only.**

**The reason is that filling in place would make a headline result circular.** Entry 12
records that position explains R2 = 0.178 of the variance in selection score, and that 82
percent of the variance sits within position — that is the project's answer to "the metric
is just detecting position." If position were derived from height, then for those players
position *is* height, and anyone could argue the variance decomposition is partly an
artifact of how the gaps were filled. Separating the fields means the site can label every
point on a chart while `validation.R` and every correlation continue to use `POS3` alone.
Nothing in the analysis reads `POS3_DISPLAY`.

**One disagreement worth recording.** Orlando Robinson is listed 6 ft 10 in, which the rule
calls a forward, and the league listed him a centre in the seasons it listed him. The rule
was applied as specified and he is derived `F` for 2024-25. This is the case the instruction
"never to a player the league already listed, even if the height rule would disagree"
anticipates: for 2024-25 the league listed nothing, so the rule applies; for the seasons it
did list him, his reported `C` stands untouched.

The height thresholds are constants at the top of `R/03_compute_scores.R`.

---

## 29. Rule A4 superseded: zones are computed, from one constants block

**Date:** 2026-08-27 · **Amends:** `CLAUDE.md` A4, Section 12, Section 18 · **Branch:** `zone-model-10`

A4 banned writing a zone classifier: zones came from concatenating `SHOT_ZONE_BASIC` and
`SHOT_ZONE_AREA`. The ban existed because an early version of this project wasted sessions
deriving radial boundaries and checking them against a hand-written classifier, and the
league's labels were both less work and a stronger claim.

**What changed.** Deriving the zone outlines for the website (entry 27) exposed two things the
labels encode that are not basketball distinctions. The scheme mixes a rectangular lane with a
polar grid, so the two disagree along the lane walls and leave slivers. And it changes its
angular thresholds at 16 feet — 60°/120° in the 8–16 ft band, 36°/72°/108°/144° beyond it —
which puts a step in the middle of a zone.

**What A4 protected against was two definitions drifting apart**, not computation as such. The
new rule protects the same thing by a different route: every number that places a boundary
lives in `R/zone_model.R`, and `classify_zone()` and `zone_polygon()` both read it, so a
boundary change is one edit that moves the classifier and the outline together.

**Ordering matters and was nearly got wrong.** The original plan sequenced all documentation at
step 6, after the pipeline rewire. But rewiring stage 2 against a classifier *is* the act the
old A4 forbade, so the rule had to be amended first. `R/zone_model.R` was also found already
asserting in its header that A4 "was rewritten on 2026-08-27" when it had not been.

---

## 30. Backcourt is cut at y = 397.5, measured and not geometric

**Date:** 2026-08-27 · **Stage:** 2 · **Constant:** `Y_BACKCOURT` in `R/zone_model.R`

Under the NBA labels, backcourt heaves were dropped by testing `SHOT_ZONE_BASIC = 'Backcourt'`
and `SHOT_ZONE_AREA = 'Back Court(BC)'`. Under coordinate classification that filter would be
the one place still reaching into the retired labels, so it becomes a coordinate cut:
`classify_zone()` returns `NA` above `Y_BACKCOURT` and stage 2 drops those rows explicitly.

**397.5 is measured from the gap in the data.** The maximum in-play y is 397 and the minimum
backcourt y is 398, across all 1,091,329 shots in five seasons. This is the same method entry
27 used for the corner break, and for the same reason: shot coordinates are integers, so a
threshold placed on one leaves shots sitting exactly on it.

**The true half-court line is y = 417.5** — 47 ft less the hoop's 5.25 ft from the baseline —
and it is the wrong value here. 149 backcourt-labelled shots sit inside it, heaves whose
recorded coordinate lands short of where the ball was released. Excluding those is the point of
the filter. **Do not "correct" 397.5 to 417.5.**

**Verified equivalent, per season and not merely in total:** 475 / 459 / 465 / 555 / 38 rows,
identical row sets to the retired label filter. Stage 2 asserts this on every run against the
label columns, which stay in `data/raw/` forever. It is a proof, not a dependency.

`TOP_BOUND`, which closes the open polygons, was moved from 430 to the same constant so the
outlines cover exactly what the classifier assigns. At 430 a 32.5-unit band would have belonged
to a zone by polygon and to nothing by classifier.

---

## 31. Two figures in the draft zone table did not reproduce, and were not quietly adopted

**Date:** 2026-08-27 · **Stage:** 2 · **Affects:** `ZONE_MODEL_ACCEPTANCE.md`, `EXPECTED`

The session that drafted `R/zone_model.R` produced a zone-count table and an eligibility table.
Rebuilding from the shipped classifier reproduces both except in two places.

**The mid-range ray split, 4 shots.** Shipped gives `mid_left` 29,758 / `mid_right` 29,948 /
`mid_center` 62,581 against the draft's 29,757 / 29,945 / 62,585. Four shots at (±96, 93) lie
exactly on `atan2(77.5, 80)`, and the shipped classifier's `<=` is inclusive where the draft's
was exclusive. **`ZONE_MODEL_ACCEPTANCE.md` cites the draft figures and was not edited.** A
pre-registered file that moves to accommodate an outcome is not a pre-registration; its
Criterion 4 is a symmetry test within ~10 percent, which the shipped numbers pass at 0.64.

**The 2025-26 cell counts.** Draft 3,087 / 60 / 197 against a build of 3,089 / 61 / 198. The 60
and 197 reproduce exactly if the tally is taken *before* the point-value clashes are dropped,
so that table was measured one stage early. **3,087 reproduces under nothing tested**: not the
mid-ray difference (no 2025-26 shot lies on a mid ray), not rim, lane, free-throw-line, corner
or arc inclusivity, not either backcourt treatment. Two cells in 3,089 is 0.06 percent, and
none of these figures is pre-registered. `EXPECTED` now carries the measured values, labelled
in the source as a drift guard rather than an independent check.

---

## 32. Zone ids will survive the model change with different geometry — unresolved

**Date:** 2026-08-27 · **Stage:** 7 · **Status:** open, to be solved at step 5

`arc3_center`, `corner3_left` and `corner3_right` exist in both the 14-zone and 10-zone models
with different shapes, and `arc3_left_center` / `arc3_right_center` become `arc3_left` /
`arc3_right`. The website keys its SVG paths off these ids. A site holding outlines from before
today would draw a wrong court for the three reused ids **with nothing raising an error.**

Documenting this is not sufficient. Step 5 must propose a mechanism that makes it impossible —
a schema version in the export the site asserts against, or ids that change whenever the
geometry does. The site failing to build is the acceptable outcome; rendering a wrong court is
not.

---

## 33. `ASSUMPTIONS.md` is tracked in git as of 2026-08-27

**Date:** 2026-08-27 · **Amends:** `CLAUDE.md` C2 and Section 13, `.gitignore`

This file was gitignored from the start. It is now committed, for the reason `CLAUDE.md`
stopped being gitignored: an audit trail records decisions and their reasoning that exist
nowhere else, so a lost copy cannot be reconstructed from the code, the way a description of
the code can be. Reconstructing `CLAUDE.md` cost a full session and the reconstruction
contained errors.

The trigger was concrete. On 2026-08-27 the `zone-model-10` branch held three commits that
existed on one laptop with no remote copy, and entries 29 to 32 of this file had no copy
anywhere at all. Pushing the branch fixed the first problem and, because of the gitignore
entry, did nothing for the second.

Nothing here is raw NBA data, so A16 is untouched.

---

## 34. The 14-zone baseline is extracted to `data/cache/baseline_14zone/`, from ref `ec2d350`

**Date:** 2026-08-27 · **Stage:** 3 precondition

`ZONE_MODEL_ACCEPTANCE.md` Criterion 3a compares each player's old selection score against
his new one by Spearman correlation. The old scores live only in git: stage 2 rewrites
`player_scores` with its own six-column shape, so the working tree already has no
`score_pooled` in any season.

**The ref is `ec2d350`**, the last commit before the pre-registration, and it is written down
because `HEAD` will not stay usable. `git show HEAD:data/processed/...` returns the baseline
only until something commits the rebuilt tables, after which the same command silently returns
the new file. Verified this session: `data/processed` is byte-identical between `ec2d350` and
the current `HEAD`.

All fifteen files -- three tables, five seasons -- are extracted to
`data/cache/baseline_14zone/`, with a `PROVENANCE.txt` naming the ref. That directory is
gitignored permanently (A16), which is correct here: these are derived aggregates being kept
as a local convenience, and git remains the authoritative copy.

---

## 35. `arc3_center` is renamed `arc3_top`; `corner3_left` and `corner3_right` keep their names

**Date:** 2026-08-27 · **Stage:** 2 · **Affects:** the JSON export, `export/SCHEMA.md`, the website

Three ids existed in both the 14-zone and 10-zone models. Two of them are safe and one was not.

`corner3_left` and `corner3_right` are **membership-identical across the two models**, shot for
shot: 58,364 and 53,415 over five seasons, 10,434 and 9,645 in the 2025-26 qualifying pool,
matching the old `Left Corner 3 | Left Side(L)` and `Right Corner 3 | Right Side(R)` exactly.
Their outlines differ only in epsilon placement. A site holding the old shapes draws them
correctly. They keep their names, and that stability is a real property rather than an
accident.

`arc3_center` was not safe. Under the 14-zone model it was the NBA's roughly 72-108 degree
wedge; under the 10-zone model the same string named the 60-120 degree wedge, nearly twice as
wide, at 29,332 qualifying attempts in 2025-26 against 15,586. A consumer holding the old
outline would have drawn the narrow wedge against the wide wedge's number **with nothing
raising an error**, and a centre wedge looks like a centre wedge, so no reader would catch it.

Renamed to `arc3_top`, not to anything containing `arc3_center` as a substring, so a naive
match cannot bridge the two. This is insurance, not the mechanism: the mechanism is a model
version emitted into both `meta.json` and `zone_polygons.json` and asserted at site build time,
designed in the polygon step and deliberately not built yet. The rename protects the case the
version check cannot -- a file copied by hand, with no build step between.

---

## 36. The ten zone display labels are placeholders and must not ship

**Date:** 2026-08-27 · **Stage:** 2 · **Marker:** `TODO_ZONE_LABELS` in `R/02_build_zone_stats.R`

`ZONE_REF$zone_label` currently holds copy written by the assistant, not by the author. It is
user-facing text destined for charts, the JSON export and the website, and the author writes
that. `ZONE_LABELS_PROVISIONAL <- TRUE` sits beside the table so stage 5 can refuse to run
while it is set; wiring that assertion is part of the stage 5 rewire. Wording arrives from the
author before the export step.

---

## 37. `LANE_TOP` is the nominal free-throw line at 137.5, not the labels' 138.5

**Date:** 2026-08-27 · **Stage:** 2 · **Constant:** `LANE_TOP` in `R/zone_model.R`

Two candidates, and the difference is one coordinate unit.

**138.5, the measured value.** The NBA's labels put the paint/mid-range cut there: across all
1,089,337 in-play shots, the maximum y under an In The Paint (Non-RA) label is 138 and the
minimum y for a Mid-Range shot inside the lane is 139. `R/08_zone_polygons.R` recorded
`FT <- 138.5` for exactly this reason, following the general method of entry 27 — measure the
threshold from the gap rather than assume it.

**137.5, the nominal value, and the one adopted.** The free-throw line is 15 feet from the
backboard face, which puts it at y = 137.5 in shot-chart units. That is where the line is
painted on the floor.

**137.5 wins because the model computes zones from court geometry rather than reproducing the
NBA's classification.** 138.5 exists only to match a label boundary, and that label scheme is
what this change retires. Adopting a value derived from a retired source imports the thing
being left behind. Entry 27's measure-the-gap method was correct for its purpose — it was
reproducing the labels — and this is a different purpose.

**The consequence is 799 shots.** They sit in the strip `|x| <= 80`, `137.5 < y < 138.5`, all
at y = 138. Every one is In The Paint (Non-RA) by label and `mid_center` here: 787 Center(C),
6 Left Side(L), 6 Right Side(R). **They are the only paint-family disagreement between this
model and the NBA labels across all 1,089,337 shots** — every other shot in the restricted
area and the paint agrees. The divergence report at step 5 will show them.

**138.5 is not a correction to be applied later.** It will look like an error against
`R/08`'s constant block and against entry 27, and it is not one. This is the same hazard as
the corner break at 87.5, which is measured where a diagram says 89.478, and as the backcourt
cut at 397.5, which is measured where geometry says 417.5. Each of the three looks wrong
against one reference and is right against the one that governs it. Check which reference
governs before changing any of them.

No integer y can equal 137.5, so no shot sits on the boundary and ray casting stays defined.
