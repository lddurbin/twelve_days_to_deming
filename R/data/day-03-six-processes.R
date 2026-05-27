# Day 3 "Six Processes" datasets
# =================================================================
# Source: Neave, Day 3 page 19 — twelve control charts arranged as six
# pairs (A1/A2 ... F1/F2). Each chart uses 24 data-points.
#
# Two data-origin tiers:
#
# 1. Simulated (Neave's "All-Knowing" trio):
#    - A: four dice — totals.
#    - B: twenty-five coins — number of Heads per toss.
#    - C: Red Beads — counts of red beads in the paddle.
#    Neave does not print the original values; he simulated them when
#    preparing the source material in the 1980s. We reproduce the same
#    recipes under fixed seeds so the chart shapes match the published
#    image. See the deviations log under `docs/deviations/` for the
#    rationale and the seed-selection methodology.
#
# 2. Digitised (the "serious" trio — D, E, F):
#    - D: Neave's breakfast pulse-rates over 24 consecutive days.
#    - E: average measurements on 24 small samples of manufactured
#         cigarette-lighter sockets (Japanese case study).
#    - F: monthly United States trade deficit, billions of dollars
#         (Chart F1: 2006-07; Chart F2: 2008-09).
#    The original raw values are not reproducible — D is personal data,
#    E is a confidential case study, F is published BEA data Neave then
#    rounded for the chart. We digitise from the printed chart so the
#    visual shape matches; we are not trying to recover historical truth.
# =================================================================

# Roll `n_dice` six-sided dice `n_throws` times; return the totals.
roll_dice_totals <- function(n_dice, n_throws) {
  replicate(n_throws,
            sum(sample.int(6, size = n_dice, replace = TRUE)))
}

# Toss `n_coins` fair coins `n_tosses` times; return the Heads count
# for each toss (Binomial(n_coins, 0.5)).
toss_coins_heads <- function(n_coins, n_tosses) {
  rbinom(n_tosses, size = n_coins, prob = 0.5)
}

# Draw `n_paddles` paddles of 50 beads from a Red Beads urn with the
# given fraction red (Neave's Day 2 urn nominally 20% red).
draw_red_beads <- function(n_paddles, paddle_size = 50, p_red = 0.20) {
  rbinom(n_paddles, size = paddle_size, prob = p_red)
}

# --- Process A: four-dice totals ---------------------------------
#
# Seed chosen so that the SD-based ("magenta") limits on A1 come out
# virtually identical to the MR-based limits, while the SD-based limits
# on A2 come out roughly twice as wide as MR — exactly the contrast
# Neave's prose makes about page 19. See docs/deviations/.

set.seed(274)
process_A1 <- roll_dice_totals(n_dice = 4, n_throws = 24)
process_A2 <- c(
  roll_dice_totals(n_dice = 4, n_throws = 6),
  roll_dice_totals(n_dice = 2, n_throws = 6),
  roll_dice_totals(n_dice = 6, n_throws = 12)
)

# --- Process B: heads when 25 coins are tossed --------------------
#
# B1: 25 coins for all 24 tosses.
# B2: 25 coins for the first 14 tosses, then two extra coins each toss
# (27, 29, 31, ... 45) — the special-cause recipe Neave describes.

set.seed(151)
process_B1 <- toss_coins_heads(n_coins = 25, n_tosses = 24)
process_B2 <- c(
  toss_coins_heads(n_coins = 25, n_tosses = 14),
  vapply(seq(27, 45, by = 2),
         function(n) toss_coins_heads(n_coins = n, n_tosses = 1),
         numeric(1))
)

# --- Process C: Red Beads counts ----------------------------------
#
# C1: 24 paddles of 50 beads from a 20%-red urn.
# C2: first 18 paddles as normal; last 6 are the sum of two junior
# inspectors' counts on the same paddle — so roughly double the count
# (the "process of *recording* the data" went out of control, not the
# physical process). We model the inspector-sum as 2 * single-count.

set.seed(88)
process_C1 <- draw_red_beads(24)
process_C2 <- c(
  draw_red_beads(18),
  2L * draw_red_beads(6)
)

