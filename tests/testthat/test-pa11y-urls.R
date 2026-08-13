# --- generate .pa11yci.json's `urls` from _quarto-en.yml's chapter list,
#     plus an essays orphan check (issue #630) ---
#
# Acceptance criteria under test:
#   * Chapters and appendices flatten into pa11y URLs in document order.
#   * index.qmd maps to the site root ("/"), not "/index.html".
#   * A hand-maintained extra URL is inserted immediately after the chapter
#     it varies from.
#   * pa11y_urls_json() keeps the existing file's `defaults` block verbatim
#     and only replaces `urls`.
#   * pa11y_urls_up_to_date() detects both a stale `urls` list and a
#     manually hand-edited `defaults` block as drift.
#   * pa11y_urls_write() writes a file pa11y_urls_up_to_date() then accepts,
#     and running it twice is a no-op the second time.
#   * pa11y_urls_orphaned_essays() is empty when there's no essays
#     directory, empty when every essay is listed as a chapter, and lists
#     exactly the essays that aren't — never touching content-fr/.

source(here::here("R/functions/pa11y-urls.R"))

.mk_qmd <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", 'title: "Test"', "---", "", "Body."), path)
}

.setup_fixture_project <- function(envir = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = envir)
  withr::local_dir(dir, .local_envir = envir)

  writeLines(c(
    "book:",
    "  chapters:",
    "    - index.qmd",
    '    - part: "Day 1: Test"',
    "      chapters:",
    "        - day1/a.qmd",
    "    - share-your-experience.qmd",
    "  appendices:",
    "    - appendix/plain.qmd"
  ), "_quarto-en.yml")

  writeLines(c(
    "{",
    '  "defaults": {',
    '    "standard": "WCAG2AA",',
    '    "ignore": ["SOME.RULE"]',
    "  },",
    '  "urls": []',
    "}",
    ""
  ), ".pa11yci.json")

  invisible(dir)
}

# ---------------------------------------------------------------------------
# 1. Chapters and appendices flatten into pa11y URLs, in document order.
# ---------------------------------------------------------------------------

test_that("pa11y_urls_build flattens chapters then appendices in document order", {
  .setup_fixture_project()
  urls <- pa11y_urls_build()

  expect_identical(urls[1], "http://localhost:8765/")
  expect_identical(urls[2], "http://localhost:8765/day1/a.html")
  expect_identical(tail(urls, 1), "http://localhost:8765/appendix/plain.html")
})

# ---------------------------------------------------------------------------
# 2. index.qmd maps to the site root, not index.html.
# ---------------------------------------------------------------------------

test_that("index.qmd maps to the site root rather than index.html", {
  .setup_fixture_project()
  urls <- pa11y_urls_build()

  expect_true("http://localhost:8765/" %in% urls)
  expect_false("http://localhost:8765/index.html" %in% urls)
})

# ---------------------------------------------------------------------------
# 3. A hand-maintained extra URL is inserted right after its base chapter.
# ---------------------------------------------------------------------------

test_that("a hand-maintained extra is inserted immediately after its chapter's URL", {
  .setup_fixture_project()
  urls <- pa11y_urls_build()

  base_idx <- which(urls == "http://localhost:8765/share-your-experience.html")
  expect_length(base_idx, 1)
  expect_identical(
    urls[base_idx + 1],
    "http://localhost:8765/share-your-experience.html?submitted=1"
  )
})

# ---------------------------------------------------------------------------
# 4. defaults is preserved verbatim; only urls is regenerated.
# ---------------------------------------------------------------------------

test_that("pa11y_urls_json keeps defaults verbatim and regenerates only urls", {
  .setup_fixture_project()
  built <- jsonlite::fromJSON(pa11y_urls_json(), simplifyVector = FALSE)

  expect_identical(built$defaults$standard, "WCAG2AA")
  expect_identical(built$defaults$ignore, list("SOME.RULE"))
  expect_true("http://localhost:8765/day1/a.html" %in% unlist(built$urls))
})

# ---------------------------------------------------------------------------
# 5. Drift detection: stale urls, and a hand-edited defaults block, both
#    count as out of date.
# ---------------------------------------------------------------------------

test_that("pa11y_urls_up_to_date is FALSE when urls is stale", {
  .setup_fixture_project()
  expect_false(pa11y_urls_up_to_date())
})

test_that("pa11y_urls_up_to_date is TRUE immediately after writing", {
  .setup_fixture_project()
  pa11y_urls_write()
  expect_true(pa11y_urls_up_to_date())
})

test_that("pa11y_urls_up_to_date is FALSE again once the chapter list changes underneath a written file", {
  .setup_fixture_project()
  pa11y_urls_write()
  expect_true(pa11y_urls_up_to_date())

  writeLines(c(
    "book:",
    "  chapters:",
    "    - index.qmd",
    "    - new-page.qmd",
    "  appendices: []"
  ), "_quarto-en.yml")

  expect_false(pa11y_urls_up_to_date())
})

# ---------------------------------------------------------------------------
# 6. pa11y_urls_write() is idempotent.
# ---------------------------------------------------------------------------

test_that("pa11y_urls_write is a no-op the second time it runs", {
  .setup_fixture_project()
  pa11y_urls_write()
  first <- .pa11y_urls_read_raw(".pa11yci.json")

  pa11y_urls_write()
  second <- .pa11y_urls_read_raw(".pa11yci.json")

  expect_identical(first, second)
})

# ---------------------------------------------------------------------------
# 7. Essays orphan check: no directory, no orphans, some orphans.
# ---------------------------------------------------------------------------

test_that("pa11y_urls_orphaned_essays returns character(0) when the essays directory doesn't exist", {
  .setup_fixture_project()
  expect_identical(pa11y_urls_orphaned_essays(), character(0))
})

test_that("pa11y_urls_orphaned_essays is empty when every essay is listed as a chapter", {
  .setup_fixture_project()
  .mk_qmd("essays/listed.qmd")
  writeLines(c(
    "book:",
    "  chapters:",
    "    - index.qmd",
    "    - essays/listed.qmd",
    "  appendices: []"
  ), "_quarto-en.yml")

  expect_identical(pa11y_urls_orphaned_essays(), character(0))
})

test_that("pa11y_urls_orphaned_essays lists an essay missing from chapters, without erroring on unrelated dirs", {
  .setup_fixture_project()
  .mk_qmd("essays/listed.qmd")
  .mk_qmd("essays/forgotten.qmd")
  .mk_qmd("content-fr/some-page.qmd")
  writeLines(c(
    "book:",
    "  chapters:",
    "    - index.qmd",
    "    - essays/listed.qmd",
    "  appendices: []"
  ), "_quarto-en.yml")

  orphans <- pa11y_urls_orphaned_essays()
  expect_identical(orphans, "essays/forgotten.qmd")
})
