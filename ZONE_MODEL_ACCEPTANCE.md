# Acceptance criteria: 14 NBA zones → 10 computed zones

**Pre-registered 2026-08-27, on branch `zone-model-10`, before any new number exists.**

Written and committed before step 4 of the plan — before the pipeline has been rewired, before
any prior has been refitted, before any leaderboard has been regenerated. The point is that
once results exist it is too easy to decide, after the fact, that whatever appeared was
acceptable. These thresholds are fixed now and are not to be moved to accommodate an outcome.

If a criterion fails, the honest response is to report the failure and stop, not to adjust the
criterion. A failed criterion does not automatically mean reverting — it means the change
cannot be presented as preserving the project's central claims, and the writeup would have to
say so plainly.

---

## What the change must not break

The project's central defence of the metric is that it measures **shot allocation**, not
position. Two results carry that defence:

1. **Position explains little of the score.** Currently R² = 0.178 for 2025-26, range
   0.156–0.204 across five seasons. Stated in the README as "position explains only about 18
   percent of the variance", with the corollary that 82 percent is within position.
2. **The metric separates players inside a position.** Centres currently have a within-group
   SD of 0.0848 against a league-wide SD of 0.061 — **139 percent**. Forwards 96 percent,
   guards 69 percent. This is the stronger of the two, because it is what makes the extremes
   basketball-legible rather than a positional sort.

A redrawn zone model that made the score *more* determined by position would weaken both,
because merging zones could plausibly concentrate the rim-versus-perimeter distinction that
tracks position most closely.

---

## Criterion 1 — Position variance (R²)

Measured on 2025-26 with `POS3` (reported positions only, never `POS3_DISPLAY`), C/F/G only,
excluding `Unknown`, exactly as `R/validation.R` computes it today.

| Outcome | Threshold | Response |
|---|---|---|
| **Pass** | R² ≤ 0.25 | The claim survives. Restate the number if it moved at all. |
| **Warn** | 0.25 < R² < 0.35 | The claim survives in weakened form. The README must say "explains roughly a quarter/third" and must not keep the "only 18 percent" framing. Flag prominently. |
| **Fail** | **R² ≥ 0.35** | The new zones are materially more position-determined. Report and stop. |

**Why 0.35.** At R² = 0.35 the within-position share falls from 82 to 65 percent. The
argument "this measures allocation, not role" rests on within-position variance dominating,
and a claim that two-thirds dominates one-third is much weaker than five-sixths to one-sixth.
Doubling the current value is also well outside the 0.156–0.204 spread the metric already
shows across seasons, so it could not be dismissed as ordinary season-to-season movement.

**Also checked, and failing on its own:** if the mean R² across all five seasons is ≥ 0.35,
that is a fail even if 2025-26 alone squeaks under. One season is not the result.

---

## Criterion 2 — Within-position discrimination

Within-group SD of `score_pooled`, as a percentage of the league-wide SD, 2025-26.

| Outcome | Threshold | Response |
|---|---|---|
| **Pass** | At least one group ≥ 110% | The metric still separates within position more sharply than across the league. |
| **Warn** | Best group 100–110% | Survives, materially weakened, must be restated. |
| **Fail** | **No group reaches 100%** | The metric no longer discriminates within position better than league-wide. Report and stop. |

**Why 100 percent.** This is the threshold at which the claim inverts. If every position group
is *less* spread than the league as a whole, then the league-wide spread is being driven by
between-position differences, which is precisely the "it just detects position" objection the
project exists to answer.

Centres are currently 139 percent and are the group expected to carry this.

---

## Criterion 3 — Leaderboards: shifting versus not surviving

The finding is not that Kalkbrenner ranks first. It is that the extremes are
basketball-legible: rim-concentrated finishers at the top, mid-range-heavy scorers at the
bottom. Ordering may move; character may not.

Old top five, 2025-26: **Kalkbrenner, Gobert, Hayes, Robert Williams III, Kornet.**
Old bottom five: **Durant, DeRozan, McConnell, Nembhard, Keegan Murray.**

### 3a. Rank correlation, old score against new score

Same 318 players, Spearman.

| Outcome | Threshold | Response |
|---|---|---|
| **Pass** | ρ ≥ 0.90 | The same metric, zones redrawn. |
| **Warn** | 0.75 ≤ ρ < 0.90 | Materially different ordering. Report the movers and explain them before proceeding. |
| **Fail** | **ρ < 0.75** | This is a different metric wearing the same name. Report and stop. |

**Why 0.75.** Below that, roughly half the rank information is not shared, and no honest
writeup could present five seasons of prior conclusions as still applying.

### 3b. Extremes retain identity

| Outcome | Threshold |
|---|---|
| **Pass** | At least 3 of the old top 5 appear in the new top 10, and at least 3 of the old bottom 5 in the new bottom 10 |
| **Fail** | **Fewer than 3 at either end** |

### 3c. Character, not just membership

Operationalised so it cannot be argued either way after the fact:

- The new top 5 must have **mean combined rim + paint frequency above the league median**.
- The new bottom 5 must have **mean combined mid-range frequency above the league median**.

**Fail if either does not hold.** If the top of the board stops being rim-concentrated
players, the interpretation printed throughout the README is no longer describing what the
metric ranks, whoever happens to be listed.

---

## Criterion 4 — Mechanical regressions (any failure stops the run)

These are not judgment calls. Any one of them failing means a bug, not a finding.

- Raw shots per season unchanged: 216,722 / 217,220 / 218,700 / 219,527 / **219,160**.
- Qualifying players unchanged: 312 / 292 / 281 / 304 / **318**. Redrawing zones must not
  change who qualifies, since eligibility is on total attempts and games.
- Total shots dropped for point-value disagreement across five seasons: **exactly 407**.
- Every real coordinate classifies to exactly one zone; none to zero, none to two.
- Left/right symmetry within ~10 percent on mirrored pairs: `mid_left` 29,757 vs `mid_right`
  29,945; `corner3_left` 58,364 vs `corner3_right` 53,415.
- Grid rows for 2025-26: 318 × 10 = **3,180**.
- Polygons agree with the classifier: zero disagreements, zero orphans, zero overlaps.

---

## What I expect, recorded so it can be held against the outcome

Stating the expectation now, because a prediction made in advance is falsifiable and a
prediction made afterwards is not.

I expect **all criteria to pass**. Specifically I expect R² to land between 0.15 and 0.25,
probably slightly above the current 0.178 because merging the paint zones concentrates a
rim-versus-perimeter distinction that tracks position. I expect centres to remain the
widest-spread group at over 120 percent of league SD. I expect ρ ≥ 0.95, since the zone
boundaries move but the underlying allocation being measured does not. I expect four or five
of the old top five to remain in the new top ten.

**If R² lands above 0.25 I will report it as the warning it is**, not as a minor restatement.
**If any criterion fails I will report the failure and stop**, per the plan's step 4, before
any documentation is touched.

---

## Scope note

This file governs the zone model change only. It is not a general standard for the project and
should not be cited as one. Once the change is either accepted or abandoned, this file records
what the bar was, and stays in the repository for that reason.
