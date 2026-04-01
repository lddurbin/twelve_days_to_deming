source("renv/activate.R")

# Project-wide R setup for Quarto rendering
# See: https://github.com/lddurbin/twelve_days_to_deming/issues/68
# Guard: only source setup.R when knitr is installed (skipped during renv bootstrap/restore)
local({
  setup_file <- file.path("R", "setup.R")
  if (file.exists(setup_file) && requireNamespace("knitr", quietly = TRUE)) {
    source(setup_file)
  }
})
