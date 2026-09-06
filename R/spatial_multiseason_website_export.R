suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

source(file.path("R", "spatial_targeted_relocation_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) == 1L) args[[1]] else "verify"
target_assert(mode %in% c("run", "verify"), "mode must be run or verify")

SEASONS <- c("2025-26", "2024-25", "2023-24", "2022-23", "2021-22")
V3_ROOT <- file.path("export", "spatial-shot-selection", "v3")
V4_ROOT <- file.path("export", "spatial-shot-selection", "v4")
CACHE_ROOT <- file.path("data", "cache", "spatial_multiseason_website_export")
COMPLETION_PATH <- file.path(CACHE_ROOT, "v4_complete.rds")
LOCK_PATH <- file.path(CACHE_ROOT, "v4_run.lock")
RAW_ROOT <- file.path("data", "raw", "shots")
MIN_GAMES <- 20L
MIN_ATTEMPTS <- 250L
CELLS_PER_PLAYER <- 156L

sha256_file <- function(path) {
  value <- system2("shasum", c("-a", "256", path), stdout = TRUE)
  target_assert(length(value) == 1L, paste("could not hash", path))
  strsplit(value, "[[:space:]]+")[[1]][[1]]
}

write_json_file <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(object, path, auto_unbox = TRUE, pretty = TRUE, digits = 15,
             na = "null")
}

copy_tree_exact <- function(source, target) {
  files <- sort(list.files(source, recursive = TRUE, all.files = FALSE))
  target_assert(length(files) > 0L, paste("empty source", source))
  for (relative in files) {
    destination <- file.path(target, relative)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    target_assert(file.copy(file.path(source, relative), destination,
                            overwrite = FALSE),
                  paste("could not copy", relative))
  }
  invisible(files)
}

bundle_files <- function(root) {
  sort(list.files(root, recursive = TRUE, all.files = FALSE))
}

bundle_hashes <- function(root) {
  files <- bundle_files(root)
  setNames(vapply(file.path(root, files), sha256_file, character(1)), files)
}

inventory_for <- function(root, relative_paths) {
  lapply(relative_paths, function(relative) {
    path <- file.path(root, relative)
    list(path = relative, bytes = unname(file.info(path)$size),
         sha256 = sha256_file(path))
  })
}

season_source <- function(season) {
  if (identical(season, "2025-26")) return(V3_ROOT)
  file.path(CACHE_ROOT, paste0("season=", season), "bundle")
}

read_season_index <- function(root, season) {
  fromJSON(file.path(root, "seasons", season, "players.json"),
           simplifyVector = FALSE)
}

season_metadata <- function(season, analyzed_entries) {
  path <- file.path(RAW_ROOT, paste0("season=", season), "shots.parquet")
  raw <- read_parquet(
    path, col_select = c("GAME_ID", "PLAYER_ID", "PLAYER_NAME", "LOC_Y")
  ) |>
    as_tibble()
  recorded <- raw |>
    summarise(
      player_name = first(PLAYER_NAME),
      recorded_shots = n(),
      in_play_shots = sum(LOC_Y <= 397.5),
      in_play_games = n_distinct(GAME_ID[LOC_Y <= 397.5]),
      .by = PLAYER_ID
    ) |>
    arrange(PLAYER_ID)
  analyzed <- tibble(
    PLAYER_ID = as.integer(vapply(analyzed_entries, `[[`, character(1),
                                  "player_id")),
    evidence_status = vapply(analyzed_entries, `[[`, character(1),
                             "evidence_status")
  )
  recorded |>
    left_join(analyzed, by = "PLAYER_ID") |>
    mutate(
      analysis_available = !is.na(evidence_status),
      availability_status = if_else(
        analysis_available, evidence_status, "model_ineligible"
      ),
      availability_reason = case_when(
        analysis_available ~ evidence_status,
        in_play_games < MIN_GAMES & in_play_shots < MIN_ATTEMPTS ~
          "fewer_than_20_games_and_250_attempts",
        in_play_games < MIN_GAMES ~ "fewer_than_20_games",
        in_play_shots < MIN_ATTEMPTS ~ "fewer_than_250_attempts",
        TRUE ~ "eligibility_mismatch"
      )
    )
}

availability_catalog <- function(indexes) {
  metadata <- setNames(lapply(SEASONS, function(season) {
    season_metadata(season, indexes[[season]]$players)
  }), SEASONS)
  all_ids <- sort(unique(unlist(lapply(metadata, `[[`, "PLAYER_ID"))))
  players <- lapply(all_ids, function(player_id) {
    most_recent <- NULL
    season_states <- lapply(SEASONS, function(season) {
      row <- metadata[[season]] |>
        filter(PLAYER_ID == player_id)
      if (nrow(row) == 0L) {
        return(list(
          season = season, analysis_available = FALSE,
          availability_status = "no_recorded_shots",
          availability_reason = "no_recorded_shots",
          recorded_shots = 0L, in_play_shots = 0L, in_play_games = 0L
        ))
      }
      if (is.null(most_recent)) most_recent <<- row$player_name[[1]]
      list(
        season = season,
        analysis_available = row$analysis_available[[1]],
        availability_status = row$availability_status[[1]],
        availability_reason = row$availability_reason[[1]],
        recorded_shots = as.integer(row$recorded_shots[[1]]),
        in_play_shots = as.integer(row$in_play_shots[[1]]),
        in_play_games = as.integer(row$in_play_games[[1]])
      )
    })
    list(player_id = as.character(player_id), player_name = most_recent,
         seasons = season_states)
  })
  list(
    schema_version = "4.0.0",
    data_version = "five-season-targeted-v4",
    statuses = list(
      no_recorded_shots = "No recorded shots for this player and season.",
      model_ineligible = paste(
        "Recorded shots exist, but the player did not meet the season model's",
        "20-game and 250-attempt eligibility rules."
      ),
      insufficient_evidence = paste(
        "The player has an eligible modeled surface but no supported",
        "relocation destination."
      ),
      single_destination = "The relocation estimate has one supported destination.",
      multiple_destinations = "The relocation estimate has multiple supported destinations."
    ),
    players = players
  )
}

build_v4 <- function(root) {
  dir.create(root, recursive = FALSE, showWarnings = FALSE)
  target_assert(dir.exists(root), "could not create v4 staging root")
  indexes <- list()
  source_manifests <- list()
  for (season in SEASONS) {
    source <- season_source(season)
    target_assert(dir.exists(source), paste("missing verified season bundle", season))
    indexes[[season]] <- read_season_index(source, season)
    source_manifests[[season]] <- fromJSON(
      file.path(source, "manifest.json"), simplifyVector = FALSE
    )
    copy_tree_exact(
      file.path(source, "seasons", season),
      file.path(root, "seasons", season)
    )
  }
  catalog <- availability_catalog(indexes)
  write_json_file(catalog, file.path(root, "players.json"))

  player_counts <- vapply(indexes, function(index) length(index$players), integer(1))
  status_counts <- lapply(SEASONS, function(season) {
    statuses <- vapply(indexes[[season]]$players, `[[`, character(1),
                       "evidence_status")
    list(
      insufficient_evidence = sum(statuses == "insufficient_evidence"),
      single_destination = sum(statuses == "single_destination"),
      multiple_destinations = sum(statuses == "multiple_destinations")
    )
  })
  names(status_counts) <- SEASONS
  payload_paths <- setdiff(bundle_files(root), "manifest.json")
  manifest <- list(
    schema_version = "4.0.0",
    data_version = "five-season-targeted-v4",
    export_method = "spatial-targeted-capped-multiseason-website-export-v4",
    seasons = lapply(SEASONS, function(season) list(
      season = season,
      player_index = file.path("seasons", season, "players.json"),
      player_count = unname(player_counts[[season]]),
      evidence_counts = status_counts[[season]],
      source_manifest_sha256 = sha256_file(
        file.path(season_source(season), "manifest.json")
      )
    )),
    player_availability_catalog = "players.json",
    counts = list(
      seasons = length(SEASONS),
      analyzed_player_seasons = sum(player_counts),
      unique_players_with_recorded_shots = length(catalog$players),
      shots = sum(vapply(source_manifests, function(manifest) {
        as.integer(manifest$counts$shots)
      }, integer(1))),
      heatmap_cells = sum(player_counts) * CELLS_PER_PLAYER
    ),
    model = list(
      season_pooling = FALSE,
      description = paste(
        "Each season is a separate descriptive production analysis using the",
        "CAR specification selected during the 2025-26 evaluation."
      ),
      grid_cells = CELLS_PER_PLAYER,
      posterior_draws = 4000L,
      destination_min_attempts = 10L,
      destination_min_certainty = 0.90,
      maximum_final_destination_share = 0.50
    ),
    preservation = list(
      v3_2025_26_player_payloads_unchanged = TRUE,
      v3_2025_26_source = "../v3/seasons/2025-26"
    ),
    disclaimer = paste(
      "Results are modeled descriptive estimates based on past shots.",
      "They are not causal, do not guarantee improvement, and do not show",
      "that a hypothetical relocated attempt would be made."
    ),
    payload_inventory_note = paste(
      "Hashes cover the availability catalog, season indexes, and player files;",
      "the manifest cannot hash itself."
    ),
    payload_files = inventory_for(root, payload_paths)
  )
  write_json_file(manifest, file.path(root, "manifest.json"))
  invisible(root)
}

validate_v4 <- function(root) {
  target_assert(dir.exists(root), "v4 bundle is missing")
  files <- bundle_files(root)
  target_assert(all(tools::file_ext(files) == "json"),
                "v4 contains a non-JSON file")
  manifest <- fromJSON(file.path(root, "manifest.json"), simplifyVector = FALSE)
  target_assert(identical(manifest$data_version, "five-season-targeted-v4") &&
                  length(manifest$seasons) == 5L,
                "v4 manifest identity changed")
  for (season in SEASONS) {
    source <- file.path(season_source(season), "seasons", season)
    target <- file.path(root, "seasons", season)
    source_hashes <- bundle_hashes(source)
    target_hashes <- bundle_hashes(target)
    target_assert(identical(source_hashes, target_hashes),
                  paste(season, "season files changed during aggregation"))
    index <- fromJSON(file.path(target, "players.json"), simplifyVector = FALSE)
    for (entry in index$players) {
      player <- fromJSON(file.path(target, entry$player_file), simplifyVector = FALSE)
      target_assert(length(player$heatmap_cells) == CELLS_PER_PLAYER,
                    paste(season, entry$player_id, "heatmap cell count"))
    }
  }
  catalog <- fromJSON(file.path(root, "players.json"), simplifyVector = FALSE)
  target_assert(length(catalog$players) > 0L && all(vapply(
    catalog$players, function(player) length(player$seasons) == 5L, logical(1)
  )), "availability catalog is incomplete")
  inventory_paths <- vapply(manifest$payload_files, `[[`, character(1), "path")
  inventory_hashes <- vapply(manifest$payload_files, `[[`, character(1), "sha256")
  observed <- bundle_hashes(root)[inventory_paths]
  target_assert(setequal(inventory_paths, setdiff(files, "manifest.json")) &&
                  identical(unname(inventory_hashes), unname(observed)),
                "v4 payload inventory differs from files")
  forbidden <- c("GAME_ID", "game_id", "event_id", "GAME_DATE", "game_date",
                 "opponent", "SHOT_CLOCK", "shot_clock", "DEFENDER", "defender",
                 "stable_source_row")
  keys <- function(value) {
    own <- names(value)
    nested <- if (is.list(value)) unlist(lapply(value, keys), use.names = FALSE)
      else character()
    c(own, nested)
  }
  parsed <- lapply(file.path(root, files), fromJSON, simplifyVector = FALSE)
  target_assert(!any(unique(unlist(lapply(parsed, keys))) %in% forbidden),
                "v4 contains a forbidden shot-context field")
  text <- paste(vapply(file.path(root, files), function(path) {
    paste(readLines(path, warn = FALSE), collapse = "")
  }, character(1)), collapse = "\n")
  target_assert(!grepl("/Users/|data/cache|NaN|Infinity", text),
                "v4 contains a private path or invalid number")
  list(files = files, hashes = bundle_hashes(root),
       bytes = sum(file.info(file.path(root, files))$size))
}

if (mode == "verify") {
  verified <- validate_v4(V4_ROOT)
  completion <- readRDS(COMPLETION_PATH)
  target_assert(isTRUE(completion$complete) &&
                  identical(completion$file_hashes, verified$hashes),
                "v4 completion record differs from files")
  cat("Verified v4:", length(verified$files), "files,", verified$bytes,
      "bytes.\n")
  quit(save = "no", status = 0L)
}

head <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)[[1]]
upstream <- system2("git", c("rev-parse", "@{upstream}"), stdout = TRUE)[[1]]
target_assert(identical(head, upstream), "HEAD must match upstream before v4 build")
target_assert(system2("git", c("diff", "--quiet")) == 0L &&
                system2("git", c("diff", "--cached", "--quiet")) == 0L,
              "tracked tree must be clean before v4 build")
