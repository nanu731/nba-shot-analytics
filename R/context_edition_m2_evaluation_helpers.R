# Outcome-agnostic helpers for the frozen historical M2-versus-M1 evaluation.

CONTEXT_M2_EVALUATION_VERSION <- "context_m2_historical_evaluation_v0.1.0"
CONTEXT_M2_HISTORICAL_VALIDATION_SEASONS <- c("2023-24", "2024-25", "2025-26")
CONTEXT_M2_PROSPECTIVE_SEASON <- "2026-27"

context_m2_evaluation_assert <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  invisible(TRUE)
}

context_m2_evaluation_character_equal <- function(left, right) {
  identical(lapply(left, as.character), lapply(right, as.character))
}

context_m2_evaluation_verify_hash <- function(path, expected_hash, hash_function) {
  if (!file.exists(path)) stop("reusable artifact is missing", call. = FALSE)
  observed <- hash_function(path)
  if (!grepl("^[0-9a-f]{64}$", expected_hash) || observed != expected_hash) {
    stop("reusable artifact hash mismatch", call. = FALSE)
  }
  invisible(observed)
}

context_m2_evaluation_recovery_action <- function(
  result_exists, access_marker_exists, prediction_checkpoint_exists
) {
  if (result_exists) return("verify_completed_result")
  if (access_marker_exists && prediction_checkpoint_exists) return("resume_from_predictions")
  if (access_marker_exists && !prediction_checkpoint_exists) return("stop_for_manual_recovery")
  if (!access_marker_exists && prediction_checkpoint_exists) return("reject_orphan_checkpoint")
  "start_fresh_authorized_execution"
}

context_m2_evaluation_validate_windows <- function(windows) {
  required <- c(
    "evaluation_version", "comparison_id", "order", "training_seasons",
    "validation_season", "m1_fit_source", "m1_fit_sha256", "m2_fit_source",
    "m2_fit_policy", "validation_outcomes_accessed"
  )
  missing <- setdiff(required, names(windows))
  if (length(missing) > 0L) stop("window fields missing: ", paste(missing, collapse = ", "), call. = FALSE)
  expected_training <- c(
    "2021-22;2022-23",
    "2021-22;2022-23;2023-24",
    "2021-22;2022-23;2023-24;2024-25"
  )
  context_m2_evaluation_assert(nrow(windows) == 3L, "exactly three historical windows are required")
  context_m2_evaluation_assert(identical(as.integer(windows$order), 1:3), "window order changed")
  context_m2_evaluation_assert(
    identical(windows$training_seasons, expected_training),
    "training windows changed"
  )
  context_m2_evaluation_assert(
    identical(windows$validation_season, CONTEXT_M2_HISTORICAL_VALIDATION_SEASONS),
    "historical validation seasons changed"
  )
  context_m2_evaluation_assert(
    !any(windows$validation_outcomes_accessed),
    "validation access flags must remain false before execution"
  )
  context_m2_evaluation_assert(
    !any(grepl(CONTEXT_M2_PROSPECTIVE_SEASON, windows$m1_fit_source, fixed = TRUE)) &&
      !any(grepl(CONTEXT_M2_PROSPECTIVE_SEASON, windows$m2_fit_source, fixed = TRUE)),
    "prospective-season path entered the historical runner"
  )
  invisible(TRUE)
}

context_m2_evaluation_guard_seasons <- function(training_seasons, validation_season) {
  allowed_training <- c("2021-22", "2022-23", "2023-24", "2024-25")
  if (validation_season == CONTEXT_M2_PROSPECTIVE_SEASON ||
      CONTEXT_M2_PROSPECTIVE_SEASON %in% training_seasons) {
    stop("2026-27 is sealed and cannot be loaded by this runner", call. = FALSE)
  }
  if (!validation_season %in% CONTEXT_M2_HISTORICAL_VALIDATION_SEASONS ||
      any(!training_seasons %in% allowed_training)) {
    stop("unregistered season requested", call. = FALSE)
  }
  train_start <- as.integer(substr(training_seasons, 1L, 4L))
  validation_start <- as.integer(substr(validation_season, 1L, 4L))
  if (max(train_start) >= validation_start) stop("training must precede validation", call. = FALSE)
  invisible(TRUE)
}

context_m2_evaluation_group_counts <- function(data) {
  required <- c(
    "player_id_factor", "point_value_factor", "finish_family",
    "creation_family", "shot_distance_feet", "field_goal_made"
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) stop("grouping fields missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (anyNA(data$field_goal_made) || any(!data$field_goal_made %in% c(0L, 1L))) {
    stop("training outcome must be binary", call. = FALSE)
  }
  data |>
    dplyr::group_by(
      player_id_factor, point_value_factor, finish_family,
      creation_family, shot_distance_feet, .drop = TRUE
    ) |>
    dplyr::summarise(
      makes = sum(field_goal_made), attempts = dplyr::n(),
      misses = attempts - makes, .groups = "drop"
    ) |>
    dplyr::arrange(
      player_id_factor, point_value_factor, finish_family,
      creation_family, shot_distance_feet
    )
}

