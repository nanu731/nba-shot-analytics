# Copies the finished JSON export into the website repository, which is a separate git
# repo. This script only copies. Committing on the website side stays manual, so a bad
# export never lands in the site's history without someone looking at it.
#
#   Rscript R/06_sync_to_site.R

library(glue)

# The destination is read from the environment so the path is not baked into a script that
# has to run on other machines. This is the documented default for the author's laptop.
DEFAULT_SITE_DIR <- "/Users/narayanlekhi/projects/portfolio-site/public/data/shot-selection/"
SITE_DIR_VAR     <- "SHOT_SELECTION_SITE_DIR"

sync_to_site <- function(dest = Sys.getenv(SITE_DIR_VAR, DEFAULT_SITE_DIR),
                         src = "export/data") {
  files <- list.files(src, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0) {
    stop(glue("no JSON in {src}. Run R/05_export_json.R first."), call. = FALSE)
  }

  # Deliberately does not create the directory. A typo in the environment variable would
  # otherwise silently produce a new folder that nothing serves, and the copy would look
  # like it succeeded.
  if (!dir.exists(dest)) {
    stop(glue(
      "destination does not exist: {dest}\n",
      "  This script will not create it. Either the website repository is not checked out ",
      "at that path, or {SITE_DIR_VAR} is set wrong.\n",
      "  Set it with: export {SITE_DIR_VAR}=/path/to/site/public/data/shot-selection"
    ), call. = FALSE)
  }

  cat(glue("syncing {length(files)} files"), "\n")
  cat(glue("  from {normalizePath(src)}"), "\n")
  cat(glue("  to   {normalizePath(dest)}"), "\n\n")

  ok <- file.copy(files, dest, overwrite = TRUE)
  if (!all(ok)) {
    stop(glue("copy failed for: {paste(basename(files[!ok]), collapse = ', ')}"), call. = FALSE)
  }

  written <- file.path(dest, basename(files))
  for (f in written) {
    cat(glue("  {basename(f)}  {round(file.size(f) / 1024, 1)} KB"), "\n")
  }
  cat(glue("\n  {round(sum(file.size(written)) / 1024^2, 2)} MB written. ",
           "Commit on the website side manually."), "\n")

  invisible(written)
}

if (sys.nframe() == 0L) sync_to_site()
