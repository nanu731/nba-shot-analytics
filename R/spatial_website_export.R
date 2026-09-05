# Deterministic website export of verified spatial shot-selection results.
#
# Audit mode is read-only. Run mode writes only the versioned static JSON bundle
# and an ignored atomic completion marker. It cannot fit a model or regenerate
# posterior draws.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript R/spatial_website_export.R <season> <audit|run>", call. = FALSE)
}
season <- args[[1]]
mode <- args[[2]]
if (!identical(season, "2025-26")) stop("Only 2025-26 is frozen", call. = FALSE)
if (!mode %in% c("audit", "run")) stop("Mode must be audit or run", call. = FALSE)

SCHEMA_VERSION <- "1.0.0"
DATA_VERSION <- "2025-26-v1"
EXPORT_METHOD_ID <- "spatial-website-export-v1"
MODEL_METHOD_ID <- "frozen-car-production-all-folds-grid40-v1"
RELOCATION_METHOD_ID <- "car-proportional-relocation-v1"
SCORE_METHOD_ID <- "self-relative-shot-selection-score-25pct-v1"
EXPECTED_PLAYERS <- 318L
EXPECTED_QUALIFIED <- 122L
EXPECTED_INSUFFICIENT <- 196L
CELLS_PER_PLAYER <- 156L
EXPECTED_LATTICE_ROWS <- 49608L
SLIDERS <- c(0, 0.05, 0.10, 0.15, 0.20, 0.25)
TOLERANCE <- 1e-12
MAX_FILE_BYTES <- 90 * 1024^2
MAX_BUNDLE_BYTES <- 50 * 1024^2

PRODUCTION_RESULT_COMMIT <- "16a55dcc13f84279ccf9841c4bcc44c4e910333b"
RELOCATION_RESULT_COMMIT <- "d0844a93ed1e0231303ae52c81a133931b09442b"
SCORE_RESULT_COMMIT <- "4cf4c070f4edfe70587f36eb5033053b79ea728b"

EXPECTED_HASHES <- c(
  production_fit = "a8d1cfd71bee21a075b7d1e5848d91544b0bce9230d8c8ef6c246520ce3819c0",
  production_completion = "c2d6c92b36981feaf5870a58fb7eca84eff399ddd7ed1c7ed39d649c932f923c",
  production_manifest = "ccf887be231989019eacb93601beb5de74c5aeaa1c4ba52b3365a6bb71748c89",
  production_surface = "a08c060fd2008c3b062cd0d8bc0bfec12aba0806486d16656e0ac44023fd457f",
  relocation_completion = "e06f32b9da196feb9692b66c7c821a0bbaa3aa38d3927990c7afda3c6fc045d4",
  relocation_manifest = "664235d9f14287f07e1043a81130f0a327fc9533b39e7939e5c930122bb338a8",
  relocation_cells = "aa30d46ee54e4a9c3dce0594aeb66dac46fa5b8b833a9770f577b5b2c070832d",
  relocation_evidence = "7c4dda82739043e731c0fad34d7ae4182c758c090b1f5a51d9647ed07675b2c2",
  relocation_sliders = "0418f1241158e91d9ac48b18244d75838b3badf43664e30d7151ef418848aff4",
  score_completion = "1357a9161ee8953aa712964840c5ec80dfbcf9d68fdfa26d65a79e46ed68e6ad",
  score_manifest = "5733708e353e42e18c6339553e31ac0315b90d6da1f52382e95f4a227a59672a",
  score_table = "dcf181e5d14de57262a7a3bc70684fb525ba2ff441aee165a537fbe3720e582b"
)

production_cache <- file.path("data", "cache", "spatial_car_production", paste0("season=", season))
production_result <- file.path("data", "processed", "spatial_car_production", paste0("season=", season))
relocation_cache <- file.path("data", "cache", "spatial_relocation", paste0("season=", season))
relocation_result <- file.path("data", "processed", "spatial_relocation", paste0("season=", season))
score_cache <- file.path("data", "cache", "spatial_shot_selection_score", paste0("season=", season))
score_result <- file.path("data", "processed", "spatial_shot_selection_score", paste0("season=", season))
export_parent <- file.path("export", "spatial-shot-selection")
bundle_dir <- file.path(export_parent, "v1")
export_cache <- file.path("data", "cache", "spatial_website_export", paste0("season=", season))
completion_path <- file.path(export_cache, "website_export_complete.rds")
lock_path <- file.path(export_cache, "active_run.lock")

