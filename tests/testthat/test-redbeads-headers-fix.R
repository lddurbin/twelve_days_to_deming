# --- fix gt's headers attribute ordering on red-beads tables (issue #586) ---
#
# Acceptance criteria under test:
#   * A malformed `headers="stub_<n>_<n> Day 1"` (gt's emitted order, plus
#     an unsanitised space in the column reference) is rewritten to
#     `headers="Day-1 stub_<n>_<n>"`.
#   * A column token with no whitespace (e.g. "Totals") is just reordered,
#     no dash inserted.
#   * Multiple malformed `headers` attributes in one file are all fixed.
#   * An already-correctly-ordered `headers` attribute (column id first) is
#     left untouched — the regex must not "fix" something already correct.
#   * Unrelated `headers`-less markup round-trips byte-for-byte.
#   * A file with no matching pattern is reported unmodified (no
#     unnecessary write).
#   * A missing file is handled without erroring.
#   * fix_redbeads_headers() filters to .html files and returns the count of
#     files actually modified.

source(here::here("R/functions/redbeads-headers-fix.R"))

#' Write `body` to a tempfile with no trailing newline, matching Quarto's
#' actual output (verified against a real rendered page).
.mk_html <- function(body) {
  tmp <- tempfile(fileext = ".html")
  con <- file(tmp, "wb")
  writeChar(body, con, eos = NULL, useBytes = TRUE)
  close(con)
  tmp
}

.read_raw <- function(path) {
  readChar(path, file.info(path)$size, useBytes = TRUE)
}

# ---------------------------------------------------------------------------
# 1. Malformed headers with a space-containing column token get reordered
#    AND sanitised (space -> dash), matching the real <th id="Day-1"> gt
#    emits for that column's label.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file reorders and sanitises a space-containing column token", {
  tmp <- .mk_html(paste0(
    '<table><thead><tr>\n',
    '<th id="stub_1_1" scope="row">Audrey</th>\n',
    '<th id="Day-1">Day 1</th>\n',
    '</tr></thead><tbody><tr>\n',
    '<td headers="stub_1_1 Day 1">16</td>\n',
    '</tr></tbody></table>'
  ))

  modified <- fix_redbeads_headers_in_file(tmp)
  expect_true(modified)

  out <- .read_raw(tmp)
  expect_match(out, 'headers="Day-1 stub_1_1"', fixed = TRUE)
  expect_no_match(out, 'headers="stub_1_1 Day 1"', fixed = TRUE)
})

# ---------------------------------------------------------------------------
# 2. A column token with no whitespace (e.g. "Totals") is just reordered.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file reorders a whitespace-free column token without altering it", {
  tmp <- .mk_html('<td headers="stub_1_1 Totals">21</td>')

  modified <- fix_redbeads_headers_in_file(tmp)
  expect_true(modified)

  out <- .read_raw(tmp)
  expect_match(out, 'headers="Totals stub_1_1"', fixed = TRUE)
})

# ---------------------------------------------------------------------------
# 3. Multiple malformed headers in one file are all fixed.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file fixes every malformed headers attribute in a file", {
  tmp <- .mk_html(paste0(
    '<td headers="stub_1_1 Day 1">16</td>\n',
    '<td headers="stub_1_1 Day 2">9</td>\n',
    '<td headers="stub_1_2 Day 1">9</td>\n'
  ))

  modified <- fix_redbeads_headers_in_file(tmp)
  expect_true(modified)

  out <- .read_raw(tmp)
  expect_match(out, 'headers="Day-1 stub_1_1"', fixed = TRUE)
  expect_match(out, 'headers="Day-2 stub_1_1"', fixed = TRUE)
  expect_match(out, 'headers="Day-1 stub_1_2"', fixed = TRUE)
})

# ---------------------------------------------------------------------------
# 4. An already-correctly-ordered headers attribute (column id first) is
#    left untouched, since the malformed pattern always has the stub id
#    first.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file leaves a correctly-ordered headers attribute alone", {
  body <- '<td headers="Day-1 stub_1_1">16</td>'
  tmp <- .mk_html(body)

  modified <- fix_redbeads_headers_in_file(tmp)
  expect_false(modified)
  expect_identical(.read_raw(tmp), body)
})

# ---------------------------------------------------------------------------
# 5. A file with no matching pattern is reported unmodified, and unrelated
#    content round-trips byte-for-byte.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file is a no-op when there is no matching headers attribute", {
  body <- '<html><head></head><body><p>Nothing to see here.</p></body></html>'
  tmp <- .mk_html(body)

  modified <- fix_redbeads_headers_in_file(tmp)
  expect_false(modified)
  expect_identical(.read_raw(tmp), body)
})

# ---------------------------------------------------------------------------
# 6. Missing file: handled without erroring.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers_in_file returns FALSE for a missing file", {
  expect_false(fix_redbeads_headers_in_file(tempfile(fileext = ".html")))
})

# ---------------------------------------------------------------------------
# 7. fix_redbeads_headers() filters to .html and counts modifications.
# ---------------------------------------------------------------------------

test_that("fix_redbeads_headers filters to .html files and counts modifications", {
  fixed <- .mk_html('<td headers="stub_1_1 Day 1">16</td>')
  already_correct <- .mk_html('<td headers="Day-1 stub_1_1">16</td>')
  non_html <- tempfile(fileext = ".xml")
  writeLines('<td headers="stub_1_1 Day 1">16</td>', non_html)
  non_html_before <- .read_raw(non_html)

  count <- fix_redbeads_headers(c(fixed, already_correct, non_html))
  expect_identical(count, 1L)
  # Filtered out by extension — never passed to fix_redbeads_headers_in_file.
  expect_identical(.read_raw(non_html), non_html_before)
})
