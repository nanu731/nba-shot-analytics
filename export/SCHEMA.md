# export/data — current schema

Describes what `R/05_export_json.R` emits **as of the files currently on disk**
(`generated: 2026-08-24`). This is a description of present behaviour, not a specification of
intended behaviour. Where a field is named misleadingly or carries a subtlety, that is recorded
rather than corrected.

Verified by reading the emitted JSON, not only the generating code.

---

## Files

The export writes **one metadata file plus one file per season**, all flat (not pretty-printed),
into `export/data/`.

| File | Size | Contents |
|---|---|---|
| `meta.json` | 1.4 KB | Zone definitions, eligibility rules, metric descriptions |
| `season-2021-22.json` | 643 KB | 312 players |
| `season-2022-23.json` | 602 KB | 292 players |
| `season-2023-24.json` | 580 KB | 281 players |
| `season-2024-25.json` | 626 KB | 304 players |
| `season-2025-26.json` | 654 KB | 318 players |

Total 3.03 MB. Season files are written for every season present in
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

### meta.zones[]

**This is the lookup table for every `zone` integer elsewhere in the export.**

| Key | Type | Notes |
|---|---|---|
| `index` | integer 0–13 | The value used by `zone` fields in season files. |
| `zone` | string | Full zone name, e.g. `"Above the Break 3 | Center(C)"`. This is the NBA's `SHOT_ZONE_BASIC` and `SHOT_ZONE_AREA` joined with `" | "`. Up to 41 characters. |
| `value` | integer, 2 or 3 | Point value of every shot in this zone. |

Order is fixed and runs basket-outward: 0 restricted area, 1–3 paint (L/C/R), 4–8 mid-range
(L/LC/C/RC/R), 9 left corner three, 10–12 above the break (LC/C/RC), 13 right corner three.

**Indices are positional, not stable identifiers.** They are assigned by row order from the
pipeline's zone reference table. If the zone model ever changes, the same integer will mean a
different zone. Consumers should resolve through `meta.zones` rather than hardcoding.

**`zone` contains no geometry.** It is a label only. See the note at the end of this document.

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
| `zone` | integer | — | Index into `meta.zones`. |
| `alpha` | number, 3 dp | pseudo-makes | Beta-binomial α for this zone-season. |
| `beta` | number, 3 dp | pseudo-misses | Beta-binomial β. |
| `k` | number, 2 dp | pseudo-attempts | `alpha + beta`. The shrinkage strength: effectively the number of league-average attempts added to every player's record in this zone. Ranges 31 to 560 in 2025-26. |
| `prior_mean` | number, 4 dp | proportion 0–1 | `alpha / k`. The fitted league field-goal percentage for this zone. Note this is the *fitted* value and can differ slightly from the raw pooled percentage. |
| `league_attempts` | integer | shots | **Misleadingly named.** This is attempts by *qualifying players only*, not the whole league. For 2025-26 restricted area it is 54,217; the true league-wide figure is 62,253. |
| `converged` | boolean | — | `true` if the maximum-likelihood fit converged. |
| `method` | string | — | `"vglm"` (maximum likelihood) or `"moments"` (method-of-moments fallback). Across all 70 zone-seasons: 67 `vglm`, 3 `moments`. `converged` is `false` exactly when `method` is `"moments"`. |

### baselines[] — 14 objects, one per zone

The league shot distribution, which is the comparison point in the score formula.

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | integer | — | Index into `meta.zones`. |
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
| `zones` | array of 14 objects | — | Always exactly 14, always ordered by `zone` index 0–13, including zones with no attempts. |

### players[].zones[] — 14 objects per player

| Key | Type | Units | Notes |
|---|---|---|---|
| `zone` | integer | — | Index into `meta.zones`. |
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
`players` is sorted by `score` descending; each player's `zones` array is in ascending `zone`
order with all 14 present; `priors` and `baselines` are in ascending `zone` order.

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
