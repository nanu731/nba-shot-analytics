# Outcome-agnostic helpers for the first Context Edition rolling-origin check.

CONTEXT_FIRST_VALIDATION_VERSION <- "context_first_validation_v0.1.0"
CONTEXT_FIRST_COMPARISON_ID <- "retrospective_1"
CONTEXT_FIRST_TRAINING_SEASONS <- c("2021-22", "2022-23")
CONTEXT_FIRST_VALIDATION_SEASON <- "2023-24"

context_sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) stop("could not hash ", path, call. = FALSE)
  strsplit(output[[1]], " ", fixed = TRUE)[[1]][[1]]
}

context_hash_values <- function(values) {
  path <- tempfile("context-hash-")
  on.exit(unlink(path), add = TRUE)
  writeLines(enc2utf8(as.character(values)), path, useBytes = TRUE)
  context_sha256_file(path)
}

context_write_csv_stable <- function(data, path) {
  readr::write_csv(data, path, na = "", quote = "needed")
}

context_atomic_write_csv <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = paste0(".", basename(path), "-"), tmpdir = dirname(path))
  context_write_csv_stable(data, temporary)
  if (!file.rename(temporary, path)) stop("atomic CSV publication failed: ", path, call. = FALSE)
  invisible(path)
}

context_current_rss_bytes <- function() {
  output <- suppressWarnings(system2("ps", c("-o", "rss=", "-p", as.character(Sys.getpid())), stdout = TRUE))
  value <- suppressWarnings(as.numeric(trimws(output[[1]])))
  if (length(value) != 1L || !is.finite(value)) return(NA_real_)
  value * 1024
}

context_available_disk_bytes <- function(path) {
  output <- system2("df", c("-k", path), stdout = TRUE)
  fields <- strsplit(trimws(output[[length(output)]]), "[[:space:]]+")[[1]]
  value <- suppressWarnings(as.numeric(fields[[4]]))
  if (!is.finite(value)) stop("could not measure free disk", call. = FALSE)
  value * 1024
}

