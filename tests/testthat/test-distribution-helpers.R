# --- histogram_with_pdf ---

test_that("histogram_with_pdf returns a ggplot object", {
  p <- histogram_with_pdf(rnorm(100), binwidth = 0.5)
  expect_s3_class(p, "ggplot")
})

test_that("histogram_with_pdf warns when binwidth is NULL", {
  expect_warning(
    histogram_with_pdf(rnorm(100), binwidth = NULL),
    "binwidth = NULL"
  )
})

test_that("histogram_with_pdf rejects non-numeric values", {
  expect_error(histogram_with_pdf(c("a", "b", "c"), binwidth = 1))
})

# --- pdf_family_plot ---

test_that("pdf_family_plot returns a ggplot object (overlay)", {
  pdfs <- list(
    "A" = function(x) dnorm(x),
    "B" = function(x) dnorm(x, sd = 2)
  )
  expect_s3_class(pdf_family_plot(pdfs, xlim = c(-5, 5)), "ggplot")
})

test_that("pdf_family_plot returns a ggplot object (stack)", {
  pdfs <- list(
    "A" = function(x) dnorm(x),
    "B" = function(x) dnorm(x, sd = 2)
  )
  expect_s3_class(
    pdf_family_plot(pdfs, xlim = c(-5, 5), layout = "stack"),
    "ggplot"
  )
})

test_that("pdf_family_plot rejects mismatched colour vector length", {
  pdfs <- list("A" = function(x) dnorm(x))
  expect_error(pdf_family_plot(pdfs, xlim = c(-5, 5),
                                colours = c("red", "blue")))
})

test_that("pdf_family_plot rejects unnamed pdfs list", {
  pdfs <- list(function(x) dnorm(x), function(x) dnorm(x, sd = 2))
  expect_error(pdf_family_plot(pdfs, xlim = c(-5, 5)))
})

# --- conf_interval_plot ---

test_that("conf_interval_plot returns a ggplot object", {
  expect_s3_class(conf_interval_plot(0.95), "ggplot")
})

test_that("conf_interval_plot accepts explicit z override", {
  expect_s3_class(conf_interval_plot(0.95, z = 1.96), "ggplot")
  expect_s3_class(conf_interval_plot(0.99, z = 2.58), "ggplot")
})

test_that("conf_interval_plot rejects level outside (0, 1)", {
  expect_error(conf_interval_plot(0))
  expect_error(conf_interval_plot(1))
  expect_error(conf_interval_plot(1.2))
  expect_error(conf_interval_plot(-0.1))
})

test_that("conf_interval_plot rejects non-positive z override", {
  expect_error(conf_interval_plot(0.95, z = 0))
  expect_error(conf_interval_plot(0.95, z = -1.96))
})

test_that("conf_interval_plot rejects z at or beyond upper xlim", {
  # boundary line at z must sit inside the panel
  expect_error(conf_interval_plot(0.95, z = 4, xlim = c(-4, 4)))
})

# --- xbar_false_signal_probs ---

test_that("xbar_false_signal_probs returns a vector of the requested length", {
  set.seed(359)
  out <- xbar_false_signal_probs(n = 4, m_subgroups = 12,
                                 n_replications = 200)
  expect_true(is.numeric(out))
  expect_length(out, 200)
})

test_that("xbar_false_signal_probs values are in [0, 1]", {
  set.seed(359)
  out <- xbar_false_signal_probs(n = 2, m_subgroups = 12,
                                 n_replications = 500)
  expect_true(all(out >= 0))
  expect_true(all(out <= 1))
})

test_that("xbar_false_signal_probs medians are sensible for n in {2, 4, 6}", {
  # With 12 subgroups, n = 2 has the widest spread and n = 6 has the
  # tightest. Median should sit in [0, 0.02] in all three cases (well
  # below the upper x-axis bound of the corresponding histogram panel).
  set.seed(361)
  med_n2 <- median(xbar_false_signal_probs(n = 2, m_subgroups = 12,
                                           n_replications = 2000))
  med_n4 <- median(xbar_false_signal_probs(n = 4, m_subgroups = 12,
                                           n_replications = 2000))
  med_n6 <- median(xbar_false_signal_probs(n = 6, m_subgroups = 12,
                                           n_replications = 2000))
  expect_true(med_n2 > 0 && med_n2 < 0.02)
  expect_true(med_n4 > 0 && med_n4 < 0.02)
  expect_true(med_n6 > 0 && med_n6 < 0.02)
})

test_that("xbar_false_signal_probs rejects subgroup sizes outside d2 table", {
  expect_error(
    xbar_false_signal_probs(n = 7, m_subgroups = 12, n_replications = 100),
    "No built-in d2"
  )
})

test_that("xbar_false_signal_probs honours d2_override for non-table n", {
  set.seed(362)
  expect_silent(
    xbar_false_signal_probs(n = 7, m_subgroups = 12,
                            n_replications = 50, d2_override = 2.704)
  )
})

test_that("xbar_false_signal_probs rejects non-integer or infinite parameters", {
  expect_error(xbar_false_signal_probs(n = 4.5, m_subgroups = 12, n_replications = 100))
  expect_error(xbar_false_signal_probs(n = Inf, m_subgroups = 12, n_replications = 100))
  expect_error(xbar_false_signal_probs(n = 4,   m_subgroups = 4.5, n_replications = 100))
  expect_error(xbar_false_signal_probs(n = 4,   m_subgroups = Inf, n_replications = 100))
  expect_error(xbar_false_signal_probs(n = 4,   m_subgroups = 12,  n_replications = 1.5))
  expect_error(xbar_false_signal_probs(n = 4,   m_subgroups = 12,  n_replications = Inf))
})

# --- xbar_false_signal_panel ---

test_that("xbar_false_signal_panel returns a ggplot object", {
  set.seed(363)
  probs <- xbar_false_signal_probs(n = 4, m_subgroups = 12,
                                   n_replications = 500)
  p <- xbar_false_signal_panel(probs, caption = "12 subgroups of size 4",
                               x_max = 0.020)
  expect_s3_class(p, "ggplot")
})

test_that("xbar_false_signal_panel rejects non-character caption", {
  expect_error(xbar_false_signal_panel(rep(0.001, 10), caption = 123,
                                       x_max = 0.020))
})
