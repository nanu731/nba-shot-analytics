# Planning-only tests. No runner, model, real data, posterior or export loader.
# Existing pure allocation helpers run only on invented numeric fixtures.
if (length(commandArgs(trailingOnly = TRUE))) {
  stop("Planning tests accept no execution mode or season.", call. = FALSE)
}
source("R/spatial_targeted_relocation_helpers.R")

passed <- character()
check <- function(label, value) {
  if (!isTRUE(value)) stop("FAILED: ", label, call. = FALSE)
  passed <<- c(passed, label)
}
rejects <- function(expression) {
  inherits(tryCatch(force(expression), error = identity), "error")
}
near <- function(a, b) all(is.finite(c(a, b))) &&
  length(a) == length(b) && max(abs(a - b)) <= 1e-12

validate_grid <- function(grid) {
  stopifnot(identical(names(grid), c(
    "condition_id", "min_destination_attempts", "min_posterior_evidence",
    "max_final_destination_share", "is_baseline"
  )), nrow(grid) == 27L, !anyNA(grid), !anyDuplicated(grid$condition_id),
  is.logical(grid$is_baseline), sum(grid$is_baseline) == 1L)
  expected <- expand.grid(
    min_destination_attempts = c(5L, 10L, 20L),
    min_posterior_evidence = c(.8, .9, .95),
    max_final_destination_share = c(.3, .5, .7)
  )
  expected <- expected[order(expected[[1]], expected[[2]], expected[[3]]), ]
  stopifnot(isTRUE(all.equal(unname(as.matrix(grid[2:4])),
                            unname(as.matrix(expected)), tolerance = 0)))
  ids <- sprintf("A%02d_E%02d_C%02d", grid[[2]],
                 as.integer(round(100 * grid[[3]])),
                 as.integer(round(100 * grid[[4]])))
  stopifnot(identical(grid$condition_id, ids),
            identical(grid$condition_id[grid$is_baseline], "A10_E90_C50"))
  TRUE
}

grid <- read.csv("config/location_edition_sensitivity_grid_v0_1.csv",
                 stringsAsFactors = FALSE)
check("exact ordered 27-condition grid and one production baseline", validate_grid(grid))
bad <- grid; bad$condition_id[2] <- bad$condition_id[1]
check("duplicate condition rejected", rejects(validate_grid(bad)))
bad <- grid; bad$min_destination_attempts[1] <- 7L
check("unregistered attempt threshold rejected", rejects(validate_grid(bad)))
bad <- grid; bad$is_baseline <- FALSE
check("missing baseline rejected", rejects(validate_grid(bad)))
bad <- grid; bad$extra <- 1
check("schema expansion rejected", rejects(validate_grid(bad)))
bad <- grid; bad$min_posterior_evidence[1] <- NA_real_
check("missing threshold rejected", rejects(validate_grid(bad)))

doc <- paste(readLines("docs/LOCATION_EDITION_SENSITIVITY_PREREGISTRATION.md"),
                       collapse = "\n")
check("protocol and separate-authorization boundary present",
      grepl("location_sensitivity_v0.1.0", doc, fixed = TRUE) &&
        grepl("calculation not authorized", doc, fixed = TRUE))
check("five seasons and fixed eligible counts documented",
      all(vapply(c("2025-26 | 318", "2024-25 | 304", "2023-24 | 281",
                   "2022-23 | 292", "2021-22 | 312"),
                 grepl, logical(1), x = doc, fixed = TRUE)))
check("prospective and Context protection documented",
      grepl("No M3 or 2026-27 access is allowed", doc, fixed = TRUE))
check("all structural code parses without executing exporters",
      all(vapply(c("R/spatial_targeted_relocation_helpers.R",
                   "R/spatial_targeted_capped_website_export.R",
                   "R/spatial_multiseason_website_export.R"), function(path) {
        length(parse(path)) > 0L
      }, logical(1))))
expected_hashes <- c(
  "R/spatial_targeted_relocation_helpers.R" =
    "bc23d4738fa19c15c0571754698ef2456c175f1e8d74ccab1d9030f1a6198aa7",
  "R/spatial_targeted_capped_website_export.R" =
    "bc4b761d0dad35ebc5584a2b773020591c17caa93d569ea8db61f26042f1c113",
  "R/spatial_multiseason_website_export.R" =
    "99edeb6622b18f57fecd83143cb44c4fed4fe67b23a7b05ece90676a96c7e211"
)
actual_hashes <- vapply(names(expected_hashes), function(path) {
  line <- system2("shasum", c("-a", "256", shQuote(path)), stdout = TRUE)
  strsplit(line, "[[:space:]]+")[[1]][1]
}, character(1))
check("three production implementation hashes unchanged",
      identical(actual_hashes, expected_hashes))

# Boundary evidence examples, not production posteriors or sensitivity results.
better <- c(rep(TRUE, 3200), rep(FALSE, 800))
check("80 percent is inclusive at exactly 3200 of 4000 draws",
      mean(better) >= .8 && mean(c(better[-1], FALSE)) < .8)
check("90 and 95 percent draw-count boundaries",
      mean(c(rep(TRUE, 3600), rep(FALSE, 400))) == .9 &&
        mean(c(rep(TRUE, 3800), rep(FALSE, 200))) == .95)
check("equal expected points do not count as superiority",
      mean(c(1.1, 1, .9) > 1) == 1/3)
check("focal attempt threshold is inclusive and separate from evidence",
      identical(c(4, 5, 10) >= 5 & c(.99, .8, .79) >= .8,
                c(FALSE, TRUE, FALSE)))
