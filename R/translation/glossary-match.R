# glossary-match.R
#
# Alias-aware term frequency/context matcher (issue #414).
#
# With the flattened segment frame (#412) and the curated seed (#413) in
# place, count how often each SEEDED term occurs across the corpus and in
# what contexts. This is the deterministic half of the glossary pipeline —
# unlike #415's open-ended mining, every term here is already known; this
# module only measures it.
#
# `match_terms(segments, seed)` returns one row per seed row, augmenting it
# with frequency / occurrence_types / contexts — the same seven-column shape
# discover_candidates() (#415) returns, so #416 can simply rbind() the two.
#
# No French rendering, no CSV writing, no term discovery here (see #413 for
# the seed itself, #415 for discovery, #416 for assembly).

# ---------------------------------------------------------------------------
# Term -> search pattern.
# ---------------------------------------------------------------------------

#' Escape literal PCRE metacharacters in x. Hyphen and space are deliberately
#' left alone: a later step turns runs of either into a flexible separator
#' class, so "common-cause" (the term_en slug) and "common cause" (free
#' prose) become the SAME search pattern.
.escape_regex <- function(x) {
  gsub("([\\\\^$.|?*+()\\[\\]{}])", "\\\\\\1", x, perl = TRUE)
}

#' Build one case-insensitive boundary-anchored PCRE pattern matching ANY
#' variant (term_en + pipe-split aliases) of a seed term.
#'
#' Variants are deduplicated (case-insensitively) so aliases that only differ
#' by hyphen-vs-space — seed-terms.csv routinely lists both, e.g. "common
#' cause" and "common-cause" — collapse to one alternative instead of double-
#' counting the same literal occurrence twice.
#'
#' Surviving alternatives are ordered LONGEST first: at a text position where
#' both "common cause" and "common-cause variation" would match, alternation
#' tries alternatives left to right, so a shorter alias tried first would
#' "win" the position and consume only its own span — silently truncating
#' what is actually the longer alias's occurrence. Longest-first guarantees
#' the fuller phrase is matched (and counted once) whenever it is present.
#'
#' Boundaries use lookaround (`(?<![A-Za-z0-9_])` / `(?![A-Za-z0-9_])`)
#' rather than `\b`: a plain `\b` requires a word/non-word transition at the
#' EDGE of the match, which fails for a variant that itself ends or starts on
#' punctuation (e.g. an abbreviation alias like "P.D.S.A. (cycle)") — neither
#' side of that boundary is a word character, so `\b` silently never matches.
#' Lookaround only asserts "not another letter/digit here", independent of
#' what character the match itself ends or starts on.
.term_pattern <- function(term_en, aliases) {
  variants <- c(as.character(term_en), strsplit(as.character(aliases), "|", fixed = TRUE)[[1]])
  variants <- trimws(variants)
  variants <- variants[nzchar(variants)]

  escaped <- .escape_regex(variants)
  patterns <- gsub("[- ]+", "[- ]+", escaped, perl = TRUE)
  patterns <- patterns[!duplicated(tolower(patterns))]
  patterns <- patterns[order(-nchar(patterns))]

  sprintf("(?<![A-Za-z0-9_])(?:%s)(?![A-Za-z0-9_])", paste(patterns, collapse = "|"))
}

# ---------------------------------------------------------------------------
# Public entry point.
# ---------------------------------------------------------------------------

.EMPTY_MATCHES <- data.frame(
  term_en = character(0), fr_rendering = character(0), source = character(0),
  frequency = integer(0), occurrence_types = character(0), contexts = character(0),
  decision_needed = logical(0), stringsAsFactors = FALSE
)

#' Alias-aware term frequency/context matcher.
#'
#' For every row of `seed`, count how often the term (or any of its aliases,
#' case-insensitive, hyphen/space-interchangeable) occurs across `segments`,
#' and record which surfaces it appears on and a few sample contexts.
#'
#' @param segments data.frame as returned by glossary_segments() (columns
#'   text, kind, occurrence_type, file, start_line).
#' @param seed data.frame as read from glossary/seed-terms.csv (columns
#'   term_en, fr_rendering, source, aliases, decision_needed); `aliases` is
#'   `|`-delimited.
#' @return data.frame with columns term_en, fr_rendering, source, frequency,
#'   occurrence_types (`|`-joined sorted "prose"/"r"/"ui", NA if zero
#'   occurrences), contexts (up to 3 `|`-joined sample snippets, NA if zero
#'   occurrences), decision_needed — one row per seed row, in seed's original
#'   order (sorting is #416's job, at merge time).
match_terms <- function(segments, seed) {
  if (nrow(seed) == 0L) return(.EMPTY_MATCHES)

  text <- segments$text
  otype <- segments$occurrence_type

  rows <- vector("list", nrow(seed))
  for (i in seq_len(nrow(seed))) {
    pattern <- .term_pattern(seed$term_en[i], seed$aliases[i])
    m <- gregexpr(pattern, text, perl = TRUE, ignore.case = TRUE)
    n_matches <- lengths(regmatches(text, m))
    hit <- n_matches > 0L

    samples <- trimws(gsub("\\s+", " ", text[hit], perl = TRUE))
    samples <- unique(substr(samples, 1, 160))
    samples <- head(samples[nzchar(samples)], 3L)

    rows[[i]] <- data.frame(
      term_en = seed$term_en[i],
      fr_rendering = seed$fr_rendering[i],
      source = seed$source[i],
      frequency = sum(n_matches),
      occurrence_types = if (any(hit)) paste(sort(unique(otype[hit])), collapse = "|") else NA_character_,
      contexts = if (length(samples)) paste(samples, collapse = " | ") else NA_character_,
      decision_needed = seed$decision_needed[i],
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
