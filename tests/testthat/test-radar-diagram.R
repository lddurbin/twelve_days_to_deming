# --- radar_diagram_plot ---

test_that("radar_diagram_plot returns a ggplot object", {
  p <- radar_diagram_plot()
  expect_s3_class(p, "ggplot")
})

test_that("radar_diagram_plot labels all four arms", {
  p <- radar_diagram_plot()
  # The four arm titles are added as `annotate("text", ...)` layers, which
  # surface in `p$layers[[i]]$aes_params$label`. Collect them and assert
  # all four cardinal axes are present.
  text_labels <- vapply(
    p$layers,
    function(l) {
      lbl <- l$aes_params$label
      if (is.null(lbl)) NA_character_ else as.character(lbl)[[1]]
    },
    character(1)
  )
  text_labels <- text_labels[!is.na(text_labels)]
  expect_true(all(c("PSYCHOLOGY", "SYSTEM", "KNOWLEDGE", "VARIATION") %in%
                    text_labels))
})

test_that("radar_diagram_plot uses a fixed-aspect coordinate system", {
  p <- radar_diagram_plot()
  # coord_fixed() returns a CoordCartesian with `ratio = 1`. Assert both
  # the class and the ratio so we know aspect is locked.
  expect_s3_class(p$coordinates, "CoordCartesian")
  expect_equal(p$coordinates$ratio, 1)
})