source_paths <- c(
  production_fit = file.path(production_cache, "car_production_fit.rds"),
  production_completion = file.path(production_cache, "production_complete_checkpoint.rds"),
  production_manifest = file.path(production_result, "production_manifest.parquet"),
  production_surface = file.path(production_cache, "player_probability_surfaces.parquet"),
  relocation_completion = file.path(relocation_cache, "relocation_complete.rds"),
  relocation_manifest = file.path(relocation_result, "relocation_manifest.parquet"),
  relocation_cells = file.path(relocation_result, "player_cell_support.parquet"),
  relocation_evidence = file.path(relocation_result, "player_evidence.parquet"),
  relocation_sliders = file.path(relocation_result, "slider_results.parquet"),
  score_completion = file.path(score_cache, "score_complete.rds"),
  score_manifest = file.path(score_result, "score_manifest.parquet"),
  score_table = file.path(score_result, "shot_selection_scores.parquet")
)

sha256_file <- function(path) {
  output <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  if (length(output) != 1L) stop("Could not hash ", path, call. = FALSE)
  strsplit(output, "[[:space:]]+")[[1]][[1]]
}

git_value <- function(arguments) {
  output <- system2("git", arguments, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop("Git verification failed: ", paste(output, collapse = " | "), call. = FALSE)
  }
  output
}

assert <- function(condition, message) {
  if (!isTRUE(condition)) stop("EXPORT CHECK FAILED: ", message, call. = FALSE)
  invisible(TRUE)
}

numeric_equal <- function(actual, expected) {
  same_missing <- is.na(actual) == is.na(expected)
  all(same_missing) && all(abs(actual[!is.na(actual)] - expected[!is.na(expected)]) <= TOLERANCE)
}

json_scalar <- function(value) {
  if (length(value) != 1L || is.na(value)) return(NA_real_)
  as.numeric(value)
}

write_json_file <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(value, path, auto_unbox = TRUE, na = "null", null = "null",
             pretty = FALSE, digits = 16)
}

verify_source_artifacts <- function() {
  assert(all(file.exists(source_paths)), "one or more frozen source artifacts are missing")
  actual <- vapply(source_paths, sha256_file, character(1))
  assert(identical(actual[names(EXPECTED_HASHES)], EXPECTED_HASHES), "a frozen source hash changed")
  commits <- c(PRODUCTION_RESULT_COMMIT, RELOCATION_RESULT_COMMIT, SCORE_RESULT_COMMIT)
  ancestor <- vapply(commits, function(commit) {
    system2("git", c("merge-base", "--is-ancestor", commit, "HEAD")) == 0L
  }, logical(1))
  assert(all(ancestor), "a required result commit is not in HEAD history")

  production_complete <- readRDS(source_paths[["production_completion"]])
  relocation_complete <- readRDS(source_paths[["relocation_completion"]])
  score_complete <- readRDS(source_paths[["score_completion"]])
  assert(isTRUE(production_complete$complete) && all(production_complete$checks$passed), "production completion failed")
  assert(isTRUE(relocation_complete$complete) && all(relocation_complete$checks$passed), "relocation completion failed")
  assert(isTRUE(score_complete$complete) && all(score_complete$checks$passed), "score completion failed")
  assert(identical(production_complete$player_count, EXPECTED_PLAYERS), "production player count changed")
  assert(identical(production_complete$lattice_rows, EXPECTED_LATTICE_ROWS), "production lattice count changed")
  assert(identical(relocation_complete$supported_player_count, EXPECTED_QUALIFIED), "qualified count changed")
  assert(identical(score_complete$qualified_player_count, EXPECTED_QUALIFIED), "score qualified count changed")
  actual
}

load_sources <- function() {
  list(
    surface = as.data.frame(read_parquet(source_paths[["production_surface"]])),
    cells = as.data.frame(read_parquet(source_paths[["relocation_cells"]])),
    evidence = as.data.frame(read_parquet(source_paths[["relocation_evidence"]])),
    sliders = as.data.frame(read_parquet(source_paths[["relocation_sliders"]])),
    scores = as.data.frame(read_parquet(source_paths[["score_table"]]))
  )
}

