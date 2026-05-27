library(ggplot2)
library(dplyr)
library(gt)
library(scales)
library(patchwork)

# =============================================================================
# R-figure conventions (project-wide)
# =============================================================================
#
# Output device: chart chunks render as external SVG files via
# `dev = "svglite"` (set in R/setup.R), which Quarto then wraps in
# `<img src="…svg">`. This is what makes dark-mode re-skin possible —
# see the "Dark-mode mechanism" note below.
#
# Default dimensions: chart chunks use `fig.width=5, fig.height=5` (square)
# in side-by-side columns; full-width R figures use `fig.width=7`. `dpi`
# is harmless and ignored by svglite, so existing chunk options can stay.
#
# fig-cap vs caption-in-image:
#   - Prefer `#| fig-cap: "..."` on the chunk and let Quarto render the
#     caption below the figure as plain HTML. This keeps the caption text
#     searchable, translatable, and screen-reader accessible.
#   - Only bake a caption *into* the image bitmap when the source PDF does
#     and faithfulness to the original matters more than accessibility.
#
# Alt-text + lightbox:
#   - For R-generated figures inside chunks, Quarto emits the chunk's
#     `fig-cap` as both caption and (when wrapped in figure markup) alt
#     attribute. No extra work needed.
#   - For PNGs referenced via Markdown `![cap](url)`, Quarto drops the alt
#     attribute unless you add `{.lightbox}` to the image. This is a known
#     Quarto quirk with no workaround short of switching to a figure div.
#
# Theme colour tokens:
#   - CHART_FG ("black"): axis text, ticks, axis line. Black on white is
#     the light-mode appearance; under dark mode the page-level CSS
#     `filter: invert(1) hue-rotate(180deg)` (see "Dark-mode mechanism"
#     below) flips it to near-white against the dark page.
#   - CHART_GRID ("#808080"): major gridlines. Picked so the same single
#     colour clears WCAG 1.4.11 (3:1 contrast for essential non-text
#     graphics) on both light (#fff, 3.95:1) and Darkly (~#222, 3.51:1)
#     backgrounds. The invert filter takes #808080 → #7f7f7f — near
#     symmetric — so the contrast survives the round-trip.
#   - CHART_GRID_FAINT ("#cccccc"): minor gridlines. Inverts to #333 on
#     dark, which is faint against #222 — minor gridlines are decorative
#     by design and reading them is not load-bearing.
#   - CHART_LINE_COLOUR ("#ed0000"): the data ink. invert + hue-rotate
#     round-trips this back to a near-identical red on both modes.
#   - CONTROL_LIMIT_COLOUR ("blue"): control limit lines and labels.
#     Same round-trip — stays blue on both modes.
#
# Dark-mode mechanism:
#   - svglite emits SVGs that Quarto embeds as `<img src="…svg">`. Img-
#     wrapped SVG renders in an isolated context that the parent
#     document's CSS selectors cannot reach (no `svg text { fill: … }`
#     trick available). We therefore use a CSS *filter* instead, applied
#     to the img element: `filter: invert(1) hue-rotate(180deg)`. Invert
#     flips brightness (black ink ↔ light ink, transparent bg stays
#     transparent so the dark page shows through); the 180° hue-rotate
#     cancels the chromatic flip that invert introduces, so red stays
#     red and blue stays blue.
#   - The filter lives in assets/styles/main.css under the
#     `body.quarto-dark .cell-output-display img[src$=".svg"]` selector.
#   - Single-asset path: each chart renders once, both modes share the
#     file. No per-mode render branch, no doubled assets.
#
# Adding a new chart function:
#   1. Apply `run_chart_theme()` (or a sibling theme helper) for the axis
#      treatment so dark-mode parity is automatic.
#   2. Use the named constants above for any ink the function adds itself.
#   3. If a chart genuinely needs different ink colours per mode, accept
#      that this is the option-(a) dual-render path (per issue #309) —
#      that path is not yet built; raise a follow-up issue.
#
# =============================================================================

# --- Named constants ---

CHART_FG             <- "black"
CHART_GRID           <- "#808080"
CHART_GRID_FAINT     <- "#cccccc"
CHART_LINE_COLOUR    <- "#ed0000"
CONTROL_LIMIT_COLOUR <- "blue"

# --- Run charts ---

#' Create a minimal ggplot2 theme for run charts
#'
#' Returns a theme with mid-grey gridlines (suppressible), no axis titles,
#' transparent plot/panel backgrounds (so the surrounding page colour shows
#' through in either light or dark mode), and a configurable right margin
#' (increased when horizontal reference lines have labels).
#'
#' Axis ink uses CHART_FG ("black"), which svglite emits without an
#' inline fill/stroke declaration so dark-mode CSS can re-skin it without
#' !important. See the conventions block at the top of this file.
#'
#' @param right_margin Numeric. Right margin in points. Default 5; use ~30
#'   when horizontal line labels are present.
#' @param gridlines Character. \code{"full"} (default) draws the Day 2 / Day 3
#'   technical-aid grid: major y, major x, faint minor y. \code{"none"}
#'   suppresses every gridline (used for charts where Neave drew clean axes
#'   without grid paper, e.g. the "favourite example" charts on Day 3 page 21).
#' @return A ggplot2 theme object.
run_chart_theme <- function(right_margin = 5, gridlines = c("full", "none")) {
  gridlines <- match.arg(gridlines)
  base <- theme_minimal(base_size = 14) +
    theme(
      panel.background   = element_rect(fill = "transparent", colour = NA),
      plot.background    = element_rect(fill = "transparent", colour = NA),
      plot.margin        = margin(5, right_margin, 5, 5),
      axis.ticks.y = element_line(color = CHART_FG),
      axis.ticks.x = element_blank(),
      axis.text.y  = element_text(color = CHART_FG, size = 16),
      axis.text.x  = element_text(color = CHART_FG, size = 14),
      axis.title   = element_blank(),
      axis.line.y  = element_line(color = CHART_FG, linewidth = 1),
      axis.line.x  = element_blank()
    )

  if (gridlines == "full") {
    base + theme(
      panel.grid.major.y = element_line(color = CHART_GRID, linewidth = .8),
      panel.grid.major.x = element_line(color = CHART_GRID, linewidth = 1.2),
      panel.grid.minor.y = element_line(color = CHART_GRID_FAINT, linewidth = .3),
      panel.grid.minor.x = element_blank()
    )
  } else {
    base + theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )
  }
}

#' Plot a run chart (time series line graph)
#'
#' Draws a run chart connecting sequential values with a coloured line.
#' Optionally adds horizontal reference lines (control limits) and a thin
#' Central Line at the process average.
#'
#' @param values Numeric vector. The data values to plot in order.
#' @param line_width Numeric. Width of the plotted line. Default 6.
#' @param y_limits Numeric vector of length 2. Y-axis range. Default c(10, 25).
#' @param y_breaks Numeric vector. Major y-axis tick positions.
#' @param y_minor_breaks Numeric vector. Minor y-axis tick positions.
#' @param hlines Numeric vector or NULL. Y-intercepts for horizontal reference
#'   lines (e.g. control limits).
#' @param hline_labels Character vector or NULL. Labels for the horizontal
#'   lines, anchored according to \code{hline_label_side} and offset
#'   vertically by \code{hline_label_offset}.
#' @param hline_label_side Character. \code{"right"} (default) anchors hline
#'   labels at the right edge of the chart (existing Red Beads convention);
#'   \code{"left"} anchors them at the left edge (Neave's convention for the
#'   "favourite example" control chart on Day 3 page 21, where the limit
#'   value sits inside the chart near the start of each blue line).
#' @param hline_label_offset Numeric (scalar or vector). Vertical offset
#'   applied to each hline label, in y-axis units. Positive places the label
#'   above its line, negative below. Default 1.2 (above, current Red Beads
#'   behaviour). Pass a vector to position different labels above/below
#'   independently.
#' @param central_line Numeric or NULL. If given, draws a thin blue line at
#'   this y-intercept — Shewhart's Central Line at the process average.
#'   Neave introduces the Central Line on Day 3 page 11 and adopts it as
#'   standard practice from that point onward.
#' @param y_label_fn Function or NULL. If given, applied to the y-axis tick
#'   labels (e.g. \code{scales::label_percent(accuracy = 1)} for the
#'   "favourite example" proportion-defective charts).
#' @param gridlines Character. Passed through to \code{run_chart_theme}.
#'   \code{"full"} (default) or \code{"none"}.
#' @param show_x_labels Logical. If TRUE (default), draw the sequence position
#'   under each point (the Day 2 Red Beads convention). If FALSE, suppress
#'   x-axis labels — Neave omits them on Day 3 page 7 and page 21, where
#'   the values' sequence position carries no independent meaning.
#' @param x_breaks Integer vector or NULL. Major tick positions along the
#'   x-axis. If NULL (default), uses \code{seq_along(values)} — one tick at
#'   every data-point, matching the Day 2 Red Beads convention. Override
#'   with a sparser sequence (e.g. \code{seq(3, 48, by = 3)}) on long charts
#'   where labelling every point would be unreadable — Neave does this on
#'   the Day 3 page 30 individual A3–F3 charts (48 points each).
#' @param hline_colour Character. Colour for the \code{hlines} and their
#'   labels. Defaults to \code{CONTROL_LIMIT_COLOUR} (blue). Override
#'   for Neave's Day 3 page 15 contrast where the standard-deviation limits
#'   are drawn in magenta to distinguish them from the moving-range limits
#'   on the same data. Pure magenta (\code{"magenta"} / \code{"#ff00ff"})
#'   round-trips through the dark-mode invert+hue-rotate filter cleanly.
#' @return A ggplot2 object containing the run chart.
#' @examples
#' run_chart_plot(c(13, 19, 18, 14, 16))
#' run_chart_plot(c(9, 11, 8, 14), hlines = c(5, 15), hline_labels = c("LCL", "UCL"))
run_chart_plot <- function(values, line_width = 6,
                           y_limits = c(10, 25),
                           y_breaks = seq(10, 25, by = 5),
                           y_minor_breaks = seq(10, 25, by = 1),
                           hlines = NULL, hline_labels = NULL,
                           hline_label_side = c("right", "left"),
                           hline_label_offset = 1.2,
                           central_line = NULL,
                           y_label_fn = NULL,
                           gridlines = c("full", "none"),
                           show_x_labels = TRUE,
                           x_breaks = NULL,
                           hline_colour = CONTROL_LIMIT_COLOUR) {
  stopifnot(is.numeric(values), length(values) >= 2)
  hline_label_side <- match.arg(hline_label_side)
  gridlines <- match.arg(gridlines)

  df <- data.frame(x = seq_along(values), y = values)
  right_margin <- if (!is.null(hlines) && hline_label_side == "right") 30 else 5

  y_scale_args <- list(
    limits = y_limits, breaks = y_breaks,
    minor_breaks = y_minor_breaks, expand = c(0, 0)
  )
  if (!is.null(y_label_fn)) y_scale_args$labels <- y_label_fn

  x_breaks_resolved <- if (is.null(x_breaks)) seq_along(values) else x_breaks

  p <- ggplot(df, aes(x, y)) +
    scale_x_continuous(breaks = x_breaks_resolved, expand = c(0, 0)) +
    do.call(scale_y_continuous, y_scale_args) +
    run_chart_theme(right_margin = right_margin, gridlines = gridlines)

  if (!show_x_labels) {
    p <- p + theme(axis.text.x = element_blank())
  }

  # Central Line first so it sits visually below the data line.
  if (!is.null(central_line)) {
    p <- p + geom_hline(yintercept = central_line,
                        color = CONTROL_LIMIT_COLOUR, linewidth = 0.4)
  }

  # Data line on top of CL but below the (thicker) control limits.
  p <- p + geom_line(colour = CHART_LINE_COLOUR, linewidth = line_width, linejoin = "round")

  if (!is.null(hlines)) {
    offsets <- rep_len(hline_label_offset, length(hlines))
    label_x <- if (hline_label_side == "right") length(values) else 1
    label_hjust <- if (hline_label_side == "right") 1 else 0
    for (i in seq_along(hlines)) {
      p <- p + geom_hline(yintercept = hlines[i], color = hline_colour, linewidth = 1)
      if (!is.null(hline_labels) && !is.na(hline_labels[i])) {
        p <- p + annotate("text", x = label_x,
                          y = hlines[i] + offsets[i],
                          label = hline_labels[i],
                          hjust = label_hjust,
                          vjust = if (offsets[i] >= 0) 0 else 1,
                          color = hline_colour, size = 7, fontface = "bold")
      }
    }
  }
  p
}

