# NBA Shot Selection

**Do NBA players take most of their shots from the zones where they generate the most points?**

Not a question about who shoots well. A question about *where* players choose to shoot,
given how well they shoot from each place on the floor. A player can be an excellent
shooter and still allocate his attempts badly, and a limited scorer can allocate them
almost perfectly.

Five seasons, 2021-22 through 2025-26. Roughly 1.09 million field goal attempts.

---

## The metric: points per shot

PPS is total points generated in a zone divided by field goal attempts in that zone. A
made two is worth 2, a made three is worth 3, a miss is worth 0.

**Why PPS rather than eFG%.** Effective field goal percentage is a rescaled shooting
percentage — it answers "what fraction of shots went in, counting threes as worth more."
The question here is about points, and PPS states the answer in the units the question is
asked in. A player generating 1.15 points per attempt from above the break and 0.87 from
mid-range does not need that translated into a percentage to be understood. Nothing in this
project uses eFG%.

PPS also has a property that makes the statistics tractable. Every zone contains shots of
exactly one point value, so

```
PPS[player, zone] = point_value[zone] × FG%[player, zone]
```

which means shrinking PPS reduces exactly to shrinking a binomial proportion — a solved
problem — rather than requiring a bespoke estimator.

---

## The zone model: 14 zones, taken from the NBA

Zones are not derived, computed, or classified here. The NBA already classified every shot.
The raw shot log carries `SHOT_ZONE_BASIC` and `SHOT_ZONE_AREA`, and the zone key is those
two columns concatenated:

| Zone | Points | 2025-26 attempts |
|---|---|---|
| Restricted Area, Center | 2 | 62,253 |
| In The Paint (Non-RA), Left / Center / Right | 2 | 2,253 / 39,141 / 2,514 |
| Mid-Range, Left / Left-Center / Center / Right-Center / Right | 2 | 5,819 / 2,861 / 4,718 / 2,806 / 5,813 |
| Left Corner 3 | 3 | 12,210 |
| Above the Break 3, Left-Center / Center / Right-Center | 3 | 26,511 / 17,219 / 23,624 |
| Right Corner 3 | 3 | 11,360 |

These reproduce the NBA.com shot chart exactly, which is a stronger claim than approximating
it with hand-drawn boundaries.

**Two exclusions.** Backcourt heaves are dropped — 38 shots in 2025-26, all buzzer attempts,
which the NBA's own charts also exclude. And 20 shots carry a `SHOT_TYPE` contradicting their
zone's point value: twelve labelled *Above the Break 3* were scored as two-pointers, eight
labelled *Mid-Range* as threes. All sit at 21 to 24 feet, where the coordinate-derived zone
label and the scored point value disagree. They are dropped so that point-homogeneity holds
exactly. That leaves 219,102 attempts in 2025-26.

**No zone-level minimum.** Every zone where a player took at least one shot is included, and
zones where he took none are carried as zero-attempt cells. Low volume in a zone is precisely
the signal the metric measures; filtering thin cells would discard the most relevant data.
Sampling noise is handled by shrinkage, not by exclusion.

---

## Eligibility

A player qualifies in a season with **20 or more games** and **250 or more field goal
attempts**. In 2025-26 that is 318 players out of 582.

250 is the 25th percentile of total attempts among players clearing the 20-game gate
(235.75, rounded). A shots-per-game gate was considered and rejected: the 23 players it
excluded were disproportionately rim-running centres playing genuine rotation minutes, so it
would have deleted a position group rather than low-impact players. Those players turn out to
be among the most interesting cases in the analysis.

One caveat worth stating: `games` counts games in which a player attempted a shot, not true
games played, so a player who appeared without shooting is undercounted.

---

## Shrinkage: beta-binomial empirical Bayes

Among the 318 qualifying players there are 4,184 player-zone cells with at least one attempt.
228 contain a single attempt and 629 contain three or fewer. A one-attempt cell produces a PPS
of either 0 or 2 on a coin flip. Without correction, part of what the metric measures is luck.

For each of the 14 zones independently, a beta-binomial is fitted to the (makes, attempts)
pairs across qualifying players, giving `α[z]` and `β[z]`:

```
FG%_shrunk[p,z] = (makes[p,z] + α[z]) / (attempts[p,z] + α[z] + β[z])
PPS_shrunk[p,z] = point_value[z] × FG%_shrunk[p,z]
```

