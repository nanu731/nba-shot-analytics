# Outcome-agnostic helpers for the Context Edition training-only preflight.

CONTEXT_PREFLIGHT_TRAINING_SEASONS <- c("2021-22", "2022-23")
CONTEXT_PREFLIGHT_VALIDATION_SEASONS <- c("2023-24", "2024-25", "2025-26")

context_preflight_group_keys <- function(model_id) {
  switch(
    model_id,
    M0 = c("player_id_factor", "point_value_factor"),
    M1 = c(
      "player_id_factor", "point_value_factor",
      "finish_family", "creation_family"
    ),
    stop("unknown model_id: ", model_id, call. = FALSE)
  )
}

context_preflight_group_counts <- function(data, model_id) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("dplyr is required", call. = FALSE)
  }
  required <- c(context_preflight_group_keys(model_id), "field_goal_made")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("missing grouping fields: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (any(!data$field_goal_made %in% c(0L, 1L)) || anyNA(data$field_goal_made)) {
    stop("field_goal_made must contain only zero and one", call. = FALSE)
  }
  keys <- context_preflight_group_keys(model_id)
  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys)), .drop = TRUE) |>
    dplyr::summarise(
      makes = sum(field_goal_made),
      attempts = dplyr::n(),
      misses = attempts - makes,
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(keys)))
}

context_preflight_atomic_publish <- function(stage_path, final_path) {
  if (!dir.exists(stage_path)) stop("atomic stage is missing", call. = FALSE)
  if (file.exists(final_path) || dir.exists(final_path)) {
    stop("atomic target already exists", call. = FALSE)
  }
  if (!file.rename(stage_path, final_path)) {
    stop("atomic directory publication failed", call. = FALSE)
  }
  invisible(final_path)
}

context_preflight_verify_manifest <- function(manifest, root, hash_function) {
  required <- c("artifact", "sha256", "atomic_complete", "checks_passed")
  missing <- setdiff(required, names(manifest))
  if (length(missing) > 0L) {
    stop("manifest fields missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  paths <- file.path(root, manifest$artifact)
  if (!all(file.exists(paths))) stop("manifest artifact is missing", call. = FALSE)
  if (!all(manifest$atomic_complete) || !all(manifest$checks_passed)) {
    stop("manifest is not complete and passing", call. = FALSE)
  }
  observed <- vapply(paths, hash_function, character(1))
  if (!identical(unname(observed), unname(manifest$sha256))) {
    stop("manifest hash mismatch", call. = FALSE)
  }
  invisible(TRUE)
}

context_preflight_fixed_prediction <- function(model, newdata) {
  stats::plogis(stats::predict(
    model,
    newdata = newdata,
    type = "link",
    exclude = "s(player_id_factor)",
    newdata.guaranteed = TRUE
  ))
}

context_preflight_boundary_grid <- function(player_levels, point_value_levels, distances) {
  if (length(player_levels) < 1L || length(point_value_levels) != 2L || length(distances) < 1L) {
    stop("boundary-grid inputs are incomplete", call. = FALSE)
  }
  grid <- tidyr::crossing(
    point_value_factor = point_value_levels,
    shot_distance_feet = distances
  )
  grid$player_id_factor <- factor(player_levels[[1]], levels = player_levels)
  grid$point_value_factor <- factor(grid$point_value_factor, levels = point_value_levels)
  grid |>
    dplyr::select(player_id_factor, point_value_factor, shot_distance_feet)
}