#' Compute MR-based Shewhart limits for a sequence of individual values
#'
#' Returns a list with \code{central} (mean), \code{lcl}, and \code{ucl}
#' computed from the average moving range: limits = mean ± 2.66 * MR̄.
#' This is Shewhart's individuals-chart formula as Neave presents it
#' on Day 3 page 13 (Technical Aid 8).
#'
#' Note: \code{lcl} may be negative for non-negative or count-bounded
#' processes with a low mean (e.g. Process C red beads on Day 3 page 19).
#' This matches Neave's presentation — he draws the LCL where the formula
#' puts it and lets ggplot clip it against the panel's \code{y_limits}.
#' Callers needing a domain-specific floor (\code{max(0, lcl)} for counts,
#' etc.) should apply it themselves.
#'
#' @param values Numeric vector of individual observations.
#' @return Named list with components \code{central}, \code{lcl}, \code{ucl}.
mr_limits <- function(values) {
  mr_bar <- mean(abs(diff(values)))
  mu     <- mean(values)
  list(central = mu,
       lcl     = mu - 2.66 * mr_bar,
       ucl     = mu + 2.66 * mr_bar)
}

#' Compose a 6×2 panel of small control charts (Day 3 page 19)
#'
#' Renders Neave's "Six Processes" composite — twelve small individuals
#' charts arranged as six pairs (A1/A2 ... F1/F2). Each panel computes
#' its own MR-based control limits and central line from its own data,
#' then renders a thin-line run chart with title above and no x-axis
#' labels (the sequence position carries no independent meaning at this
#' scale — only the *shape* matters).
#'
#' Reused by Day 3.06 (this 6×2 grid) and by Day 3.09 (the extended A3–F3
#' panel of 48-point charts with limits from the first 24).
#'
#' @param processes Named list. Each entry must contain \code{data}
#'   (numeric vector), \code{label} (chart title), \code{y_limits} and
#'   \code{y_breaks}. \code{y_minor_breaks} is optional. Layout follows
#'   list order, filling rows first.
#' @param ncol Integer. Columns in the composed panel. Default 2.
#' @param chart_line_width Numeric. Thinner line for small panels.
#'   Default 1.2.
#' @return A patchwork object combining all panels.
six_processes_panel <- function(processes, ncol = 2,
                                chart_line_width = 1.2) {
  charts <- lapply(processes, function(p) {
    lims <- mr_limits(p$data)
    minor <- if (!is.null(p$y_minor_breaks)) p$y_minor_breaks else p$y_breaks
    run_chart_plot(
      values         = p$data,
      line_width     = chart_line_width,
      y_limits       = p$y_limits,
      y_breaks       = p$y_breaks,
      y_minor_breaks = minor,
      hlines         = c(lims$lcl, lims$ucl),
      central_line   = lims$central,
      show_x_labels  = FALSE
    ) +
      ggtitle(p$label) +
      theme(plot.title    = element_text(hjust = 0.5, face = "bold",
                                         size = 14, colour = CHART_FG),
            plot.margin   = margin(4, 8, 4, 4),
            axis.text.y   = element_text(size = 10, colour = CHART_FG))
  })
  patchwork::wrap_plots(charts, ncol = ncol)
}

#' Compose a six-row stack of extended A3–F3 control charts (Day 3 page 23)
#'
#' For each process letter L in \code{pairs} (default A–F), concatenates the
#' L1 and L2 data from \code{processes} into a single 48-point series,
#' computes MR-based control limits from the *first 24 points only* (the L1
#' half — when the process was in statistical control), and renders all 48
#' points with those earlier limits *extended unchanged into the future*.
#'
#' This is the pedagogical companion to \code{six_processes_panel}: there the
#' control limits are recomputed from each half's own data, so the
#' out-of-control half's limits drift outward to accommodate the contamination.
#' Here the limits stay fixed at the stable-period values, so the signals of
#' instability in the second half show through more strongly — Neave's main
#' point on page 22: "leave the control limits alone if you have no good
#' reason for changing them".
#'
#' Labels are auto-generated as "<letter>3" (A3, B3, ...) since the extended
#' chart is always the third in the series for each process.
#'
#' @param processes Named list (as accepted by \code{six_processes_panel})
#'   containing both halves for each process — entries keyed
#'   \code{<letter>1} and \code{<letter>2} (e.g. \code{A1}, \code{A2}). The
#'   \code{y_limits}, \code{y_breaks}, and (optional) \code{y_minor_breaks}
#'   are read from the L1 entry.
#' @param pairs Character vector. Letters identifying which pairs to combine.
#'   Default \code{c("A", "B", "C", "D", "E", "F")}.
#' @param chart_line_width Numeric. Thinner line for stacked panels. Default
#'   1.0 — slightly thinner than \code{six_processes_panel} since each panel
#'   now carries twice as many points.
#' @return A patchwork object: a single column of six panels.
six_processes_extended_panel <- function(processes,
                                         pairs = c("A","B","C","D","E","F"),
                                         chart_line_width = 1.0) {
  charts <- lapply(pairs, function(letter) {
    p1 <- processes[[paste0(letter, "1")]]
    p2 <- processes[[paste0(letter, "2")]]
    stopifnot(!is.null(p1), !is.null(p2))

    combined <- c(p1$data, p2$data)
    lims     <- mr_limits(p1$data)
    minor    <- if (!is.null(p1$y_minor_breaks)) p1$y_minor_breaks else p1$y_breaks

    run_chart_plot(
      values         = combined,
      line_width     = chart_line_width,
      y_limits       = p1$y_limits,
      y_breaks       = p1$y_breaks,
      y_minor_breaks = minor,
      hlines         = c(lims$lcl, lims$ucl),
      central_line   = lims$central,
      gridlines      = "none",
      show_x_labels  = FALSE
    ) +
      ggtitle(paste0(letter, "3")) +
      theme(plot.title  = element_text(hjust = 0.5, face = "bold",
                                       size = 14, colour = CHART_FG),
            plot.margin = margin(4, 8, 4, 4),
            axis.text.y = element_text(size = 10, colour = CHART_FG))
  })
  patchwork::wrap_plots(charts, ncol = 1)
}

#' Render a single A3–F3 control chart with numbered x-axis (Day 3 page 30)
#'
#' Builds one of the six "individual" extended charts that Neave reproduces
#' larger on page 30 of Day 3, where the prose discusses specific point
#' numbers ("Point 31 drops onto the LCL ...", "Point 45 onward ...").
#' Structurally identical to a single row of \code{six_processes_extended_panel}:
#' concatenates L1 + L2 into 48 points, computes MR limits from the L1 half
#' only, and extends those limits across all 48. The two differences are:
#' x-axis labels are visible (so prose can reference specific point numbers),
#' and the figure is rendered at a larger size with a sparser tick spacing
#' (every third point — labelling all 48 would be unreadable).
#'
#' @param processes Named list (as accepted by \code{six_processes_panel})
#'   containing both halves for each process — entries keyed
#'   \code{<letter>1} and \code{<letter>2}. The \code{y_limits},
#'   \code{y_breaks}, and (optional) \code{y_minor_breaks} are read from the
#'   L1 entry.
#' @param letter Single character identifying the process (e.g. \code{"A"}).
#' @param line_width Numeric. Default 1.4 — between the stacked-panel default
#'   (1.0) and the Day 2 Red Beads default (6); reads cleanly at the larger
#'   per-chart size used on page 30.
#' @param x_breaks_by Integer. Spacing between x-axis ticks. Default 3, which
#'   matches Neave's printed page 30 layout: ticks at 3, 6, 9, ..., 48.
#' @return A ggplot2 object — a single 48-point chart with extended limits.
individual_process_chart <- function(processes, letter,
                                     line_width = 1.4,
                                     x_breaks_by = 3) {
  p1 <- processes[[paste0(letter, "1")]]
  p2 <- processes[[paste0(letter, "2")]]
  stopifnot(!is.null(p1), !is.null(p2))

  combined <- c(p1$data, p2$data)
  lims     <- mr_limits(p1$data)
  minor    <- if (!is.null(p1$y_minor_breaks)) p1$y_minor_breaks else p1$y_breaks

  run_chart_plot(
    values         = combined,
    line_width     = line_width,
    x_breaks       = seq(x_breaks_by, length(combined), by = x_breaks_by),
    y_limits       = p1$y_limits,
    y_breaks       = p1$y_breaks,
    y_minor_breaks = minor,
    hlines         = c(lims$lcl, lims$ucl),
    central_line   = lims$central,
    gridlines      = "none",
    show_x_labels  = TRUE
  ) +
    ggtitle(paste0(letter, "3")) +
    theme(plot.title  = element_text(hjust = 0.5, face = "bold",
                                     size = 16, colour = CHART_FG),
          plot.margin = margin(4, 12, 4, 4),
          axis.text.x = element_text(size = 11, colour = CHART_FG),
          axis.text.y = element_text(size = 11, colour = CHART_FG))
}

