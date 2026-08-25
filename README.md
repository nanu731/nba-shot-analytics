# NBA Shot Selection

**Do NBA players take most of their shots from the spots where they score the most?**

Last season Stephen Curry scored 1.65 points for every shot he took from the left corner.
From the right wing behind the arc he scored 1.07. He took 33 shots from the corner and 171
from the wing.

That gap is the whole idea. Curry shoots better from one place than another, and he takes
five times more shots from the worse one. Some of that is defenses chasing him off the
corner. Some of it is choice.

This project measures that gap for 318 players a season, across five seasons and 1.09
million shots.

---

## Points per shot

Points per shot divides what a player scored from a spot by how many shots he took there.
A made three counts 3, a made two counts 2, a miss counts 0. Curry's 1.65 in the left corner
means 33 attempts turned into 54 points.

Most shooting stats answer a different question: what fraction went in. That works fine
until you compare a three to a layup, where the same percentage means different value.
Points per shot puts every spot on one scale, and the scale is the thing the game is scored
in.

The floor splits into 14 zones. The NBA already labels every shot with the zone it came
from, so this project uses those labels rather than drawing its own boundaries. The zones
match what you see on an NBA.com shot chart.

| Zone | Worth | 2025-26 shots |
|---|---|---|
| Restricted area | 2 | 62,253 |
| Paint, outside the restricted area (left / center / right) | 2 | 2,253 / 39,141 / 2,514 |
| Mid-range (5 zones, left to right) | 2 | 5,819 / 2,861 / 4,718 / 2,806 / 5,813 |
| Left corner three | 3 | 12,210 |
| Above the break (left / center / right) | 3 | 26,511 / 17,219 / 23,624 |
| Right corner three | 3 | 11,360 |

---

## The score

Take a player's shooting from each of the 14 zones and hold it fixed. Then ask what he
would average if he shot the same mix as a typical NBA player, and compare that to what he
actually averaged.

The difference is the score. Skill sits on both sides of the comparison and cancels out.
What survives is the choice of where to shoot.

A score of +0.06 means his shot selection is worth six extra points per hundred attempts,
given how well he shoots from each spot. A negative score means the reverse.

The score runs from roughly -0.12 to +0.29. League-wide, one standard deviation is 0.061.

---

## What the numbers say

### Who allocates well, 2025-26

| | Player | Score | Points per shot |
|---|---|---|---|
| 1 | Ryan Kalkbrenner | +0.286 | 1.50 |
| 2 | Rudy Gobert | +0.262 | 1.36 |
| 3 | Jaxson Hayes | +0.251 | 1.52 |
| ... | | | |
| 316 | T.J. McConnell | -0.093 | 1.11 |
| 317 | DeMar DeRozan | -0.117 | 1.04 |
| 318 | Kevin Durant | -0.118 | 1.18 |

Big men fill the top. Their job puts them at the rim, which is the most valuable spot on
the floor outside the corners. That much is unsurprising.

### The interesting part is inside each position

Position accounts for 18% of the variation in score. The other 82% separates players who
share a position.

Centers spread wider than the league does. Their standard deviation is 0.0848 against a
league figure of 0.061, running from -0.053 to +0.286. The metric tells centers apart more
sharply than it tells the league apart.

| Position | Best three | Worst three |
|---|---|---|
| Center | Kalkbrenner, Gobert, Hayes | Vučević, Adebayo, Embiid |
| Forward | Gafford, Antetokounmpo, Diabaté | Dončić, Murray, Durant |
| Guard | Payton II, Champagnie, Braun | Nembhard, McConnell, DeRozan |

Every row runs rim-finishers against players who drift out to mid-range. Compare players
to others at their position, not to the league.

### Scores fall as volume rises

Players taking 250 to 400 shots average +0.046. Above 900 shots they average -0.022. The
pattern holds in all five seasons and inside every position group.

Two explanations fit. A high-usage player creates late in the clock against a set defense
and takes what he can get. A role player shoots when he is open at the rim and passes
otherwise. Or the score is picking up usage rather than allocation. The shot log cannot
separate those, so the pattern is reported rather than corrected.

---

## How the numbers get built

### Handling small samples

Among 318 qualifying players there are 4,184 zone cells with at least one shot. 228 hold a
single attempt. A one-shot cell scores either 0.00 or 2.00 depending on whether the ball
went in, and neither number says anything about the player.

The fix pulls thin cells toward the league average for that zone, in proportion to how thin
they are. One attempt lands almost entirely on the league value. Two hundred attempts keep
almost all of the player's own. Statisticians call this shrinkage, and the version here
fits a beta-binomial prior per zone:

```
FG%_shrunk[p,z] = (makes[p,z] + a[z]) / (attempts[p,z] + a[z] + b[z])
PPS_shrunk[p,z] = point_value[z] * FG%_shrunk[p,z]
```

Priors get fitted per zone and per season. Three-point zones need far more evidence before
the estimate stabilizes (fitted weights of 237 to 560) than paint zones do (31 to 96),
which matches published work finding that three-point percentage takes around 750 attempts
to settle.

Zones where a player never shot return the league average, so empty cells need no special
case.

### The formula

```
S[p] = sum over zones of ( f[p,z] - f_league[z] ) * PPS_shrunk[p,z]
```

`f[p,z]` is the share of a player's shots from zone `z`. `f_league[z]` is the league's
share. Economists use this structure to separate composition effects from rate effects.

An earlier version used `sum of f[p,z] * PPS[p,z]`. That one collapses to total points over
total attempts, which is just overall points per shot. It would have ranked players by
scoring efficiency instead of shot selection. On this data it correlates 1.000 with raw
points per shot. The version above correlates 0.58.