verify_source_tables <- function(x) {
  ids <- sort(unique(x$surface$PLAYER_ID))
  assert(length(ids) == EXPECTED_PLAYERS, "surface must contain 318 players")
  assert(nrow(x$surface) == EXPECTED_LATTICE_ROWS, "surface row count changed")
  assert(nrow(x$cells) == EXPECTED_LATTICE_ROWS, "cell-support row count changed")
  assert(nrow(x$sliders) == EXPECTED_PLAYERS * length(SLIDERS), "slider row count changed")
  assert(nrow(x$evidence) == EXPECTED_PLAYERS && nrow(x$scores) == EXPECTED_PLAYERS, "player table count changed")
  for (table in x) assert(setequal(unique(table$PLAYER_ID), ids), "player IDs differ between source tables")
  surface_key <- paste(x$surface$PLAYER_ID, x$surface$cell_id)
  cell_key <- paste(x$cells$PLAYER_ID, x$cells$cell_id)
  assert(!anyDuplicated(surface_key) && !anyDuplicated(cell_key) && setequal(surface_key, cell_key), "cell keys differ")
  slider_key <- paste(x$sliders$PLAYER_ID, x$sliders$slider_fraction)
  assert(!anyDuplicated(slider_key), "slider keys are duplicated")
  assert(setequal(unique(x$sliders$slider_fraction), SLIDERS), "slider values changed")
  assert(all(table(x$surface$PLAYER_ID) == CELLS_PER_PLAYER), "every surface must have 156 cells")
  assert(all(table(x$sliders$PLAYER_ID) == length(SLIDERS)), "every player must have six sliders")
  assert(sum(x$scores$evidence_status == "qualified") == EXPECTED_QUALIFIED, "qualified score count changed")
  assert(sum(x$scores$evidence_status == "insufficient_evidence") == EXPECTED_INSUFFICIENT, "insufficient score count changed")
  assert(all(is.finite(x$surface$probability)) && all(x$surface$probability >= 0 & x$surface$probability <= 1), "surface probabilities are invalid")
  assert(all(is.finite(x$surface$probability_lower_90)) && all(is.finite(x$surface$probability_median)) && all(is.finite(x$surface$probability_upper_90)), "surface intervals are invalid")
  assert(all(x$surface$probability_lower_90 <= x$surface$probability_median & x$surface$probability_median <= x$surface$probability_upper_90), "surface intervals are unordered")
  assert(!anyDuplicated(x$evidence$PLAYER_ID) && !anyDuplicated(x$scores$PLAYER_ID), "player rows are duplicated")
  invisible(ids)
}

normalize_status <- function(value) {
  ifelse(value == "estimated", "qualified",
         ifelse(value == "insufficient_supported_destinations", "insufficient_evidence", NA_character_))
}

cell_bounds <- function(cell_id) {
  x_index <- ((cell_id - 1L) %% 13L) + 1L
  y_index <- ((cell_id - 1L) %/% 13L) + 1L
  data.frame(
    x_min_ft = (-250 + (x_index - 1L) * 40) / 10,
    x_max_ft = pmin(-250 + x_index * 40, 250) / 10,
    y_min_ft = (-52.5 + (y_index - 1L) * 40) / 10,
    y_max_ft = pmin(-52.5 + y_index * 40, 397.5) / 10
  )
}

make_index_entry <- function(score_row) {
  qualified <- identical(score_row$evidence_status[[1]], "qualified")
  list(
    player_id = as.character(score_row$PLAYER_ID[[1]]),
    player_name = score_row$PLAYER_NAME[[1]],
    player_file = file.path("players", paste0(score_row$PLAYER_ID[[1]], ".json")),
    evidence_status = score_row$evidence_status[[1]],
    score_available = qualified,
    shot_selection_score = if (qualified) score_row$display_score[[1]] else NA_real_,
    score_lower_90 = if (qualified) score_row$display_score_lower_90[[1]] else NA_real_,
    score_upper_90 = if (qualified) score_row$display_score_upper_90[[1]] else NA_real_
  )
}