#' Plot the Funnel Experiment "track"
#'
#' Draws the one-dimensional Funnel Experiment track from
#' \code{x_min} to \code{x_max} (default 20-40) as a horizontal row of
#' square cells with alternating green/yellow fills and red borders.
#' Each cell carries its position number in bold serif. The
#' \code{target} square (default 30) is overlaid with a dark
#' bullseye-style marker — the "target-point" of the silly game on
#' [Day 3.10](../../../content/days/day-03/10-introduction-to-the-funnel-experiment.qmd).
#'
#' Two optional markers float just above the track:
#' \itemize{
#'   \item \code{funnel_pos} — blue downward triangle on a short stick,
#'     marking where the funnel was placed.
#'   \item \code{marble_pos} — yellow filled circle, marking where the
#'     marble came to rest.
#' }
#' Either or both may be \code{NULL} (the default) to produce the
#' "basic" empty track.
#'
#' @param funnel_pos Numeric or NULL. Track position of the funnel
#'   marker. Default \code{NULL}.
#' @param marble_pos Numeric or NULL. Track position of the marble
#'   marker. Default \code{NULL}.
#' @param x_min,x_max Numeric. Inclusive range of track positions.
#'   Default 20 to 40.
#' @param target Numeric. Position of the highlighted target square.
#'   Default 30.
#' @return A ggplot2 object.
funnel_track_plot <- function(funnel_pos = NULL,
                              marble_pos = NULL,
                              x_min = 20,
                              x_max = 40,
                              target = 30) {
  stopifnot(x_min < x_max, target >= x_min, target <= x_max)
  if (!is.null(funnel_pos)) {
    stopifnot(funnel_pos >= x_min, funnel_pos <= x_max)
  }
  if (!is.null(marble_pos)) {
    stopifnot(marble_pos >= x_min, marble_pos <= x_max)
  }

  positions <- seq(x_min, x_max)
  track_df  <- data.frame(
    x         = positions,
    fill      = ifelse(positions %% 2 == 0, "#4caf50", "#fff176"),
    is_target = positions == target
  )

  border_colour <- "#d32f2f"
  number_size   <- 7

  p <- ggplot() +
    geom_tile(
      data     = track_df,
      mapping  = aes(x = .data$x, y = 0, fill = .data$fill),
      width    = 1, height = 1,
      colour   = border_colour, linewidth = 0.9
    ) +
    scale_fill_identity() +
    geom_text(
      data     = subset(track_df, !track_df$is_target),
      mapping  = aes(x = .data$x, y = 0, label = .data$x),
      family   = "serif", fontface = "bold",
      size     = number_size, colour = CHART_FG
    ) +
    annotate("point", x = target, y = 0,
             shape = 21, size = 12,
             fill = "#1a237e", colour = border_colour, stroke = 1.2) +
    annotate("text", x = target, y = 0, label = as.character(target),
             family = "serif", fontface = "bold",
             size = number_size - 1, colour = border_colour) +
    coord_fixed(ratio = 1, clip = "off") +
    scale_x_continuous(limits = c(x_min - 0.6, x_max + 0.6), expand = c(0, 0)) +
    scale_y_continuous(limits = c(-0.7, 1.6), expand = c(0, 0)) +
    theme_void() +
    theme(plot.background  = element_rect(fill = "transparent", colour = NA),
          panel.background = element_rect(fill = "transparent", colour = NA),
          plot.margin      = margin(2, 2, 2, 2))

  if (!is.null(funnel_pos)) {
    p <- p +
      annotate("segment", x = funnel_pos, xend = funnel_pos,
               y = 0.55, yend = 1.25,
               colour = "#1565c0", linewidth = 1) +
      annotate("point", x = funnel_pos, y = 0.7,
               shape = 25, size = 7,
               fill = "#1565c0", colour = "#1565c0")
  }

  if (!is.null(marble_pos)) {
    p <- p +
      annotate("point", x = marble_pos, y = 0.85,
               shape = 21, size = 6,
               fill = "#fbc02d", colour = CHART_FG, stroke = 0.6)
  }

  p
}

#' Plot the Funnel Experiment "dice sequences" fallback table
#'
#' Draws Neave's two pre-recorded dice-throw sequences (Seq. A and Seq. B)
#' provided on Day 3 page 37 as a fallback for any reader without
#' physical dice. Each sequence runs from Stage 6 through Stage 40 — both
#' begin at Stage 6 because Neave supplies the first five stages
#' separately for demonstration purposes. Each entry is a *pair* of
#' dice values (one for each of two dice), shown as a comma-separated
#' numeric pair (e.g. "6,4") so the output matches Neave's printed table
#' verbatim.
#'
#' The table is split across two horizontal blocks to stay legible at
#' page width — Stages 6–23 in the upper block, Stages 24–40 in the
#' lower block — matching Neave's printed layout.
#'
#' Implementation note — pair representation: an initial pass tried the
#' Unicode dice glyphs (U+2680..U+2685, ⚀⚁⚂⚃⚄⚅) so the table would read
#' as a glyph grid. Those glyphs only live in specialty symbol fonts
#' (e.g. Apple Symbols on macOS, DejaVu Sans on Linux distributions that
#' include it) and rendered as tofu boxes through svglite on a CI Ubuntu
#' image without the right font installed. Adding a font-loading
#' dependency (showtext / ggimage) for what is fundamentally a fallback
#' figure that the reader can ignore if they have physical dice did not
#' carry its own weight. Numeric pairs are also Neave's own choice in
#' the printed PDF, so this is both portable and source-faithful.
#'
#' @param stages_per_block Integer. How many stages occupy each
#'   horizontal block. Default 18 (matching Neave's printed layout
#'   of 18 + 17 stages across the two blocks; the last block holds
#'   whatever remains).
#' @return A ggplot2 object — a single figure containing both blocks
#'   stacked vertically.
#' @examples
#' funnel_dice_sequences_plot()
funnel_dice_sequences_plot <- function(stages_per_block = 18) {
  # Neave's two recorded sequences, Stages 6 through 40 inclusive.
  # Each entry is a (die-1, die-2) pair.
  seq_a <- list(
    c(6,4), c(2,4), c(4,5), c(4,5), c(1,3), c(5,6), c(6,3), c(3,5),
    c(6,4), c(3,5), c(2,2), c(5,2), c(4,2), c(2,4), c(6,6), c(4,6),
    c(5,3), c(4,3),
    c(2,5), c(6,3), c(5,6), c(6,3), c(5,1), c(6,1), c(2,1), c(2,2),
    c(3,6), c(5,3), c(6,6), c(5,3), c(4,6), c(6,5), c(3,4), c(3,6),
    c(5,6)
  )
  seq_b <- list(
    c(3,5), c(3,6), c(4,4), c(1,3), c(1,1), c(4,1), c(5,3), c(1,6),
    c(4,5), c(1,2), c(5,4), c(1,4), c(6,1), c(1,2), c(1,3), c(5,4),
    c(6,5), c(6,1),
    c(4,3), c(6,6), c(1,5), c(6,3), c(4,4), c(5,2), c(4,4), c(1,4),
    c(6,1), c(3,2), c(5,5), c(5,6), c(6,2), c(1,3), c(4,6), c(6,3),
    c(3,1)
  )

  stages <- 6:40
  stopifnot(length(seq_a) == length(stages),
            length(seq_b) == length(stages))

  pair_text <- function(pair) paste0(pair[1], ",", pair[2])

  # Split into two horizontal blocks. First block = stages_per_block stages;
  # second block = whatever remains.
  block1_idx <- seq_len(min(stages_per_block, length(stages)))
  block2_idx <- setdiff(seq_along(stages), block1_idx)

  # Cell-width tuning: each row's first cell is the row label ("Stage",
  # "Seq. A", "Seq. B"), which is wider than a dice-pair cell. Widening
  # the label tile and shifting all data tiles right by the same amount
  # keeps the columns aligned cleanly with no overlap.
  label_width <- 2.2
  data_width  <- 1.3
  label_x     <- 0
  first_x     <- label_x + (label_width + data_width) / 2

  build_block <- function(idx, block_y) {
    # block_y is the vertical centre of this block group; we use 3 rows:
    # block_y + 1 = "Stage" header, block_y = Seq. A, block_y - 1 = Seq. B.
    n <- length(idx)
    x <- first_x + (seq_len(n) - 1) * data_width
    data.frame(
      x      = c(label_x, x, label_x, x, label_x, x),
      y      = c(rep(block_y + 1, n + 1),
                 rep(block_y,     n + 1),
                 rep(block_y - 1, n + 1)),
      label  = c("Stage", as.character(stages[idx]),
                 "Seq. A", vapply(seq_a[idx], pair_text, character(1)),
                 "Seq. B", vapply(seq_b[idx], pair_text, character(1))),
      role   = c("header", rep("stage", n),
                 "header", rep("dice",  n),
                 "header", rep("dice",  n)),
      width  = c(label_width, rep(data_width, n),
                 label_width, rep(data_width, n),
                 label_width, rep(data_width, n)),
      stringsAsFactors = FALSE
    )
  }

  block1 <- build_block(block1_idx, block_y = 4)   # upper block
  block2 <- build_block(block2_idx, block_y = 0)   # lower block
  df <- rbind(block1, block2)
  df$height <- 1.0

  dice_df   <- df[df$role == "dice", ]
  stage_df  <- df[df$role == "stage", ]
  header_df <- df[df$role == "header", ]

  ggplot(df, aes(x = .data$x, y = .data$y)) +
    geom_tile(aes(width = .data$width, height = .data$height),
              fill = "white", colour = CHART_FG, linewidth = 0.8) +
    geom_text(data = header_df, aes(label = .data$label),
              fontface = "bold", family = "sans",
              size = 5, colour = CHART_FG) +
    geom_text(data = stage_df, aes(label = .data$label),
              family = "sans", size = 5, colour = CHART_FG) +
    geom_text(data = dice_df, aes(label = .data$label),
              family = "sans", size = 4.6, colour = CHART_FG) +
    coord_fixed(ratio = 1, clip = "off") +
    theme_void() +
    theme(plot.background  = element_rect(fill = "transparent", colour = NA),
          panel.background = element_rect(fill = "transparent", colour = NA),
          plot.margin      = margin(4, 4, 4, 4),
          legend.position  = "none")
}

#' Plot a Red Beads Experiment control chart
#'
#' Convenience wrapper around \code{run_chart_plot} pre-configured for Red
#' Beads data: y-axis 0-26, control limits at LCL and UCL.
#'
#' @param red_beads_vec Numeric vector. Red bead counts per round.
#' @param LCL Numeric. Lower control limit. Default 1.4.
#' @param UCL Numeric. Upper control limit. Default 18.2.
#' @return A ggplot2 object containing the control chart.
#' @examples
#' red_beads_control_chart(c(9, 11, 12, 7, 9, 13))
red_beads_control_chart <- function(red_beads_vec, LCL = 1.4, UCL = 18.2) {
  run_chart_plot(
    red_beads_vec, line_width = 2,
    y_limits = c(0, 26),
    y_breaks = seq(0, 25, by = 5),
    y_minor_breaks = seq(0, 25, by = 1),
    hlines = c(LCL, UCL),
    hline_labels = c("LCL", "UCL")
  )
}

# --- Histograms ---

#' Plot a counts-based histogram
#'
#' Draws a histogram of one numeric vector with configurable binning and
#' optional bin-count labels. Shares the same axis treatment as
#' \code{run_chart_plot} so light/dark mode parity is automatic.
#'
#' Downstream issues (#312, #313, #315) extract Day 3 / Optional Extras
#' histograms from PDF crops into R-generated figures; this is the helper
#' they will share.
#'
#' @param values Numeric vector. Raw observations to bin.
#' @param binwidth Numeric or NULL. Bin width. If NULL (default), ggplot2
#'   picks a sensible default via \code{stat_bin}'s heuristic.
#' @param boundary Numeric. Bin boundary alignment (e.g. \code{0} to align
#'   integer counts on whole numbers). Default 0.
#' @param show_counts Logical. If TRUE, render the bin count above each
#'   bar. Labels always show raw n even when \code{y_relative = TRUE}
#'   (raw counts read more naturally above a proportion-scaled bar than
#'   the proportion itself would). Default FALSE.
#' @param y_relative Logical. If TRUE, scale the Y axis to relative
#'   frequency (proportion) instead of raw counts. Default FALSE.
#' @param fill_colour Character. Bar fill colour. Default
#'   \code{CHART_LINE_COLOUR}.
#' @param x_breaks Numeric vector or NULL. Major x-axis tick positions.
#' @return A ggplot2 object containing the histogram.
#' @examples
#' histogram_plot(rnorm(200))
#' histogram_plot(c(0, 1, 1, 2), binwidth = 1, show_counts = TRUE)
histogram_plot <- function(values,
                           binwidth = NULL,
                           boundary = 0,
                           show_counts = FALSE,
                           y_relative = FALSE,
                           fill_colour = CHART_LINE_COLOUR,
                           x_breaks = NULL) {
  stopifnot(is.numeric(values), length(values) >= 1)

  df <- data.frame(value = values)

  y_aes <- if (y_relative) {
    aes(y = after_stat(count / sum(count)))
  } else {
    aes(y = after_stat(count))
  }

  p <- ggplot(df, aes(x = .data$value)) +
    geom_histogram(
      mapping = y_aes,
      binwidth = binwidth,
      boundary = boundary,
      closed = "left",
      fill = fill_colour,
      colour = CHART_FG,
      linewidth = 0.3
    )

  if (show_counts) {
    p <- p + stat_bin(
      mapping = if (y_relative) {
        aes(y = after_stat(count / sum(count)),
            label = after_stat(count))
      } else {
        aes(y = after_stat(count), label = after_stat(count))
      },
      binwidth = binwidth,
      boundary = boundary,
      closed = "left",
      geom = "text",
      vjust = -0.4,
      size = 4.5,
      colour = CHART_FG
    )
  }

  if (!is.null(x_breaks)) {
    p <- p + scale_x_continuous(breaks = x_breaks)
  }

  if (y_relative) {
    p <- p + scale_y_continuous(
      labels = scales::percent_format(accuracy = 1)
    )
  }

  p + run_chart_theme()
}

