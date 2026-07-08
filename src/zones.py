"""
src/zones.py — Zone polygon construction for overlay charts.

Polygons use the exact same boundary thresholds as assign_zone() in
src/metrics.py. Coordinate system matches src/court.py: basket at (0, 0),
feet as units, positive y toward half court.

All polygons must pass the verification test before any coloring or
charting logic is built on top of them.
"""

import numpy as np
import matplotlib.colors as mcolors
import matplotlib.patheffects as pe
from matplotlib.cm import ScalarMappable
from matplotlib.patches import Polygon as MplPolygon

from src.metrics import (
    assign_zone,
    _CORNER_3_BREAK_Y,
    _THETA_CORNER_R,
    _THETA_WING_R,
    _THETA_WING_L,
    _THETA_CORNER_L,
)
from src.court import draw_court

# ── Boundary constants — exact values from assign_zone() in src/metrics.py ───
_RA_RADIUS   = 4.0    # Restricted Area: dist <= this value
# Inner arc of the Paint (Non-RA) polygon. A finite-point arc is an inscribed
# polygon, so its chord midpoints sit slightly *inside* the true 4.0 ft circle
# and cut a fraction of an inch into the Restricted Area — causing sampled
# points at dist ≈ 3.98 ft to fail verification. Offsetting the drawn radius
# outward by 0.02 ft (0.24 inches) keeps the polygon entirely clear of the RA.
# This is geometrically negligible and invisible on any rendered chart.
_PAINT_INNER_RADIUS = _RA_RADIUS + 0.02   # 4.02 ft
_PAINT_X     = 8.0    # Paint half-width: abs(x) <= this value
_PAINT_Y_TOP = 14.5   # Paint top boundary: y <= this value
_CORNER_3_X  = 22.0   # Corner-3 straight line: |x| >= this value
# _CORNER_3_BREAK_Y ≈ 8.95 ft — imported from src.metrics, not redefined here

# ── Above-break 3 constants — exact values from assign_zone() in src/metrics.py ─
_ARC_3_RADIUS        = 23.75   # Above-break 3: dist >= this value
# The inner arc of the above-break (outer-ring) polygons is drawn at a slightly
# LARGER radius so the inscribed-polygon chords stay OUTSIDE the true 23.75 ft
# circle. A finite-point arc bows inward (chord midpoints sit at a smaller
# radius); drawn at 23.75 that would pull the polygon edge inside the arc, into
# dist < 23.75 territory, where assign_zone() returns a mid-range zone — causing
# false verification failures. The mid-range (inner-ring) polygons instead use
# the true 23.75 ft arc as their OUTER edge, where the inward-bowing chords stay
# safely inside. A 0.05 ft (0.6 inch) offset clears all outer-ring zones with
# zero mismatches across many seeds and is invisible on any rendered chart.
_ARC_3_INNER_RADIUS  = _ARC_3_RADIUS + 0.05   # 23.80 ft
_HALFCOURT_Y         = 47.0    # half-court line: outer ring extends up to this y

# ── Court boundary constants — matching src/court.py ─────────────────────────
_BASELINE_Y = -4.75   # y-coordinate of the baseline behind the basket
_SIDELINE_X = 25.0    # |x| of the sidelines

# ── Zone-overlay styling ─────────────────────────────────────────────────────
# Diverging colormap for PPS vs league average: red (below) → white (at league
# average) → green (above).
_PPS_CMAP = mcolors.LinearSegmentedColormap.from_list(
    "pps_div", ["#c1121f", "#f7f7f7", "#1a9850"]
)
_NO_DATA_COLOR = "#d9d9d9"   # neutral gray for zones with zero attempts

# Short label drawn inside each zone (kept small so it fits the narrower zones).
_ZONE_ABBREV = {
    "Restricted Area":          "RA",
    "Paint (Non-RA)":           "Paint",
    "Left Corner 3":            "LC3",
    "Right Corner 3":           "RC3",
    "Mid-Range Left Corner":    "Mid LC",
    "Mid-Range Left Wing":      "Mid LW",
    "Mid-Range Top of Key":     "Mid TK",
    "Mid-Range Right Wing":     "Mid RW",
    "Mid-Range Right Corner":   "Mid RC",
    "Above Break 3 Left Wing":  "AB3 LW",
    "Above Break 3 Top of Key": "AB3 TK",
    "Above Break 3 Right Wing": "AB3 RW",
}

