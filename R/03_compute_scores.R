library(tidyverse)
library(arrow)
library(duckdb)
library(DBI)
library(glue)

# VGAM masks several dplyr verbs, so it is called namespaced rather than attached.

# ZONE_REF is the canonical 14-zone reference with point values and display order.
# Sourcing stage 2 rather than restating it here keeps one definition; the source has
# no side effects because its run call is guarded by sys.nframe().
source("R/02_build_zone_stats.R")

# Cells with no attempts carry no binomial information and are dropped from the fit.
# The prior they receive afterwards is exactly the fitted mean, which is the point.
MIN_CELLS_FOR_FIT <- 20

# Reads one season's file directly rather than globbing the store. A glob unions every
# season's schema, which breaks mid-run once some seasons are enriched and others are
# not. season comes from the path, so it is restored here.
read_processed <- function(table, season) {
  read_parquet(glue("data/processed/{table}/season={season}/{table}.parquet")) |>
    as_tibble() |>
    mutate(season = .env$season, .before = 1)
}

# The columns stage 2 owns. Selecting them explicitly makes stage 3 idempotent: a
# re-run drops any enrichment already present instead of colliding with it.
STAGE2_ZONE_COLS   <- c("season", "PLAYER_ID", "PLAYER_NAME", "zone", "zone_value",
                        "makes", "attempts", "fg_pct", "pps_raw", "shot_freq")
STAGE2_PLAYER_COLS <- c("season", "PLAYER_ID", "PLAYER_NAME", "total_attempts",
                        "games", "zones_used", "pps_overall_raw")

# Fallback only. Decomposes the observed spread of shooting percentages into true
# between-player variance and the binomial noise expected at each player's attempt
# count, then matches that to a Beta. Less efficient than the MLE, but it cannot fail
# to converge.
fit_prior_mom <- function(makes, attempts) {
  p       <- makes / attempts
  mu      <- sum(makes) / sum(attempts)
  v_total <- var(p)
  v_noise <- mean(p * (1 - p) / attempts)
  v_true  <- max(v_total - v_noise, 1e-8)
  k       <- max(mu * (1 - mu) / v_true - 1, 1e-6)
  list(alpha = mu * k, beta = (1 - mu) * k)
}

# Returns alpha and beta for one zone. VGAM's betabinomial is parameterised by a mean
# mu and an intra-cluster correlation rho, where rho = 1 / (1 + alpha + beta).
fit_zone_prior <- function(makes, attempts, label) {
  d <- tibble(makes, attempts) |> filter(attempts > 0)
  if (nrow(d) < MIN_CELLS_FOR_FIT) {
    warning(glue("{label}: only {nrow(d)} non-empty cells, using method of moments"),
            call. = FALSE, immediate. = TRUE)
    mom <- fit_prior_mom(d$makes, d$attempts)
    return(c(mom, list(method = "moments", converged = FALSE)))
  }

  failed <- NULL
  fit <- withCallingHandlers(
    try(VGAM::vglm(cbind(makes, attempts - makes) ~ 1, VGAM::betabinomial,
                   data = d, trace = FALSE), silent = TRUE),
    warning = function(w) {
      if (str_detect(conditionMessage(w), regex("converg", ignore_case = TRUE))) {
        failed <<- conditionMessage(w)
      }
      invokeRestart("muffleWarning")
    })

  if (!inherits(fit, "try-error") && is.null(failed)) {
    est <- VGAM::Coef(fit)
    mu  <- unname(est["mu"])
    rho <- unname(est["rho"])
    k   <- (1 - rho) / rho
    if (all(is.finite(c(mu, rho, k))) && rho > 0 && rho < 1 && k > 0) {
      return(list(alpha = mu * k, beta = (1 - mu) * k,
                  method = "vglm", converged = TRUE))
    }
    failed <- glue("implausible estimates mu={signif(mu,3)} rho={signif(rho,3)}")
  }
  if (inherits(fit, "try-error")) failed <- str_squish(as.character(fit))

  # Rule A9: a convergence failure must surface, never be silently substituted.
  warning(glue("{label}: beta-binomial MLE failed ({failed}). ",
               "Falling back to method of moments."), call. = FALSE, immediate. = TRUE)
  mom <- fit_prior_mom(d$makes, d$attempts)
  c(mom, list(method = "moments", converged = FALSE))
}

# Priors are fitted per zone and per season. Section 6 requires the prior to describe
# the population being scored, and both the qualifying pool and the league's shooting
# environment change year to year.
fit_zone_priors <- function(zone_stats, season) {
  zone_stats |>
    left_join(select(ZONE_REF, zone, zone_order), by = "zone") |>
    group_by(zone, zone_value, zone_order) |>
    group_modify(\(d, key) {
      p <- fit_zone_prior(d$makes, d$attempts, glue("{season} {key$zone}"))
      tibble(alpha = p$alpha, beta = p$beta, method = p$method, converged = p$converged,
             league_makes = sum(d$makes), league_attempts = sum(d$attempts))
    }) |>
    ungroup() |>
    mutate(k = alpha + beta,
           prior_mean = alpha / k,
           pooled_fg_pct = league_makes / league_attempts,
           season = .env$season, .before = 1) |>
    arrange(zone_order)
}

