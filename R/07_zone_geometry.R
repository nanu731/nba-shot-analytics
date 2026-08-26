# Tooling for the website's hand-authored zone outlines. This repository does not draw
# them and must not: zones come from the NBA's own labels, never from geometry (rule A4).
# What it can do is emit a reference the shapes can be traced from, and check a candidate
# set of shapes against the labels exhaustively.
#
#   Rscript R/07_zone_geometry.R                      # write the reference grid
#   Rscript R/07_zone_geometry.R candidate.json       # check candidate polygons
#
# Candidate file format: a JSON object keyed by stable zone id, each value an array of
# [x, y] vertices in NBA shot-chart units (tenths of a foot, hoop at the origin).
#
#   { "restricted_area": [[-39,-36],[39,-36], ...], "paint_left": [ ... ], ... }

library(tidyverse)
library(arrow)
library(glue)
library(jsonlite)

source("R/02_build_zone_stats.R")

GRID_CELL <- 5           # half a foot; fine enough to trace, coarse enough to stay aggregate
GRID_PATH <- "export/reference/zone_grid.csv"
MAX_DEFECT_ROWS <- 5000  # cap on the inspectable defect file

labelled_shots <- function(seasons = NULL) {
  files <- list.files("data/raw/shots", pattern = "\\.parquet$",
                      full.names = TRUE, recursive = TRUE)
  if (!is.null(seasons)) {
    files <- files[str_detect(files, str_c(seasons, collapse = "|"))]
  }
  if (length(files) == 0) stop("no raw shot files found under data/raw/shots", call. = FALSE)

  map(files, \(f) read_parquet(f, col_select = c("LOC_X", "LOC_Y",
                                                 "SHOT_ZONE_BASIC", "SHOT_ZONE_AREA"))) |>
    list_rbind() |>
    filter(SHOT_ZONE_BASIC != "Backcourt", SHOT_ZONE_AREA != "Back Court(BC)") |>
    mutate(zone = str_c(SHOT_ZONE_BASIC, " | ", SHOT_ZONE_AREA)) |>
    left_join(select(ZONE_REF, zone, zone_id), by = "zone") |>
    select(x = LOC_X, y = LOC_Y, zone_id)
}

# One row per occupied cell per zone, so a cell straddling a boundary appears as two rows
# and the consumer can see exactly which zones meet there. Counts, not shots: this is a
# spatial histogram and carries no per-shot record, which is what keeps it on the
# permitted side of rule A16.
zone_grid <- function(cell = GRID_CELL, seasons = NULL) {
  labelled_shots(seasons) |>
    mutate(x = floor(x / cell) * cell + cell / 2,
           y = floor(y / cell) * cell + cell / 2) |>
    count(x, y, zone_id, name = "n") |>
    arrange(y, x, zone_id)
}

write_zone_grid <- function(cell = GRID_CELL, path = GRID_PATH) {
  g <- zone_grid(cell)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_csv(g, path)

  boundary <- g |> summarise(z = n(), .by = c(x, y)) |> filter(z > 1)
  cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  cat(glue("  {nrow(g)} rows, {n_distinct(g[c('x','y')])} cells at {cell} units ",
           "({cell/10} ft), {sum(g$n)} shots"), "\n")
  cat(glue("  {nrow(boundary)} cells contain more than one zone; those are the boundary cells"), "\n")
  invisible(path)
}

# Ray casting, vectorised over points and looped over edges. A polygon here has tens of
# vertices and the point set has ~1.1 million rows, so this orientation is the fast one.
# No new dependency: sf and sp would both pull in a geospatial stack for one predicate.
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