Priors are fitted **per zone and per season** — the qualifying pool and the shooting
environment both change year to year, and different zones have different between-player
variance, so a single shrinkage weight would over-shrink some zones and under-shrink others.
At zero attempts the formula returns exactly the prior mean, so empty cells need no special
handling.

The fitted weights `k = α + β` are far larger for three-point zones (237 to 560) than for
paint zones (31 to 96), consistent with published findings that three-point percentage takes
roughly 750 attempts to stabilise.

---

## The score: a shift-share decomposition

```
S[p] = Σ over zones of ( f[p,z] − f_league[z] ) × PPS_shrunk[p,z]
```

where `f[p,z]` is the share of the player's attempts taken from zone `z`, and `f_league[z]`
is the league's pooled share.

Read plainly: the difference between what a player actually generates per shot and what he
would generate with his own zone-by-zone abilities but a league-typical shot diet. Because
`PPS_shrunk[p,z]` appears identically in both counterfactuals, shooting ability cancels and
only allocation remains. Units are points per shot: a score of +0.06 means the player's shot
choices are worth six extra points per hundred attempts, given his abilities.

This is the structure economists use to separate composition effects from rate effects.

**A formula that was tried and rejected**, because it is instructive: `Σ f[p,z] × PPS[p,z]`
collapses algebraically to total points over total attempts — it is just overall points per
shot, and would have ranked players by scoring efficiency rather than by shot selection. On
the current data it correlates 1.000 with raw overall PPS. The shift-share version correlates
0.58.

Each zone's term is retained, so any player's score breaks down into which zones helped and
which hurt.

---

## Findings

### The best and worst allocators, 2025-26

| | Player | Score | Overall PPS |
|---|---|---|---|
| 1 | Ryan Kalkbrenner | +0.286 | 1.50 |
| 2 | Rudy Gobert | +0.262 | 1.36 |
| 3 | Jaxson Hayes | +0.251 | 1.52 |
| … | | | |
| 316 | T.J. McConnell | −0.093 | 1.11 |
| 317 | DeMar DeRozan | −0.117 | 1.04 |
| 318 | Kevin Durant | −0.118 | 1.18 |

### The metric discriminates within position, not just between positions

Centres score higher on average than guards, which is unsurprising: their role concentrates
attempts at the rim, the highest-PPS zone. But position explains only **R² = 0.178** of the
variance in score. The other 82% is within position.

Within-group spread makes the point sharply. Centres have a standard deviation of 0.0848 —
**139% of the league-wide standard deviation of 0.061** — spanning −0.053 to +0.286. The
metric separates centres from one another more sharply than it separates the league as a
whole.

The within-position extremes are basketball-legible, which is the strongest evidence the
metric is measuring allocation rather than role:

| Position | Best | Worst |
|---|---|---|
| C | Kalkbrenner, Gobert, Hayes | Vučević, Adebayo, Embiid |
| F | Gafford, Antetokounmpo, Diabaté | Dončić, Murray, Durant |
| G | Payton II, Champagnie, Braun | Nembhard, McConnell, DeRozan |

Every panel runs rim-finishers at the top against players who drift to mid-range at the
bottom. **Within-position comparisons are the meaningful ones**, and the primary chart is
faceted accordingly.

### Score falls as shot volume rises

Mean score by volume band in 2025-26: **+0.046** at 250–400 attempts, **+0.022** at 400–600,
**+0.011** at 600–900, **−0.022** above 900. Overall correlation −0.386, stable at −0.37 to
−0.39 across all five seasons, and it holds within every position group.

This is discussed as a limitation below rather than corrected away.

---

## Limitations

**Free throws.** PPS counts field goal attempts only. A drive that draws a shooting foul often
records no attempt at all, so restricted-area PPS understates the value of attacking the rim
and the metric may penalise foul-drawing players. This is untestable from shot-log data, which
carries no free-throw records. A proposed proxy — correlating score against restricted-area
frequency — was designed and then withdrawn as invalid: overweighting the restricted area is
close to the largest positive term in the score by construction, so a high correlation is what
the formula guarantees rather than evidence about free throws.

