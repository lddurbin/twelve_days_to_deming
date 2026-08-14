# --- funnel_rule_*_sim — reproducibility under fixed seed ---

test_that("funnel_rule_1_sim is reproducible under a fixed seed", {
  a <- funnel_rule_1_sim(20, seed = 7)
  b <- funnel_rule_1_sim(20, seed = 7)
  expect_identical(a, b)
})

test_that("funnel_rule_2_sim is reproducible under a fixed seed", {
  a <- funnel_rule_2_sim(20, seed = 2)
  b <- funnel_rule_2_sim(20, seed = 2)
  expect_identical(a, b)
})

test_that("funnel_rule_3_sim is reproducible under a fixed seed", {
  a <- funnel_rule_3_sim(20, seed = 1)
  b <- funnel_rule_3_sim(20, seed = 1)
  expect_identical(a, b)
})

test_that("funnel_rule_4_sim is reproducible under a fixed seed", {
  a <- funnel_rule_4_sim(20, seed = 42)
  b <- funnel_rule_4_sim(20, seed = 42)
  expect_identical(a, b)
})

test_that("different seeds produce different sequences (smoke)", {
  expect_false(identical(funnel_rule_1_sim(10, seed = 1),
                         funnel_rule_1_sim(10, seed = 2)))
})

# --- Return type / length contract ---

test_that("funnel_rule_*_sim returns a numeric vector of length n", {
  for (fn in list(funnel_rule_1_sim, funnel_rule_2_sim,
                  funnel_rule_3_sim, funnel_rule_4_sim)) {
    v <- fn(25)
    expect_type(v, "double")
    expect_length(v, 25)
  }
})

test_that("funnel_rule_*_sim rejects n < 1", {
  for (fn in list(funnel_rule_1_sim, funnel_rule_2_sim,
                  funnel_rule_3_sim, funnel_rule_4_sim)) {
    expect_error(fn(0))
  }
})

# --- Rule-1 mean ≈ target for long n ---

test_that("Rule 1's sample mean is close to target for large n", {
  vals <- funnel_rule_1_sim(10000, seed = 7, sd = 1, target = 0)
  # With n = 10000, SE of mean is sd / sqrt(n) ≈ 0.01; |mean| should be
  # well within 0.1 for any reasonable seed.
  expect_lt(abs(mean(vals)), 0.1)
})

# --- Rule-4 variance grows with n (random-walk property) ---

test_that("Rule 4's variance grows with n (random-walk signature)", {
  # The variance of a Gaussian random walk after k steps is k * sd^2, so
  # var(last quarter) should comfortably exceed var(first quarter) when
  # averaged across many independent seeds.
  ratios <- vapply(1:30, function(s) {
    v <- funnel_rule_4_sim(400, seed = s, sd = 1, target = 0)
    var(v[301:400]) / var(v[1:100])
  }, numeric(1))
  expect_gt(mean(ratios), 1.5)
})

# --- Rule 3 expectation: amplitude grows over time ---

test_that("Rule 3's amplitude grows over the run (averaged across seeds)", {
  growths <- vapply(1:30, function(s) {
    v <- funnel_rule_3_sim(100, seed = s, sd = 1, target = 0)
    sd(v[51:100]) / sd(v[1:50])
  }, numeric(1))
  expect_gt(mean(growths), 1.3)
})

# --- Rule 2 expectation: negative lag-1 autocorrelation (zig-zag) ---

test_that("Rule 2 induces negative lag-1 autocorrelation on average", {
  acs <- vapply(1:30, function(s) {
    v <- funnel_rule_2_sim(200, seed = s, sd = 1, target = 0)
    cor(v[-length(v)], v[-1])
  }, numeric(1))
  expect_lt(mean(acs), -0.2)
})

# --- Chart-rendering smoke test ---

test_that("funnel_simulation_chart_plot returns a ggplot object", {
  v <- funnel_rule_1_sim(50, seed = 7, sd = 5, target = 30)
  p <- funnel_simulation_chart_plot(v, n_baseline = 15,
                                    y_limits = c(0, 60),
                                    y_breaks = seq(0, 60, by = 10),
                                    y_minor_breaks = seq(0, 60, by = 5))
  expect_s3_class(p, "ggplot")
})

test_that("funnel_simulation_chart_plot adds CL + LCL + UCL hlines", {
  v <- funnel_rule_1_sim(50, seed = 7, sd = 5, target = 30)
  p <- funnel_simulation_chart_plot(v, n_baseline = 15,
                                    y_limits = c(0, 60),
                                    y_breaks = seq(0, 60, by = 10))
  hline_layers <- Filter(function(l) inherits(l$geom, "GeomHline"), p$layers)
  # central line + LCL + UCL = 3 hlines.
  expect_length(hline_layers, 3)
})

test_that("funnel_simulation_chart_plot works with n_baseline = NULL", {
  v <- funnel_rule_1_sim(15, seed = 7, sd = 5, target = 30)
  p <- funnel_simulation_chart_plot(v,
                                    y_limits = c(0, 60),
                                    y_breaks = seq(0, 60, by = 10))
  expect_s3_class(p, "ggplot")
  hline_layers <- Filter(function(l) inherits(l$geom, "GeomHline"), p$layers)
  expect_length(hline_layers, 3)
})

