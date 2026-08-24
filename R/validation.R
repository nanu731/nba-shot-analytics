# Section 16 validation. Run once, reported in the writeup, not part of the recurring
# pipeline. Diagnosis only -- nothing here changes the metric.

library(tidyverse)
library(arrow)
library(glue)

SEASONS <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")

load_season <- function(season) {
  ps <- read_parquet(glue("data/processed/player_scores/season={season}/player_scores.parquet"))
  zs <- read_parquet(glue("data/processed/zone_stats/season={season}/zone_stats.parquet"))
  ra <- zs |>
    filter(zone == "Restricted Area | Center(C)") |>
    select(PLAYER_ID, ra_freq = shot_freq)
  left_join(ps, ra, by = "PLAYER_ID") |> mutate(season = season)
}

validate <- function(season) {
  d <- load_season(season)
  cat(glue("\n===== {season}  (n = {nrow(d)}) ====="), "\n")

  cat("\n-- check 3: score vs zones_used --\n")
  r3 <- cor(d$score_pooled, d$zones_used)
  cat(glue("  r = {round(r3, 4)}  (Section 16 says do not assume a direction)"), "\n")
  print(d |> summarise(n = n(), mean_score = round(mean(score_pooled), 3),
                       .by = zones_used) |> arrange(zones_used), n = Inf)

  cat("\n-- check 4: positional pattern --\n")
  by_pos <- d |>
    summarise(n = n(), mean = round(mean(score_pooled), 4), sd = round(sd(score_pooled), 4),
              min = round(min(score_pooled), 3), max = round(max(score_pooled), 3),
              .by = POS3) |>
    arrange(desc(mean))
  print(by_pos, n = Inf)

  known <- filter(d, POS3 != "Unknown")
  fit <- lm(score_pooled ~ POS3, data = known)
  a   <- anova(fit)
  cat(glue("  ANOVA on C/F/G only: F({a$Df[1]},{a$Df[2]}) = {round(a$`F value`[1], 1)}, ",
           "p = {format.pval(a$`Pr(>F)`[1], digits = 3)}"), "\n")
  cat(glue("  position explains R2 = {round(summary(fit)$r.squared, 3)} ",
           "({round(100 * summary(fit)$r.squared)}%) of score variance"), "\n")

  cat("\n-- check 5: score vs restricted-area frequency (free-throw proxy) --\n")
  cat(glue("  r = {round(cor(d$score_pooled, d$ra_freq), 4)}"), "\n")

  cat("\n-- Herfindahl vs score (redundant; see Section 8) --\n")
  cat(glue("  r = {round(cor(d$score_pooled, d$herfindahl), 4)}"), "\n")

  # Section 8a's axis. The gradient is the reason volume replaced concentration.
  cat("\n-- score vs shot volume (Section 8a primary axis) --\n")
  cat(glue("  r = {round(cor(d$score_pooled, d$total_attempts), 4)}"), "\n")
  print(d |> mutate(vol = cut(total_attempts, c(249, 400, 600, 900, Inf),
                              labels = c("250-400","400-600","600-900","900+"))) |>
          summarise(n = n(), mean_score = round(mean(score_pooled), 4), .by = vol) |>
          arrange(vol))

  cat("\n-- score vs volume WITHIN volume quartiles --\n")
  # Restricting to a quartile narrows the range of total_attempts, which attenuates r
  # for purely mechanical reasons. The slope does not suffer that, so it is the figure
  # to read: a gradient that persists inside quartiles is continuous, one that flattens
  # means the leaderboard is largely an artifact of the 250-attempt gate.
  qd <- d |> mutate(vq = ntile(total_attempts, 4))
  print(qd |>
    summarise(n = n(),
              lo = min(total_attempts), hi = max(total_attempts),
              r = round(cor(score_pooled, total_attempts), 3),
              slope_per_1000 = round(coef(lm(score_pooled ~ total_attempts))[2] * 1000, 4),
              .by = vq) |> arrange(vq))
  full_slope <- coef(lm(score_pooled ~ total_attempts, data = d))[2] * 1000
  cat(glue("  pooled slope across all players = {round(full_slope, 4)} per 1000 attempts"), "\n")

  invisible(list(season = season, r_zones = r3,
                 vq = qd |> summarise(r = cor(score_pooled, total_attempts),
                                      slope = coef(lm(score_pooled ~ total_attempts))[2] * 1000,
                                      .by = vq) |> arrange(vq),
                 full_slope = full_slope,
                 r_ra = cor(d$score_pooled, d$ra_freq),
                 r_h  = cor(d$score_pooled, d$herfindahl),
                 r_vol = cor(d$score_pooled, d$total_attempts),
                 r2_pos = summary(fit)$r.squared, by_pos = by_pos, d = d))
}

# The question the positional pattern raises: does the score separate players inside a
# position, or is it mostly reading position off the shot diet?
within_position <- function(d) {
  cat("\n-- within-position discrimination --\n")
  overall_sd <- sd(d$score_pooled)
  cat(glue("  overall SD = {round(overall_sd, 4)}"), "\n\n")

  for (pos in c("C", "F", "G")) {
    g <- filter(d, POS3 == pos) |> arrange(desc(score_pooled))
    cat(glue("  {pos}  n = {nrow(g)}  SD = {round(sd(g$score_pooled), 4)}  ",
             "({round(100 * sd(g$score_pooled) / overall_sd)}% of overall)  ",
             "range {round(min(g$score_pooled), 3)} to {round(max(g$score_pooled), 3)}  ",
             "IQR = {round(IQR(g$score_pooled), 4)}"), "\n")
    top <- head(g, 3); bot <- tail(g, 3)
    fmt <- \(x) str_c(x$PLAYER_NAME, " ", sprintf("%+.3f", x$score_pooled), collapse = ",  ")
    cat(glue("     top: {fmt(top)}"), "\n")
    cat(glue("     bot: {fmt(bot)}"), "\n\n")
  }
}

if (sys.nframe() == 0L) {
  res <- map(SEASONS, validate)
  cat("\n\n===== cross-season summary =====\n")
  print(map_dfr(res, \(r) tibble(season = r$season, r_zones_used = round(r$r_zones, 3),
                                 r_ra_freq = round(r$r_ra, 3),
                                 r_herfindahl = round(r$r_h, 3),
                                 r_volume = round(r$r_vol, 3),
                                 pos_r2 = round(r$r2_pos, 3))))
  within_position(res[[5]]$d)
}