# Anchor point (feet) where each zone's two-line label is centered. Chosen to sit
# comfortably inside each polygon rather than at a raw vertex centroid, which for
# the fan-shaped radial zones can land outside the shape.
_ZONE_LABEL_ANCHORS = {
    "Restricted Area":          (  0.0,  1.0),
    "Paint (Non-RA)":           (  0.0,  9.5),
    "Left Corner 3":            (-23.4,  1.5),
    "Right Corner 3":           ( 23.4,  1.5),
    "Mid-Range Left Corner":    (-15.0,  0.5),
    "Mid-Range Left Wing":      (-14.0, 11.0),
    "Mid-Range Top of Key":     (  0.0, 18.5),
    "Mid-Range Right Wing":     ( 14.0, 11.0),
    "Mid-Range Right Corner":   ( 15.0,  0.5),
    "Above Break 3 Left Wing":  (-17.5, 19.0),
    "Above Break 3 Top of Key": (  0.0, 30.0),
    "Above Break 3 Right Wing": ( 17.5, 19.0),
}


def _arc_points(cx, cy, radius, theta1_deg, theta2_deg, n=64):
    """
    Return an (n, 2) array of points along a circular arc.

    Parameters
    ----------
    cx, cy     : center of the circle in feet
    radius     : radius in feet
    theta1_deg : start angle in degrees (0 = right, 90 = top)
    theta2_deg : end angle in degrees
    n          : number of sample points — more points = smoother curve
    """
    thetas = np.linspace(np.radians(theta1_deg), np.radians(theta2_deg), n)
    return np.column_stack([
        cx + radius * np.cos(thetas),
        cy + radius * np.sin(thetas),
    ])


