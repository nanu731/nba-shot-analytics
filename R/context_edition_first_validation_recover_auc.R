#!/usr/bin/env Rscript

# Recover the non-selecting AUC diagnostic from the verified private prediction
# checkpoint. This script has no canonical-data path and cannot fit a model.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(purrr)
  library(readr)
})

options(stringsAsFactors = FALSE)
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_first_validation_recover_auc.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
mode <- if (length(commandArgs(trailingOnly = TRUE)) == 0L) "run" else commandArgs(trailingOnly = TRUE)[[1]]
if (!mode %in% c("run", "verify")) stop("mode must be run or verify", call. = FALSE)

source(file.path(repo_root, "R", "context_edition_m0_m1_protocol.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_preflight_helpers.R"), local = TRUE)
source(file.path(repo_root, "R", "context_edition_first_validation_helpers.R"), local = TRUE)

private_parent <- file.path(repo_root, "data", "cache", "context_edition_first_validation")
source_checkpoint <- file.path(private_parent, "retrospective_1_v0.1.0")
recovery_checkpoint <- file.path(private_parent, "retrospective_1_v0.1.1_auc_recovery")
archive_root <- file.path(
  private_parent, "recovery_archives", "20260915T004914Z_auc_integer_overflow"
)
tracked_results <- file.path(
  repo_root, "data", "processed", "context_edition_first_validation_v0_1", "results"
)

verify_checkpoint <- function(root) {
  manifest <- read_csv(file.path(root, "completion_manifest.csv"), show_col_types = FALSE)
  context_verify_file_manifest(manifest, root)
  invisible(manifest)
}
verify_public <- function(root) {
  manifest <- read_csv(file.path(root, "artifact_manifest.csv"), show_col_types = FALSE)
  context_verify_file_manifest(manifest, root)
  invisible(manifest)
}

if (mode == "verify") {
  verify_checkpoint(source_checkpoint)
  verify_checkpoint(recovery_checkpoint)
  verify_public(tracked_results)
  archive_manifest <- read_csv(file.path(archive_root, "archive_manifest.csv"), show_col_types = FALSE)
  archived_paths <- file.path(archive_root, archive_manifest$archived_path)
  if (!all(file.exists(archived_paths))) stop("archived original result is incomplete", call. = FALSE)
  hashes <- vapply(archived_paths, context_sha256_file, character(1))
  if (!identical(unname(hashes), unname(archive_manifest$sha256_before)) ||
      !identical(unname(hashes), unname(archive_manifest$sha256_after))) {
    stop("archived original result hash mismatch", call. = FALSE)
  }
  message("AUC recovery and preserved original result verified; no source outcome was read")
  quit(save = "no", status = 0L)
}

if (!dir.exists(source_checkpoint)) stop("verified source checkpoint is missing", call. = FALSE)
if (!dir.exists(tracked_results)) stop("original tracked result is missing", call. = FALSE)
if (dir.exists(recovery_checkpoint) || dir.exists(archive_root)) stop("AUC recovery already exists", call. = FALSE)
source_manifest <- verify_checkpoint(source_checkpoint)
original_public_manifest <- verify_public(tracked_results)

source_manifest_hash <- context_sha256_file(file.path(source_checkpoint, "completion_manifest.csv"))
predictions_path <- file.path(source_checkpoint, "shot_predictions.parquet")
expected_prediction_hash <- source_manifest$sha256[source_manifest$artifact == "shot_predictions.parquet"]
if (length(expected_prediction_hash) != 1L || context_sha256_file(predictions_path) != expected_prediction_hash) {
  stop("private prediction checkpoint hash mismatch", call. = FALSE)
}

predictions <- read_parquet(
  predictions_path,
  col_select = c("game_id", "outcome", "probability_m0", "probability_m1"),
  as_data_frame = TRUE
)
if (nrow(predictions) != 218700L || anyNA(predictions) || any(!predictions$outcome %in% c(0L, 1L))) {
  stop("private prediction checkpoint is invalid", call. = FALSE)
}
auc <- c(
  M0 = context_auc(predictions$outcome, predictions$probability_m0),
  M1 = context_auc(predictions$outcome, predictions$probability_m1)
)
if (any(!is.finite(auc)) || any(auc < 0 | auc > 1)) stop("recovered AUC remains invalid", call. = FALSE)

public_names <- c(
  "execution_manifest.csv", "fit_diagnostics.csv", "pooled_metrics.csv",
  "season_metrics.csv", "calibration_bins.csv", "subgroup_calibration.csv",
  "bootstrap_summary.csv", "model_selection.csv", "execution_checks.csv"
)
payloads <- setNames(lapply(public_names, function(name) {
  read_csv(file.path(source_checkpoint, name), show_col_types = FALSE)
}), public_names)

update_auc <- function(data) {
  data$value[data$metric_id == "roc_auc" & data$model_id == "M0"] <- auc[["M0"]]
  data$value[data$metric_id == "roc_auc" & data$model_id == "M1"] <- auc[["M1"]]
  data$value[data$metric_id == "roc_auc" & data$model_id == "M1_minus_M0"] <- auc[["M1"]] - auc[["M0"]]
  data
}
payloads[["pooled_metrics.csv"]] <- update_auc(payloads[["pooled_metrics.csv"]])
payloads[["season_metrics.csv"]] <- update_auc(payloads[["season_metrics.csv"]])

game_counts <- predictions |>
  count(game_id, name = "shots")
