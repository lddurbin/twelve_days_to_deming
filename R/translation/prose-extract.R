# prose-extract.R
#
# Foundational tooling for the French-translation pipeline (issue #323).
#
# A NON-DESTRUCTIVE prose extractor + reinjector for Quarto `.qmd` files.
#
# Design contract
# ---------------
# A `.qmd` file is treated as an ordered sequence of LINES. Each line is
# classified as either STRUCTURAL (preserved verbatim, never translated) or
# part of a TRANSLATABLE PROSE block. Contiguous translatable lines are grouped
# into prose *segments*, each carrying:
#   * a stable `id`            (content-derived hash, order-tagged for stability)
#   * a structural `address`   (region kind + start/end line, byte offsets)
#   * the raw `text`           (exact source bytes of the segment)
#   * a `masked` form + `placeholders` map, in which every inline construct that
#     must NOT be exposed to a translator (inline code, cross-refs, citations,
#     shortcodes, maths, <span lang>, <dfn id>, #sec-pageN anchors, relative
#     ../day-NN/*.qmd#sec-pageN links) is replaced by an opaque token. The mask
#     is what a translator/MT engine consumes; the raw text is what the identity
#     round-trip reinjects.
#
# What is STRUCTURAL (never emitted as translatable prose):
#   * YAML front matter, except the VALUES of translatable keys
#     (title / subtitle / description) which become their own prose segments.
#   * Fenced code blocks (``` / ```{...} / ~~~), bodies AND fences.
#   * Lines that are purely an HTML structural tag (<div ...>, </div>,
#     <details>, <summary> alone, <button ...>, </button>, <figure>, <table> …).
#   * Fenced-div fences (::: / :::: with attributes).
#   * Bare span/anchor-only lines such as `[]{#sec-page7}`.
#   * Blank lines, separators, HTML comments.
#
# Reinjection is the exact inverse: a translated value is provided per segment id;
# every structural region is reproduced byte-for-byte from the original. The
# IDENTITY round-trip (reinject each segment's own raw text) therefore yields a
# byte-identical file by construction. That is the hard correctness gate.
#
# Dependencies: base R + yaml + jsonlite + digest. (stringr/purrr deliberately
# avoided so the tool runs under a minimal renv subset.)

suppressPackageStartupMessages({
  library(yaml)
  library(jsonlite)
  library(digest)
})

# Sub-line code-string extraction primitives (issue #324) live in a sibling
# module so a follow-up (#325) can reuse them for OJS/JS. Sourced here because
# .mask_inline()/.ph_token() defined below are shared, and extract_qmd() needs
# the scanner. Resolve the path relative to THIS file so callers in any CWD work.
.prose_extract_dir <- (function() {
  # (1) Rscript: the script path is in commandArgs as --file=.
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) {
    d <- dirname(normalizePath(sub("^--file=", "", m[1])))
    if (file.exists(file.path(d, "code-string-extract.R"))) return(d)
  }
  # (2) source(): R stashes the sourced file path in the `source` call frame's
  # `ofile` variable. Walk the frames to find our own directory so the sibling
  # module resolves regardless of the caller's working directory.
  for (fr in rev(sys.frames())) {
    of <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("prose-extract[.]R$", of)) {
      d <- dirname(normalizePath(of))
      if (file.exists(file.path(d, "code-string-extract.R"))) return(d)
    }
  }
  # (3) Fallback: search upward from the working directory for the module.
  d <- normalizePath(getwd())
  repeat {
    cand <- file.path(d, "R", "translation")
    if (file.exists(file.path(cand, "code-string-extract.R"))) return(cand)
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  file.path("R", "translation")
})()

# ---------------------------------------------------------------------------
# Low-level IO: read a file as its exact byte string, and split into lines
# while remembering whether the final line had a trailing newline.
# ---------------------------------------------------------------------------

#' Read a file's full content as a single UTF-8 string (exact bytes).
.read_raw_text <- function(path) {
  sz <- file.info(path)$size
  if (is.na(sz)) stop("cannot stat file: ", path)
  raw <- readBin(path, "raw", n = sz)
  txt <- rawToChar(raw)
  Encoding(txt) <- "UTF-8"
  txt
}

