library(ggplot2)
library(dplyr)

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