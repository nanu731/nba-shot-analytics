# Outcome-agnostic constants and helpers for the third rolling-origin check.

CONTEXT_THIRD_VALIDATION_VERSION <- "context_third_validation_v0.1.0"
CONTEXT_THIRD_COMPARISON_ID <- "retrospective_3"
CONTEXT_THIRD_TRAINING_SEASONS <- c("2021-22", "2022-23", "2023-24", "2024-25")
CONTEXT_THIRD_VALIDATION_SEASON <- "2025-26"
CONTEXT_THIRD_LATER_SEASONS <- "2026-27"
CONTEXT_FIRST_RESULT_MANIFEST_SHA256 <- "ca1c7d9bffa5ed7b0b3cad96c1339538f44d43a1286bab583deacfee7d7aff4c"
CONTEXT_SECOND_RESULT_MANIFEST_SHA256 <- "a10db5ef9fcf93801c76975d83b317e95769ecdf6b5dbd22050781159fd06cb1"

context_third_season_interpretation <- function(
  log_loss_m0,
  log_loss_m1,
  bootstrap_se,
  calibration_abs_ci_lower,
  ece_ci_lower
) {
  context_first_season_interpretation(
    log_loss_m0,
    log_loss_m1,
    bootstrap_se,
    calibration_abs_ci_lower,
    ece_ci_lower
  )
}

context_character_equal <- function(left, right) {
  identical(lapply(left, as.character), lapply(right, as.character))
}

context_verify_third_fit_component <- function(component_root, expected_model_id) {
  manifest_path <- file.path(component_root, "completion_manifest.csv")
  if (!file.exists(manifest_path)) stop("fit component manifest is missing", call. = FALSE)
  manifest <- readr::read_csv(manifest_path, show_col_types = FALSE)
  context_verify_file_manifest(manifest, component_root)
  metadata <- readr::read_csv(file.path(component_root, "fit_metadata.csv"), show_col_types = FALSE)
  if (nrow(metadata) != 1L || metadata$model_id != expected_model_id ||
      !metadata$converged || metadata$validation_outcomes_accessed ||
      metadata$training_seasons != paste(CONTEXT_THIRD_TRAINING_SEASONS, collapse = ";")) {
    stop(expected_model_id, " fit component metadata is invalid", call. = FALSE)
  }
  fit_path <- file.path(component_root, "fit.rds")
  fit <- readRDS(fit_path)
  formulas <- context_model_formulas()
  expected_formula <- gsub("[[:space:]]+", "", paste(deparse(formulas[[expected_model_id]]), collapse = ""))
  observed_formula <- gsub("[[:space:]]+", "", paste(deparse(stats::formula(fit)), collapse = ""))
  if (!inherits(fit, "gam") || !isTRUE(fit$converged) || expected_formula != observed_formula ||
      length(fit$sp) != 1L || any(!is.finite(stats::coef(fit))) || any(!is.finite(fit$Vp))) {
    stop(expected_model_id, " fit object failed recovery checks", call. = FALSE)
  }
  list(
    fit = fit,
    fit_sha256 = context_sha256_file(fit_path),
    metadata = metadata,
    diagnostics = readr::read_csv(file.path(component_root, "fit_diagnostics.csv"), show_col_types = FALSE),
    checks = readr::read_csv(file.path(component_root, "sanity_checks.csv"), show_col_types = FALSE)
  )
}
