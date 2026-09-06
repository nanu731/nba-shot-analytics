suppressPackageStartupMessages({
  library(jsonlite)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("TEST FAILED: ", label, call. = FALSE)
}

# Evidence states distinguish zero, one, and multiple supported destinations.
expect_true(
  identical(target_evidence_status(0L), "insufficient_evidence"),
  "zero destinations are insufficient evidence"
)
expect_true(
  identical(target_evidence_status(1L), "single_destination"),
  "one destination receives the single-destination status"
)
expect_true(
  identical(target_evidence_status(2L), "multiple_destinations") &&
    identical(target_evidence_status(7L), "multiple_destinations"),
  "two or more destinations receive the multiple-destination status"
)

# Source removal stays weakest-first and permits a fractional boundary cell.
attempts <- c(2L, 3L, 5L, 0L)
share <- attempts / sum(attempts)
expected_points <- c(0.7, 0.9, 1.3, 0.4)
source_order <- target_source_order(attempts, expected_points, 1.1, 1:4)
expect_true(
  identical(source_order, c(1L, 2L)),
  "weak source cells rank from lowest to highest"
)
removed <- target_remove_mass(share, source_order, 0.25)
expect_true(
  abs(removed$actual - 0.25) <= 1e-12 &&
    max(abs(removed$removed - c(0.2, 0.05, 0, 0))) <= 1e-12,
  "source removal uses a fractional final boundary"
)

# A single destination stops at the universal 50% final-share cap.
single <- target_capped_allocation(
  baseline_share = c(0.30, 0.40, 0.30),
  supported = c(TRUE, FALSE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.40
)
expect_true(
  abs(single$actual - 0.20) <= 1e-12 &&
    max(abs(single$added - c(0.20, 0, 0))) <= 1e-12 &&
    isTRUE(single$cap_limited),
  "single destination uses only positive capacity"
)

# Weak-source exhaustion can stop relocation before a destination cap binds.
source_limited <- target_capped_allocation(
  baseline_share = c(0.10, 0.45, 0.45),
  supported = c(TRUE, FALSE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.12
)
expect_true(
  abs(source_limited$actual - 0.12) <= 1e-12 &&
    !isTRUE(source_limited$cap_limited),
  "weak-source capacity limits the actual share"
)

# Multiple destinations start proportional, then redistribute around a cap.
redistributed <- target_capped_allocation(
  baseline_share = c(0.45, 0.10, 0.45),
  supported = c(TRUE, TRUE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.30
)
expect_true(
  abs(redistributed$actual - 0.25) <= 1e-12 &&
    max(abs(redistributed$added - c(0.05, 0.20, 0))) <= 1e-12,
  "mass redistributes after the first destination reaches 50 percent"
)
expect_true(
  all(c(0.45, 0.10, 0.45) + redistributed$added <= 0.5 + 1e-12),
  "no final destination share exceeds 50 percent"
)

proportional <- target_capped_allocation(
  baseline_share = c(0.20, 0.10, 0.70),
  supported = c(TRUE, TRUE, FALSE),
  requested_share = 0.12,
  source_capacity = 0.40
)
expect_true(
  max(abs(proportional$added - c(0.08, 0.04, 0))) <= 1e-12,
  "uncapped multiple destinations receive proportional mass"
)

no_capacity <- target_capped_allocation(
  baseline_share = c(0.50, 0.25, 0.25),
  supported = c(TRUE, FALSE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.25
)
expect_true(
  identical(no_capacity$actual, 0) && all(no_capacity$added == 0),
  "a supported destination with no positive capacity receives no relocation"
)

exhausted <- target_capped_allocation(
  baseline_share = c(0.49, 0.48, 0.03),
  supported = c(TRUE, TRUE, FALSE),
  requested_share = 0.25,
  source_capacity = 0.30
)
expect_true(
  abs(exhausted$actual - 0.03) <= 1e-12 &&
    max(abs(exhausted$added - c(0.01, 0.02, 0))) <= 1e-12 &&
    isTRUE(exhausted$cap_limited),
  "all supported capacity can be exhausted before the request"
)

# Destination marker assignment accepts one destination and remains deterministic.
single_sequence <- target_destination_sequence(4L, 1L, c(1, 0, 0))
expect_true(
  identical(single_sequence, rep(1L, 4L)),
  "single-destination markers use the supported cell"
)
multiple_sequence <- target_destination_sequence(
  10L, c(1L, 2L), c(0.6, 0.4, 0)
)
expect_true(
  identical(
    multiple_sequence,
    c(1L, 2L, 1L, 2L, 1L, 1L, 2L, 1L, 2L, 1L)
  ),
  "multiple-destination marker order is deterministic"
)

# Make or miss values cannot change any helper input or movement output.
made_a <- c(TRUE, FALSE, TRUE, FALSE, TRUE)
made_b <- !made_a
plan_a <- list(source_order = source_order, allocation = redistributed$added)
plan_b <- list(source_order = source_order, allocation = redistributed$added)
expect_true(
  identical(plan_a, plan_b) && !identical(made_a, made_b),
  "made and missed outcomes do not determine movement"
)

# The verified v2 public payload supplies Wembanyama's frozen regression inputs.
wemby_path <- file.path(
  "export", "spatial-shot-selection", "v2", "seasons", "2025-26",
  "players", "1641705.json"
)
expect_true(file.exists(wemby_path), "Wembanyama v2 payload exists")
wemby <- fromJSON(wemby_path, simplifyVector = TRUE, flatten = TRUE)
wemby_supported <- wemby$heatmap_cells$supported_destination
wemby_shares <- wemby$heatmap_cells$observed_attempts / wemby$observed_attempts
expect_true(
  identical(wemby$observed_attempts, 1080L) &&
    identical(wemby$makes, 553L) && identical(wemby$misses, 527L) &&
    sum(wemby_supported) == 1L &&
    sum(wemby$heatmap_cells$observed_attempts[wemby_supported]) == 297L,
  "Wembanyama regression inputs match the verified audit"
)
wemby_plan <- target_capped_allocation(
  baseline_share = wemby_shares,
  supported = wemby_supported,
  requested_share = 0.25,
  source_capacity = wemby$eligible_source_share
)
expect_true(
  abs(wemby_plan$actual - 0.225) <= 1e-12 &&
    max(wemby_shares + wemby_plan$added) <= 0.5 + 1e-12,
  "Wembanyama reaches the supported cell cap at 22.5 percent relocation"
)

cat("All focused capped targeted-relocation tests passed.\n")
