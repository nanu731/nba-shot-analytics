# The zone model. This file is the only place a zone boundary is defined.
#
# Zones are computed from shot coordinates, not read from the NBA's labels. See rule A4,
# which was rewritten on 2026-08-27 to permit this, and ASSUMPTIONS.md for why.
#
# Two artifacts come out of the one definition below: classify_zone() assigns a shot to a
# zone, and zone_polygon() draws that zone's outline. Neither derives from the other, so
# there is no direction in which one can drift ahead of the other. Changing a boundary is a
# one-line edit here that moves both. R/07_zone_geometry.R checks they still agree.
#
# Units are tenths of a foot, hoop at the origin, y increasing away from the baseline.

library(tidyverse)

# --- Court primitives ------------------------------------------------------------------
# Almost every number below is a real court marking or a ray chosen to pass through one.
# Two are not, and both say so where they are defined: CORNER_TOP and Y_BACKCOURT are
# measured from the data, because the feature they mark has no court line to sit on.

R_RIM      <- 40      # restricted area
LANE_HALF  <- 80      # lane half-width
LANE_TOP   <- 137.5   # free throw line, 15 ft from the backboard face. Nominal, and
                      # deliberately not the 138.5 the NBA's labels imply. See below.
BASELINE   <- -52.5   # baseline
R_ARC      <- 237.5   # three-point arc
CORNER_X   <- 220     # corner three straight segment
CORNER_TOP <- 87.5    # where the corner segment ends; measured from the labels, not
                      # geometry. The arc meets x = 220 at y = 89.478, so the two do not
                      # quite close. See "the notch" below.
SIDELINE   <- 250

# The far edge of the partition. Backcourt heaves are excluded entirely, as they are on
# the NBA's own charts, and this is where they start.
#
# MEASURED, NOT GEOMETRIC. The true half-court line is y = 417.5 (47 ft less the hoop's
# 5.25 ft from the baseline), and 149 backcourt-labelled shots sit inside it: heaves whose
# recorded coordinate lands short of where the ball was released. Excluding those is the
# point of the filter, so the cut goes below them. 397.5 is the gap between the maximum
# in-play y (397) and the minimum backcourt y (398), measured across all five seasons, and
# it reproduces the old SHOT_ZONE_BASIC = 'Backcourt' filter shot for shot.
#
# Do not "correct" this to 417.5. Same hazard as the corner break at 87.5, which is also
# measured and also looks wrong against a court diagram.
Y_BACKCOURT <- 397.5

# Polygons close on the same line, so the outlines cover exactly what the classifier
# assigns and no more. A larger bound would leave a band belonging to a zone by polygon
# and to nothing by classifier.
TOP_BOUND  <- Y_BACKCOURT

# Mid-range dividing rays pass through the third lane space mark at (+/- 80, 77.5), which
# is 13 feet from the baseline: -52.5 + 130 = 77.5.
LANE_MARK_Y <- 77.5
MID_RAY     <- atan2(LANE_MARK_Y, LANE_HALF) * 180 / pi   # 44.0906 degrees
ARC_RAY     <- 60                                          # above-the-break divider

# Boundary inclusivity, verified across all 1,089,337 in-play shots. Shot coordinates are
# integers, so what matters at each threshold is which side an exact hit falls on.
#
#   rim     r <  R_RIM        max r under a Restricted Area label is 39.96248; the 129
#                             shots at exactly r = 40 are all labelled paint, and the
#                             strict < sends them to paint too.
#   lane    |x| <= LANE_HALF  paint labels reach |x| = 80; Mid-Range beside the lane
#                             starts at |x| = 81. Inclusive is right.
#   corner  |x| >= CORNER_X   Mid-Range reaches |x| = 219; corner threes start at 220.
#
#   lane    y <= LANE_TOP     THE ONE PLACE THIS MODEL AND THE LABELS PART. The NBA's cut
#                             is at 138.5 -- paint labels reach y = 138, Mid-Range inside
#                             the lane starts at 139 -- and LANE_TOP is the nominal
#                             free-throw line at 137.5 instead. 799 shots at y = 138 are
#                             In The Paint (Non-RA) by label and mid_center here, and they
#                             are the only paint-family disagreement anywhere in the five
#                             seasons. Chosen, not inherited: 138.5 is an artifact of the
#                             labelling convention this model retires, while 137.5 is
#                             where the line is painted. Do not "correct" it to 138.5.
#                             ASSUMPTIONS entry 37. No integer y can equal 137.5, so
#                             nothing sits on the boundary.

# arc3_top is deliberately not called arc3_center. The 14-zone model had an id of that
# name for the NBA's roughly 72-108 degree wedge; this zone is the 60-120 degree one, at
# 29,332 qualifying attempts in 2025-26 against that zone's 15,586. Reusing the string
# would let a site holding the old outline draw the narrow wedge against the wide wedge's
# number, with nothing raising an error. corner3_left and corner3_right keep their names
# because their membership is identical across both models, shot for shot.
ZONE_IDS <- c("rim", "paint",
              "mid_left", "mid_center", "mid_right",
              "corner3_left", "arc3_left", "arc3_top", "arc3_right", "corner3_right")

