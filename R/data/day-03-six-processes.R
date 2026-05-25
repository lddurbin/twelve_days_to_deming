# Day 3 "Six Processes" datasets
# =================================================================
# Source: Neave, Day 3 page 19 — twelve control charts arranged as six
# pairs (A1/A2 ... F1/F2). Each chart uses 24 data-points.
#
# Process A is the dice illustration: the data are the total "spots"
# showing when four dice are thrown 24 times.
#
#   A1 (stable):   four dice for all 24 throws.
#   A2 (unstable): four dice for the first 6 throws, then two dice for
#                  the next 6 throws, then six dice for the remaining
#                  12 throws — the special-cause recipe described in
#                  the prose accompanying the chart.
#
# Neave does not print the original throw-by-throw values; he simulated
# them himself when preparing the source material in the 1980s. We
# reproduce the same recipe under a fixed seed so the chart shapes
# match the published image. See `docs/deviations-from-source.md` for
# the rationale.
#
# This file currently defines process A only. Processes B–F are added
# incrementally as later issues (#344 onward) replace each chart.
# =================================================================

# Roll `n_dice` six-sided dice `n_throws` times; return the totals.
roll_dice_totals <- function(n_dice, n_throws) {
  replicate(n_throws,
            sum(sample.int(6, size = n_dice, replace = TRUE)))
}

# --- Process A: four-dice totals ---------------------------------
#
# Seed chosen so that the SD-based ("purple") limits on A1 come out
# virtually identical to the MR-based limits, while the SD-based limits
# on A2 come out roughly twice as wide as MR — exactly the contrast
# Neave's prose makes about page 19. See deviations-from-source.md.

set.seed(274)

# A1: 24 throws, four dice each — stable process.
process_A1 <- roll_dice_totals(n_dice = 4, n_throws = 24)

# A2: special-cause recipe (4 dice, then 2 dice, then 6 dice).
process_A2 <- c(
  roll_dice_totals(n_dice = 4, n_throws = 6),
  roll_dice_totals(n_dice = 2, n_throws = 6),
  roll_dice_totals(n_dice = 6, n_throws = 12)
)