#' Split content into physical lines, recording the trailing-newline flag.
#' Returns list(lines = character vector WITHOUT newline chars,
#'              trailing_newline = logical).
#' Note: the corpus is LF-only (verified); we assume "\n" line endings.
.split_lines <- function(content) {
  if (identical(content, "")) {
    return(list(lines = character(0), trailing_newline = FALSE))
  }
  trailing <- grepl("\n$", content)
  # strsplit drops a trailing empty field, so a trailing "\n" yields the
  # correct line set; we recombine with the flag on write.
  lines <- strsplit(content, "\n", fixed = TRUE)[[1]]
  # If content ended without "\n", strsplit still gives the last partial line.
  list(lines = lines, trailing_newline = trailing)
}

#' Recombine lines into a byte string, honouring the trailing-newline flag.
.join_lines <- function(lines, trailing_newline) {
  if (length(lines) == 0) return("")
  body <- paste(lines, collapse = "\n")
  if (trailing_newline) paste0(body, "\n") else body
}

# ---------------------------------------------------------------------------
# Line classification
# ---------------------------------------------------------------------------

# Translatable YAML keys: only the VALUES of these keys are prose.
TRANSLATABLE_YAML_KEYS <- c("title", "subtitle", "description")

# A line is a fence opener/closer for fenced CODE if it starts (after optional
# indentation) with ``` or ~~~ (3+). Quarto code chunks use ```{...}; plain
# fenced code uses ```. We treat the whole fenced region as structural.
.is_code_fence <- function(line) {
  grepl("^[ \\t]*(`{3,}|~{3,})", line, perl = TRUE)
}

# Fenced-div fences: ::: or :::: optionally followed by {attrs} or a class word.
# These are pandoc structural divs (Quarto callouts, columns, etc.).
.is_div_fence <- function(line) {
  grepl("^[ \\t]*:{3,}", line, perl = TRUE)
}

# A line that is ONLY HTML structural markup (open or close tag(s)), with no
# prose text outside the tags. Examples:
#   <div class="thought" role="note">
#   </div>
#   <details>
#   <summary>Describe this chart</summary>   <- has text, but it is a LABEL …
#   <button ...>Click...</button>
# We keep block-level structural tags structural. <summary>/<button> carry
# translatable label text, so they are handled as prose; their wrapper tags are
# masked (see html_label_tag) leaving only the inner label on the translator
# surface. Block container tags on their own line are structural.
.HTML_BLOCK_TAGS <- c("div", "details", "figure", "table", "thead", "tbody",
                      "tr", "td", "th", "section", "article", "aside",
                      "nav", "header", "footer", "ul", "ol", "blockquote")

#' TRUE if the line consists solely of one or more block-level HTML tags
#' (open/close), possibly with attributes, and nothing else but whitespace.
.is_html_structural <- function(line) {
  s <- trimws(line)
  if (!nzchar(s)) return(FALSE)
  if (!startsWith(s, "<")) return(FALSE)
  tagset <- paste(.HTML_BLOCK_TAGS, collapse = "|")
  # one-or-more whole tags, each open <tag ...> or close </tag>, nothing between
  one <- sprintf("</?(?:%s)\\b[^>]*>", tagset)
  pat <- sprintf("^(?:%s)+$", one)
  grepl(pat, s, perl = TRUE, ignore.case = TRUE)
}

# Bare anchor-only line: `[]{#sec-pageN}` or `[]{#anything}` possibly with
# surrounding whitespace. Structural (an inter-day link target).
.is_bare_anchor <- function(line) {
  grepl("^[ \\t]*\\[\\]\\{#[^}]+\\}[ \\t]*$", line, perl = TRUE)
}

# HTML comment line(s). The `-->$` clause is deliberate: it catches the CLOSING
# line of a multi-line comment block (which opens with `<!--` on an earlier
# line), so both ends break the surrounding prose block at the call site.
.is_comment_line <- function(line) {
  s <- trimws(line)
  grepl("^<!--", s) || grepl("-->$", s)
}

# A blank line.
.is_blank <- function(line) !nzchar(trimws(line))

# ---------------------------------------------------------------------------
# Inline masking: replace protected inline constructs with opaque placeholders.
# Used to build the translator-facing `masked` text and `placeholders` map.
# Order matters: maths/code first (they may contain anything), then structured
# tokens, then links/spans/anchors.
# ---------------------------------------------------------------------------

