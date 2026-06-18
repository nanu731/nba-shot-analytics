"""
src/court.py — Reusable NBA half-court drawing utility.

All coordinates are in feet with the basket at the origin (0, 0),
matching the coordinate system used in shots_cleaned.csv.
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle, Arc

# The corner-3 straight lines (at x = ±22 ft) meet the above-break arc
# (radius 23.75 ft) at this y-value. Derived from Pythagorean theorem:
# y = sqrt(23.75² - 22²) ≈ 8.95 ft from the basket.
_CORNER_3_BREAK_Y = float(np.sqrt(23.75**2 - 22.0**2))


def draw_court(ax=None, color=None, lw=2, fig_size=(12, 11), dark_bg=False):
    """
    Draw a regulation NBA half-court on a matplotlib Axes.

    All measurements are in feet. The basket sits at (0, 0); the baseline
    is at y = -4.75 ft and half court is at y = 47 ft.

    Parameters
    ----------
    ax       : matplotlib Axes to draw on. Creates a new figure if None.
    color    : line color for all court markings. Defaults to 'white' when
               dark_bg=True, 'black' otherwise.
    lw       : line width for court markings (default 2)
    fig_size : (width, height) in inches — only used when ax is None
    dark_bg  : if True, use a dark navy background with white lines

    Returns
    -------
    ax : the Axes with the court drawn on it
    """
    if ax is None:
        _, ax = plt.subplots(figsize=fig_size)

    if color is None:
        color = "white" if dark_bg else "black"

    ax.set_facecolor("#1a2a4a" if dark_bg else "white")

    # ── Basket ──────────────────────────────────────────────────────────────
    # NBA rim: 18-inch diameter → 0.75-foot radius.
    ax.add_patch(Circle((0, 0), radius=0.75, linewidth=lw, color=color, fill=False))

    # ── Backboard ───────────────────────────────────────────────────────────
    # Front face of backboard sits ~0.75 ft behind basket center; 6 ft wide.
    ax.plot([-3, 3], [-0.75, -0.75], linewidth=lw * 1.5, color=color)

    # ── Restricted Area Arc ─────────────────────────────────────────────────
    # 4-foot radius semicircle facing half court.
    ax.add_patch(Arc(
        (0, 0), width=8, height=8,
        angle=0, theta1=0, theta2=180,
        color=color, linewidth=lw,
    ))

    # ── Paint / Lane ────────────────────────────────────────────────────────
    # 16 ft wide (±8 ft from center).
    # Runs from baseline (y = -4.75) to free throw line (19 ft from baseline
    # = 14.25 ft from basket center in our coordinate system).
    ax.add_patch(Rectangle(
        (-8, -4.75), width=16, height=19,
        linewidth=lw, edgecolor=color, facecolor="none",
    ))

    # ── Free Throw Circle ───────────────────────────────────────────────────
    # Radius 6 ft, centered on the free throw line at (0, 14.25).
    # Upper half: solid arc (above the line, outside the paint visually).
    # Lower half: dashed arc (inside the paint).
    ax.add_patch(Arc(
        (0, 14.25), width=12, height=12,
        angle=0, theta1=0, theta2=180,
        color=color, linewidth=lw,
    ))
    ax.add_patch(Arc(
        (0, 14.25), width=12, height=12,
        angle=0, theta1=180, theta2=360,
        color=color, linewidth=lw, linestyle="dashed",
    ))

    # ── 3-Point Line ────────────────────────────────────────────────────────
    # Corner straight sections: vertical lines at x = ±22 ft, running from
    # the baseline up to the break point where the arc begins.
    break_y = _CORNER_3_BREAK_Y
    ax.plot([ 22,  22], [-4.75, break_y], linewidth=lw, color=color)
    ax.plot([-22, -22], [-4.75, break_y], linewidth=lw, color=color)

    # Above-break arc: radius 23.75 ft, from right break point to left
    # break point (counterclockwise through the top of the key).
    break_angle = np.degrees(np.arctan2(break_y, 22))   # ≈ 22.1°
    ax.add_patch(Arc(
        (0, 0), width=23.75 * 2, height=23.75 * 2,
        angle=0,
        theta1=break_angle,
        theta2=180 - break_angle,
        color=color, linewidth=lw,
    ))

    # ── Half-Court Line and Center Circle ────────────────────────────────────
    # Half court is 47 ft from the basket.
    ax.plot([-25, 25], [47, 47], linewidth=lw, color=color)

    # Draw only the lower half of the center circle (facing the basket).
    ax.add_patch(Arc(
        (0, 47), width=12, height=12,
        angle=0, theta1=180, theta2=360,
        color=color, linewidth=lw,
    ))

    # ── Court Boundary ──────────────────────────────────────────────────────
    ax.plot([-25,  25], [-4.75, -4.75], linewidth=lw, color=color)  # baseline
    ax.plot([-25, -25], [-4.75,    47], linewidth=lw, color=color)  # left sideline
    ax.plot([ 25,  25], [-4.75,    47], linewidth=lw, color=color)  # right sideline

    # ── Axis Formatting ─────────────────────────────────────────────────────
    ax.set_xlim(-28, 28)
    ax.set_ylim(-7, 50)
    ax.set_aspect("equal")
    ax.axis("off")

    return ax
