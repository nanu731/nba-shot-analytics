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
| `meta.json` | 41 KB | Zone definitions, the geometry fingerprint, eligibility rules, metric descriptions, player search index |
| `season-2021-22.json` | 528 KB | 312 players |
| `season-2022-23.json` | 495 KB | 292 players |
| `season-2023-24.json` | 476 KB | 281 players |
| `season-2024-25.json` | 515 KB | 304 players |
| `season-2025-26.json` | 538 KB | 318 players |

Total 2.53 MB, down from 3.38 MB under the 14-zone model: fewer zones means fewer per-player
rows. Season files are written for every season present in
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
| `zone_model` | string | **Geometry fingerprint**, e.g. `"zm10-c5fdd6d04ead"`. A hash of the zone ids, their point values and every polygon vertex. `export/reference/zone_polygons.json` carries the same field. **A consumer combining the two MUST assert they are equal and fail if either is missing or they differ** — see the geometry section at the end. |
| `zone_labels_provisional` | boolean | `true` while `zones[].name` holds placeholder copy. A consumer MUST NOT publish display names while this is `true`. `R/06_sync_to_site.R` refuses to sync. |
| `zones` | array of 10 objects | The zone dictionary. See below. |
| `players` | object | Player search index, keyed by player id. See below. |

### meta.zones[]

**This is the lookup table for every `zone` value elsewhere in the export.**

| Key | Type | Notes |
|---|---|---|
| `zone` | string | **Stable identifier.** The key used by `zone` fields in season files. Derived from what the zone means, never from its position. Safe to hardcode, to key SVG paths off, and to persist. |
| `name` | string | Display name. **Currently placeholder copy** — see `meta.zone_labels_provisional`. Display text; do not key off it. |
| `value` | integer, 2 or 3 | Point value of every shot in this zone. |

The 10 ids, in the array's canonical basket-outward order:

| `zone` | `name` | Points |
|---|---|---|
| `rim` | Restricted Area | 2 |
| `paint` | Paint (non-RA) | 2 |
| `mid_left` | Mid-Range Left | 2 |
| `mid_center` | Mid-Range Center | 2 |
| `mid_right` | Mid-Range Right | 2 |
| `corner3_left` | Left Corner 3 | 3 |
| `arc3_left` | Above the Break 3 Left | 3 |
| `arc3_top` | Above the Break 3 Center | 3 |
| `arc3_right` | Above the Break 3 Right | 3 |
| `corner3_right` | Right Corner 3 | 3 |

**These ids replaced a 14-id set on 2026-08-27 and are not interchangeable with it.** Three
strings appear in both. `corner3_left` and `corner3_right` are safe: they contain exactly the
same shots under both models, verified across all 1,089,337 in-play shots. `arc3_center` was
**not** safe — it named a narrower wedge before — and the current zone is called `arc3_top`
precisely so that a stale consumer misses rather than silently matching. The remaining eleven
old ids (`restricted_area`, `paint_left`, `paint_center`, `paint_right`, `midrange_left`,
`midrange_left_center`, `midrange_center`, `midrange_right_center`, `midrange_right`,
`arc3_left_center`, `arc3_right_center`) no longer exist.

**This is what `zone_model` is for.** Two ids matching by coincidence is exactly the failure a
version assertion catches and an id comparison does not.

**Array order is display order, not identity.** The array is ordered basket-outward and that
order is stable, but **never use array position as an identifier** — resolve by the `zone`
string. An earlier version of this export keyed zones by integer index; if the zone model had
changed, the same integer would have meant a different zone with nothing raising an error.

**`zone` contains no geometry.** It is an identifier only. The outlines live in
`export/reference/zone_polygons.json`; see the geometry section at the end of this document.

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

### priors[] — 10 objects, one per zone

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

### baselines[] — 10 objects, one per zone

