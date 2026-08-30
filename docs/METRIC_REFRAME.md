# Metric reframe: from league-counterfactual allocation to self-relative relocation gain

> **Superseded design draft.** This document contains useful research and
> reasoning, but later planning changed the relocation cap, the model comparison,
> and the decision to remove zones from presentation. The active decisions live
> in `docs/SPATIAL_MODEL_PLAN.md`.

**Status: specification in progress. Nothing in this document has been built. None of it has
met data. The logic may change before or during implementation.**

Written 2026-08-29, on branch `zone-model-10`, after the 14-zone to 10-zone change was
completed and before any of the work below was started. It exists because the reasoning
behind it currently lives only in a conversation, and conversations in this project have been
lost twice.

This is not a plan of record. It is a snapshot of intent detailed enough that someone with no
memory of the conversation can reconstruct why each choice was made, disagree with it on the
merits, and know what evidence would change it.

---

## How to read the tags

Every substantive claim below carries one. Check the tag before relying on the sentence.

| Tag | Means |
|---|---|
| **[Settled]** | Reasoning that holds independently of how the build goes. Usually a fact about the current metric, or a constraint from an existing project rule. Changing it needs a real argument. |
| **[Decision]** | A choice made deliberately, with a named alternative that was rejected. Revisitable. Each one states what would change it. |
| **[Intent]** | Current plan. Weakly held. Expected to move on contact with data. |
| **[Open]** | Not decided. Listed so it is not mistaken for decided. |

Nothing here is tagged **[Finding]**, because nothing here has been measured. Where numbers
appear they describe the **current, shipped** metric, which does exist and has met data — they
are the evidence for abandoning it, not evidence about its replacement.

---

## 1. Why the current metric is being abandoned

### What it computes

    S[p] = SUM over z of ( f[p,z] - f_league[z] ) * PPS_shrunk[p,z]

The player's own zone-by-zone efficiency, held fixed, weighted by how far his shot
distribution departs from the league's pooled distribution. It is a shift-share
decomposition. Skill appears identically on both sides of the comparison and cancels, which
is the property that made it attractive: what remains is attributable to allocation rather
than to shooting ability.

**[Settled] The formula is not wrong on its own terms.** It does what it claims. The problem
is what its terms mean.

### The first objection: it needs ability where there is no evidence

`PPS_shrunk[p,z]` must be defined for every zone, including zones the player never uses,
because `f_league[z]` is nonzero everywhere. Shrinkage supplies a value there — at zero
attempts it returns exactly the fitted prior mean — and that is mathematically clean. But a
term built from the prior mean is a statement about the league, multiplied by a frequency gap
that is large precisely because the player avoids that zone. The score's most heavily weighted
terms are frequently its least evidenced.

**This is not hypothetical and it is not confined to marginal players.** On 2025-26, measured
on the shipped model:

| | |
|---|---|
| Qualifying players with at least one zero-attempt cell | 36 of 318 |
| Largest share of one player's score magnitude coming from zero-attempt cells | **41.6%** (Deandre Ayton) |
| Median share of score magnitude from cells with fewer than 10 attempts | 6.7% |

And for the five players the project puts at the top of its leaderboard:

| Player | Score | Zero-attempt cells | Share of score magnitude from cells with <10 attempts |
|---|---|---|---|
| Ryan Kalkbrenner | +0.285 | 2 | 35.1% |
| Rudy Gobert | +0.263 | 2 | 35.4% |
| Jaxson Hayes | +0.248 | **7** | 39.4% |
| Robert Williams III | +0.231 | 1 | 33.0% |
| Luke Kornet | +0.210 | 5 | 37.6% |

**[Settled] Roughly a third of the headline result is arithmetic over cells where the player
has almost no record.** Jaxson Hayes has seven of ten zones empty. His score is mostly a
statement about what the league does in those seven zones, scaled by his avoidance of them.
That is defensible as a construction and indefensible as a description of Hayes.

### The second objection: a low score does not establish that a different diet was available

**Kevin Durant, 2025-26, is the worked example.** Score −0.109, third from bottom of 318.
1,376 attempts, so none of this is small-sample.

| Zone | His attempts | His freq | League freq | His shrunk PPS | Contribution |
|---|---|---|---|---|---|
| `rim` | 128 | 0.093 | 0.278 | 1.45 | **−0.269** |
| `paint` | 377 | 0.274 | 0.203 | 1.15 | +0.081 |
| `mid_center` | 228 | 0.166 | 0.053 | 0.95 | +0.108 |
| `arc3_top` | 229 | 0.166 | 0.150 | 1.07 | +0.017 |
| `corner3_left` | 15 | 0.011 | 0.054 | 1.19 | −0.051 |
| *(remaining five)* | | | | | +0.005 |