make_player_object <- function(player_id, x) {
  surface <- x$surface[x$surface$PLAYER_ID == player_id, , drop = FALSE]
  cells <- x$cells[x$cells$PLAYER_ID == player_id, , drop = FALSE]
  sliders <- x$sliders[x$sliders$PLAYER_ID == player_id, , drop = FALSE]
  evidence <- x$evidence[x$evidence$PLAYER_ID == player_id, , drop = FALSE]
  score <- x$scores[x$scores$PLAYER_ID == player_id, , drop = FALSE]
  surface <- surface[order(surface$cell_id), , drop = FALSE]
  cells <- cells[match(surface$cell_id, cells$cell_id), , drop = FALSE]
  sliders <- sliders[order(sliders$slider_fraction), , drop = FALSE]
  qualified <- identical(score$evidence_status[[1]], "qualified")
  assert(identical(normalize_status(evidence$evidence_status), score$evidence_status), "evidence status mismatch")
  bounds <- cell_bounds(surface$cell_id)

  slider_objects <- lapply(seq_len(nrow(sliders)), function(i) {
    row <- sliders[i, , drop = FALSE]
    list(
      relocated_share = row$slider_fraction[[1]],
      posterior_mean_season_point_gain = if (qualified) row$additional_season_points[[1]] else NA_real_,
      season_point_gain_lower_90 = if (qualified) row$additional_season_points_lower_90[[1]] else NA_real_,
      season_point_gain_upper_90 = if (qualified) row$additional_season_points_upper_90[[1]] else NA_real_,
      posterior_mean_gain_per_100_shots = if (qualified) row$additional_points_per_100_shots[[1]] else NA_real_,
      gain_per_100_shots_lower_90 = if (qualified) row$additional_points_per_100_shots_lower_90[[1]] else NA_real_,
      gain_per_100_shots_upper_90 = if (qualified) row$additional_points_per_100_shots_upper_90[[1]] else NA_real_
    )
  })

  cell_objects <- lapply(seq_len(nrow(surface)), function(i) {
    list(
      cell_id = as.integer(surface$cell_id[[i]]),
      center_x_ft = surface$x_ft[[i]],
      center_y_ft = surface$y_ft[[i]],
      x_min_ft = bounds$x_min_ft[[i]],
      x_max_ft = bounds$x_max_ft[[i]],
      y_min_ft = bounds$y_min_ft[[i]],
      y_max_ft = bounds$y_max_ft[[i]],
      modeled_make_probability = surface$probability[[i]],
      make_probability_lower_90 = surface$probability_lower_90[[i]],
      make_probability_median = surface$probability_median[[i]],
      make_probability_upper_90 = surface$probability_upper_90[[i]],
      observed_attempts = as.integer(surface$attempts[[i]]),
      effective_point_value = json_scalar(cells$point_value[[i]]),
      supported_destination = isTRUE(cells$supported_destination[[i]])
    )
  })

  list(
    schema_version = SCHEMA_VERSION,
    data_version = DATA_VERSION,
    player_id = as.character(player_id),
    player_name = score$PLAYER_NAME[[1]],
    season = season,
    methods = list(model = MODEL_METHOD_ID, relocation = RELOCATION_METHOD_ID,
                   score = SCORE_METHOD_ID, export = EXPORT_METHOD_ID),
    evidence_status = score$evidence_status[[1]],
    relocation_available = qualified,
    score_available = qualified,
    observed_attempts = as.integer(evidence$attempts[[1]]),
    posterior_mean_baseline_expected_points_per_shot = sliders$baseline_expected_points_per_shot[[1]],
    score = list(
      point_estimate_convention = "median_of_draw_level_scores",
      shot_selection_score = if (qualified) score$display_score[[1]] else NA_real_,
      score_lower_90 = if (qualified) score$display_score_lower_90[[1]] else NA_real_,
      score_upper_90 = if (qualified) score$display_score_upper_90[[1]] else NA_real_
    ),
    sliders = slider_objects,
    heatmap_cells = cell_objects
  )
}

inventory_for <- function(root, relative_paths) {
  lapply(relative_paths, function(relative_path) {
    path <- file.path(root, relative_path)
    list(path = relative_path, bytes = unname(file.info(path)$size), sha256 = sha256_file(path))
  })
}

