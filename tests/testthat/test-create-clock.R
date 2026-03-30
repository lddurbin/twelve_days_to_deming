test_that("create_clock returns a ggplot object", {
  p <- create_clock(3, 0)
  expect_s3_class(p, "gg")
  expect_s3_class(p, "ggplot")
})

test_that("create_clock includes point and segment layers", {
  p <- create_clock(9, 30)
  geom_types <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  expect_true("GeomPoint" %in% geom_types)
  expect_true("GeomSegment" %in% geom_types)
})

test_that("create_clock rejects non-numeric input", {
  expect_error(create_clock("three", 0))
  expect_error(create_clock(3, "zero"))
})

test_that("create_clock handles 12-hour wraparound", {
  # hour=0 and hour=12 should produce the same hand position
  p0 <- create_clock(0, 0)
  p12 <- create_clock(12, 0)
  # Find the segment layer with hand data (has "hand" column)
  hand_layer_idx <- which(vapply(p0$layers, function(l) inherits(l$geom, "GeomSegment"), logical(1)))
  hand_idx <- hand_layer_idx[length(hand_layer_idx)]  # last segment layer = hands
  hand_data_0 <- layer_data(p0, hand_idx)
  hand_data_12 <- layer_data(p12, hand_idx)
  expect_equal(hand_data_0$xend, hand_data_12$xend, tolerance = 1e-10)
  expect_equal(hand_data_0$yend, hand_data_12$yend, tolerance = 1e-10)
})

test_that("create_clock minute hand points up at 0 minutes", {
  p <- create_clock(3, 0)
  hand_layer_idx <- which(vapply(p$layers, function(l) inherits(l$geom, "GeomSegment"), logical(1)))
  hand_idx <- hand_layer_idx[length(hand_layer_idx)]
  hand_data <- layer_data(p, hand_idx)
  # minute hand is the second row; at 0 minutes it should point straight up (x≈0, y>0)
  expect_equal(hand_data$xend[2], 0, tolerance = 1e-10)
  expect_gt(hand_data$yend[2], 0)
})
