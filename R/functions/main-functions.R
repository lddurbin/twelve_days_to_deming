library(ggplot2)
library(dplyr)
library(gt)
library(DiagrammeR)

# --- Named constants ---

CHART_LINE_COLOUR <- "#ed0000"
CONTROL_LIMIT_COLOUR <- "blue"

# --- Run charts ---

#' Create a minimal ggplot2 theme for run charts
#'
#' Returns a theme with light gridlines, no axis titles, and configurable
#' right margin (increased when horizontal reference lines have labels).
#'
#' @param right_margin Numeric. Right margin in points. Default 5; use ~30
#'   when horizontal line labels are present.
#' @return A ggplot2 theme object.
run_chart_theme <- function(right_margin = 5) {
  theme_minimal(base_size = 14) +
    theme(
      panel.grid.major.y = element_line(color = "grey80", linewidth = .8),
      panel.grid.major.x = element_line(color = "#cccccc", linewidth = 1.2),
      panel.grid.minor.y = element_line(color = "grey90", linewidth = .3),
      panel.grid.minor.x = element_blank(),
      panel.background    = element_blank(),
      plot.margin         = margin(5, right_margin, 5, 5),
      axis.ticks.y = element_line(color = "black"),
      axis.ticks.x = element_blank(),
      axis.text.y  = element_text(color = "black", size = 16),
      axis.text.x  = element_text(color = "black", size = 14),
      axis.title   = element_blank(),
      axis.line.y  = element_line(color = "black", linewidth = 1),
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
