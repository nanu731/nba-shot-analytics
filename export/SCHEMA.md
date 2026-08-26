# export/data — current schema

Describes what `R/05_export_json.R` emits **as of the files currently on disk**
(`generated: 2026-08-26`). This is a description of present behaviour, not a specification of
intended behaviour. Where a field is named misleadingly or carries a subtlety, that is recorded
rather than corrected.

Verified by reading the emitted JSON, not only the generating code.

---

## Files

The export writes **one metadata file plus one file per season**, all flat (not pretty-printed),
into `export/data/`.

| File | Size | Contents |
|---|---|---|
| `meta.json` | 41 KB | Zone definitions, eligibility rules, metric descriptions, player search index |
| `season-2021-22.json` | 707 KB | 312 players |
| `season-2022-23.json` | 662 KB | 292 players |
| `season-2023-24.json` | 638 KB | 281 players |
| `season-2024-25.json` | 689 KB | 304 players |
| `season-2025-26.json` | 720 KB | 318 players |

Total 3.38 MB. Season files are written for every season present in
`data/processed/zone_stats/`, discovered from disk at run time; the list is not hardcoded.

`export/data/` is excluded from version control as a build artifact. `export/charts/` (SVG) is
committed and is a separate output, not covered here.

---

## meta.json

A single object, five keys.

| Key | Type | Notes |
|---|---|---|
| `generated` | string | Date the export ran, `YYYY-MM-DD`. No time, no timezone. From the system date at run time. |
| `seasons` | array of string | Every season present in this export, ascending. Format `"2021-22"`. |
| `eligibility` | object | Two integers: `min_games` (20) and `min_attempts` (250). Both gates must be met for a player to appear. These are hardcoded in the export, not read from the pipeline. |
| `metric` | object | Four prose strings — `score`, `pps`, `shrinkage`, `note` — describing the metric in words. Human-readable only; nothing parses them. |
| `zones` | array of 14 objects | The zone dictionary. See below. |
| `players` | object | Player search index, keyed by player id. See below. |

### meta.zones[]

**This is the lookup table for every `zone` value elsewhere in the export.**

| Key | Type | Notes |
|---|---|---|
| `zone` | string | **Stable identifier.** The key used by `zone` fields in season files. Derived from what the zone means, never from its position. Safe to hardcode, to key SVG paths off, and to persist. |
| `name` | string | Full NBA zone name, e.g. `"Above the Break 3 | Center(C)"` — `SHOT_ZONE_BASIC` and `SHOT_ZONE_AREA` joined with `" | "`. Display text; do not key off it. |
| `value` | integer, 2 or 3 | Point value of every shot in this zone. |

The 14 ids, in the array's canonical basket-outward order:

| `zone` | `name` | Points |
|---|---|---|
| `restricted_area` | Restricted Area \| Center(C) | 2 |
| `paint_left` | In The Paint (Non-RA) \| Left Side(L) | 2 |
| `paint_center` | In The Paint (Non-RA) \| Center(C) | 2 |
| `paint_right` | In The Paint (Non-RA) \| Right Side(R) | 2 |
| `midrange_left` | Mid-Range \| Left Side(L) | 2 |
| `midrange_left_center` | Mid-Range \| Left Side Center(LC) | 2 |
| `midrange_center` | Mid-Range \| Center(C) | 2 |
| `midrange_right_center` | Mid-Range \| Right Side Center(RC) | 2 |
| `midrange_right` | Mid-Range \| Right Side(R) | 2 |
| `corner3_left` | Left Corner 3 \| Left Side(L) | 3 |
| `arc3_left_center` | Above the Break 3 \| Left Side Center(LC) | 3 |
| `arc3_center` | Above the Break 3 \| Center(C) | 3 |
| `arc3_right_center` | Above the Break 3 \| Right Side Center(RC) | 3 |
| `corner3_right` | Right Corner 3 \| Right Side(R) | 3 |

