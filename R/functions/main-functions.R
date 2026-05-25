library(ggplot2)
library(dplyr)
library(gt)

# =============================================================================
# R-figure conventions (project-wide)
# =============================================================================
#
# Output device: chart chunks render as inline SVG via `dev = "svglite"`
# (set in R/setup.R). This is what makes dark-mode re-skin possible — see
# the "Dark-mode mechanism" note below.
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
#     quirk — see [[feedback_image_alt_lightbox]] in memory.
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
#' Returns a theme with mid-grey gridlines, no axis titles, transparent
#' plot/panel backgrounds (so the surrounding page colour shows through
#' in either light or dark mode), and a configurable right margin
#' (increased when horizontal reference lines have labels).
#'
#' Axis ink uses CHART_FG ("black"), which svglite emits without an
#' inline fill/stroke declaration so dark-mode CSS can re-skin it without
#' !important. See the conventions block at the top of this file.
#'
#' @param right_margin Numeric. Right margin in points. Default 5; use ~30
#'   when horizontal line labels are present.
#' @return A ggplot2 theme object.
run_chart_theme <- function(right_margin = 5) {
  theme_minimal(base_size = 14) +
    theme(
      panel.grid.major.y = element_line(color = CHART_GRID, linewidth = .8),
      panel.grid.major.x = element_line(color = CHART_GRID, linewidth = 1.2),
      panel.grid.minor.y = element_line(color = CHART_GRID_FAINT, linewidth = .3),
      panel.grid.minor.x = element_blank(),
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
}

#' Plot a run chart (time series line graph)
#'
#' Draws a run chart connecting sequential values with a coloured line.
#' Optionally adds horizontal reference lines (e.g. control limits).
#'
#' @param values Numeric vector. The data values to plot in order.
#' @param line_width Numeric. Width of the plotted line. Default 6.
#' @param y_limits Numeric vector of length 2. Y-axis range. Default c(10, 25).
#' @param y_breaks Numeric vector. Major y-axis tick positions.
#' @param y_minor_breaks Numeric vector. Minor y-axis tick positions.
#' @param hlines Numeric vector or NULL. Y-intercepts for horizontal reference
#'   lines (e.g. control limits).
#' @param hline_labels Character vector or NULL. Labels for the horizontal
#'   lines, positioned at the right edge of the chart.
#' @return A ggplot2 object containing the run chart.
#' @examples
#' run_chart_plot(c(13, 19, 18, 14, 16))
#' run_chart_plot(c(9, 11, 8, 14), hlines = c(5, 15), hline_labels = c("LCL", "UCL"))
run_chart_plot <- function(values, line_width = 6,
                           y_limits = c(10, 25),
                           y_breaks = seq(10, 25, by = 5),
                           y_minor_breaks = seq(10, 25, by = 1),
                           hlines = NULL, hline_labels = NULL) {
  stopifnot(is.numeric(values), length(values) >= 2)

  df <- data.frame(x = seq_along(values), y = values)
  right_margin <- if (!is.null(hlines)) 30 else 5

  p <- ggplot(df, aes(x, y)) +
    geom_line(colour = CHART_LINE_COLOUR, linewidth = line_width, linejoin = "round") +
    scale_x_continuous(breaks = seq_along(values), expand = c(0, 0)) +
    scale_y_continuous(limits = y_limits, breaks = y_breaks,
                       minor_breaks = y_minor_breaks, expand = c(0, 0)) +
    run_chart_theme(right_margin = right_margin)

  if (!is.null(hlines)) {
    for (i in seq_along(hlines)) {
      p <- p + geom_hline(yintercept = hlines[i], color = CONTROL_LIMIT_COLOUR, linewidth = 1)
      if (!is.null(hline_labels) && !is.na(hline_labels[i])) {
        p <- p + annotate("text", x = length(values), y = hlines[i] + 1.2,
                          label = hline_labels[i], hjust = 1, vjust = 0,
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
#'   bar. Default FALSE.
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
