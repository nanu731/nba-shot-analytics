# Copies finished artifacts into the website repository, which is a separate git repo.
# This script only copies. Committing on the website side stays manual, so a bad export
# never lands in the site's history without someone looking at it.
#
#   Rscript R/06_sync_to_site.R
#
# Two destinations, because the site consumes the two kinds of file differently.
#
#   runtime  export/data/*.json          fetched by the browser at run time
#   build    export/reference/           imported by the build, so it belongs in src/
#
# Sending the zone outlines to public/ would work by accident and be wrong: the site
# imports them at build time to emit SVG paths, so they belong in the source tree where a
# build failure is visible rather than in a directory served to visitors.

library(glue)

# Destinations come from the environment so no path is baked into a script that has to run
# on other machines. These are the documented defaults for the author's laptop.
DEFAULT_RUNTIME_DIR <- "/Users/narayanlekhi/projects/portfolio-site/public/data/shot-selection/"
DEFAULT_BUILD_DIR   <- "/Users/narayanlekhi/projects/portfolio-site/src/data/shot-selection/"
RUNTIME_VAR <- "SHOT_SELECTION_SITE_DIR"
BUILD_VAR   <- "SHOT_SELECTION_SRC_DIR"

# Files that go to the build destination. Named rather than globbed: export/reference/ also
# holds zone_grid.csv and the checker's vertex-only file, which are development aids the
# site has no use for.
BUILD_FILES <- "export/reference/zone_polygons.json"

copy_into <- function(files, dest, var, label) {
  missing <- files[!file.exists(files)]
  if (length(missing)) {
    stop(glue("missing {label} source file(s): {paste(missing, collapse = ', ')}"), call. = FALSE)
  }

  # Deliberately does not create the directory. A typo in the environment variable would
  # otherwise silently produce a new folder that nothing serves or imports, and the copy
  # would look like it succeeded.
  if (!dir.exists(dest)) {
    stop(glue(
      "{label} destination does not exist: {dest}\n",
      "  This script will not create it. Either the website repository is not checked out ",
      "at that path, or {var} is set wrong.\n",
      "  Set it with: export {var}=/path/to/site/..."
    ), call. = FALSE)
  }

  ok <- file.copy(files, dest, overwrite = TRUE)
  if (!all(ok)) {
    stop(glue("copy failed for: {paste(basename(files[!ok]), collapse = ', ')}"), call. = FALSE)
  }

  written <- file.path(dest, basename(files))
  cat(glue("{label}: {length(written)} file(s) -> {normalizePath(dest)}"), "\n")
  for (f in written) cat(glue("  {basename(f)}  {round(file.size(f) / 1024, 1)} KB"), "\n")
  invisible(written)
}

sync_runtime <- function(dest = Sys.getenv(RUNTIME_VAR, DEFAULT_RUNTIME_DIR),
                         src = "export/data") {
  files <- list.files(src, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0) {
    stop(glue("no JSON in {src}. Run R/05_export_json.R first."), call. = FALSE)
  }
  copy_into(files, dest, RUNTIME_VAR, "runtime")
}

sync_build <- function(dest = Sys.getenv(BUILD_VAR, DEFAULT_BUILD_DIR),
                       files = BUILD_FILES) {
  copy_into(files, dest, BUILD_VAR, "build")
}

sync_to_site <- function() {
  written <- c(sync_runtime(), { cat("\n"); sync_build() })
  cat(glue("\n  {round(sum(file.size(written)) / 1024^2, 2)} MB written across ",
           "{length(written)} files. Commit on the website side manually."), "\n")
  invisible(written)
}

if (sys.nframe() == 0L) sync_to_site()
