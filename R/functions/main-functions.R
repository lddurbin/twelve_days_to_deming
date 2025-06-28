library(ggplot2)
library(dplyr)
library(gt)

# Function to create clock with inward-facing dashes for hour ticks and hands attached to inner circle
create_clock <- function(hour, minute) {
  
  # Convert time to radians for plotting
  hour_angle <- (hour %% 12 + minute / 60) * 30  # 360 degrees / 12 hours = 30 degrees per hour
  minute_angle <- minute * 6                     # 360 degrees / 60 minutes = 6 degrees per minute
  
  # Convert degrees to radians
  hour_angle <- (90 - hour_angle) * pi / 180
  minute_angle <- (90 - minute_angle) * pi / 180
  
  # Clock hands data
  clock_data <- data.frame(
    x = c(0, 0),
    y = c(0, 0),
    xend = c(0.015 * cos(hour_angle), 0.023 * cos(minute_angle)),  # Slightly reduce hand length
    yend = c(0.015 * sin(hour_angle), 0.023 * sin(minute_angle)),
    hand = c("hour", "minute")
  )
  
  # Clock ticks as dashes facing inward
  tick_angles <- seq(0, 2 * pi, length.out = 13)[-13]  # Remove the last value (full circle repetition)
  
  tick_data <- data.frame(
    x = 0.028 * cos(tick_angles),
    y = 0.028 * sin(tick_angles),
    xend = 0.02 * cos(tick_angles),  # Short inward-facing dashes
    yend = 0.02 * sin(tick_angles)
  )
  
  # Create ggplot clock
  ggplot() + 
    # Circle for clock face (smaller size)
    geom_point(aes(x = 0, y = 0), size = 150, shape = 1) +  # Adjust circle size
    
    # Small inner circle at the center of the clock
    geom_point(aes(x = 0, y = 0), size = 15, shape = 1) +  # Smaller inner circle for hands attachment
    
    # Clock ticks as inward-facing dashes
    geom_segment(data = tick_data, aes(x = x, y = y, xend = xend, yend = yend), size = 0.4) + 
    
    # Hour and minute hands (slightly shorter)
    geom_segment(data = clock_data, aes(x = x, y = y, xend = xend, yend = yend, colour = hand), size = 1.5) +
    scale_colour_manual(values = c("black", "black")) +
    coord_fixed(xlim = c(-0.1, 0.1), ylim = c(-0.1, 0.1), expand = FALSE) + # Adjust to ensure clock fills the space
    theme_void() + 
    theme(
      legend.position = "none",
      plot.margin = unit(c(-0.01, -0.01, -0.01, -0.01), "cm"),
      panel.spacing = unit(0, "cm"),
      plot.background = element_rect(fill = "transparent", colour = NA)
      ) +
    coord_fixed()
}

# Extended generic run chart function to allow horizontal reference lines with labels
basic_run_chart <- function(df, x, y, line_color = "#7a0000", line_size = 1, 
                            x_limits = NULL, y_limits = NULL, x_breaks = NULL, y_breaks = NULL, minor_y_breaks = NULL,
                            hlines = NULL, hline_labels = NULL, hline_label_color = "blue", hline_color = "blue", hline_size = 1) {
  p <- ggplot(df, aes_string(x = x, y = y)) +
    geom_line(color = line_color, size = line_size) +
    scale_x_continuous(breaks = x_breaks, limits = x_limits, expand = c(0, 0)) +
    scale_y_continuous(breaks = y_breaks, limits = y_limits, minor_breaks = minor_y_breaks, expand = c(0, 0)) +
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.major.y = element_line(color = "grey80", size = .8),
      panel.grid.major.x = element_line(color = "#cccccc", size = 1.2),
      panel.grid.minor.y = element_line(color = "grey90", size = .3),
      panel.grid.minor.x = element_blank(),
      panel.background = element_blank(),
      plot.margin = margin(5, 30, 5, 5),
      axis.ticks.y = element_line(color = "black"),
      axis.ticks.x = element_blank(),
      axis.text.y  = element_text(color = "black", size = 16),
      axis.text.x  = element_text(color = "black", size = 14),
      axis.title = element_blank(),
      axis.line.y = element_line(color = "black", size = 1),
      axis.line.x = element_blank()
    )
  if (!is.null(hlines)) {
    for (i in seq_along(hlines)) {
      p <- p + geom_hline(yintercept = hlines[i], color = hline_color, size = hline_size)
      if (!is.null(hline_labels) && !is.na(hline_labels[i])) {
        # Place label at right edge, just above the line, right-aligned and inside plot
        p <- p + annotate(
          "text",
          x = max(df[[x]]),
          y = hlines[i] + 1.2,  # Just above the line
          label = hline_labels[i],
          hjust = 1,
          vjust = 0,
          color = hline_label_color,
          size = 7,
          fontface = "bold"
        )
      }
    }
  }
  p
}

