source("renv/activate.R")

# Project-wide R setup for Quarto rendering
# See: https://github.com/lddurbin/twelve_days_to_deming/issues/68
# Guard: only source setup.R when ALL required packages are available
# (skipped during renv bootstrap/restore and other CI steps)
local({
  setup_file <- file.path("R", "setup.R")
  deps_available <- all(vapply(
    c("knitr", "ggplot2", "dplyr", "gt"),
    requireNamespace, logical(1), quietly = TRUE
  ))
  if (file.exists(setup_file) && deps_available) {
    source(setup_file)
  }
})