**Array order is display order, not identity.** The array is ordered basket-outward and that
order is stable, but **never use array position as an identifier** — resolve by the `zone`
string. An earlier version of this export keyed zones by integer index; if the zone model had
changed, the same integer would have meant a different zone with nothing raising an error.

**`zone` contains no geometry.** It is an identifier only. See the note at the end of this
document.

### meta.players

The search index. An object keyed by player id as a string, so the picker can search every
player without downloading a season file.

| Key | Type | Notes |
|---|---|---|
| *(key)* | string | The player id, as a string because JSON object keys are strings. Parse to integer to match `players[].player_id` in season files, which is a number. |
| `name` | string | Display name. |
| `seasons` | array of string | Every season in which this player qualifies, ascending. |

538 players across the five seasons. Example:

```json
"201939": { "name": "Stephen Curry", "seasons": ["2021-22", "2022-23", "2023-24", "2024-25", "2025-26"] }
```

**Names are display text only. Every join goes on the id.** A player's name is not stable
across seasons: `202685` appears as "Jonas Valančiūnas" in four seasons and "Jonas Valanciunas"
in 2025-26, and `1626171` changes from "Bobby Portis" to "Bobby Portis Jr.". This index carries
the **most recent** name. Ids are stable — 376 of the 538 players appear in two or more seasons
and no id ever refers to two different people, and no name maps to two ids in the current data.

---

## season-YYYY-YY.json

A single object, four keys: `season`, `priors`, `baselines`, `players`.

| Key | Type | Notes |
|---|---|---|
| `season` | string | Repeats the season, e.g. `"2025-26"`. Redundant with the filename. |

### priors[] — 14 objects, one per zone

The fitted shrinkage parameters for this season. Ordered by `zone` ascending.

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | string | — | Stable zone id; resolve through `meta.zones`. |
| `alpha` | number, 3 dp | pseudo-makes | Beta-binomial α for this zone-season. |
| `beta` | number, 3 dp | pseudo-misses | Beta-binomial β. |
| `k` | number, 2 dp | pseudo-attempts | `alpha + beta`. The shrinkage strength: effectively the number of league-average attempts added to every player's record in this zone. Ranges 31 to 560 in 2025-26. |
| `prior_mean` | number, 4 dp | proportion 0–1 | `alpha / k`. The fitted league field-goal percentage for this zone. Note this is the *fitted* value and can differ slightly from the raw pooled percentage. |
| `qualifying_attempts` | integer | shots | Attempts in this zone by **qualifying players only**, not the whole league. For 2025-26 restricted area it is 54,217; the league-wide figure including non-qualifying players is 62,253. Renamed from `league_attempts` on 2026-08-26, which claimed the wrong population. |
| `converged` | boolean | — | `true` if the maximum-likelihood fit converged. |
| `method` | string | — | `"vglm"` (maximum likelihood) or `"moments"` (method-of-moments fallback). Across all 70 zone-seasons: 67 `vglm`, 3 `moments`. `converged` is `false` exactly when `method` is `"moments"`. |

### baselines[] — 14 objects, one per zone

The league shot distribution, which is the comparison point in the score formula.

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | string | — | Stable zone id; resolve through `meta.zones`. |
| `freq_pooled` | number, 5 dp | proportion 0–1 | Total qualifying-pool attempts in this zone ÷ total qualifying-pool attempts. **This is the primary baseline** and the one used to compute `score`. Sums to exactly 1.00000 across the 14 zones. |
| `freq_unweighted` | number, 5 dp | proportion 0–1 | The mean across players of each player's own share. Used only for `score_unweighted`. Does not correspond to any actual shot distribution. |

This block exists so the baseline vector is carried once per season rather than repeated inside
every player object.

### players[] — one object per qualifying player

**Sorted by `score` descending.** Index 0 is the season's highest-scoring allocator.