# Function to plot a run chart for a vector of sales values (legacy interface)
run_chart_plot <- function(sales_vec) {
  df <- data.frame(
    month = 1:length(sales_vec),
    sales = sales_vec
  )
  ggplot(df, aes(month, sales)) +
    geom_line(
      colour    = "#ed0000",
      size      = 6,
      linejoin  = "round"
    ) +
    scale_x_continuous(
      breaks = 1:length(sales_vec),
      expand = c(0, 0)
    ) +
    scale_y_continuous(
      limits      = c(10, 25),
      breaks      = seq(10, 25, by = 5),
      minor_breaks = seq(10, 25, by = 1),
      expand      = c(0, 0)
    ) +
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.major.y = element_line(color = "grey80", size = .8),
      panel.grid.major.x = element_line(color = "#cccccc", size = 1.2),
      panel.grid.minor.y = element_line(color = "grey90", size = .3),
      panel.grid.minor.x = element_blank(),
      panel.background = element_blank(),
      plot.margin = margin(5, 5, 5, 5),
      axis.ticks.y = element_line(color = "black"),
      axis.ticks.x = element_blank(),
      axis.text.y  = element_text(color = "black", size = 16),
      axis.text.x  = element_text(color = "black", size = 14),
      axis.title = element_blank(),
      axis.line.y = element_line(color = "black", size = 1),
      axis.line.x = element_blank()
    )
}

# Function to plot the red beads control chart with UCL and LCL
red_beads_control_chart <- function(red_beads_vec, LCL = 1.4, UCL = 18.2) {
  df <- data.frame(order = 1:length(red_beads_vec), beads = red_beads_vec)
  basic_run_chart(
    df, x = "order", y = "beads",
    line_color = "#ed0000", line_size = 2,
    x_limits = c(1, length(red_beads_vec)),
    y_limits = c(0, 26),
    x_breaks = 1:length(red_beads_vec),
    y_breaks = seq(0, 25, by = 5),
    minor_y_breaks = seq(0, 25, by = 1),
    hlines = c(LCL, UCL),
    hline_labels = c("LCL", "UCL"),
    hline_label_color = "blue",
    hline_color = "blue",
    hline_size = 1
  )
}

# Function to plot the red beads run chart (no control limits)
red_beads_run_chart <- function(red_beads_vec) {
  df <- data.frame(order = 1:length(red_beads_vec), beads = red_beads_vec)
  ggplot(df, aes(order, beads)) +
    geom_line(
      colour    = "#ed0000",
      size      = 2,
      linejoin  = "round"
    ) +
    scale_x_continuous(
      breaks = 1:length(red_beads_vec),
      expand = c(0, 0)
    ) +
    scale_y_continuous(
      limits      = c(0, 26),
      breaks      = seq(0, 25, by = 5),
      minor_breaks = seq(0, 25, by = 1),
      expand      = c(0, 0)
    ) +
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.major.y = element_line(color = "grey80", size = .8),
      panel.grid.major.x = element_line(color = "#cccccc", size = 1.2),
      panel.grid.minor.y = element_line(color = "grey90", size = .3),
      panel.grid.minor.x = element_blank(),
      panel.background = element_blank(),
      plot.margin = margin(5, 5, 5, 5),
      axis.ticks.y = element_line(color = "black"),
      axis.ticks.x = element_blank(),
      axis.text.y  = element_text(color = "black", size = 16),
      axis.text.x  = element_text(color = "black", size = 14),
      axis.title = element_blank(),
      axis.line.y = element_line(color = "black", size = 1),
      axis.line.x = element_blank()
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
  ) %>%
    rowwise() %>%
    mutate(
      Totals = if (all(!is.na(c_across(all_of(days))))) sum(c_across(all_of(days))) else NA_real_
    ) %>%
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
  df %>%
    gt(rowname_col = "Name") %>%
    fmt_missing(everything(), missing_text = "") %>%
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
    ) %>%
    # Bold 'Daily Totals' in the stub
    tab_style(
      style = cell_text(weight = "bold"),
      locations = cells_stub(rows = "Daily Totals")
    )
}