The single largest term in Durant's score, by a factor of two and a half, is `rim`. The metric
observes that he shoots 9.3% of his attempts at the rim where the league shoots 27.8%, that he
converts at 1.45 points per attempt when he does, and concludes he is leaving value on the
floor.

**[Settled] To read that as a criticism of Durant's shot selection requires believing he could
triple his rim rate.** The metric does not know whether he can. Nothing in a shot log
distinguishes a player who chooses not to attack the rim from one whose role, team spacing,
age, or the defence's willingness to concede a mid-range jumper rather than a drive means he
cannot. The counterfactual is arithmetically available and behaviourally unexamined.

Note that Durant illustrates the *second* objection, not the first: only 7.6% of his score
magnitude comes from cells with fewer than 30 attempts, and he has no empty cells. The two
objections bite different players. The first hits specialists, including the top of the
leaderboard. The second hits high-usage players, including the bottom. Between them they cover
both ends of the ranking the project reports.

### What is *not* the reason

**[Settled] The metric is not being abandoned because it failed validation.** It passes every
check in CLAUDE.md Section 16. Pooled and unweighted baselines correlate 0.9998, it does not
collapse into raw efficiency (0.573), position explains only 17% of its variance, and centres
discriminate at 140% of the league SD. It was also just carried through a zone-model change
with a rank correlation of 0.998, which is evidence it measures something stable.

It is being abandoned because **passing those checks does not answer the objections above**,
and the objections are about what the number means rather than whether it is reproducible.

---

## 2. What replaces it

**[Decision] The score becomes the gain available from shifting attempts toward the areas
where the player is already strongest, evaluated on his own shot distribution.**

Informally: not *"what would he score with the league's diet?"* but *"how much better would he
do by doing slightly more of what he is already good at?"*

The properties this buys:

**No league counterfactual, so no extrapolation.** Weight moves between cells the player
already uses, toward cells where his own estimated efficiency is highest. There is no term
requiring his ability in a place he has never shot, because there is no comparison to a
distribution that is nonzero everywhere.

**The comparison is internal.** A player is measured against himself, so role differences
between a rim-running centre and a primary creator do not enter as a penalty on one of them.
This directly addresses the position confound that CLAUDE.md Sections 8 and 16 currently
handle by labelling rather than correcting.

**The direction is actionable in a way the old one was not.** "Take more of the shots you
already take well" is a claim about a marginal change. "Shoot like the league" is a claim
about a wholesale change, and the latter is the one the data cannot support.

**[Settled] What is deliberately given up.** The old score's headline property — that shooting
skill cancels exactly, so the number is *purely* allocation — does not survive. A
self-relative gain necessarily mixes allocation with the spread of a player's own efficiency
across the floor: a player with a flat efficiency profile has little to gain from relocation
regardless of how well allocated he already is. **This is a real cost and should be stated in
any writeup rather than glossed.** The judgement is that a slightly less clean decomposition
of a question that can be answered beats a clean decomposition of one that cannot.

---

## 3. Why there is no relocation cap

The score is the **rate of gain as relocation begins** — the derivative at zero, not the
integral to some endpoint. No fixed quantity of shots is moved.

Two alternatives were considered and both rejected. **Recording both, because either could be
revisited and the reasoning should not have to be reconstructed.**

**[Decision] Rejected: a fixed percentage cap.** Move up to *n*% of a player's attempts and
report the gain at that point. Rejected as **arbitrary**. Nothing in basketball or in the data
picks 5% over 10% over 20%, the choice silently sets the metric's scale, and every reported
number would inherit a parameter no reader could evaluate. Worse, different caps could reorder
players — a cap large enough to exhaust a specialist's best zone treats him differently from
one that does not.

*What would change this:* evidence that the ranking is materially cap-dependent, which is
exactly what Check 1 in Section 8 is designed to detect. If rank correlation across candidate
caps turns out to be low, the derivative is not summarising the family well and a specific
cap, chosen and defended, becomes necessary.

**[Decision] Rejected: calibrating a cap from observed season-to-season movement.** Measure
how much players actually shift their distributions between consecutive seasons and use that
as a realistic relocation budget. Rejected as **unnecessary**, not as wrong — it is a
defensible idea and the data to do it exists, since all five seasons are collected. It was
rejected because the derivative already answers the question without introducing an estimated
parameter, its estimation error, and a dependence on the pairs of seasons used. It also
imports an assumption that historical movement bounds achievable movement, which is a strong
claim about a league that changes.