The league shot distribution, which is the comparison point in the score formula.

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | string | — | Stable zone id; resolve through `meta.zones`. |
| `freq_pooled` | number, 5 dp | proportion 0–1 | Total qualifying-pool attempts in this zone ÷ total qualifying-pool attempts. **This is the primary baseline** and the one used to compute `score`. Sums to exactly 1.00000 across the 10 zones. |
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
| `zones_used` | integer 0–10 | zones | Count of zones with at least one attempt. Observed minimum is 3. **Note the ceiling is crowded**: 282 of 318 qualifying players in 2025-26 use all ten, so this field is close to binary and is a poor axis to plot against. |
| `pps` | number, 4 dp | points per shot | Overall raw points per shot: total points ÷ total attempts. **Not shrunk.** |
| `score` | number, 5 dp | points per shot | **The headline selection score**, pooled baseline. Signed; roughly −0.12 to +0.29. Positive means the player's allocation of shots adds value given his own abilities. |
| `score_unweighted` | number, 5 dp | points per shot | Same formula against `freq_unweighted`. A robustness check; correlates 0.9996–0.9998 with `score`. |
| `herfindahl` | number, 4 dp | index 0–1 | Sum of squared shot frequencies. Concentration of the shot diet. Floor is 1/10 = 0.100 (perfectly even); 1.0 would be every shot from one zone. Observed range in 2025-26 is 0.111 to 0.758. |
| `zones` | array of 10 objects | — | Always exactly 10, in the same basket-outward order as `meta.zones`, including zones with no attempts. |

### players[].zones[] — 10 objects per player

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | string | — | Stable zone id; resolve through `meta.zones`. |
| `makes` | integer | shots | Made field goals. `0` when the player never shot here. |
| `attempts` | integer | shots | Field goal attempts. `0` when the player never shot here. |
| `fg_pct` | number, 4 dp or **null** | proportion 0–1 | Raw field goal percentage. **`null` when `attempts` is 0** — no shots means no observed rate, which is distinct from a rate of zero. 268 nulls in 2025-26. |
| `pps` | number, 4 dp or **null** | points per shot | Raw points per shot, `value × fg_pct`. **`null` when `attempts` is 0**, same reasoning. |
| `freq` | number, 4 dp | proportion 0–1 | This player's share of his own attempts taken from this zone. `0` when he never shot here — this is a genuine zero, not an absence, so it is not null. Sums to 1 across the 10 zones **up to rounding**: observed drift up to ~2×10⁻⁴ because each value is rounded to 4 dp independently. |
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
this export they do not.** Each of the 10 contributions is rounded to 5 dp independently and
`score` is rounded separately, so the two disagree in the fourth decimal place. Measured across
all 1,507 player-seasons the maximum disagreement is **3.0 × 10⁻⁴** (Trayce Jackson-Davis,
2023-24); it is nonzero for most players.

Display the shipped `score`. Use `contrib` for the per-zone breakdown — which zones help and
which hurt, and by roughly how much. A bar chart of `contrib` values will not add up to the
headline number, and should not be presented as though it does. If exact reconciliation is ever
needed, the fix belongs in the export (emit unrounded values, or derive `score` from the rounded
contributions so the two agree by construction), not in the consuming site.

**`freq` has the same property** for the same reason: the 10 per-zone frequencies are each
rounded to 4 dp, so they sum to 1 only up to about 2 × 10⁻⁴ rather than exactly.

**Null semantics, summarised.** Only three fields are ever null. `zone.fg_pct` and `zone.pps`
are null exactly when `attempts = 0`, meaning "no observation". `player.position` is null when
the player is absent from the end-of-season roster. Everything else is always present.

**What is not exported.** Nothing shot-level. No coordinates (`LOC_X`, `LOC_Y`), no `GAME_ID`,
no `ACTION_TYPE`, no per-shot rows of any kind. The finest grain in the export is the
player-zone cell. No team identifiers appear anywhere. No dates beyond `meta.generated`.