# Placeholder sentinels are wrapped in Unicode Private Use Area delimiters
# (U+E000 / U+E001) so a token can never collide with prose characters.
.PH_OPEN  <- "\uE000"
.PH_CLOSE <- "\uE001"
.ph_token <- function(n) sprintf("%sPH%d%s", .PH_OPEN, n, .PH_CLOSE)

# Now that the shared placeholder scheme exists, load the code-string module,
# which builds on .ph_token/.PH_OPEN/.PH_CLOSE for masking R-string escapes.
source(file.path(.prose_extract_dir, "code-string-extract.R"))

# Each entry: name + PCRE pattern, applied left-to-right; matches become
# sentinel tokens (see .ph_token).
.PROTECT_PATTERNS <- list(
  # Quarto/pandoc shortcodes: {{< ... >}}
  shortcode      = "\\{\\{<.*?>\\}\\}",
  # Display maths $$ ... $$  (non-greedy, may span — but we mask per line)
  math_display   = "\\$\\$.+?\\$\\$",
  # Inline maths $ ... $  (avoid $$, avoid currency: require non-space after $)
  math_inline    = "(?<!\\$)\\$(?!\\$)[^$\\n]+?\\$(?!\\$)",
  # Inline code `...` (1+ backticks)
  inline_code    = "(`+)[^`]*?\\1",
  # Citations [@key], [@key1; @key2], including locators
  citation       = "\\[(?:[^\\]]*?@[^\\]]+?)\\]",
  # Bare cross-references / cite keys @sec-... @fig-... @tbl-... @key
  xref           = "@[A-Za-z][A-Za-z0-9_:.-]*",
  # <span lang="..">inner</span>  (whole element, inner kept inside placeholder)
  span_lang      = "<span\\s+lang=[\"']?[a-z-]+[\"']?\\s*>.*?</span>",
  # <dfn id=\"..\">inner</dfn>  (whole element)
  dfn            = "<dfn\\s+id=[\"'][^\"']+[\"']\\s*>.*?</dfn>",
  # <summary>/<button> WRAPPER tags only (open or close). Unlike span_lang/dfn,
  # the inner text of these is a translatable label, so we mask just the tags
  # and leave the label on the translator surface. This stops a translator from
  # ever seeing — and possibly reordering or translating — the raw HTML, which
  # would break reinjection.
  html_label_tag = "</?(?:summary|button)\\b[^>]*>",
  # Relative inter-day links: [text](../day-NN/file.qmd#sec-pageN) and the
  # ../days/day-NN/ form. Mask the whole link (URL is structural; text is
  # arguably translatable but conservatively preserved to honour #323's
  # "relative ../day-NN/*.qmd#sec-pageN link forms must survive byte-identical").
  rellink_day    = "\\[[^\\]]*\\]\\(\\.\\.\\/(?:days\\/)?day-\\d{2}\\/[^)]*?#sec-page\\d+\\)",
  # Inline span/anchor attribute attachments: text wrapped as []{#sec-pageN}
  # or [text]{.class ...} inline (fenced-div attribute on a span)
  inline_attr    = "\\[[^\\]]*\\]\\{#sec-page\\d+\\}",
  # Any remaining #sec-pageN bare token (defensive)
  sec_anchor     = "#sec-page\\d+"
)

#' Mask protected inline constructs in a piece of text.
#' Returns list(masked = <string with sentinels>, placeholders = named list).
#'
#' @param yaml_value when TRUE, the text is a single YAML `key: value` line; the
#'        `key: ` prefix and any wrapping quotes are masked first so the masked
#'        form is the bare value a translator should edit. The structural prefix
#'        and quotes are restored on reinjection from the raw text.
.mask_inline <- function(text, yaml_value = FALSE) {
  placeholders <- list()
  counter <- 0L
  masked <- text

  if (yaml_value) {
    # Mask "key: " prefix (incl. an optional opening quote) and a closing quote.
    m <- regexec("^([A-Za-z_][A-Za-z0-9_.-]*:[ \t]+[\"']?)(.*?)([\"']?)[ \t]*$",
                 masked, perl = TRUE)
    g <- regmatches(masked, m)[[1]]
    if (length(g) == 4) {
      prefix <- g[2]; val <- g[3]; suffix <- g[4]
      counter <- counter + 1L
      ptok <- .ph_token(counter)
      placeholders[[ptok]] <- list(kind = "yaml_prefix", value = prefix)
      if (nzchar(suffix)) {
        counter <- counter + 1L
        stok <- .ph_token(counter)
        placeholders[[stok]] <- list(kind = "yaml_suffix", value = suffix)
        masked <- paste0(ptok, val, stok)
      } else {
        masked <- paste0(ptok, val)
      }
    }
  }

  for (nm in names(.PROTECT_PATTERNS)) {
    pat <- .PROTECT_PATTERNS[[nm]]
    repeat {
      m <- regexpr(pat, masked, perl = TRUE)
      if (m[1] == -1L) break
      matched <- regmatches(masked, m)
      counter <- counter + 1L
      # Use the shared PUA-sentinel helper (same scheme as the YAML tokens
      # above) so the token can never collide with a literal digit in the
      # prose during the fixed-string substitution in .unmask_inline.
      token <- .ph_token(counter)
      placeholders[[token]] <- list(kind = nm, value = matched)
      # replace only the first occurrence
      masked <- sub(pat, token, masked, perl = TRUE)
    }
  }
  list(masked = masked, placeholders = placeholders)
}

