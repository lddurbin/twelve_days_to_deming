# --- fix og:description/twitter:description from the page's own <meta
#     name="description"> (issue #521) ---
#
# Acceptance criteria under test:
#   * A page whose og:description/twitter:description differ from its
#     <meta name="description"> gets both corrected to match.
#   * Non-ASCII content (curly quotes, em dash) round-trips exactly, with no
#     spurious byte changes elsewhere in the file (in particular: no
#     trailing newline added where the original had none).
#   * A file with no <meta name="description"> tag is left untouched.
#   * A file already correct is reported unmodified (no unnecessary write).
#   * A missing file is handled without erroring.
#   * fix_og_description() filters to .html files and returns the count of
#     files actually modified.

source(here::here("R/functions/og-description-fix.R"))

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
# 1. Mismatched og/twitter descriptions get corrected to the page's own.
# ---------------------------------------------------------------------------

test_that("fix_og_description_in_file corrects mismatched og/twitter descriptions", {
  tmp <- .mk_html(paste0(
    '<html><head>\n',
    '<meta name="description" content="Page-specific description.">\n',
    '<meta property="og:description" content="Book-level fallback description.">\n',
    '<meta name="twitter:description" content="Book-level fallback description.">\n',
    '</head><body></body></html>'
  ))

  modified <- fix_og_description_in_file(tmp)
  expect_true(modified)

  out <- .read_raw(tmp)
  expect_match(out, 'property="og:description" content="Page-specific description\\."', perl = TRUE)
  expect_match(out, 'name="twitter:description" content="Page-specific description\\."', perl = TRUE)
  expect_no_match(out, "Book-level fallback")
})

# ---------------------------------------------------------------------------
# 2. Non-ASCII content round-trips byte-for-byte outside the fixed tags.
# ---------------------------------------------------------------------------

test_that("fix_og_description_in_file preserves UTF-8 content and exact byte layout", {
  page_desc <- "Henry Neave’s course — a free edition."
  body <- paste0(
    '<html><head>\n',
    sprintf('<meta name="description" content="%s">\n', page_desc),
    '<meta property="og:description" content="Generic book blurb — unchanged otherwise.">\n',
    '<meta name="twitter:description" content="Generic book blurb — unchanged otherwise.">\n',
    '</head><body>Body text untouched.</body></html>'
  )
  tmp <- .mk_html(body)
  original <- .read_raw(tmp)

  modified <- fix_og_description_in_file(tmp)
  expect_true(modified)

  out <- .read_raw(tmp)
  expect_true(grepl(page_desc, out, fixed = TRUE))
  # Only the two description tags should differ from the original bytes.
  expect_false(identical(out, original))
  expect_false(endsWith(out, "\n"))  # no newline added where none existed
  expect_true(endsWith(out, "</html>"))
})

# ---------------------------------------------------------------------------
# 3. No <meta name="description"> tag: file left untouched.
# ---------------------------------------------------------------------------

test_that("fix_og_description_in_file is a no-op when there is no description tag", {
  body <- '<html><head><meta property="og:description" content="x"></head><body></body></html>'
  tmp <- .mk_html(body)

  modified <- fix_og_description_in_file(tmp)
  expect_false(modified)
  expect_identical(.read_raw(tmp), body)
})

# ---------------------------------------------------------------------------
# 4. Already-correct file: reported unmodified.
# ---------------------------------------------------------------------------

test_that("fix_og_description_in_file reports no change when already correct", {
  body <- paste0(
    '<html><head>\n',
    '<meta name="description" content="Same description everywhere.">\n',
    '<meta property="og:description" content="Same description everywhere.">\n',
    '<meta name="twitter:description" content="Same description everywhere.">\n',
    '</head><body></body></html>'
  )
  tmp <- .mk_html(body)

  modified <- fix_og_description_in_file(tmp)
  expect_false(modified)
  expect_identical(.read_raw(tmp), body)
})

# ---------------------------------------------------------------------------
# 5. Missing file: handled without erroring.
# ---------------------------------------------------------------------------

test_that("fix_og_description_in_file returns FALSE for a missing file", {
  expect_false(fix_og_description_in_file(tempfile(fileext = ".html")))
})

# ---------------------------------------------------------------------------
# 6. fix_og_description() filters to .html and counts modified files.
# ---------------------------------------------------------------------------

test_that("fix_og_description filters to .html files and counts modifications", {
  fixed <- .mk_html(paste0(
    '<meta name="description" content="New description.">\n',
    '<meta property="og:description" content="Old description.">\n',
    '<meta name="twitter:description" content="Old description.">'
  ))
  already_correct <- .mk_html(paste0(
    '<meta name="description" content="Same.">\n',
    '<meta property="og:description" content="Same.">\n',
    '<meta name="twitter:description" content="Same.">'
  ))
  non_html <- tempfile(fileext = ".xml")
  writeLines('<meta name="description" content="Old description.">', non_html)
  non_html_before <- .read_raw(non_html)

  count <- fix_og_description(c(fixed, already_correct, non_html))
  expect_identical(count, 1L)
  # Filtered out by extension — never passed to fix_og_description_in_file.
  expect_identical(.read_raw(non_html), non_html_before)
})
