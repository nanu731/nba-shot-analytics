#!/usr/bin/env Rscript

# Generate a machine-local LaunchAgent plist without installing or starting it.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) == 1L && args[[1L]] %in% c("-h", "--help"))) {
  cat(
    "Usage: Rscript R/generate_spatial_exact_gam_launchagent.R [ABSOLUTE_OUTPUT_PATH]\n",
    "Generates and validates a local plist; it does not install or start a job.\n",
    sep = ""
  )
  quit(status = if (length(args) == 1L) 0L else 2L)
}

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) != 1L) {
  stop("Run this generator with Rscript so its repository path is unambiguous",
       call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
repository_path <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
template_path <- file.path(
  repository_path, "R", "com.narayanlekhi.nba-shot-analytics.exact-gam.plist.in"
)
runner_path <- file.path(repository_path, "R", "run_spatial_exact_gam_long.sh")
default_output <- file.path(
  repository_path, "data", "cache", "launchagents",
  "com.narayanlekhi.nba-shot-analytics.exact-gam.plist"
)
output_path <- if (length(args) == 1L) args[[1L]] else default_output

is_absolute <- startsWith(output_path, "/")
if (!is_absolute) stop("The generated plist path must be absolute", call. = FALSE)
if (file.exists(output_path)) {
  stop("Refusing to overwrite an existing generated plist", call. = FALSE)
}

required_files <- c(template_path, runner_path, "/usr/bin/caffeinate", "/usr/local/bin/Rscript", "/usr/bin/plutil")
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0L) {
  stop("Missing required path(s): ", paste(missing_files, collapse = ", "), call. = FALSE)
}
if (file.access(runner_path, mode = 1L) != 0L) {
  stop("The exact-GAM runner is not executable: ", runner_path, call. = FALSE)
}

xml_escape <- function(value) {
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  value <- gsub('"', "&quot;", value, fixed = TRUE)
  gsub("'", "&apos;", value, fixed = TRUE)
}

launchd_log_dir <- file.path(repository_path, "data", "cache", "launchagents", "logs")
exact_cache_dir <- file.path(
  repository_path, "data", "cache", "spatial_gam_exact_full_league_benchmark",
  "season=2025-26"
)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
dir.create(launchd_log_dir, recursive = TRUE, showWarnings = FALSE)

contents <- paste(readLines(template_path, warn = FALSE), collapse = "\n")
replacements <- c(
  "__RUNNER_PATH__" = xml_escape(runner_path),
  "__REPOSITORY_PATH__" = xml_escape(repository_path),
  "__LAUNCHD_STDOUT_PATH__" = xml_escape(file.path(launchd_log_dir, "launchd.stdout.log")),
  "__LAUNCHD_STDERR_PATH__" = xml_escape(file.path(launchd_log_dir, "launchd.stderr.log"))
)
for (placeholder in names(replacements)) {
  contents <- gsub(placeholder, replacements[[placeholder]], contents, fixed = TRUE)
}
if (grepl("__[A-Z0-9_]+__", contents)) {
  stop("The generated plist contains an unresolved placeholder", call. = FALSE)
}

temporary <- tempfile(pattern = "exact-gam-launchagent-", tmpdir = dirname(output_path))
on.exit(unlink(temporary), add = TRUE)
writeLines(contents, temporary, useBytes = TRUE)
lint_status <- system2("/usr/bin/plutil", c("-lint", temporary))
if (!identical(lint_status, 0L)) stop("Apple plist validation failed", call. = FALSE)
if (!file.rename(temporary, output_path)) {
  stop("Could not atomically publish the generated plist", call. = FALSE)
}

stale_paths <- c(
  file.path(exact_cache_dir, "active_run.lock"),
  file.path(
    repository_path, "data", "processed",
    "spatial_gam_exact_full_league_benchmark", "season=2025-26",
    "benchmark_failure.parquet"
  )
)
cat("Generated and validated: ", output_path, "\n", sep = "")
cat("The plist was not installed, loaded, or started.\n")
if (any(file.exists(stale_paths))) {
  cat(
    "Recovery warning: preserved interrupted-run artifacts will make the exact runner refuse a future start until they are reviewed.\n"
  )
}
