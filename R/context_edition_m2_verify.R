#!/usr/bin/env Rscript

# Read-only verifier for the complete M2 preregistration. It does not load shot
# outcomes, write artifacts, or fit a model.

options(stringsAsFactors = FALSE)
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg) == 1L) sub("^--file=", "", script_arg) else "R/context_edition_m2_verify.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) stop("unable to hash ", path, call. = FALSE)
  sub("[[:space:]].*$", "", output)
}

manifest_path <- file.path(
  repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1",
  "artifact_manifest.csv"
)
if (!file.exists(manifest_path)) stop("M2 artifact manifest is missing", call. = FALSE)
manifest <- utils::read.csv(manifest_path, check.names = FALSE)
required <- c("protocol_version", "file", "bytes", "sha256", "contains_shot_level_rows", "artifact_role")
if (!identical(names(manifest), required)) stop("M2 artifact manifest schema changed", call. = FALSE)
if (anyDuplicated(manifest$file)) stop("M2 artifact manifest contains duplicate paths", call. = FALSE)
if (any(manifest$protocol_version != "context_m2_protocol_v0.1.0")) stop("protocol version mismatch", call. = FALSE)
if (any(manifest$contains_shot_level_rows)) stop("manifest declares a shot-level artifact", call. = FALSE)

paths <- file.path(repo_root, manifest$file)
if (!all(file.exists(paths))) stop("a registered M2 artifact is missing", call. = FALSE)
actual_bytes <- as.numeric(file.info(paths)$size)
actual_hashes <- vapply(paths, sha256_file, character(1))
if (!identical(actual_bytes, as.numeric(manifest$bytes))) stop("M2 artifact byte size mismatch", call. = FALSE)
if (!identical(unname(actual_hashes), unname(manifest$sha256))) stop("M2 artifact SHA-256 mismatch", call. = FALSE)

canonical_root <- file.path(
  repo_root, "data", "cache", "context_edition_canonical",
  "context_field_goal_v0.1.2__2021-22_to_2025-26"
)
canonical_manifest <- utils::read.csv(file.path(canonical_root, "completion_manifest.csv"), check.names = FALSE)
partition_rows <- grepl("^season=202[1-5]-", canonical_manifest$artifact)
registered <- canonical_manifest[partition_rows, , drop = FALSE]
if (nrow(registered) != 5L || any(!registered$checks_passed) || any(!registered$atomic_complete)) {
  stop("five-season canonical completion registration failed", call. = FALSE)
}
canonical_paths <- file.path(canonical_root, registered$artifact)
if (!all(file.exists(canonical_paths))) stop("a canonical partition is missing", call. = FALSE)
canonical_hashes <- vapply(canonical_paths, sha256_file, character(1))
if (!identical(unname(canonical_hashes), unname(registered$sha256))) stop("canonical partition hash mismatch", call. = FALSE)

m1_verify <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(file.path(repo_root, "R", "context_edition_third_validation.R"), "verify"),
  stdout = TRUE, stderr = TRUE
)
if (!is.null(attr(m1_verify, "status")) || !any(grepl("verified", m1_verify))) {
  stop("selected M1 result verification failed", call. = FALSE)
}

source(file.path(repo_root, "R", "context_edition_m2_protocol.R"), local = TRUE)
feature_matrix <- utils::read.csv(file.path(repo_root, "config", "context_edition_m2_feature_allowlist_v0_1.csv"), check.names = FALSE)
split_spec <- utils::read.csv(file.path(repo_root, "config", "context_edition_m2_development_plan_v0_1.csv"), check.names = FALSE)
context_m2_validate_feature_allowlist(feature_matrix)
context_m2_validate_split_spec(split_spec)

m2_code_paths <- file.path(
  repo_root, "R",
  c("context_edition_m2_protocol.R", "context_edition_m2_predictor_audit.R", "context_edition_m2_structural_tests.R", "context_edition_m2_verify.R")
)
invisible(lapply(m2_code_paths, parse))
m2_code <- paste(unlist(lapply(m2_code_paths, readLines, warn = FALSE)), collapse = "\n")
if (grepl("mgcv::(gam|bam)\\s*\\(", m2_code, perl = TRUE)) stop("a real model fit call entered M2 preregistration code", call. = FALSE)

audit <- utils::read.csv(
  file.path(repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1", "pre_registration_audit.csv"),
  check.names = FALSE
)
tests <- utils::read.csv(
  file.path(repo_root, "data", "processed", "context_edition_m2_preregistration_v0_1", "structural_test_results.csv"),
  check.names = FALSE
)
if (!all(audit$passed) || !all(tests$passed)) stop("aggregate M2 checks are not all passing", call. = FALSE)

message(
  "Verified ", nrow(manifest), " M2 preregistration artifacts, five canonical predictor partitions, ",
  nrow(tests), " structural tests, and the immutable M1 decision. No outcomes or models were opened."
)
