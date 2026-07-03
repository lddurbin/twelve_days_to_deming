# --- lock the reviewer-completed glossary (issue #327) ---
#
# Acceptance criteria under test:
#   * approved-glossary.json's underlying structure is produced only when
#     every term is resolved.
#   * The lock step's failure path lists every offending term_en.

source(here::here("R/translation/glossary-lock.R"))

repo_root <- here::here()

#' Build a minimal reviewer-glossary-shaped data.frame.
.mk_review <- function(term_en, approved_fr = NA_character_, decision = NA_character_,
                        source = NA_character_, reviewer_notes = NA_character_) {
  n <- length(term_en)
  data.frame(
    term_en = term_en,
    approved_fr = rep(approved_fr, length.out = n),
    decision = rep(decision, length.out = n),
    source = rep(source, length.out = n),
    reviewer_notes = rep(reviewer_notes, length.out = n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. find_unresolved().
# ---------------------------------------------------------------------------

test_that("a blank decision is unresolved", {
  review <- .mk_review("common-cause")
  expect_equal(find_unresolved(review), "common-cause")
})

test_that("translate without an approved_fr is unresolved", {
  review <- .mk_review("common-cause", decision = "translate")
  expect_equal(find_unresolved(review), "common-cause")
})

test_that("translate with an approved_fr is resolved", {
  review <- .mk_review("common-cause", approved_fr = "causes communes", decision = "translate")
  expect_length(find_unresolved(review), 0L)
})

test_that("keep english and gloss on first use are resolved without an approved_fr", {
  review <- .mk_review(
    c("widget", "gizmo"),
    decision = c("keep english", "gloss on first use")
  )
  expect_length(find_unresolved(review), 0L)
})

test_that("decision matching is case- and whitespace-insensitive", {
  review <- .mk_review(
    c("common-cause", "widget"),
    approved_fr = c("causes communes", NA),
    decision = c(" Translate ", "KEEP ENGLISH")
  )
  expect_length(find_unresolved(review), 0L)
})

test_that("an unrecognised decision value is unresolved", {
  review <- .mk_review("common-cause", approved_fr = "causes communes", decision = "maybe translate")
  expect_equal(find_unresolved(review), "common-cause")
})

test_that("only the offending rows are listed, in their original order", {
  review <- .mk_review(
    c("resolved-one", "unresolved-one", "resolved-two", "unresolved-two"),
    approved_fr = c("x", NA, NA, NA),
    decision = c("translate", NA, "keep english", "translate")
  )
  expect_equal(find_unresolved(review), c("unresolved-one", "unresolved-two"))
})

# ---------------------------------------------------------------------------
# 2. lock_glossary(): failure path.
# ---------------------------------------------------------------------------

test_that("lock_glossary stops and lists every unresolved term_en", {
  review <- .mk_review(c("common-cause", "special-cause"))

  expect_error(lock_glossary(review), regexp = "common-cause")
  expect_error(lock_glossary(review), regexp = "special-cause")
})

# ---------------------------------------------------------------------------
# 3. lock_glossary(): success path and JSON-readiness.
# ---------------------------------------------------------------------------

test_that("lock_glossary returns a named list keyed by term_en with normalised decisions", {
  review <- .mk_review(
    c("common-cause", "widget", "gizmo"),
    approved_fr = c("causes communes", NA, NA),
    decision = c("translate", "keep english", "gloss on first use"),
    source = c("cited source", NA, NA),
    reviewer_notes = c(NA, NA, "glose : petit gadget")
  )

  out <- lock_glossary(review)

  expect_identical(names(out), c("common-cause", "widget", "gizmo"))
  expect_equal(out[["common-cause"]]$decision, "translate")
  expect_equal(out[["common-cause"]]$approved_fr, "causes communes")
  expect_equal(out[["common-cause"]]$source, "cited source")
  expect_null(out[["common-cause"]]$reviewer_notes)

  expect_equal(out[["widget"]]$decision, "keep-english")
  expect_null(out[["widget"]]$approved_fr)

  expect_equal(out[["gizmo"]]$decision, "gloss-first-use")
  expect_equal(out[["gizmo"]]$reviewer_notes, "glose : petit gadget")
})

test_that("lock_glossary's output round-trips cleanly through jsonlite", {
  review <- .mk_review(
    "common-cause",
    approved_fr = "causes communes",
    decision = "translate"
  )

  json <- jsonlite::toJSON(lock_glossary(review), auto_unbox = TRUE, null = "null")
  parsed <- jsonlite::fromJSON(json)

  expect_equal(parsed$`common-cause`$approved_fr, "causes communes")
  expect_equal(parsed$`common-cause`$decision, "translate")
})

# ---------------------------------------------------------------------------
# 4. Real-file smoke test (documents current state; the real reviewer file
#    is not expected to be fully resolved yet).
# ---------------------------------------------------------------------------

test_that("pre-resolved (established) rows in the real review file are never flagged unresolved", {
  source(file.path(repo_root, "R", "translation", "glossary-review.R"))
  draft <- read.csv(file.path(repo_root, "glossary", "draft-glossary.csv"), stringsAsFactors = FALSE)
  review <- prepare_review_glossary(draft)

  pre_resolved <- review$term_en[!is.na(review$decision)]
  unresolved <- find_unresolved(review)

  expect_length(intersect(pre_resolved, unresolved), 0L)
})
