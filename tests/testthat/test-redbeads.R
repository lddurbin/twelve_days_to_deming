# --- make_redbeads_df ---

test_that("make_redbeads_df returns 7 rows (6 workers + Daily Totals)", {
  df <- make_redbeads_df(
    day1 = c(9, 11, 7, 13, 8, 10),
    day2 = c(8, 12, 6, 14, 9, 11)
  )
  expect_equal(nrow(df), 7)
})

test_that("make_redbeads_df has correct columns", {
  df <- make_redbeads_df()
  expect_equal(names(df), c("Name", "Day 1", "Day 2", "Day 3", "Day 4", "Totals"))
})

test_that("make_redbeads_df computes row totals when all days provided", {
  df <- make_redbeads_df(
    day1 = c(1, 2, 3, 4, 5, 6),
    day2 = c(1, 2, 3, 4, 5, 6),
    day3 = c(1, 2, 3, 4, 5, 6),
    day4 = c(1, 2, 3, 4, 5, 6)
  )
  # First worker: 1+1+1+1 = 4
  expect_equal(df$Totals[1], 4)
  # Last worker: 6+6+6+6 = 24
  expect_equal(df$Totals[6], 24)
})

test_that("make_redbeads_df row totals are NA when some days missing", {
  df <- make_redbeads_df(
    day1 = c(9, 11, 7, 13, 8, 10)
  )
  # Only day1 provided, days 2-4 are NA, so Totals should be NA
  expect_true(all(is.na(df$Totals[1:6])))
})

test_that("make_redbeads_df computes Daily Totals row correctly", {
  df <- make_redbeads_df(
    day1 = c(1, 2, 3, 4, 5, 6),
    day2 = c(1, 2, 3, 4, 5, 6),
    day3 = c(1, 2, 3, 4, 5, 6),
    day4 = c(1, 2, 3, 4, 5, 6)
  )
  totals_row <- df[7, ]
  expect_equal(totals_row$Name, "Daily Totals")
  expect_equal(unname(totals_row$`Day 1`), 21)  # 1+2+3+4+5+6
  expect_equal(unname(totals_row$Totals), 84)   # 21*4
})

test_that("make_redbeads_df Daily Totals are NA when column incomplete", {
  df <- make_redbeads_df()  # all days are NA
  totals_row <- df[7, ]
  expect_true(is.na(totals_row$`Day 1`))
  expect_true(is.na(totals_row$Totals))
})

test_that("make_redbeads_df accepts custom worker names", {
  df <- make_redbeads_df(workers = c("A", "B", "C", "D", "E", "F"))
  expect_equal(df$Name[1:6], c("A", "B", "C", "D", "E", "F"))
})

# --- render_redbeads_table ---

test_that("render_redbeads_table returns a gt object", {
  df <- make_redbeads_df(
    day1 = c(9, 11, 7, 13, 8, 10),
    day2 = c(8, 12, 6, 14, 9, 11),
    day3 = c(10, 10, 8, 12, 7, 9),
    day4 = c(7, 13, 9, 11, 10, 8)
  )
  # fmt_missing() is deprecated in gt >= 0.6.0; source code still uses it
  tbl <- suppressWarnings(render_redbeads_table(df))
  expect_s3_class(tbl, "gt_tbl")
})

test_that("render_redbeads_table produces HTML output", {
  df <- make_redbeads_df(
    day1 = c(9, 11, 7, 13, 8, 10),
    day2 = c(8, 12, 6, 14, 9, 11),
    day3 = c(10, 10, 8, 12, 7, 9),
    day4 = c(7, 13, 9, 11, 10, 8)
  )
  # fmt_missing() is deprecated in gt >= 0.6.0; source code still uses it
  tbl <- suppressWarnings(render_redbeads_table(df))
  html <- as.character(as_raw_html(tbl))
  expect_true(grepl("<table", html))
  expect_true(grepl("Daily Totals", html))
})