context_m2_evaluation_predict <- function(fit, data) {
  levels_frozen <- context_m2_factor_levels()
  player_levels <- levels(fit$model$player_id_factor)
  newdata <- data
  newdata$player_id_factor <- factor(as.character(data$player_id), levels = player_levels)
  newdata$point_value_factor <- factor(
    ifelse(data$point_value == 2L, "two", "three"),
    levels = levels_frozen$point_value_factor
  )
  newdata$finish_family <- factor(data$finish_family, levels = levels_frozen$finish_family)
  newdata$creation_family <- factor(data$creation_family, levels = levels_frozen$creation_family)
  context_m2_validate_distance(newdata$shot_distance_feet, range(fit$model$shot_distance_feet))
  known <- as.character(data$player_id) %in% player_levels
  probability <- rep(NA_real_, nrow(data))
  if (any(known)) {
    probability[known] <- as.numeric(stats::predict(
      fit, newdata = newdata[known, , drop = FALSE], type = "response"
    ))
  }
  if (any(!known)) {
    unseen <- newdata[!known, , drop = FALSE]
    unseen$player_id_factor <- factor(
      rep("__UNSEEN_PLAYER__", nrow(unseen)),
      levels = c(player_levels, "__UNSEEN_PLAYER__")
    )
    probability[!known] <- suppressWarnings(context_preflight_fixed_prediction(fit, unseen))
  }
  if (anyNA(probability) || any(!is.finite(probability)) || any(probability <= 0 | probability >= 1)) {
    stop("M2 probabilities are missing, non-finite, or outside (0, 1)", call. = FALSE)
  }
  list(probability = probability, known_player = known)
}

context_m2_distance_subgroup_calibration <- function(data, probability, model_id) {
  distance_group <- as.character(context_m2_distance_band(data$shot_distance_feet))
  data.frame(
    subgroup = distance_group,
    probability = probability,
    outcome = data$field_goal_made,
    point_value = data$point_value
  ) |>
    dplyr::group_by(subgroup) |>
    dplyr::summarise(
      shots = dplyr::n(),
      mean_prediction = mean(probability),
      observed_make_rate = mean(outcome),
      signed_gap_observed_minus_predicted = observed_make_rate - mean_prediction,
      absolute_gap = abs(signed_gap_observed_minus_predicted),
      expected_points_per_shot = mean(point_value * probability),
      realized_points_per_shot = mean(point_value * outcome),
      precision_claim_eligible = shots >= CONTEXT_MIN_SUBGROUP_SHOTS,
      .groups = "drop"
    ) |>
    dplyr::mutate(model_id = model_id, subgroup_axis = "distance_band", .before = 1L)
}

context_m2_paired_game_bootstrap <- function(
  data,
  replicates = CONTEXT_M2_BOOTSTRAP_REPLICATES,
  seed = CONTEXT_M2_BOOTSTRAP_SEED
) {
  required <- c("comparison_id", "game_id", "outcome", "probability_m1", "probability_m2")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) stop("bootstrap fields missing: ", paste(missing, collapse = ", "), call. = FALSE)
  context_assert_binary(data$outcome)
  data$probability_m1 <- context_clip_probability(data$probability_m1)
  data$probability_m2 <- context_clip_probability(data$probability_m2)
  game_strata <- unique(data[c("comparison_id", "game_id")])
  strata <- split(game_strata$game_id, game_strata$comparison_id)
  data$bin_m1 <- context_equal_count_bins(data$probability_m1)
  data$bin_m2 <- context_equal_count_bins(data$probability_m2)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  result <- matrix(NA_real_, nrow = replicates, ncol = 3L)
  colnames(result) <- c(
    "log_loss_m2_minus_m1", "calibration_abs_m2_minus_m1", "ece_m2_minus_m1"
  )
  row_key <- paste(data$comparison_id, data$game_id, sep = "::")
  for (replicate_id in seq_len(replicates)) {
    sampled_keys <- unlist(lapply(names(strata), function(stratum) {
      sampled <- sample(strata[[stratum]], length(strata[[stratum]]), replace = TRUE)
      paste(stratum, sampled, sep = "::")
    }), use.names = FALSE)
    multiplicity <- table(sampled_keys)
    weights <- as.numeric(multiplicity[row_key])
    weights[is.na(weights)] <- 0
    loss_m1 <- context_log_loss(data$outcome, data$probability_m1, weights)
    loss_m2 <- context_log_loss(data$outcome, data$probability_m2, weights)
    cal_m1 <- context_calibration_errors(data$outcome, data$probability_m1, data$bin_m1, weights)
    cal_m2 <- context_calibration_errors(data$outcome, data$probability_m2, data$bin_m2, weights)
    result[replicate_id, ] <- c(loss_m2 - loss_m1, cal_m2 - cal_m1)
  }
  as.data.frame(result)
}

context_m2_evaluation_select <- function(
  pooled_m1, pooled_m2, paired_se, calibration_lower, ece_lower,
  season_m1, season_m2, d1_signal = NULL
) {
  # d1_signal is deliberately ignored: D1 is interpretive only.
  context_m2_select(
    pooled_m1, pooled_m2, paired_se, calibration_lower, ece_lower,
    season_m1, season_m2
  )
}

context_m2_evaluation_verify_authorization <- function(path, comparison_id, pre_result_commit) {
  if (!file.exists(path)) stop("separate execution authorization is missing", call. = FALSE)
  authorization <- readr::read_csv(path, show_col_types = FALSE)
  required <- c("comparison_id", "authorized", "pre_result_implementation_commit")
  if (nrow(authorization) != 1L || length(setdiff(required, names(authorization))) > 0L ||
      authorization$comparison_id != comparison_id || !authorization$authorized ||
      authorization$pre_result_implementation_commit != pre_result_commit) {
    stop("execution authorization does not match this frozen comparison", call. = FALSE)
  }
  invisible(TRUE)
}

context_m2_evaluation_atomic_publish <- function(stage, final) {
  context_preflight_atomic_publish(stage, final)
}
