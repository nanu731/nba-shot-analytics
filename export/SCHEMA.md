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
| `seasons` | array of string | Every season present in this export, ascending. Format `"2021-22"`. Always an array, including a single-season export. |
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
| `seasons` | array of string | Every season in which this player qualifies, ascending. **Always an array, with no exceptions** — a player qualifying in exactly one season gets a one-element array, not a bare string. Verified across all 538 entries. |

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
| `pos3` | string | — | Three-way bucket derived from `position` by taking the text before any hyphen. Values `C`, `F`, `G`, or `Unknown`. **Never null**; `"Unknown"` is used where `position` is null. **Reported data only** — this is the field any analysis of position must use. |
| `pos3_display` | string | — | `pos3`, with `Unknown` filled from listed height where possible. **Use this for labelling and colouring charts.** `C`, `F`, `G`, or `Unknown` if height was also unavailable. |
| `pos3_derived` | boolean | — | `true` where `pos3_display` came from the height rule rather than a roster. 8 of 1,507 player-seasons. Never `true` for a player the league listed. |
| `listed_height` | string or **null** | feet-inches | Height as the NBA lists it, e.g. `"6-10"`. Present for anyone appearing on any season's roster; `null` otherwise. Informational: it is the input to the height rule, not a measurement this project made. |
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

## Zone geometry reference and the polygon checker

`export/reference/` holds development aids for authoring the website's zone outlines. **The
site does not fetch this at runtime** — `export/data/` is the runtime payload; this directory
is for the person drawing shapes.

### `zone_grid.csv`

A spatial histogram of every labelled shot across all five seasons, binned into half-foot
cells. This is what the outlines get traced from.

| Column | Type | Notes |
|---|---|---|
| `x`, `y` | number | Cell **centre**, NBA shot-chart units (tenths of a foot, hoop at origin). Cells are 5 units square, so a cell covers `x ± 2.5`, `y ± 2.5`. |
| `zone_id` | string | Stable zone id, matching `meta.zones[].zone`. |
| `n` | integer | Shots from that zone in that cell, pooled across 2021-22 to 2025-26. |

7,902 rows over 7,508 distinct cells, 1,089,337 shots, 233 KB.

**One row per cell per zone.** Most cells hold a single zone and produce one row. **387 cells
hold two**, and those are exactly the cells a zone boundary passes through — they are the most
useful rows in the file, because they show where an edge runs rather than merely where a zone
is. A cell's rows summing across two zones is a feature, not a data error.

**Why a grid rather than the raw points.** Rule A16 forbids shot-level data leaving this
machine in any form, and a labelled point cloud is one row per shot. A binned histogram is a
derived aggregate: it carries no per-shot record, no player, no game, no outcome, and no
coordinate finer than half a foot. It is also the better artifact for the job — the zones are
non-convex (the arc zones are annular sectors) so convex hulls would be wrong, and a grid
traces a non-convex boundary directly.

If the full point cloud is genuinely needed for local work, generate it with
`labelled_shots()` in `R/07_zone_geometry.R` and keep it under `data/cache/`, which is
gitignored permanently. It must not be committed or copied into `export/`.

### `zone_polygons.json`

The 14 zone outlines, built by `R/08_zone_polygons.R`. **Verified against all 1,089,337
labelled shots with zero disagreements, zero orphans and zero overlaps** — every shot falls
inside exactly one polygon, and it is the polygon its NBA label names.

This file is **imported at build time**, not fetched by the browser. `R/06_sync_to_site.R`
copies it into the site's source tree, separately from the runtime payload in
`export/data/`.

53 KB, 3,153 vertices across 14 zones, 20 arc records.

#### Position: reported versus derived

Positions come from `CommonTeamRoster`, an end-of-season snapshot, so a player waived or
traded late can qualify on shots and appear on no roster. Eight player-seasons out of 1,507
have no listed position.

For those eight only, a bucket is derived from the player's listed height:

| Listed height | `pos3_display` |
|---|---|
| 6 ft 5.5 in and under | `G` |
| 6 ft 6 in to 6 ft 10 in | `F` |
| 6 ft 11 in and over | `C` |

Heights are listed in whole inches, so the guard ceiling is effectively 6 ft 5 in and the
forward band is 78 to 82 inches inclusive. Where a player is listed in several seasons, the
listing nearest the season being filled is used; no player's listings straddle a threshold.

**The rule applies only where `pos3` is `Unknown`.** A player the league listed keeps that
listing even where the height rule would disagree — and it does disagree in one case. Orlando
Robinson is 6 ft 10 in, which the rule calls a forward, and the league listed him a centre in
the seasons it listed him at all. He is derived `F` for 2024-25, the season with no listing.
Nothing overrides a reported value anywhere.

The eight: James Johnson and Drew Eubanks (2021-22), John Wall (2022-23), Killian Hayes
(2023-24), Orlando Robinson (2024-25), Jaden Ivey, Vince Williams Jr. and Cam Thomas
(2025-26).

**Why the derived value sits in its own field.** The project's defence of the metric is that
position explains only about 18 percent of the variance in selection score. If position were
filled in place from height, then for those players position *is* height, and that result
becomes partly circular. Keeping `pos3` reported-only means a chart can show a bucket for
everyone via `pos3_display` while any analysis of position uses `pos3` alone. `pos3_derived`
tells a reader which values came from a roster and which from a tape measure.

---

#### Coordinate system — read this before drawing anything

Units are **tenths of a foot**. The hoop is at the origin `(0, 0)`.

**x** increases to the **right**. Range across all vertices is −250.5 to 250.5, the sidelines.

