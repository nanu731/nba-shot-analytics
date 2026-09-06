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

target_destination_sequence <- function(count, destination_indices, weights) {
  target_assert(count >= 0L && length(count) == 1L, "invalid marker count")
  if (count == 0L) return(integer())
  target_assert(
    length(destination_indices) >= 2L &&
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
