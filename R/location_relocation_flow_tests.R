# Read-only contract verification. No exporter, model, raw data, or draw loading.
suppressPackageStartupMessages(library(jsonlite))
source(file.path("R", "spatial_targeted_relocation_helpers.R"))
check <- function(x, label) {
  if (!isTRUE(x)) stop("FLOW CHECK FAILED: ", label, call. = FALSE)
}
near <- function(x, y, scale = 1) {
  length(x) == length(y) && all(is.finite(c(x, y))) &&
    all(abs(x - y) <= 1e-12 * max(1, scale))
}
cell_at <- function(x, y) {
  check(all(is.finite(c(x, y))) && all(x >= -25 & x <= 25) &&
          all(y >= -5.25 & y <= 39.75), "court coordinates")
  as.integer((pmin(floor((y + 5.25) / 4), 11) * 13) +
               pmin(floor((x + 25) / 4), 12) + 1)
}

# Executable contract example, confined to this verification file.
# It deliberately accepts no outcomes, probabilities, or after-marker positions.
flow <- function(n, available, reason, shots, slider) {
  m <- slider$actual_relocated_attempt_equivalents
  check(length(m) == 1L && is.finite(m) && m >= 0, "finite movement")
  cells <- data.frame(cell_id = seq_len(156L),
                      removed_attempt_equivalents = numeric(156L),
                      added_attempt_equivalents = numeric(156L))
  active <- !is.na(shots$move_order)
  if (available) {
    w <- pmin(1, pmax(0, m - shots$move_order[active] + 1))
    totals <- tapply(w, cell_at(shots$x_ft[active], shots$y_ft[active]), sum)
    cells$removed_attempt_equivalents[as.integer(names(totals))] <- as.numeric(totals)
    a <- slider$destination_allocation
    if (nrow(a) > 0L) cells$added_attempt_equivalents[a$cell_id] <- n * a$added_share
  } else {
    check(m == 0 && !any(active) && length(slider$destination_allocation) == 0,
          "unavailable has no movement")
  }
  list(relocation_available = available, availability_reason = reason,
       requested_share = slider$requested_share,
       actual_relocated_attempt_equivalents = m, cells = cells)
}

# Cheap synthetic checks before reading the bundle.
check(identical(cell_at(c(-25, -21, 25, 25), c(-5.25, -5.25, 38.75, 39.75)),
                c(1L, 2L, 156L, 156L)), "half-open and clipped boundaries")
s <- data.frame(x_ft = c(-25, -25, -21), y_ft = -5.25, move_order = 1:3)
a <- data.frame(cell_id = 3L, added_share = .25, final_share = .5)
slider <- list(requested_share = .25, actual_relocated_attempt_equivalents = 2.5,
               destination_allocation = a)
f <- flow(10, TRUE, "available", s, slider)
check(identical(f$cells$removed_attempt_equivalents[1:3], c(2, .5, 0)) &&
        f$cells$added_attempt_equivalents[3] == 2.5, "fractional source boundary")
slider$actual_relocated_attempt_equivalents <- 0
slider$requested_share <- 0
slider$destination_allocation$added_share <- 0
check(sum(unlist(flow(10, TRUE, "available", s, slider)$cells[-1])) == 0,
      "available zero request")
s$move_order <- NA_integer_
slider$destination_allocation <- list()
check(sum(unlist(flow(10, FALSE, "no_supported_destinations", s, slider)$cells[-1])) == 0,
      "unavailable zero movement distinct from availability")
bad <- slider; bad$actual_relocated_attempt_equivalents <- NA_real_
check(inherits(tryCatch(flow(10, FALSE, "unavailable", s, bad),
                       error = identity), "error"), "missing movement fails closed")
cat("Synthetic contract checks passed.\n")

root <- file.path("export", "spatial-shot-selection", "v4")
hash <- function(path) digest::digest(file = path, algo = "sha256")
check(identical(hash(file.path(root, "manifest.json")),
  "685aa02b5003cb292fbe0926b242a351200f0cd785a169c31942f8518ac03242"), "frozen v4 manifest")
manifest <- fromJSON(file.path(root, "manifest.json"))
inventory <- manifest$payload_files
check(identical(sort(c("manifest.json", inventory$path)),
                sort(list.files(root, recursive = TRUE))), "complete inventory")
check(!anyDuplicated(inventory$path) &&
        identical(unname(vapply(file.path(root, inventory$path), hash, character(1))),
                  inventory$sha256) &&
        identical(as.numeric(file.info(file.path(root, inventory$path))$size),
                  as.numeric(inventory$bytes)), "all published hashes and sizes")
check(manifest$model$destination_min_attempts == 10 &&
        manifest$model$destination_min_certainty == .9 &&
        manifest$model$maximum_final_destination_share == .5, "production baseline only")

shot_fields <- c("x_ft", "y_ft", "made", "move_order", "after_x_ft", "after_y_ft")
cell_fields <- c("cell_id", "center_x_ft", "center_y_ft", "x_min_ft", "x_max_ft",
                 "y_min_ft", "y_max_ft", "modeled_make_probability",
                 "make_probability_lower_90", "make_probability_median",
                 "make_probability_upper_90", "observed_attempts", "effective_point_value",
                 "supported_destination")