*What would change this:* wanting the score in units of "points per season actually gainable"
rather than a rate. That is a genuinely different and more communicable quantity, and if
presentation demands it, this is the route to it.

**[Settled] The derivative has a real advantage beyond avoiding a parameter.** It is
scale-free, so it does not need restating when the eligibility gates or the zone model change,
and it cannot be gamed by choosing the cap that flatters a preferred conclusion.

---

## 4. Why diversity is a second number

**[Decision] Shot-distribution entropy is reported alongside the score, not folded into it.**

The temptation is to combine them: a player who concentrates entirely on his best spot scores
well on relocation gain almost by construction, and a metric that rewarded that alone would
say something trivially true.

**Rejected: penalising concentration inside the score.** A star who genuinely does everything
well — creates from everywhere, converts from everywhere — would be marked down by a
diversity penalty embedded in a metric that claims to measure allocation quality. That is a
category error: breadth is a property of a player's role and skill set, not a defect in how he
allocates. The old metric already ran into the adjacent version of this problem, which
CLAUDE.md Section 8 records: concentration correlates 0.777 with the current score and 0.904
within centres, and the project's response was to *stop using concentration as an axis*
rather than to correct for it.

Reporting entropy separately keeps both readable. A high score with low entropy is a
specialist exploiting a narrow edge. A high score with high entropy is a player with a broad
game who is still underweighting his best areas. Those are different findings and a combined
number would erase the distinction.

**[Open] Which entropy.** Shannon over the cell distribution is the obvious default, but the
cell grid is finer than the ten zones and entropy is resolution-dependent, so a value computed
on a fine grid is not comparable to one computed on the zone table. Whether to report it at
zone resolution for interpretability, at grid resolution for fidelity, or both, is undecided.

---

## 5. The estimation change

### From beta-binomial per zone to a spatial model

**[Settled] The current approach fits fourteen — now ten — independent beta-binomials, one per
zone, with no information shared between them.** CLAUDE.md Section 12 already records that a
conditional autoregressive prior is "a genuinely better model" and "a reasonable v2", deferred
only because it needs MCMC and fits take minutes rather than seconds. Section 6's instruction
to isolate shrinkage in a single function taking `(makes, attempts, zone)` was written
specifically so this swap would be one function.

**[Settled] But the deferral note carries a caveat that must not be lost.** The same section
records that adjacency was later tested directly and *carried no information at the zone
level*: Left Corner 3 correlates 0.295 with Right Corner 3 and 0.262 with its own physical
neighbour. **That test was run on ten large zones, where a "neighbour" is an entire region.**
The reframe's premise is that at finer resolution neighbouring cells genuinely are informative
about each other, which is a different claim. It is a premise, not an established result, and
if a spatial model shows no gain over independent cells on held-out loss, that premise has
failed and the finer grid is not earning its cost.

### Model make probability, not points per shot

**[Decision] The spatial model estimates make probability. Point value is applied per cell
afterwards.**

The reason is continuity. Make probability varies smoothly across the floor: a shot from just
inside the arc and one from just outside it are nearly the same shot and convert at nearly the
same rate. Points per shot does not vary smoothly — it jumps by a factor of 1.5 at the arc,
because the same physical shot is worth two on one side of a painted line and three on the
other. **A spatial smoother applied to a discontinuous surface will smooth across the
discontinuity**, borrowing strength between cells whose values differ for a reason that has
nothing to do with shooting. Modelling the continuous quantity and applying the discrete
multiplier afterwards keeps the discontinuity exactly where the rulebook puts it.

*Rejected: model points per shot directly.* Simpler, one stage, and it is what the current
metric consumes. Rejected for the reason above.

**[Settled] eFG% was proposed and is rejected.** It was raised as a value-aware alternative to
raw make probability. It is not one: effective field goal percentage is points per shot scaled
by one half, so it inherits the identical discontinuity at the arc and solves nothing. It is
also **banned outright by rule A3**, which forbids eFG%, true shooting, or any efficiency
metric other than PPS anywhere in the project, and CLAUDE.md Section 3 records that an earlier
version used eFG% and it was deliberately replaced. This is not a close call and it should not
be reopened without reopening A3 first.

### The neighbourhood is not cut at the three-point line