ZONE_VALUE <- c(rim = 2, paint = 2,
                mid_left = 2, mid_center = 2, mid_right = 2,
                corner3_left = 3, arc3_left = 3, arc3_top = 3,
                arc3_right = 3, corner3_right = 3)

# --- The classifier --------------------------------------------------------------------

# A shot is a three-pointer if it is beyond the corner segment below the break, or beyond
# the arc above it. Written as one expression so the two cases cannot be reordered into
# disagreement.
is_three <- function(x, y) {
  r <- sqrt(x^2 + y^2)
  (abs(x) >= CORNER_X & y < CORNER_TOP) | (r >= R_ARC & y >= CORNER_TOP)
}

#' Assign each shot to one of the ten zones. Vectorised; returns a character vector, NA
#' beyond Y_BACKCOURT. NA is the honest shape there: a backcourt heave is outside the
#' partition rather than a member of some zone, and it makes stage 2 drop it explicitly
#' instead of absorbing it into arc3_top, which is what an unbounded classifier does.
classify_zone <- function(x, y) {
  r   <- sqrt(x^2 + y^2)
  ang <- atan2(y, x) * 180 / pi          # (-180, 180]
  three <- is_three(x, y)

  # Below the hoop's own line the left/right split is by sign of x, not by angle: atan2
  # returns values near -180 there, and a naive `ang >= 135.9` test silently drops those
  # shots into mid_center. 18,257 shots sit in that region on the left alone. The -90
  # cutoff is safe because a mid-range shot at y < 0 must have |x| > LANE_HALF, so no shot
  # can sit exactly on it.
  case_when(
    y > Y_BACKCOURT                                  ~ NA_character_,
    r < R_RIM                                        ~ "rim",
    abs(x) <= LANE_HALF & y <= LANE_TOP              ~ "paint",

    three & y <  CORNER_TOP & x <  0                 ~ "corner3_left",
    three & y <  CORNER_TOP & x >= 0                 ~ "corner3_right",
    three & ang >= 180 - ARC_RAY                     ~ "arc3_left",
    three & ang <= ARC_RAY                           ~ "arc3_right",
    three                                            ~ "arc3_top",

    ang >= 180 - MID_RAY | ang <= -90                ~ "mid_left",
    ang <= MID_RAY       & ang >  -90                ~ "mid_right",
    .default = "mid_center"
  )
}

# --- Polygons --------------------------------------------------------------------------
#
# The outlines render the classifier above. Where a boundary sits on a whole number, an
# integer shot coordinate can land exactly on it, and ray casting there is undefined. The
# polygon is therefore offset by EPS in the direction the classifier's inclusivity implies:
# rim shrinks (r < R_RIM excludes the boundary), the lane grows (|x| <= LANE_HALF includes
# it), the corner grows inward (|x| >= CORNER_X includes it).
#
# EPS is a rendering allowance, not a second definition. It is smaller than the gap between
# any two achievable integer coordinates, so it moves no shot between zones; R/07 proves
# that against all 1,089,337 real coordinates.

EPS <- 0.02

P_RIM     <- R_RIM - EPS
P_LANE    <- LANE_HALF + EPS
P_CORNER  <- CORNER_X - EPS
P_SIDE    <- SIDELINE + EPS     # shots exist at exactly |x| = 250
P_MID_RAY <- MID_RAY + 0.0002   # integer points sit exactly on this ray, e.g. (160, 155)

# Where the nudged ray meets the nudged lane wall. Anchoring the ray edge here rather than
# at the true lane mark keeps that edge a true constant-angle ray: starting it at
# (P_LANE, LANE_MARK_Y) would make it a chord that crosses the real ray, putting points at
# exactly MID_RAY on the wrong side near the wall.
P_MARK_Y  <- P_LANE * tan(P_MID_RAY * pi / 180)

deg      <- function(d) d * pi / 180
on_ray   <- function(a, r) c(r * cos(deg(a)), r * sin(deg(a)))
ang_at_y <- function(r, y) asin(y / r) * 180 / pi
rad_at_y <- function(a, y) y / sin(deg(a))

ARC_STEP <- 0.5   # degrees; chord error at R_ARC is about 0.002 units

arc_pts <- function(r, a1, a2) {
  n <- max(2L, ceiling(abs(a2 - a1) / ARC_STEP) + 1L)
  a <- seq(a1, a2, length.out = n)
  cbind(r * cos(deg(a)), r * sin(deg(a)))
}

ln <- function(x, y) list(kind = "line", to = c(x, y))
ar <- function(r, a1, a2) list(kind = "arc", r = r, a1 = a1, a2 = a2)