def build_zone_polygons():
    """
    Return a dict mapping zone name -> (N, 2) numpy array of polygon vertices.

    Zones built (all 12):
      "Restricted Area", "Paint (Non-RA)", "Left Corner 3", "Right Corner 3",
      "Mid-Range Right Corner", "Mid-Range Right Wing", "Mid-Range Top of Key",
      "Mid-Range Left Wing", "Mid-Range Left Corner",
      "Above Break 3 Right Wing", "Above Break 3 Top of Key",
      "Above Break 3 Left Wing"

    The four fixed zones are unchanged; the other eight fan out from the basket
    along four radial lines (two corner lines through (±22, break_y) and two wing
    lines through (±8, wing_break_y)), shared between the mid-range inner ring
    and the above-break outer ring. Every polygon uses the exact same boundary
    thresholds and radial angles as assign_zone() in src/metrics.py. All 12 pass
    the verification test at 100%.
    """
    polys = {}

    # ── Restricted Area ───────────────────────────────────────────────────────
    # assign_zone condition: dist <= 4.0
    #
    # Full circle of radius 4.0 centered at the basket origin. The circle's
    # lowest point is y = -4.0, which sits above the baseline at y = -4.75,
    # so no capping against the baseline is required. 128 points renders
    # as a visually smooth circle.
    polys["Restricted Area"] = _arc_points(0, 0, _RA_RADIUS, 0, 360, n=128)

    # ── Paint (Non-RA) ────────────────────────────────────────────────────────
    # assign_zone conditions: abs(x) <= 8.0  AND  y <= 14.5  AND  dist > 4.0
    #
    # The paint is the rectangle x in [-8, 8], y in [baseline, 14.5] with the RA
    # disk removed. The RA circle's lowest point (y = -4.02) sits ABOVE the
    # baseline (y = -4.75), so the removed disk does not touch any edge of the
    # rectangle — topologically the paint is a ring. A single closed polygon
    # cannot contain a floating hole, so we cut a hair-thin slit from the bottom
    # of the RA circle straight down to the baseline (along x = 0, behind the
    # basket) and trace the RA circle as an inner boundary. The outer rectangle
    # is wound counter-clockwise and the inner circle clockwise, so the fill
    # rule leaves the RA disk empty (the RA zone is drawn separately on top).
    ra_hole = _arc_points(0, 0, _PAINT_INNER_RADIUS, 270, -90, n=128)  # circle, CW from bottom
    polys["Paint (Non-RA)"] = np.vstack([
        [[ 0.0,       _BASELINE_Y         ]],   # slit mouth on the baseline (0, -4.75)
        [[ _PAINT_X,  _BASELINE_Y         ]],   # (8, -4.75)
        [[ _PAINT_X,  _PAINT_Y_TOP        ]],   # (8, 14.5)
        [[-_PAINT_X,  _PAINT_Y_TOP        ]],   # (-8, 14.5)
        [[-_PAINT_X,  _BASELINE_Y         ]],   # (-8, -4.75)
        [[ 0.0,       _BASELINE_Y         ]],   # back to the slit mouth (0, -4.75)
        [[ 0.0,      -_PAINT_INNER_RADIUS ]],   # up the slit to the RA bottom (0, -4.02)
        ra_hole,                                # trace the RA circle (hole), CW
        [[ 0.0,      -_PAINT_INNER_RADIUS ]],   # close the hole at (0, -4.02)
        [[ 0.0,       _BASELINE_Y         ]],   # back down the slit to close
    ])

    # ── Left Corner 3 ─────────────────────────────────────────────────────────
    # assign_zone condition: x <= -22.0  AND  y <= _CORNER_3_BREAK_Y
    #
    # Rectangle from the left sideline to the corner-3 straight line, spanning
    # from the baseline (y = -4.75) up to the break point where the straight line
    # meets the above-break arc (y ≈ 8.95 ft, same formula used in assign_zone
    # and court.py: sqrt(23.75² - 22²)). Extended to the baseline so it fills the
    # court behind the basket rather than stopping short at y = 0.
    polys["Left Corner 3"] = np.array([
        [-_SIDELINE_X,  _BASELINE_Y      ],  # bottom-left
        [-_CORNER_3_X,  _BASELINE_Y      ],  # bottom-right
        [-_CORNER_3_X,  _CORNER_3_BREAK_Y],  # top-right
        [-_SIDELINE_X,  _CORNER_3_BREAK_Y],  # top-left
    ])

    # ── Right Corner 3 ────────────────────────────────────────────────────────
    # assign_zone condition: x >= 22.0  AND  y <= _CORNER_3_BREAK_Y
    polys["Right Corner 3"] = np.array([
        [ _CORNER_3_X,  _BASELINE_Y      ],  # bottom-left
        [ _SIDELINE_X,  _BASELINE_Y      ],  # bottom-right
        [ _SIDELINE_X,  _CORNER_3_BREAK_Y],  # top-right
        [ _CORNER_3_X,  _CORNER_3_BREAK_Y],  # top-left
    ])

    # ── Radial zone geometry ──────────────────────────────────────────────────
    # The eight non-fixed zones fan out from the basket along four radial lines.
    # The angles come from src/metrics.py so the polygons match assign_zone()
    # exactly. The mid-range (inner) ring uses the 3-point arc at r_arc (23.75)
    # as its outer edge; the above-break (outer) ring uses the same arc offset
    # outward to r_out (23.80) as its inner edge (chords of a finite-point arc
    # bow inward, so the outward offset keeps the outer-ring polygons at
    # dist >= 23.75 — same reasoning as the previous model).
    tcR, twR = _THETA_CORNER_R, _THETA_WING_R    # right corner / wing angles
    twL, tcL = _THETA_WING_L, _THETA_CORNER_L    # left  wing / corner angles
    r_arc = _ARC_3_RADIUS            # mid-range outer edge / true 3-point arc
    r_out = _ARC_3_INNER_RADIUS      # above-break inner edge (offset outward)

    def _ray(theta_deg, x=None, y=None):
        """Point [x, y] on the ray from the basket at theta, given x OR y."""
        t = np.radians(theta_deg)
        if x is not None:
            return [x, x * np.tan(t)]
        return [y / np.tan(t), y]

    cby = _CORNER_3_BREAK_Y                              # ≈ 8.95
    P_wR_top  = _ray(twR, y=_PAINT_Y_TOP)               # θwR ∩ paint top  ≈ (5.19, 14.5)
    P_wL_top  = _ray(twL, y=_PAINT_Y_TOP)               # θwL ∩ paint top  ≈ (-5.19, 14.5)
    P_cR_edge = _ray(tcR, x=_PAINT_X)                   # θcR ∩ x=+8       ≈ (8, 3.26)
    P_cL_edge = _ray(tcL, x=-_PAINT_X)                  # θcL ∩ x=-8       ≈ (-8, 3.26)
    P_wR_half = _ray(twR, y=_HALFCOURT_Y)               # θwR ∩ y=47       ≈ (16.8, 47)
    P_wL_half = _ray(twL, y=_HALFCOURT_Y)               # θwL ∩ y=47       ≈ (-16.8, 47)
    a_out_22  = float(np.degrees(np.arccos(_CORNER_3_X / r_out)))   # offset-arc angle at x=22

    # ── Mid-Range Right Corner ────────────────────────────────────────────────
    # Inner-ring slice below the θcR line (angle ≤ ~22.14°). A quad between the
    # paint edge and the flat corner-3, from the baseline up to the θcR line.
    polys["Mid-Range Right Corner"] = np.array([
        [ _PAINT_X,    _BASELINE_Y      ],   # (8, -4.75)
        [ _CORNER_3_X, _BASELINE_Y      ],   # (22, -4.75)
        [ _CORNER_3_X, _CORNER_3_BREAK_Y],   # (22, break_y)  θcR meets the arc
        P_cR_edge,                           # (8, 3.26)      θcR meets the paint edge
    ])

    # ── Mid-Range Right Wing ──────────────────────────────────────────────────
    # Inner-ring slice between θcR and θwR. Outer edge the arc; wraps over the
    # upper-right of the paint (the notch at x ≤ 8, y ≥ 14.5) and is bounded
    # below by the θcR line.
    mid_rwing_arc = _arc_points(0, 0, r_arc, tcR, twR, n=48)  # (22,break_y) → (8, 22.36)
    polys["Mid-Range Right Wing"] = np.vstack([
        mid_rwing_arc,                       # (22, break_y) → (8, 22.36)
        [P_wR_top],                          # (5.19, 14.5)   down θwR to paint top
        [[_PAINT_X, _PAINT_Y_TOP]],          # (8, 14.5)      across the paint top
        [P_cR_edge],                         # (8, 3.26)      down the paint edge
    ])

    # ── Mid-Range Top of Key ──────────────────────────────────────────────────
    # Inner-ring slice between the two wing lines. Bottom is the paint top from
    # (-5.19, 14.5) to (5.19, 14.5); sides are the wing lines; top is the arc.
    mid_top_arc = _arc_points(0, 0, r_arc, twL, twR, n=64)  # (-8,22.36) → over top → (8,22.36)
    polys["Mid-Range Top of Key"] = np.vstack([
        mid_top_arc,                         # (-8, 22.36) → over top → (8, 22.36)
        [P_wR_top],                          # (5.19, 14.5)
        [P_wL_top],                          # (-5.19, 14.5)
    ])

    # ── Mid-Range Left Wing ───────────────────────────────────────────────────
    # Mirror of Mid-Range Right Wing (between θwL and θcL).
    mid_lwing_arc = _arc_points(0, 0, r_arc, tcL, twL, n=48)  # (-22,break_y) → (-8, 22.36)
    polys["Mid-Range Left Wing"] = np.vstack([
        mid_lwing_arc,                       # (-22, break_y) → (-8, 22.36)
        [P_wL_top],                          # (-5.19, 14.5)
        [[-_PAINT_X, _PAINT_Y_TOP]],         # (-8, 14.5)
        [P_cL_edge],                         # (-8, 3.26)
    ])

    # ── Mid-Range Left Corner ─────────────────────────────────────────────────
    # Mirror of Mid-Range Right Corner (angle ≥ ~157.86°).
    polys["Mid-Range Left Corner"] = np.array([
        [-_PAINT_X,    _BASELINE_Y      ],   # (-8, -4.75)
        [-_CORNER_3_X, _BASELINE_Y      ],   # (-22, -4.75)
        [-_CORNER_3_X, _CORNER_3_BREAK_Y],   # (-22, break_y)
        P_cL_edge,                           # (-8, 3.26)
    ])

    # ── Above Break 3 Right Wing ──────────────────────────────────────────────
    # Outer-ring slice below θwR. Inner edge the offset arc from the corner break
    # up to the θwR line; bounded below by the flat corner-3 top (y = break_y)
    # and the sideline, and above by the θwR line out to the half-court line.
    ab_rwing_arc = _arc_points(0, 0, r_out, a_out_22, twR, n=48)  # (22, ~9.08) → (8.02, 22.41)
    polys["Above Break 3 Right Wing"] = np.vstack([
        [P_wR_half],                         # (16.8, 47)
        [[ _SIDELINE_X, _HALFCOURT_Y     ]], # (25, 47)
        [[ _SIDELINE_X, _CORNER_3_BREAK_Y]], # (25, break_y)
        [[ _CORNER_3_X, _CORNER_3_BREAK_Y]], # (22, break_y)
        ab_rwing_arc,                        # (22, ~9.08) → (8.02, 22.41)
    ])

    # ── Above Break 3 Top of Key ──────────────────────────────────────────────
    # Outer-ring slice between the two wing lines. Inner edge the offset arc over
    # the top; sides the wing lines out to the half-court line.
    ab_top_arc = _arc_points(0, 0, r_out, twL, twR, n=64)  # (-8.02,22.41) → over top → (8.02,22.41)
    polys["Above Break 3 Top of Key"] = np.vstack([
        [P_wR_half],                         # (16.8, 47)
        [P_wL_half],                         # (-16.8, 47)
        ab_top_arc,                          # (-8.02, 22.41) → over top → (8.02, 22.41)
    ])

    # ── Above Break 3 Left Wing ───────────────────────────────────────────────
    # Mirror of Above Break 3 Right Wing (above θwL).
    ab_lwing_arc = _arc_points(0, 0, r_out, 180.0 - a_out_22, twL, n=48)  # (-22,~9.08) → (-8.02,22.41)
    polys["Above Break 3 Left Wing"] = np.vstack([
        [P_wL_half],                         # (-16.8, 47)
        [[-_SIDELINE_X, _HALFCOURT_Y     ]], # (-25, 47)
        [[-_SIDELINE_X, _CORNER_3_BREAK_Y]], # (-25, break_y)
        [[-_CORNER_3_X, _CORNER_3_BREAK_Y]], # (-22, break_y)
        ab_lwing_arc,                        # (-22, ~9.08) → (-8.02, 22.41)
    ])

    # ── Normalize winding order ───────────────────────────────────────────────
    # These polygons are built by different traces (some clockwise, some counter-
    # clockwise). The verification test samples interior points with
    # Path.contains_points(radius=-margin), and that inset runs along the edge
    # normal — whose direction flips with winding order. On a clockwise polygon
    # the "-margin" therefore EXPANDS the region instead of shrinking it, pulling
    # in points just outside a boundary (e.g. paint points 0.01 ft past the x=8
    # edge). Forcing every polygon counter-clockwise makes the margin shrink the
    # region uniformly. Winding does not affect how a filled polygon renders, so
    # this is purely a correctness fix for the sampling test.
    for _name, _verts in polys.items():
        _x, _y = _verts[:, 0], _verts[:, 1]
        _signed_area = 0.5 * np.sum(_x * np.roll(_y, -1) - np.roll(_x, -1) * _y)
        if _signed_area < 0:                 # clockwise → reverse to CCW
            polys[_name] = _verts[::-1]

    return polys