**[Decision] The spatial neighbourhood structure crosses the arc. Cells just inside and just
outside it are neighbours.**

The alternative is to treat the arc as a hard boundary and fit two separate surfaces, which is
superficially attractive because the *value* changes there.

It is rejected because the **shooting ability** does not change there, and severing the
neighbourhood would erase a pattern the metric should be able to see. A player who is strong
from 20 to 22 feet but does not shoot threes is a real and identifiable type. With the arc as
a hard boundary, his long-two skill contributes nothing to the estimate of his ability just
beyond it, and the pattern is smoothed away into whatever his sparse three-point record says.
With the neighbourhood intact, the surface shows a genuine ability gradient that stops at a
line he does not cross — which is a finding about shot selection, and precisely the kind of
finding the reframe exists to surface.

Since make probability is what is being smoothed and value is applied afterwards, crossing the
arc in the neighbourhood costs nothing on the value side.

### CAR against a Gaussian process

**[Intent] Both are to be implemented and compared. Neither is presumed.**

A conditional autoregressive prior treats cells as a lattice with explicit adjacency. A
Gaussian process treats the surface as continuous with a distance-based kernel. They encode
different assumptions about how ability varies across the floor, and the honest position is
that it is not obvious which fits basketball better.

**[Decision] Decided on held-out log-loss.** Log-loss because the quantity is a probability
and log-loss is the proper scoring rule for one — it penalises confident errors correctly,
which is exactly the failure mode a spatial prior can introduce in sparse regions. Held-out
because in-sample fit will reward the more flexible model regardless.

**[Decision] Runtime is reported but not decisive.** Section 12 deferred CAR partly on
runtime, and that deferral has already been paid for: the pipeline currently rebuilds five
seasons in nine seconds and this will be slower by orders of magnitude. Runtime belongs in the
report because a model nobody can afford to run is a real problem for the clean-state
discipline. But a model that is meaningfully better on held-out loss should win a comparison
against one that is merely faster, and pre-committing to that ordering now prevents the
decision being made later on convenience and rationalised as principle.

*What would change this:* a runtime so large that the clean-state rebuild becomes impractical.
That is a threshold, not a gradient, and it should be named before the comparison is run
rather than after.

---

## 6. `freq_pooled` stays raw

**[Decision] The league pooled frequency vector is used unsmoothed in the score. It is
smoothed only for display.**

Smoothing it is tempting for the same reason smoothing anything is tempting — the raw vector
is noisy at fine resolution and a smoothed one looks better on a chart.

It is rejected in the score because **smoothing moves league weight into cells where neither
the league nor the player shoots.** A smoother spreads mass from busy cells into their empty
neighbours. Those cells then carry a nonzero `f_league` against a player frequency of zero and
an efficiency estimate that comes entirely from the spatial prior. The score's dependence on
the prior goes up, in exactly the cells where the prior is least constrained by data — which
is the first objection in Section 1, reintroduced through the back door after the reframe was
designed to remove it.

**[Settled] The display case is different and the distinction is worth keeping explicit.** A
chart is read for shape, and a smoothed baseline surface reads better without misleading
anyone, because nothing is computed from it. The rule is: **smoothed for the eye, raw for the
arithmetic**, and any code that blurs the two should be treated as a bug.

*What would change this:* if the raw vector at the chosen grid resolution turns out to be so
sparse that the score is dominated by single-shot cells. That is a resolution problem and the
fix is a coarser grid, not a smoother baseline.

---

## 7. What survives

**[Settled] Most of the infrastructure is unaffected, and this is by design.** The reframe
changes what is computed from the shot log, not how the shot log is obtained, cleaned, or
bounded.

| Survives | Note |
|---|---|
| **The ten zones** | Retained as a **reporting table**, not as the estimation grid. Human-readable aggregation for the site and the writeup. |
| **Eligibility gates** | 20 games and 250 attempts, unchanged. Rule A6 forbids adding others, and nothing in the reframe argues for moving these. Changing them would confound the reframe with a population change, the same argument that kept them fixed through the zone change. |
| **Geometry constants** | `R/zone_model.R` — every court primitive, the measured `CORNER_TOP`, `Y_BACKCOURT`, `LANE_TOP`. The fine grid is defined in the same coordinate system. |
| **`classify_zone()`** | Still needed to produce the ten-zone reporting table from coordinates. |
| **The version fingerprint** | `zone_model_version()` and the `zone_model` assertion between `meta.json` and the polygon file. If the reframe changes the reporting zones or the geometry, the fingerprint moves on its own and a stale site fails to build. |
| **Clean-state discipline** | `rm -rf data/processed export/data export/charts` then one command. Currently 9.2 seconds and byte-identical across three builds. **This is the property most at risk from a slow spatial fit** — see the runtime note in Section 5. |
| **Rules A3, A6, A9, A13, A14, A15, A16** | Untouched. PPS remains the only efficiency metric; failures still surface loudly; Parquet only; `season` always an argument; no raw data leaves the machine. |
| **A4** | Untouched in spirit and probably in letter: boundaries still live in one constants block. If the estimation grid introduces its own spacing constant, it belongs in `R/zone_model.R` beside the rest. |

