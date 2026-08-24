library(tidyverse)
library(arrow)
library(glue)
library(svglite)
library(ggrepel)

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

# Court outline in NBA shot-chart units: tenths of a foot, hoop at the origin. This is a
# visual reference only. Section 12 rejects derived zone geometry, and nothing here
# classifies anything -- every zone label comes from the NBA's own columns.
court_layer <- function(colour = "grey45", linewidth = 0.35) {
  arc <- function(r, from, to, n = 200) {
    t <- seq(from, to, length.out = n)
    tibble(x = r * cos(t), y = r * sin(t))
  }
  three_arc <- arc(237.5, acos(220 / 237.5), pi - acos(220 / 237.5))
  list(
    annotate("path", x = arc(7.5, 0, 2 * pi)$x, y = arc(7.5, 0, 2 * pi)$y,
             colour = colour, linewidth = linewidth),
    annotate("segment", x = -30, xend = 30, y = -7.5, yend = -7.5,
             colour = colour, linewidth = linewidth),
    annotate("rect", xmin = -80, xmax = 80, ymin = -52.5, ymax = 137.5,
             fill = NA, colour = colour, linewidth = linewidth),
    annotate("path", x = arc(40, 0, pi)$x, y = arc(40, 0, pi)$y,
             colour = colour, linewidth = linewidth),
    annotate("segment", x = c(-220, 220), xend = c(-220, 220),
             y = -52.5, yend = 89.5, colour = colour, linewidth = linewidth),
    annotate("path", x = three_arc$x, y = three_arc$y, colour = colour, linewidth = linewidth),
    annotate("segment", x = -250, xend = 250, y = -52.5, yend = -52.5,
             colour = colour, linewidth = linewidth)
  )
}

# Label anchors come from league-wide shot positions so every player's chart puts each
# zone's label in the same place, including zones where the player never shot.
.zone_anchor_cache <- new.env(parent = emptyenv())
zone_anchors <- function(season) {
  if (is.null(.zone_anchor_cache[[season]])) {
    .zone_anchor_cache[[season]] <- read_parquet(
      glue("data/raw/shots/season={season}/shots.parquet")) |>
      filter(SHOT_ZONE_BASIC != "Backcourt", SHOT_ZONE_AREA != "Back Court(BC)") |>
      mutate(zone = str_c(SHOT_ZONE_BASIC, " | ", SHOT_ZONE_AREA)) |>
      summarise(lx = median(LOC_X), ly = median(LOC_Y), .by = zone)
  }
  .zone_anchor_cache[[season]]
}

#' Zone chart for one player, coloured by the NBA's own 14-zone classification.
#'
#' @param player   PLAYER_ID, or a PLAYER_NAME matched exactly.
#' @param season   e.g. "2025-26".
#' @param colour_by "contribution" shades each zone by its contribution to the selection
#'   score, which is the mismatch story Section 7 stores per cell. "pps" shades by shrunk
#'   points per shot instead.
zone_chart <- function(player, season, colour_by = c("contribution", "pps")) {
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
    filter(PLAYER_ID == pid,
           SHOT_ZONE_BASIC != "Backcourt", SHOT_ZONE_AREA != "Back Court(BC)") |>
    mutate(zone = str_c(SHOT_ZONE_BASIC, " | ", SHOT_ZONE_AREA)) |>
    inner_join(select(row, zone, zone_value, pps_shrunk, score_contrib, shot_freq, attempts),
               by = "zone") |>
    filter(zone_value == if_else(SHOT_TYPE == "3PT Field Goal", 3, 2))

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
                       "Zones are the NBA's own 14."),
      x = NULL, y = NULL
    ) +
    theme_shots() +
    theme(axis.text = element_blank(), panel.grid = element_blank(),
          legend.position = "right", legend.key.height = unit(1.1, "cm"),
          legend.title = element_text(size = 8), legend.text = element_text(size = 7))
}
