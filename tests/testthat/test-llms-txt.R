# --- generate llms.txt from _quarto-en.yml's chapter list (issue #511) ---
#
# Acceptance criteria under test:
#   * H1/blockquote come from the top-level Quarto config's book title and
#     description (folded, trimmed).
#   * Chapters not wrapped in a `part:` collapse into a single "## Pages"
#     block, even when they appear both before and after part blocks.
#   * Each `part:` becomes its own "## <part>" block, in document order.
#   * A page missing `pagetitle` falls back to `title`; a page missing
#     `description` renders as a bare link with no trailing colon.
#   * An appendices `part:` given as a .qmd path (not a title string)
#     resolves its heading via that file's own front matter and folds all
#     appendix content into one flat "## Optional" section.
#   * llms_txt_write() writes the built lines to disk.
#   * An unrecognised chapters-entry shape errors instead of silently
#     dropping content.

source(here::here("R/functions/llms-txt.R"))

.mk_qmd <- function(path, pagetitle = NULL, title = NULL, description = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  fm <- c("---")
  if (!is.null(title)) fm <- c(fm, sprintf('title: "%s"', title))
  if (!is.null(pagetitle)) fm <- c(fm, sprintf('pagetitle: "%s"', pagetitle))
  if (!is.null(description)) fm <- c(fm, sprintf('description: "%s"', description))
  fm <- c(fm, "---", "", "Body text.")
  writeLines(fm, path)
}

.setup_fixture_project <- function(envir = parent.frame()) {
  # withr's cleanup normally unwinds when *this* function returns; passing
  # the caller's frame defers it until the enclosing test_that() block
  # exits instead, which is when the fixture actually needs to still exist.
  dir <- withr::local_tempdir(.local_envir = envir)
  withr::local_dir(dir, .local_envir = envir)

  writeLines(c(
    "book:",
    '  title: "Test Course"',
    "  description: >",
    "    A test course description",
    "    spanning two lines.",
    '  site-url: "https://example.test"'
  ), "_quarto.yml")

  writeLines(c(
    "book:",
    "  chapters:",
    "    - front.qmd",
    '    - part: "Day 1: Test"',
    "      chapters:",
    "        - day1/a.qmd",
    "        - day1/b.qmd",
    "    - back.qmd",
    "  appendices:",
    "    - appendix/plain.qmd",
    "    - part: appendix/intro.qmd",
    "      chapters:",
    "        - appendix/sub.qmd"
  ), "_quarto-en.yml")

  .mk_qmd("front.qmd", pagetitle = "Front Page", description = "Front description.")
  .mk_qmd("day1/a.qmd", pagetitle = "Day 1 A", description = "A description.")
  .mk_qmd("day1/b.qmd", title = "Raw Title B")
  .mk_qmd("back.qmd", pagetitle = "Back Page")
  .mk_qmd("appendix/plain.qmd", pagetitle = "Plain Appendix", description = "Plain desc.")
  .mk_qmd("appendix/intro.qmd", pagetitle = "Intro Appendix", description = "Intro desc.")
  .mk_qmd("appendix/sub.qmd", pagetitle = "Sub Appendix", description = "Sub desc.")

  invisible(dir)
}

# ---------------------------------------------------------------------------
# 1. H1 and blockquote come from the site-level config.
# ---------------------------------------------------------------------------

test_that("llms_txt_build renders the site title and folded, trimmed description", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  expect_identical(lines[1], "# Test Course")
  expect_identical(lines[3], "> A test course description spanning two lines.")
})

# ---------------------------------------------------------------------------
# 2. Ungrouped chapters merge into a single "## Pages" block.
# ---------------------------------------------------------------------------

test_that("ungrouped chapters collapse into one Pages block regardless of position", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  headings <- grep("^## ", lines, value = TRUE)
  expect_identical(sum(headings == "## Pages"), 1L)

  pages_start <- which(lines == "## Pages")
  pages_block <- lines[pages_start:(pages_start + 4)]
  expect_true(any(grepl("Front Page", pages_block)))
  expect_true(any(grepl("Back Page", pages_block)))
})

# ---------------------------------------------------------------------------
# 3. Part blocks render in order with correct links and descriptions.
# ---------------------------------------------------------------------------

test_that("a part block renders its title as a heading and chapters as bullets", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  day1_idx <- which(lines == "## Day 1: Test")
  expect_length(day1_idx, 1)
  expect_identical(
    lines[day1_idx + 2],
    "- [Day 1 A](https://example.test/day1/a.html): A description."
  )
})

# ---------------------------------------------------------------------------
# 4. Missing pagetitle falls back to title; missing description omits ":".
# ---------------------------------------------------------------------------

test_that("a page without pagetitle falls back to title", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  expect_true("- [Raw Title B](https://example.test/day1/b.html)" %in% lines)
})

test_that("a page without a description renders as a bare link", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  expect_true("- [Back Page](https://example.test/back.html)" %in% lines)
})

# ---------------------------------------------------------------------------
# 5. Appendices: path-based part resolves its own heading via front matter,
#    and all appendix content flattens into one "## Optional" section.
# ---------------------------------------------------------------------------

test_that("appendices flatten into a single Optional section, including a path-based part's own page", {
  .setup_fixture_project()
  lines <- llms_txt_build()

  headings <- grep("^## ", lines, value = TRUE)
  expect_identical(sum(headings == "## Optional"), 1L)

  optional_start <- which(lines == "## Optional")
  optional_block <- lines[optional_start:length(lines)]
  expect_true(any(grepl("Plain Appendix", optional_block)))
  # The part's own path (appendix/intro.qmd) becomes a bullet using its own
  # front matter, not a bare "## <path>" heading.
  expect_true(any(grepl("^- \\[Intro Appendix\\]", optional_block)))
  expect_true(any(grepl("Sub Appendix", optional_block)))
  expect_false(any(grepl("^## ", optional_block[-1])))
})

# ---------------------------------------------------------------------------
# 6. llms_txt_write() writes the built content to disk.
# ---------------------------------------------------------------------------

test_that("llms_txt_write writes llms.txt to the given path", {
  .setup_fixture_project()
  out <- llms_txt_write("llms.txt")

  expect_identical(out, "llms.txt")
  expect_true(file.exists("llms.txt"))
  written <- readLines("llms.txt")
  expect_identical(written[1], "# Test Course")
})

# ---------------------------------------------------------------------------
# 7. An unrecognised chapters-entry shape errors rather than dropping
#    content silently.
# ---------------------------------------------------------------------------

test_that("an unrecognised chapters entry shape errors instead of silently dropping content", {
  bad_entries <- list("front.qmd", list(unexpected = "value"))
  expect_error(.llms_txt_flatten_paths(bad_entries), "unrecognised")
  expect_error(.llms_txt_chapter_blocks(bad_entries), "unrecognised")
})
