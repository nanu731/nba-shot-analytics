#!/usr/bin/env Rscript

# Outcome-agnostic helpers for the Context Edition M2 preregistration.
# This file defines formulas, guards, and mechanical decisions. It contains no
# model-fitting call and no canonical-data loading path.

CONTEXT_M2_PROTOCOL_VERSION <- "context_m2_protocol_v0.1.0"
CONTEXT_M2_BOOTSTRAP_SEED <- 20260914L
CONTEXT_M2_BOOTSTRAP_REPLICATES <- 2000L
CONTEXT_M2_LOG_CLIP <- 1e-15
CONTEXT_M2_CALIBRATION_MARGIN <- 0.005
CONTEXT_M2_DISTANCE_MIN <- 0
CONTEXT_M2_DISTANCE_MAX <- 100
CONTEXT_M2_INITIAL_K <- 10L
CONTEXT_M2_ESCALATED_K <- 20L
CONTEXT_M2_K_CHECK_SEED <- 20260916L
CONTEXT_M2_K_CHECK_SUBSAMPLE <- 5000L
CONTEXT_M2_K_CHECK_REPLICATES <- 400L

context_m2_formulas <- function(k = CONTEXT_M2_INITIAL_K) {
  if (length(k) != 1L || is.na(k) || !k %in% c(CONTEXT_M2_INITIAL_K, CONTEXT_M2_ESCALATED_K)) {
    stop("k must be the registered initial or one-time escalated value", call. = FALSE)
  }
  distance_term <- sprintf("s(shot_distance_feet, bs = 'cr', k = %d, m = 2)", k)
  list(
    M0 = stats::as.formula(
      "cbind(makes, misses) ~ point_value_factor + s(player_id_factor, bs = 're')"
    ),
    M1 = stats::as.formula(paste(
      "cbind(makes, misses) ~ point_value_factor + finish_family +",
      "creation_family + s(player_id_factor, bs = 're')"
    )),
    D1 = stats::as.formula(paste(
      "cbind(makes, misses) ~ point_value_factor +",
      "s(player_id_factor, bs = 're') +", distance_term
    )),
    M2 = stats::as.formula(paste(
      "cbind(makes, misses) ~ point_value_factor + finish_family +",
      "creation_family + s(player_id_factor, bs = 're') +", distance_term
    ))
  )
}

