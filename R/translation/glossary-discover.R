# glossary-discover.R
#
# Discover recurring un-seeded candidate terms (issue #415).
#
# Beyond the known canonical vocabulary curated in glossary/seed-terms.csv
# (#413), the corpus contains other recurring domain terms and named course
# concepts worth a glossary decision. This is the OPEN-ENDED, heuristic half
# of the glossary pipeline — deliberately quarantined from the deterministic
# seed -> match -> assemble spine (#412/#413/#414/#416) so it can iterate
# independently.
#
# Two mining strategies over `glossary_segments()` rows:
#   * prose (kind == "prose"): bigram/trigram frequency, plus maximal
#     capitalised-phrase runs (Title Case spans, allowing a single interior
#     connector word before another capitalised word — e.g. "System of
#     Profound Knowledge").
#   * ui (kind %in% c("ui-string", "aria-label")): exact-repeat whole-string
#     labels (e.g. "Type your comments here.").
#
# Anything already present in the seed (by term_en OR any alias, matched
# hyphen/case/whitespace-insensitively) is excluded — this tool proposes NEW
# candidates only, never re-litigates seeded terms. Every surviving candidate
# at or above `min_freq` is returned with a blank fr_rendering and
# decision_needed = TRUE: this tool never invents a French rendering, it only
# flags that one is needed (mirrors #413's "seed from established sources,
# don't invent" discipline).
#
# No NLP dependencies — base-R tokenisation only, reusing prose-extract.R's
# .mask_inline() (already sourced transitively via glossary-corpus.R) to
# strip the same protected inline constructs (code, math, citations, xrefs,
# dfn/span-lang wrappers, day-NN cross-links) that the translation pipeline
# itself treats as non-prose, so the miner never mistakes markup for a term.

