# glossary-review.R
#
# Prepare the reviewer-facing glossary (issue #327).
#
# Adds three fillable columns -- approved_fr, decision, reviewer_notes -- to
# the assembled draft (#416). Terms that are already established
# (decision_needed == FALSE with a sourced fr_rendering) are pre-resolved as
# "translate" so the human reviewer's bounded effort concentrates on the
# contested seed terms and discovered candidates that actually need a call.
#
# Re-running against a newer draft preserves any decisions already recorded
# in an existing reviewer file (matched by term_en): regenerating the file
# must never clobber in-progress human review.

.glossary_review_dir <- (function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) {
    d <- dirname(normalizePath(sub("^--file=", "", m[1])))
    if (file.exists(file.path(d, "glossary-corpus.R"))) return(d)
  }
  for (fr in rev(sys.frames())) {
    of <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("glossary-review[.]R$", of)) {
      d <- dirname(normalizePath(of))
      if (file.exists(file.path(d, "glossary-corpus.R"))) return(d)
    }
  }
  d <- normalizePath(getwd())
  repeat {
    cand <- file.path(d, "R", "translation")
    if (file.exists(file.path(cand, "glossary-corpus.R"))) return(cand)
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  file.path("R", "translation")
})()

# .nonblank() lives in glossary-lock.R; sourcing it here (rather than
# redefining it) is what keeps the two modules' notion of "blank" from
# silently drifting apart if one is edited without the other.
source(file.path(.glossary_review_dir, "glossary-lock.R"))

#' Build the reviewer-facing glossary from the assembled draft.
#'
#' @param draft data.frame as returned by build_draft_glossary() / read from
#'   glossary/draft-glossary.csv.
#' @param existing NULL, or a previously-written reviewer data.frame (same
#'   shape as this function's return value) whose approved_fr/decision/
#'   reviewer_notes take precedence over fresh pre-fills, keyed by term_en.
#' @return data.frame: draft's columns plus approved_fr, decision,
#'   reviewer_notes (all NA_character_ by default). Established terms
#'   (decision_needed == FALSE with a non-blank fr_rendering) are pre-filled
#'   decision = "translate", approved_fr = fr_rendering; every other row
#'   starts blank pending review. Row order matches `draft`.
prepare_review_glossary <- function(draft, existing = NULL) {
  out <- draft
  out$approved_fr <- NA_character_
  out$decision <- NA_character_
  out$reviewer_notes <- NA_character_

  established <- !out$decision_needed & .nonblank(out$fr_rendering)
  out$approved_fr[established] <- out$fr_rendering[established]
  out$decision[established] <- "translate"

  if (!is.null(existing) && nrow(existing) > 0L) {
    idx <- match(out$term_en, existing$term_en)
    have <- which(!is.na(idx))

    carry <- function(col) {
      prior <- existing[[col]][idx[have]]
      keep <- have[.nonblank(prior)]
      out[[col]][keep] <<- existing[[col]][idx[keep]]
    }
    carry("approved_fr")
    carry("decision")
    carry("reviewer_notes")
  }

  out
}
