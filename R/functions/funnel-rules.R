# =============================================================================
# Funnel Experiment — rule-1-through-rule-4 simulation helpers
# =============================================================================
#
# Each helper returns the sequence of resting positions produced by `n`
# successive drops of the marble under one of Deming's four Funnel-Experiment
# rules. The rules are described in *The Deming Dimension* Chapter 5, and in
# this repo on Day 3:
#   - Rule 1: content/days/day-03/11-the-first-two-rules-of-the-funnel.qmd
#             (§ "Rule 1 of the Funnel (Ford's Second Strategy)").
#   - Rule 2: same file, § "Rule 2 of the Funnel (Ford's First Strategy)".
#   - Rules 3 & 4: content/days/day-03/12-rules-3-and-4-of-the-funnel.qmd.
# The Optional Extras Part A control-chart treatment of all four rules lives
# at content/appendix/optional-extras/01-part-a-funnel-charts.qmd.
#
# Model. Each drop's resting position is `aim + noise`, where `aim` is the
# location of the funnel and `noise ~ Normal(0, sd)`. The four rules differ
# only in how the funnel is repositioned between drops:
#
#   Rule 1 — "leave the funnel fixed at the target": aim stays at `target`
#            for every drop. Resting positions are i.i.d. Normal(target, sd).
#   Rule 2 — "compensate by the deviation just observed, relative to the
#            funnel's current position": aim_{i+1} = aim_i − (rest_i − target).
#            Equivalently: shift the funnel by the negative of the last
#            deviation-from-target. This is Ford's "automatic compensation".
#   Rule 3 — "place the funnel on the opposite side of the target at the
#            same distance the marble just landed from target":
#            aim_{i+1} = target − (rest_i − target) = 2·target − rest_i.
#            Each step's amplitude tends to grow — the classic "explodes"
#            behaviour.
#   Rule 4 — "place the funnel where the marble just landed":
#            aim_{i+1} = rest_i. This is a random walk on the resting
#            positions (`rest_{i+1} = rest_i + noise_{i+1}`) — drift away.
#
# Reproducibility. All four take a `seed` argument and call `set.seed(seed)`
# locally; nothing is read from or written to the global RNG state. The four
# illustrative defaults below were picked by sweeping seeds 1–300 against the
# characteristic-behaviour checks in tests/testthat/test-funnel-rules.R.
# They are not Neave's original Monte Carlo sequences (those values are not
# in the source PDF or this repo) — they are *illustrative* runs that exhibit
# each rule's signature shape.
#
# Vectorisation. Rules 1 and 4 admit clean closed-form vectorised
# expressions: Rule 1 is plain `rnorm`, Rule 4 is `target + cumsum(noise)`.
# Rule 2 also has a closed form — substituting `rest[i] = aim[i] + noise[i]`
# into the recurrence collapses to `rest[i] = target + noise[i] − noise[i−1]`
# for i ≥ 2 — so vectorisation is possible. Rule 3 is more genuinely
# sequential: the alternating-cumulative-sum closed form exists in principle
# but reads less clearly than the recurrence. For consistency, both Rule 2
# and Rule 3 use a `for` loop here. Each loop runs once per drop with O(1)
# work per iteration; at the n ≤ 50 sizes the consumer chart uses, there is
# no measurable benefit to vectorising.
#
# Why a separate file (not main-functions.R). The four sim helpers form a
# small, self-contained module; keeping them in their own file keeps the
# main file from growing further (it's already ~1500 lines) and makes the
# module easy to discover from a directory listing. Sourced from R/setup.R
# alongside main-functions.R.
# =============================================================================

#' Simulate Funnel Experiment Rule 1 (leave the funnel at the target)
#'
#' Generates `n` resting positions for the Funnel Experiment under Rule 1:
#' the funnel stays at `target` for every drop, so resting positions are
#' independent draws from Normal(target, sd).
#'
#' Source: Neave Day 3, "Rule 1 of the Funnel (Ford's Second Strategy)"
#'   (content/days/day-03/11-the-first-two-rules-of-the-funnel.qmd).
#'
#' Default seed `7` produces a stable, random-around-target run that
#' visually parallels a stable in-control process when fed into
#' `run_chart_plot()`. Override `seed` to explore other illustrative runs.
#'
#' @param n Integer. Number of drops. Must be >= 1.
#' @param seed Integer. RNG seed. Default 7.
#' @param sd Numeric. Standard deviation of each drop's offset from the
#'   funnel. Default 1.
#' @param target Numeric. Funnel position (and target). Default 0.
#' @return Numeric vector of length `n` (resting positions).
#' @examples
#' funnel_rule_1_sim(50)
#' funnel_rule_1_sim(15, seed = 7, sd = 5, target = 30)
funnel_rule_1_sim <- function(n, seed = 7, sd = 1, target = 0) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 1, n == as.integer(n))
  set.seed(seed)
  # Rule 1 is fully vectorisable — the aim never moves, so each drop is an
  # independent Normal(target, sd) draw. No loop needed.
  rnorm(n, mean = target, sd = sd)
}

