# Location Edition aggregate relocation-flow contract

Verified 2026-09-29 from `a0fd51b7f6e7bbb7da67f52ec0a9a19a1738f584`.
Scope: analytics contract and read-only verification. Portfolio integration
requires separate authorization.

## Decision: reuse v4

Use the existing selected player-season JSON in
`export/spatial-shot-selection/v4/seasons/{season}/players/{player_id}.json`.
No additional export, endpoint, player identifier, or shot record is needed.
Keep v1-v4 unchanged. Use only the production baseline: 10 attempts, 90%
posterior evidence and the 50% final destination cap. Do not expose sensitivity
conditions as choices.

The production calculation defines removed and added mass for each cell, but
does not define a source-to-destination transport matrix. The exporter assigns
`after_x_ft` and `after_y_ft` to illustrative markers using a deterministic
sequence based on the 25% allocation. Lower slider values use prefixes. Those
display assignments need not reproduce the analytical destination allocation
at each slider value. Do not count their endpoints to construct flow totals or
present them as modeled basketball routes.

Use two sets of cell totals, labeled **Attempts removed from** and **Attempts
added to**. If the interface needs connectors, connect both sets through one
**Relocated attempts** pool. There is no cell-to-cell edge contract.

## Existing inputs and exact derivation

Read these fields from the already-loaded payload:

| Purpose | Existing fields |
|---|---|
| State and scale | `observed_attempts`, `relocation_available`, `availability_reason` |
| Original locations and saved source order | `shots[].x_ft`, `shots[].y_ft`, `shots[].move_order` |
| Cell geometry and support | `heatmap_cells[].cell_id`, rectangle bounds, `observed_attempts`, `supported_destination` |
| Selected slider | `requested_share`, `actual_relocated_share`, `actual_relocated_attempt_equivalents`, `destination_allocation[]` |
| Destination mass | `destination_allocation[].cell_id`, `added_share`, `final_share` |

Select one of the existing requests: 0, .05, .10, .15, .20 or .25. Do not
interpolate between settings. Let `N = observed_attempts` and let `M` be that
slider's saved `actual_relocated_attempt_equivalents`. For a shot with saved
movement order `r`, use:

`weight = min(1, max(0, M - r + 1))`

A null order has weight zero. Sum these weights by the shot's **original**
cell. This retains the saved weakest-first source order, including a fractional
last attempt. Do not rerank cells using exported marginal make probabilities;
the production source order used joint-draw means, which are not interchangeable
with those point estimates.

For each destination cell, use:

`added_attempt_equivalents = N * added_share`

Use that slider's saved allocation, not marker endpoints or scaled 25% weights.
Cells absent from the destination array receive zero. Source and supported
destination sets are disjoint. The resulting before/after count is
`observed_attempts - removed_attempt_equivalents + added_attempt_equivalents`.
This derivation neither reallocates mass nor recalculates a gain or score.

Map original coordinates in feet to the frozen grid:

`cell_id = 1 + min(floor((x + 25)/4), 12) + 13*min(floor((y + 5.25)/4), 11)`

Require `-25 <= x <= 25` and `-5.25 <= y <= 39.75`. Internal boundaries belong
to the cell above/right; include the outer court limits in the final row or
column. Use the exported clipped rectangles for display. Do not invent named
court zones at this stage.

## In-memory aggregate contract

Within the existing selected player-season context, derive one object:

| Field | Type and meaning |
|---|---|
| `relocation_available` | existing boolean |
| `availability_reason` | existing string, unchanged |
| `requested_share` | existing numeric slider request |
| `actual_relocated_attempt_equivalents` | existing finite nonnegative number `M` |
| `cells` | 156 objects, ascending integer `cell_id` |
| `cells[].cell_id` | integer 1-156; join the existing geometry |
| `cells[].removed_attempt_equivalents` | finite nonnegative number, zero included |
| `cells[].added_attempt_equivalents` | finite nonnegative number, zero included |

There are no pair IDs, new player IDs, shot rows, outcome fields, coordinates,
or gain fields in this aggregate object. Geometry already exists in the payload.
Keep numeric precision through aggregation. Round only tooltip text, never
flow widths or totals. Do not force balance by changing one cell's mass.

