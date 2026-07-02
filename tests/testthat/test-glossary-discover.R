# --- discover un-seeded candidate terms (issue #415) ---
#
# Acceptance criteria under test:
#   * No seed term (or alias) reappears as a discovered candidate.
#   * Every candidate is flagged decision_needed = TRUE with an empty
#     fr_rendering.
#   * The frequency threshold is configurable.
#
# Plus coverage for the individual mining strategies (bigram, trigram,
# capitalised-phrase, exact-repeat UI label) and determinism, matching the
# testing discipline set by test-glossary-corpus.R.

source(here::here("R/translation/glossary-discover.R"))

repo_root <- here::here()

#' Build a minimal segments data.frame matching glossary_segments()'s schema.
.mk_segments <- function(text, kind = "prose", file = "test.qmd") {
  n <- length(text)
  data.frame(
    text = text,
    kind = rep(kind, length.out = n),
    occurrence_type = rep(ifelse(kind == "prose", "prose", "ui"), length.out = n),
    file = rep(file, length.out = n),
    start_line = seq_len(n),
    stringsAsFactors = FALSE
  )
}

#' Build a minimal seed data.frame matching seed-terms.csv's schema.
.mk_seed <- function(term_en, aliases, fr_rendering = "x", source = "test", decision_needed = FALSE) {
  n <- length(term_en)
  data.frame(
    term_en = term_en, fr_rendering = rep(fr_rendering, n), source = rep(source, n),
    aliases = aliases, decision_needed = rep(decision_needed, n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. Seed exclusion (AC1) — the core, most important guarantee.
# ---------------------------------------------------------------------------

test_that("a seeded term does not reappear as a discovered candidate", {
  seed <- .mk_seed("common-cause", "common cause|common-cause variation")
  segments <- .mk_segments(rep(
    "Deming taught us that common cause variation matters a great deal in practice.", 6
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("common cause" %in% tolower(cand$term_en))
})

test_that("seed exclusion matches regardless of hyphenation or case", {
  # term_en is a kebab slug; the corpus mentions the Title Case alias form.
  seed <- .mk_seed("system-of-profound-knowledge", "System of Profound Knowledge|SoPK")
  segments <- .mk_segments(rep(
    "Every part of the System of Profound Knowledge reinforces the others.", 6
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("system of profound knowledge" %in% tolower(cand$term_en))
})

test_that("a genuinely new recurring phrase is still discovered alongside an excluded seed term", {
  seed <- .mk_seed("common-cause", "common cause")
  segments <- .mk_segments(c(
    rep("Deming taught us that common cause variation matters in practice.", 6),
    rep("The Widget Assembly Protocol was reviewed again this week.", 6)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 5)

  expect_false("common cause" %in% tolower(cand$term_en))
  expect_true("widget assembly protocol" %in% tolower(cand$term_en))
})

# ---------------------------------------------------------------------------
# 2. Every candidate: decision_needed = TRUE, blank fr_rendering (AC2).
# ---------------------------------------------------------------------------

test_that("every candidate has decision_needed = TRUE and NA fr_rendering/source", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again this week.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_true(nrow(cand) > 0)
  expect_true(all(cand$decision_needed))
  expect_true(all(is.na(cand$fr_rendering)))
  expect_true(all(is.na(cand$source)))
})

# ---------------------------------------------------------------------------
# 3. min_freq is configurable (AC3).
# ---------------------------------------------------------------------------

test_that("min_freq controls which candidates survive", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again.", 4))

  below <- discover_candidates(segments, seed, min_freq = 5)
  at    <- discover_candidates(segments, seed, min_freq = 4)

  expect_false("widget assembly protocol" %in% tolower(below$term_en))
  expect_true("widget assembly protocol" %in% tolower(at$term_en))
})

# ---------------------------------------------------------------------------
# 4. Individual mining strategies.
# ---------------------------------------------------------------------------

test_that("a recurring bigram of content words is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please inspect the control chart before the next shift.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("control chart" %in% tolower(cand$term_en))
})

test_that("bigrams where every token is a stopword are never candidates", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("This happens because of the way that it is used, and of that.", 8))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("of the" %in% tolower(cand$term_en))
  expect_false("and of" %in% tolower(cand$term_en))
})

test_that("a recurring trigram of content words is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The central limit theorem underpins a lot of this reasoning.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("central limit theorem" %in% tolower(cand$term_en))
})

test_that("a 4+ word capitalised-phrase run is discovered as one candidate, not fragments", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep(
    "Please review the Total Process Improvement Board before Friday.", 5
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("total process improvement board" %in% tolower(cand$term_en))
})

test_that("a capitalised phrase exactly bigram/trigram length is counted once, not doubled", {
  # "Optional Extras" is capitalised AND exactly 2 tokens long, so it is
  # reachable by both the plain bigram window and capitalised-phrase
  # detection. Each of the 5 occurrences below must contribute frequency 1,
  # not 2 (regression test for the double-count this design deliberately
  # avoids — see .cap_phrases()'s length >= 4 cutoff).
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please refer to the Optional Extras for more detail.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "optional extras", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$frequency, 5L)
})

test_that("an exact-repeat UI/ARIA label is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(
    rep("Type your comments here.", 5),
    kind = "ui-string"
  )

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("type your comments here." %in% tolower(cand$term_en))
  expect_equal(cand$occurrence_types[tolower(cand$term_en) == "type your comments here."], "ui")
})

test_that("occurrence_types aggregates across prose and ui surfaces for the same term", {
  seed <- .mk_seed(character(0), character(0))
  segments <- rbind(
    .mk_segments(rep("Please review the Technical Aid before you begin.", 4)),
    .mk_segments(rep("Technical Aid", 4), kind = "aria-label")
  )

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "technical aid", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$occurrence_types, "prose|ui")
  expect_equal(row$frequency, 8L)
})

# ---------------------------------------------------------------------------
# 5. Determinism and edge cases.
# ---------------------------------------------------------------------------

test_that("discover_candidates is deterministic", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again.", 5))

  a <- discover_candidates(segments, seed, min_freq = 3)
  b <- discover_candidates(segments, seed, min_freq = 3)

  expect_identical(a, b)
})

test_that("empty segments yield an empty, correctly-shaped result", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(character(0))

  cand <- discover_candidates(segments, seed, min_freq = 1)

  expect_equal(nrow(cand), 0L)
  expect_identical(
    colnames(cand),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

test_that("results are sorted by frequency desc, then term_en asc", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("Please inspect the control chart today.", 6),
    rep("The Widget Assembly Protocol was reviewed again.", 4)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_true(all(diff(cand$frequency) <= 0))
})

# ---------------------------------------------------------------------------
# 6. Real-corpus integration smoke test (mirrors test-glossary-corpus.R).
# ---------------------------------------------------------------------------

test_that("discover_candidates on the real corpus never reproduces a seeded term/alias", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  cand <- discover_candidates(segments, seed, min_freq = 10)

  excluded <- .seed_exclusion_set(seed)
  expect_equal(sum(.norm_term(cand$term_en) %in% excluded), 0L)
  expect_true(all(cand$decision_needed))
  expect_true(all(is.na(cand$fr_rendering)))
})
