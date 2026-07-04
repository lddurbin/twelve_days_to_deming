# --- prepare reviewer-facing glossary (issue #327) ---
#
# Acceptance criteria under test:
#   * A clear reviewer-facing file with fillable approved_fr/decision/
#     reviewer_notes columns is generated from the assembled draft.
#   * Established (non-contested) seed terms are pre-resolved so reviewer
#     effort concentrates on what actually needs a decision.
#   * Re-running never clobbers decisions already recorded by a reviewer.

source(here::here("R/translation/glossary-review.R"))

repo_root <- here::here()

#' Build a minimal draft-glossary-shaped data.frame.
.mk_draft <- function(term_en, fr_rendering = NA_character_, source = NA_character_,
                       frequency = 5L, decision_needed = FALSE) {
  n <- length(term_en)
  data.frame(
    term_en = term_en,
    fr_rendering = rep(fr_rendering, length.out = n),
    source = rep(source, length.out = n),
    frequency = rep(frequency, length.out = n),
    occurrence_types = rep("prose", length.out = n),
    contexts = rep("some context", length.out = n),
    decision_needed = rep(decision_needed, length.out = n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. Schema.
# ---------------------------------------------------------------------------

test_that("adds the three fillable columns to the draft's schema", {
  draft <- .mk_draft("common-cause", fr_rendering = "causes communes")

  out <- prepare_review_glossary(draft)

  expect_identical(
    colnames(out),
    c(
      "term_en", "fr_rendering", "source", "frequency", "occurrence_types",
      "contexts", "decision_needed", "approved_fr", "decision", "reviewer_notes"
    )
  )
  expect_equal(nrow(out), nrow(draft))
})

# ---------------------------------------------------------------------------
# 2. Pre-resolution of established terms.
# ---------------------------------------------------------------------------

test_that("established terms are pre-filled decision = translate", {
  draft <- .mk_draft("common-cause", fr_rendering = "causes communes", decision_needed = FALSE)

  out <- prepare_review_glossary(draft)

  expect_equal(out$approved_fr, "causes communes")
  expect_equal(out$decision, "translate")
})

test_that("contested seed terms are left blank even with a candidate fr_rendering", {
  draft <- .mk_draft("pdsa-cycle", fr_rendering = "PDSA", decision_needed = TRUE)

  out <- prepare_review_glossary(draft)

  expect_true(is.na(out$approved_fr))
  expect_true(is.na(out$decision))
})

test_that("discovered candidates with no fr_rendering are left blank", {
  draft <- .mk_draft("widget-assembly", fr_rendering = NA_character_, decision_needed = TRUE)

  out <- prepare_review_glossary(draft)

  expect_true(is.na(out$approved_fr))
  expect_true(is.na(out$decision))
})

#' Build a minimal auto_resolutions-shaped data.frame.
.mk_auto <- function(term_en, decision, approved_fr = NA_character_, reviewer_notes = NA_character_) {
  n <- length(term_en)
  data.frame(
    term_en = term_en,
    decision = rep(decision, length.out = n),
    approved_fr = rep(approved_fr, length.out = n),
    reviewer_notes = rep(reviewer_notes, length.out = n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 2b. Curated auto-resolutions for discovered candidates.
# ---------------------------------------------------------------------------

test_that("a curated auto-resolution pre-fills decision/approved_fr and clears decision_needed", {
  draft <- .mk_draft("Gallery Furniture", fr_rendering = NA_character_, decision_needed = TRUE)
  auto <- .mk_auto("Gallery Furniture", "keep english", reviewer_notes = "real company name")

  out <- prepare_review_glossary(draft, auto_resolutions = auto)

  expect_equal(out$decision, "keep english")
  expect_true(is.na(out$approved_fr))
  expect_equal(out$reviewer_notes, "real company name")
  expect_false(out$decision_needed)
})

test_that("auto-resolution matching is case- and hyphen-insensitive, like seed exclusion", {
  draft <- .mk_draft("gallery furniture", fr_rendering = NA_character_, decision_needed = TRUE)
  auto <- .mk_auto("Gallery-Furniture", "keep english")

  out <- prepare_review_glossary(draft, auto_resolutions = auto)

  expect_equal(out$decision, "keep english")
})

test_that("a translate-type auto-resolution fills approved_fr too", {
  draft <- .mk_draft("Your comments.", fr_rendering = NA_character_, decision_needed = TRUE)
  auto <- .mk_auto("Your comments.", "translate", approved_fr = "Vos commentaires.",
                    reviewer_notes = "mechanical UI copy, auto-suggested")

  out <- prepare_review_glossary(draft, auto_resolutions = auto)

  expect_equal(out$decision, "translate")
  expect_equal(out$approved_fr, "Vos commentaires.")
})

test_that("auto-resolutions never override an already-established seed term", {
  draft <- .mk_draft("common-cause", fr_rendering = "causes communes", decision_needed = FALSE)
  auto <- .mk_auto("common-cause", "keep english")

  out <- prepare_review_glossary(draft, auto_resolutions = auto)

  expect_equal(out$decision, "translate")
  expect_equal(out$approved_fr, "causes communes")
})

test_that("a reviewer's override of an auto-resolution survives regenerating against a newer draft", {
  draft <- .mk_draft("Gallery Furniture", fr_rendering = NA_character_, decision_needed = TRUE)
  auto <- .mk_auto("Gallery Furniture", "keep english")
  first <- prepare_review_glossary(draft, auto_resolutions = auto)
  first$decision[1] <- "gloss on first use"
  first$reviewer_notes[1] <- "reviewer disagreed with auto-resolution"

  second <- prepare_review_glossary(draft, existing = first, auto_resolutions = auto)

  expect_equal(second$decision, "gloss on first use")
  expect_equal(second$reviewer_notes, "reviewer disagreed with auto-resolution")
})

test_that("a candidate absent from the auto-resolutions table is left blank", {
  draft <- .mk_draft("widget-assembly", fr_rendering = NA_character_, decision_needed = TRUE)
  auto <- .mk_auto("Gallery Furniture", "keep english")

  out <- prepare_review_glossary(draft, auto_resolutions = auto)

  expect_true(is.na(out$decision))
})

# ---------------------------------------------------------------------------
# 3. Merge-preserve across regenerations.
# ---------------------------------------------------------------------------

test_that("a reviewer's manual decision survives regenerating against a newer draft", {
  draft <- .mk_draft(
    c("common-cause", "pdsa-cycle"),
    fr_rendering = c("causes communes", "PDSA"),
    decision_needed = c(FALSE, TRUE)
  )
  first <- prepare_review_glossary(draft)
  first$decision[first$term_en == "pdsa-cycle"] <- "keep english"
  first$reviewer_notes[first$term_en == "pdsa-cycle"] <- "sigle conservé tel quel"

  second <- prepare_review_glossary(draft, existing = first)

  expect_equal(second$decision[second$term_en == "pdsa-cycle"], "keep english")
  expect_equal(second$reviewer_notes[second$term_en == "pdsa-cycle"], "sigle conservé tel quel")
})

test_that("a reviewer's override of a pre-filled established term is preserved", {
  draft <- .mk_draft("common-cause", fr_rendering = "causes communes", decision_needed = FALSE)
  first <- prepare_review_glossary(draft)
  first$approved_fr[1] <- "causes communes (variante)"

  second <- prepare_review_glossary(draft, existing = first)

  expect_equal(second$approved_fr, "causes communes (variante)")
})

test_that("new terms in a regenerated draft start fresh, unaffected by unrelated existing rows", {
  draft <- .mk_draft(
    c("common-cause", "special-cause"),
    fr_rendering = c("causes communes", "causes spéciales"),
    decision_needed = FALSE
  )
  existing <- prepare_review_glossary(.mk_draft("common-cause", fr_rendering = "causes communes"))

  out <- prepare_review_glossary(draft, existing = existing)

  expect_equal(out$decision[out$term_en == "special-cause"], "translate")
  expect_equal(out$approved_fr[out$term_en == "special-cause"], "causes spéciales")
})

test_that("terms dropped from a newer draft do not appear in the output", {
  draft <- .mk_draft("common-cause", fr_rendering = "causes communes")
  existing <- prepare_review_glossary(.mk_draft(
    c("common-cause", "retired-term"),
    fr_rendering = c("causes communes", "x")
  ))

  out <- prepare_review_glossary(draft, existing = existing)

  expect_false("retired-term" %in% out$term_en)
  expect_equal(nrow(out), 1L)
})

# ---------------------------------------------------------------------------
# 4. Real-corpus integration smoke test.
# ---------------------------------------------------------------------------

test_that("preparing the review file from the real draft glossary is well-formed", {
  draft <- read.csv(
    file.path(repo_root, "glossary", "draft-glossary.csv"),
    stringsAsFactors = FALSE, fileEncoding = "UTF-8"
  )

  out <- prepare_review_glossary(draft)

  expect_equal(nrow(out), nrow(draft))
  established <- !draft$decision_needed & .nonblank(draft$fr_rendering)
  expect_true(all(out$decision[established] == "translate"))
  expect_true(all(is.na(out$decision[!established])))
})
