# --- alias-aware term frequency/context matcher (issue #414) ---
#
# Acceptance criteria under test:
#   * Alias variants (e.g. "common cause" / "common-cause variation") are
#     counted as a single term.
#   * occurrence_types aggregation across surfaces (prose/r/ui) is covered
#     by tests.
#   * Matching is case-insensitive and deterministic.

source(here::here("R/translation/glossary-corpus.R"))
source(here::here("R/translation/glossary-match.R"))

repo_root <- here::here()

#' Build a minimal segments data.frame matching glossary_segments()'s schema.
#' occurrence_type is derived via the real .occurrence_type() mapping (from
#' glossary-corpus.R) so these mocks can never drift from the real kind ->
#' occurrence_type contract.
.mk_segments <- function(text, kind = "prose", file = "test.qmd") {
  n <- length(text)
  data.frame(
    text = text,
    kind = rep(kind, length.out = n),
    occurrence_type = .occurrence_type(rep(kind, length.out = n)),
    file = rep(file, length.out = n),
    start_line = seq_len(n),
    stringsAsFactors = FALSE
  )
}

#' Build a minimal seed data.frame matching seed-terms.csv's schema.
#' rep(x, length.out = n), not rep(x, n): the latter mis-recycles when the
#' caller passes a full-length vector (e.g. decision_needed = c(FALSE, TRUE)
#' for n = 2) instead of relying on the scalar default.
.mk_seed <- function(term_en, aliases, fr_rendering = "x", source = "test", decision_needed = FALSE) {
  n <- length(term_en)
  data.frame(
    term_en = term_en, fr_rendering = rep(fr_rendering, length.out = n), source = rep(source, length.out = n),
    aliases = aliases, decision_needed = rep(decision_needed, length.out = n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. Alias variants collapse into a single term (AC1).
# ---------------------------------------------------------------------------

test_that("alias variants are counted as one term's frequency", {
  seed <- .mk_seed("common-cause", "common cause|common-cause variation")
  segments <- .mk_segments(c(
    rep("Deming taught us that common cause variation matters.", 3),
    rep("This is common-cause variation, not special-cause.", 2),
    rep("Unrelated sentence about something else entirely.", 4)
  ))

  out <- match_terms(segments, seed)

  expect_equal(nrow(out), 1L)
  expect_equal(out$term_en, "common-cause")
  expect_equal(out$frequency, 5L)
})

test_that("a longer alias occurrence is counted once, not split across a shorter alias it contains", {
  # "common-cause variation" literally contains "common cause" as a prefix
  # once separators are normalised; the longer alias must win the position
  # so this counts as ONE occurrence, not two.
  seed <- .mk_seed("common-cause", "common cause|common-cause variation")
  segments <- .mk_segments("We observed common-cause variation during the run.")

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 1L)
})

test_that("hyphen and space forms of the same term_en are treated as the same variant", {
  seed <- .mk_seed("in-statistical-control", "in statistical control")
  segments <- .mk_segments(c(
    "The process is in-statistical-control this week.",
    "The process is in statistical control this week."
  ))

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 2L)
})

# ---------------------------------------------------------------------------
# 2. occurrence_types aggregates across prose/r/ui surfaces (AC2).
# ---------------------------------------------------------------------------

test_that("occurrence_types aggregates prose, r, and ui surfaces for the same term", {
  seed <- .mk_seed("funnel", "funnel experiment")
  segments <- rbind(
    .mk_segments("The funnel experiment demonstrates tampering.", kind = "prose"),
    .mk_segments("funnel experiment", kind = "r-string"),
    .mk_segments("funnel experiment", kind = "ui-string")
  )

  out <- match_terms(segments, seed)

  expect_equal(out$occurrence_types, "prose|r|ui")
  expect_equal(out$frequency, 3L)
})

test_that("occurrence_types is NA, not empty string, when a term has zero occurrences", {
  seed <- .mk_seed("psychology", "theory of psychology")
  segments <- .mk_segments("This corpus never mentions that concept at all.")

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 0L)
  expect_true(is.na(out$occurrence_types))
  expect_true(is.na(out$contexts))
})