.glossary_discover_dir <- (function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) {
    d <- dirname(normalizePath(sub("^--file=", "", m[1])))
    if (file.exists(file.path(d, "glossary-corpus.R"))) return(d)
  }
  for (fr in rev(sys.frames())) {
    of <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("glossary-discover[.]R$", of)) {
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

source(file.path(.glossary_discover_dir, "glossary-corpus.R"))

# ---------------------------------------------------------------------------
# Term normalisation (for seed exclusion matching).
# ---------------------------------------------------------------------------

# seed-terms.csv's term_en is a kebab-case slug ("system-of-profound-knowledge")
# while its aliases are free text ("System of Profound Knowledge"); a mined
# candidate is always free text. Normalising hyphens to spaces before
# lower-casing lets one comparison catch both forms.
.norm_term <- function(x) {
  x <- gsub("-", " ", x, fixed = TRUE)
  x <- tolower(trimws(x))
  gsub("\\s+", " ", x, perl = TRUE)
}

#' Build the set of normalised terms/aliases already present in the seed —
#' anything in this set must never be (re-)proposed as a discovered candidate.
.seed_exclusion_set <- function(seed) {
  terms <- .norm_term(seed$term_en)
  aliases <- unlist(strsplit(as.character(seed$aliases), "|", fixed = TRUE))
  aliases <- .norm_term(aliases[nzchar(trimws(aliases))])
  unique(c(terms, aliases))
}

# ---------------------------------------------------------------------------
# Prose cleaning + tokenisation.
# ---------------------------------------------------------------------------

# Common English function words. A bigram/trigram is only a discovery
# candidate if EVERY token is outside this list — pure connective phrases
# ("of course", "rather than", "in order", "need to") are not domain terms,
# and letting even one token be a stopword (e.g. "the control", "part of")
# reopened the flood gate to that same noise in earlier tuning.
.STOPWORDS <- c(
  "a", "an", "the", "of", "in", "on", "at", "to", "for", "and", "or", "but", "nor", "so", "yet",
  "is", "are", "was", "were", "be", "been", "being", "it", "its", "this", "that", "these", "those",
  "as", "by", "with", "from", "into", "onto", "over", "under", "not", "no", "if", "then", "than",
  "you", "your", "we", "our", "i", "he", "she", "they", "them", "his", "her", "their",
  "do", "does", "did", "have", "has", "had", "can", "could", "will", "would", "should", "may", "might",
  "there", "here", "what", "which", "who", "whom", "when", "where", "why", "how", "all", "some", "any",
  "one", "two", "three", "up", "down", "out", "about", "also", "just", "more", "most", "very"
)

# Lowercase words allowed INSIDE (never at the boundary of) a capitalised-
# phrase run, e.g. the "of" in "System of Profound Knowledge".
.CONNECTOR_WORDS <- c("of", "the", "and", "for", "to", "in", "a", "an")

#' Reduce one segment's raw text to plain prose words: mask the same
#' protected inline constructs the translation pipeline masks (code, math,
#' citations, xrefs, dfn/span-lang, day-NN cross-links) via .mask_inline(),
#' drop the resulting placeholder sentinels, then strip markup .mask_inline()
#' deliberately leaves alone because it is NOT translator-hidden there
#' (pandoc bracket-attribute blocks, stray HTML tags, HTML entities, and the
#' URL half of markdown links whose target isn't a day-NN cross-link) — for
#' THIS miner those bytes are never prose and would otherwise surface as fake
#' "terms" (e.g. an unmasked `&nbsp;` producing a bogus "nbsp" token).
.prose_plain_text <- function(text) {
  masked <- .mask_inline(text)$masked
  out <- gsub(paste0(.PH_OPEN, "PH[0-9]+", .PH_CLOSE), " ", masked, perl = TRUE)
  out <- gsub("\\[([^\\]]*)\\]\\([^)]*\\)", "\\1", out, perl = TRUE)
  out <- gsub("\\{[^}]*\\}", " ", out, perl = TRUE)
  out <- gsub("<[^>]*>", " ", out, perl = TRUE)
  out <- gsub("&[A-Za-z]+;", " ", out, perl = TRUE)
  out
}

#' Tokenise already-cleaned plain text (see .prose_plain_text()) into
#' case-preserved word tokens. Hyphens are treated as separators (so
#' "common-cause" and "common cause" tokenise identically), matching the
#' same choice made in .norm_term(). Split out from .tokenize_prose() so
#' discover_candidates() can reuse one .prose_plain_text() call for both
#' tokenising AND building the context snippet, instead of masking the same
#' segment text twice.
.tokenize_plain <- function(plain) {
  m <- gregexpr("[A-Za-z][A-Za-z']*", plain, perl = TRUE)
  regmatches(plain, m)[[1]]
}

#' Tokenise a segment's raw text directly (cleans then tokenises in one
#' call). A thin convenience wrapper over .prose_plain_text() +
#' .tokenize_plain() for callers that only need the tokens.
.tokenize_prose <- function(text) {
  .tokenize_plain(.prose_plain_text(text))
}

#' All contiguous n-grams of a token vector, as space-joined strings.
.ngrams <- function(tokens, n) {
  L <- length(tokens)
  if (L < n) return(character(0))
  vapply(seq_len(L - n + 1L), function(i) paste(tokens[i:(i + n - 1L)], collapse = " "), character(1))
}

.is_capitalised <- function(word) grepl("^[A-Z].", word, perl = TRUE)

#' Maximal capitalised-phrase runs of 4+ tokens: sequences starting and
#' ending on a capitalised token, allowing single interior connector words
#' (see .CONNECTOR_WORDS) only when they are immediately followed by another
#' capitalised token (so a run never ends on a dangling connector).
#'
#' Runs of length 2-3 are deliberately NOT emitted here even though they are
#' "capitalised phrases" too: an identically-positioned window is already
#' produced by .ngrams(toks, 2)/.ngrams(toks, 3), so including them here
#' would count the SAME occurrence twice (once per detection strategy) and
#' inflate frequency. Capitalised-run detection's only genuinely new
#' contribution beyond fixed-width n-grams is spans n-grams can't reach —
#' i.e. length >= 4 (e.g. "System of Profound Knowledge").
.cap_phrases <- function(tokens, max_len = 6L) {
  n <- length(tokens)
  out <- character(0)
  i <- 1L
  while (i <= n) {
    if (.is_capitalised(tokens[i])) {
      j <- i
      last_cap <- i
      while (j < n) {
        nxt <- tokens[j + 1L]
        if (.is_capitalised(nxt)) {
          j <- j + 1L
          last_cap <- j
        } else if (tolower(nxt) %in% .CONNECTOR_WORDS && (j + 1L) < n && .is_capitalised(tokens[j + 2L])) {
          j <- j + 1L
        } else {
          break
        }
      }
      j <- last_cap
      len <- j - i + 1L
      # A run longer than max_len is skipped WHOLESALE, not truncated to a
      # max_len-length sub-phrase: verified against the real corpus, runs
      # this long are almost always bibliography citations ("Author Title
      # Publisher City"), weekday lists, or heading concatenations — never
      # genuine glossary candidates — so a truncated prefix would just be a
      # misleading fragment rather than a useful one.
      if (len >= 4L && len <= max_len) {
        out <- c(out, paste(tokens[i:j], collapse = " "))
      }
      i <- j + 1L
    } else {
      i <- i + 1L
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Public entry point.
# ---------------------------------------------------------------------------

#' Pick the most frequent original-case surface form among a key's
#' occurrences, rather than whichever casing happened to occur first in
#' corpus order (e.g. "control chart" beating "Control Chart" purely because
#' a lowercase mid-sentence mention was scanned before a capitalised one).
#' Ties break alphabetically via table()'s sorted names + which.max's
#' first-max — deterministic either way.
.mode_display <- function(x) {
  tab <- table(x)
  names(tab)[which.max(tab)]
}

.EMPTY_CANDIDATES <- data.frame(
  term_en = character(0), fr_rendering = character(0), source = character(0),
  frequency = integer(0), occurrence_types = character(0), contexts = character(0),
  decision_needed = logical(0), stringsAsFactors = FALSE
)

#' Discover recurring un-seeded candidate glossary terms.
#'
#' @param segments data.frame as returned by glossary_segments() (columns
#'   text, kind, occurrence_type, file, start_line).
#' @param seed data.frame as read from glossary/seed-terms.csv (columns
#'   term_en, fr_rendering, source, aliases, decision_needed); `aliases` is
#'   `|`-delimited.
#' @param min_freq minimum occurrence count for a candidate to be returned.
#' @return data.frame with columns term_en, fr_rendering (NA), source (NA),
#'   frequency, occurrence_types (`|`-joined "prose"/"ui"), contexts (up to 3
#'   `|`-joined sample snippets), decision_needed (TRUE) — sorted by
#'   frequency desc, then term_en asc, for determinism.
discover_candidates <- function(segments, seed, min_freq = 5L) {
  excluded <- .seed_exclusion_set(seed)

  prose <- segments[segments$kind == "prose", , drop = FALSE]
  # Collect per-segment into list slots and flatten ONCE at the end. Growing
  # `keys`/`displays`/... via repeated c() inside this loop is O(n^2) in
  # allocations — profiling on the real corpus (~4,700 prose segments,
  # ~100k surviving n-gram occurrences) showed c() alone as >60% of self
  # time, so this is not a theoretical concern.
  key_parts <- vector("list", nrow(prose))
  display_parts <- vector("list", nrow(prose))
  otype_parts <- vector("list", nrow(prose))
  ctx_parts <- vector("list", nrow(prose))

  for (i in seq_len(nrow(prose))) {
    plain <- .prose_plain_text(prose$text[i])
    toks <- .tokenize_plain(plain)
    if (length(toks) < 2L) next
    cands <- c(.ngrams(toks, 2L), .ngrams(toks, 3L), .cap_phrases(toks))
    if (!length(cands)) next
    keep <- vapply(
      strsplit(cands, " ", fixed = TRUE),
      function(w) all(!tolower(w) %in% .STOPWORDS) && all(nchar(w) >= 2L),
      logical(1)
    )
    cands <- cands[keep]
    if (!length(cands)) next
    ctx <- substr(trimws(gsub("\\s+", " ", plain, perl = TRUE)), 1, 160)
    key_parts[[i]] <- tolower(cands)
    display_parts[[i]] <- cands
    otype_parts[[i]] <- rep("prose", length(cands))
    ctx_parts[[i]] <- rep(ctx, length(cands))
  }

  keys <- unlist(key_parts, use.names = FALSE)
  displays <- unlist(display_parts, use.names = FALSE)
  otypes <- unlist(otype_parts, use.names = FALSE)
  ctxs <- unlist(ctx_parts, use.names = FALSE)

  ui <- segments[segments$kind %in% c("ui-string", "aria-label"), , drop = FALSE]
  if (nrow(ui)) {
    ui_text <- trimws(ui$text)
    keys <- c(keys, tolower(ui_text))
    displays <- c(displays, ui_text)
    otypes <- c(otypes, rep("ui", nrow(ui)))
    ctxs <- c(ctxs, ui$file)
  }

  if (!length(keys)) return(.EMPTY_CANDIDATES)
  keys <- .norm_term(keys)

  # Group occurrence indices by normalised key in one pass (hashed split(),
  # not a per-key scan) — this function runs over hundreds of thousands of
  # n-gram occurrences, so an O(n * unique keys) scan is not viable.
  idx_by_key <- split(seq_along(keys), keys)
  idx_by_key <- idx_by_key[!names(idx_by_key) %in% excluded]
  idx_by_key <- idx_by_key[lengths(idx_by_key) >= min_freq]
  if (!length(idx_by_key)) return(.EMPTY_CANDIDATES)

  rows <- vector("list", length(idx_by_key))
  for (k in seq_along(idx_by_key)) {
    idx <- idx_by_key[[k]]
    samples <- unique(ctxs[idx])
    samples <- head(samples[nzchar(samples)], 3L)
    # NA, not "", when no non-empty snippet survives — matches the
    # NA_character_ convention used by fr_rendering/source below, so a
    # downstream caller can test is.na() uniformly across every "not filled
    # in" column instead of "" for this one and NA for the others.
    contexts <- if (length(samples)) paste(samples, collapse = " | ") else NA_character_
    rows[[k]] <- data.frame(
      term_en = .mode_display(displays[idx]),
      fr_rendering = NA_character_,
      source = NA_character_,
      frequency = length(idx),
      occurrence_types = paste(sort(unique(otypes[idx])), collapse = "|"),
      contexts = contexts,
      decision_needed = TRUE,
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  out <- out[order(-out$frequency, out$term_en), ]
  rownames(out) <- NULL
  out
}