seasons <- c("2025-26", "2024-25", "2023-24", "2022-23", "2021-22")
expected_players <- c(318L, 304L, 281L, 292L, 312L)
expected_shots <- c(194987L, 194526L, 192608L, 192897L, 193577L)
max_mass_error <- 0
all_sizes <- numeric()
for (z in seq_along(seasons)) {
  paths <- list.files(file.path(root, "seasons", seasons[z], "players"), full.names = TRUE)
  check(length(paths) == expected_players[z], "season players")
  shots_total <- unavailable <- single <- multiple <- fractional <- 0L
  for (path in paths) {
    p <- fromJSON(path)
    h <- p$heatmap_cells; n <- p$observed_attempts
    check(identical(names(p$shots), shot_fields) && identical(names(h), cell_fields),
          "public shot/cell field allowlists")
    check(identical(h$cell_id, seq_len(156L)) && sum(h$observed_attempts) == n &&
            nrow(p$shots) == n && p$season == seasons[z], "cell order, counts and season")
    ids <- cell_at(p$shots$x_ft, p$shots$y_ft)
    check(identical(tabulate(ids, 156L), h$observed_attempts), "original coordinates to cells")
    check(all(p$shots$x_ft >= h$x_min_ft[ids] & p$shots$x_ft <= h$x_max_ft[ids] &
                p$shots$y_ft >= h$y_min_ft[ids] & p$shots$y_ft <= h$y_max_ft[ids]),
          "exported cell rectangles")
    orders <- p$shots$move_order
    active <- which(!is.na(orders))
    check(all(is.finite(orders[active])) && all(orders[active] == as.integer(orders[active])) &&
            identical(sort(as.integer(orders[active])), seq_along(active)),
          "unique contiguous movement order (all-null columns allowed)")
    source_sequence <- ids[active[order(orders[active])]]
    source_order <- unique(source_sequence)
    check(identical(rle(source_sequence)$values, source_order), "source cells occupy contiguous blocks")
    check(!any(h$supported_destination[source_order]) &&
            all(h$observed_attempts[h$supported_destination] >= 10L), "disjoint and supported cells")
    sliders <- p$sliders
    check(identical(sliders$requested_share, c(0, .05, .10, .15, .20, .25)), "six sliders")
    check(length(active) == ceiling(max(sliders$actual_relocated_attempt_equivalents) - 1e-12),
          "saved source sequence covers maximum movement")
    for (j in seq_len(6L)) {
      one <- lapply(sliders[c("requested_share", "actual_relocated_share",
                              "actual_relocated_attempt_equivalents", "destination_allocation")],
                    function(column) if (is.list(column)) column[[j]] else column[j])
      pure_shots <- p$shots[c("x_ft", "y_ft", "move_order")]
      result <- flow(n, p$relocation_available, p$availability_reason, pure_shots, one)
      removed <- result$cells$removed_attempt_equivalents
      added <- result$cells$added_attempt_equivalents
      m <- one$actual_relocated_attempt_equivalents
      expected <- target_capped_allocation(h$observed_attempts/n, h$supported_destination,
                                          one$requested_share, p$eligible_source_share)
      check(near(m, n*one$actual_relocated_share, n) && near(m, n*expected$actual, n) &&
              near(added, n*expected$added, n), "saved allocation and mass")
      check(near(sum(removed), m, n) && near(sum(added), m, n) &&
              near(sum(removed), sum(added), n), "balanced totals")
      max_mass_error <- max(max_mass_error, abs(sum(removed)-m), abs(sum(added)-m))
      check(all(removed >= 0 & removed <= h$observed_attempts + 1e-12*n) &&
              all(added >= 0) && all(added[!h$supported_destination] == 0), "bounds and support")
      independent <- target_remove_mass(h$observed_attempts/n, source_order, m/n)
      check(near(removed, n*independent$removed, n), "marker-prefix equals cell-level removal")
      final <- h$observed_attempts - removed + added
      check(near(sum(final), n, n) && all(final >= -1e-12*n) &&
              all(final[added > 1e-12*n] <= .5*n + 1e-12*n), "mass and receiving-cell cap")
      if (p$relocation_available) {
        dest <- one$destination_allocation
        check(identical(names(dest), c("cell_id", "added_share", "final_share")) &&
                identical(dest$cell_id, h$cell_id[h$supported_destination]) &&
                near(dest$final_share, final[dest$cell_id]/n), "destination schema/order/final shares")
      } else {
        check(all(is.na(unlist(p$score))) &&
                all(is.na(unlist(sliders$season_gain[j, ]))) &&
                all(is.na(unlist(sliders$gain_per_100[j, ]))), "unavailable remains null")
      }
      check(identical(names(result$cells), c("cell_id", "removed_attempt_equivalents",
                                            "added_attempt_equivalents")), "aggregate allowlist")
      check(identical(result, flow(n, p$relocation_available, p$availability_reason,
                                   pure_shots[nrow(pure_shots):1, ], one)), "row-order determinism")
      if (j == 1L) check(all(removed == 0 & added == 0) && m == 0, "zero-flow request")
      fractional <- fractional + as.integer(abs(m-round(m)) > 1e-9)
    }
    unavailable <- unavailable + !p$relocation_available
    single <- single + (p$evidence_status == "single_destination")
    multiple <- multiple + (p$evidence_status == "multiple_destinations")
    shots_total <- shots_total + n
  }
  check(shots_total == expected_shots[z], "season attempt total")
  all_sizes <- c(all_sizes, file.info(paths)$size)
  cat(seasons[z], "players", length(paths), "shots", shots_total, "sliders", 6*length(paths),
      "unavailable", unavailable, "single", single, "multiple", multiple,
      "fractional-slider-boundaries", fractional, "PASS\n")
}
cat("Maximum mass discrepancy in attempt-equivalents:", format(max_mass_error, digits=16), "\n")
cat("Player payload bytes min/median/max:", min(all_sizes), median(all_sizes), max(all_sizes), "\n")
cat("Bundle bytes:", sum(inventory$bytes) + file.info(file.path(root, "manifest.json"))$size,
    "; new export bytes: 0; additional browser requests: 0\n")
cat("PASS: five seasons, 1507 players, 9042 sliders; read-only public-v4 verification.\n")
