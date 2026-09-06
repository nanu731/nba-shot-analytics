target_assert <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop("TARGETED RELOCATION CHECK FAILED: ", message, call. = FALSE)
  }
}

target_quantile <- function(values, probability) {
  as.numeric(stats::quantile(values, probability, names = FALSE, type = 7))
}

target_summary <- function(values) {
  list(
    mean = mean(values),
    lower_90 = target_quantile(values, 0.05),
    upper_90 = target_quantile(values, 0.95)
  )
}

target_assign_cells <- function(shots, grid_width = 40L,
                                x_min = -250, x_max = 250,
                                y_min = -52.5, y_max = 397.5) {
  nx <- as.integer(ceiling((x_max - x_min) / grid_width))
  ny <- as.integer(ceiling((y_max - y_min) / grid_width))
  shots |>
    dplyr::mutate(
      x_index = pmin(
        as.integer(floor((LOC_X - x_min) / grid_width)) + 1L,
        nx
      ),
      y_index = pmin(
        as.integer(floor((LOC_Y - y_min) / grid_width)) + 1L,
        ny
      ),
      cell_id = (y_index - 1L) * nx + x_index
    )
}

target_source_order <- function(attempts, expected_points, baseline, cell_id) {
  eligible <- attempts > 0L & expected_points < baseline
  which(eligible)[order(expected_points[eligible], cell_id[eligible])]
}

target_remove_mass <- function(baseline_share, source_order, requested_share,
                               tolerance = 1e-12) {
  target_assert(
    is.numeric(requested_share) && length(requested_share) == 1L &&
      is.finite(requested_share) && requested_share >= 0,
    "requested share must be one finite nonnegative number"
  )
  removed <- numeric(length(baseline_share))
  remaining <- min(requested_share, sum(baseline_share[source_order]))
  actual <- remaining
  for (index in source_order) {
    if (remaining <= tolerance) break
    amount <- min(baseline_share[[index]], remaining)
    removed[[index]] <- amount
    remaining <- remaining - amount
  }
  target_assert(
    abs(sum(removed) - actual) <= tolerance,
    "removed source mass does not equal actual relocated mass"
  )
  list(removed = removed, actual = actual)
}

target_evidence_status <- function(supported_count) {
  target_assert(
    length(supported_count) == 1L && is.numeric(supported_count) &&
      is.finite(supported_count) && supported_count >= 0 &&
      supported_count == as.integer(supported_count),
    "supported destination count must be one nonnegative integer"
  )
  if (supported_count == 0L) return("insufficient_evidence")
  if (supported_count == 1L) return("single_destination")
  "multiple_destinations"
}

target_capped_allocation <- function(baseline_share, supported,
                                     requested_share, source_capacity,
                                     destination_cap = 0.5,
                                     tolerance = 1e-12) {
  target_assert(
    is.numeric(baseline_share) && length(baseline_share) > 0L &&
      all(is.finite(baseline_share)) && all(baseline_share >= 0) &&
      abs(sum(baseline_share) - 1) <= tolerance,
    "baseline shares must be finite, nonnegative, and sum to one"
  )
  target_assert(
    is.logical(supported) && length(supported) == length(baseline_share) &&
      !anyNA(supported) && all(baseline_share[supported] > 0),
    "supported flags must align with baseline shares"
  )
  target_assert(
    is.numeric(requested_share) && length(requested_share) == 1L &&
      is.finite(requested_share) && requested_share >= 0,
    "requested share must be one finite nonnegative number"
  )
  target_assert(
    is.numeric(source_capacity) && length(source_capacity) == 1L &&
      is.finite(source_capacity) && source_capacity >= 0,
    "source capacity must be one finite nonnegative number"
  )
  target_assert(
    is.numeric(destination_cap) && length(destination_cap) == 1L &&
      is.finite(destination_cap) && destination_cap > 0 &&
      destination_cap <= 1,
    "destination cap must be in (0, 1]"
  )

  capacity <- numeric(length(baseline_share))
  capacity[supported] <- pmax(0, destination_cap - baseline_share[supported])
  total_capacity <- sum(capacity)
  actual <- min(requested_share, source_capacity, total_capacity)
  added <- numeric(length(baseline_share))
  remaining <- actual
  active <- which(supported & capacity > tolerance)

  while (remaining > tolerance && length(active) > 0L) {
    active_weights <- baseline_share[active] / sum(baseline_share[active])
    proposal <- remaining * active_weights
    available <- capacity[active] - added[active]
    binding <- proposal >= available - tolerance
    if (!any(binding)) {
      added[active] <- added[active] + proposal
      remaining <- 0
    } else {
      binding_indices <- active[binding]
      allocated <- pmax(0, available[binding])
      added[binding_indices] <- added[binding_indices] + allocated
      remaining <- remaining - sum(allocated)
      active <- active[!binding]
    }
  }

  target_assert(
    abs(sum(added) - actual) <= tolerance,
    "destination allocation does not equal feasible relocated mass"
  )
  target_assert(
    all(added[!supported] == 0) &&
      all(baseline_share[supported] + added[supported] <=
            destination_cap + tolerance),
    "destination allocation violates support or cap"
  )
  list(
    added = added,
    actual = actual,
    capacity = capacity,
    total_capacity = total_capacity,
    cap_limited = total_capacity < min(requested_share, source_capacity) - tolerance
  )
}

target_destination_sequence <- function(count, destination_indices, weights) {
  target_assert(count >= 0L && length(count) == 1L, "invalid marker count")
  if (count == 0L) return(integer())
  target_assert(
    length(destination_indices) >= 1L &&
      all(weights[destination_indices] > 0) &&
      abs(sum(weights[destination_indices]) - 1) <= 1e-12,
    "destination weights are invalid"
  )
  assigned <- integer(length(destination_indices))
  result <- integer(count)
  for (move_index in seq_len(count)) {
    deficits <- move_index * weights[destination_indices] - assigned
    choice <- which.max(deficits)
    result[[move_index]] <- destination_indices[[choice]]
    assigned[[choice]] <- assigned[[choice]] + 1L
  }
  result
}

target_score <- function(baseline_draws, relocated_draws) {
  raw <- 100 * baseline_draws / relocated_draws
  display <- pmin(100, pmax(0, raw))
  list(
    point = stats::median(display),
    lower_90 = target_quantile(display, 0.05),
    upper_90 = target_quantile(display, 0.95)
  )
}
