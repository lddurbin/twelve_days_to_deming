# glossary-assemble.R
#
# Assemble the idempotent draft glossary (issue #416).
#
# The final integration step of the pipeline: merge the seed's measured
# frequencies/contexts (#413 + #414) with the un-seeded candidates mined from
# the corpus (#415) into the single deliverable the reviewer lock (#327)
# consumes. Both match_terms() and discover_candidates() already return the
# same seven-column shape, so this module's only job is rbind + a stable
# sort — no new term logic lives here.
#
# Determinism: match_terms() and discover_candidates() are themselves
# deterministic (same segments/seed in -> identical() frame out), and
# order() is a stable sort, so build_draft_glossary() is idempotent by
# construction — re-running against an unchanged corpus produces a
# byte-identical draft-glossary.csv.

.glossary_assemble_dir <- (function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) {
    d <- dirname(normalizePath(sub("^--file=", "", m[1])))
    if (file.exists(file.path(d, "glossary-corpus.R"))) return(d)
  }
  for (fr in rev(sys.frames())) {
    of <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("glossary-assemble[.]R$", of)) {
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

source(file.path(.glossary_assemble_dir, "glossary-match.R"))
source(file.path(.glossary_assemble_dir, "glossary-discover.R"))

#' Assemble the draft glossary: seed terms (with measured frequency/context)
#' plus un-seeded discovered candidates, in one deterministically-sorted
#' frame.
#'
#' @param segments data.frame as returned by glossary_segments() (columns
#'   text, kind, occurrence_type, file, start_line).
#' @param seed data.frame as read from glossary/seed-terms.csv (columns
#'   term_en, fr_rendering, source, aliases, decision_needed).
#' @param min_freq minimum occurrence count for a discovered candidate to be
#'   included (passed through to discover_candidates()).
#' @return data.frame with columns term_en, fr_rendering, source, frequency,
#'   occurrence_types, contexts, decision_needed — sorted by frequency desc,
#'   then term_en asc, for stable, idempotent tie-breaks.
build_draft_glossary <- function(segments, seed, min_freq = 5L) {
  seeded <- match_terms(segments, seed)
  discovered <- discover_candidates(segments, seed, min_freq = min_freq)

  out <- rbind(seeded, discovered)
  out <- out[order(-out$frequency, out$term_en), ]
  rownames(out) <- NULL
  out
}