build <- function(start, segs) {
  pts <- matrix(start, ncol = 2)
  arcs <- list()
  for (s in segs) {
    if (s$kind == "line") {
      pts <- rbind(pts, s$to)
    } else {
      pts <- rbind(pts, arc_pts(s$r, s$a1, s$a2))
      arcs[[length(arcs) + 1]] <- list(centre = c(0, 0), r = s$r,
                                       start_deg = s$a1, end_deg = s$a2)
    }
  }
  if (isTRUE(all.equal(pts[1, ], pts[nrow(pts), ]))) pts <- pts[-nrow(pts), , drop = FALSE]
  list(vertices = pts, arcs = arcs)
}

mirror <- function(z) {
  z$vertices[, 1] <- -z$vertices[, 1]
  z$arcs <- map(z$arcs, \(a) { a$start_deg <- 180 - a$start_deg
                               a$end_deg   <- 180 - a$end_deg; a })
  z
}

# Derived intersections, all from the constants above.
A_NOTCH   <- ang_at_y(R_ARC, CORNER_TOP)          # arc at the corner break: 21.63 deg
X_NOTCH   <- sqrt(R_ARC^2 - CORNER_TOP^2)         # 220.79 -- outside CORNER_X by 0.79
R_MID_IN  <- rad_at_y(ARC_RAY, TOP_BOUND)         # 60 deg ray at the top bound
X_TOP_ARC <- TOP_BOUND / tan(deg(ARC_RAY))

.zones <- local({
  z <- list()

  z$rim <- build(on_ray(0, P_RIM), list(ar(P_RIM, 0, 360)))

  # The lane minus the rim disc, so paint is a keyhole. The slit runs out at x = 0.25,
  # which no integer coordinate can equal, and doubles back around the hole the other way.
  SLIT   <- 0.25
  SLIT_Y <- -sqrt(P_RIM^2 - SLIT^2)
  A_SLIT <- atan2(SLIT_Y, SLIT) * 180 / pi
  z$paint <- build(
    c(P_LANE, BASELINE),
    list(ln(P_LANE, LANE_TOP), ln(-P_LANE, LANE_TOP), ln(-P_LANE, BASELINE),
         ln(SLIT, BASELINE), ln(SLIT, SLIT_Y),
         ar(P_RIM, A_SLIT, A_SLIT - 360),
         ln(SLIT, BASELINE), ln(P_LANE, BASELINE)))

  # Mid-range right: lane wall up to the lane mark, out along the ray to the arc, down the
  # arc to the corner break, in across the notch, then down the corner line to the
  # baseline. The notch is the 0.79-unit step where the corner segment and the arc fail to
  # meet; no shot has ever landed in it.
  z$mid_right <- build(
    c(P_LANE, BASELINE),
    list(ln(P_LANE, P_MARK_Y),
         ln(on_ray(P_MID_RAY, R_ARC)[1], on_ray(P_MID_RAY, R_ARC)[2]),
         ar(R_ARC, P_MID_RAY, A_NOTCH),
         ln(X_NOTCH, CORNER_TOP), ln(P_CORNER, CORNER_TOP),
         ln(P_CORNER, BASELINE)))
  z$mid_left <- mirror(z$mid_right)

  z$mid_center <- build(
    c(P_LANE, P_MARK_Y),
    list(ln(on_ray(P_MID_RAY, R_ARC)[1], on_ray(P_MID_RAY, R_ARC)[2]),
         ar(R_ARC, P_MID_RAY, 180 - P_MID_RAY),
         ln(-P_LANE, P_MARK_Y), ln(-P_LANE, LANE_TOP), ln(P_LANE, LANE_TOP)))

  z$corner3_right <- build(c(P_CORNER, BASELINE),
    list(ln(P_SIDE, BASELINE), ln(P_SIDE, CORNER_TOP), ln(P_CORNER, CORNER_TOP)))
  z$corner3_left <- mirror(z$corner3_right)

  z$arc3_right <- build(
    c(X_NOTCH, CORNER_TOP),
    list(ln(P_SIDE, CORNER_TOP), ln(P_SIDE, TOP_BOUND), ln(X_TOP_ARC, TOP_BOUND),
         ar(R_ARC, ARC_RAY, A_NOTCH)))
  z$arc3_left <- mirror(z$arc3_right)

  z$arc3_top <- build(
    on_ray(ARC_RAY, R_ARC),
    list(ln(X_TOP_ARC, TOP_BOUND), ln(-X_TOP_ARC, TOP_BOUND),
         ar(R_ARC, 180 - ARC_RAY, ARC_RAY)))

  z[ZONE_IDS]
})

#' Outline for one zone: vertices, plus arc records for the curved edges.
zone_polygon <- function(id) {
  if (!id %in% ZONE_IDS) stop(glue::glue("unknown zone id: {id}"), call. = FALSE)
  .zones[[id]]
}

zone_polygons <- function() .zones
