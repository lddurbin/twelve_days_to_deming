# glossary-lock.R
#
# Lock the reviewer-completed glossary into the machine-readable termbase
# (issue #327). find_unresolved() is the single source of truth for what
# "resolved" means, shared between the CLI's non-zero exit and any caller
# that wants to check review progress without failing.
#
# A row is resolved once `decision` holds one of the three reviewer-facing
# values and, for "translate", `approved_fr` backs it up -- "keep english"
# and "gloss on first use" are valid without a French rendering.

VALID_DECISIONS <- c("translate", "keep english", "gloss on first use")

.nonblank <- function(x) !is.na(x) & nzchar(trimws(x))

#' term_en of every row in `review` that still needs a reviewer decision.
#'
#' @param review data.frame as returned by prepare_review_glossary(), after
#'   the reviewer has (partially) filled in approved_fr/decision.
#' @return character vector of term_en, in `review`'s row order.
find_unresolved <- function(review) {
  decision <- tolower(trimws(review$decision))
  valid_decision <- !is.na(decision) & decision %in% VALID_DECISIONS
  needs_fr <- valid_decision & decision == "translate"

  resolved <- valid_decision & (!needs_fr | .nonblank(review$approved_fr))

  review$term_en[!resolved]
}

#' Build the machine-readable termbase from a fully-resolved reviewer file.
#'
#' @param review data.frame as returned by prepare_review_glossary(), with
#'   every row resolved (see find_unresolved()).
#' @return a named list keyed by term_en, each entry holding decision
#'   (normalised to "translate"/"keep-english"/"gloss-first-use"),
#'   approved_fr, source, and reviewer_notes (NULL when blank, which
#'   jsonlite::write_json(..., null = "null") serialises as JSON `null`,
#'   not an absent key) -- ready for jsonlite::toJSON()/write_json().
#' @details Stops, listing every offending term_en, if any row is
#'   unresolved -- there is no partial lock.
lock_glossary <- function(review) {
  unresolved <- find_unresolved(review)
  if (length(unresolved) > 0L) {
    stop(
      "glossary lock failed -- ", length(unresolved),
      " term(s) still need a reviewer decision:\n  ",
      paste(unresolved, collapse = "\n  "),
      call. = FALSE
    )
  }

  decision_slug <- c(
    "translate" = "translate",
    "keep english" = "keep-english",
    "gloss on first use" = "gloss-first-use"
  )

  entries <- lapply(seq_len(nrow(review)), function(i) {
    list(
      decision = unname(decision_slug[[tolower(trimws(review$decision[i]))]]),
      approved_fr = if (.nonblank(review$approved_fr[i])) trimws(review$approved_fr[i]) else NULL,
      source = if (.nonblank(review$source[i])) review$source[i] else NULL,
      reviewer_notes = if (.nonblank(review$reviewer_notes[i])) review$reviewer_notes[i] else NULL
    )
  })
  names(entries) <- review$term_en

  entries
}