**Ordering invariants that currently hold**, though nothing in the format enforces them:
`players` is sorted by `score` descending; each player's `zones` array is in `meta.zones`
order with all 10 present; `priors` and `baselines` are in `meta.zones` order.

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

`export/reference/` holds the zone outlines and the tooling that verifies them. **The site
does not fetch this at runtime** — `export/data/` is the runtime payload; `zone_polygons.json`
here is imported at build time.

Until 2026-08-27 this directory existed so someone could *author* outlines by hand, because
the project took zones from the NBA's labels and rule A4 forbade deriving geometry. It now
generates them instead, from the single constants block in `R/zone_model.R`.

### `zone_grid.csv`

A spatial histogram of every in-play shot across all five seasons, binned into half-foot
cells, classified by `classify_zone()`.

| Column | Type | Notes |
|---|---|---|
| `x`, `y` | number | Cell **centre**, NBA shot-chart units (tenths of a foot, hoop at origin). Cells are 5 units square, so a cell covers `x ± 2.5`, `y ± 2.5`. |
| `zone` | string | Stable zone id, matching `meta.zones[].zone`. **Renamed from `zone_id` on 2026-08-27**, when the model stopped carrying two identifiers. |
| `n` | integer | Shots from that zone in that cell, pooled across 2021-22 to 2025-26. |

7,788 rows over 7,508 distinct cells, 1,089,337 shots, 183 KB.

**One row per cell per zone.** Most cells hold a single zone and produce one row. **277 cells
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
`shot_coordinates()` in `R/07_zone_geometry.R` and keep it under `data/cache/`, which is
gitignored permanently. It must not be committed or copied into `export/`.

### `zone_polygons.json`

The 10 zone outlines, generated by `write_zone_polygons()` in `R/07_zone_geometry.R` from
`zone_polygons()` in `R/zone_model.R`. **Verified against all 104,205 distinct real
coordinates, covering 1,091,329 shots, with zero disagreements, zero orphans and zero
overlaps** — every shot falls inside exactly one polygon, and it is the polygon
`classify_zone()` assigns it to.

This file is **imported at build time**, not fetched by the browser. `R/06_sync_to_site.R`
copies it into the site's source tree, separately from the runtime payload in
`export/data/`.

34.6 KB, 2,036 vertices across 10 zones, 8 arc records.

**Top-level keys.** `zone_model`, the geometry fingerprint, identical to `meta.zone_model`;
`units`, a prose string; and `zones`, an object keyed by zone id. **A consumer combining this
file with a season file MUST assert the two `zone_model` values are equal**, and fail the
build if either is absent or they differ. An absent field is how a file predating 2026-08-27
would otherwise pass unnoticed.

`R/08_zone_polygons.R` built this file until 2026-08-27 and was deleted: it held a second copy
of every court constant, which rule A4 now forbids.

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
behind the hoop) to 397.5, the backcourt cut, which is just past the furthest shot on record
at y = 397. Nothing is drawn above it, and no shot beyond it belongs to any zone.

**y is therefore inverted relative to SVG**, where y grows downward. A single group
transform such as `scale(1, -1)` handles the polygons. Text inside that transform renders
upside down, so labels must be positioned outside it or counter-transformed.

Angles, where they appear, are **degrees, measured from the +x axis, counter-clockwise**.
0° points right, 90° points up the court, 180° points left.

#### Per-zone keys

Keyed by stable zone id, the same ids used by `meta.zones[].zone` in the runtime export.

| Key | Type | Notes |
|---|---|---|
| `zone` | string | The id, repeated inside the object so a value carries its own key. |
| `value` | integer, 2 or 3 | Point value, matching `meta.zones[].value`. |
| `vertices` | array of `[x, y]` | The closed polygon. **The first vertex is not repeated at the end** — close the path yourself. Winding order is not guaranteed and should not be relied on. |
| `arcs` | array of objects | Empty on zones with no curved edges — `corner3_left` and `corner3_right`, which are rectangles. |