target_assert(!dir.exists(V4_ROOT), "refusing to overwrite v4")
target_assert(!file.exists(COMPLETION_PATH), "refusing to overwrite v4 completion")
dir.create(CACHE_ROOT, recursive = TRUE, showWarnings = FALSE)
target_assert(dir.create(LOCK_PATH), "another v4 build is active")
success <- FALSE
on.exit({ if (success && dir.exists(LOCK_PATH)) unlink(LOCK_PATH, recursive = TRUE) },
        add = TRUE)
first <- tempfile("v4-first-", CACHE_ROOT)
second <- tempfile("v4-second-", CACHE_ROOT)
build_v4(first)
first_check <- validate_v4(first)
build_v4(second)
second_check <- validate_v4(second)
target_assert(identical(first_check$files, second_check$files) &&
                identical(first_check$hashes, second_check$hashes),
              "two v4 builds are not byte-for-byte identical")
unlink(second, recursive = TRUE)
dir.create(dirname(V4_ROOT), recursive = TRUE, showWarnings = FALSE)
target_assert(file.rename(first, V4_ROOT), "could not publish v4 atomically")
final <- validate_v4(V4_ROOT)
target_assert(identical(first_check$hashes, final$hashes),
              "published v4 differs from staging")
completion <- list(
  complete = TRUE, data_version = "five-season-targeted-v4",
  pre_result_commit = head, file_hashes = final$hashes,
  files = length(final$files), bytes = final$bytes,
  deterministic_regeneration = TRUE
)
pending <- tempfile("v4-complete-", CACHE_ROOT, fileext = ".rds")
saveRDS(completion, pending)
target_assert(file.rename(pending, COMPLETION_PATH),
              "could not publish v4 completion atomically")
success <- TRUE
cat(toJSON(completion[c("data_version", "files", "bytes",
                        "deterministic_regeneration")],
           auto_unbox = TRUE, pretty = TRUE), "\n")