#' Plot a histogram with a smooth probability-density overlay
#'
#' Draws a bar histogram of \code{values} and overlays a smooth probability
#' density function (PDF) drawn from \code{pdf_fun}. The default \code{pdf_fun}
#' fits a normal distribution to \code{values} using \code{mean(values)} and
#' \code{sd(values)} — appropriate for the Part D body-temperature illustration
#' where Neave shows a sequence of histograms (rising sample size and rising
#' precision) converging visually to the underlying normal density.
#'
#' When \code{y_relative = FALSE} (raw counts) the PDF is rescaled by
#' \code{length(values) * binwidth} so that the curve and the histogram share
#' the same vertical scale: the area under the (unscaled) PDF integrates to 1,
#' and the total area in the histogram bars is \code{length(values) * binwidth}.
#' When \code{y_relative = TRUE} (proportion / relative frequency) the PDF is
#' rescaled by \code{binwidth} alone, matching the proportion-per-bin scale.
#'
#' Reused by issue #354 (normal-family + area-percentages diagrams) and #358
#' (Part E PDFs + x-bar histograms).
#'
#' @param values Numeric vector. Raw observations to bin.
#' @param pdf_fun Function \code{function(x) numeric} or NULL. The smooth
#'   density to overlay. If NULL (default), fits a normal using
#'   \code{mean(values)} and \code{sd(values)}.
#' @param binwidth Numeric or NULL. Bin width. If NULL (default), ggplot2
#'   picks a sensible default via \code{stat_bin}'s heuristic. A value is
#'   strongly recommended whenever the PDF is overlaid on raw-count bars,
#'   because the count-scale rescaling depends on a known bin width.
#' @param boundary Numeric. Bin boundary alignment. Default 0.
#' @param y_relative Logical. If TRUE, scale the Y axis to relative frequency
#'   (proportion) instead of raw counts. Default FALSE.
#' @param fill_colour Character. Bar fill colour. Default
#'   \code{CHART_LINE_COLOUR}.
#' @param pdf_colour Character. Colour of the smooth PDF curve. Default
#'   \code{CONTROL_LIMIT_COLOUR} (blue) — the same dark-mode-safe accent
#'   used for Shewhart Central Lines and control limits elsewhere in the
#'   project; provides a contrasting overlay against the red histogram bars
#'   that round-trips cleanly through the dark-mode invert+hue-rotate filter.
#' @param pdf_linewidth Numeric. Line width for the PDF overlay. Default 0.9.
#' @param x_breaks Numeric vector or NULL. Major x-axis tick positions.
#' @param xlim Numeric vector of length 2 or NULL. X-axis limits passed to
#'   \code{geom_function} so the smooth curve can extend beyond the observed
#'   data range. If NULL (default), the curve is drawn over the panel's
#'   automatic x range.
#' @return A ggplot2 object containing the histogram and PDF overlay.
#' @examples
#' set.seed(1)
#' histogram_with_pdf(rnorm(1000, mean = 0, sd = 1), binwidth = 0.25)
histogram_with_pdf <- function(values,
                               pdf_fun = NULL,
                               binwidth = NULL,
                               boundary = 0,
                               y_relative = FALSE,
                               fill_colour = CHART_LINE_COLOUR,
                               pdf_colour = CONTROL_LIMIT_COLOUR,
                               pdf_linewidth = 0.9,
                               x_breaks = NULL,
                               xlim = NULL) {
  stopifnot(is.numeric(values), length(values) >= 1)

  # Default PDF: a normal fitted to the sample.
  if (is.null(pdf_fun)) {
    mu_hat    <- mean(values)
    sigma_hat <- stats::sd(values)
    if (!is.finite(sigma_hat) || sigma_hat <= 0) {
      stop("Default normal PDF requires sd(values) to be finite and positive; ",
           "supply pdf_fun explicitly for degenerate samples.")
    }
    pdf_fun <- function(x) stats::dnorm(x, mean = mu_hat, sd = sigma_hat)
  }
  stopifnot(is.function(pdf_fun))

  df <- data.frame(value = values)

  y_aes <- if (y_relative) {
    aes(y = after_stat(count / sum(count)))
  } else {
    aes(y = after_stat(count))
  }

  # Rescale the unit-area PDF so the curve matches the histogram's vertical
  # scale. Raw counts: bar area = n * binwidth, so multiply by n * binwidth.
  # Relative frequency: bar area = binwidth, so multiply by binwidth alone.
  # When binwidth is NULL we cannot rescale; warn so the caller notices the
  # near-invisible curve, then fall back to the unscaled PDF.
  scale_factor <- if (is.null(binwidth)) {
    warning(
      "binwidth = NULL: the PDF overlay cannot be rescaled to match the ",
      "histogram's vertical scale and will appear near-zero. Supply ",
      "binwidth for a meaningful curve.",
      call. = FALSE
    )
    1
  } else if (y_relative) {
    binwidth
  } else {
    length(values) * binwidth
  }

  scaled_pdf <- function(x) pdf_fun(x) * scale_factor

  geom_function_args <- list(
    fun       = scaled_pdf,
    colour    = pdf_colour,
    linewidth = pdf_linewidth
  )
  if (!is.null(xlim)) {
    geom_function_args$xlim <- xlim
  }

  p <- ggplot(df, aes(x = .data$value)) +
    geom_histogram(
      mapping = y_aes,
      binwidth = binwidth,
      boundary = boundary,
      closed = "left",
      fill = fill_colour,
      colour = CHART_FG,
      linewidth = 0.3
    ) +
    do.call(geom_function, geom_function_args)

  if (!is.null(x_breaks)) {
    p <- p + scale_x_continuous(breaks = x_breaks)
  }

  if (y_relative) {
    p <- p + scale_y_continuous(
      labels = scales::percent_format(accuracy = 1)
    )
  }

  p + run_chart_theme()
}

#' Plot a Central Limit Theorem demonstration histogram
#'
#' Simulates \code{n_samples} draws of the sample mean \eqn{\bar{X}} of size
#' \code{n} from a user-supplied parent-distribution sampler, standardises each
#' \eqn{\bar{X}} to \eqn{Z = (\bar{X} - \mu) / (\sigma / \sqrt{n})}, and returns
#' a histogram of those Z values with the standard normal density \eqn{N(0, 1)}
#' overlaid for comparison. This is the figure-shape Neave uses on Part D
#' pages 52–54 of the Optional Extras to demonstrate the Central Limit Theorem:
#' as \code{n} grows, the standardised \eqn{\bar{X}} histogram converges in shape
#' to the standard normal — irrespective of the parent distribution's shape.
#'
#' The parent distribution must be supplied as a sampler function
#' \code{function(n) numeric}; the helper does not bake-in any particular
#' family. Issue #356 calls this for triangular and uniform parents; issue #357
#' will reuse the same helper for an exponential parent via
#' \code{function(n) rexp(n, rate = 1)}. The population mean and standard
#' deviation \code{mu} and \code{sigma} default to the standardising values
#' from Neave's chosen σ = 1 parents (\code{sigma = 1}, \code{mu = NULL} ->
#' estimated from a large pilot sample) but should be supplied directly when
#' the closed-form values are known, both for accuracy and to make the chunks
#' deterministic.
#'
#' Visual idiom matches \code{histogram_with_pdf()}: red bars with thin black
#' outlines, smooth blue \eqn{N(0, 1)} overlay, \code{run_chart_theme()} for
#' axis treatment and dark-mode parity. The histogram is drawn on the
#' density (proportion-per-unit) scale so the unit-area normal curve sits
#' naturally on top of it without further rescaling — that single visual
#' difference from \code{histogram_with_pdf()} is what makes the curve-over-bars
#' comparison readable when the histogram is itself a sampling distribution.
#'
#' @param parent_dist Function \code{function(n) numeric}. Sampler for the
#'   parent distribution — must return \code{n} draws each time it is called.
#'   The function will be invoked \code{n_samples} times with argument \code{n}.
#' @param n Integer. Sample size per \eqn{\bar{X}}.
#' @param n_samples Integer. Number of \eqn{\bar{X}} values to simulate.
#'   Default 100,000 — comfortably enough to show the CLT shape clearly while
#'   keeping per-chunk render time well under a second. Neave used 10,000,000;
#'   the shape is visually indistinguishable at 100K on a printed/screen page.
#' @param mu Numeric or NULL. Theoretical mean of the parent distribution
#'   used to standardise \eqn{\bar{X}}. If NULL (default), estimated from a
#'   pilot sample of size \code{1e5} drawn via \code{parent_dist}.
#' @param sigma Numeric. Theoretical standard deviation of the parent
#'   distribution. Default 1 — matches Neave's chosen σ = 1 parametrisations
#'   across all four CLT-demo families on pages 52–54.
#' @param binwidth Numeric. Bin width for the histogram in standardised
#'   units. Default 0.2 — fine enough to read the bell shape, coarse enough
#'   to keep individual bars stable at moderate \code{n_samples}.
#' @param xlim Numeric vector of length 2. X-axis range in standardised
#'   units. Default \code{c(-4, 4)} — covers the bulk of any plausible
#'   \eqn{Z} distribution after the CLT has taken effect.
#' @param fill_colour Character. Bar fill. Default \code{CHART_LINE_COLOUR}.
#' @param pdf_colour Character. Overlay-curve colour. Default
#'   \code{CONTROL_LIMIT_COLOUR} (blue).
#' @param pdf_linewidth Numeric. Overlay curve line width. Default 0.9.
#' @return A ggplot2 object containing the standardised-\eqn{\bar{X}}
#'   histogram with the standard normal density overlaid.
#' @examples
#' set.seed(356)
#' clt_demo_plot(function(n) runif(n, min = -sqrt(3), max = sqrt(3)), n = 4)
clt_demo_plot <- function(parent_dist,
                          n,
                          n_samples     = 100000L,
                          mu            = NULL,
                          sigma         = 1,
                          binwidth      = 0.2,
                          xlim          = c(-4, 4),
                          fill_colour   = CHART_LINE_COLOUR,
                          pdf_colour    = CONTROL_LIMIT_COLOUR,
                          pdf_linewidth = 0.9) {
  stopifnot(is.function(parent_dist),
            is.numeric(n), length(n) == 1L, n >= 1,
            is.numeric(n_samples), length(n_samples) == 1L, n_samples >= 1,
            is.numeric(sigma), length(sigma) == 1L, sigma > 0,
            is.numeric(binwidth), length(binwidth) == 1L, binwidth > 0,
            is.numeric(xlim), length(xlim) == 2L, xlim[1] < xlim[2])

  n         <- as.integer(n)
  n_samples <- as.integer(n_samples)

  # Estimate mu from a pilot sample if not supplied. A large pilot keeps the
  # estimate stable across runs even when no seed is set in the calling chunk.
  if (is.null(mu)) {
    pilot <- parent_dist(1e5)
    mu    <- mean(pilot)
  }
  stopifnot(is.numeric(mu), length(mu) == 1L, is.finite(mu))

  # One big draw, reshape into rows. rowMeans is the vectorised idiom; avoid
  # apply() (which silently transposes when the inner function returns a
  # vector) so the code reads cleanly and matches the project's style.
  total <- n_samples * n
  draws <- matrix(parent_dist(total), nrow = n_samples, ncol = n)
  xbar  <- rowMeans(draws)
  z     <- (xbar - mu) / (sigma / sqrt(n))

  df <- data.frame(z = z)

  ggplot(df, aes(x = .data$z)) +
    geom_histogram(
      mapping  = aes(y = after_stat(density)),
      binwidth = binwidth,
      boundary = 0,
      closed   = "left",
      fill     = fill_colour,
      colour   = CHART_FG,
      linewidth = 0.3
    ) +
    geom_function(
      fun       = function(x) dnorm(x, mean = 0, sd = 1),
      colour    = pdf_colour,
      linewidth = pdf_linewidth,
      xlim      = xlim,
      n         = 401
    ) +
    scale_x_continuous(limits = xlim, expand = c(0, 0)) +
    run_chart_theme()
}

