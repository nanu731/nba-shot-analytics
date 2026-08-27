# Geometry tooling for the 10-zone model: it writes the outlines and it checks them.
#
# Nothing here defines a boundary. Every shape comes from zone_polygon() in R/zone_model.R,
# which rule A4 makes the only place a boundary may be defined. This file used to check
# hand-authored outlines against the NBA's labels; that question died with the labels, and
# what replaced it is a stricter one -- do the two artifacts generated from the shared
# constants, the classifier and the outline, agree with each other?
#
#   Rscript R/07_zone_geometry.R          # write the reference grid and the outlines
#   Rscript R/07_zone_geometry.R check    # run the checker
#
# The checker is a test that can fail, not a build step. It is not part of the pipeline.

library(tidyverse)
library(arrow)
library(duckdb)
library(DBI)
library(glue)
library(jsonlite)

source("R/zone_model.R")

GRID_CELL     <- 5      # half a foot; fine enough to trace, coarse enough to stay aggregate
GRID_PATH     <- "export/reference/zone_grid.csv"
POLY_PATH     <- "export/reference/zone_polygons.json"
DEFECT_PATH   <- "export/reference/polygon_defects.csv"
AUDIT_STEP    <- 0.25   # dense-grid spacing, in tenths of a foot
MAX_DEFECT_ROWS <- 5000

