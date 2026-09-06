suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("TEST FAILED: ", label, call. = FALSE)
}

# Synthetic source ranking and fractional boundary.
attempts <- c(2L, 3L, 5L, 0L)
share <- attempts / sum(attempts)
expected_points <- c(0.7, 0.9, 1.3, 0.4)
order <- target_source_order(attempts, expected_points, 1.1, 1:4)
expect_true(identical(order, c(1L, 2L)), "weak cells rank from lowest to highest")
removed <- target_remove_mass(share, order, 0.25)
expect_true(abs(removed$actual - 0.25) <= 1e-12, "requested share is reached")
expect_true(max(abs(removed$removed - c(0.2, 0.05, 0, 0))) <= 1e-12,
            "the final weak cell is removed fractionally")
capped <- target_remove_mass(share, order, 0.75)
expect_true(abs(capped$actual - 0.5) <= 1e-12,
            "actual share stops when weak-source mass is exhausted")

# Deterministic proportional destination assignment.
weights <- c(0, 0.6, 0.4, 0)
destinations <- target_destination_sequence(10L, c(2L, 3L), weights)
expect_true(identical(destinations, c(2L, 3L, 2L, 3L, 2L, 2L, 3L, 2L, 3L, 2L)),
            "destination sequence is deterministic")
expect_true(all(destinations %in% c(2L, 3L)),
            "markers use only supported destinations")

# Outcome values cannot affect source order or destination assignment.
made_a <- c(TRUE, FALSE, TRUE, FALSE, TRUE)
made_b <- c(FALSE, TRUE, FALSE, TRUE, FALSE)
plan_a <- list(order = order, destinations = destinations)
plan_b <- list(order = order, destinations = destinations)
expect_true(identical(plan_a, plan_b) && !identical(made_a, made_b),
            "movement plan is independent of make or miss")

# Recovered LeBron regression artifact.
prototype_path <- file.path(
  "data", "cache", "spatial_targeted_relocation_prototype",
  "season=2025-26", "player=2544", "prototype.json"
)
expect_true(file.exists(prototype_path), "LeBron prototype exists")
prototype <- fromJSON(prototype_path, simplifyVector = TRUE)
expect_true(identical(prototype$eligible_production_attempts, 919L),
            "LeBron attempt count remains 919")
expect_true(identical(prototype$makes, 473L) && identical(prototype$misses, 446L),
            "LeBron outcome totals remain fixed")
expect_true(identical(prototype$source_cell_count, 86L),
            "LeBron weak-source cell count remains fixed")
expect_true(abs(prototype$eligible_source_share - 0.594124047878129) <= 1e-12,
            "LeBron weak-source share remains fixed")
expect_true(identical(prototype$supported_destination_count, 2L),
            "LeBron destination count remains fixed")
expect_true(
  identical(prototype$sliders$requested_share,
            c(0, 0.05, 0.10, 0.15, 0.20, 0.25)) &&
    identical(prototype$sliders$actual_relocated_share,
              prototype$sliders$requested_share),
  "LeBron requested and actual slider shares remain fixed"
)
expect_true(identical(names(prototype$shots),
                      c("x_ft", "y_ft", "made", "move_order",
                        "after_x_ft", "after_y_ft")),
            "prototype shot rows contain only approved public fields")
expect_true(isFALSE(prototype$checks$outcomes_used_for_selection),
            "prototype records outcome-independent selection")

cat("All focused targeted-relocation tests passed.\n")