#' Inverse of .mask_inline: expand placeholder tokens back to their original
#' inline constructs. Given a (possibly translated) masked string and the
#' placeholders map, restores every protected token verbatim. Expanding the
#' UNCHANGED masked string yields exactly the original raw text — this is the
#' lossless property the translation reinjection path relies on.
.unmask_inline <- function(masked, placeholders) {
  out <- masked
  # Replace longest token numbers last is irrelevant since tokens are delimited;
  # iterate over names and substitute each delimited token with its value.
  for (tok in names(placeholders)) {
    val <- placeholders[[tok]]$value
    # `tok` already includes the PUA delimiters; fixed substitution.
    out <- gsub(tok, val, out, fixed = TRUE)
  }
  out
}

# ---------------------------------------------------------------------------
# Stable segment IDs.
# ---------------------------------------------------------------------------
# An id must be stable across runs and reasonably stable across edits to OTHER
# segments. We derive it from: file-relative path + a short content hash of the
# raw segment text + the segment's ordinal within its region kind. The ordinal
# disambiguates identical prose (e.g. repeated headings) without coupling to
# absolute line numbers of unrelated edits.

.segment_id <- function(rel_path, region_kind, raw_text, ordinal) {
  h <- substr(digest::digest(raw_text, algo = "xxhash64"), 1, 10)
  sprintf("%s::%s#%d::%s", rel_path, region_kind, ordinal, h)
}

# ---------------------------------------------------------------------------
# Sub-line segment record builder (issue #324).
# ---------------------------------------------------------------------------
# A SUB-LINE segment is a translatable string LITERAL living inside one line of
# code (e.g. the "A1" inside `ggtitle("A1")`). Unlike a prose segment, its
# address carries CHARACTER OFFSETS (start_col/end_col, 1-based, INNER span
# between the quotes) so reinjection can splice within the line and leave the
# rest of that line byte-identical. start_line == end_line by construction.
#
# The masked surface protects R escapes / format specifiers (via
# .mask_code_string) so a translator never breaks `\n`, `%s`, `{x}` etc. The
# raw `text` is the exact inner bytes, which the identity round-trip reinjects.
#
# `rel_path`, `kind` and an ordinal counter come from the caller; `inner` is the
# literal's inner content and `start_col`/`end_col` its offsets on `line_no`.
.build_subline_segment <- function(rel_path, kind, ordinal,
                                   line_no, start_col, end_col, inner) {
  mk <- .mask_code_string(inner)
  list(
    id = .segment_id(rel_path, kind, inner, ordinal),
    address = list(
      file = rel_path,
      kind = jsonlite::unbox(kind),
      start_line = jsonlite::unbox(line_no),
      end_line = jsonlite::unbox(line_no),
      # Byte/char offsets (the design contract anticipated "byte offsets"; the
      # corpus is ASCII at these literal positions, and substr() is character-
      # based, so 1-based char offsets are the stable addressing unit).
      start_col = jsonlite::unbox(start_col),
      end_col = jsonlite::unbox(end_col)
    ),
    text = jsonlite::unbox(inner),
    masked = jsonlite::unbox(mk$masked),
    placeholders = mk$placeholders
  )
}

# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------