# ---------------------------------------------------------------------------
# 3. Case-insensitive and deterministic (AC3).
# ---------------------------------------------------------------------------

test_that("matching is case-insensitive", {
  seed <- .mk_seed("system-of-profound-knowledge", "System of Profound Knowledge|SoPK")
  segments <- .mk_segments(c(
    "SYSTEM OF PROFOUND KNOWLEDGE underpins everything Deming taught.",
    "sopk is the acronym some readers will recognise."
  ))

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 2L)
})

test_that("match_terms is deterministic", {
  seed <- .mk_seed(
    c("common-cause", "special-cause"),
    c("common cause", "special cause")
  )
  segments <- .mk_segments(c(
    "common cause and special cause variation both matter.",
    "special cause events need investigation."
  ))

  a <- match_terms(segments, seed)
  b <- match_terms(segments, seed)

  expect_identical(a, b)
})

# ---------------------------------------------------------------------------
# 4. Multiple occurrences within one segment; contexts; row shape.
# ---------------------------------------------------------------------------

test_that("repeated mentions within a single segment each count", {
  seed <- .mk_seed("control-chart", "control chart")
  segments <- .mk_segments(
    "A control chart shows variation. Review the control chart weekly."
  )

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 2L)
})

test_that("contexts carries a sample snippet, collapsed and truncated", {
  seed <- .mk_seed("red-beads", "red bead experiment")
  segments <- .mk_segments("The   red bead experiment   \n teaches variation.")

  out <- match_terms(segments, seed)

  expect_false(is.na(out$contexts))
  expect_true(grepl("red bead experiment", out$contexts, fixed = TRUE))
  expect_false(grepl("  ", out$contexts, fixed = TRUE))
})

test_that("output has one row per seed row, in seed's original order, with fr_rendering/source/decision_needed passed through", {
  seed <- .mk_seed(
    c("special-cause", "common-cause"),
    c("special cause", "common cause"),
    fr_rendering = c("causes speciales", "causes communes"),
    decision_needed = c(FALSE, TRUE)
  )
  segments <- .mk_segments("special cause and common cause both occur here.")

  out <- match_terms(segments, seed)

  expect_equal(nrow(out), 2L)
  expect_identical(out$term_en, c("special-cause", "common-cause"))
  expect_identical(out$fr_rendering, c("causes speciales", "causes communes"))
  expect_identical(out$decision_needed, c(FALSE, TRUE))
  expect_identical(
    colnames(out),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

test_that("a variant containing regex metacharacters is matched literally, not as a broken pattern", {
  seed <- .mk_seed("plan-do-study-act", "P.D.S.A. (cycle)")
  segments <- .mk_segments("Deming's P.D.S.A. (cycle) repeats continuously.")

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 1L)
})

test_that("a seed row with NA aliases matches only term_en, not the literal string 'NA'", {
  # Regression test: NA aliases (a term with none yet curated) must never
  # leak a literal "NA" alternative into the search pattern — a corpus
  # mention of the unrelated text "NA" must not be counted.
  seed <- .mk_seed("variation", NA_character_)
  segments <- .mk_segments(c(
    "variation in the process is expected",
    "the result is NA here"
  ))

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 1L)
})

test_that("a seed row with an empty-string aliases value matches only term_en", {
  seed <- .mk_seed("variation", "")
  segments <- .mk_segments("variation in the process is expected")

  out <- match_terms(segments, seed)

  expect_equal(out$frequency, 1L)
})

test_that("empty seed yields an empty, correctly-shaped result", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments("Any text at all.")

  out <- match_terms(segments, seed)

  expect_equal(nrow(out), 0L)
  expect_identical(
    colnames(out),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

# ---------------------------------------------------------------------------
# 5. Real-corpus integration smoke test (mirrors test-glossary-discover.R).
# ---------------------------------------------------------------------------

test_that("match_terms on the real corpus covers every seed term with no NA frequency", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  out <- match_terms(segments, seed)

  expect_equal(nrow(out), nrow(seed))
  expect_identical(out$term_en, seed$term_en)
  expect_false(any(is.na(out$frequency)))
  expect_true(all(out$frequency >= 0L))
})