make_manifest <- function(source_hashes, pre_export_commit, payload_inventory) {
  list(
    schema_version = SCHEMA_VERSION,
    data_version = DATA_VERSION,
    season = season,
    export_method = EXPORT_METHOD_ID,
    pre_export_commit = pre_export_commit,
    source_commits = list(production = PRODUCTION_RESULT_COMMIT,
                          relocation = RELOCATION_RESULT_COMMIT,
                          score = SCORE_RESULT_COMMIT),
    source_sha256 = as.list(source_hashes),
    counts = list(players = EXPECTED_PLAYERS, qualified = EXPECTED_QUALIFIED,
                  insufficient_evidence = EXPECTED_INSUFFICIENT,
                  cells_per_player = CELLS_PER_PLAYER,
                  sliders_per_player = length(SLIDERS)),
    court = list(
      coordinate_units = "feet",
      basket_center = list(x = 0, y = 0),
      orientation = "x spans -25 to 25; y increases from the baseline-side edge toward half court",
      bounds = list(x_min = -25, x_max = 25, y_min = -5.25, y_max = 39.75),
      grid = list(nominal_cell_width_ft = 4, columns = 13L, rows = 12L,
                  cells = CELLS_PER_PLAYER, edge_cells = "clipped to court bounds")
    ),
    sliders = list(values = as.list(SLIDERS),
                   meaning = "maximum share of attempts proportionally relocated among supported destinations"),
    summary_conventions = list(
      relocation_gain = "posterior mean with existing 5th and 95th percentile interval bounds",
      score = "median of draw-level 25-percent-relocation scores with 5th and 95th percentile bounds"
    ),
    score_meaning = "self-relative room to improve under the frozen 25-percent relocation scenario; not a rank, grade, or overall quality measure",
    insufficient_evidence = "fewer than two destinations passed the frozen attempt and posterior-certainty rules; score and gain fields are null",
    disclaimer = "Modeled relocation gains are non-causal and do not account for shot creation, defense, fatigue, or game context.",
    loading = list(index = "players.json", player_file_pattern = "players/{player_id}.json"),
    payload_inventory_note = "Hashes cover players.json and 318 player files; the manifest cannot hash itself.",
    payload_files = payload_inventory
  )
}

build_bundle <- function(root, x, source_hashes, pre_export_commit) {
  dir.create(file.path(root, "players"), recursive = TRUE, showWarnings = FALSE)
  ids <- sort(unique(x$scores$PLAYER_ID))
  score_ordered <- x$scores[match(ids, x$scores$PLAYER_ID), , drop = FALSE]
  index_entries <- lapply(seq_len(nrow(score_ordered)), function(i) make_index_entry(score_ordered[i, , drop = FALSE]))
  index_object <- list(schema_version = SCHEMA_VERSION, data_version = DATA_VERSION,
                       season = season, players = index_entries)
  write_json_file(index_object, file.path(root, "players.json"))
  for (player_id in ids) {
    write_json_file(make_player_object(player_id, x), file.path(root, "players", paste0(player_id, ".json")))
  }
  payload_paths <- c("players.json", file.path("players", paste0(ids, ".json")))
  manifest <- make_manifest(source_hashes, pre_export_commit, inventory_for(root, payload_paths))
  write_json_file(manifest, file.path(root, "manifest.json"))
  invisible(c("manifest.json", payload_paths))
}