#' Extract translatable prose segments from one `.qmd` file.
#'
#' @param path absolute or repo-relative path to a .qmd file
#' @param rel_path path stored in the segment id / address (defaults to `path`)
#' @return list with:
#'   file               : rel_path
#'   trailing_newline   : logical
#'   n_lines            : integer
#'   segments           : list of segment records
extract_qmd <- function(path, rel_path = path) {
  content <- .read_raw_text(path)
  sl <- .split_lines(content)
  lines <- sl$lines
  n <- length(lines)

  segments <- list()
  ord <- new.env(parent = emptyenv())  # per-region-kind ordinal counters

  next_ord <- function(kind) {
    cur <- if (exists(kind, envir = ord, inherits = FALSE)) get(kind, envir = ord) else 0L
    cur <- cur + 1L
    assign(kind, cur, envir = ord)
    cur
  }

  add_segment <- function(kind, start_line, end_line) {
    raw <- paste(lines[start_line:end_line], collapse = "\n")
    o <- next_ord(kind)
    mk <- .mask_inline(raw, yaml_value = identical(kind, "yaml_value"))
    seg <- list(
      id = .segment_id(rel_path, kind, raw, o),
      address = list(
        file = rel_path,
        kind = jsonlite::unbox(kind),
        start_line = jsonlite::unbox(start_line),
        end_line = jsonlite::unbox(end_line)
      ),
      text = jsonlite::unbox(raw),
      masked = jsonlite::unbox(mk$masked),
      placeholders = mk$placeholders
    )
    segments[[length(segments) + 1L]] <<- seg
  }

  # ---- Phase 1: YAML front matter -----------------------------------------
  i <- 1L
  yaml_end <- 0L
  if (n >= 1 && grepl("^---[ \t]*$", lines[1])) {
    closers <- which(grepl("^(---|\\.\\.\\.)[ \t]*$", lines))
    closers <- closers[closers > 1]
    if (length(closers) >= 1) {
      yaml_end <- closers[1]
      # Extract translatable scalar values within the front matter.
      # We only handle simple `key: value` and quoted forms on one line, which
      # covers the entire corpus (verified: no block scalars). Each such value
      # becomes a prose segment addressed by its single line.
      # seq_len (not 2:(yaml_end-1)) so empty front matter (yaml_end == 2)
      # yields an empty range, not R's descending c(2, 1).
      for (j in seq_len(yaml_end - 2L) + 1L) {
        ln <- lines[j]
        m <- regexec("^([A-Za-z_][A-Za-z0-9_.-]*):[ \t]+(.*\\S)[ \t]*$", ln, perl = TRUE)
        g <- regmatches(ln, m)[[1]]
        if (length(g) == 3 && g[2] %in% TRANSLATABLE_YAML_KEYS) {
          # The VALUE may be quoted; we keep the raw value (with quotes) as the
          # segment text so reinjection is byte-exact. A translator works on the
          # masked form; quote characters are preserved as part of the line.
          add_segment("yaml_value", j, j)
        }
      }
    }
  }
  i <- if (yaml_end > 0L) yaml_end + 1L else 1L

  # ---- Phase 2: body ------------------------------------------------------
  in_code <- FALSE
  code_is_r <- FALSE  # is the currently-open fenced chunk an ```{r} chunk?
  code_fctx <- .func_param_context_init()  # cross-line function-param tracker
  code_fence_re <- NULL
  block_start <- 0L  # start of an open prose block, 0 if none

  flush_block <- function(upto) {
    if (block_start > 0L && upto >= block_start) {
      add_segment("prose", block_start, upto)
    }
    block_start <<- 0L
  }

  while (i <= n) {
    ln <- lines[i]

    # Inside a fenced code block: preserve until the matching closing fence.
    if (in_code) {
      if (.is_code_fence(ln)) {
        in_code <- FALSE
      } else if (code_is_r) {
        # R chunk BODY line: scan for whitelisted user-facing string literals and
        # emit each as a sub-line `r-string` segment. Code logic is never altered
        # — only the inner bytes of a label literal become translatable.
        upd <- .update_func_param_context(ln, code_fctx)
        code_fctx <- upd$state
        for (lit in .scan_code_line_literals(ln, in_func_params = upd$line_in_params)) {
          o <- next_ord("r-string")
          seg <- .build_subline_segment(
            rel_path, "r-string", o, i,
            lit$inner_start, lit$inner_end, lit$inner
          )
          segments[[length(segments) + 1L]] <- seg
        }
      }
      i <- i + 1L
      next
    }

    # Code fence opener (closes any open prose block first). Detect whether this
    # is an R chunk (```{r ...} or ```{r}) so only R bodies are string-scanned;
    # other languages (ojs, python, mermaid, dot, plain ```) are left untouched
    # here — #325 will add OJS/JS handling via the same machinery.
    if (.is_code_fence(ln)) {
      flush_block(i - 1L)
      in_code <- TRUE
      code_is_r <- grepl("^[ \t]*`{3,}\\{r[ ,}]", ln, perl = TRUE) ||
                   grepl("^[ \t]*`{3,}\\{r\\}", ln, perl = TRUE)
      code_fctx <- .func_param_context_init()  # fresh paren context per chunk
      i <- i + 1L
      next
    }

    # Structural lines break prose blocks and are preserved verbatim.
    if (.is_blank(ln) ||
        .is_div_fence(ln) ||
        .is_bare_anchor(ln) ||
        .is_comment_line(ln) ||
        .is_html_structural(ln)) {
      flush_block(i - 1L)
      i <- i + 1L
      next
    }

    # Otherwise: translatable prose. Start or extend the current block.
    if (block_start == 0L) block_start <- i
    i <- i + 1L
  }
  flush_block(n)

  list(
    file = rel_path,
    trailing_newline = sl$trailing_newline,
    n_lines = n,
    segments = segments
  )
}

