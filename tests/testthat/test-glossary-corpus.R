# --- glossary corpus loader (issue #412) ---
#
# Acceptance criteria for the flattened segment frame:
#   * glossary_segments() returns one row per extracted segment across all three
#     corpora (cross-checked against summing the extract_* segment counts).
#   * the kind/context -> occurrence_type mapping is covered by direct unit tests
#     of the helper for every kind value.
#   * idempotence: two calls return identical() frames.
#
# PURE READ — no term logic, no matching, no French (sibling issues).

source(here::here("R/translation/glossary-corpus.R"))

repo_root <- here::here()

# ---------------------------------------------------------------------------
# 1. Row count == sum of extract_* segment counts across all three corpora.
# ---------------------------------------------------------------------------

test_that("glossary_segments returns one row per extracted segment across all corpora", {
  qmd_files <- qmd_corpus(repo_root)
  r_files   <- r_corpus(repo_root)
  js_files  <- js_corpus(repo_root)

  expected <-
    sum(vapply(qmd_files, function(f) length(extract_qmd(f, rel_path = f)$segments), integer(1))) +
    sum(vapply(r_files,   function(f) length(extract_r_file(f, rel_path = f)$segments), integer(1))) +
    sum(vapply(js_files,  function(f) length(extract_js_file(f, rel_path = f)$segments), integer(1)))

  frame <- glossary_segments(repo_root)

  expect_identical(nrow(frame), as.integer(expected))
  # sane lower bound: the prose corpus alone is well into the thousands of segments
  expect_gt(nrow(frame), 500L)
  expect_identical(
    colnames(frame),
    c("text", "kind", "occurrence_type", "file", "start_line")
  )
  expect_true(is.character(frame$text))
  expect_true(is.character(frame$kind))
  expect_true(is.character(frame$occurrence_type))
  expect_true(is.character(frame$file))
  expect_true(is.integer(frame$start_line))
})

# ---------------------------------------------------------------------------
# 2. kind normalisation and kind/context -> occurrence_type mapping.
# ---------------------------------------------------------------------------

test_that("kind normalisation maps yaml_value -> yaml and leaves others intact", {
  expect_identical(.normalise_kind("yaml_value"), "yaml")
  expect_identical(.normalise_kind("prose"), "prose")
  expect_identical(.normalise_kind("r-string"), "r-string")
  expect_identical(.normalise_kind("ui-string"), "ui-string")
  expect_identical(.normalise_kind("aria-label"), "aria-label")
  # vectorised
  expect_identical(
    .normalise_kind(c("yaml_value", "prose", "ui-string")),
    c("yaml", "prose", "ui-string")
  )
})

test_that("occurrence_type covers every kind value", {
  # raw front-matter kind and its normalised form both bucket to prose
  expect_identical(.occurrence_type("yaml_value"), "prose")
  expect_identical(.occurrence_type("yaml"), "prose")
  expect_identical(.occurrence_type("prose"), "prose")
  expect_identical(.occurrence_type("r-string"), "r")
  expect_identical(.occurrence_type("ui-string"), "ui")
  expect_identical(.occurrence_type("aria-label"), "ui")

  # context is accepted but does not change the result for any kind
  expect_identical(.occurrence_type("ui-string", context = "ojs-input"), "ui")
  expect_identical(.occurrence_type("aria-label", context = "html-attr"), "ui")
  expect_identical(.occurrence_type("r-string", context = NA_character_), "r")

  # vectorised over every kind at once
  expect_identical(
    .occurrence_type(c("yaml_value", "prose", "r-string", "ui-string", "aria-label")),
    c("prose", "prose", "r", "ui", "ui")
  )
})

test_that("occurrence_type errors loudly on an unmapped kind", {
  expect_error(.occurrence_type("totally-unknown-kind"), "unmapped segment kind")
})

# ---------------------------------------------------------------------------
# 3. The frame's own kind/occurrence_type columns are internally consistent.
# ---------------------------------------------------------------------------

test_that("frame kind values are normalised and occurrence_type agrees with kind", {
  frame <- glossary_segments(repo_root)
  # no raw "yaml_value" leaks into the frame
  expect_false("yaml_value" %in% frame$kind)
  expect_true(all(frame$kind %in%
    c("prose", "yaml", "r-string", "ui-string", "aria-label")))
  expect_true(all(frame$occurrence_type %in% c("prose", "r", "ui")))
  # the column is exactly what the helper would derive from the kind
  expect_identical(frame$occurrence_type, .occurrence_type(frame$kind))
})

# ---------------------------------------------------------------------------
# 4. Idempotence: same input tree -> identical() frame.
# ---------------------------------------------------------------------------

test_that("glossary_segments is idempotent", {
  a <- glossary_segments(repo_root)
  b <- glossary_segments(repo_root)
  expect_identical(a, b)
})