validate_bundle <- function(root, x) {
  files <- sort(list.files(root, recursive = TRUE, all.files = FALSE))
  assert(length(files) == EXPECTED_PLAYERS + 2L, "bundle must contain 320 JSON files")
  assert(all(tools::file_ext(files) == "json"), "bundle contains a non-JSON file")
  sizes <- file.info(file.path(root, files))$size
  assert(all(sizes < MAX_FILE_BYTES), "an export file reached the 90 MiB stop threshold")
  assert(sum(sizes) < MAX_BUNDLE_BYTES, "the bundle reached the 50 MiB stop threshold")
  parsed <- lapply(file.path(root, files), fromJSON, simplifyVector = FALSE)
  names(parsed) <- files
  index <- fromJSON(file.path(root, "players.json"), simplifyVector = TRUE)
  assert(nrow(index$players) == EXPECTED_PLAYERS, "player index count changed")
  assert(length(unique(index$players$player_id)) == EXPECTED_PLAYERS, "index player IDs are duplicated")
  assert(all(file.exists(file.path(root, index$players$player_file))), "an index path does not resolve")

  qualified <- 0L
  insufficient <- 0L
  for (i in seq_len(nrow(index$players))) {
    entry <- index$players[i, , drop = FALSE]
    player_id <- as.numeric(entry$player_id[[1]])
    object <- fromJSON(file.path(root, entry$player_file[[1]]), simplifyVector = TRUE)
    surface <- x$surface[x$surface$PLAYER_ID == player_id, , drop = FALSE]
    surface <- surface[order(surface$cell_id), , drop = FALSE]
    cells <- x$cells[x$cells$PLAYER_ID == player_id, , drop = FALSE]
    cells <- cells[match(surface$cell_id, cells$cell_id), , drop = FALSE]
    sliders <- x$sliders[x$sliders$PLAYER_ID == player_id, , drop = FALSE]
    sliders <- sliders[order(sliders$slider_fraction), , drop = FALSE]
    score <- x$scores[x$scores$PLAYER_ID == player_id, , drop = FALSE]
    assert(nrow(object$heatmap_cells) == CELLS_PER_PLAYER && !anyDuplicated(object$heatmap_cells$cell_id), "player heatmap is incomplete")
    assert(nrow(object$sliders) == length(SLIDERS), "player slider set is incomplete")
    assert(numeric_equal(object$heatmap_cells$modeled_make_probability, surface$probability), "exported probability changed")
    assert(numeric_equal(object$heatmap_cells$make_probability_lower_90, surface$probability_lower_90), "exported probability lower bound changed")
    assert(numeric_equal(object$heatmap_cells$make_probability_median, surface$probability_median), "exported probability median changed")
    assert(numeric_equal(object$heatmap_cells$make_probability_upper_90, surface$probability_upper_90), "exported probability upper bound changed")
    assert(identical(as.integer(object$heatmap_cells$observed_attempts), as.integer(surface$attempts)), "exported cell attempts changed")
    assert(numeric_equal(object$heatmap_cells$effective_point_value, cells$point_value), "exported point value changed")
    assert(identical(object$heatmap_cells$supported_destination, as.logical(cells$supported_destination)), "exported support status changed")
    assert(numeric_equal(object$posterior_mean_baseline_expected_points_per_shot, sliders$baseline_expected_points_per_shot[[1]]), "baseline expected points changed")
    assert(numeric_equal(object$sliders$relocated_share, sliders$slider_fraction), "slider values changed")

    if (identical(score$evidence_status[[1]], "qualified")) {
      qualified <- qualified + 1L
      assert(numeric_equal(object$score$shot_selection_score, score$display_score), "score changed")
      assert(numeric_equal(object$score$score_lower_90, score$display_score_lower_90), "score lower bound changed")
      assert(numeric_equal(object$score$score_upper_90, score$display_score_upper_90), "score upper bound changed")
      assert(numeric_equal(object$sliders$posterior_mean_season_point_gain, sliders$additional_season_points), "season gains changed")
      assert(numeric_equal(object$sliders$season_point_gain_lower_90, sliders$additional_season_points_lower_90), "season gain lower bounds changed")
      assert(numeric_equal(object$sliders$season_point_gain_upper_90, sliders$additional_season_points_upper_90), "season gain upper bounds changed")
      assert(numeric_equal(object$sliders$posterior_mean_gain_per_100_shots, sliders$additional_points_per_100_shots), "per-100 gains changed")
      assert(numeric_equal(object$sliders$gain_per_100_shots_lower_90, sliders$additional_points_per_100_shots_lower_90), "per-100 lower bounds changed")
      assert(numeric_equal(object$sliders$gain_per_100_shots_upper_90, sliders$additional_points_per_100_shots_upper_90), "per-100 upper bounds changed")
    } else {
      insufficient <- insufficient + 1L
      score_values <- unlist(object$score[c("shot_selection_score", "score_lower_90", "score_upper_90")], use.names = FALSE)
      gain_names <- c("posterior_mean_season_point_gain", "season_point_gain_lower_90", "season_point_gain_upper_90",
                      "posterior_mean_gain_per_100_shots", "gain_per_100_shots_lower_90", "gain_per_100_shots_upper_90")
      assert(all(is.na(score_values)) && all(is.na(unlist(object$sliders[gain_names], use.names = FALSE))), "insufficient-evidence values must be null")
    }
  }
  assert(qualified == EXPECTED_QUALIFIED && insufficient == EXPECTED_INSUFFICIENT, "eligibility totals changed")
  all_text <- paste(vapply(file.path(root, files), function(path) paste(readLines(path, warn = FALSE), collapse = ""), character(1)), collapse = "\n")
  forbidden <- c("median_season_point_gain", "median_gain_per_100", "GAME_ID", "game_id", "SHOT_ID", "shot_id",
                 "posterior_draws", "fit_object", "/Users/", "data/cache", "NaN", "Infinity")
  assert(!any(vapply(forbidden, grepl, logical(1), x = all_text, fixed = TRUE)), "forbidden content appears in JSON")
  list(files = files, sizes = sizes, hashes = setNames(vapply(file.path(root, files), sha256_file, character(1)), files))
}