# ---------------------------------------------------------------------------
# Reinjection (inverse step)
# ---------------------------------------------------------------------------

#' Reinject translated (or identical) segment text back into a source file.
#'
#' @param path        the ORIGINAL source file (provides all structural bytes)
#' @param extraction  the result of extract_qmd() for that file
#' @param replacements named character vector / list mapping segment id ->
#'                     replacement text. Missing ids fall back to the segment's
#'                     own original `text` (identity).
#' @param rel_path    path used when re-deriving (defaults to extraction$file)
#' @return the reconstructed file content as a single byte string.
reinject_qmd <- function(path, extraction, replacements = list(), rel_path = extraction$file) {
  content <- .read_raw_text(path)
  sl <- .split_lines(content)
  lines <- sl$lines

  segs <- extraction$segments

  # Segments come in two flavours:
  #   * WHOLE-LINE segments (prose, yaml_value): addressed by [start_line,
  #     end_line]; replacement may change the line COUNT.
  #   * SUB-LINE segments (r-string and, later, ojs/js-string): addressed by a
  #     character span start_col..end_col on a single line; replacement rewrites
  #     only that span, leaving the rest of the line byte-identical.
  # We apply SUB-LINE edits FIRST, on the ORIGINAL line numbering, because
  # whole-line splicing below can change line indices. Sub-line segments only
  # ever sit inside code chunks while whole-line segments sit outside them, so
  # the two never contend for the same line.
  is_subline <- function(s) !is.null(s$address$start_col)

  sub_segs <- Filter(is_subline, segs)
  if (length(sub_segs)) {
    recs <- lapply(sub_segs, function(s) {
      repl_inner <- if (!is.null(replacements[[s$id]])) replacements[[s$id]] else as.character(s$text)
      list(
        start_line = as.integer(s$address$start_line),
        start_col  = as.integer(s$address$start_col),
        end_col    = as.integer(s$address$end_col),
        repl       = repl_inner
      )
    })
    lines <- .reinject_subline_segments(lines, recs)
  }

  # Whole-line segments. Because they never overlap and are line-addressed, we
  # rebuild the line vector by splicing replacement lines into each segment's
  # [start_line, end_line] range. We process in DESCENDING line order so earlier
  # indices remain valid.
  line_segs <- Filter(function(s) !is_subline(s), segs)
  if (length(line_segs)) {
    starts <- vapply(line_segs, function(s) as.integer(s$address$start_line), integer(1))
    ord <- order(starts, decreasing = TRUE)
    for (k in ord) {
      s <- line_segs[[k]]
      id <- s$id
      repl <- if (!is.null(replacements[[id]])) replacements[[id]] else as.character(s$text)
      a <- as.integer(s$address$start_line)
      b <- as.integer(s$address$end_line)
      new_lines <- strsplit(repl, "\n", fixed = TRUE)[[1]]
      if (length(new_lines) == 0L) new_lines <- ""  # empty replacement -> one empty line
      before <- if (a > 1L) lines[1:(a - 1L)] else character(0)
      after  <- if (b < length(lines)) lines[(b + 1L):length(lines)] else character(0)
      lines <- c(before, new_lines, after)
    }
  }

  .join_lines(lines, sl$trailing_newline)
}