context_git_value <- function(repo_root, arguments) {
  output <- system2("git", c("-C", repo_root, arguments), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop("git command failed: ", paste(arguments, collapse = " "), call. = FALSE)
  trimws(output[[1]])
}

context_verify_file_manifest <- function(manifest, root) {
  required <- c("artifact", "sha256", "atomic_complete", "checks_passed")
  missing <- setdiff(required, names(manifest))
  if (length(missing) > 0L) stop("manifest fields missing: ", paste(missing, collapse = ", "), call. = FALSE)
  paths <- file.path(root, manifest$artifact)
  if (!all(file.exists(paths))) stop("manifest artifact is missing", call. = FALSE)
  hashes <- vapply(paths, context_sha256_file, character(1))
  if (!identical(unname(hashes), unname(manifest$sha256))) stop("manifest hash mismatch", call. = FALSE)
  if (!all(manifest$atomic_complete) || !all(manifest$checks_passed)) stop("manifest is not complete", call. = FALSE)
  invisible(TRUE)
}

context_make_prediction_data <- function(data, fit) {
  levels_frozen <- context_factor_levels()
  player_levels <- levels(fit$model$player_id_factor)
  result <- data
  result$player_id_factor <- factor(as.character(result$player_id), levels = player_levels)
  result$point_value_factor <- factor(
    ifelse(result$point_value == 2L, "two", "three"),
    levels = levels_frozen$point_value_factor
  )
  result$finish_family <- factor(result$finish_family, levels = levels_frozen$finish_family)
  result$creation_family <- factor(result$creation_family, levels = levels_frozen$creation_family)
  result
}

context_predict_first_validation <- function(fit, data) {
  prediction_data <- context_make_prediction_data(data, fit)
  player_levels <- levels(fit$model$player_id_factor)
  known <- as.character(data$player_id) %in% player_levels
  probability <- rep(NA_real_, nrow(data))
  if (any(known)) {
    probability[known] <- as.numeric(stats::predict(
      fit, newdata = prediction_data[known, , drop = FALSE], type = "response"
    ))
  }
  if (any(!known)) {
    unseen <- prediction_data[!known, , drop = FALSE]
    unseen$player_id_factor <- factor(
      rep("__UNSEEN_PLAYER__", nrow(unseen)),
      levels = c(player_levels, "__UNSEEN_PLAYER__")
    )
    probability[!known] <- suppressWarnings(context_preflight_fixed_prediction(fit, unseen))
  }
  if (anyNA(probability) || any(!is.finite(probability)) || any(probability <= 0 | probability >= 1)) {
    stop("prediction probabilities are missing, non-finite, or outside (0, 1)", call. = FALSE)
  }
  list(probability = probability, known_player = known)
}

context_auc <- function(outcome, probability) {
  context_assert_binary(outcome)
  probability <- context_clip_probability(probability)
  positives <- sum(outcome == 1L)
  negatives <- sum(outcome == 0L)
  if (positives == 0L || negatives == 0L) return(NA_real_)
  ranks <- rank(probability, ties.method = "average")
  (sum(ranks[outcome == 1L]) - positives * (positives + 1) / 2) / (positives * negatives)
}

context_calibration_diagnostics <- function(outcome, probability) {
  probability <- context_clip_probability(probability)
  linear_predictor <- stats::qlogis(probability)
  fit_value <- function(formula) {
    fit <- tryCatch(
      suppressWarnings(stats::glm(formula, family = stats::binomial())),
      error = function(error) error
    )
    if (inherits(fit, "error") || !isTRUE(fit$converged) || any(!is.finite(stats::coef(fit)))) {
      return(c(value = NA_real_, ok = 0))
    }
    c(value = unname(tail(stats::coef(fit), 1L)), ok = 1)
  }
  intercept <- fit_value(outcome ~ 1 + offset(linear_predictor))
  slope <- fit_value(outcome ~ linear_predictor)
  c(
    predicted_rate = mean(probability),
    observed_rate = mean(outcome),
    signed_bias_observed_minus_predicted = mean(outcome - probability),
    absolute_bias = abs(mean(outcome - probability)),
    calibration_intercept = intercept[["value"]],
    calibration_intercept_estimable = intercept[["ok"]],
    calibration_slope = slope[["value"]],
    calibration_slope_estimable = slope[["ok"]]
  )
}

context_model_metrics <- function(data, probability) {
  expected_points <- context_expected_points(probability, data$point_value)
  realized_points <- data$point_value * data$field_goal_made
  game_totals <- data.frame(
    game_id = data$source_game_id,
    expected_points = expected_points,
    realized_points = realized_points
  ) |>
    dplyr::group_by(game_id) |>
    dplyr::summarise(
      expected_points = sum(expected_points),
      realized_points = sum(realized_points),
      .groups = "drop"
    )
  calibration <- context_calibration_diagnostics(data$field_goal_made, probability)
  c(
    bernoulli_log_loss = context_log_loss(data$field_goal_made, probability),
    brier_score = mean((data$field_goal_made - probability)^2),
    roc_auc = context_auc(data$field_goal_made, probability),
    expected_points_rmse = sqrt(mean((realized_points - expected_points)^2)),
    game_points_mae = mean(abs(game_totals$realized_points - game_totals$expected_points)),
    game_points_rmse = sqrt(mean((game_totals$realized_points - game_totals$expected_points)^2)),
    points_bias_per_100 = 100 * mean(realized_points - expected_points),
    calibration
  )
}

context_calibration_bins_table <- function(data, probability, model_id) {
  bin_id <- context_equal_count_bins(probability, CONTEXT_CALIBRATION_BINS)
  data.frame(
    bin_id = bin_id,
    probability = probability,
    outcome = data$field_goal_made
  ) |>
    dplyr::group_by(bin_id) |>
    dplyr::summarise(
      shots = dplyr::n(),
      mean_prediction = mean(probability),
      observed_make_rate = mean(outcome),
      signed_gap_observed_minus_predicted = observed_make_rate - mean_prediction,
      absolute_gap = abs(signed_gap_observed_minus_predicted),
      .groups = "drop"
    ) |>
    dplyr::mutate(model_id = model_id, .before = 1L)
}

context_training_volume_groups <- function(training_metadata) {
  counts <- training_metadata |>
    dplyr::count(player_id, name = "training_attempts") |>
    dplyr::arrange(training_attempts, player_id) |>
    dplyr::mutate(
      volume_index = pmin(4L, floor((dplyr::row_number() - 1L) * 4L / dplyr::n()) + 1L),
      player_volume_group = paste0("returning_q", volume_index)
    )
  counts
}

context_subgroup_calibration <- function(data, probability, model_id) {
  axes <- list(
    point_value = ifelse(data$point_value == 2L, "two", "three"),
    finish_family = as.character(data$finish_family),
    creation_family = as.character(data$creation_family),
    player_training_volume = as.character(data$player_volume_group)
  )
  purrr::imap_dfr(axes, function(values, axis) {
    data.frame(
      subgroup = values,
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
      dplyr::mutate(model_id = model_id, subgroup_axis = axis, .before = 1L)
  })
}

context_first_season_interpretation <- function(
  log_loss_m0,
  log_loss_m1,
  bootstrap_se,
  calibration_abs_ci_lower,
  ece_ci_lower
) {
  improvement <- log_loss_m0 - log_loss_m1
  calibration_worse <- calibration_abs_ci_lower > CONTEXT_CALIBRATION_MARGIN ||
    ece_ci_lower > CONTEXT_CALIBRATION_MARGIN
  if (log_loss_m1 >= log_loss_m0) {
    return(c(label = "provisional_M0_lower_log_loss", one_se_passed = "FALSE", calibration_gate_passed = as.character(!calibration_worse)))
  }
  if (improvement <= bootstrap_se) {
    return(c(label = "provisional_M0_within_one_standard_error", one_se_passed = "FALSE", calibration_gate_passed = as.character(!calibration_worse)))
  }
  if (calibration_worse) {
    return(c(label = "provisional_M1_improvement_blocked_by_calibration", one_se_passed = "TRUE", calibration_gate_passed = "FALSE"))
  }
  c(label = "provisional_M1_clears_first_season_gates", one_se_passed = "TRUE", calibration_gate_passed = "TRUE")
}
