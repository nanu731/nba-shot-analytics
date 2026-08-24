library(tidyverse)
library(arrow)
library(glue)
library(svglite)

# Section 8a. Concentration was the original second axis and was dropped: it correlates
# 0.83 with the score and worsens within position. Volume is independent enough to carry
# a scatter and makes the volume gradient of Section 17 visible rather than hidden.

POS_COLOURS <- c(C = "#0F7B6C", F = "#B5651D", G = "#3A5FCD", Unknown = "#8A8A8A")
POS_ORDER   <- c("C", "F", "G", "Unknown")

score_volume_chart <- function(season) {
  d <- read_parquet(glue("data/processed/player_scores/season={season}/player_scores.parquet")) |>
    mutate(POS3 = factor(POS3, levels = POS_ORDER))

  # Unknown is kept as its own panel rather than dropped. Section 9 is explicit that
  # players missing a roster position stay visible on the primary chart.
  panels <- d |>
    summarise(n = n(), med_vol = median(total_attempts), .by = POS3) |>
    mutate(label = glue("{POS3}  (n = {n})"))

  # Labels are nudged above the point and pushed inward at the panel edges, since
  # without that the longest names run off and get clipped.
  span <- range(d$total_attempts)
  labelled <- d |>
    slice_max(score_pooled, n = 3, by = POS3) |>
    bind_rows(slice_min(d, score_pooled, n = 3, by = POS3)) |>
    distinct(PLAYER_ID, .keep_all = TRUE) |>
    arrange(POS3, desc(score_pooled)) |>
    mutate(rel = (total_attempts - span[1]) / diff(span),
           hjust = case_when(rel > 0.72 ~ 1, rel < 0.12 ~ 0, .default = 0.5),
           # Alternating above/below keeps names legible where two players sit almost on
           # top of each other, which happens at both extremes of every panel.
           vjust = rep_len(c(-0.9, 1.8), length.out = n()), .by = POS3)

  strip <- set_names(panels$label, panels$POS3)

  ggplot(d, aes(total_attempts, score_pooled)) +
    geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey55") +
    geom_vline(aes(xintercept = med_vol), data = panels,
               linewidth = 0.3, linetype = "dashed", colour = "grey70") +
    geom_point(aes(colour = POS3), size = 1.8, alpha = 0.75) +
    geom_text(aes(label = PLAYER_NAME, hjust = hjust, vjust = vjust), data = labelled,
              size = 2.4, colour = "grey20") +
    scale_colour_manual(values = POS_COLOURS, guide = "none") +
    scale_x_continuous(labels = scales::comma, breaks = seq(250, 1500, 250),
                       expand = expansion(mult = 0.07)) +
    scale_y_continuous(labels = \(x) sprintf("%+.2f", x),
                       expand = expansion(mult = c(0.05, 0.10))) +
    facet_wrap(~POS3, nrow = 1, labeller = labeller(POS3 = strip)) +
    labs(
      title = glue("Shot selection against shot volume, {season}"),
      subtitle = paste("Selection score is points per shot gained or lost against a league-typical",
                       "shot diet, holding each player's own zone abilities fixed.\nDashed line is the",
                       "median volume within each position. Zero means a league-typical allocation."),
      x = "Field goal attempts",
      y = "Selection score (points per shot)",
      caption = "Qualifying players: 20+ games and 250+ field goal attempts."
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      strip.text = element_text(face = "bold", hjust = 0),
      axis.text.x = element_text(size = 8),
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(colour = "grey30", size = 9, lineheight = 1.2),
      plot.caption = element_text(colour = "grey45", size = 8),
      plot.title.position = "plot"
    )
}

write_chart <- function(plot, name, season, width = 14, height = 5.8) {
  dir.create("export/charts", recursive = TRUE, showWarnings = FALSE)
  path <- glue("export/charts/{name}_{season}.svg")
  ggsave(path, plot, device = svglite, width = width, height = height)
  cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  path
}

if (sys.nframe() == 0L) {
  season <- "2025-26"
  cat(glue("charts for {season}\n\n"))
  write_chart(score_volume_chart(season), "score_vs_volume", season)
}