**y** increases **away from the baseline, up the court**. Range is −52.5 (the baseline,
behind the hoop) to 430 (a bound comfortably past the furthest shot on record at y = 397).

**y is therefore inverted relative to SVG**, where y grows downward. A single group
transform such as `scale(1, -1)` handles the polygons. Text inside that transform renders
upside down, which is why `anchor` is given in data coordinates and expected to be passed
through the transform separately rather than being baked into the path data.

Angles, where they appear, are **degrees, measured from the +x axis, counter-clockwise**.
0° points right, 90° points up the court, 180° points left.

#### Per-zone keys

Keyed by stable zone id, the same ids used by `meta.zones[].zone` in the runtime export.

| Key | Type | Notes |
|---|---|---|
| `vertices` | array of `[x, y]` | The closed polygon. **The first vertex is not repeated at the end** — close the path yourself. Winding order is not guaranteed and should not be relied on. |
| `anchor` | `[x, y]` | Label anchor in data coordinates. The point furthest from the zone's own boundary, so it is inside the shape even where the shape is not convex. |
| `arcs` | array of objects | Present only on zones with curved edges. **Absent on `corner3_left` and `corner3_right`**, which are rectangles. A consumer must expect the key to be missing rather than empty. |

Each arc record:

| Field | Type | Notes |
|---|---|---|
| `centre` | `[x, y]` | Always `[0, 0]`. Every arc in the model is centred on the hoop. |
| `r` | number | Radius. |
| `start_deg`, `end_deg` | number | Degrees as above. `start_deg` may be **greater** than `end_deg`, which means the edge is traversed clockwise. Do not assume increasing angles. |

**The arc parameters are a source, not a reconstruction.** The polygons are generated from
these declarations; the parameters were not recovered from finished vertices afterwards.
Drawing the arc mathematically and drawing the vertex list produce the same curve by
construction, so the two cannot silently drift apart. Prefer the arc form where the renderer
supports exact curves — the vertex list samples arcs at 0.5°, a chord error of about 0.002
units at the three-point radius.

#### Worked example: `midrange_right_center`

The right wing mid-range zone, bounded by two arcs about the hoop and two straight rays
between them.

```json
"midrange_right_center": {
  "vertices": [
    [129.448, 94.049],
    [192.142, 139.599],
    [190.916, 141.27],
    ...
    [127.786, 96.294],
    [128.622, 95.175]
  ],
  "anchor": [105, 169],
  "arcs": [
    { "centre": [0, 0], "r": 237.5,   "start_deg": 36, "end_deg": 72 },
    { "centre": [0, 0], "r": 160.006, "start_deg": 72, "end_deg": 36 }
  ]
}
```

146 vertices. Reading it: the boundary starts on the 16 ft band at 36°, runs out along that
ray to the three-point arc, sweeps that arc counter-clockwise from 36° to 72°, comes back
down the 72° ray to the 16 ft band, then sweeps that inner arc **clockwise** from 72° back
to 36° to close. The second arc's `start_deg` exceeding its `end_deg` is what encodes the
reversal, and it is why the inner curve bulges toward the hoop rather than away from it.

The two straight ray segments are implicit: they are the vertices between the end of one arc
and the start of the next, not separate records.

For contrast, a zone with no curved edges:

```json
"corner3_right": {
  "vertices": [[219.5, -52.5], [250.5, -52.5], [250.5, 87.5], [219.5, 87.5]],
  "anchor": [233, -35]
}
```

Four vertices, no `arcs` key at all.

#### Why the constants look wrong

Several boundaries sit a fraction off their nominal court values — the paint wall at 80.5
rather than 80, the free-throw line at 138.5 rather than 137.5, the corner cut at 87.5
rather than the 89.478 where the three-point arc actually meets the corner line. Shot
coordinates are integers, so a boundary placed exactly on one leaves shots sitting on it
where inside-versus-outside is undefined. Each threshold was measured from the labels and
placed in the gap. Do not round them to the diagram values; they are correct as shipped.

`zone_polygons_vertices.json` beside this file is the same shapes with vertices only, in the
format `R/07_zone_geometry.R` takes for checking. The site does not need it.

### The polygon checker

```bash
Rscript R/07_zone_geometry.R                    # regenerate zone_grid.csv
Rscript R/07_zone_geometry.R candidate.json     # check a candidate set of outlines
```

The candidate file is a JSON object keyed by stable zone id, each value an array of `[x, y]`
vertices in the same units as the grid:

```json
{
  "restricted_area": [[-39,-36],[39,-36],[39,39],[-39,39]],
  "paint_left": [ ... ],
  "corner3_right": [ ... ]
}
```

All 14 ids must be present and no others; a missing or unknown id stops the run naming both.
Each polygon needs at least three vertices and is treated as closed.

Every labelled shot is tested against every polygon by ray casting, and results are reported
per zone against the label the NBA assigned. **Three defect categories, kept separate because
they are different bugs:**

| Defect | Meaning | Usually caused by |
|---|---|---|
| `disagreement` | The shot landed inside exactly one polygon, but not the one its NBA label names. | A boundary in the wrong place. |
| `orphan` | The shot landed in no polygon at all. | A gap between shapes, or a zone drawn too small. |
| `overlap` | The shot landed inside two or more polygons. | Shapes that double-cover an area. |

A correct set of outlines produces **zero of all three**. Anything else writes
`export/reference/polygon_defects.csv` with the coordinate, the NBA label, and the polygon it
actually landed in for each defect, capped at 5,000 rows, so a specific bad edge can be
inspected directly rather than inferred from a count.

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