context_m2_factor_levels <- function() {
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

context_m2_distance_band <- function(distance) {
  context_m2_validate_distance(distance)
  cut(
    distance,
    breaks = c(-Inf, 4, 10, 22, 30, Inf),
    right = FALSE,
    labels = c(
      "restricted_0_to_under_4", "other_paint_4_to_under_10",
      "midrange_10_to_under_22", "three_point_distance_22_to_under_30",
      "long_heave_30_plus"
    )
  )
}

context_m2_validate_distance <- function(distance, training_range = NULL) {
  if (length(distance) == 0L || anyNA(distance) || any(!is.finite(distance))) {
    stop("shot distance must be non-empty, non-missing, and finite", call. = FALSE)
  }
  if (any(distance != floor(distance))) {
    stop("shot distance must remain in canonical whole feet", call. = FALSE)
  }
  if (any(distance < CONTEXT_M2_DISTANCE_MIN | distance > CONTEXT_M2_DISTANCE_MAX)) {
    stop("shot distance lies outside the canonical 0-to-100-foot guard", call. = FALSE)
  }
  if (!is.null(training_range)) {
    if (length(training_range) != 2L || anyNA(training_range) || any(!is.finite(training_range))) {
      stop("training range must contain two finite endpoints", call. = FALSE)
    }
    if (any(distance < training_range[1] | distance > training_range[2])) {
      stop("prediction distance lies outside the observed training range", call. = FALSE)
    }
  }
  invisible(TRUE)
}

context_m2_k_escalation <- function(edf, k_index, p_value, current_k) {
  values <- c(edf, k_index, p_value, current_k)
  if (anyNA(values) || any(!is.finite(values))) {
    stop("distance-smooth k diagnostics must be finite", call. = FALSE)
  }
  if (current_k == CONTEXT_M2_ESCALATED_K) return("stop_if_still_inadequate")
  if (current_k != CONTEXT_M2_INITIAL_K) stop("unregistered k", call. = FALSE)
  near_ceiling <- edf >= 0.95 * (current_k - 1)
  residual_pattern <- k_index < 0.9 && p_value < 0.05
  if (near_ceiling && residual_pattern) "refit_once_at_k_20" else "retain_k_10"
}

context_m2_select <- function(
  pooled_log_loss_m1,
  pooled_log_loss_m2,
  paired_log_loss_se,
  calibration_abs_difference_ci_lower,
  ece_difference_ci_lower,
  season_log_loss_m1,
  season_log_loss_m2
) {
  values <- c(
    pooled_log_loss_m1, pooled_log_loss_m2, paired_log_loss_se,
    calibration_abs_difference_ci_lower, ece_difference_ci_lower,
    season_log_loss_m1, season_log_loss_m2
  )
  if (anyNA(values) || any(!is.finite(values))) stop("selection inputs must be finite", call. = FALSE)
  if (length(season_log_loss_m1) != 3L || length(season_log_loss_m2) != 3L) {
    stop("selection requires exactly three development seasons", call. = FALSE)
  }
  improvement <- pooled_log_loss_m1 - pooled_log_loss_m2
  if (improvement <= 0) return(c(model = "M1", reason = "M1 has equal or lower pooled log loss"))
  if (improvement <= paired_log_loss_se) return(c(model = "M1", reason = "M1 is within one paired bootstrap standard error"))
  calibration_worse <-
    calibration_abs_difference_ci_lower > CONTEXT_M2_CALIBRATION_MARGIN ||
    ece_difference_ci_lower > CONTEXT_M2_CALIBRATION_MARGIN
  if (calibration_worse) return(c(model = "M1", reason = "M2 is materially worse calibrated"))
  if (sum(season_log_loss_m2 < season_log_loss_m1) < 2L) {
    return(c(model = "M1", reason = "M2 improves fewer than two development seasons"))
  }
  c(model = "M2", reason = "M2 clears the one-SE, calibration, and season-breadth gates")
}

context_m2_validate_feature_allowlist <- function(feature_matrix) {
  required <- c("field_or_concept", "m0", "m1", "d1", "m2")
  missing <- setdiff(required, names(feature_matrix))
  if (length(missing) > 0L) stop("feature matrix fields missing", call. = FALSE)
  row_for <- function(name) {
    row <- match(name, feature_matrix$field_or_concept)
    if (is.na(row)) stop("feature matrix row missing: ", name, call. = FALSE)
    row
  }
  distance_row <- row_for("shot_distance_feet")
  if (!identical(unname(as.character(feature_matrix[distance_row, c("m0", "m1", "d1", "m2")])), c("BLOCK", "BLOCK", "ALLOW", "ALLOW"))) {
    stop("distance permissions differ from the registered nested design", call. = FALSE)
  }
  blocked <- c(
    "location_x_or_y", "period_or_game_clock", "home_away_or_score_margin",
    "team_id", "player_by_family_or_distance", "raw_play_by_play_text",
    "post_shot_or_future_context"
  )
  for (name in blocked) {
    row <- row_for(name)
    if (any(feature_matrix[row, c("m0", "m1", "d1", "m2")] != "BLOCK")) {
      stop("blocked feature entered a candidate: ", name, call. = FALSE)
    }
  }
  invisible(TRUE)
}

context_m2_validate_split_spec <- function(split_spec) {
  required <- c("comparison_id", "training_seasons", "validation_season", "evidence_status", "outcomes_accessed")
  if (length(setdiff(required, names(split_spec))) > 0L) stop("split specification is incomplete", call. = FALSE)
  if (any(split_spec$outcomes_accessed)) stop("outcome access must be false at preregistration", call. = FALSE)
  historical <- split_spec$validation_season %in% c("2023-24", "2024-25", "2025-26")
  if (any(split_spec$evidence_status[historical] != "historical_model_development")) {
    stop("historical comparisons must be labeled model development", call. = FALSE)
  }
  prospective <- split_spec$validation_season == "2026-27"
  if (sum(prospective) != 1L || split_spec$evidence_status[prospective] != "prospective_confirmation_untouched") {
    stop("2026-27 must be the single untouched prospective comparison", call. = FALSE)
  }
  invisible(TRUE)
}