#' Plot one or more smooth probability density functions, overlaid or stacked
#'
#' Draws each function in \code{pdfs} on a shared x range. Two layouts:
#'
#' \itemize{
#'   \item \code{layout = "overlay"} (default): all curves on one panel,
#'         mapped to a colour legend — useful for direct visual comparison
#'         when shapes are intentionally different and the eye is meant to
#'         see them stacked atop each other.
#'   \item \code{layout = "stack"}: one panel per curve, faceted vertically
#'         in input order, fixed x and y scales across panels so heights
#'         and widths remain directly comparable — matches Neave's printed
#'         page 47 layout (three independent panels for σ = 1, 2, 3) and
#'         is the right default whenever the source figure stacks rather
#'         than overlays.
#' }
#'
#' Both layouts evaluate each PDF on \code{n} evenly-spaced points across
#' \code{xlim}. The overlay layout uses \code{geom_function} (which performs
#' its own adaptive sampling around \code{n} points); the stacked layout
#' pre-evaluates into a long data frame and uses \code{geom_line} with
#' \code{facet_wrap} — same visual fidelity at the n used here.
#'
#' Default palette: \code{CHART_LINE_COLOUR} (the red data ink) for the first
#' curve, \code{CONTROL_LIMIT_COLOUR} (blue) for the second, \code{CHART_FG}
#' (black) for the third. The palette extends with \code{CHART_GRID} (mid-grey)
#' for a fourth curve so the #358 four-family case has a non-repeating
#' colour assignment. No new colour tokens are introduced — every entry is
#' one of the existing dark-mode-safe constants documented at the top of
#' this file.
#'
#' @param pdfs Named list of functions \code{function(x) numeric}. The list
#'   names are used as legend labels and as the colour scale's breaks (so
#'   legend order matches list order).
#' @param xlim Numeric vector of length 2. The x range over which every
#'   curve is evaluated; passed to \code{geom_function}'s \code{xlim} and
#'   used to set the panel's x scale.
#' @param colours Character vector or NULL. Colours aligned to \code{pdfs}
#'   (positionally or by name). NULL (default) uses the project palette
#'   described above, recycled if there are more PDFs than palette entries.
#' @param linewidth Numeric. Line width for every curve. Default 0.7 —
#'   thinner than \code{histogram_with_pdf()}'s 0.9 because multiple
#'   curves on one panel read more cleanly when each is a finer line.
#' @param legend_title Character or NULL. Title above the colour legend.
#'   NULL (default) suppresses the legend title — fine when the legend
#'   labels are self-describing (e.g. "Smallish σ").
#' @param y_label Character. Y-axis label. Default \code{"Density"}.
#' @param show_y_axis Logical. If FALSE (default), suppress y-axis ink and
#'   labels — appropriate for PDF illustrations where only the *shape* and
#'   *relative* heights carry meaning, as in Neave's printed page 47. Set
#'   TRUE if the caller wants a numeric density axis.
#' @param n Integer. Number of points each curve is evaluated at across
#'   \code{xlim}. Default 401 — finer than ggplot's 101 default so the bell
#'   shoulders read smoothly even on tall narrow panels.
#' @param layout Character. \code{"overlay"} (default) returns a single
#'   panel with all curves; \code{"stack"} returns a vertically faceted
#'   plot with one panel per curve in input order, fixed x and y scales
#'   across panels.
#' @return A ggplot2 object — one shared panel for \code{"overlay"}, a
#'   \code{facet_wrap}-ed plot with one row per curve for \code{"stack"}.
#' @examples
#' pdf_family_plot(
#'   pdfs = list(
#'     "σ = 1" = function(x) dnorm(x, 0, 1),
#'     "σ = 2" = function(x) dnorm(x, 0, 2),
#'     "σ = 3" = function(x) dnorm(x, 0, 3)
#'   ),
#'   xlim = c(-10, 10)
#' )
#' pdf_family_plot(
#'   pdfs = list(
#'     "Smallish σ"     = function(x) dnorm(x, 0, 1),
#'     "Larger σ"       = function(x) dnorm(x, 0, 2),
#'     "Still larger σ" = function(x) dnorm(x, 0, 3)
#'   ),
#'   xlim = c(-10, 10),
#'   layout = "stack"
#' )
pdf_family_plot <- function(pdfs,
                            xlim,
                            colours      = NULL,
                            linewidth    = 0.7,
                            legend_title = NULL,
                            y_label      = "Density",
                            show_y_axis  = FALSE,
                            n            = 401,
                            layout       = c("overlay", "stack")) {
  layout <- match.arg(layout)
  stopifnot(is.list(pdfs), length(pdfs) >= 1,
            !is.null(names(pdfs)), all(nzchar(names(pdfs))),
            all(vapply(pdfs, is.function, logical(1))),
            is.numeric(xlim), length(xlim) == 2L, xlim[1] < xlim[2])

  palette <- c(CHART_LINE_COLOUR, CONTROL_LIMIT_COLOUR, CHART_FG, CHART_GRID)
  if (is.null(colours)) {
    colours <- rep_len(palette, length(pdfs))
  } else {
    stopifnot(length(colours) == length(pdfs))
  }
  names(colours) <- names(pdfs)

  if (layout == "stack") {
    xs <- seq(xlim[1], xlim[2], length.out = n)
    long <- do.call(rbind, lapply(names(pdfs), function(lbl) {
      data.frame(label = lbl, x = xs, density = pdfs[[lbl]](xs))
    }))
    long$label <- factor(long$label, levels = names(pdfs))

    p <- ggplot(long, aes(x = .data$x, y = .data$density,
                          colour = .data$label)) +
      geom_line(linewidth = linewidth) +
      facet_wrap(~ label, ncol = 1, scales = "fixed", strip.position = "top") +
      scale_colour_manual(values = colours, breaks = names(pdfs),
                          guide = "none") +
      scale_x_continuous(limits = xlim, expand = c(0, 0)) +
      labs(y = y_label) +
      run_chart_theme()
  } else {
    # Dummy single-row data layer: geom_function ignores it and computes y
    # from `fun`. Same trick is used elsewhere in this file (histogram_with_pdf
    # at least supplies a real data layer for the bars, but pure-curve plots
    # have no observations to bind to).
    dummy <- data.frame(x = mean(xlim))

    p <- ggplot(dummy, aes(x = .data$x))
    for (label in names(pdfs)) {
      p <- p + geom_function(
        fun       = pdfs[[label]],
        aes(colour = !!label),
        xlim      = xlim,
        linewidth = linewidth,
        n         = n
      )
    }

    p <- p +
      scale_colour_manual(
        name   = legend_title,
        values = colours,
        breaks = names(pdfs)
      ) +
      scale_x_continuous(limits = xlim, expand = c(0, 0)) +
      labs(y = y_label) +
      run_chart_theme()
  }

  if (!show_y_axis) {
    p <- p + theme(axis.text.y        = element_blank(),
                   axis.ticks.y       = element_blank(),
                   axis.title.y       = element_blank(),
                   axis.line.y        = element_blank(),
                   panel.grid.major.x = element_blank(),
                   panel.grid.major.y = element_blank(),
                   panel.grid.minor.x = element_blank(),
                   panel.grid.minor.y = element_blank())
  }

  p
}

