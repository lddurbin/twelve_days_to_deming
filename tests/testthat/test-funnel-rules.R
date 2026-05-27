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

test_that("Rule sim outputs can be passed directly to run_chart_plot", {
  v <- funnel_rule_2_sim(20, seed = 2, sd = 5, target = 30)
  p <- run_chart_plot(v, y_limits = c(0, 60),
                     y_breaks = seq(0, 60, by = 10),
                     y_minor_breaks = seq(0, 60, by = 5))
  expect_s3_class(p, "ggplot")
})