test_that("Rule sim outputs can be passed directly to run_chart_plot", {
  v <- funnel_rule_2_sim(20, seed = 2, sd = 5, target = 30)
  p <- run_chart_plot(v, y_limits = c(0, 60),
                     y_breaks = seq(0, 60, by = 10),
                     y_minor_breaks = seq(0, 60, by = 5))
  expect_s3_class(p, "ggplot")
})

# --- funnel_track_plot() move-annotation helpers (test-local) ---

# The funnel/ghost markers are GeomPoint layers distinguished by shape
# (25 = solid funnel marker, 24 = outline ghost echo). The move arrow is
# the one GeomSegment layer whose y == yend (a horizontal segment) —
# the funnel-stick and ghost-stick segments are both vertical (y != yend).
funnel_pos_from_plot <- function(gg) {
  pt <- Filter(function(l) inherits(l$geom, "GeomPoint") &&
                 identical(l$aes_params$shape, 25), gg$layers)
  if (length(pt) == 0) return(NULL)
  pt[[1]]$data$x
}

move_arrow_from_plot <- function(gg) {
  seg <- Filter(function(l) inherits(l$geom, "GeomSegment") &&
                  isTRUE(all.equal(l$data$y, l$data$yend)), gg$layers)
  if (length(seg) == 0) return(NULL)
  seg[[1]]$data
}

# --- funnel_track_plot() no-op regression guard ---

test_that("funnel_track_plot() with no annotation args is unchanged (bare)", {
  p <- funnel_track_plot()
  # 4 layers: track tiles, position-number text, target bullseye point,
  # target number text. A change here means a base-track layer was
  # added/removed/reordered — cross-check against an SVG diff (see PR
  # #649 description) before trusting this count alone, since it can
  # also shift on an unrelated ggplot2 upgrade.
  expect_length(p$layers, 4)
  expect_equal(p$scales$get_scales("y")$limits, c(-0.7, 1.6))
})

test_that("funnel_track_plot() with no annotation args is unchanged (funnel + marble)", {
  p <- funnel_track_plot(funnel_pos = 27, marble_pos = 28)
  # 7 = the 4 base layers above + funnel stick, funnel triangle, marble
  # circle. See the comment on the "(bare)" case above for the caveat
  # on trusting this count in isolation.
  expect_length(p$layers, 7)
  expect_equal(p$scales$get_scales("y")$limits, c(-0.7, 1.6))
  expect_null(move_arrow_from_plot(p))
})

test_that("funnel_track_plot() rejects out-of-range move/ghost positions", {
  expect_error(funnel_track_plot(move_from = 10, move_to = 29))
  expect_error(funnel_track_plot(move_from = 27, move_to = 50))
  expect_error(funnel_track_plot(ghost_funnel = 100))
})

test_that("funnel_track_plot() with a move annotation extends the lower y limit", {
  p <- funnel_track_plot(funnel_pos = 29, marble_pos = 28,
                         move_from = 27, move_to = 29,
                         move_label = "test origin", ghost_funnel = 27)
  expect_lt(p$scales$get_scales("y")$limits[1], -0.7)
  arrow_data <- move_arrow_from_plot(p)
  expect_equal(arrow_data$x, 27)
  expect_equal(arrow_data$xend, 29)
})

# --- funnel_rule_comparison_plot() ---

test_that("funnel_rule_comparison_plot returns a composed patchwork object", {
  p <- funnel_rule_comparison_plot()
  expect_s3_class(p, "patchwork")
})

test_that("funnel_rule_comparison_plot names the computed rule result on out-of-range error", {
  # funnel_pos = 40, marble_pos = 39, target = 21 sends Rule 3's result
  # (target - (marble_pos - target) = 3) below x_min = 20. The error
  # should name "Rule 3's computed funnel position", not the generic
  # "funnel_pos" complaint funnel_track_plot()'s own stopifnot would
  # raise if this weren't pre-validated.
  expect_error(
    funnel_rule_comparison_plot(funnel_pos = 40, marble_pos = 39, target = 21),
    "Rule 3's computed funnel position"
  )
})

test_that("funnel_rule_comparison_plot's three rows carry funnel positions 27, 29, 32 with the marble at 28 throughout", {
  p <- funnel_rule_comparison_plot()
  rows <- c(p$patches$plots, list(p))
  expect_length(rows, 3)
  expect_equal(vapply(rows, funnel_pos_from_plot, numeric(1)), c(27, 29, 32))
})

test_that("funnel_rule_comparison_plot's Rule 2 and Rule 3 arrows share span but differ in origin", {
  p <- funnel_rule_comparison_plot()
  rows <- c(p$patches$plots, list(p))

  rule2_arrow <- move_arrow_from_plot(rows[[2]])
  rule3_arrow <- move_arrow_from_plot(rows[[3]])

  expect_equal(abs(rule2_arrow$xend - rule2_arrow$x), 2)
  expect_equal(abs(rule3_arrow$xend - rule3_arrow$x), 2)
  expect_equal(rule2_arrow$x, 27)
  expect_equal(rule3_arrow$x, 30)
  expect_false(identical(rule2_arrow$x, rule3_arrow$x))
})
