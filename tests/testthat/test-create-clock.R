library(testthat)
library(ggplot2)

source(here::here("R/functions/main-functions.R"))

test_that("create_clock returns a ggplot object", {
  p <- create_clock(3, 0)
  expect_s3_class(p, "gg")
  expect_s3_class(p, "ggplot")
})

test_that("create_clock has expected layers", {
  p <- create_clock(9, 30)
  # 2 geom_point (face + center) + 1 tick segments + 1 hand segments = 4 layers

  expect_equal(length(p$layers), 4)
})

test_that("create_clock rejects non-numeric input", {
  expect_error(create_clock("three", 0))
  expect_error(create_clock(3, "zero"))
})

test_that("create_clock handles 12-hour wraparound", {
  # hour=0 and hour=12 should produce the same hand position
  p0 <- create_clock(0, 0)
  p12 <- create_clock(12, 0)
  hand_data_0 <- layer_data(p0, 4)
  hand_data_12 <- layer_data(p12, 4)
  expect_equal(hand_data_0$xend, hand_data_12$xend, tolerance = 1e-10)
  expect_equal(hand_data_0$yend, hand_data_12$yend, tolerance = 1e-10)
})

test_that("create_clock minute hand points up at 0 minutes", {
  p <- create_clock(3, 0)
  hand_data <- layer_data(p, 4)
  # minute hand is the second row; at 0 minutes it should point straight up (x≈0, y>0)
  expect_equal(hand_data$xend[2], 0, tolerance = 1e-10)
  expect_gt(hand_data$yend[2], 0)
})