**Shot volume.** Two readings, and the shot log cannot separate them. Either high-usage players
genuinely face harder shots by necessity — creating late in the clock, from everywhere, against
a set defence, while a role player shoots only when open at the rim — in which case the
gradient is a real effect the metric captures correctly. Or the score is partly measuring
offensive usage rather than allocation quality. Both mechanisms predict the same correlation.

A partial test: correlating score against volume *within* each volume quartile. The top quartile
is negative in all five seasons, but the lower three flip sign season to season, so the effect
sits among high-volume players rather than running smoothly through the range. Eight of the top
20 scorers sit within 100 shots of the 250-attempt eligibility gate, which bears on whether that
threshold does more work than intended — though the gradient living at the opposite end of the
distribution argues against a pure threshold artifact.

**Endogeneity of ability and frequency.** The formula treats zone PPS as a fixed skill
parameter, but the two are not independent — research using marked spatial point processes finds
a positive association between shot accuracy and shot intensity for about 80% of players, meaning
players shoot better where they shoot more. Whether that is selection or causation is unsettled.

**Concentration is nearly redundant with the score.** A Herfindahl index of shot-diet
concentration correlates 0.833 with the selection score, and the redundancy *increases* within
position (0.913 for centres). That is itself a result: players do not reach good allocation by
being broadly good, they reach it by concentrating on their best zone. It also means a
score-against-concentration scatter is close to a diagonal, so it is not used as the primary
visual.

**Shrinkage weight is not sharply identified everywhere — but the rankings are.** Three
independent methods were compared per zone: the beta-binomial MLE, split-half reliability, and
cross-validation. The MLE and cross-validation agree closely (rank correlation 0.838); split-half
agrees with neither on levels. All three disagree most in the three-point zones, and those are
not the thinnest zones — the prediction that they would be was tested and failed.

The cross-validated loss surface there is genuinely flat rather than merely unbounded. Extending
the search grid to 20,000 produced a nominal minimum in every zone, but held-out loss stays within
0.01% of that minimum across a range spanning 450 to 20,000 for the centre above-the-break zone.
The weight is not identified, and the MLE's estimate falls inside that interval — cross-validation
does not contradict it so much as fail to discriminate.

**What that costs the results: almost nothing.** Rebuilding every player's score under all three
weight vectors gives rank correlations of 0.995 to 0.9985. No player moves more than one league
standard deviation (0.061); the largest shift under any pairing is 0.015, a quarter of an SD.
Twenty to fifty-two players out of 318 move more than ten rank places, all in the middle of the
distribution. **The top five and bottom five are identical under all three weightings.**

The reason is structural: a score sums across 14 zones, and each zone's term is weighted by how
far the player's frequency departs from the league's, which is small precisely where the weight is
uncertain. Cell-level sensitivity does not propagate to the player score.

**Position granularity.** The NBA publishes three position buckets, not five. Three qualifying
players in 2025-26 appear on no end-of-season roster and are shown as `Unknown` rather than being
dropped or imputed. Position is a display variable only and is never a modelling input.

**Pooled baseline self-reference.** High-volume players partly define the league baseline they
are measured against.

---

## Running it

Collection is Python, because `nba_api` is the client that reliably reaches the NBA stats
endpoints. **Everything else — cleaning, shrinkage, scoring, charts, export — is R.**

```bash
# Collection. Slow, and only needed when a season is first pulled.
conda activate nba-analytics
python src/collect.py --seasons 2025-26

# Analysis. Stages 2 through 5 for one season, several, or all collected seasons.
Rscript R/run_pipeline.R 2025-26
Rscript R/run_pipeline.R

# One-off diagnostics, not part of the pipeline.
Rscript R/validation.R
Rscript R/k_comparison.R
```

Shots are collected one team at a time with `player_id=0`, which returns a team's full season
in a single call — 30 calls per season rather than roughly 550. Passing `team_id=0` looks like
a one-call whole-season pull but silently truncates at 102,400 rows, and is never used.

### Layout

```
R/            Analysis, numbered by pipeline order
src/          Python ingestion only
data/raw/     Shot logs and rosters, Hive-partitioned by season
data/processed/   zone_stats, player_scores, zone_priors
export/charts/    SVG
export/data/      JSON for the site (a build artifact; regenerate with R/05)
```

Output tables are `zone_stats` (one row per player-zone, 14 per player including zeros),
`player_scores` (one row per player), and `zone_priors` (one row per zone).