Each zone's contribution gets stored, so any player's score breaks into which spots helped
and which hurt.

### Zone rules

Every zone holds shots of one point value, which means

```
PPS[player, zone] = point_value[zone] * FG%[player, zone]
```

and shrinking points per shot reduces to shrinking a percentage. That keeps the statistics
on solved ground.

Two sets of shots come out. Backcourt heaves (38 in 2025-26) are buzzer attempts, and the
NBA's own charts drop them too. And 20 shots carry a point value that contradicts their
zone label, sitting at 21 to 24 feet where the coordinate-derived zone and the scored
value disagree. Dropping them keeps the rule above exact. 219,102 attempts remain.

No zone gets filtered for low volume. A player who rarely shoots from somewhere is exactly
what the metric measures, so cutting thin cells would throw away the relevant data.
Shrinkage handles the noise.

### Who qualifies

20 games and 250 shots in a season. That is 318 players out of 582 in 2025-26.

250 is the 25th percentile of attempts among players clearing the games gate. A
shots-per-game requirement got tested and dropped: the 23 players it cut were mostly
rim-running big men playing real minutes, so it would have deleted a position rather than
low-impact players. Several of them ended up near the top of the leaderboard.

One caveat. Games counts appearances where a player took a shot, so someone who played
without shooting is undercounted.

---

## What this cannot tell you

**Free throws are missing.** Points per shot counts field goal attempts. A drive that draws
a shooting foul often records no attempt at all, so rim scoring gets undercounted and
players who draw fouls get penalized. Shot logs carry no free-throw records, so there is no
way to test the size of the effect from this data. A proxy test got designed and then
withdrawn: overweighting the restricted area is close to the largest positive term in the
formula, so a correlation there is what the math guarantees rather than evidence about
fouls.

**Volume and score move together.** Covered above. Both explanations predict the same
correlation, and the shot log cannot pick between them. Testing inside volume quartiles
narrowed it: the top quartile is negative in all five seasons, but the lower three flip
sign year to year, so the effect lives among high-volume players rather than running
through the whole range. Eight of the top 20 sit within 100 shots of the 250 cutoff, which
raises a question about that threshold, though the effect sitting at the other end of the
distribution argues against a pure cutoff artifact.

**Ability and frequency are not independent.** The formula treats zone shooting as fixed
skill. Research using marked spatial point processes finds players shoot better where they
shoot more, for around 80% of players studied. Whether that is selection or cause remains
unsettled.

**Concentration says nearly the same thing as the score.** A Herfindahl index of how
concentrated a player's shot diet is correlates 0.833 with the score, rising to 0.913
inside centers. That is a result on its own: players reach good allocation by leaning on
their best zone, not by being broadly good everywhere. It also rules out plotting score
against concentration, which would draw a diagonal line.

**The shrinkage weight is not pinned down, though the rankings are.** Three methods got
compared per zone: the beta-binomial fit, split-half reliability, and cross-validation. The
first and third agree (rank correlation 0.838). Split-half agrees with neither on levels.
All three diverge most in three-point zones, and those are not the thinnest zones, which
was the prediction and it failed.

The cross-validated loss surface there is flat. Extending the search to 20,000 found a
nominal minimum in every zone, but held-out loss stays within 0.01% of it across a range
spanning 450 to 20,000 for the center above-the-break zone. Cross-validation does not
contradict the beta-binomial fit so much as fail to distinguish it from anything else.

Rebuilding every score under all three weightings gives rank correlations of 0.995 to
0.9985. No player moves more than one league standard deviation. The largest shift is
0.015, a quarter of an SD. Between 20 and 52 players move more than ten rank places, all
of them in the crowded middle. The top five and bottom five hold under all three.

That happens because a score sums 14 zones, and each zone's weight is how far the player's
frequency sits from the league's. Where the shrinkage weight is least certain, that
frequency gap is smallest. Uncertainty in a cell does not reach the player.

**Positions come in three buckets.** The NBA publishes guard, forward, and center, not five
positions. Three qualifying players in 2025-26 appear on no end-of-season roster and show
as Unknown rather than getting dropped or guessed at. Position colors the charts and never
enters the math.

**The league baseline includes the players being measured.** High-volume players help
define the average they get compared to.

---

## Running it

Collection runs in Python, since `nba_api` is the client that reaches the NBA stats
endpoints reliably. Cleaning, shrinkage, scoring, charts, and export all run in R.

```bash
# Collection. Slow, and only needed the first time a season is pulled.
conda activate nba-analytics
python src/collect.py --seasons 2025-26

# Analysis. One season, several, or everything collected.
Rscript R/run_pipeline.R 2025-26
Rscript R/run_pipeline.R

# Diagnostics. Run once, not part of the pipeline.
Rscript R/validation.R
Rscript R/k_comparison.R
```

Shots come one team at a time with `player_id=0`, which returns a full team season in one
call. That is 30 calls a season instead of 550. Passing `team_id=0` looks like a
whole-league pull but truncates at 102,400 rows without saying so, and never gets used.

### Layout

```
R/                Analysis, numbered by pipeline order
src/              Python ingestion
data/raw/         Shot logs and rosters, partitioned by season
data/processed/   zone_stats, player_scores, zone_priors
export/charts/    SVG
export/data/      JSON for the site, regenerated by R/05
```

Three tables come out. `zone_stats` holds one row per player-zone, 14 per player including
the empty ones. `player_scores` holds one row per player. `zone_priors` holds one row per
zone.
