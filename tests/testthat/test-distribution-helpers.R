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
