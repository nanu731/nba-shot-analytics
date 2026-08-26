# Constructs the 14 zone outlines analytically from court geometry and the classification
# thresholds recovered from the labelled data. Nothing here is fitted to the shot cloud:
# every vertex is generated from a declared primitive, which is why the arc parameters
# emitted alongside the vertices are a source rather than a reconstruction.
#
#   Rscript R/08_zone_polygons.R
#
# Writes export/reference/zone_polygons.json for the website and for R/07's checker.

library(tidyverse)
library(glue)
library(jsonlite)

# point_in_polygon() is defined in the checker; the anchor search reuses it.
source("R/07_zone_geometry.R")

# --- Geometry, in NBA shot-chart units: tenths of a foot, hoop at the origin -----------
# Shot coordinates are integers, so each threshold is placed in the gap between the last
# value on one side and the first on the other, measured across all five seasons. A
# threshold sitting exactly on an integer leaves shots on the line, where ray casting is
# undefined. The nominal court value is given for each.
BASE   <- -52.5     # baseline; deepest shot is y = -52
PAINT  <- 80.5      # paint wall, nominally 80: last paint |x| = 80, first mid-range = 81
FT     <- 138.5     # free throw line, nominally 137.5: last paint y = 138, first mid = 139
R_RA   <- 39.98     # restricted area, nominally 40: last RA r = 39.9625, first paint = 40
R8     <- 80.003    # 8 ft band: paint centre includes r = 80, paint side starts at 80.0062
R16    <- 160.006   # 16 ft band: r = 160 is still the inner band, LC/RC start at 160.0125
R3     <- 237.5     # three point arc: last mid-range r = 237.4974, first arc3 = 237.5079
CORNER <- 219.5     # corner segment, nominally 220: last mid-range |x| = 219, corner = 220
BREAK  <- 87.5      # corner / above-the-break cut: last corner y = 87, first arc3 = 88
SIDE   <- 250.5     # sideline, nominally 250: furthest shot is |x| = 250
TOP    <- 430       # generous top bound; the furthest shot in five seasons is y = 397

ARC_STEP <- 0.5    # degrees. At r = 237.5 this puts chord error at 0.002 units.

deg <- function(d) d * pi / 180
on_arc <- function(r, a) c(r * cos(deg(a)), r * sin(deg(a)))

# Angle at which a circle of radius r crosses a horizontal line y = h.
ang_at_y <- function(r, h) asin(h / r) * 180 / pi
# Radius at which a ray at angle a crosses y = h.
rad_at_y <- function(a, h) h / sin(deg(a))

arc_pts <- function(r, a1, a2, step = ARC_STEP) {
  n <- max(2L, ceiling(abs(a2 - a1) / step) + 1L)
  a <- seq(a1, a2, length.out = n)
  cbind(r * cos(deg(a)), r * sin(deg(a)))
}

# A zone is a list of segments. Each is either a line to a point, or an arc about the
# hoop. Vertices are generated from these; the arc records are kept and exported.
ln <- function(x, y) list(kind = "line", to = c(x, y))
ar <- function(r, a1, a2) list(kind = "arc", r = r, a1 = a1, a2 = a2)

build <- function(start, segs) {
  pts <- matrix(start, ncol = 2)
  arcs <- list()
  for (s in segs) {
    if (s$kind == "line") {
      pts <- rbind(pts, s$to)
    } else {
      p <- arc_pts(s$r, s$a1, s$a2)
      pts <- rbind(pts, p)
      arcs[[length(arcs) + 1]] <- list(r = s$r, start_deg = s$a1, end_deg = s$a2,
                                       centre = c(0, 0))
    }
  }
  # Drop a duplicated closing vertex; polygons are implicitly closed.
  if (isTRUE(all.equal(pts[1, ], pts[nrow(pts), ]))) pts <- pts[-nrow(pts), , drop = FALSE]
  list(vertices = pts, arcs = arcs)
}

mirror <- function(z) {
  z$vertices[, 1] <- -z$vertices[, 1]
  z$arcs <- map(z$arcs, \(a) { a2 <- a; a2$start_deg <- 180 - a$start_deg
                               a2$end_deg <- 180 - a$end_deg; a2 })
  z
}

# --- Derived intersections -------------------------------------------------------------
A_BASE_R8  <- ang_at_y(R8, BASE)          # r=80 meets the baseline, right side: -41.05
X_BASE_R8  <- sqrt(R8^2 - BASE^2)
R_FT_60    <- rad_at_y(60, FT)            # 60 deg ray meets the free throw line: 158.83
X_FT_60    <- R_FT_60 * cos(deg(60))
A_BREAK_R3 <- ang_at_y(R3, BREAK)         # arc meets y = 87.5 at 21.63 deg
X_BREAK_R3 <- sqrt(R3^2 - BREAK^2)
X_TOP_72   <- TOP / tan(deg(72))

zones <- list()

zones$restricted_area <- build(on_arc(R_RA, 0), list(ar(R_RA, 0, 360)))

# The paint centre wraps all the way around the restricted area, so it is an annulus and
# is emitted as a keyhole: out along a slit, around the hole the other way, back in. The
# slit sits at x = 0.5 so no integer shot coordinate lies on it.
SLIT_X <- 0.5
SLIT_Y <- -sqrt(R_RA^2 - SLIT_X^2)
A_SLIT <- atan2(SLIT_Y, SLIT_X) * 180 / pi
zones$paint_center <- build(
  c(X_BASE_R8, BASE),
  list(ar(R8, A_BASE_R8, 60), ln(X_FT_60, FT), ln(-X_FT_60, FT),
       ar(R8, 120, 180 - A_BASE_R8), ln(-X_BASE_R8, BASE),
       ln(SLIT_X, BASE), ln(SLIT_X, SLIT_Y),
       ar(R_RA, A_SLIT, A_SLIT - 360),
       ln(SLIT_X, BASE), ln(X_BASE_R8, BASE)))

