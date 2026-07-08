"""
src/metrics.py — Court zone classification and shooting metric functions.

All spatial functions use feet with the basket at (0, 0), matching the
coordinate system in shots_cleaned.csv.

Zone model (12 zones)
---------------------
Four fixed zones — Restricted Area, Paint (Non-RA), Left Corner 3, Right
Corner 3 — plus eight zones that fan out from the basket along four radial
lines. The radial lines are shared between the mid-range (inner) and above-
break 3 (outer) rings, so the boundary between, say, Left Corner and Left Wing
is the same continuous angled line in both rings. The two "corner" radial lines
pass through the corner-break points (x = ±22 on the 23.75 ft arc); the two
"wing" radial lines pass through the points where the paint edges (x = ±8) meet
the 23.75 ft arc, which lines the Top of Key up with the width of the paint.
"""

import numpy as np

# ── Boundary constants ───────────────────────────────────────────────────────
_RA_RADIUS        = 4.0     # Restricted Area radius
_PAINT_HALF_WIDTH = 8.0     # paint spans x in [-8, 8]
_PAINT_Y_TOP      = 14.5    # paint top (free-throw line) in this coordinate frame
_CORNER_3_X       = 22.0    # straight corner-3 line at |x| = 22
_ARC_3_RADIUS     = 23.75   # above-break 3-point arc radius

# y where x = ±22 meets the arc (corner break) and where x = ±8 meets the arc.
_CORNER_3_BREAK_Y = float(np.sqrt(_ARC_3_RADIUS**2 - _CORNER_3_X**2))        # ≈ 8.95
_WING_BREAK_Y     = float(np.sqrt(_ARC_3_RADIUS**2 - _PAINT_HALF_WIDTH**2))  # ≈ 22.36

# ── Radial boundary angles (degrees from the +x axis) ────────────────────────
# Measured from the basket. Corner lines pass through (±22, break_y); wing lines
# pass through (±8, wing_break_y). Left angles are the mirror of the right ones.
_THETA_CORNER_R = float(np.degrees(np.arctan2(_CORNER_3_BREAK_Y, _CORNER_3_X)))       # ≈ 22.14
_THETA_WING_R   = float(np.degrees(np.arctan2(_WING_BREAK_Y, _PAINT_HALF_WIDTH)))     # ≈ 70.31
_THETA_WING_L   = 180.0 - _THETA_WING_R                                               # ≈ 109.69
_THETA_CORNER_L = 180.0 - _THETA_CORNER_R                                             # ≈ 157.86


def assign_zone(loc_x_ft: float, loc_y_ft: float) -> str:
    """
    Assign a court location to one of the 12 named NBA zones.

    Parameters
    ----------
    loc_x_ft : horizontal distance from basket center (negative = left)
    loc_y_ft : depth from basket toward half court (0 = basket, ~47 = half court)

    Returns
    -------
    Zone name as a string — always returns a value, never None.
    """
    x = loc_x_ft
    y = loc_y_ft
    dist = np.sqrt(x**2 + y**2)

    # ── Fixed zones (highest priority) ────────────────────────────────────────
    if dist <= _RA_RADIUS:
        return "Restricted Area"
    if x <= -_CORNER_3_X and y <= _CORNER_3_BREAK_Y:
        return "Left Corner 3"
    if x >= _CORNER_3_X and y <= _CORNER_3_BREAK_Y:
        return "Right Corner 3"
    if abs(x) <= _PAINT_HALF_WIDTH and y <= _PAINT_Y_TOP:
        return "Paint (Non-RA)"

    # ── Radial rings ──────────────────────────────────────────────────────────
    # Angle of the shot from the basket, measured so the wraparound seam sits at
    # straight-down (theta = -90°) behind the basket. That region is always RA or
    # paint (handled above), so no radial shot is ever near the seam and plain
    # linear angle comparisons are safe — including for shots behind the basket.
    theta = np.degrees(np.arctan2(y, x))
    if theta < -90.0:
        theta += 360.0

    if dist >= _ARC_3_RADIUS:
        # Outer ring — above-break 3 (the outer corners are the flat corner-3s).
        if theta > _THETA_WING_L:
            return "Above Break 3 Left Wing"
        if theta > _THETA_WING_R:
            return "Above Break 3 Top of Key"
        return "Above Break 3 Right Wing"

    # Inner ring — mid-range, split into five radial slices.
    if theta > _THETA_CORNER_L:
        return "Mid-Range Left Corner"
    if theta > _THETA_WING_L:
        return "Mid-Range Left Wing"
    if theta > _THETA_WING_R:
        return "Mid-Range Top of Key"
    if theta > _THETA_CORNER_R:
        return "Mid-Range Right Wing"
    return "Mid-Range Right Corner"


def compute_efg(fgm: float, fg3m: float, fga: float) -> float:
    """eFG% = (FGM + 0.5 × 3PM) / FGA. Returns NaN if FGA == 0."""
    return (fgm + 0.5 * fg3m) / fga if fga > 0 else float("nan")


def compute_pps(points: float, fga: float) -> float:
    """Points per shot attempt. Returns NaN if FGA == 0."""
    return points / fga if fga > 0 else float("nan")