#' Simulate Funnel Experiment Rule 2 (compensate by last deviation, relative)
#'
#' Generates `n` resting positions under Rule 2: after each drop, shift the
#' funnel by the negative of the just-observed deviation from target, so the
#' next aim is `current aim − (last rest − target)`. This is Ford's
#' "automatic compensation" device, and Deming's first cautionary tale.
#'
#' Source: Neave Day 3, "Rule 2 of the Funnel (Ford's First Strategy)"
#'   (content/days/day-03/11-the-first-two-rules-of-the-funnel.qmd).
#'
#' Behaviour. The compensation introduces strong negative lag-1
#' autocorrelation — high outcomes are followed by low ones and vice versa
#' — producing the characteristic central zig-zag. The series stays
#' bounded (does not drift), but its short-term variance is inflated
#' relative to Rule 1, which artificially widens MR-based control limits
#' (the "hugging the Central Line" effect Neave discusses on Optional
#' Extras Part A page 10).
#'
#' Default seed `2` produces a pronounced zig-zag suitable for a 50-drop
#' control chart demo.
#'
#' Loop vs closed form: substituting `rest[i] = aim[i] + noise[i]` into the
#' recurrence collapses it to `rest[i] = target + noise[i] − noise[i−1]` for
#' i ≥ 2, so vectorisation via lagged differences *is* possible. The loop
#' is kept for parity with `funnel_rule_3_sim()` (whose recurrence reads
#' more clearly than its alternating-cumulative-sum closed form) and
#' because at n ≤ 50 — the size the chart consumer uses — there is no
#' measurable benefit. The loop pre-draws all noise terms in one `rnorm`
#' call, then walks the recurrence.
#'
#' @param n Integer. Number of drops. Must be >= 1.
#' @param seed Integer. RNG seed. Default 2.
#' @param sd Numeric. Standard deviation of each drop's offset from the
#'   funnel. Default 1.
#' @param target Numeric. Initial funnel position (and target). Default 0.
#' @return Numeric vector of length `n` (resting positions).
#' @examples
#' funnel_rule_2_sim(50)
#' funnel_rule_2_sim(15, seed = 2, sd = 5, target = 30)
funnel_rule_2_sim <- function(n, seed = 2, sd = 1, target = 0) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 1, n == as.integer(n))
  set.seed(seed)
  noise <- rnorm(n, mean = 0, sd = sd)
  aim  <- numeric(n)
  rest <- numeric(n)
  aim[1] <- target
  for (i in seq_len(n)) {
    rest[i] <- aim[i] + noise[i]
    if (i < n) {
      aim[i + 1] <- aim[i] - (rest[i] - target)
    }
  }
  rest
}

#' Simulate Funnel Experiment Rule 3 (mirror across target — "explodes")
#'
#' Generates `n` resting positions under Rule 3: after each drop, place
#' the funnel on the opposite side of `target` at the same distance the
#' marble landed from target — i.e. next aim = `target − (last rest −
#' target) = 2·target − last rest`. The funnel's previous position is
#' irrelevant.
#'
#' Source: Neave Day 3, "Rules 3 and 4 of the Funnel"
#'   (content/days/day-03/12-rules-3-and-4-of-the-funnel.qmd).
#'
#' Behaviour. The amplitude of the zig-zag grows over time: any large
#' deviation gets reflected and amplified by the next drop's noise. This
#' is the classic "explodes" rule — give it long enough and the resting
#' positions wander further and further from target.
#'
#' Default seed `1` produces a run whose second half has roughly
#' 2.7× the standard deviation of its first half — visually striking on a
#' 50-drop control chart while still readable on the page.
#'
#' Loop: sequential by construction.
#'
#' @param n Integer. Number of drops. Must be >= 1.
#' @param seed Integer. RNG seed. Default 1.
#' @param sd Numeric. Standard deviation of each drop's offset from the
#'   funnel. Default 1.
#' @param target Numeric. Target position (and initial aim). Default 0.
#' @return Numeric vector of length `n` (resting positions).
#' @examples
#' funnel_rule_3_sim(50)
#' funnel_rule_3_sim(15, seed = 1, sd = 5, target = 30)
funnel_rule_3_sim <- function(n, seed = 1, sd = 1, target = 0) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 1, n == as.integer(n))
  set.seed(seed)
  noise <- rnorm(n, mean = 0, sd = sd)
  aim  <- numeric(n)
  rest <- numeric(n)
  aim[1] <- target
  for (i in seq_len(n)) {
    rest[i] <- aim[i] + noise[i]
    if (i < n) {
      aim[i + 1] <- target - (rest[i] - target)
    }
  }
  rest
}

