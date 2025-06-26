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