#' Plot a confidence-interval illustration on a standard normal curve
#'
#' Draws the standard-normal pdf with the central \code{level}-fraction of the
#' area shaded "yellow" and the two tails shaded "red", plus vertical line
#' markers and tick labels at the boundaries. This is the page-50 figure in
#' Neave's Part D crash-course: a 95% confidence region uses
#' \code{level = 0.95} (boundaries at ±1.96σ); a 99% confidence region uses
#' \code{level = 0.99} (boundaries at ±2.58σ).
#'
#' The plot is drawn in σ-units (standard normal, μ = 0, σ = 1). The boundary
#' labels follow Neave's printed form — \code{"μ−1.96σ"} on the
#' left and \code{"μ+1.96σ"} on the right — so the figure reads as
#' an illustration of *any* normal distribution rather than the standard
#' normal specifically. The percentage label inside the central region is
#' formatted from \code{level} (e.g. \code{0.95} renders as \code{"95%"}).
#'
#' Like \code{pdf_family_plot()}, this helper renders an analytic curve from
#' \code{dnorm}; no \code{set.seed()} is required and none should be added
#' to its calling chunks. The yellow / red fill palette intentionally
#' matches Neave's printed figure rather than the project's dark-mode-safe
#' palette — the central "yellow" and the tail "red" are pedagogically
#' load-bearing (Neave's prose on page 50 refers to "the yellow area" and
#' "the red tails" by name) and the figure's chromatic identity reads as a
#' single coherent illustration only when those two colours are used.
#'
#' @param level Numeric in (0, 1). Central confidence level — e.g.
#'   \code{0.95} or \code{0.99}.
#' @param z Numeric or NULL. Half-width of the central region in σ-units.
#'   If NULL (default), computed as \code{qnorm((1 + level) / 2)} — the
#'   z-score that puts \code{level} of the area in the central region.
#'   Override (e.g. \code{1.96} or \code{2.58}) to reproduce Neave's
#'   conventional rounded values verbatim; without an override the
#'   computed z-scores are 1.959964 (95%) and 2.575829 (99%), which
#'   round to Neave's printed values but differ in the third decimal.
#' @param xlim Numeric vector of length 2. X-axis range in σ-units.
#'   Default \code{c(-4, 4)} — the curve is visually flat outside this
#'   range and the same range is used for both the 95% and the 99%
#'   figures so the two illustrations compose at the same horizontal
#'   scale.
#' @param fill_central Character. Fill colour for the central
#'   \code{level}-fraction band. Default \code{"#fff176"} (the yellow
#'   Neave uses on the printed page).
#' @param fill_tail Character. Fill colour for the two tail bands.
#'   Default \code{"#ed0000"} (the project's existing red, also Neave's
#'   tail colour).
#' @param curve_colour Character. Colour of the bell-curve outline and
#'   the baseline. Default \code{CHART_FG}.
#' @param boundary_label_format Function. Called as
#'   \code{boundary_label_format(z, sign)} where \code{sign} is
#'   \code{-1L} for the left boundary and \code{+1L} for the right.
#'   Should return a single character string. The default formats as
#'   \code{"μ−1.96σ"} / \code{"μ+1.96σ"} when
#'   \code{z = 1.96}, matching Neave's printed labels. Override to
#'   produce a different label form (e.g. raw z-scores).
#' @param percent_label Character or NULL. Label drawn inside the
#'   central region. If NULL (default), formatted from \code{level}
#'   via \code{scales::label_percent(accuracy = 1)} — e.g.
#'   \code{"95%"} for \code{level = 0.95}.
#' @return A ggplot2 object — a single panel with no axis ink other
#'   than the baseline and the boundary tick labels.
#' @examples
#' conf_interval_plot(0.95)
#' conf_interval_plot(0.99, z = 2.58)
conf_interval_plot <- function(level,
                               z = NULL,
                               xlim = c(-4, 4),
                               fill_central = "#fff176",
                               fill_tail    = "#ed0000",
                               curve_colour = CHART_FG,
                               boundary_label_format = NULL,
                               percent_label = NULL) {
  stopifnot(is.numeric(level), length(level) == 1L,
            level > 0, level < 1,
            is.numeric(xlim), length(xlim) == 2L, xlim[1] < xlim[2])

  if (is.null(z)) {
    z <- qnorm((1 + level) / 2)
  }
  stopifnot(is.numeric(z), length(z) == 1L, z > 0, z < xlim[2])

  if (is.null(boundary_label_format)) {
    boundary_label_format <- function(z, sign) {
      sign_glyph <- if (sign < 0) "−" else "+"
      # Trim trailing zeros so 1.96 stays "1.96" but 2.00 would render as "2".
      z_text <- format(z, trim = TRUE, drop0trailing = TRUE)
      paste0("μ", sign_glyph, z_text, "σ")
    }
  }
  stopifnot(is.function(boundary_label_format))

  if (is.null(percent_label)) {
    percent_label <- scales::label_percent(accuracy = 1)(level)
  }

  xs   <- seq(xlim[1], xlim[2], length.out = 801)
  dens <- data.frame(x = xs, y = dnorm(xs))
  peak <- dnorm(0)

  left_tail   <- dens[dens$x <= -z, ]
  right_tail  <- dens[dens$x >=  z, ]
  central     <- dens[dens$x >= -z & dens$x <= z, ]

  # Label positions:
  # - percentage label sits at the visual centre of the central region,
  #   anchored at a fraction of the peak so it reads cleanly on both the
  #   95% (wide yellow) and 99% (wider yellow) figures.
  # - boundary labels sit just below the baseline.
  pct_y    <- 0.40 * peak
  label_y  <- -0.04 * peak

  ggplot(dens, aes(x = .data$x, y = .data$y)) +
    geom_ribbon(data = central, aes(x = .data$x, ymin = 0, ymax = .data$y),
                fill = fill_central, inherit.aes = FALSE) +
    geom_ribbon(data = left_tail, aes(x = .data$x, ymin = 0, ymax = .data$y),
                fill = fill_tail, inherit.aes = FALSE) +
    geom_ribbon(data = right_tail, aes(x = .data$x, ymin = 0, ymax = .data$y),
                fill = fill_tail, inherit.aes = FALSE) +
    geom_line(colour = curve_colour, linewidth = 0.7) +
    annotate("segment", x = xlim[1], xend = xlim[2], y = 0, yend = 0,
             colour = curve_colour, linewidth = 0.5) +
    annotate("segment", x = -z, xend = -z, y = 0, yend = dnorm(z),
             colour = curve_colour, linewidth = 0.4) +
    annotate("segment", x =  z, xend =  z, y = 0, yend = dnorm(z),
             colour = curve_colour, linewidth = 0.4) +
    annotate("text", x = 0, y = pct_y, label = percent_label,
             colour = curve_colour, size = 6, fontface = "bold") +
    annotate("text", x = -z, y = label_y,
             label = boundary_label_format(z, -1L),
             colour = curve_colour, size = 5, hjust = 0.5, vjust = 1) +
    annotate("text", x =  z, y = label_y,
             label = boundary_label_format(z, +1L),
             colour = curve_colour, size = 5, hjust = 0.5, vjust = 1) +
    scale_x_continuous(limits = xlim, expand = c(0, 0)) +
    scale_y_continuous(limits = c(-0.12 * peak, peak * 1.05),
                       expand = c(0, 0)) +
    theme_void() +
    theme(plot.background  = element_rect(fill = "transparent", colour = NA),
          panel.background = element_rect(fill = "transparent", colour = NA),
          plot.margin      = margin(6, 6, 6, 6))
}

#' Plot a stacked-unit-boxes "histogram" (Day 3 page 7 left panel)
#'
#' For each integer value in \code{values}, draws a column of unit squares —
#' one square per observation, stacked from the baseline upward. This is
#' Neave's left-hand pictorial form on Day 3 page 7, where each item in the
#' data is represented by a box stacked on the appropriate pile and small
#' visible gaps separate adjacent boxes (so the reader can see where the
#' individual observations are before the gaps are filled in to make a
#' conventional bar histogram in the right-hand panel).
#'
#' Uses \code{geom_tile} with \code{coord_fixed(ratio = 1)} so the tile size
#' AND the gap between adjacent tiles are both expressed in data units —
#' this keeps the gap-to-box ratio constant horizontally and vertically
#' regardless of the panel's aspect ratio. An earlier version used
#' \code{geom_point(shape = 22)} sized in millimetres, but that left
#' visible asymmetric gaps (large vertical, small horizontal) whenever the
#' panel was wider than tall.
#'
#' @param values Numeric vector. Integer-like observations to stack.
#' @param x_breaks Numeric vector or NULL. Major x-axis tick positions.
#'   If NULL, ggplot picks the breaks via its default heuristic.
#' @param box_fill Numeric in (0, 1]. Fraction of the unit cell each box
#'   occupies; the remainder shows as the gap between adjacent boxes.
#'   Default 0.85 — a small but visible gap on every side, matching
#'   Neave's printed page-7 figure.
#' @return A ggplot2 object.
#' @examples
#' stacked_boxes_plot(c(10, 11, 11, 11, 12, 12), x_breaks = 10:12)
stacked_boxes_plot <- function(values, x_breaks = NULL, box_fill = 0.85) {
  stopifnot(is.numeric(values), length(values) >= 1,
            box_fill > 0, box_fill <= 1)

  df <- data.frame(value = values) |>
    dplyr::group_by(.data$value) |>
    dplyr::mutate(stack = dplyr::row_number()) |>
    dplyr::ungroup()

  max_stack <- max(df$stack)

  p <- ggplot(df, aes(x = .data$value, y = .data$stack)) +
    geom_tile(width = box_fill, height = box_fill,
              fill = CHART_LINE_COLOUR, colour = CHART_FG, linewidth = 0.4) +
    coord_fixed(ratio = 1, clip = "off")

  if (!is.null(x_breaks)) {
    p <- p + scale_x_continuous(breaks = x_breaks)
  }

  p +
    scale_y_continuous(limits = c(0.5, max_stack + 0.5), expand = c(0, 0)) +
    theme_minimal(base_size = 14) +
    theme(
      panel.background = element_rect(fill = "transparent", colour = NA),
      plot.background  = element_rect(fill = "transparent", colour = NA),
      axis.text.x      = element_text(color = CHART_FG, size = 14),
      axis.text.y      = element_blank(),
      axis.ticks       = element_blank(),
      axis.title       = element_blank(),
      axis.line.x      = element_line(color = CHART_FG, linewidth = 0.6),
      axis.line.y      = element_blank(),
      panel.grid       = element_blank()
    )
}

#' Plot a Ford-style histogram with LSL/USL knife-edge framing
#'
#' Draws a bar histogram of \code{values} (one bar per occupied integer bin)
#' inside a "Lower Specification Limit ... Upper Specification Limit" frame:
#' a horizontal baseline under the bars with vertical lines at \code{lsl_at}
#' and \code{usl_at}, each labelled above. No y-axis, no x-axis tick labels,
#' and a single x-axis title ("Shaft diameter" by default). This is the
#' qualitative shape illustration Neave uses on Day 3 page 5 for the
#' Ford-with-compensation and Ford-without-compensation pair — the two
#' charts are visually comparable only if they share the same \code{lsl_at}
#' and \code{usl_at}, so callers should pass identical framing values when
#' rendering the pair.
#'
#' Bin positions in the source PDF carry no numeric meaning (the histogram
#' has no x-axis numbers); the digitised position values in
#' \code{R/data/day-03-ford-*.csv} are arbitrary left-to-right indices.
#'
#' @param values Numeric vector. Expanded raw observations (one entry per
#'   shaft); use \code{rep(df$position, df$count)} to expand the digitised
#'   (position, count) CSV into the form this function expects.
#' @param lsl_at Numeric. X-position of the Lower Specification Limit line.
#' @param usl_at Numeric. X-position of the Upper Specification Limit line.
#' @param lsl_label Character. Multi-line label drawn above the LSL line.
#'   Default \code{"Lower\nSpecification\nLimit"}.
#' @param usl_label Character. Multi-line label drawn above the USL line.
#' @param x_title Character. X-axis title under the baseline. Default
#'   \code{"Shaft diameter"}.
#' @param fill_colour Character. Bar fill colour. Default
#'   \code{CHART_LINE_COLOUR}.
#' @param ymax_factor Numeric. How tall the LSL/USL vertical lines are
#'   relative to the tallest bar. Default 1.6 (matches Neave's printed
#'   proportions).
#' @return A ggplot2 object.
#' @examples
#' ford_histogram_plot(rep(c(5, 8, 10, 12), c(2, 4, 3, 1)),
#'                     lsl_at = 0, usl_at = 15)
ford_histogram_plot <- function(values,
                                lsl_at,
                                usl_at,
                                lsl_label = "Lower\nSpecification\nLimit",
                                usl_label = "Upper\nSpecification\nLimit",
                                x_title   = "Shaft diameter",
                                fill_colour = CHART_LINE_COLOUR,
                                ymax_factor = 1.6) {
  stopifnot(is.numeric(values), length(values) >= 1,
            is.numeric(lsl_at), is.numeric(usl_at), lsl_at < usl_at)

  ymax <- max(table(values)) * ymax_factor

  ggplot(data.frame(value = values), aes(x = .data$value)) +
    geom_histogram(binwidth = 1, boundary = 0.5, closed = "left",
                   fill = fill_colour, colour = CHART_FG, linewidth = 0.3) +
    annotate("segment", x = lsl_at, xend = usl_at, y = 0, yend = 0,
             colour = CHART_FG, linewidth = 0.5) +
    annotate("segment", x = lsl_at, xend = lsl_at, y = 0, yend = ymax,
             colour = CHART_FG, linewidth = 0.5) +
    annotate("segment", x = usl_at, xend = usl_at, y = 0, yend = ymax,
             colour = CHART_FG, linewidth = 0.5) +
    annotate("text", x = lsl_at, y = ymax + 0.4, label = lsl_label,
             hjust = 0.5, vjust = 0, colour = CHART_FG, size = 4.5,
             lineheight = 0.95) +
    annotate("text", x = usl_at, y = ymax + 0.4, label = usl_label,
             hjust = 0.5, vjust = 0, colour = CHART_FG, size = 4.5,
             lineheight = 0.95) +
    coord_cartesian(xlim = c(lsl_at - 0.5, usl_at + 0.5),
                    ylim = c(-0.5, ymax + 3.5), clip = "off") +
    labs(x = x_title) +
    theme_void() +
    theme(
      plot.background  = element_rect(fill = "transparent", colour = NA),
      panel.background = element_rect(fill = "transparent", colour = NA),
      axis.title.x     = element_text(color = CHART_FG, size = 14,
                                      margin = margin(t = 10))
    )
}

