# glossary-corpus.R
#
# Glossary corpus loader (issue #412).
#
# A PURE-READ flattener that turns the three extraction corpora (.qmd prose +
# YAML values, .R helper strings, .js UI/ARIA strings) into ONE tidy base
# data.frame, one row per extracted segment. This is the input surface a
# downstream glossary/term pass (sibling issues) consumes — but THIS module does
# NO term logic, NO matching, and NO French. It only discovers, extracts, and
# flattens.
#
# Determinism: the frame is reproducible for a given input tree. Corpora are
# iterated in a fixed order (qmd, then r, then js); within each corpus, files are
# enumerated by the existing *_corpus() helpers (which already sort), and
# segments are kept in extraction order. Same tree in -> identical() frame out.
#
# Dependencies: base R + yaml + jsonlite (transitively, via prose-extract.R,
# also digest). NO new packages — the result is a base data.frame with
# stringsAsFactors = FALSE, deliberately avoiding dplyr/tibble.

# Source the extractor (which itself sources code-string-extract.R). Resolve the
# path relative to THIS file so the loader works from any working directory,
# mirroring prose-extract.R's own self-locating logic.
.glossary_corpus_dir <- (function() {
  # (1) Rscript: the script path is in commandArgs as --file=.
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) {
    d <- dirname(normalizePath(sub("^--file=", "", m[1])))
    if (file.exists(file.path(d, "prose-extract.R"))) return(d)
  }
  # (2) source(): the sourced file path lives in the call frame's `ofile`.
  for (fr in rev(sys.frames())) {
    of <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("glossary-corpus[.]R$", of)) {
      d <- dirname(normalizePath(of))
      if (file.exists(file.path(d, "prose-extract.R"))) return(d)
    }
  }
  # (3) Fallback: search upward from the working directory.
  d <- normalizePath(getwd())
  repeat {
    cand <- file.path(d, "R", "translation")
    if (file.exists(file.path(cand, "prose-extract.R"))) return(cand)
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  file.path("R", "translation")
})()

source(file.path(.glossary_corpus_dir, "prose-extract.R"))

# ---------------------------------------------------------------------------
# kind/context -> occurrence_type mapping.
# ---------------------------------------------------------------------------
# The extractor emits these `kind` values across the three corpora:
#   * "yaml_value"  : front-matter scalar (title/subtitle/description) — .qmd
#   * "prose"       : whole-line prose blocks                          — .qmd
#   * "r-string"    : user-facing string literal in R code             — .qmd / .R
#   * "ui-string"   : interface text (button/placeholder/OJS labels)   — .qmd / .js
#   * "aria-label"  : accessibility label attribute values             — .qmd / .js
#
# The issue's column spec lists the normalised kind "yaml" (not "yaml_value").
# We normalise that ONE name; every other kind passes through unchanged.
#
# occurrence_type is a coarse three-way bucket the downstream pass keys off:
#   prose|yaml -> "prose"   (translatable body / front-matter prose)
#   r-string   -> "r"       (code-embedded label)
#   ui-string|aria-label -> "ui"  (interface / accessibility text)
#
# NOTE on `context`: the segment address MAY carry an `address$context` hint
# ("ojs-input" / "html-attr" / "js") for sub-line UI/ARIA segments. It is NOT
# needed to derive occurrence_type here, because the `kind` already partitions
# the space unambiguously (ui-string/aria-label are the only kinds that ever
# carry a context, and both map to "ui" regardless of which surface produced
# them). The mapping therefore keys solely off `kind`; `context` is accepted as
# an argument only to keep the helper's contract explicit and future-proof, and
# is asserted-but-unused so a reviewer can see the deliberate choice.

#' Normalise a raw extractor `kind` to the issue's `kind` column vocabulary.
#' Only "yaml_value" -> "yaml"; all other kinds pass through unchanged.
.normalise_kind <- function(kind) {
  ifelse(kind == "yaml_value", "yaml", kind)
}

#' Map a (normalised-or-raw) `kind` plus optional `context` to occurrence_type.
#' Accepts either the raw "yaml_value" or the normalised "yaml" so the helper is
#' robust regardless of call order. `context` is intentionally unused (see the
#' block comment above) but kept in the signature to document the design choice.
#' Vectorised over `kind`.
.occurrence_type <- function(kind, context = NULL) {
  k <- .normalise_kind(kind)
  out <- ifelse(k %in% c("prose", "yaml"), "prose",
         ifelse(k == "r-string", "r",
         ifelse(k %in% c("ui-string", "aria-label"), "ui",
                NA_character_)))
  if (anyNA(out)) {
    stop("unmapped segment kind(s): ",
         paste(unique(k[is.na(out)]), collapse = ", "))
  }
  out
}

# ---------------------------------------------------------------------------
# Segment -> one-row frame.
# ---------------------------------------------------------------------------
# Each extractor segment is a list with jsonlite::unbox()'d scalars. Unwrap to
# plain scalars (as.character / as.integer strip the unbox class) for the frame.

#' Flatten a single extraction's segments into a one-row-per-segment data.frame.
#' Returns a zero-row frame (with the right columns) when there are no segments.
.segments_to_rows <- function(segments) {
  n <- length(segments)
  empty <- data.frame(
    text = character(0),
    kind = character(0),
    occurrence_type = character(0),
    file = character(0),
    start_line = integer(0),
    stringsAsFactors = FALSE
  )
  if (n == 0L) return(empty)

  text       <- character(n)
  raw_kind   <- character(n)
  file       <- character(n)
  start_line <- integer(n)

  for (i in seq_len(n)) {
    s <- segments[[i]]
    a <- s$address
    text[i]       <- as.character(s$text)
    raw_kind[i]   <- as.character(a$kind)
    file[i]       <- as.character(a$file)
    start_line[i] <- as.integer(a$start_line)
  }

  # occurrence_type is a pure function of kind (see .occurrence_type); the
  # segment's address$context is intentionally not threaded through here.
  data.frame(
    text = text,
    kind = .normalise_kind(raw_kind),
    occurrence_type = .occurrence_type(raw_kind),
    file = file,
    start_line = start_line,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Public entry point.
# ---------------------------------------------------------------------------

#' Build the flattened glossary segment frame across all three corpora.
#'
#' Discovers and extracts every translatable segment from the .qmd, .R and .js
#' corpora and returns ONE tidy base data.frame, one row per segment, with
#' exactly these columns: text, kind, occurrence_type, file, start_line.
#'
#' Row order is deterministic: corpora in (qmd, r, js) order; files in each
#' corpus in the order the *_corpus() helper returns (already sorted); segments
#' in extraction order within each file.
#'
#' @param root repo root to scan (default ".").
#' @return base data.frame (stringsAsFactors = FALSE).
glossary_segments <- function(root = ".") {
  rows <- list()

  add_extraction <- function(extractions) {
    for (ex in extractions) {
      rows[[length(rows) + 1L]] <<- .segments_to_rows(ex$segments)
    }
  }

  # .qmd corpus
  add_extraction(lapply(qmd_corpus(root), function(f) extract_qmd(f, rel_path = f)))
  # .R corpus
  add_extraction(lapply(r_corpus(root), function(f) extract_r_file(f, rel_path = f)))
  # .js corpus
  add_extraction(lapply(js_corpus(root), function(f) extract_js_file(f, rel_path = f)))

  if (length(rows) == 0L) {
    return(.segments_to_rows(list()))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
