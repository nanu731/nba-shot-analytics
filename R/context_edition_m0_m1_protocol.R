# Frozen, outcome-agnostic helpers for the Context Edition M0/M1 protocol.
# This file defines formulas and evaluation mechanics. It contains no model fit
# call and no data-loading path.

CONTEXT_PROTOCOL_VERSION <- "context_m0_m1_protocol_v0.1.0"
CONTEXT_BOOTSTRAP_SEED <- 20260914L
CONTEXT_BOOTSTRAP_REPLICATES <- 2000L
CONTEXT_LOG_CLIP <- 1e-15
CONTEXT_CALIBRATION_MARGIN <- 0.005
CONTEXT_CALIBRATION_BINS <- 10L
CONTEXT_MIN_SUBGROUP_SHOTS <- 200L

context_model_formulas <- function() {
  list(
    M0 = stats::as.formula(
      "cbind(makes, misses) ~ point_value_factor + s(player_id_factor, bs = 're')"
    ),
    M1 = stats::as.formula(
      paste(
        "cbind(makes, misses) ~ point_value_factor + finish_family +",
        "creation_family + s(player_id_factor, bs = 're')"
      )
    )
  )
}

context_factor_levels <- function() {
  list(
    point_value_factor = c("two", "three"),
    finish_family = c(
      "regular_jumper", "dunk", "layup", "floater", "hook",
      "fadeaway_or_turnaround", "step_back"
    ),
    creation_family = c(
      "other_or_unknown", "drive_cut_or_roll", "pull_up_or_self_created", "putback"
    )
  )
}

context_assert_finite <- function(x, name) {
  if (length(x) == 0L || anyNA(x) || any(!is.finite(x))) {
    stop(name, " must be non-empty, non-missing, and finite", call. = FALSE)
  }
  invisible(TRUE)
}

context_assert_binary <- function(x, name = "outcome") {
  context_assert_finite(x, name)
  if (any(!x %in% c(0, 1))) {
    stop(name, " must contain only zero and one", call. = FALSE)
  }
  invisible(TRUE)
}

context_clip_probability <- function(probability) {
  context_assert_finite(probability, "probability")
  if (any(probability < 0 | probability > 1)) {
    stop("probability must lie within [0, 1] before clipping", call. = FALSE)
  }
  pmin(pmax(probability, CONTEXT_LOG_CLIP), 1 - CONTEXT_LOG_CLIP)
}

context_log_loss <- function(outcome, probability, weights = NULL) {
  context_assert_binary(outcome)
  probability <- context_clip_probability(probability)
  if (length(outcome) != length(probability)) {
    stop("outcome and probability lengths differ", call. = FALSE)
  }
  if (is.null(weights)) weights <- rep(1, length(outcome))
  context_assert_finite(weights, "weights")
  if (length(weights) != length(outcome) || any(weights < 0) || sum(weights) <= 0) {
    stop("weights must align, be non-negative, and sum above zero", call. = FALSE)
  }
  loss <- -(outcome * log(probability) + (1 - outcome) * log(1 - probability))
  stats::weighted.mean(loss, weights)
}

context_expected_points <- function(probability, point_value) {
  probability <- context_clip_probability(probability)
  context_assert_finite(point_value, "point_value")
  if (length(probability) != length(point_value) || any(!point_value %in% c(2, 3))) {
    stop("point_value must align and contain only two or three", call. = FALSE)
  }
  probability * point_value
}

context_equal_count_bins <- function(probability, bins = CONTEXT_CALIBRATION_BINS) {
  probability <- context_clip_probability(probability)
  if (length(bins) != 1L || is.na(bins) || bins < 2L || bins > length(probability)) {
    stop("bins must be between two and the number of predictions", call. = FALSE)
  }
  order_index <- order(probability, seq_along(probability))
  assigned <- integer(length(probability))
  assigned[order_index] <- pmin(
    bins,
    floor((seq_along(probability) - 1L) * bins / length(probability)) + 1L
  )
  assigned
}

context_calibration_errors <- function(outcome, probability, bin_id, weights = NULL) {
  context_assert_binary(outcome)
  probability <- context_clip_probability(probability)
  if (length(outcome) != length(probability) || length(bin_id) != length(outcome)) {
    stop("calibration inputs must have equal lengths", call. = FALSE)
  }
  if (is.null(weights)) weights <- rep(1, length(outcome))
  context_assert_finite(weights, "weights")
  if (length(weights) != length(outcome) || any(weights < 0) || sum(weights) <= 0) {
    stop("calibration weights are invalid", call. = FALSE)
  }
  overall_bias <- stats::weighted.mean(outcome - probability, weights)
  bin_levels <- sort(unique(bin_id))
  bin_error <- vapply(bin_levels, function(bin) {
    keep <- bin_id == bin & weights > 0
    if (!any(keep)) return(NA_real_)
    abs(
      stats::weighted.mean(outcome[keep], weights[keep]) -
        stats::weighted.mean(probability[keep], weights[keep])
    )
  }, numeric(1))
  bin_weight <- vapply(bin_levels, function(bin) sum(weights[bin_id == bin]), numeric(1))
  keep_bins <- is.finite(bin_error) & bin_weight > 0
  ece <- stats::weighted.mean(bin_error[keep_bins], bin_weight[keep_bins])
  c(calibration_in_large_abs = abs(overall_bias), ece = ece)
}