# ---------------------------------------------------------------------------
# Identity round-trip helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# `.R` helper-file extraction (issue #324).
# ---------------------------------------------------------------------------
# User-facing default labels (e.g. `x_title = "Shaft diameter"`,
# `lsl_label = "Lower\nSpecification\nLimit"`) and on-canvas annotate("text")
# labels also live in the R HELPER file `R/functions/main-functions.R`, not just
# in `.qmd` chunks. We extract them with the SAME whitelist + sub-line machinery.
# An `.R` file is pure code, so EVERY line is a code body line (no fences, no
# prose, no YAML). The result reuses the exact `r-string` segment shape so
# reinjection and the round-trip gate are identical to the .qmd path.

#' Extract `r-string` segments from a `.R` source file.
#' @return list(file, trailing_newline, n_lines, segments) — same shape as
#'         extract_qmd(), but segments are exclusively sub-line `r-string`.
extract_r_file <- function(path, rel_path = path) {
  content <- .read_raw_text(path)
  sl <- .split_lines(content)
  lines <- sl$lines
  n <- length(lines)

  segments <- list()
  ord <- 0L
  # Track function-parameter context across lines so helper DEFAULT-arg labels
  # (whose `function(` opener is several lines above the default) are eligible.
  fctx <- .func_param_context_init()
  for (i in seq_len(n)) {
    upd <- .update_func_param_context(lines[i], fctx)
    fctx <- upd$state
    for (lit in .scan_code_line_literals(lines[i], in_func_params = upd$line_in_params)) {
      ord <- ord + 1L
      seg <- .build_subline_segment(
        rel_path, "r-string", ord, i,
        lit$inner_start, lit$inner_end, lit$inner
      )
      segments[[length(segments) + 1L]] <- seg
    }
  }

  list(
    file = rel_path,
    trailing_newline = sl$trailing_newline,
    n_lines = n,
    segments = segments
  )
}

#' Round-trip one file: extract, reinject originals, compare bytes.
#' Dispatches on extension so `.R` files use extract_r_file() while everything
#' else uses extract_qmd(); reinjection/comparison are shared.
#' Returns list(ok, file, n_segments, [first_diff]).
roundtrip_file <- function(path, rel_path = path) {
  original <- .read_raw_text(path)
  ex <- if (grepl("[.][Rr]$", path)) extract_r_file(path, rel_path = rel_path)
        else extract_qmd(path, rel_path = rel_path)
  rebuilt <- reinject_qmd(path, ex, replacements = list(), rel_path = rel_path)
  ok <- identical(charToRaw(original), charToRaw(rebuilt))
  out <- list(ok = ok, file = rel_path, n_segments = length(ex$segments))
  if (!ok) {
    ob <- charToRaw(original); rb <- charToRaw(rebuilt)
    lim <- min(length(ob), length(rb))
    d <- if (lim == 0) 1L else which(ob[seq_len(lim)] != rb[seq_len(lim)])
    out$first_diff_byte <- if (length(d)) d[1] else (lim + 1L)
    out$orig_len <- length(ob); out$rebuilt_len <- length(rb)
  }
  out
}

#' Enumerate the .qmd corpus: content/** plus root-level *.qmd.
qmd_corpus <- function(root = ".") {
  body <- list.files(file.path(root, "content"), pattern = "[.]qmd$",
                     recursive = TRUE, full.names = TRUE)
  top <- list.files(root, pattern = "[.]qmd$", recursive = FALSE, full.names = TRUE)
  c(sort(body), sort(top))
}

#' Enumerate the `.R` helper corpus that carries user-facing default labels.
#' Scoped tightly to R/functions/ (where the chart/table helpers live). Other
#' `.R` trees (R/data/, R/translation/, the tooling itself) hold no translatable
#' user-facing strings — keeping the corpus narrow avoids false positives and
#' keeps the round-trip gate fast and meaningful.
r_corpus <- function(root = ".") {
  sort(list.files(file.path(root, "R", "functions"), pattern = "[.]R$",
                  recursive = TRUE, full.names = TRUE))
}