# --- Optional Extras Part E §4: X-bar false-signal probabilities ---

#' Simulate the false-signal probability for an X-bar chart
#'
#' For each of \code{n_replications} replications, draws \code{m_subgroups}
#' subgroups of size \code{n} from a standard normal distribution, builds an
#' X-bar control chart in the textbook way (grand mean ± A2 · R-bar), then
#' computes the probability that a *future* subgroup mean (which under the
#' true model is N(0, 1/√n)) falls outside those limits. Returns a vector of
#' \code{n_replications} probabilities — one per replication.
#'
#' This is the simulation behind the histograms on Neave's Optional Extras
#' Part E pages 69 and 70. The pages 69/70 histograms are built by calling
#' this function once per subgroup size n ∈ \{2, 4, 6\} with
#' \code{m_subgroups = 12} (page 69) or \code{m_subgroups = 40} (page 70).
#' The textbook claim that the false-signal probability "is" 0.0027 assumes
#' that the *true* μ and σ are known; in practice they have to be estimated
#' from finite data, and the spread of these histograms quantifies how
#' badly that estimation noise affects the claim.
#'
#' The X-bar chart constants follow Shewhart's standard form
#' \eqn{UCL/LCL = \bar{\bar{X}} \pm A_2 \bar{R}}, where
#' \eqn{A_2 = 3 / (d_2 \sqrt{n})} and \eqn{d_2} depends only on the
#' subgroup size \eqn{n}. The values of \eqn{d_2} used are the standard
#' ones tabulated in Part B (page 20): 1.128 (n=2), 1.693 (n=3),
#' 2.059 (n=4), 2.326 (n=5), 2.534 (n=6). Callers can override \eqn{d_2}
#' via the optional \code{d2_override} argument; the default lookup covers
#' \eqn{n \in \{2, 3, 4, 5, 6\}}.
#'
#' Vectorised throughout. Subgroups are stored as an
#' \code{n_replications × (m_subgroups · n)} matrix; row-wise subgroup
#' ranges are computed by reshaping the matrix to an
#' \code{n × m_subgroups × n_replications} array and folding the n-axis
#' with \code{pmax} / \code{pmin}, so no \code{apply()} calls appear.
#'
#' @param n Integer-ish. Subgroup size. Must be in \{2, 3, 4, 5, 6\} unless
#'   \code{d2_override} is supplied.
#' @param m_subgroups Integer-ish. Number of subgroups used to compute the
#'   control limits in each replication.
#' @param n_replications Integer-ish. Number of replications.
#' @param d2_override Numeric or NULL. If non-NULL, used as \eqn{d_2}
#'   instead of the built-in lookup — useful for non-standard \eqn{n}.
#' @return Numeric vector of length \code{n_replications}: the simulated
#'   false-signal probability for each replication.
#' @examples
#' set.seed(359)
#' probs <- xbar_false_signal_probs(n = 4, m_subgroups = 12,
#'                                  n_replications = 1000)
#' summary(probs)
xbar_false_signal_probs <- function(n,
                                    m_subgroups,
                                    n_replications,
                                    d2_override = NULL) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 2,
            is.numeric(m_subgroups), length(m_subgroups) == 1,
            m_subgroups >= 2,
            is.numeric(n_replications), length(n_replications) == 1,
            n_replications >= 1)

  d2_table <- c("2" = 1.128, "3" = 1.693, "4" = 2.059,
                "5" = 2.326, "6" = 2.534)
  d2 <- if (!is.null(d2_override)) {
    d2_override
  } else {
    val <- d2_table[as.character(n)]
    if (is.na(val)) {
      stop("No built-in d2 for n = ", n,
           "; supply d2_override.", call. = FALSE)
    }
    unname(val)
  }
  A2 <- 3 / (d2 * sqrt(n))

  total <- n_replications * m_subgroups * n
  draws <- matrix(rnorm(total),
                  nrow = n_replications,
                  ncol = m_subgroups * n)

  # Row-wise grand mean = simple mean across all m_subgroups * n columns.
  grand_mean <- rowMeans(draws)

  # Row-wise subgroup ranges: reshape each replication's row to an
  # n × m_subgroups slice (one subgroup per column) and fold over the n
  # axis with pmax / pmin to get colMax / colMin per slice — vectorised
  # across replications. `array(t(draws), c(n, m_subgroups, R))` lays out
  # storage column-major so consecutive within-subgroup observations
  # land in one column of each m_subgroups × R slice as the n-axis varies
  # fastest.
  arr <- array(t(draws), dim = c(n, m_subgroups, n_replications))
  col_max <- arr[1, , , drop = FALSE]
  col_min <- arr[1, , , drop = FALSE]
  if (n >= 2) {
    for (i in seq.int(2L, n)) {
      col_max <- pmax(col_max, arr[i, , , drop = FALSE])
      col_min <- pmin(col_min, arr[i, , , drop = FALSE])
    }
  }
  # Drop the leading singleton n-axis so we end up with an
  # m_subgroups × n_replications matrix.
  dim(col_max) <- c(m_subgroups, n_replications)
  dim(col_min) <- c(m_subgroups, n_replications)
  ranges <- col_max - col_min
  r_bar  <- colMeans(ranges)

  half_width <- A2 * r_bar
  UCL <- grand_mean + half_width
  LCL <- grand_mean - half_width

  # Future subgroup mean has distribution N(0, 1/√n) under the true model.
  sd_xbar <- 1 / sqrt(n)
  pnorm(LCL, mean = 0, sd = sd_xbar) +
    pnorm(UCL, mean = 0, sd = sd_xbar, lower.tail = FALSE)
}

#' Plot a single Optional Extras Part E §4 false-signal histogram panel
#'
#' Builds one of the three stacked histograms on Neave's pages 69 and 70:
#' a histogram of simulated X-bar-chart false-signal probabilities with a
#' red tick and "0.0027" label marking the textbook target value on the
#' x axis, and a subgroup-size caption (for example "12 subgroups of
#' size 2") centred under the panel.
#'
#' Layout faithfulness to Neave's printed page is the brief here. The
#' histogram uses unfilled bars with thin black outlines; the x axis is
#' a single black baseline with major ticks at every 0.005; there is no
#' y-axis ink at all (the printed page has none); the 0.0027 marker is
#' drawn as a short red tick *below* the baseline with the label "0.0027"
#' in red just under it; the panel caption sits well below the axis.
#'
#' @param values Numeric vector. False-signal probabilities for the
#'   replications behind this panel. Values beyond \code{x_max} are clipped
#'   onto the rightmost bin so the histogram does not visually under-count
#'   the long tail (matching the printed page, which truncates rather than
#'   trims).
#' @param caption Character. Caption text placed below the panel
#'   (for example "12 subgroups of size 2").
#' @param x_max Numeric. Upper limit of the x axis. Neave uses 0.020 on
#'   page 69 and 0.025 on page 70.
#' @param binwidth Numeric. Histogram bin width. Default 0.0003 matches
#'   the visual bin density of Neave's printed page (about 65 bins across
#'   \code{[0, x_max]}).
#' @return A ggplot2 object.
#' @examples
#' set.seed(359)
#' xbar_false_signal_panel(
#'   xbar_false_signal_probs(n = 4, m_subgroups = 12, n_replications = 1000),
#'   caption = "12 subgroups of size 4", x_max = 0.020
#' )
xbar_false_signal_panel <- function(values,
                                    caption,
                                    x_max,
                                    binwidth = 0.0003) {
  stopifnot(is.numeric(values), length(values) >= 1,
            is.character(caption), length(caption) == 1,
            is.numeric(x_max), length(x_max) == 1, x_max > 0)

  df <- data.frame(v = pmin(values, x_max))
  x_breaks <- seq(0, x_max, by = 0.005)

  ggplot(df, aes(x = .data$v)) +
    geom_histogram(
      binwidth  = binwidth,
      boundary  = 0,
      closed    = "left",
      fill      = "white",
      colour    = CHART_FG,
      linewidth = 0.2
    ) +
    # Red 0.0027 tick + label below the baseline. clip = "off" so the tick
    # and the label can sit underneath the plotting area.
    annotate("segment", x = 0.0027, xend = 0.0027,
             y = 0, yend = -Inf,
             colour = CHART_LINE_COLOUR, linewidth = 0.6) +
    annotate("text", x = 0.0027, y = 0,
             label = "0.0027",
             colour = CHART_LINE_COLOUR,
             hjust = 0.5, vjust = 1.8, size = 4) +
    labs(caption = caption) +
    scale_x_continuous(
      limits = c(0, x_max),
      breaks = x_breaks,
      labels = format(x_breaks, nsmall = 3, trim = TRUE),
      expand = c(0, 0)
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    coord_cartesian(clip = "off") +
    theme_void() +
    theme(
      plot.background     = element_rect(fill = "transparent", colour = NA),
      panel.background    = element_rect(fill = "transparent", colour = NA),
      axis.line.x         = element_line(colour = CHART_FG, linewidth = 0.5),
      axis.ticks.x        = element_line(colour = CHART_FG, linewidth = 0.4),
      axis.ticks.length.x = unit(3, "pt"),
      axis.text.x         = element_text(colour = CHART_FG, size = 10,
                                         margin = margin(t = 4)),
      plot.caption        = element_text(colour = CHART_FG, size = 12,
                                         hjust = 0.5,
                                         margin = margin(t = 18, b = 4)),
      plot.margin         = margin(8, 12, 24, 12)
    )
}

# --- Taguchi loss function (Day 7 page 22) ---

#' Plot the abstract Taguchi loss function
#'
#' Draws the symmetric parabola \eqn{y = k(x - \text{nominal})^2} used by
#' mathematicians as "the" Taguchi loss function. There are no numeric
#' scales — Neave deliberately presents this as a shape, not a scaled
#' function. A small floating axis-cross labels "loss" (vertical) and
#' "measurement" (horizontal); the word "nominal" sits below the minimum
#' of the curve.
#'
#' This pairs with \code{taguchi_loss_personal()}, which draws Neave's own
#' temperature-vs-loss data on a scaled graph; the two together are
#' Figure 34 of \emph{DemDim} as reproduced on Day 7 page 22.
#'
#' @return A ggplot2 object.
#' @examples
#' taguchi_loss_abstract()
taguchi_loss_abstract <- function() {
  # x and k chosen so the parabola visually matches the proportions of
  # Neave's drawing — see deviations log entry for issue #311.
  curve_df <- data.frame(x = seq(-1, 1, length.out = 200))
  curve_df$y <- curve_df$x^2

  ggplot(curve_df, aes(x = .data$x, y = .data$y)) +
    geom_line(colour = CHART_FG, linewidth = 0.8) +
    annotate("segment", x = -0.95, xend = -0.95, y = 0.05, yend = 0.6,
             colour = CHART_FG, linewidth = 0.6,
             arrow = arrow(length = unit(0.18, "cm"))) +
    annotate("segment", x = -0.95, xend = -0.55, y = 0.05, yend = 0.05,
             colour = CHART_FG, linewidth = 0.6,
             arrow = arrow(length = unit(0.18, "cm"))) +
    annotate("text", x = -0.97, y = 0.65, label = "loss",
             hjust = 1, vjust = 0.5, colour = CHART_FG, size = 4.5) +
    annotate("text", x = -0.55, y = 0.02, label = "measurement",
             hjust = 0, vjust = 1, colour = CHART_FG, size = 4.5) +
    annotate("text", x = 0, y = -0.05, label = "nominal",
             hjust = 0.5, vjust = 1, colour = CHART_FG, size = 4.5) +
    coord_cartesian(xlim = c(-1.1, 1.1), ylim = c(-0.15, 1.1), clip = "off") +
    theme_void() +
    theme(plot.background  = element_rect(fill = "transparent", colour = NA),
          panel.background = element_rect(fill = "transparent", colour = NA))
}

#' Plot a personal Taguchi loss-function graph
#'
#' Draws an X marker at each (temperature, loss) reading and a smooth
#' curve through them. This is the bottom panel of Figure 34 on Day 7
#' page 22 — Neave's plotted answers to his own Activity 7-e.
#'
#' Real-life loss functions are not exactly symmetric about the nominal
#' value; the smooth curve is fitted with \code{stats::loess} so individual
#' asymmetries (e.g. Neave losing efficiency faster when cold than hot)
#' come through faithfully.
#'
#' @param temps Numeric vector. Temperatures along the horizontal axis.
#' @param losses Numeric vector (same length). Percentage losses (0-100).
#' @param y_breaks Numeric vector. Major y-axis breaks. Default
#'   \code{seq(0, 100, by = 10)}.
#' @return A ggplot2 object.
#' @examples
#' taguchi_loss_personal(
#'   temps  = c(6, 11, 16, 21, 26, 31, 36),
#'   losses = c(95, 50, 15, 0, 10, 45, 85)
#' )
taguchi_loss_personal <- function(temps, losses,
                                  y_breaks = seq(0, 100, by = 10)) {
  stopifnot(is.numeric(temps), is.numeric(losses),
            length(temps) == length(losses), length(temps) >= 3)

  df <- data.frame(temp = temps, loss = losses)
  x_pad <- (max(temps) - min(temps)) * 0.05

  ggplot(df, aes(x = .data$temp, y = .data$loss)) +
    geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                colour = CONTROL_LIMIT_COLOUR, linewidth = 0.7,
                span = 0.9) +
    geom_point(shape = 4, size = 4, stroke = 1.2,
               colour = CONTROL_LIMIT_COLOUR) +
    scale_x_continuous(breaks = temps,
                       labels = paste0(temps, "°C"),
                       limits = c(min(temps) - x_pad, max(temps) + x_pad),
                       expand = c(0, 0)) +
    scale_y_continuous(breaks = y_breaks,
                       labels = paste0(y_breaks, "%"),
                       limits = c(min(y_breaks), max(y_breaks)),
                       expand = c(0, 0)) +
    labs(y = "Loss") +
    run_chart_theme() +
    theme(axis.title.y = element_text(color = CHART_FG, size = 14,
                                      angle = 0, vjust = 1,
                                      margin = margin(r = 6)),
          axis.text.x  = element_text(color = CHART_FG, size = 12))
}

