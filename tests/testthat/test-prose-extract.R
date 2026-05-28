# --- prose extract / reinject / identity round-trip (issue #323) ---
#
# The hard correctness gate: extracting and reinjecting each segment's ORIGINAL
# text must reproduce every `.qmd` in the corpus byte-for-byte. Plus unit checks
# that protected constructs are never exposed as translatable, and that the
# inline mask/unmask is lossless.

source(here::here("R/translation/prose-extract.R"))

repo_root <- here::here()

# ---------------------------------------------------------------------------
# 1. Identity round-trip over the WHOLE corpus — byte-identical for every file.
# ---------------------------------------------------------------------------

test_that("identity round-trip is byte-identical for every .qmd in the corpus", {
  files <- qmd_corpus(repo_root)
  expect_gt(length(files), 100)  # sanity: corpus is ~122 files

  failures <- character(0)
  for (f in files) {
    rel <- sub(paste0("^", normalizePath(repo_root), "/?"), "", normalizePath(f))
    r <- roundtrip_file(f, rel_path = rel)
    if (!isTRUE(r$ok)) {
      failures <- c(failures, sprintf("%s (first diff byte %s)", rel, r$first_diff_byte))
    }
  }
  expect_identical(failures, character(0),
                   info = paste("non-identical files:", paste(failures, collapse = "; ")))
})

# ---------------------------------------------------------------------------
# 2. Protected constructs are never emitted as translatable prose.
# ---------------------------------------------------------------------------

mk <- function(x, ...) .mask_inline(x, ...)

test_that("inline code is masked out of the translatable surface", {
  r <- mk("Run `quarto render` to build the book.")
  expect_false(grepl("quarto render", r$masked))
  expect_true(any(vapply(r$placeholders, function(p) p$kind == "inline_code", logical(1))))
})

test_that("cross-references and citations are masked", {
  r1 <- mk("See @sec-page2 and @fig-clock for details.")
  kinds1 <- vapply(r1$placeholders, function(p) p$kind, character(1))
  expect_true(all(c("xref") %in% kinds1))
  expect_false(grepl("@sec-page2", r1$masked))
  expect_false(grepl("@fig-clock", r1$masked))

  r2 <- mk("This was shown earlier [@deming1986].")
  expect_true(any(vapply(r2$placeholders, function(p) p$kind == "citation", logical(1))))
  expect_false(grepl("@deming1986", r2$masked))
})

test_that("maths (inline and display) are masked", {
  r1 <- mk("The mean is $\\bar{x} = 5$ here.")
  expect_true(any(vapply(r1$placeholders, function(p) p$kind == "math_inline", logical(1))))
  expect_false(grepl("bar\\{x\\}", r1$masked))

  r2 <- mk("Formula: $$E = mc^2$$ done.")
  expect_true(any(vapply(r2$placeholders, function(p) p$kind == "math_display", logical(1))))
})

test_that("shortcodes are masked", {
  r <- mk("Embedded {{< video https://x >}} here.")
  expect_true(any(vapply(r$placeholders, function(p) p$kind == "shortcode", logical(1))))
  expect_false(grepl("video", r$masked))
})

test_that("the repo-specific #sec-pageN anchors and ../day-NN links are masked", {
  r1 <- mk("Continue to []{#sec-page7} the next section.")
  kinds1 <- vapply(r1$placeholders, function(p) p$kind, character(1))
  expect_true(any(kinds1 %in% c("inline_attr", "sec_anchor")))
  expect_false(grepl("sec-page7", r1$masked))

  r2 <- mk("See [Day 4 page 20](../day-04/04-points-1-to-6.qmd#sec-page20) now.")
  expect_true(any(vapply(r2$placeholders, function(p) p$kind == "rellink_day", logical(1))))
  expect_false(grepl("sec-page20", r2$masked))
  expect_false(grepl("day-04", r2$masked))

  r3 <- mk("See [Day 2 page 16](../days/day-02/04-our-first-control-chart.qmd#sec-page16).")
  expect_true(any(vapply(r3$placeholders, function(p) p$kind == "rellink_day", logical(1))))
})

test_that("<span lang> wrappers and <dfn id> anchors are masked whole", {
  r1 <- mk("Deming valued <span lang=\"ja\">kaizen</span> deeply.")
  expect_true(any(vapply(r1$placeholders, function(p) p$kind == "span_lang", logical(1))))
  expect_false(grepl("<span", r1$masked))

  # unquoted attribute value form used in the corpus
  r2 <- mk("He said <span class=deming_quote>nope</span>.")  # NOT lang -> not masked as span_lang
  expect_false(any(vapply(r2$placeholders, function(p) p$kind == "span_lang", logical(1))))

  r3 <- mk("the <dfn id=\"pdsa-cycle\">PDSA cycle</dfn> matters")
  expect_true(any(vapply(r3$placeholders, function(p) p$kind == "dfn", logical(1))))
  expect_false(grepl("<dfn", r3$masked))
})