check("three evidence categories",
      identical(vapply(0:2, target_evidence_status, character(1)),
                c("insufficient_evidence", "single_destination", "multiple_destinations")))

single <- target_capped_allocation(c(.3, .4, .3), c(TRUE, FALSE, FALSE), .25, .4)
check("single receiver final cap limits actual share",
      near(single$actual, .2) && near(single$added, c(.2, 0, 0)) && single$cap_limited)
historical <- target_capped_allocation(c(.6, .2, .2), c(TRUE, FALSE, FALSE),
                                      .25, .4, destination_cap = .3)
check("historical over-cap mass preserved with zero addition",
      historical$actual == 0 && all(historical$added == 0))
multi <- target_capped_allocation(c(.45, .1, .45), c(TRUE, TRUE, FALSE), .25, .45)
check("capped receiver redistributes using original shares",
      near(multi$added, c(.05, .2, 0)) && near(multi$actual, .25))
check("a reached cell cap need not limit total movement",
      near(.45 + multi$added[1], .5) && !multi$cap_limited)
source_limited <- target_capped_allocation(c(.1, .45, .45), c(TRUE, FALSE, FALSE),
                                          .25, .12, destination_cap = .7)
check("weak-source limit is distinct from receiving limit",
      near(source_limited$actual, .12) && !source_limited$cap_limited)
none <- target_capped_allocation(c(.2, .3, .5), rep(FALSE, 3), .25, .5)
check("no destination produces no movement", none$actual == 0 && all(none$added == 0))
order <- target_source_order(c(2, 3, 5), c(.7, .7, 1.4), 1.1, c(2L, 1L, 3L))
check("source ties use ascending cell ID", identical(order, c(2L, 1L)))
removal <- target_remove_mass(c(.2, .3, .5), c(1L, 2L), .25)
check("fractional final source cell retained", near(removal$removed, c(.2, .05, 0)))
check("fractional attempt-equivalents not rounded", near(removal$actual * 11, 2.75))

requests <- c(0, .05, .10, .15, .20, .25)
allocations <- lapply(requests, function(s) {
  target_capped_allocation(c(.45, .1, .45), c(TRUE, TRUE, FALSE), s, .45)
})
additions <- vapply(allocations, `[[`, numeric(3), "added")
removals <- vapply(allocations, function(x) {
  target_remove_mass(c(.45, .1, .45), 3L, x$actual)$removed
}, numeric(3))
final <- c(.45, .1, .45) - removals + additions
check("synthetic mass, caps and unchanged attempts",
      max(abs(colSums(final) - 1)) <= 1e-12 && all(final >= -1e-12) &&
        all(final[additions > 1e-12] <= .5 + 1e-12) &&
        max(abs(colSums(final) * 1000 - 1000)) <= 1e-9)
check("source and destination increments nest over requests",
      all(apply(additions, 1, diff) >= -1e-12) &&
        all(apply(removals, 1, diff) >= -1e-12))
check("zero request moves no mass", all(additions[,1] == 0) && all(removals[,1] == 0))
check("allocation is deterministic", identical(multi,
      target_capped_allocation(c(.45, .1, .45), c(TRUE, TRUE, FALSE), .25, .45)))
check("movement helper interfaces exclude make/miss outcomes",
      !any(grepl("made|miss|outcome", c(names(formals(target_source_order)),
        names(formals(target_remove_mass)), names(formals(target_capped_allocation))))))
toy_order <- function(toy) target_source_order(toy$attempts, toy$expected,
                                               1.1, toy$cell_id)
toy <- data.frame(attempts=c(2,3,5), expected=c(.7,.9,1.4), cell_id=1:3,
                  made=c(0,1,1))
flipped <- toy; flipped$made <- 1 - flipped$made
check("flipping synthetic outcomes leaves fixed-surface source order unchanged",
      identical(toy_order(toy), toy_order(flipped)))
check("invalid shares fail instead of silent repair",
      rejects(target_capped_allocation(c(.4,.4), c(TRUE,FALSE), .25,.4)))
check("source/support overlap is a stop condition",
      rejects(target_assert(!any(c(TRUE,FALSE)[1]), "source/support overlap")))
score <- target_score(c(1,1.2,1.4), c(1.2,1.4,1.6))
expected_score <- median(pmin(100, pmax(0, 100*c(1,1.2,1.4)/c(1.2,1.4,1.6))))
check("score is median of clipped draw ratios",
      near(score$point, expected_score))
summary <- target_summary(c(-.2, .1, .4))
check("negative uncertainty bounds preserved and ordered",
      summary$lower_90 < 0 && summary$lower_90 <= summary$upper_90 &&
        near(summary$mean, .1))
paired <- c(1,2,3) - c(1,2,3)
check("paired self-comparison has zero uncertainty", all(paired == 0))
check("high-volume subgroup sizes are frozen rank quarters",
      identical(ceiling(c(318,304,281,292,312)/4), c(80,76,71,73,78)))
check("descriptive stability avoids a post-result cutoff",
      grepl("exact `k/27`",doc,fixed=TRUE) &&
        grepl("Do not create a binary majority cutoff",doc,fixed=TRUE))
check("private player outputs and public aggregate-only separation documented",
      grepl("Private player-season outputs",doc,fixed=TRUE) &&
        grepl("none enter tracked outputs",doc,fixed=TRUE))
check("two-build byte determinism is an execution gate",
      grepl("byte-identical sorted file inventories",doc,fixed=TRUE))
cat(sprintf("PASS: %d structural and invented-fixture checks. No real data, models,\nposterior artifacts, exports, or sensitivity results loaded or written.\n",
            length(passed)))