# --- Specification limits diagram (Day 7 page 19) ---

#' Plot Neave's specification-limits "knife edge" diagram
#'
#' A horizontal number line with two vertical ticks at the Lower (LSL) and
#' Upper (USL) Specification Limits, and four labelled results sitting
#' just inside/outside each limit. By the conformance-to-specification
#' rule, the two outside points (\emph{b} and \emph{d}) are rejected
#' while the two inside points (\emph{a} and \emph{c}) are accepted —
#' even though each pair is practically indistinguishable. Neave's
#' "second logical flaw".
#'
#' @return A ggplot2 object.
#' @examples
#' specification_limits_diagram()
specification_limits_diagram <- function() {
  # Coordinates are in arbitrary units; only relative positions matter.
  lsl_x <- 1
  usl_x <- 6
  tick_half <- 0.18
  inside_offset  <- 0.08
  outside_offset <- 0.08

  ggplot() +
    annotate("segment", x = lsl_x - 1, xend = usl_x + 1, y = 0, yend = 0,
             colour = CHART_FG, linewidth = 0.6) +
    annotate("segment", x = lsl_x, xend = lsl_x,
             y = -tick_half, yend = tick_half,
             colour = CHART_FG, linewidth = 0.6) +
    annotate("segment", x = usl_x, xend = usl_x,
             y = -tick_half, yend = tick_half,
             colour = CHART_FG, linewidth = 0.6) +
    annotate("text", x = lsl_x, y = -tick_half - 0.05, label = "LSL",
             hjust = 0.5, vjust = 1, colour = CHART_FG, size = 5) +
    annotate("text", x = usl_x, y = -tick_half - 0.05, label = "USL",
             hjust = 0.5, vjust = 1, colour = CHART_FG, size = 5) +
    annotate("text", x = lsl_x - outside_offset, y = tick_half + 0.05,
             label = "b", hjust = 1, vjust = 0,
             colour = CHART_FG, size = 5) +
    annotate("text", x = lsl_x + inside_offset, y = tick_half + 0.05,
             label = "a", hjust = 0, vjust = 0,
             colour = CHART_FG, size = 5) +
    annotate("text", x = usl_x - inside_offset, y = tick_half + 0.05,
             label = "c", hjust = 1, vjust = 0,
             colour = CHART_FG, size = 5) +
    annotate("text", x = usl_x + outside_offset, y = tick_half + 0.05,
             label = "d", hjust = 0, vjust = 0,
             colour = CHART_FG, size = 5) +
    coord_cartesian(xlim = c(lsl_x - 1.1, usl_x + 1.1),
                    ylim = c(-0.55, 0.55), clip = "off") +
    theme_void() +
    theme(plot.background  = element_rect(fill = "transparent", colour = NA),
          panel.background = element_rect(fill = "transparent", colour = NA))
}

#' Create a Red Beads results data frame
#'
#' Builds a tibble of worker-by-day red bead counts with row/column totals,
#' suitable for rendering with \code{render_redbeads_table}. NA values are
#' preserved for days not yet revealed (progressive disclosure).
#'
#' @param day1 Numeric vector of length 6. Red bead counts for Day 1.
#' @param day2 Numeric vector of length 6. Red bead counts for Day 2.
#' @param day3 Numeric vector of length 6. Red bead counts for Day 3.
#' @param day4 Numeric vector of length 6. Red bead counts for Day 4.
#' @param workers Character vector of length 6. Worker names.
#' @return A tibble with 7 rows (6 workers + "Daily Totals") and columns
#'   Name, Day 1-4, and Totals.
#' @examples
#' make_redbeads_df(day1 = c(9, 11, 12, 7, 9, 13))
make_redbeads_df <- function(
  day1    = rep(NA_real_, 6),
  day2    = rep(NA_real_, 6),
  day3    = rep(NA_real_, 6),
  day4    = rep(NA_real_, 6),
  workers = c("Audrey","John","Al","Carol","Ben","Ed")
) {
  days <- c("Day 1","Day 2","Day 3","Day 4")
  
  df <- tibble(
    Name    = workers,
    `Day 1` = day1,
    `Day 2` = day2,
    `Day 3` = day3,
    `Day 4` = day4
  ) |> 
    rowwise() |> 
    mutate(
      Totals = if (all(!is.na(c_across(all_of(days))))) sum(c_across(all_of(days))) else NA_real_
    ) |> 
    ungroup()
  
  # compute bottom row but only if entire column is non‐NA
  daily_vals <- sapply(df[days], function(col) if(all(!is.na(col))) sum(col) else NA_real_)
  grand_val   <- if(all(!is.na(daily_vals))) sum(daily_vals) else NA_real_
  bottom <- tibble(
    Name    = "Daily Totals",
    `Day 1` = daily_vals[1],
    `Day 2` = daily_vals[2],
    `Day 3` = daily_vals[3],
    `Day 4` = daily_vals[4],
    Totals  = grand_val
  )
  
  bind_rows(df, bottom)
}

#' Render a Red Beads results table as a gt object
#'
#' Takes the output of \code{make_redbeads_df} and renders it as a styled
#' gt table with bold borders, centred column labels, and a separated
#' "Daily Totals" row.
#'
#' @param df A tibble produced by \code{make_redbeads_df}.
#' @return A gt table object ready for display.
#' @examples
#' make_redbeads_df(day1 = c(9, 11, 12, 7, 9, 13)) |> render_redbeads_table()
render_redbeads_table <- function(df) {
  df |> 
    gt(rowname_col = "Name") |> 
    fmt_missing(everything(), missing_text = "") |> 
    tab_options(
      table.background.color = "white",
      row.striping.background_color = "white",
      table.border.top.style = "solid",
      table.border.top.width = px(4),
      table.border.top.color = "black",
      table.border.right.style = "solid",
      table.border.right.width = px(4),
      table.border.right.color = "black",
      table.border.bottom.style = "solid",
      table.border.bottom.width = px(4),
      table.border.bottom.color = "black",
      table.border.left.style = "solid",
      table.border.left.width = px(4),
      table.border.left.color = "black"
    ) |> 
    # Add thin black horizontal grid lines between body rows
    tab_style(
      style = cell_borders(sides = "bottom", color = "#c1c1c1", weight = px(1)),
      locations = cells_body()
    ) |> 
    tab_style(
      style = cell_borders(sides = "left", color = "#c1c1c1", weight = px(1)),
      locations = cells_column_labels()
    ) |> 
    # Add thin black vertical grid lines between body columns
    tab_style(
      style = cell_borders(sides = "right", color = "#c1c1c1", weight = px(1)),
      locations = cells_body()
    ) |> 
    # Add thick black border at the left of the "Day 1" column label (ensures continuity)
    tab_style(
      style = cell_borders(sides = "left", color = "black", weight = px(2)),
      locations = cells_body(columns = "Totals")
    ) |> 
    tab_style(
      style = cell_borders(sides = "top", color = "black", weight = px(2)),
      locations = cells_body(rows = 7)
    ) |> 
    tab_style(
      style = cell_borders(sides = "bottom", color = "black", weight = px(2)),
      locations = cells_column_labels()
    ) |> 
    tab_style(
      style = cell_borders(sides = "right", color = "black", weight = px(2)),
      locations = cells_stub()
    ) |> 
    tab_style(
      style = cell_borders(sides = "top", color = "black", weight = px(2)),
      locations = cells_stub(rows = 7)
    ) |> 
      tab_style(
        style = cell_borders(sides = c("bottom", "right"), color = "black", weight = px(2)),
        locations = cells_stubhead()
      ) |> 
    # Bold column labels
    tab_style(
      style = cell_text(weight = "bold", align = "center"),
      locations = cells_column_labels()
    ) |> 
    # Bold 'Daily Totals' in the stub
    tab_style(
      style = cell_text(weight = "bold"),
      locations = cells_stub(rows = "Daily Totals")
    )
}