context_paired_game_bootstrap <- function(
  data,
  replicates = CONTEXT_BOOTSTRAP_REPLICATES,
  seed = CONTEXT_BOOTSTRAP_SEED
) {
  required <- c("comparison_id", "game_id", "outcome", "probability_m0", "probability_m1")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) stop("missing bootstrap fields: ", paste(missing, collapse = ", "), call. = FALSE)
  context_assert_binary(data$outcome)
  data$probability_m0 <- context_clip_probability(data$probability_m0)
  data$probability_m1 <- context_clip_probability(data$probability_m1)
  if (anyNA(data$comparison_id) || anyNA(data$game_id)) {
    stop("comparison_id and game_id cannot be missing", call. = FALSE)
  }
  game_strata <- unique(data[c("comparison_id", "game_id")])
  if (anyDuplicated(paste(game_strata$comparison_id, game_strata$game_id, sep = "::"))) {
    stop("game keys must be unique within comparison", call. = FALSE)
  }
  data$bin_m0 <- context_equal_count_bins(data$probability_m0)
  data$bin_m1 <- context_equal_count_bins(data$probability_m1)
  strata <- split(game_strata$game_id, game_strata$comparison_id)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  result <- matrix(NA_real_, nrow = replicates, ncol = 3L)
  colnames(result) <- c(
    "log_loss_m1_minus_m0",
    "calibration_abs_m1_minus_m0",
    "ece_m1_minus_m0"
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
    loss_m0 <- context_log_loss(data$outcome, data$probability_m0, weights)
    loss_m1 <- context_log_loss(data$outcome, data$probability_m1, weights)
    cal_m0 <- context_calibration_errors(data$outcome, data$probability_m0, data$bin_m0, weights)
    cal_m1 <- context_calibration_errors(data$outcome, data$probability_m1, data$bin_m1, weights)
    result[replicate_id, ] <- c(loss_m1 - loss_m0, cal_m1 - cal_m0)
  }
  as.data.frame(result)
}

context_select_model <- function(
  pooled_log_loss_m0,
  pooled_log_loss_m1,
  paired_log_loss_se,
  calibration_abs_difference_ci_lower,
  ece_difference_ci_lower,
  season_log_loss_m0,
  season_log_loss_m1
) {
  values <- c(
    pooled_log_loss_m0, pooled_log_loss_m1, paired_log_loss_se,
    calibration_abs_difference_ci_lower, ece_difference_ci_lower,
    season_log_loss_m0, season_log_loss_m1
  )
  context_assert_finite(values, "selection inputs")
  if (length(season_log_loss_m0) != 3L || length(season_log_loss_m1) != 3L) {
    stop("selection requires exactly three retrospective seasons", call. = FALSE)
  }
  improvement <- pooled_log_loss_m0 - pooled_log_loss_m1
  if (improvement <= 0) {
    return(c(model = "M0", reason = "M0 has equal or lower pooled log loss"))
  }
  if (improvement <= paired_log_loss_se) {
    return(c(model = "M0", reason = "M0 is within one paired bootstrap standard error"))
  }
  calibration_worse <-
    calibration_abs_difference_ci_lower > CONTEXT_CALIBRATION_MARGIN ||
    ece_difference_ci_lower > CONTEXT_CALIBRATION_MARGIN
  if (calibration_worse) {
    return(c(model = "M0", reason = "M1 is materially worse calibrated"))
  }
  season_wins <- sum(season_log_loss_m1 < season_log_loss_m0)
  if (season_wins < 2L) {
    return(c(model = "M0", reason = "M1 improves fewer than two retrospective seasons"))
  }
  c(model = "M1", reason = "M1 clears the one-SE, calibration, and season-breadth gates")
}

context_validate_split_spec <- function(split_spec) {
  required <- c(
    "comparison_id", "order", "training_seasons", "validation_season",
    "split_unit", "game_overlap_allowed", "validation_outcomes_accessed"
  )
  missing <- setdiff(required, names(split_spec))
  if (length(missing) > 0L) stop("missing split fields: ", paste(missing, collapse = ", "), call. = FALSE)
  if (any(split_spec$split_unit != "whole_game")) stop("split unit must be whole_game", call. = FALSE)
  if (any(split_spec$game_overlap_allowed)) stop("game overlap is prohibited", call. = FALSE)
  if (any(split_spec$validation_outcomes_accessed)) stop("validation outcomes must remain sealed", call. = FALSE)
  season_number <- function(x) as.integer(substr(x, 1L, 4L))
  for (row in seq_len(nrow(split_spec))) {
    train <- strsplit(split_spec$training_seasons[row], ";", fixed = TRUE)[[1]]
    if (max(season_number(train)) >= season_number(split_spec$validation_season[row])) {
      stop("training seasons must precede validation season", call. = FALSE)
    }
  }
  invisible(TRUE)
}

context_validate_feature_matrix <- function(feature_matrix) {
  required <- c("field_or_concept", "m0", "m1")
  missing <- setdiff(required, names(feature_matrix))
  if (length(missing) > 0L) stop("missing feature fields: ", paste(missing, collapse = ", "), call. = FALSE)
  blocked <- c(
    "loc_x_or_loc_y", "shot_distance", "period_or_game_clock",
    "home_away_or_score_margin", "player_by_family", "raw_play_by_play_text",
    "post_shot_score_or_final_result", "free_throws_or_shot_trip_value",
    "volume_capacity_or_future_role"
  )
  rows <- match(blocked, feature_matrix$field_or_concept)
  if (anyNA(rows) || any(feature_matrix$m0[rows] != "BLOCK") || any(feature_matrix$m1[rows] != "BLOCK")) {
    stop("M2-or-later or leaking features entered M0/M1", call. = FALSE)
  }
  invisible(TRUE)
}