| Key | Type | Units | Notes |
|---|---|---|---|
| `player_id` | integer | — | NBA's official player ID. See §Player identity below. |
| `name` | string | — | Display name as delivered by the NBA for that season. |
| `position` | string or **null** | — | Raw NBA roster position. Observed values across all seasons: `C`, `C-F`, `F`, `F-C`, `F-G`, `G`, `G-F`. **`null` means the player appears on no end-of-season roster** — 8 occurrences across the five seasons. |
| `pos3` | string | — | Three-way bucket derived from `position` by taking the text before any hyphen. Values `C`, `F`, `G`, or `Unknown`. **Never null**; `"Unknown"` is used where `position` is null. Display variable only — never an input to any calculation. |
| `games` | integer | games | Games in which the player attempted at least one shot. **Not true games played** — a player who appeared without shooting is undercounted. |
| `attempts` | integer | shots | Total field goal attempts, after cleaning. Excludes backcourt shots and 20 label-contradiction shots per season. |
| `zones_used` | integer 0–14 | zones | Count of zones with at least one attempt. Observed minimum is 4. |
| `pps` | number, 4 dp | points per shot | Overall raw points per shot: total points ÷ total attempts. **Not shrunk.** |
| `score` | number, 5 dp | points per shot | **The headline selection score**, pooled baseline. Signed; roughly −0.12 to +0.29. Positive means the player's allocation of shots adds value given his own abilities. |
| `score_unweighted` | number, 5 dp | points per shot | Same formula against `freq_unweighted`. A robustness check; correlates 0.9996–0.9998 with `score`. |
| `herfindahl` | number, 4 dp | index 0–1 | Sum of squared shot frequencies. Concentration of the shot diet. Floor is 1/14 ≈ 0.071 (perfectly even); 1.0 would be every shot from one zone. |
| `zones` | array of 14 objects | — | Always exactly 14, in the same basket-outward order as `meta.zones`, including zones with no attempts. |

### players[].zones[] — 14 objects per player

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | string | — | Stable zone id; resolve through `meta.zones`. |
| `makes` | integer | shots | Made field goals. `0` when the player never shot here. |
| `attempts` | integer | shots | Field goal attempts. `0` when the player never shot here. |
| `fg_pct` | number, 4 dp or **null** | proportion 0–1 | Raw field goal percentage. **`null` when `attempts` is 0** — no shots means no observed rate, which is distinct from a rate of zero. 268 nulls in 2025-26. |
| `pps` | number, 4 dp or **null** | points per shot | Raw points per shot, `value × fg_pct`. **`null` when `attempts` is 0**, same reasoning. |
| `freq` | number, 4 dp | proportion 0–1 | This player's share of his own attempts taken from this zone. `0` when he never shot here — this is a genuine zero, not an absence, so it is not null. Sums to 1 across the 14 zones **up to rounding**: observed drift up to ~2×10⁻⁴ because each value is rounded to 4 dp independently. |
| `fg_pct_shrunk` | number, 4 dp | proportion 0–1 | Shrunk field goal percentage. **Never null.** At `attempts = 0` this equals the zone's `prior_mean` exactly, which is the intended behaviour. |
| `pps_shrunk` | number, 4 dp | points per shot | `value × fg_pct_shrunk`. **Never null**, for the same reason. |
| `contrib` | number, 5 dp | points per shot | This zone's contribution to the player's score: `(freq − freq_pooled) × pps_shrunk`. Signed. Negative for zones the player is underweight in relative to the league, even where he shoots well. **Does not sum exactly to `score` in this file** — see the rounding caveat below. |

---

## Cross-cutting notes

**Rounding.** Every numeric field is rounded at export: 2 dp for `k`; 3 dp for `alpha` and
`beta`; 4 dp for percentages, points-per-shot values, `freq`, and `herfindahl`; 5 dp for
`score`, `score_unweighted`, `contrib`, and the two baseline frequencies. Full precision exists
only in the Parquet files under `data/processed/`, which are committed to the repository but
are not part of this export.