read_raw <- function(table, season) {
  con <- dbConnect(duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbGetQuery(con, glue(
    "SELECT * FROM read_parquet('data/raw/{table}/**/*.parquet',
     hive_partitioning = 1) WHERE season = '{season}'")) |> as_tibble()
}

# Unknown means the player never appears in the end-of-season roster, which happens to
# players waived or traded late. A POSITION that is present but unrecognised is a
# different failure and warns rather than being folded into Unknown.
derive_pos3 <- function(position) {
  primary <- str_trim(str_extract(position, "^[^-]+"))
  bad <- setdiff(unique(primary[!is.na(primary)]), c("C", "F", "G"))
  if (length(bad)) {
    warning(glue("unrecognised POSITION values: {str_c(bad, collapse = ', ')}"),
            call. = FALSE, immediate. = TRUE)
  }
  case_when(
    is.na(position)            ~ "Unknown",
    primary %in% c("C","F","G") ~ primary,
    .default                    = NA_character_
  )
}

compute_scores <- function(season) {
  cat(glue("\n=== stage 3: {season} ==="), "\n\n")
  zs     <- read_processed("zone_stats", season)   |> select(all_of(STAGE2_ZONE_COLS))
  scores <- read_processed("player_scores", season) |> select(all_of(STAGE2_PLAYER_COLS))
  priors <- fit_zone_priors(zs, season)

  fell_back <- filter(priors, !converged)
  cat(glue("priors: {sum(priors$converged)} of {nrow(priors)} zones by beta-binomial MLE"), "\n")
  if (nrow(fell_back)) {
    cat(glue("  METHOD OF MOMENTS FALLBACK: {str_c(fell_back$zone, collapse = '; ')}"), "\n")
  }

  # Both baselines are 14-element vectors over the qualifying pool. Pooled is a real
  # shot distribution; unweighted is a mean of ratios kept only as a robustness check.
  baselines <- zs |>
    summarise(freq_pooled     = sum(attempts) / sum(scores$total_attempts),
              freq_unweighted = mean(shot_freq),
              .by = zone)
  for (nm in c("freq_pooled", "freq_unweighted")) {
    drift <- abs(sum(baselines[[nm]]) - 1)
    if (drift > 1e-9) stop(glue("{nm} sums to {1 + drift}, not 1"), call. = FALSE)
  }
  cat(glue("baselines: both 14-zone vectors sum to 1"), "\n")

  zone_stats <- zs |>
    left_join(select(priors, zone, alpha, beta, prior_mean), by = "zone") |>
    left_join(baselines, by = "zone") |>
    mutate(
      fg_pct_shrunk = (makes + alpha) / (attempts + alpha + beta),
      pps_shrunk    = zone_value * fg_pct_shrunk,
      # Shift-share: the player's own zone ability held fixed, weighted by how far his
      # shot diet departs from the league's. Ability cancels, allocation remains.
      score_contrib = (shot_freq - freq_pooled) * pps_shrunk
    ) |>
    select(season, PLAYER_ID, PLAYER_NAME, zone, zone_value, makes, attempts,
           fg_pct, pps_raw, shot_freq, fg_pct_shrunk, pps_shrunk,
           freq_pooled, freq_unweighted, score_contrib)

  empty <- filter(zone_stats, attempts == 0)
  drift <- zone_stats |>
    left_join(select(priors, zone, prior_mean), by = "zone") |>
    filter(attempts == 0) |>
    summarise(d = max(abs(fg_pct_shrunk - prior_mean))) |> pull(d)
  if (length(drift) && drift > 1e-12) {
    stop(glue("zero-attempt cells do not return the prior mean (drift {drift})"), call. = FALSE)
  }
  cat(glue("zero-attempt cells return the prior mean exactly ({nrow(empty)} cells)"), "\n")

  per_player <- zone_stats |>
    summarise(score_pooled     = sum(score_contrib),
              score_unweighted = sum((shot_freq - freq_unweighted) * pps_shrunk),
              herfindahl       = sum(shot_freq^2),
              .by = PLAYER_ID)

  roster <- read_raw("roster", season) |>
    select(PLAYER_ID, POSITION) |>
    distinct(PLAYER_ID, .keep_all = TRUE)

  player_scores <- scores |>
    left_join(per_player, by = "PLAYER_ID") |>
    left_join(roster, by = "PLAYER_ID") |>
    mutate(POS3 = derive_pos3(POSITION))

  unknown <- filter(player_scores, POS3 == "Unknown")
  cat(glue("position: {sum(player_scores$POS3 != 'Unknown')} of {nrow(player_scores)} matched, ",
           "{nrow(unknown)} Unknown"), "\n")
  if (nrow(unknown) && nrow(unknown) <= 10) {
    cat(glue("  {str_c(unknown$PLAYER_NAME, collapse = ', ')}"), "\n")
  }
  cat(glue("  POS3 buckets: {str_c(sort(unique(player_scores$POS3)), collapse = ', ')}"), "\n")

  # Score checks 1 and 2 live in R/validation.R, which Section 16 keeps separate from the
  # recurring pipeline.


  zone_priors <- priors |>
    select(season, zone, zone_value, alpha, beta, k, prior_mean,
           league_attempts, converged, method)

  cat("\nwritten\n")
  for (path in c(write_season_table(zone_stats, "zone_stats", season),
                 write_season_table(player_scores, "player_scores", season),
                 write_season_table(zone_priors, "zone_priors", season))) {
    cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  }

  invisible(list(zone_stats = zone_stats, player_scores = player_scores,
                 zone_priors = zone_priors))
}

if (sys.nframe() == 0L) {
  for (s in c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")) compute_scores(s)
}