# Distinct coordinates with a count, not one row per shot. Ray casting over 102k distinct
# points is identical in coverage to 1.09M rows and forty times cheaper, and the count
# keeps the shot-weighted totals reportable.
shot_coordinates <- function() {
  con <- dbConnect(duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbGetQuery(con, "SELECT LOC_X AS x, LOC_Y AS y, COUNT(*) AS shots
    FROM read_parquet('data/raw/shots/**/*.parquet', hive_partitioning = 1)
    GROUP BY 1, 2") |>
    as_tibble() |>
    mutate(zone = classify_zone(x, y))
}

# One row per occupied cell per zone, so a cell straddling a boundary appears twice and a
# consumer can see which zones meet there. Counts, not shots: a spatial histogram carries
# no per-shot record, which is what keeps it on the permitted side of rule A16.
zone_grid <- function(cell = GRID_CELL) {
  shot_coordinates() |>
    filter(!is.na(zone)) |>
    mutate(x = floor(x / cell) * cell + cell / 2,
           y = floor(y / cell) * cell + cell / 2) |>
    summarise(n = sum(shots), .by = c(x, y, zone)) |>
    arrange(y, x, zone)
}

write_zone_grid <- function(cell = GRID_CELL, path = GRID_PATH) {
  g <- zone_grid(cell)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_csv(g, path)
  boundary <- g |> summarise(z = n(), .by = c(x, y)) |> filter(z > 1)
  cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  cat(glue("  {nrow(g)} rows, {n_distinct(g[c('x','y')])} cells at {cell/10} ft, ",
           "{sum(g$n)} shots, {nrow(boundary)} boundary cells"), "\n")
  invisible(path)
}

# The outlines, serialised. This is all that survives of R/08_zone_polygons.R, which held a
# second copy of every court constant and was deleted for that reason on 2026-08-27. The arc
# records are a source rather than a reconstruction because build() emits them alongside the
# vertices it generates from them.
write_zone_polygons <- function(path = POLY_PATH) {
  P <- zone_polygons()
  out <- list(zone_model = zone_model_version(),
              units = "tenths of a foot, hoop at the origin, y away from the baseline",
              zones = imap(P, \(z, id) list(
                zone = id,
                value = unname(ZONE_VALUE[[id]]),
                vertices = unname(split(round(z$vertices, 3), row(z$vertices))),
                arcs = map(z$arcs, \(a) list(centre = a$centre, r = a$r,
                                             start_deg = a$start_deg, end_deg = a$end_deg)))))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(out, path, auto_unbox = TRUE, digits = 6)
  cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB  {out$zone_model}"), "\n")
  cat(glue("  {length(P)} zones, {sum(map_int(P, \\(z) nrow(z$vertices)))} vertices, ",
           "{sum(map_int(P, \\(z) length(z$arcs)))} arc records"), "\n")
  invisible(path)
}

# Ray casting, vectorised over points and looped over edges. A polygon here has tens to
# hundreds of vertices and the point sets run to millions of rows, so this orientation is
# the fast one. No new dependency: sf and sp both pull a geospatial stack for one predicate.
point_in_polygon <- function(x, y, poly) {
  px <- poly[, 1]; py <- poly[, 2]
  n <- length(px)
  inside <- rep(FALSE, length(x))
  j <- n
  for (i in seq_len(n)) {
    crosses <- (py[i] > y) != (py[j] > y)
    if (any(crosses)) {
      xint <- (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i]) + px[i]
      hit <- crosses & (x < xint)
      inside[hit] <- !inside[hit]
    }
    j <- i
  }
  inside
}

# The three defect categories, against classify_zone() as the reference. Points beyond
# Y_BACKCOURT are outside the partition: the classifier returns NA and no polygon may
# contain them, so containment there is its own defect rather than being skipped.
audit_points <- function(x, y, zone = classify_zone(x, y)) {
  P <- zone_polygons()
  hits <- map(P, \(p) point_in_polygon(x, y, p$vertices))
  n_in <- reduce(hits, `+`)
  landed <- rep(NA_character_, length(x))
  for (id in names(hits)) landed[hits[[id]]] <- id
  tibble(x, y, zone, n_polygons = n_in, landed_in = landed) |>
    mutate(defect = case_when(
      is.na(zone) & n_polygons > 0 ~ "outside-partition",
      is.na(zone)                  ~ NA_character_,
      n_polygons == 0              ~ "orphan",
      n_polygons > 1               ~ "overlap",
      landed_in != zone            ~ "disagreement",
      .default = NA_character_))
}

report <- function(res, label, weight = NULL) {
  n <- if (is.null(weight)) nrow(res) else sum(weight)
  bad <- filter(res, !is.na(defect))
  cat(glue("\n{label}"), "\n")
  cat(glue("  points {format(nrow(res), big.mark = ',')}",
           if (!is.null(weight)) glue(" covering {format(n, big.mark = ',')} shots") else ""), "\n")
  for (d in c("disagreement", "orphan", "overlap", "outside-partition")) {
    cat(glue("  {format(d, width = 18)} {sum(res$defect == d, na.rm = TRUE)}"), "\n")
  }
  invisible(bad)
}

check_zone_polygons <- function(defect_out = DEFECT_PATH) {
  cat(glue("zone model {zone_model_version()}"), "\n")

  pts <- shot_coordinates()
  real <- audit_points(pts$x, pts$y, pts$zone)
  bad_real <- report(real, "every real coordinate", weight = pts$shots)

  g <- expand_grid(x = seq(-SIDELINE + 0.5, SIDELINE - 0.5, by = AUDIT_STEP),
                   y = seq(BASELINE + 0.5, Y_BACKCOURT - 0.5, by = AUDIT_STEP))
  synth <- audit_points(g$x, g$y)
  bad_synth <- report(synth, glue("dense in-court grid at {AUDIT_STEP} units"))

  bad <- bind_rows(mutate(bad_real, source = "real"), mutate(bad_synth, source = "grid"))
  if (nrow(bad_real) == 0) {
    cat("\n  PASS on real coordinates: every one lands in exactly one polygon, and in the",
        "\n  polygon classify_zone() names.\n")
  }
  if (nrow(bad) > 0) {
    dir.create(dirname(defect_out), recursive = TRUE, showWarnings = FALSE)
    write_csv(head(arrange(bad, source, defect, x, y), MAX_DEFECT_ROWS), defect_out)
    cat(glue("\n  {nrow(bad)} defects; wrote up to {MAX_DEFECT_ROWS} to {defect_out}"), "\n")
  }
  invisible(bad)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) && args[1] == "check") {
    check_zone_polygons()
  } else {
    write_zone_grid()
    write_zone_polygons()
  }
}
