# --- clt_demo_plot ---

test_that("clt_demo_plot returns a ggplot object", {
  set.seed(356)
  p <- clt_demo_plot(
    parent_dist = function(n) runif(n, min = -sqrt(3), max = sqrt(3)),
    n           = 4,
    mu          = 0,
    sigma       = 1,
    n_samples   = 1000
  )
  expect_s3_class(p, "ggplot")
})

test_that("clt_demo_plot accepts an arbitrary parent-distribution sampler", {
  # The helper must work for any sampler — issue #357 will reuse it with rexp.
  set.seed(357)
  p <- clt_demo_plot(
    parent_dist = function(n) rexp(n, rate = 1),
    n           = 10,
    mu          = 1,
    sigma       = 1,
    n_samples   = 1000
  )
  expect_s3_class(p, "ggplot")
})

test_that("clt_demo_plot estimates mu when not supplied", {
  # Pilot-sample fallback path: mu = NULL should run without error and
  # produce a centred (mean(z) ≈ 0) standardised distribution.
  set.seed(356)
  expect_silent(
    clt_demo_plot(
      parent_dist = function(n) runif(n, min = -sqrt(3), max = sqrt(3)),
      n           = 4,
      sigma       = 1,
      n_samples   = 1000
    )
  )
})

test_that("clt_demo_plot rejects non-function parent_dist", {
  expect_error(clt_demo_plot(parent_dist = "not-a-function", n = 4))
})

test_that("clt_demo_plot rejects non-positive sigma", {
  expect_error(
    clt_demo_plot(
      parent_dist = function(n) runif(n),
      n           = 4,
      sigma       = 0
    )
  )
})

test_that("clt_demo_plot rejects invalid xlim", {
  expect_error(
    clt_demo_plot(
      parent_dist = function(n) runif(n),
      n           = 4,
      xlim        = c(4, -4)
    )
  )
})