test_that("YAML keys are never translatable; only the value is exposed", {
  r <- mk('title: "DAY 1: THE STORY"', yaml_value = TRUE)
  # masked surface is the bare value, no key, no quotes
  expect_false(grepl("title:", r$masked))
  expect_false(grepl('"', r$masked))
  expect_true(grepl("DAY 1: THE STORY", r$masked))
  kinds <- vapply(r$placeholders, function(p) p$kind, character(1))
  expect_true(all(c("yaml_prefix", "yaml_suffix") %in% kinds))
})

# ---------------------------------------------------------------------------
# 3. mask / unmask is lossless (translation reinjection relies on it).
# ---------------------------------------------------------------------------

test_that("unmasking the unchanged masked string reproduces the original text", {
  samples <- c(
    "Run `code` and see @sec-page2 with $x=1$ and [@cite].",
    "Deming valued <span lang=\"ja\">kaizen</span> and the <dfn id=\"x\">term</dfn>.",
    "Link [Day 4 page 20](../day-04/04-points-1-to-6.qmd#sec-page20) inline.",
    "Plain prose with em-dash — and a curly quote “quote”."
  )
  for (s in samples) {
    r <- mk(s)
    expect_identical(.unmask_inline(r$masked, r$placeholders), s)
  }
})

# ---------------------------------------------------------------------------
# 4. Code-chunk bodies are never extracted as prose.
# ---------------------------------------------------------------------------

test_that("fenced code chunk bodies are not emitted as prose segments", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---",
    'title: "Test"',
    "---",
    "",
    "Some prose before.",
    "",
    "```{r}",
    "x <- translatable_looking_but_code()",
    "labs(y = \"Loss\")",
    "```",
    "",
    "Prose after."
  ), tmp)
  ex <- extract_qmd(tmp)
  all_text <- paste(vapply(ex$segments, function(s) as.character(s$text), character(1)),
                    collapse = "\n")
  expect_false(grepl("translatable_looking_but_code", all_text))
  expect_false(grepl('labs\\(y = "Loss"\\)', all_text))
  expect_true(grepl("Some prose before", all_text))
  expect_true(grepl("Prose after", all_text))
  # round-trip still byte-identical
  expect_true(roundtrip_file(tmp)$ok)
})

# ---------------------------------------------------------------------------
# 5. Files without a trailing newline round-trip exactly (no spurious newline).
# ---------------------------------------------------------------------------

test_that("trailing-newline state is preserved", {
  tmp <- tempfile(fileext = ".qmd")
  # write WITHOUT trailing newline
  con <- file(tmp, "wb")
  writeChar("Prose line one.\nProse line two.", con, eos = NULL)
  close(con)
  ex <- extract_qmd(tmp)
  expect_false(ex$trailing_newline)
  expect_true(roundtrip_file(tmp)$ok)
})

# ---------------------------------------------------------------------------
# 6. Segment ids are stable and structural addresses are well-formed.
# ---------------------------------------------------------------------------

test_that("segment ids are stable across repeated extraction and carry addresses", {
  f <- file.path(repo_root, "content", "days", "day-01", "11-deming-story.qmd")
  skip_if_not(file.exists(f))
  a <- extract_qmd(f)
  b <- extract_qmd(f)
  ids_a <- vapply(a$segments, function(s) s$id, character(1))
  ids_b <- vapply(b$segments, function(s) s$id, character(1))
  expect_identical(ids_a, ids_b)
  expect_true(all(nzchar(ids_a)))
  # addresses
  for (s in a$segments) {
    expect_true(as.integer(s$address$start_line) >= 1L)
    expect_true(as.integer(s$address$end_line) >= as.integer(s$address$start_line))
  }
})

# ---------------------------------------------------------------------------
# 7. Reinjecting a TRANSLATION changes only the targeted segment.
# ---------------------------------------------------------------------------

test_that("reinjecting a replacement rewrites only the targeted segment", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---",
    'title: "Original Title"',
    "---",
    "",
    "First paragraph stays.",
    "",
    "Second paragraph translated."
  ), tmp)
  ex <- extract_qmd(tmp)
  # find the segment whose text is the second paragraph
  target <- NULL
  for (s in ex$segments) if (grepl("Second paragraph", as.character(s$text))) target <- s$id
  expect_false(is.null(target))
  rebuilt <- reinject_qmd(tmp, ex, replacements = setNames(list("Deuxieme paragraphe traduit."), target))
  expect_true(grepl("First paragraph stays\\.", rebuilt))
  expect_true(grepl("Deuxieme paragraphe traduit\\.", rebuilt))
  expect_false(grepl("Second paragraph translated", rebuilt))
  # YAML and structure untouched
  expect_true(grepl('title: "Original Title"', rebuilt))
})
