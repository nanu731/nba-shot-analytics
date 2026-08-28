library(tidyverse)
library(arrow)
library(glue)
library(svglite)
library(ggrepel)

# Court dimensions and the classifier both come from here. Nothing in this file restates a
# boundary; see rule A4.
source("R/zone_model.R")

# All three chart types share a theme and palette because they share a site.

POS_COLOURS <- c(C = "#0F7B6C", F = "#B5651D", G = "#3A5FCD", Unknown = "#8A8A8A")
POS_ORDER   <- c("C", "F", "G", "Unknown")

# Diverging ramp for score contribution and PPS, centred on a neutral grey so that zero
# reads as neutral rather than as a low value.
COOL <- "#2C6E8F"; WARM <- "#B03A2E"; NEUTRAL <- "#EDE7DF"

theme_shots <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", hjust = 0),
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(colour = "grey30", size = 9, lineheight = 1.2),
      plot.caption = element_text(colour = "grey45", size = 8),
      plot.title.position = "plot",
      axis.text = element_text(size = 8)
    )
}

read_scores <- function(season) {
  read_parquet(glue("data/processed/player_scores/season={season}/player_scores.parquet")) |>
    mutate(POS3 = factor(POS3, levels = POS_ORDER))
}

read_zones <- function(season) {
  read_parquet(glue("data/processed/zone_stats/season={season}/zone_stats.parquet"))
}

write_chart <- function(plot, name, season, width, height) {
  dir.create("export/charts", recursive = TRUE, showWarnings = FALSE)
  path <- glue("export/charts/{name}_{season}.svg")
  ggsave(path, plot, device = svglite, width = width, height = height)
  cat(glue("  {path}  {round(file.size(path) / 1024, 1)} KB"), "\n")
  invisible(path)
}

# Section 8a primary chart. Concentration was the original second axis and was dropped:
# it correlates 0.83 with the score and the redundancy worsens within position.
score_volume_chart <- function(season) {
  # ggrepel places labels by stochastic search, so an unseeded chart differs between two
  # runs on identical data. export/charts is committed, so that dirties five SVGs on every
  # pipeline run and trains a reader to skip diffs in a directory where a real design
  # change should be visible.
  set.seed(20260827)
  d <- read_scores(season)

  # Unknown stays as its own panel. Section 9 is explicit that players missing a roster
  # position remain visible on the primary chart rather than being dropped from it.
  panels <- d |>
    summarise(n = n(), med_vol = median(total_attempts), .by = POS3) |>
    mutate(label = glue("{POS3}  (n = {n})"))

  labelled <- d |>
    slice_max(score_pooled, n = 3, by = POS3) |>
    bind_rows(slice_min(d, score_pooled, n = 3, by = POS3)) |>
    distinct(PLAYER_ID, .keep_all = TRUE)

  ggplot(d, aes(total_attempts, score_pooled)) +
    geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey55") +
    geom_vline(aes(xintercept = med_vol), data = panels,
               linewidth = 0.3, linetype = "dashed", colour = "grey70") +
    geom_point(aes(colour = POS3), size = 1.8, alpha = 0.75) +
    geom_text_repel(aes(label = PLAYER_NAME), data = labelled, size = 2.5,
                    colour = "grey20", seed = 1, min.segment.length = 0.2,
                    segment.colour = "grey65", segment.linewidth = 0.25,
                    box.padding = 0.35, max.overlaps = Inf) +
    scale_colour_manual(values = POS_COLOURS, guide = "none") +
    scale_x_continuous(labels = scales::comma, breaks = seq(250, 1500, 250),
                       expand = expansion(mult = 0.07)) +
    scale_y_continuous(labels = \(x) sprintf("%+.2f", x),
                       expand = expansion(mult = 0.10)) +
    facet_wrap(~POS3, nrow = 1,
               labeller = labeller(POS3 = set_names(panels$label, panels$POS3))) +
    labs(
      title = glue("Shot selection against shot volume, {season}"),
      subtitle = paste("Selection score is points per shot gained or lost against a league-typical shot diet,",
                       "holding each player's own zone abilities fixed.\nDashed line is median volume within",
                       "each position. Zero means a league-typical allocation."),
      x = "Field goal attempts", y = "Selection score (points per shot)",
      caption = "Qualifying players: 20+ games and 250+ field goal attempts."
    ) +
    theme_shots() +
    theme(panel.grid.major.x = element_blank())
}