Source total, destination total and `M` agree mathematically. With serialized
floating-point values, check within `1e-12 * max(1, N)` attempt-equivalents,
equivalent to the production share tolerance. Do not demand bitwise equality
between independent sums. Verify `M = N * actual_relocated_share` at that same
tolerance. Invalid/missing required values or failed balance checks mean an
unavailable visualization with an error state, not an invented zero estimate.

## Rendering states and limits

- Available, 0%: all cell flows are zero. Keep the original court view and show
  “0 attempt-equivalents relocated”; draw no flow bands.
- Unavailable: preserve the reason and null gain/score values, including at
  0%. The payload has zero movement and no destinations, but that is not an
  estimate of zero improvement. Show the existing unavailable state.
- No recorded shots or model-ineligible: the availability catalog has no
  eligible payload. Do not derive a flow object; keep the catalog state.
- One destination: show one receiving cell if it has capacity. A supported
  cell already at or above 50% receives nothing; it may make the estimate
  unavailable. Preserve the `single_destination` evidence label.
- Multiple destinations: use their saved slider-specific shares, including
  redistribution when a cap binds. Omit zero-width bands, not their zero values
  in the aggregate object.
- Capacity below the request: label requested and actual movement separately.
  A cell receiving positive mass cannot finish above 50%. A historical cell
  already above 50% can remain there but cannot receive additional mass.

Made/missed fields do not enter this derivation or marker selection. The verifier
passes only coordinates and saved order to source aggregation. This does not
mean the model is outcome-independent: CAR ability and supported destinations
were learned from historical outcomes. Movement is fixed conditional on that
verified production plan; the interface does not choose made or missed shots.
The flow remains descriptive, non-causal and conditional on existing ability
and capacity assumptions.

## Verification and implementation path

`Rscript R/location_relocation_flow_tests.R` performs a read-only audit of the
frozen v4 manifest, full file inventory, hashes and sizes, then checks the
contract against saved production allocation rules. It sources only the pure
relocation helpers, never an exporter entry point. No private artifact is needed.

| Season | Players | Attempts | Slider cases | Unavailable players | Fractional slider boundaries |
|---|---:|---:|---:|---:|---:|
| 2025-26 | 318 | 194,987 | 1,908 | 42 | 1,164 |
| 2024-25 | 304 | 194,526 | 1,824 | 37 | 1,108 |
| 2023-24 | 281 | 192,608 | 1,686 | 47 | 992 |
| 2022-23 | 292 | 192,897 | 1,752 | 44 | 1,044 |
| 2021-22 | 312 | 193,577 | 1,872 | 45 | 1,125 |

All 9,042 cases passed: zero flow, balanced mass, source exhaustion and fractional
boundaries, supported destinations, saved cap allocation, nonnegative final
counts, unavailable/null behavior and deterministic cell order. The audit
reproduced cell-level source removal from saved marker prefixes and got identical
aggregate objects after reversing the input shot-row order. It covered single
and multiple supported destinations in each season. Synthetic checks covered
clipped/internal court boundaries, fractional removal, available zero requests,
unavailable zero movement and rejection of missing movement. The existing
`R/spatial_targeted_capped_relocation_tests.R` suite also passed, including
outcome-independent movement and capped redistribution.

Maximum observed mass discrepancy: `1.70530256582424e-13` attempt-equivalents,
below the registered tolerance. The first verifier run encountered a nested-JSON
selection error; a later run exposed R's logical type for all-null order columns.
Both corrections concern this new verifier only. Production data never changed.

V4 stays at 1,514 files and 280,809,899 bytes. Player payload size is 119,381
bytes minimum, 172,422 median and 349,391 maximum. Additional export bytes and
browser requests: **zero** when reusing the selected player's loaded payload.
Aggregate locally once per loaded player or on slider changes; do not fetch the
whole bundle. The audit enforces the existing shot/cell field allowlists and
the three-column aggregate cell allowlist. No new public artifact exists, so
two-build export determinism is not applicable; v4's prior verified two-build
provenance remains unchanged.

Next authorization: implement this contract in the portfolio's Location Edition
view, retaining the existing court display and unavailable states. Deployment
requires its own approval. No analytics export or model work is needed first.

For unchanged history, use [architecture](NBA_SHOT_SELECTION_PROJECT_ARCHITECTURE.md),
[production v4](FIVE_SEASON_V4_PLAN.md), [capped relocation](SINGLE_DESTINATION_CAP_V3_PLAN.md)
and [sensitivity results](LOCATION_EDITION_SENSITIVITY_RESULTS.md).