**[Settled] The polygon rendering path is largely superseded, and this is a consequence rather
than a problem.** `zone_polygon()`, the `EPS` offset scheme, the keyhole slit, `mirror()`, and
the checker in `R/07_zone_geometry.R` exist to draw and verify ten zone outlines. A metric
computed on a fine grid is displayed as a heatmap, not as ten filled polygons, so most of that
machinery stops being on the critical path.

It should **not** be deleted. The ten zones survive as the reporting table, the site keys its
SVG paths off the outlines, and the checker is the only thing that verifies the classifier and
the polygons agree. It moves from load-bearing to supporting. That is what "superseded" means
here and it is worth saying plainly, because the work was recent and someone reading a diff
that stops touching those files could reasonably assume something broke.

---

## 8. Three checks before any score is trusted

**[Decision] None of these are optional and none of them are validation of the metric's
meaning.** They are checks that the number is stable enough to interpret at all. Meaning comes
later and separately.

### Check 1 — does the relocation quantity matter?

Compute the score at 10%, 20% and 30% relocation and rank-correlate the three.

**High correlation means the derivative is a fair summary of the whole family**, the choice of
quantity is immaterial, and Section 3's rejection of a cap is vindicated. **Low correlation
means the ranking depends on a parameter that has been deliberately left unspecified**, which
is a direct threat to Section 3 and would force a specific cap to be chosen and defended.

This check is designed to be able to overturn a decision already made in this document. That
is the point of running it first.

### Check 2 — how much weight sits on nothing?

For every player, the share of the score's weight falling in cells with zero attempts.

The reframe exists to remove extrapolation. This measures whether it did. On the current
metric the comparable figure reaches 41.6% for one player and sits above a third for four of
the top five, and if the replacement does not improve on that substantially, **the reframe has
not achieved its central purpose** and no amount of improvement elsewhere compensates.

**[Open]** What threshold counts as acceptable is not decided and should be written down
before the number is seen, not after.

### Check 3 — the noise floor

Split each player's season into halves at random, compute the score on each, and correlate.

This establishes how much of the score is signal at all. Every other correlation in the
project — against position, volume, entropy, the old score — is uninterpretable without it,
because a metric with a low split-half correlation cannot correlate strongly with anything and
a metric with a high one is expected to. **The current project has never had this number for
any of its metrics**, which is a gap the reframe should close rather than inherit.

---

## 9. The limitation that survives everything

**[Settled] Efficiency is held fixed while shots move. The estimated gain is therefore an
upper bound, and it is optimistic.**

Shooting more from a spot invites the defence to take that spot away. A player who currently
converts 60% on a moderate volume of shots from one area will not hold 60% at triple the
volume, because the marginal shots are the contested ones the defence was previously willing
to concede, and because a defence that has seen the tendency adjusts to it. The reframe's
counterfactual is smaller and more plausible than the old metric's, which is the whole point of
Section 2, but it is the same *kind* of counterfactual and it inherits the same blind spot.

**[Settled] This cannot be estimated from the shot log.** Quantifying it needs defender
distance, shot-clock state, or possession context — none of which the public NBA Stats API
provides per shot. CLAUDE.md Section 12 records that `CLOSE_DEF_DIST` was tested across every
`context_measure_simple` value and the 24-column schema contains location and outcome only, and
that `PlayerDashPtShots` offers bucketed player-level aggregates that cannot be joined to
individual shots. **That avenue is closed** and no amount of modelling reopens it.

The honest framing for any writeup: the score is the gain available *if the shots were as good
as the ones he already takes there*, which they will not entirely be. **Document it as a
ceiling. Do not attempt to discount it by an assumed factor** — an invented adjustment is worse
than a stated limitation, because it looks like a correction and is a guess.

This is the same treatment CLAUDE.md Section 17 already gives free throws, the volume
gradient, and the endogeneity of efficiency and frequency: labelled, not corrected.