# Companion ranking view for the Section 18 leaderboards. The scatter above carries the
# full distribution; this names who sits at each end within a position.
leaderboard_chart <- function(season, n_each = 5) {
  d <- read_scores(season)
  ends <- d |>
    slice_max(score_pooled, n = n_each, by = POS3) |>
    bind_rows(slice_min(d, score_pooled, n = n_each, by = POS3)) |>
    distinct(PLAYER_ID, .keep_all = TRUE) |>
    mutate(name = fct_reorder(PLAYER_NAME, score_pooled))

  panels <- d |> summarise(n = n(), .by = POS3) |> mutate(label = glue("{POS3}  (n = {n})"))

  ggplot(ends, aes(score_pooled, name)) +
    geom_vline(xintercept = 0, linewidth = 0.4, colour = "grey55") +
    geom_segment(aes(x = 0, xend = score_pooled, yend = name, colour = POS3),
                 linewidth = 0.5, alpha = 0.55) +
    geom_point(aes(colour = POS3), size = 2.6) +
    geom_text(aes(label = sprintf("%+.3f", score_pooled),
                  hjust = if_else(score_pooled > 0, -0.25, 1.25)),
              size = 2.5, colour = "grey30") +
    scale_colour_manual(values = POS_COLOURS, guide = "none") +
    scale_x_continuous(labels = \(x) sprintf("%+.2f", x), expand = expansion(mult = 0.22)) +
    facet_wrap(~POS3, nrow = 1, scales = "free_y",
               labeller = labeller(POS3 = set_names(panels$label, panels$POS3))) +
    labs(
      title = glue("Best and worst shot selectors within each position, {season}"),
      subtitle = glue("Top and bottom {n_each} by selection score. Position is a display variable only, ",
                      "and comparisons within a\npanel are the meaningful ones: position explains just ",
                      "18% of the variance in score."),
      x = "Selection score (points per shot)", y = NULL,
      caption = "Qualifying players: 20+ games and 250+ field goal attempts."
    ) +
    theme_shots() +
    theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 8))
}

if (sys.nframe() == 0L) {
  season <- "2025-26"
  cat(glue("charts for {season}\n\n"))
  write_chart(score_volume_chart(season), "score_vs_volume", season, 14, 5.8)
  write_chart(leaderboard_chart(season),  "leaderboard",     season, 13, 5.2)
  write_chart(zone_chart("Stephen Curry", season), "zones_curry", season, 8.5, 7)
}

# Court furniture: the markings a viewer expects to see under the points. Every dimension
# is read from R/zone_model.R rather than restated here, which A4 requires and which is not
# a formality -- this function previously drew the corner segments up to y = 89.5, the
# geometric arc junction, where the model's break is the measured 87.5. Two numbers for one
# line is exactly the drift the rule exists to stop.
#
# The hoop and its 7.5-unit ring are the only numbers that are local, because no zone
# boundary depends on them.
court_layer <- function(colour = "grey45", linewidth = 0.35) {
  arc <- function(r, from, to, n = 200) {
    t <- seq(from, to, length.out = n)
    tibble(x = r * cos(t), y = r * sin(t))
  }
  three_arc <- arc(R_ARC, acos(CORNER_X / R_ARC), pi - acos(CORNER_X / R_ARC))
  seg <- function(...) annotate("segment", ..., colour = colour, linewidth = linewidth)
  path <- function(d) annotate("path", x = d$x, y = d$y, colour = colour, linewidth = linewidth)
  list(
    path(arc(7.5, 0, 2 * pi)),
    seg(x = -30, xend = 30, y = -7.5, yend = -7.5),
    annotate("rect", xmin = -LANE_HALF, xmax = LANE_HALF, ymin = BASELINE, ymax = LANE_TOP,
             fill = NA, colour = colour, linewidth = linewidth),
    path(arc(R_RIM, 0, pi)),
    seg(x = c(-CORNER_X, CORNER_X), xend = c(-CORNER_X, CORNER_X),
        y = BASELINE, yend = CORNER_TOP),
    path(three_arc),
    seg(x = -SIDELINE, xend = SIDELINE, y = BASELINE, yend = BASELINE)
  )
}

# Label anchors come from league-wide shot positions so every player's chart puts each
# zone's label in the same place, including zones where the player never shot.
.zone_anchor_cache <- new.env(parent = emptyenv())
zone_anchors <- function(season) {
  if (is.null(.zone_anchor_cache[[season]])) {
    .zone_anchor_cache[[season]] <- read_parquet(
      glue("data/raw/shots/season={season}/shots.parquet")) |>
      mutate(zone = classify_zone(LOC_X, LOC_Y)) |>
      filter(!is.na(zone)) |>
      summarise(lx = median(LOC_X), ly = median(LOC_Y), .by = zone)
  }
  .zone_anchor_cache[[season]]
}