zones$paint_right <- build(
  c(X_BASE_R8, BASE),
  list(ln(PAINT, BASE), ln(PAINT, FT), ln(X_FT_60, FT),
       ln(on_arc(R8, 60)[1], on_arc(R8, 60)[2]),
       ar(R8, 60, A_BASE_R8)))
zones$paint_left <- mirror(zones$paint_right)

zones$midrange_right <- build(
  c(PAINT, BASE),
  list(ln(CORNER, BASE), ln(CORNER, BREAK), ln(X_BREAK_R3, BREAK),
       ar(R3, A_BREAK_R3, 36), ar(R16, 36, 60),
       ln(X_FT_60, FT), ln(PAINT, FT), ln(PAINT, BASE)))
zones$midrange_left <- mirror(zones$midrange_right)

zones$midrange_right_center <- build(
  on_arc(R16, 36),
  list(ar(R3, 36, 72), ar(R16, 72, 36)))
zones$midrange_left_center <- mirror(zones$midrange_right_center)
# The ray segments between the two arcs are implicit in the vertex order.

zones$midrange_center <- build(
  c(X_FT_60, FT),
  list(ar(R16, 60, 72), ar(R3, 72, 108), ar(R16, 108, 120), ln(-X_FT_60, FT)))

zones$corner3_right <- build(c(CORNER, BASE),
  list(ln(SIDE, BASE), ln(SIDE, BREAK), ln(CORNER, BREAK)))
zones$corner3_left <- mirror(zones$corner3_right)

zones$arc3_right_center <- build(
  c(X_BREAK_R3, BREAK),
  list(ln(SIDE, BREAK), ln(SIDE, TOP), ln(X_TOP_72, TOP),
       ar(R3, 72, A_BREAK_R3)))
zones$arc3_left_center <- mirror(zones$arc3_right_center)

zones$arc3_center <- build(
  on_arc(R3, 72),
  list(ln(X_TOP_72, TOP), ln(-X_TOP_72, TOP), ar(R3, 108, 72)))

write_polygons <- function(path = "export/reference/zone_polygons.json", anchors = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  out <- imap(zones, \(z, id) {
    e <- list(vertices = unname(lapply(seq_len(nrow(z$vertices)),
                                       \(i) round(as.numeric(z$vertices[i, ]), 3))))
    if (length(z$arcs)) e$arcs <- unname(map(z$arcs, \(a)
      list(centre = a$centre, r = a$r,
           start_deg = round(a$start_deg, 4), end_deg = round(a$end_deg, 4))))
    if (!is.null(anchors)) e$anchor <- as.numeric(anchors[[id]])
    e
  })
  write_json(out, path, auto_unbox = TRUE, digits = NA)
  cat(glue("  {path}  {round(file.size(path)/1024,1)} KB"), "\n")
  invisible(path)
}

# A bare vertex-only file for R/07's checker, which expects id -> array of [x, y].
write_candidate <- function(path) {
  out <- map(zones, \(z) unname(lapply(seq_len(nrow(z$vertices)),
                                       \(i) round(as.numeric(z$vertices[i, ]), 4))))
  write_json(out, path, auto_unbox = TRUE, digits = NA)
  invisible(path)
}

# Label anchors: the point inside each zone furthest from its own boundary, the pole of
# inaccessibility. Derived from the shipped polygons, so there is no second copy of the
# geometry that could drift. A centroid would not do -- the paint centre is an annulus
# and its centroid falls in the restricted-area hole.
densify <- function(v, step = 2) {
  w <- rbind(v, v[1, ])
  out <- map(seq_len(nrow(w) - 1), \(i) {
    d <- sqrt(sum((w[i + 1, ] - w[i, ])^2))
    k <- max(1L, ceiling(d / step))
    cbind(seq(w[i, 1], w[i + 1, 1], length.out = k + 1)[-(k + 1)],
          seq(w[i, 2], w[i + 1, 2], length.out = k + 1)[-(k + 1)])
  })
  do.call(rbind, out)
}

zone_anchors <- function(step = 4) {
  gx <- seq(-255, 255, by = step); gy <- seq(-55, 425, by = step)
  grid <- expand_grid(x = gx, y = gy)
  map(set_names(names(zones)), \(id) {
    v <- zones[[id]]$vertices
    inside <- point_in_polygon(grid$x, grid$y, v)
    pts <- grid[inside, ]
    edge <- densify(v)
    d <- map_dbl(seq_len(nrow(pts)), \(i)
      min((pts$x[i] - edge[, 1])^2 + (pts$y[i] - edge[, 2])^2))
    c(round(pts$x[which.max(d)], 1), round(pts$y[which.max(d)], 1))
  })
}

if (sys.nframe() == 0L) {
  cat("vertices per zone\n")
  for (id in names(zones)) cat(sprintf("  %-22s %5d\n", id, nrow(zones[[id]]$vertices)))
  write_candidate("export/reference/zone_polygons_vertices.json")
  anchors <- zone_anchors()
  cat("\nlabel anchors\n")
  for (id in names(zones)) cat(sprintf("  %-22s (%7.1f, %7.1f)\n", id, anchors[[id]][1], anchors[[id]][2]))
  cat("\n"); write_polygons(anchors = anchors)
}
