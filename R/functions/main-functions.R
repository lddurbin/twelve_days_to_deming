library(ggplot2)
library(dplyr)
library(gt)
library(scales)

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
                           show_x_labels = TRUE) {
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

  p <- ggplot(df, aes(x, y)) +
    scale_x_continuous(breaks = seq_along(values), expand = c(0, 0)) +
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
      p <- p + geom_hline(yintercept = hlines[i], color = CONTROL_LIMIT_COLOUR, linewidth = 1)
      if (!is.null(hline_labels) && !is.na(hline_labels[i])) {
        p <- p + annotate("text", x = label_x,
                          y = hlines[i] + offsets[i],
                          label = hline_labels[i],
                          hjust = label_hjust,
                          vjust = if (offsets[i] >= 0) 0 else 1,
                          color = CONTROL_LIMIT_COLOUR, size = 7, fontface = "bold")
      }
    }
  }
  p
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
#' Uses \code{geom_point(shape = 22)} so the squares stay square regardless
#' of the panel's aspect ratio (true square shapes are sized in millimetres,
#' not data units — \code{geom_tile} would only look square when the data
#' aspect matches the panel aspect).
#'
#' @param values Numeric vector. Integer-like observations to stack.
#' @param x_breaks Numeric vector or NULL. Major x-axis tick positions.
#'   If NULL, ggplot picks the breaks via its default heuristic.
#' @param box_size Numeric. Square edge length in mm (passed as the
#'   \code{size} argument to \code{geom_point}). Default 12; reduce if the
#'   tallest stack starts touching the chart top.
#' @return A ggplot2 object.
#' @examples
#' stacked_boxes_plot(c(10, 11, 11, 11, 12, 12), x_breaks = 10:12)
stacked_boxes_plot <- function(values, x_breaks = NULL, box_size = 12) {
  stopifnot(is.numeric(values), length(values) >= 1)

  df <- data.frame(value = values) |>
    dplyr::group_by(.data$value) |>
    dplyr::mutate(stack = dplyr::row_number()) |>
    dplyr::ungroup()

  max_stack <- max(df$stack)

  p <- ggplot(df, aes(x = .data$value, y = .data$stack)) +
    geom_point(shape = 22, size = box_size,
               fill = CHART_LINE_COLOUR, colour = CHART_FG, stroke = 0.4)

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
