# --- run_chart_theme ---

test_that("run_chart_theme returns a ggplot theme", {
  th <- run_chart_theme()
  expect_s3_class(th, "theme")
})

test_that("run_chart_theme accepts custom right margin", {
  th <- run_chart_theme(right_margin = 30)
  expect_s3_class(th, "theme")
})

# --- run_chart_plot ---

test_that("run_chart_plot returns a ggplot object", {
  p <- run_chart_plot(c(13, 19, 18, 15, 12))
  expect_s3_class(p, "ggplot")
})

test_that("run_chart_plot rejects non-numeric values", {
  expect_error(run_chart_plot(c("a", "b", "c")))
})

test_that("run_chart_plot rejects fewer than 2 values", {
  expect_error(run_chart_plot(c(10)))
})

test_that("run_chart_plot adds hlines when provided", {
  p <- run_chart_plot(c(13, 19, 18), hlines = c(5, 20), hline_labels = c("LCL", "UCL"))
  hline_layers <- Filter(function(l) inherits(l$geom, "GeomHline"), p$layers)
  expect_length(hline_layers, 2)
})

# --- red_beads_control_chart ---

test_that("red_beads_control_chart returns a ggplot", {
  p <- red_beads_control_chart(c(9, 11, 7, 13, 8, 10))
  expect_s3_class(p, "ggplot")
})

test_that("red_beads_control_chart includes two control limit lines", {
  p <- red_beads_control_chart(c(9, 11, 7, 13, 8, 10))
  hline_layers <- Filter(function(l) inherits(l$geom, "GeomHline"), p$layers)
  expect_length(hline_layers, 2)
})

test_that("red_beads_control_chart accepts custom limits", {
  p <- red_beads_control_chart(c(9, 11, 7, 13, 8, 10), LCL = 2.0, UCL = 16.0)
  expect_s3_class(p, "ggplot")
})