def draw_zone_overlay(ax, zone_df, title=None, show_court=True,
                      cmap=_PPS_CMAP, min_scale=0.10):
    """
    Render the 11 court zones as filled polygons colored by a player's PPS
    relative to the league average PPS in each zone.

    Parameters
    ----------
    ax        : matplotlib Axes to draw on.
    zone_df   : DataFrame of ONE player's zone stats. Must contain the columns
                ZONE, PPS, FGA, and LEAGUE_AVG_PPS. Only zones present with
                FGA > 0 are colored and labeled; every other zone is drawn in
                neutral gray with no label (the player took no shots there).
    title     : optional title string for the Axes.
    show_court: if True, draw the court lines underneath the zone fills.
    cmap      : diverging colormap (default red→white→green).
    min_scale : floor for the symmetric color scale, so a player who is close to
                average everywhere still gets a sensible (not over-saturated)
                spread of color.

    Colour encoding
    ---------------
    Each zone's color is driven by (PPS - LEAGUE_AVG_PPS) for that zone — the
    player's points-per-shot minus the league average points-per-shot in the
    SAME zone. The diverging colormap is centered on 0 (exactly league average):
    red = below average, white = at average, green = above average. Every zone
    shares one symmetric scale, so the single colorbar reads consistently across
    the whole chart.

    Returns
    -------
    ax : the Axes, with the overlay drawn.
    """
    polys = build_zone_polygons()

    # Index this player's rows by zone and keep only zones with real attempts.
    stats = zone_df.set_index("ZONE")
    played = {z: stats.loc[z] for z in stats.index if stats.loc[z, "FGA"] > 0}

    # ── Shared diverging scale on (PPS - league average) ──────────────────────
    # A single symmetric limit keeps white pinned to league average everywhere.
    deltas = {z: float(row["PPS"]) - float(row["LEAGUE_AVG_PPS"])
              for z, row in played.items()}
    max_abs = max(max((abs(d) for d in deltas.values()), default=0.0), min_scale)
    norm = mcolors.TwoSlopeNorm(vmin=-max_abs, vcenter=0.0, vmax=max_abs)

    # ── Court underneath (optional) ───────────────────────────────────────────
    if show_court:
        draw_court(ax=ax, lw=2)

    # ── Draw each zone polygon, then label the ones with data ─────────────────
    label_effect = [pe.withStroke(linewidth=2.5, foreground="white")]
    for zone_name, verts in polys.items():
        has_data = zone_name in deltas
        face = cmap(norm(deltas[zone_name])) if has_data else _NO_DATA_COLOR

        ax.add_patch(MplPolygon(
            verts, closed=True,
            facecolor=face, edgecolor="#333333",
            linewidth=1.0, alpha=0.85, zorder=3,
        ))

        if has_data:
            lx, ly = _ZONE_LABEL_ANCHORS[zone_name]
            ax.text(
                lx, ly,
                f"{_ZONE_ABBREV[zone_name]}\n{float(played[zone_name]['PPS']):.2f}",
                ha="center", va="center",
                fontsize=8, fontweight="bold", color="black",
                linespacing=1.2, zorder=4, path_effects=label_effect,
            )

    # ── Axis framing (match draw_court even when show_court is False) ──────────
    ax.set_xlim(-28, 28)
    ax.set_ylim(-7, 50)
    ax.set_aspect("equal")
    ax.axis("off")

    if title:
        ax.set_title(title, fontsize=14, fontweight="bold", pad=12)

    # ── Colorbar: PPS vs League Average ───────────────────────────────────────
    sm = ScalarMappable(cmap=cmap, norm=norm)
    sm.set_array([])
    cbar = ax.figure.colorbar(
        sm, ax=ax, fraction=0.030, pad=0.03, aspect=28, shrink=0.6,
    )
    cbar.set_label("PPS vs League Average", fontsize=11, labelpad=10)
    cbar.set_ticks([-max_abs, 0.0, max_abs])
    cbar.set_ticklabels([
        f"Below Avg\n(-{max_abs:.2f})",
        "League Avg",
        f"Above Avg\n(+{max_abs:.2f})",
    ], fontsize=8)

    return ax
