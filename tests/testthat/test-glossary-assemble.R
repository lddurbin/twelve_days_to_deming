# --- assemble idempotent draft-glossary.csv (issue #416) ---
#
# Acceptance criteria under test:
#   * All canonical seed terms appear (with their proposed French renderings)
#     alongside discovered candidates in one merged frame.
#   * Each row carries frequency, context, and occurrence_type.
#   * Invented/contested seed renderings and every discovered candidate are
#     flagged decision_needed.
#   * Re-running produces a byte-identical draft-glossary.csv (idempotence).
#   * Stable column schema; sorted by frequency desc, then term_en asc.

source(here::here("R/translation/glossary-assemble.R"))

repo_root <- here::here()

#' Build a minimal segments data.frame matching glossary_segments()'s schema.
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
.mk_seed <- function(term_en, aliases, fr_rendering = "x", source = "test", decision_needed = FALSE) {
  n <- length(term_en)
  data.frame(
    term_en = term_en, fr_rendering = rep(fr_rendering, length.out = n), source = rep(source, length.out = n),
    aliases = aliases, decision_needed = rep(decision_needed, length.out = n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. Seed rows and discovered candidates both surface in the merged frame.
# ---------------------------------------------------------------------------

test_that("build_draft_glossary merges seed rows with discovered candidates", {
  # Row count is asserted against match_terms()/discover_candidates() output
  # directly, not a hardcoded number: a short repeated sentence yields several
  # overlapping bigram/trigram candidates (discover_candidates()'s own
  # concern, not this merge step's), so pinning an exact count here would
  # just duplicate that module's tests while being fragile to its tuning.
  seed <- .mk_seed("common-cause", "common cause", fr_rendering = "causes communes")
  segments <- .mk_segments(c(
    rep("Deming taught us that common cause variation matters.", 6),
    rep("The Widget Assembly Protocol was reviewed again today.", 6)
  ))

  out <- build_draft_glossary(segments, seed, min_freq = 3L)
  seeded <- match_terms(segments, seed)
  discovered <- discover_candidates(segments, seed, min_freq = 3L)

  expect_true(nrow(discovered) > 0L)
  expect_equal(nrow(out), nrow(seeded) + nrow(discovered))
  expect_true(setequal(out$term_en, c(seeded$term_en, discovered$term_en)))
})

test_that("seed terms carry their proposed fr_rendering through untouched", {
  seed <- .mk_seed("common-cause", "common cause", fr_rendering = "causes communes")
  segments <- .mk_segments("common cause variation is discussed here.")

  out <- build_draft_glossary(segments, seed, min_freq = 5L)

  expect_equal(out$fr_rendering[out$term_en == "common-cause"], "causes communes")
})

# ---------------------------------------------------------------------------
# 2. decision_needed flagging (AC3).
# ---------------------------------------------------------------------------

test_that("a contested seed rendering keeps its decision_needed = TRUE flag", {
  seed <- .mk_seed("pdsa-cycle", "PDSA", fr_rendering = "PDSA", decision_needed = TRUE)
  segments <- .mk_segments("The PDSA cycle repeats continuously.")

  out <- build_draft_glossary(segments, seed, min_freq = 5L)

  expect_true(out$decision_needed[out$term_en == "pdsa-cycle"])
})

test_that("an established seed rendering keeps its decision_needed = FALSE flag", {
  seed <- .mk_seed("common-cause", "common cause", decision_needed = FALSE)
  segments <- .mk_segments("common cause variation is discussed here.")

  out <- build_draft_glossary(segments, seed, min_freq = 5L)

  expect_false(out$decision_needed[out$term_en == "common-cause"])
})

test_that("every discovered candidate is flagged decision_needed with no invented fr_rendering", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again today.", 6))

  out <- build_draft_glossary(segments, seed, min_freq = 3L)

  expect_true(nrow(out) > 0L)
  expect_true(all(out$decision_needed))
  expect_true(all(is.na(out$fr_rendering)))
})

# ---------------------------------------------------------------------------
# 3. Each row records frequency, context, and occurrence_type (AC2).
# ---------------------------------------------------------------------------

test_that("every row records frequency, occurrence_types, and contexts", {
  seed <- .mk_seed("funnel", "funnel experiment")
  segments <- rbind(
    .mk_segments("The funnel experiment demonstrates tampering.", kind = "prose"),
    .mk_segments(rep("The Widget Assembly Protocol was reviewed again today.", 6), kind = "prose")
  )

  out <- build_draft_glossary(segments, seed, min_freq = 3L)

  expect_false(any(is.na(out$frequency)))
  expect_true(all(out$frequency > 0L))
  expect_false(any(is.na(out$occurrence_types)))
  expect_false(any(is.na(out$contexts)))
})

# ---------------------------------------------------------------------------
# 4. Column schema and sort order.
# ---------------------------------------------------------------------------

test_that("output has the stable seven-column schema", {
  seed <- .mk_seed("common-cause", "common cause")
  segments <- .mk_segments("common cause variation is discussed here.")

  out <- build_draft_glossary(segments, seed)

  expect_identical(
    colnames(out),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

test_that("rows are sorted by frequency desc, then term_en asc for ties", {
  seed <- .mk_seed(
    c("common-cause", "special-cause", "funnel"),
    c("common cause", "special cause", "funnel experiment")
  )
  segments <- .mk_segments(c(
    rep("common cause variation happens here.", 5),
    rep("special cause variation happens here.", 5),
    rep("the funnel experiment demonstrates tampering.", 2)
  ))

  out <- build_draft_glossary(segments, seed, min_freq = 5L)

  expect_true(all(diff(out$frequency) <= 0))
  tied <- out[out$frequency == 5L, ]
  expect_identical(tied$term_en, sort(tied$term_en))
})

# ---------------------------------------------------------------------------
# 5. Idempotence (AC4): re-running produces a byte-identical file.
# ---------------------------------------------------------------------------

test_that("build_draft_glossary is deterministic across repeated calls", {
  seed <- .mk_seed(
    c("common-cause", "special-cause"),
    c("common cause", "special cause")
  )
  segments <- .mk_segments(c(
    "common cause and special cause variation both matter.",
    "special cause events need investigation.",
    rep("the widget assembly protocol was reviewed again today.", 6)
  ))

  a <- build_draft_glossary(segments, seed, min_freq = 3L)
  b <- build_draft_glossary(segments, seed, min_freq = 3L)

  expect_identical(a, b)
})

test_that("writing the same draft twice produces byte-identical CSV files", {
  seed <- .mk_seed(
    c("common-cause", "special-cause"),
    c("common cause", "special cause")
  )
  segments <- .mk_segments(c(
    "common cause and special cause variation both matter.",
    rep("the widget assembly protocol was reviewed again today.", 6)
  ))

  path_a <- tempfile(fileext = ".csv")
  path_b <- tempfile(fileext = ".csv")
  on.exit(unlink(c(path_a, path_b)))

  write.csv(build_draft_glossary(segments, seed, min_freq = 3L), path_a, row.names = FALSE)
  write.csv(build_draft_glossary(segments, seed, min_freq = 3L), path_b, row.names = FALSE)

  expect_identical(readLines(path_a), readLines(path_b))
})

# ---------------------------------------------------------------------------
# 6. Edge case.
# ---------------------------------------------------------------------------

test_that("empty seed and segments yield an empty, correctly-shaped result", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(character(0))

  out <- build_draft_glossary(segments, seed, min_freq = 1L)

  expect_equal(nrow(out), 0L)
  expect_identical(
    colnames(out),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

# ---------------------------------------------------------------------------
# 7. Real-corpus integration smoke test (mirrors sibling glossary tests).
# ---------------------------------------------------------------------------

test_that("build_draft_glossary on the real corpus covers every seed term and stays sorted", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  out <- build_draft_glossary(segments, seed)

  expect_true(all(seed$term_en %in% out$term_en))
  expect_true(nrow(out) >= nrow(seed))
  expect_false(any(is.na(out$frequency)))
  expect_true(all(diff(out$frequency) <= 0))

  discovered <- out[!out$term_en %in% seed$term_en, ]
  expect_true(all(discovered$decision_needed))
  expect_true(all(is.na(discovered$fr_rendering)))
})