read_candidate <- function(path) {
  if (!file.exists(path)) stop(glue("candidate file not found: {path}"), call. = FALSE)
  raw <- fromJSON(path, simplifyVector = FALSE)

  expected <- ZONE_REF$zone_id
  missing <- setdiff(expected, names(raw))
  unknown <- setdiff(names(raw), expected)
  if (length(missing) || length(unknown)) {
    stop(glue(
      "candidate zone ids do not match the model.\n",
      if (length(missing)) glue("  missing: {str_c(missing, collapse = ', ')}; ") else "",
      if (length(unknown)) glue("unknown: {str_c(unknown, collapse = ', ')}") else ""
    ), call. = FALSE)
  }

  map(raw, \(v) {
    m <- do.call(rbind, map(v, \(pt) as.numeric(unlist(pt))))
    if (is.null(m) || ncol(m) != 2 || nrow(m) < 3) {
      stop("every polygon needs at least 3 vertices of [x, y]", call. = FALSE)
    }
    m
  })
}

check_zone_polygons <- function(candidate_file, seasons = NULL,
                                defect_out = "export/reference/polygon_defects.csv") {
  polys <- read_candidate(candidate_file)
  shots <- labelled_shots(seasons)
  vtx <- map_int(polys, nrow)
  cat(glue("checking {length(polys)} polygons ({min(vtx)}-{max(vtx)} vertices) ",
           "against {nrow(shots)} labelled shots"), "\n\n")

  hits <- map(polys, \(p) point_in_polygon(shots$x, shots$y, p))
  n_in <- reduce(hits, `+`)

  landed <- rep(NA_character_, nrow(shots))
  for (id in names(hits)) landed[hits[[id]]] <- id

  res <- shots |>
    mutate(n_polygons = n_in,
           landed_in = landed,
           defect = case_when(
             n_polygons == 0 ~ "orphan",
             n_polygons > 1  ~ "overlap",
             landed_in != zone_id ~ "disagreement",
             .default = NA_character_))

  cat("per-zone results, by the label the NBA assigned\n")
  per_zone <- res |>
    summarise(shots = n(),
              correct = sum(is.na(defect)),
              disagreement = sum(defect == "disagreement", na.rm = TRUE),
              orphan = sum(defect == "orphan", na.rm = TRUE),
              overlap = sum(defect == "overlap", na.rm = TRUE),
              .by = zone_id) |>
    mutate(pct_ok = round(100 * correct / shots, 2)) |>
    arrange(pct_ok)
  print(as.data.frame(per_zone), row.names = FALSE)

  bad <- filter(res, !is.na(defect))
  cat(glue("\ntotals: {nrow(res) - nrow(bad)} correct, {nrow(bad)} defective ",
           "({round(100 * nrow(bad) / nrow(res), 3)}%)"), "\n")
  cat(glue("  disagreement  {sum(res$defect == 'disagreement', na.rm = TRUE)}  ",
           "shot's label and the polygon it landed in differ"), "\n")
  cat(glue("  orphan        {sum(res$defect == 'orphan', na.rm = TRUE)}  ",
           "shot landed in no polygon"), "\n")
  cat(glue("  overlap       {sum(res$defect == 'overlap', na.rm = TRUE)}  ",
           "shot landed in more than one polygon"), "\n")

  if (nrow(bad) == 0) {
    cat("\n  no defects. These outlines reproduce the NBA classification exactly.\n")
  } else {
    dir.create(dirname(defect_out), recursive = TRUE, showWarnings = FALSE)
    out <- bad |>
      arrange(defect, zone_id) |>
      transmute(defect, x, y, labelled = zone_id, landed_in, n_polygons) |>
      head(MAX_DEFECT_ROWS)
    write_csv(out, defect_out)
    cat(glue("\n  wrote {nrow(out)} defect rows to {defect_out}"), "\n")
    if (nrow(bad) > MAX_DEFECT_ROWS) {
      cat(glue("  ({nrow(bad)} defects total; capped at {MAX_DEFECT_ROWS})"), "\n")
    }
    cat("\n  worst offenders by coordinate:\n")
    print(as.data.frame(head(out, 8)), row.names = FALSE)
  }

  invisible(res)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) write_zone_grid() else check_zone_polygons(args[1])
}