**`paint` is a keyhole and needs care.** It is the lane rectangle minus the restricted-area
disc, expressed as a **single ring with a zero-width slit** at `x = 0.25` running from the
baseline to the circle. A renderer using the even-odd fill rule draws it correctly as-is. One
using non-zero winding may fill the hole. There is no separate inner-ring key; do not expect
one.

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

#### Worked example: `arc3_right`

The right above-the-break three, bounded by the sideline, the top bound, a straight ray in
from the top, and the three-point arc.

```json
"arc3_right": {
  "zone": "arc3_right",
  "value": 3,
  "vertices": [[220.794, 87.5], [250.02, 87.5], [250.02, 397.5], [229.496, 397.5], ...],
  "arcs": [{ "centre": [0, 0], "r": 237.5, "start_deg": 60.0002, "end_deg": 21.618272 }]
}
```

81 vertices. Reading it: the boundary starts where the arc meets the corner break, runs out
along `y = 87.5` to the sideline, up the sideline to the backcourt cut at `y = 397.5`, in
along that line to the 60° ray, then down that ray to the arc and **clockwise** along the arc
from 60° back to 21.62° to close. The arc's `start_deg` exceeding its `end_deg` is what
encodes the reversal.

The straight ray segment is implicit: it is the run of vertices between the top bound and the
start of the arc, not a separate record.

For contrast, a zone with no curved edges:

```json
"corner3_right": {
  "zone": "corner3_right",
  "value": 3,
  "vertices": [[219.98, -52.5], [250.02, -52.5], [250.02, 87.5], [219.98, 87.5]],
  "arcs": []
}
```

Four vertices and an empty `arcs` array.

**The notch.** The three-point arc meets `x = 220` at `y = 89.478`, but the corner break is at
`y = 87.5`. Between those two values, outside the corner line and inside the arc, sits a sliver
about 0.79 units wide that belongs to neither corner nor arc by the obvious reading. The model
resolves it explicitly to mid-range, and **no shot has ever landed there** across all five
seasons. It is a formality, but the classifier has to be total, so it is stated rather than
left to evaluation order.

#### Why the constants look wrong

Several boundaries sit a fraction off their nominal court values. **These are deliberate and
there are two different reasons, which should not be confused.**

**Rendering offsets, worth `EPS = 0.02` or `EPS_DEG = 0.0002`.** The paint wall renders at
80.02 rather than 80, the corner line at 219.98 rather than 220, the sideline at 250.02, the
restricted-area circle at 39.98, the free-throw line at 137.52, and the 60° ray at 60.0002°.
Shot coordinates are integers, so a polygon edge placed exactly where a point can land leaves
points sitting on it, where inside-versus-outside is undefined. Each edge is nudged in the
direction the classifier's own inclusivity implies. The offsets are far smaller than the gap
between any two achievable coordinates, so they move no shot.

**Measured constants, which are the model itself.** The corner break is at `y = 87.5` rather
than the 89.478 where the arc meets the corner line, and the backcourt cut is at `y = 397.5`
rather than the true half-court line at 417.5. Both were measured from the data because the
feature they mark has no painted line to sit on.

**One deliberate departure from the NBA in the opposite direction.** The free-throw line is
`137.5`, the real court marking, where the NBA's retired labels implied `138.5`. That moves 799
shots at `y = 138` from the paint into mid-range, and they are the only paint-family
disagreement between this model and those labels across all 1,089,337 in-play shots.

**Do not round any of these to the diagram values.** They are correct as shipped.

### The polygon checker

```bash
Rscript R/07_zone_geometry.R          # regenerate zone_grid.csv and zone_polygons.json
Rscript R/07_zone_geometry.R check    # run the checker
```

