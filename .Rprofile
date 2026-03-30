source("renv/activate.R")

# Project-wide R setup for Quarto rendering
# See: https://github.com/lddurbin/twelve_days_to_deming/issues/68
local({
  setup_file <- file.path("R", "setup.R")
  if (file.exists(setup_file)) {
    source(setup_file)
  } else {
    message("Note: R/setup.R not found from current working directory; project setup skipped.")
  }
})