#' Zone chart for one player, coloured by the 10-zone model in R/zone_model.R.
#'
#' @param player   PLAYER_ID, or a PLAYER_NAME matched exactly.
#' @param season   e.g. "2025-26".
#' @param colour_by "pps" (default) shades each zone by shrunk points per shot. A colour
#'   ramp on a court is read as efficiency whatever the legend says, so the default has to
#'   mean efficiency. "contribution" shades by the zone's contribution to the selection
#'   score instead, which is the Section 7 mismatch story but reads backwards on a court:
#'   a player's best zone renders darkest red when he is underweight there.
zone_chart <- function(player, season, colour_by = c("pps", "contribution")) {
  colour_by <- match.arg(colour_by)
  zs <- read_zones(season)

  row <- if (is.numeric(player)) filter(zs, PLAYER_ID == player) else filter(zs, PLAYER_NAME == player)
  if (nrow(row) == 0) stop(glue("no qualifying player matched '{player}' in {season}"), call. = FALSE)
  if (n_distinct(row$PLAYER_ID) > 1) {
    stop(glue("'{player}' matched {n_distinct(row$PLAYER_ID)} players; pass a PLAYER_ID"), call. = FALSE)
  }
  pid  <- row$PLAYER_ID[1]
  name <- row$PLAYER_NAME[1]

  shots <- read_parquet(glue("data/raw/shots/season={season}/shots.parquet")) |>
    filter(PLAYER_ID == pid) |>
    mutate(zone = classify_zone(LOC_X, LOC_Y)) |>
    filter(!is.na(zone)) |>
    inner_join(select(row, zone, zone_value, pps_shrunk, score_contrib, shot_freq, attempts),
               by = "zone") |>
    filter(zone_value == if_else(SHOT_TYPE == "3PT Field Goal", 3, 2))

  # The join above matched on zone ids that were retired on 2026-08-27, and produced an
  # empty, entirely plausible-looking chart rather than an error. Fail loudly instead.
  if (nrow(shots) == 0) {
    stop(glue("{name}, {season}: no shots survived the zone join. The chart would render ",
              "empty rather than wrong, which is why this stops."), call. = FALSE)
  }

  fill_col <- if (colour_by == "contribution") "score_contrib" else "pps_shrunk"
  labels <- row |>
    left_join(zone_anchors(season), by = "zone") |>
    mutate(txt = glue("{sprintf('%.2f', pps_shrunk)} PPS\n{sprintf('%.1f', 100 * shot_freq)}%  ({attempts})"))

  scale_fill <- if (colour_by == "contribution") {
    scale_colour_gradient2(low = WARM, mid = NEUTRAL, high = COOL, midpoint = 0,
                           name = "Contribution to\nselection score",
                           labels = \(x) sprintf("%+.3f", x))
  } else {
    scale_colour_gradient(low = NEUTRAL, high = COOL, name = "Shrunk PPS",
                          labels = \(x) sprintf("%.2f", x))
  }

  ggplot(shots, aes(LOC_X, LOC_Y)) +
    court_layer() +
    geom_point(aes(colour = .data[[fill_col]]), size = 1.5, alpha = 0.85) +
    geom_label(aes(lx, ly, label = txt), data = labels, inherit.aes = FALSE,
               size = 2.1, lineheight = 0.95, label.size = 0, label.padding = unit(0.1, "lines"),
               fill = alpha("white", 0.78), colour = "grey15") +
    scale_fill +
    coord_fixed(xlim = c(-250, 250), ylim = c(-55, 400), expand = FALSE) +
    labs(
      title = glue("{name} — shot zones, {season}"),
      subtitle = paste("Each point is a field goal attempt, coloured by its zone's",
                       if (colour_by == "contribution") "contribution to the selection score."
                       else "shrunk points per shot.",
                       "\nLabels show shrunk PPS, then share of the player's attempts with the raw count.",
                       glue("Zones are the {length(ZONE_IDS)}-zone model, computed from",
                            " shot coordinates.")),
      x = NULL, y = NULL
    ) +
    theme_shots() +
    theme(axis.text = element_blank(), panel.grid = element_blank(),
          legend.position = "right", legend.key.height = unit(1.1, "cm"),
          legend.title = element_text(size = 8), legend.text = element_text(size = 7))
}
