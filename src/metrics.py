"""
src/metrics.py — Court zone classification and shooting metric functions.

All spatial functions use feet with the basket at (0, 0), matching the
coordinate system in shots_cleaned.csv.
"""

import numpy as np

# Where the corner-3 straight lines (at x = ±22 ft) meet the above-break
# arc (radius 23.75 ft). Derived from: y = sqrt(23.75² - 22²) ≈ 8.95 ft.
_CORNER_3_BREAK_Y = float(np.sqrt(23.75**2 - 22.0**2))


def assign_zone(loc_x_ft: float, loc_y_ft: float) -> str:
    """
    Assign a court location to one of 11 named NBA zones.

    Parameters
    ----------
    loc_x_ft : horizontal distance from basket center (negative = left)
    loc_y_ft : depth from basket toward half court (0 = basket, ~47 = half court)

    Returns
    -------
    Zone name as a string — always returns a value, never None.
    """
    dist = np.sqrt(loc_x_ft**2 + loc_y_ft**2)

    if loc_y_ft > 47.0:
        return "Backcourt"
    if loc_x_ft <= -22.0 and loc_y_ft <= _CORNER_3_BREAK_Y:
        return "Left Corner 3"
    if loc_x_ft >= 22.0 and loc_y_ft <= _CORNER_3_BREAK_Y:
        return "Right Corner 3"
    if dist >= 23.75:
        if loc_x_ft < -7.0:
            return "Above Break 3 Left"
        elif loc_x_ft <= 7.0:
            return "Above Break 3 Center"
        else:
            return "Above Break 3 Right"
    if dist <= 4.0:
        return "Restricted Area"
    if abs(loc_x_ft) <= 8.0 and loc_y_ft <= 14.5:
        return "Paint (Non-RA)"
    if loc_x_ft < -7.0:
        return "Mid-Range Left"
    elif loc_x_ft <= 7.0:
        return "Mid-Range Center"
    else:
        return "Mid-Range Right"


def compute_efg(fgm: float, fg3m: float, fga: float) -> float:
    """eFG% = (FGM + 0.5 × 3PM) / FGA. Returns NaN if FGA == 0."""
    return (fgm + 0.5 * fg3m) / fga if fga > 0 else float("nan")


def compute_pps(points: float, fga: float) -> float:
    """Points per shot attempt. Returns NaN if FGA == 0."""
    return points / fga if fga > 0 else float("nan")
