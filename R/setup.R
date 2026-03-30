# Project-wide R setup for Quarto rendering
# Sourced automatically via .Rprofile — no per-chapter setup chunk needed.
# See: https://github.com/lddurbin/twelve_days_to_deming/issues/68

knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)
source(file.path("R", "functions", "main-functions.R"))