---

## 10. Open items

**[Open] Grid resolution.** Undecided, and it is the parameter everything else is sensitive to.
Too coarse and the spatial model has nothing to do that the ten zones did not already do. Too
fine and every cell is empty, the estimate is all prior, and Check 2 fails by construction.
Entropy in Section 4 is resolution-dependent, and Section 6's rejection of a smoothed baseline
assumes a resolution at which the raw vector is not degenerate. **Nothing downstream can be
finalised before this is settled**, and it should be settled empirically — by the held-out
log-loss of Section 5 across candidate resolutions — rather than by picking a round number.

**[Open] No pre-registration exists.** The zone change had `ZONE_MODEL_ACCEPTANCE.md`,
committed before the pipeline was touched, with fail thresholds fixed in advance so that
results could not be retrofitted into acceptability. **The reframe has no equivalent and needs
one before implementation starts.** It is a harder document to write, because the reframe
deliberately changes what the metric measures, so most of the zone change's criteria —
"nothing important moves" — are inapplicable or actively wrong here.

**[Settled] And the inversion is the thing to get right.** For the zone change, a rank
correlation of 0.998 against the old score was the headline pass: same metric, zones redrawn.
**For the reframe, a high rank correlation against the old score would mean it achieved
nothing.** If the new ordering closely reproduces the old one, the objections in Section 1
have not been addressed — they have merely been re-derived with more machinery. Any
pre-registration must set an *upper* bound on that correlation, not a lower one, and must
decide in advance what "different enough to be worth it, similar enough to be measuring
basketball" looks like. That is the hardest number in the document and it is not yet written.

**[Intent] Presentation shape.** Two charts side by side — current distribution against the
efficiency surface — with a relocation slider, the ten-zone table underneath for readable
numbers, and a small set of featured players alongside the full leaderboard. **This is
intention, not commitment.** It has not been sketched, tested on anyone, or checked against
what the Astro site can do. The slider in particular presumes the reader benefits from seeing
the relocation quantity vary, which is the same question Check 1 answers quantitatively — if
that check shows the ranking is insensitive to it, the slider is decoration and should go.

Note also that CLAUDE.md Section 18 reserves the site to the author. This project writes JSON
and SVG; it does not build components or decide layout, and this paragraph is a request, not a
specification.

---

## Handoff

**Where this sits.** The 14-zone to 10-zone change is complete and committed on branch
`zone-model-10`: five seasons rebuild from clean in nine seconds, byte-identically, all
pre-registered criteria passed, documentation current. Nothing in *this* document is built.

**What it specifies.** Replacing the selection score. The current metric asks what a player
would score shooting the league's distribution with his own efficiency. That needs his ability
where he has never shot — a third of the top five's score magnitude comes from cells with under
ten attempts, one player has seven of ten zones empty — and a poor score does not establish a
different diet was available: Durant's is dominated by one term implying he should triple his
rim rate. The replacement measures the gain from shifting attempts toward areas he is already
strongest in. Self-relative, no league counterfactual, no extrapolation.

**Decisions, all revisitable, each with its rejected alternative recorded.** No relocation cap
— the score is the rate of gain as relocation begins; a fixed percentage was rejected as
arbitrary, a calibrated one as unnecessary. Diversity is reported separately as entropy, so a
star who does everything is not penalised inside a metric about allocation. Estimation moves
from per-zone beta-binomials to a spatial model of **make probability**, value applied per cell
afterwards, because make probability is continuous across the arc and value-weighted quantities
are not; eFG% was proposed and rejected, being PPS scaled by half and banned by A3. The
neighbourhood crosses the arc, so a strong long-two shooter who avoids threes shows as a
pattern rather than being smoothed away. CAR and a Gaussian process both get tested, decided on
held-out log-loss, runtime reported but not decisive. `freq_pooled` stays raw in the score,
smoothed only for display.

**Before any score is trusted:** rank correlation across 10/20/30% relocation; the share of each
player's weight in zero-attempt cells; a split-half noise floor the project has never had.

**The limitation that survives:** efficiency is held fixed while shots move, so the ceiling is
optimistic — shooting more from your best spot invites the defence. Not estimable without
tracking data. Label it; do not discount it by a guess.

**Open:** grid resolution, which everything is sensitive to; no pre-registration yet;
presentation is intent. And the inversion that matters most — unlike the zone change, a **high**
rank correlation against the old score would mean the reframe achieved nothing.