**Do not recompute `score` by summing `contrib`.** In the underlying Parquet the per-zone
contributions sum to the player's score exactly, to zero difference at double precision. **In
this export they do not.** Each of the 14 contributions is rounded to 5 dp independently and
`score` is rounded separately, so the two disagree in the fourth decimal place. Measured across
all 1,507 player-seasons the maximum disagreement is **3.0 × 10⁻⁴** (Trayce Jackson-Davis,
2023-24); it is nonzero for most players.

Display the shipped `score`. Use `contrib` for the per-zone breakdown — which zones help and
which hurt, and by roughly how much. A bar chart of `contrib` values will not add up to the
headline number, and should not be presented as though it does. If exact reconciliation is ever
needed, the fix belongs in the export (emit unrounded values, or derive `score` from the rounded
contributions so the two agree by construction), not in the consuming site.

**`freq` has the same property** for the same reason: the 14 per-zone frequencies are each
rounded to 4 dp, so they sum to 1 only up to about 2 × 10⁻⁴ rather than exactly.

**Null semantics, summarised.** Only three fields are ever null. `zone.fg_pct` and `zone.pps`
are null exactly when `attempts = 0`, meaning "no observation". `player.position` is null when
the player is absent from the end-of-season roster. Everything else is always present.

**What is not exported.** Nothing shot-level. No coordinates (`LOC_X`, `LOC_Y`), no `GAME_ID`,
no `ACTION_TYPE`, no per-shot rows of any kind. The finest grain in the export is the
player-zone cell. No team identifiers appear anywhere. No dates beyond `meta.generated`.

**Ordering invariants that currently hold**, though nothing in the format enforces them:
`players` is sorted by `score` descending; each player's `zones` array is in `meta.zones`
order with all 14 present; `priors` and `baselines` are in `meta.zones` order.

---

## Delivering the export to the website

`R/06_sync_to_site.R` copies every JSON file from `export/data/` into the website
repository, which is a separate git repo. It **only copies**; committing on the website side
stays manual, so a bad export never lands in the site's history unreviewed.

The destination is read from the `SHOT_SELECTION_SITE_DIR` environment variable, defaulting
to `/Users/narayanlekhi/projects/portfolio-site/public/data/shot-selection/`. The default is
documented rather than hardcoded so the script runs on another machine:

```bash
Rscript R/06_sync_to_site.R                                    # uses the default
SHOT_SELECTION_SITE_DIR=/other/path Rscript R/06_sync_to_site.R
```

**It will not create the destination directory.** If the path does not exist the script stops
with an error naming the path and the variable. Creating it silently would let a typo in the
variable produce a new folder that nothing serves, while the copy still looked like it
succeeded. It prints every file written and its size.

---

## Zone geometry

**The export contains no geometry, and neither does the repository.**

Zones are identified by the NBA's own two label columns, concatenated. Nothing in the pipeline
derives a zone from coordinates, and nothing defines where a zone sits on a court. There are no
polygons, no boundary definitions, no vertex lists, and no GeoJSON anywhere in the project. A
repository-wide search for polygon, vertex, boundary, and classifier constructs returns nothing
of that kind.

The static charts do draw a court, in `court_layer()` in `R/04_charts.R`. That function emits
seven ggplot annotations in NBA shot-chart units (tenths of a foot, hoop at the origin): the hoop
circle (radius 7.5), the backboard, the paint rectangle (±80 wide, −52.5 to 137.5), the
free-throw circle (radius 40), the two corner-three straight segments at x = ±220, the
three-point arc (radius 237.5), and the baseline. **These are court furniture, not zone
outlines.** No two of them bound a zone.

The only zone-positional information anywhere is `zone_anchors()` in the same file, which
computes the **median shot position per zone** from raw shot data to place a text label. That is
one point per zone, computed at run time, cached in memory, and never written to any file.

Consequence for a consuming site: zone outlines cannot be obtained from this repository in any
form. They would have to be authored independently.
