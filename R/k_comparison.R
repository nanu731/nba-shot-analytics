# Section 16's three-method k comparison. Runs once, reported in the writeup, and is not
# part of the recurring pipeline -- run_pipeline.R does not source this.
#
#   Rscript R/k_comparison.R
#
# k is the shrinkage weight: FG%_shrunk = (makes + a) / (attempts + k), where a = k * mu.
# A large k pulls a player hard toward the zone's league mean; a small k leaves his own
# rate mostly intact. Three independent estimates agreeing is a far stronger claim than
# one asserted, and if they diverge the pattern is itself diagnostic.

library(tidyverse)
library(arrow)
library(glue)

source("R/03_compute_scores.R")

SEASON  <- "2025-26"
SPLITS  <- 200                      # random halvings; one split is far too noisy
K_GRID  <- c(seq(5, 100, 5), seq(110, 400, 10), seq(425, 1200, 25))
set.seed(20260824)

# Method 2. Halve each player's attempts in a zone at random, correlate the two halves,
# then invert Spearman-Brown to the k that reliability implies. Assumption-free about how
# ability is distributed across players, which is exactly where the MLE is vulnerable.
k_split_half <- function(makes, attempts, n_splits = SPLITS) {
  keep <- attempts >= 2
  m <- makes[keep]; a <- attempts[keep]
  if (length(m) < 20) return(NA_real_)

  rs <- map_dbl(seq_len(n_splits), \(i) {
    n1 <- rbinom(length(a), a, 0.5)
    x1 <- rhyper(length(a), m, a - m, n1)
    ok <- n1 >= 1 & (a - n1) >= 1
    if (sum(ok) < 20) return(NA_real_)
    p1 <- x1[ok] / n1[ok]
    p2 <- (m[ok] - x1[ok]) / (a[ok] - n1[ok])
    if (sd(p1) == 0 || sd(p2) == 0) return(NA_real_)
    cor(p1, p2)
  })
  r_half <- mean(rs, na.rm = TRUE)
  if (!is.finite(r_half) || r_half <= 0) return(NA_real_)

  # Spearman-Brown lifts the half-length correlation to full length; the reliability of a
  # mean of n trials is n / (n + k), so k = n * (1 - rel) / rel.
  rel <- 2 * r_half / (1 + r_half)
  n_bar <- mean(a)
  max(n_bar * (1 - rel) / rel, 0)
}

# Method 3. Hold out shots, pick the k minimising held-out log loss. Optimises what
# actually matters -- prediction -- but the loss surface can be flat, which the RAPM
# literature is candid about.
k_cross_validated <- function(makes, attempts, grid = K_GRID) {
  keep <- attempts >= 2
  m <- makes[keep]; a <- attempts[keep]
  if (length(m) < 20) return(list(k = NA_real_, flat = NA))

  mu <- sum(m) / sum(a)
  n_train <- rbinom(length(a), a, 0.7)
  x_train <- rhyper(length(a), m, a - m, n_train)
  n_test  <- a - n_train
  x_test  <- m - x_train
  ok <- n_train >= 1 & n_test >= 1
  n_train <- n_train[ok]; x_train <- x_train[ok]
  n_test <- n_test[ok]; x_test <- x_test[ok]

  loss <- map_dbl(grid, \(k) {
    p <- (x_train + k * mu) / (n_train + k)
    p <- pmin(pmax(p, 1e-6), 1 - 1e-6)
    -sum(x_test * log(p) + (n_test - x_test) * log(1 - p))
  })
  best <- grid[which.min(loss)]
  # A minimum sitting at an endpoint means the curve never turned: the data cannot
  # identify k, which is a finding rather than an estimate.
  list(k = best, flat = best %in% range(grid))
}

compare_k <- function(season = SEASON) {
  zs <- read_processed("zone_stats", season) |> select(all_of(STAGE2_ZONE_COLS))
  priors <- fit_zone_priors(zs, season)

  out <- zs |>
    left_join(select(priors, zone, zone_order, k_mle = k, converged), by = "zone") |>
    summarise(
      k_mle       = first(k_mle),
      converged   = first(converged),
      zone_order  = first(zone_order),
      k_split     = k_split_half(makes, attempts),
      cv          = list(k_cross_validated(makes, attempts)),
      cells       = sum(attempts > 0),
      median_att  = median(attempts[attempts > 0]),
      .by = zone) |>
    mutate(k_cv = map_dbl(cv, "k"), cv_flat = map_lgl(cv, "flat")) |>
    select(-cv) |>
    arrange(zone_order)

  cat(glue("\n=== three-method k comparison, {season} ===\n"), "\n")
  cat(glue("split-half averaged over {SPLITS} random halvings; ",
           "cross-validation on a 70/30 shot-level split\n"), "\n")

  print(out |>
    transmute(zone = str_trunc(zone, 38), cells, median_att,
              k_mle = round(k_mle), k_split = round(k_split), k_cv = round(k_cv),
              ratio_split = round(k_split / k_mle, 2),
              ratio_cv = round(k_cv / k_mle, 2),
              flags = str_c(if_else(converged, "", "MoM "), if_else(cv_flat, "cv-flat", ""))),
    n = Inf, width = 200)

  cat("\nagreement\n")
  for (pair in list(c("k_split", "k_mle"), c("k_cv", "k_mle"), c("k_cv", "k_split"))) {
    ok <- is.finite(out[[pair[1]]]) & is.finite(out[[pair[2]]])
    cat(glue("  cor({pair[1]}, {pair[2]}) = {round(cor(out[[pair[1]]][ok], out[[pair[2]]][ok]), 3)}  ",
             "rank r = {round(cor(out[[pair[1]]][ok], out[[pair[2]]][ok], method = 'spearman'), 3)}"), "\n")
  }
  cat(glue("  median k: MLE {round(median(out$k_mle))}, ",
           "split-half {round(median(out$k_split, na.rm = TRUE))}, ",
           "CV {round(median(out$k_cv, na.rm = TRUE))}"), "\n")
  cat(glue("  CV hit a grid endpoint in {sum(out$cv_flat, na.rm = TRUE)} of {nrow(out)} zones"), "\n")

  invisible(out)
}

if (sys.nframe() == 0L) compare_k()