**The checker takes no candidate file.** Until 2026-08-27 it asked whether hand-authored
outlines reproduced the NBA's labels. That question died with the labels. It now asks a
stricter one: **do the two artifacts generated from the shared constants agree with each
other?** `classify_zone()` and `zone_polygon()` are built from one constants block but by
different code, so a bug in either surfaces here.

It runs over two point sets: every distinct real coordinate in `data/raw/`, and a dense
synthetic grid at 0.25-unit spacing over the whole in-bounds court, about 3.6 million points.
**Four defect categories, kept separate because they are different bugs:**

| Defect | Meaning | Usually caused by |
|---|---|---|
| `disagreement` | The point landed inside exactly one polygon, but not the one `classify_zone()` names. | A boundary in the wrong place. |
| `orphan` | The point landed in no polygon at all. | A gap between shapes, or a zone drawn too small. |
| `overlap` | The point landed inside two or more polygons. | Shapes that double-cover an area. |
| `outside-partition` | The point is beyond the backcourt cut, so `classify_zone()` returns `NA`, yet a polygon contains it. | A zone drawn past `y = 397.5`. |

**The pass criterion is zero defects on real coordinates, not zero everywhere.** This matters
and is easy to misread. Polygon edges are offset by `EPS` so that no point can sit exactly on
one, and that offset necessarily creates a band, `EPS` wide, in which the polygon and the
classifier disagree. Removing the band would reintroduce the undefined boundary it exists to
prevent. **The dense grid will therefore always report a nonzero count, and that is not a
failure.**

What matters is that every grid defect falls into a family with a known cause. As of
`zm10-c5fdd6d04ead`: **0 defects on all 104,205 real coordinates** in all four categories, and
103 on 3,588,609 grid points — 49 orphans on the `paint` keyhole slit at `x = 0.25`, 32 in the
`EPS` band at `r = 40`, 10 in the `EPS_DEG` band at the 60° and 120° rays, and 12 from arc
chord error at `r ≈ 237.5`, which includes both overlaps. None is reachable by an integer
coordinate.

**An unexplained grid defect, or any defect on a real coordinate, is a failure. A band defect
is not.** Defects are written to `export/reference/polygon_defects.csv` with the coordinate,
the classifier's zone, and the polygon it actually landed in, capped at 5,000 rows.

---

## Zone geometry

**The geometry originates in this repository, in `R/zone_model.R`.** This section previously
said the opposite, and said it at length. Until 2026-08-27 zones came from the NBA's own label
columns, rule A4 forbade deriving them from coordinates, and a consuming site had to author its
own outlines. All of that is now false.

Every boundary is defined once, in the constants block of `R/zone_model.R`. Two artifacts are
generated from it and neither derives from the other: `classify_zone(x, y)` assigns a shot to a
zone, and `zone_polygon(id)` returns that zone's outline. `R/07_zone_geometry.R` checks they
agree. Changing a boundary is a one-line edit that moves both.

**A consuming site should take the outlines from `export/reference/zone_polygons.json`** rather
than authoring its own, and **must assert that file's `zone_model` equals `meta.zone_model`** in
the runtime payload before drawing anything. The two files are synced separately by
`R/06_sync_to_site.R`, into the source tree and the public directory respectively, so a partial
sync can leave one stale. Three zone ids exist in both the current model and the retired
14-zone one; two of them describe the same region and would draw correctly by luck, which is
exactly why an id comparison is not sufficient and a version assertion is.

The static charts draw a court separately, in `court_layer()` in `R/04_charts.R`. It emits
seven ggplot annotations — the hoop circle, the backboard, the paint rectangle, the free-throw
circle, the two corner-three segments, the three-point arc, and the baseline — and **every
dimension is read from `R/zone_model.R` rather than restated.** These are court furniture, not
zone outlines: no two of them bound a zone. They previously carried their own copies of the
same numbers, and drew the corner segments to `y = 89.5` where the model's break is 87.5.