payloads[["execution_manifest.csv"]] <- payloads[["execution_manifest.csv"]] |>
  mutate(
    warning_count = 2L,
    error_count = 0L,
    recovery_version = "context_first_validation_auc_recovery_v0.1.1",
    recovery_from_private_checkpoint = TRUE,
    source_outcome_reads_total = 1L,
    recovery_source_outcome_reads = 0L,
    validation_game_shots_minimum = min(game_counts$shots),
    validation_game_shots_median = stats::median(game_counts$shots),
    validation_game_shots_maximum = max(game_counts$shots),
    recovered_m0_auc = auc[["M0"]],
    recovered_m1_auc = auc[["M1"]]
  )
payloads[["execution_checks.csv"]] <- bind_rows(
  payloads[["execution_checks.csv"]],
  tibble(
    check_id = c(
      "auc_values_finite", "recovery_checkpoint_hashes", "source_outcome_not_reopened",
      "original_atomic_result_preserved", "numerical_fix_did_not_change_frozen_metrics"
    ),
    passed = TRUE,
    detail = c(
      "M0 and M1 rank AUC are finite and within zero to one",
      "source private prediction and completion hashes matched",
      "recovery read only the ignored prediction checkpoint; canonical source outcome reads remain one",
      "original public tables remain byte-for-byte inside the original private checkpoint and dated archive",
      "double-precision denominator fixes integer overflow only; log loss, expected points, calibration, and bootstrap are unchanged"
    )
  )
)

stage_id <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
public_stage <- file.path(dirname(tracked_results), paste0(".results-auc-recovery-", stage_id, ".partial"))
private_stage <- paste0(recovery_checkpoint, ".partial")
dir.create(public_stage, recursive = TRUE)
dir.create(private_stage, recursive = TRUE)
walk2(payloads, names(payloads), function(data, name) {
  context_write_csv_stable(data, file.path(public_stage, name))
  context_write_csv_stable(data, file.path(private_stage, name))
})
corrected_manifest <- tibble(
  artifact = names(payloads),
  sha256 = vapply(file.path(public_stage, names(payloads)), context_sha256_file, character(1)),
  atomic_complete = TRUE,
  checks_passed = TRUE
) |>
  arrange(artifact)
context_write_csv_stable(corrected_manifest, file.path(public_stage, "artifact_manifest.csv"))
context_write_csv_stable(corrected_manifest, file.path(private_stage, "artifact_manifest.csv"))

recovery_record <- tibble(
  recovery_version = "context_first_validation_auc_recovery_v0.1.1",
  source_checkpoint_manifest_sha256 = source_manifest_hash,
  source_prediction_sha256 = expected_prediction_hash,
  source_outcome_reads_before_recovery = 1L,
  source_outcome_reads_during_recovery = 0L,
  models_refit = 0L,
  original_primary_and_secondary_metrics_changed = FALSE,
  diagnostic_corrected = "roc_auc",
  cause = "integer multiplication overflow in the rank-AUC denominator",
  correction = "cast positive and negative outcome counts to double precision before multiplication",
  m0_auc = auc[["M0"]],
  m1_auc = auc[["M1"]],
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
context_write_csv_stable(recovery_record, file.path(private_stage, "recovery_record.csv"))
private_names <- c(names(payloads), "artifact_manifest.csv", "recovery_record.csv")
recovery_manifest <- tibble(
  artifact = private_names,
  sha256 = vapply(file.path(private_stage, private_names), context_sha256_file, character(1)),
  atomic_complete = TRUE,
  checks_passed = TRUE
)
context_write_csv_stable(recovery_manifest, file.path(private_stage, "completion_manifest.csv"))
context_verify_file_manifest(recovery_manifest, private_stage)

archive_stage <- paste0(archive_root, ".partial")
dir.create(archive_stage, recursive = TRUE)
archived_results <- file.path(archive_stage, "original_tracked_results")
if (!file.rename(tracked_results, archived_results)) stop("could not archive original tracked result", call. = FALSE)
archived_files <- list.files(archived_results, full.names = TRUE, recursive = TRUE)
relative_paths <- file.path("original_tracked_results", basename(archived_files))
hashes_after <- vapply(archived_files, context_sha256_file, character(1))
hashes_before <- original_public_manifest$sha256[match(basename(archived_files), original_public_manifest$artifact)]
manifest_row <- basename(archived_files) == "artifact_manifest.csv"
hashes_before[manifest_row] <- context_sha256_file(file.path(archived_results, "artifact_manifest.csv"))
if (anyNA(hashes_before) || !identical(unname(hashes_before), unname(hashes_after))) {
  stop("original tracked result changed during archival", call. = FALSE)
}
writeLines(c(
  "status=preserved_invalid_diagnostic_output",
  "statistical_fit_failed=false",
  "primary_or_secondary_metric_failed=false",
  "warning_1=NAs produced by integer overflow",
  "warning_2=NAs produced by integer overflow",
  "source_outcome_reads=1",
  "models_refit=0",
  paste0("source_checkpoint_manifest_sha256=", source_manifest_hash)
), file.path(archive_stage, "recovery_evidence.txt"))
archive_manifest <- tibble(
  original_path = file.path("data/processed/context_edition_first_validation_v0_1/results", basename(archived_files)),
  archived_path = relative_paths,
  bytes = file.info(archived_files)$size,
  sha256_before = unname(hashes_before),
  sha256_after = unname(hashes_after)
)
context_write_csv_stable(archive_manifest, file.path(archive_stage, "archive_manifest.csv"))

if (!file.rename(private_stage, recovery_checkpoint)) stop("could not publish recovery checkpoint", call. = FALSE)
if (!file.rename(public_stage, tracked_results)) stop("could not publish corrected aggregate result", call. = FALSE)
if (!file.rename(archive_stage, archive_root)) stop("could not publish original-result archive", call. = FALSE)
message("Recovered finite AUC diagnostics from verified predictions; no source outcome was reread and no model was refit")
