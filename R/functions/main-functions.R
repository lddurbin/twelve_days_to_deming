library(ggplot2)
library(dplyr)
library(gt)

# --- Named constants ---

CLOCK <- list(
  hour_hand   = 0.015,
  minute_hand = 0.023,
  tick_outer  = 0.028,
  tick_inner  = 0.02,
  face_size   = 150,
  center_size = 15,
  tick_width  = 0.4,
  hand_width  = 1.5,
  coord_limit = 0.1,
  margin_cm   = -0.01
)

CHART_LINE_COLOUR <- "#ed0000"
CONTROL_LIMIT_COLOUR <- "blue"

# --- Clock ---

create_clock <- function(hour, minute) {
  stopifnot(is.numeric(hour), is.numeric(minute))

  hour_angle <- (hour %% 12 + minute / 60) * 30
  minute_angle <- minute * 6

  hour_angle <- (90 - hour_angle) * pi / 180
  minute_angle <- (90 - minute_angle) * pi / 180

  clock_data <- data.frame(
    x = c(0, 0),
    y = c(0, 0),
    xend = c(CLOCK$hour_hand * cos(hour_angle), CLOCK$minute_hand * cos(minute_angle)),
    yend = c(CLOCK$hour_hand * sin(hour_angle), CLOCK$minute_hand * sin(minute_angle)),
    hand = c("hour", "minute")
  )

  tick_angles <- seq(0, 2 * pi, length.out = 13)[-13]

  tick_data <- data.frame(
    x = CLOCK$tick_outer * cos(tick_angles),
    y = CLOCK$tick_outer * sin(tick_angles),
    xend = CLOCK$tick_inner * cos(tick_angles),
    yend = CLOCK$tick_inner * sin(tick_angles)
  )

  ggplot() +
    geom_point(aes(x = 0, y = 0), size = CLOCK$face_size, shape = 1) +
    geom_point(aes(x = 0, y = 0), size = CLOCK$center_size, shape = 1) +
    geom_segment(data = tick_data, aes(x = x, y = y, xend = xend, yend = yend), linewidth = CLOCK$tick_width) +
    geom_segment(data = clock_data, aes(x = x, y = y, xend = xend, yend = yend, colour = hand), linewidth = CLOCK$hand_width) +
    scale_colour_manual(values = c("black", "black")) +
    theme_void() +
    theme(
      legend.position = "none",
      plot.margin = unit(rep(CLOCK$margin_cm, 4), "cm"),
      panel.spacing = unit(0, "cm"),
      plot.background = element_rect(fill = "transparent", colour = NA)
    ) +
    coord_fixed(xlim = c(-CLOCK$coord_limit, CLOCK$coord_limit),
                ylim = c(-CLOCK$coord_limit, CLOCK$coord_limit), expand = FALSE)
}

# --- Run charts ---

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

# Function to plot the red beads control chart with UCL and LCL
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