# --- Process D: breakfast pulse-rates -----------------------------
#
# Digitised from Neave page 19. The chart's y-axis runs 60–100. D1 sits
# in the high 70s / mid 80s (Neave noted these were "rather unhealthily
# high"). D2 keeps that baseline through the first 20 days then drops
# noticeably for the final four days — Neave's newly-prescribed
# beta-blocker.

process_D1 <- c(78, 88, 84, 82, 91, 87, 89, 83, 91, 86, 82, 85,
                84, 87, 91, 86, 83, 88, 85, 90, 87, 86, 84, 75)
process_D2 <- c(84, 78, 81, 85, 79, 82, 86, 84, 80, 82, 87, 79,
                85, 82, 80, 83, 78, 81, 84, 78, 70, 68, 65, 62)

# --- Process E: cigarette-lighter socket measurements -------------
#
# Digitised from Neave page 19. The y-axis runs 15.85–15.95 in 0.05
# increments — fine-tolerance Japanese case-study measurements. E1 sits
# tightly around 15.91. E2 carries the same baseline but shows a
# transient fault around points 10–12 (a brief spike to 15.93–15.94),
# soon "more than effectively rectified".

process_E1 <- c(15.91, 15.91, 15.91, 15.92, 15.91, 15.90, 15.91, 15.92,
                15.91, 15.91, 15.92, 15.91, 15.91, 15.91, 15.92, 15.91,
                15.91, 15.91, 15.91, 15.92, 15.91, 15.91, 15.91, 15.91)
process_E2 <- c(15.91, 15.91, 15.91, 15.91, 15.92, 15.91, 15.91, 15.91,
                15.92, 15.93, 15.94, 15.93, 15.92, 15.91, 15.91, 15.91,
                15.91, 15.91, 15.91, 15.92, 15.91, 15.91, 15.91, 15.91)

# --- Process F: US monthly trade deficits (billions USD) ----------
#
# Digitised from Neave page 19. F1 covers 2006–07 (stable, sitting
# around the $60–70 bn band). F2 covers 2008–09 — the GFC drops the
# deficit sharply mid-period, with partial recovery toward year-end.
# These approximate the *shapes* Neave printed, not the BEA series
# values; see docs/deviations/.

process_F1 <- c(63, 67, 65, 60, 64, 65, 69, 67, 65, 64, 70, 64,
                60, 65, 64, 62, 57, 61, 60, 58, 58, 55, 56, 58)
process_F2 <- c(60, 65, 60, 64, 70, 68, 60, 55, 45, 35, 30, 35,
                30, 30, 35, 35, 40, 45, 50, 45, 40, 35, 40, 45)

# --- Combined list for panel rendering ----------------------------
#
# Each entry carries the data, display label, and y-axis framing
# Neave uses on page 19. `y_breaks` are the major ticks; `y_limits`
# extend slightly beyond to leave breathing room above/below the
# tallest/shortest points and the control limits.

six_processes <- list(
  A1 = list(data = process_A1, label = "A1",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  A2 = list(data = process_A2, label = "A2",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  B1 = list(data = process_B1, label = "B1",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  B2 = list(data = process_B2, label = "B2",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  C1 = list(data = process_C1, label = "C1",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  C2 = list(data = process_C2, label = "C2",
            y_limits = c(0, 30),  y_breaks = seq(0, 30, by = 10)),
  D1 = list(data = process_D1, label = "D1",
            y_limits = c(60, 100), y_breaks = seq(60, 100, by = 10)),
  D2 = list(data = process_D2, label = "D2",
            y_limits = c(60, 100), y_breaks = seq(60, 100, by = 10)),
  E1 = list(data = process_E1, label = "E1",
            y_limits = c(15.85, 15.95), y_breaks = seq(15.85, 15.95, by = 0.05)),
  E2 = list(data = process_E2, label = "E2",
            y_limits = c(15.85, 15.95), y_breaks = seq(15.85, 15.95, by = 0.05)),
  F1 = list(data = process_F1, label = "F1",
            y_limits = c(25, 100), y_breaks = seq(25, 100, by = 25)),
  F2 = list(data = process_F2, label = "F2",
            y_limits = c(25, 100), y_breaks = seq(25, 100, by = 25))
)