#' Simulate Funnel Experiment Rule 4 (place the funnel where the marble landed)
#'
#' Generates `n` resting positions under Rule 4: after each drop, place
#' the funnel exactly where the marble just rested. The aim for the next
#' drop is `last rest`, so the resting-position sequence is a random walk:
#' `rest_{i+1} = rest_i + noise_{i+1}`.
#'
#' Source: Neave Day 3, "Rule 4 of the Funnel"
#'   (content/days/day-03/12-rules-3-and-4-of-the-funnel.qmd).
#'
#' Behaviour. Short-term variation (adjacent moving range) is reduced —
#' Rule 4's motivation — but long-term variance grows linearly with the
#' number of drops, so the marble "wanders" away from target without
#' bound. On a control chart this surfaces as points piercing the
#' (artificially narrow) MR-based limits within the baseline itself.
#'
#' Default seed `42` produces a roughly equal first/second-half spread
#' while still showing clear long-range drift away from target.
#'
#' Vectorised: Rule 4 admits a closed form — resting positions are
#' `target + cumsum(noise)` — so no loop is needed.
#'
#' @param n Integer. Number of drops. Must be >= 1.
#' @param seed Integer. RNG seed. Default 42.
#' @param sd Numeric. Standard deviation of each drop's offset from the
#'   funnel. Default 1.
#' @param target Numeric. Target position (and initial funnel position).
#'   Default 0.
#' @return Numeric vector of length `n` (resting positions).
#' @examples
#' funnel_rule_4_sim(50)
#' funnel_rule_4_sim(15, seed = 42, sd = 5, target = 30)
funnel_rule_4_sim <- function(n, seed = 42, sd = 1, target = 0) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 1, n == as.integer(n))
  set.seed(seed)
  # Rule 4 is a Gaussian random walk; the closed form is target + cumsum
  # of the per-drop noises (the first drop's noise is added to aim[1] =
  # target, the second to rest[1] = target + noise[1], and so on).
  noise <- rnorm(n, mean = 0, sd = sd)
  target + cumsum(noise)
}

#' Render a Funnel-rule simulation as a run/control chart
#'
#' Convenience wrapper that pipes a Funnel-rule resting-position sequence
#' (typically produced by `funnel_rule_*_sim()`) through `run_chart_plot()`
#' with optional MR-based control limits computed from the baseline
#' portion of the series.
#'
#' Why a wrapper at all (and not a direct `run_chart_plot()` call). The
#' Optional Extras Part A figures (`rule-1-short.png`, `rule-1-long.png`,
#' and their siblings) all follow the same recipe: take a simulated
#' Funnel-rule sequence, compute MR-based limits from the first `n_baseline`
#' points (or all of them in the short version), then draw the chart with
#' those limits extended across the entire series. Wrapping that recipe
#' here keeps the call site in the consumer PR to one line and makes the
#' baseline policy uniform across all four rules. Callers wanting full
#' control can still call `run_chart_plot()` directly on the sim output.
#'
#' @param values Numeric vector. Resting positions, e.g. from
#'   `funnel_rule_1_sim(50)`.
#' @param n_baseline Integer or NULL. Number of points whose MR-based
#'   limits are extended across the full chart. Defaults to NULL meaning
#'   "compute limits from all of `values`" — appropriate for the "short"
#'   chart variant (~15 drops, no extension). Set to 15 (or whatever the
#'   baseline length is) for the "long" variant (50 drops with the
#'   baseline-limit extension Neave shows on Optional Extras Part A
#'   pages 9–10).
#' @param y_limits,y_breaks,y_minor_breaks Passed through to
#'   `run_chart_plot()`. Defaults sized for the project's Funnel target
#'   range (20–40 with target 30) but accept any range.
#' @param line_width Numeric. Passed through to `run_chart_plot()`.
#'   Default 2 — between the Red Beads default (6) and the small-panel
#'   default (1.0).
#' @param show_x_labels Logical. Passed through to `run_chart_plot()`.
#' @param ... Additional arguments forwarded to `run_chart_plot()`.
#' @return A ggplot2 object.
#' @examples
#' values <- funnel_rule_1_sim(50, sd = 5, target = 30)
#' funnel_simulation_chart_plot(values, n_baseline = 15,
#'                              y_limits = c(0, 60),
#'                              y_breaks = seq(0, 60, by = 10))
funnel_simulation_chart_plot <- function(values,
                                          n_baseline = NULL,
                                          y_limits = c(15, 45),
                                          y_breaks = seq(15, 45, by = 5),
                                          y_minor_breaks = seq(15, 45, by = 1),
                                          line_width = 2,
                                          show_x_labels = TRUE,
                                          ...) {
  stopifnot(is.numeric(values), length(values) >= 2)
  if (is.null(n_baseline)) n_baseline <- length(values)
  stopifnot(n_baseline >= 2, n_baseline <= length(values))

  lims <- mr_limits(values[seq_len(n_baseline)])

  run_chart_plot(
    values         = values,
    line_width     = line_width,
    y_limits       = y_limits,
    y_breaks       = y_breaks,
    y_minor_breaks = y_minor_breaks,
    hlines         = c(lims$lcl, lims$ucl),
    hline_labels   = c("LCL", "UCL"),
    central_line   = lims$central,
    show_x_labels  = show_x_labels,
    ...
  )
}