source_hashes <- verify_source_artifacts()
x <- load_sources()
ids <- verify_source_tables(x)
cat("Verified source artifacts:", length(ids), "players,", nrow(x$surface), "surface rows,",
    nrow(x$sliders), "slider rows; fold outcomes and model fits were not loaded.\n")

if (identical(mode, "audit")) quit(save = "no", status = 0L)

head_commit <- git_value(c("rev-parse", "HEAD"))[[1]]
upstream_commit <- git_value(c("rev-parse", "@{upstream}"))[[1]]
assert(identical(head_commit, upstream_commit), "HEAD must match its upstream before export")
tracked_status <- git_value(c("status", "--porcelain", "--untracked-files=no"))
assert(length(tracked_status) == 0L, "tracked tree must be clean before export")
assert(!dir.exists(bundle_dir), "refusing to replace an existing versioned bundle")
assert(!file.exists(completion_path), "refusing to replace an existing completion marker")
assert(!dir.exists(lock_path), "another export lock exists")
lock_created <- dir.create(lock_path, recursive = TRUE, showWarnings = FALSE)
assert(lock_created && dir.exists(lock_path), "could not create the export lock")
on.exit({ if (dir.exists(lock_path)) unlink(lock_path, recursive = TRUE) }, add = TRUE)

dir.create(export_cache, recursive = TRUE, showWarnings = FALSE)
first <- tempfile("v1.partial-first-", export_cache)
second <- tempfile("v1.partial-second-", export_cache)
assert(dir.create(first, recursive = TRUE), "could not create the first staging directory")
assert(dir.create(second, recursive = TRUE), "could not create the second staging directory")
build_bundle(first, x, source_hashes, head_commit)
first_check <- validate_bundle(first, x)
build_bundle(second, x, source_hashes, head_commit)
second_check <- validate_bundle(second, x)
assert(identical(first_check$files, second_check$files), "regeneration changed the file list")
assert(identical(first_check$hashes, second_check$hashes), "regeneration was not byte-for-byte deterministic")
unlink(second, recursive = TRUE)
dir.create(export_parent, recursive = TRUE, showWarnings = FALSE)
assert(file.rename(first, bundle_dir), "atomic bundle publication failed; partial build preserved")
final_check <- validate_bundle(bundle_dir, x)
assert(identical(first_check$hashes, final_check$hashes), "published hashes changed")

completion <- list(
  complete = TRUE, schema_version = SCHEMA_VERSION, data_version = DATA_VERSION,
  export_method = EXPORT_METHOD_ID, pre_export_commit = head_commit,
  source_hashes = source_hashes, file_hashes = final_check$hashes,
  player_count = EXPECTED_PLAYERS, qualified_player_count = EXPECTED_QUALIFIED,
  insufficient_evidence_player_count = EXPECTED_INSUFFICIENT,
  cell_count = EXPECTED_LATTICE_ROWS,
  slider_count = EXPECTED_PLAYERS * length(SLIDERS),
  index_bytes = unname(file.info(file.path(bundle_dir, "players.json"))$size),
  total_bytes = sum(final_check$sizes),
  median_player_file_bytes = unname(median(final_check$sizes[grepl("^players/", names(final_check$sizes))])),
  largest_file = names(which.max(final_check$sizes)),
  largest_file_bytes = unname(max(final_check$sizes)),
  deterministic_regeneration = TRUE,
  reproduction_tolerance = TOLERANCE,
  package_versions = c(R = paste(R.version$major, R.version$minor, sep = "."),
                       arrow = as.character(packageVersion("arrow")),
                       dplyr = as.character(packageVersion("dplyr")),
                       jsonlite = as.character(packageVersion("jsonlite")))
)
pending <- tempfile("website_export_complete.pending-", export_cache, fileext = ".rds")
saveRDS(completion, pending)
assert(file.rename(pending, completion_path), "atomic completion publication failed")
cat("Published deterministic bundle at", bundle_dir, "with", length(final_check$files), "files and",
    completion$total_bytes, "bytes.\n")
