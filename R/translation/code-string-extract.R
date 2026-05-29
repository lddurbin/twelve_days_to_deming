# code-string-extract.R
#
# User-facing string extraction from CODE chunks/files (issue #324).
#
# This module is SOURCED by prose-extract.R and provides the reusable
# primitives for pulling translatable string LITERALS out of code while
# leaving the surrounding code logic byte-identical. It is the sub-line
# (character-offset) counterpart of prose-extract.R's whole-line prose
# machinery.
#
# Why a separate module
# ---------------------
# A sibling issue (#325) will reuse this exact machinery for OJS chunks and a
# `.js` corpus. Everything here is therefore written GENERICALLY around two
# ideas, neither of which is R-specific:
#
#   1. ".scan_code_line_literals()" — given one physical line of code and a
#      WHITELIST of (function, argument-position) pairs, find every string
#      LITERAL sitting at a whitelisted position and return its character span
#      (offsets inside the quotes) plus its raw inner bytes. The caller decides
#      what segment kind to tag the result with (`r-string`, later `ojs-string`,
#      `js-string`, …). The literal scanner itself only understands quoting and
#      call syntax, not any particular language's semantics.
#
#   2. ".reinject_subline_segments()" — given the original line vector and a set
#      of SUB-LINE segments (each carrying start_line/start_col/end_col), splice
#      replacement text into each literal's span, leaving every other byte of
#      every line untouched. This generalises prose-extract.R's whole-line
#      splice to intra-line, and works for ANY sub-line segment kind.
#
# CRUCIAL DISCIPLINE — only USER-FACING literals are touched. We do NOT extract
# every string in the code. A false positive that rewrites a data key, a column
# name, a factor level, a hex colour, a file path or a theme element name would
# CORRUPT LOGIC and is far worse than a missed label (which a follow-up can add).
# We therefore extract ONLY at a tight whitelist of label-bearing positions; see
# .R_STRING_WHITELIST below. When in doubt, EXCLUDE.
#
# Dependencies: base R only (the digest/jsonlite/yaml deps come from
# prose-extract.R, which sources this file).

# ---------------------------------------------------------------------------
# The whitelist of label-bearing positions.
# ---------------------------------------------------------------------------
# Each entry says: "in a call to FUNC, a string literal at this argument is a
# user-facing label". An argument is identified EITHER by a named-argument
# prefix (e.g. `label = "..."`, `title = "..."`) OR by being the first
# POSITIONAL argument of a call where the function's whole purpose is a label
# (e.g. `ggtitle("A1")`). We deliberately keep the surface narrow:
#
#   * ggtitle(<pos1>)            — the plot title.
#   * labs(title=/subtitle=/caption=/x=/y=/fill=/colour=/color=)
#                                 — axis/legend/title labels.
#   * annotate("text", label=)  — on-canvas text labels (the "text" geom only;
#                                 annotate("segment"/"point", …) carry no text).
#   * element_*(... ) is NOT included: its string args are theme tokens, not
#                                 labels.
#
# In ADDITION, the DEFAULT VALUES of a fixed set of label-bearing arguments in
# our OWN helper functions (main-functions.R) are extracted. These are named
# explicitly (not pattern-matched) so we never accidentally grab an unrelated
# default. See .R_HELPER_DEFAULT_ARGS.
#
# Functions whose POSITIONAL first arg is a label.
.R_POSITIONAL_LABEL_FUNCS <- c("ggtitle")

# Named arguments that carry a user-facing label, keyed by the function name.
# A NULL/absent function-specific list means "applies to any call" is NOT used;
# we always require the enclosing call to be one of these named functions so we
# never grab a `label =`/`title =` that belongs to some unrelated helper.
.R_NAMED_LABEL_ARGS <- list(
  labs     = c("title", "subtitle", "caption", "x", "y", "fill", "colour", "color"),
  annotate = c("label")
)

# For annotate(): only the "text" geom carries a user-facing label. We gate on
# the first positional argument being the literal "text" so that
# annotate("segment"/"point", …) is never scanned for a label.
.R_ANNOTATE_TEXT_GEOM <- "text"

# Default-argument NAMES in our helper functions whose default VALUE is a
# user-facing label. We match a `NAME = "literal"` default anywhere in the file
# (these names are unambiguous label slots in main-functions.R). String defaults
# at any OTHER argument name are left untouched. Variable-valued defaults
# (e.g. `fill_colour = CHART_LINE_COLOUR`, `y = y_label`) are skipped naturally
# because they are not string literals.
.R_HELPER_DEFAULT_ARGS <- c(
  "lsl_label", "usl_label", "x_title", "y_label", "x_label",
  "legend_title", "percent_label", "caption", "subtitle", "title"
)

# ---------------------------------------------------------------------------
# Escape masking inside extracted R-string content.
# ---------------------------------------------------------------------------
# An extracted literal's INNER bytes are the source bytes between the quotes,
# which may contain R escape sequences (\n, \t, \", \\, …) and printf/glue
# interpolation tokens (%s, %d, {x}). A translator must never alter these, so we
# mask them with the SAME PUA-sentinel placeholder scheme prose uses (.ph_token,
# .PH_OPEN/.PH_CLOSE from prose-extract.R). Reinjection of the unchanged masked
# form reproduces the exact inner bytes, keeping the round-trip byte-identical.
.CODE_STRING_PROTECT_PATTERNS <- list(
  # Backslash escapes: \n \t \r \" \' \\ and \uXXXX etc. Match the backslash and
  # ONE following char (covers the common single-char escapes; \uXXXX's leading
  # \u is masked, the hex digits survive as literal text which is fine since they
  # are not translatable prose either way and reinjection is from raw bytes).
  r_escape  = "\\\\.",
  # printf/sprintf-style format specifiers: %s %d %1$s %.2f %% etc.
  sprintf_fmt = "%[-+ #0]*[0-9*]*(?:\\.[0-9*]+)?(?:[0-9]+\\$)?[diouxXeEfgGaAcspn%]",
  # glue/str_interp interpolation: {var} or {expr}
  glue_interp = "\\{[^}]*\\}"
)

#' Mask protected inline constructs inside an extracted code-string's content.
#' Mirrors .mask_inline() but with code-string patterns. Returns
#' list(masked, placeholders) using the shared .ph_token scheme so the rest of
#' the pipeline (segment record, reinjection) is identical to prose.
.mask_code_string <- function(text) {
  placeholders <- list()
  counter <- 0L
  masked <- text
  for (nm in names(.CODE_STRING_PROTECT_PATTERNS)) {
    pat <- .CODE_STRING_PROTECT_PATTERNS[[nm]]
    repeat {
      m <- regexpr(pat, masked, perl = TRUE)
      if (m[1] == -1L) break
      matched <- regmatches(masked, m)
      counter <- counter + 1L
      token <- .ph_token(counter)
      placeholders[[token]] <- list(kind = nm, value = matched)
      masked <- sub(pat, token, masked, perl = TRUE, fixed = FALSE)
    }
  }
  list(masked = masked, placeholders = placeholders)
}

# ---------------------------------------------------------------------------
# String-literal tokenizer for a single code line.
# ---------------------------------------------------------------------------
# We need to find string literals together with their character spans WITHOUT a
# full R parser (the tool stays on base R only). A small hand-rolled scanner is
# enough because R/JS/OJS string syntax is simple: double- or single-quoted,
# backslash escapes. We record, for each literal, its opening-quote position,
# its inner-content span, and (for whitelist matching) the bytes immediately
# preceding the quote on the line.
#
# Returns a list of records:
#   { quote, open_col, inner_start, inner_end, inner }
# where columns are 1-based CHARACTER offsets into the line, inner_start/end
# delimit the content BETWEEN the quotes (inner_end < inner_start for an empty
# string), and `inner` is the raw inner substring.
.tokenize_string_literals <- function(line) {
  chars <- strsplit(line, "", fixed = TRUE)[[1]]
  n <- length(chars)
  out <- list()
  i <- 1L
  while (i <= n) {
    c1 <- chars[i]
    if (c1 == '"' || c1 == "'") {
      quote <- c1
      open_col <- i
      inner_start <- i + 1L
      j <- i + 1L
      escaped <- FALSE
      closed <- FALSE
      while (j <= n) {
        cj <- chars[j]
        if (escaped) {
          escaped <- FALSE
        } else if (cj == "\\") {
          escaped <- TRUE
        } else if (cj == quote) {
          closed <- TRUE
          break
        }
        j <- j + 1L
      }
      if (!closed) {
        # Unterminated on this line (e.g. a string spanning multiple physical
        # lines). We do NOT extract such literals — sub-line addressing assumes
        # the literal lives on one line. Skip to end of line.
        break
      }
      inner_end <- j - 1L  # last char before the closing quote
      inner <- if (inner_end >= inner_start) {
        paste(chars[inner_start:inner_end], collapse = "")
      } else ""
      out[[length(out) + 1L]] <- list(
        quote = quote,
        open_col = open_col,
        inner_start = inner_start,
        inner_end = inner_end,
        inner = inner
      )
      i <- j + 1L
    } else {
      i <- i + 1L
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Whitelist matching for one literal on a line.
# ---------------------------------------------------------------------------
# Decide whether a given string literal (by its open-quote position) sits at a
# whitelisted, user-facing position. We look at the bytes immediately before the
# opening quote:
#   * `NAME = ` (optionally spaced)  -> a NAMED argument. Whitelisted iff the
#     name is a label arg for SOME function AND that function name appears as the
#     nearest enclosing `func(` to the left. (We approximate the enclosing call
#     by the nearest unmatched `(` scanning left — sufficient for our flat call
#     sites; conservative because a mismatch yields EXCLUSION.)
#   * `FUNC(` (optionally spaced)    -> the FIRST POSITIONAL argument of FUNC.
#     Whitelisted iff FUNC is in .R_POSITIONAL_LABEL_FUNCS.
#   * a helper DEFAULT arg `NAME = ` where NAME is in .R_HELPER_DEFAULT_ARGS and
#     we are inside a `function(` parameter list.
#
# `in_func_params` is the CROSS-LINE context flag: TRUE when this line sits
# inside an open `function(` parameter list (the open paren may be on an earlier
# physical line, so single-line scanning cannot tell — the caller tracks it).
# Returns TRUE/FALSE.
.is_whitelisted_literal <- function(line, lit, in_func_params = FALSE) {
  pre <- substr(line, 1L, lit$open_col - 1L)

  # --- Named argument: `... name = ` immediately before the quote -----------
  nm_m <- regexec("([A-Za-z_][A-Za-z0-9_.]*)[ \t]*=[ \t]*$", pre, perl = TRUE)
  nm_g <- regmatches(pre, nm_m)[[1]]
  if (length(nm_g) == 2) {
    argname <- nm_g[2]

    # (a) helper default-argument value, inside a `function(` param list. The
    # param list usually spans multiple lines, so we trust the caller's
    # cross-line `in_func_params` context AND require the nearest same-line
    # enclosing call (if any) to be `function` so a nested call default like
    # `caption = foo("x")` isn't mistaken for the default itself.
    if (argname %in% .R_HELPER_DEFAULT_ARGS && in_func_params) {
      same_line_call <- .nearest_enclosing_call(pre, want_keyword = TRUE)
      if (is.null(same_line_call) || identical(same_line_call, "function")) {
        return(TRUE)
      }
    }

    # (b) a label arg of a known function, with that function enclosing us.
    enclosing <- .nearest_enclosing_call(pre)
    if (!is.null(enclosing) && !is.null(.R_NAMED_LABEL_ARGS[[enclosing]]) &&
        argname %in% .R_NAMED_LABEL_ARGS[[enclosing]]) {
      # annotate(): only the "text" geom carries a label. Gate on the first
      # positional arg of the enclosing annotate(...) being "text".
      if (enclosing == "annotate" && !.annotate_is_text(line, lit$open_col)) {
        return(FALSE)
      }
      return(TRUE)
    }
    return(FALSE)
  }

  # --- First positional arg: `FUNC(` immediately before the quote -----------
  pos_m <- regexec("([A-Za-z_][A-Za-z0-9_.]*)[ \t]*\\([ \t]*$", pre, perl = TRUE)
  pos_g <- regmatches(pre, pos_m)[[1]]
  if (length(pos_g) == 2) {
    func <- pos_g[2]
    if (func %in% .R_POSITIONAL_LABEL_FUNCS) return(TRUE)
    return(FALSE)
  }

  FALSE
}

#' Find the name of the nearest enclosing call for a position, given the line
#' text BEFORE the literal. We scan right-to-left tracking paren depth; when we
#' reach the open paren that is still unmatched at our position, we read the
#' identifier (or the `function` keyword) immediately preceding it.
#'
#' @param want_keyword if TRUE, the `function` keyword is a valid result;
#'        otherwise only real call identifiers are returned.
#' @return the function/keyword name, or NULL if none / at top level.
.nearest_enclosing_call <- function(pre, want_keyword = FALSE) {
  chars <- strsplit(pre, "", fixed = TRUE)[[1]]
  depth <- 0L
  i <- length(chars)
  while (i >= 1L) {
    ch <- chars[i]
    if (ch == ")") {
      depth <- depth + 1L
    } else if (ch == "(") {
      if (depth == 0L) {
        # This is the unmatched open paren enclosing us. Read the identifier
        # immediately before it (skipping spaces/tabs).
        j <- i - 1L
        while (j >= 1L && (chars[j] == " " || chars[j] == "\t")) j <- j - 1L
        end <- j
        while (j >= 1L && grepl("[A-Za-z0-9_.]", chars[j])) j <- j - 1L
        if (end >= (j + 1L)) {
          name <- paste(chars[(j + 1L):end], collapse = "")
          if (identical(name, "function") && !want_keyword) return(NULL)
          return(name)
        }
        return(NULL)
      }
      depth <- depth - 1L
    }
    i <- i - 1L
  }
  NULL
}

#' For an annotate(...) call, decide whether its first positional argument is the
#' "text" geom. We look at the bytes from the enclosing `annotate(` up to the
#' literal under test and check the first quoted token equals "text". This keeps
#' us from labelling annotate("segment", …) / annotate("point", …).
.annotate_is_text <- function(line, open_col) {
  pre <- substr(line, 1L, open_col - 1L)
  # locate the enclosing `annotate(` open paren by scanning for the LAST
  # occurrence of "annotate(" before our position (call sites are flat).
  m <- gregexpr("annotate[ \t]*\\(", pre, perl = TRUE)[[1]]
  if (m[1] == -1L) return(FALSE)
  start <- m[length(m)]
  seg <- substr(line, start, open_col - 1L)
  first <- regmatches(seg, regexpr("[\"'][^\"']*[\"']", seg, perl = TRUE))
  if (length(first) == 0L) return(FALSE)
  inner <- substr(first, 2L, nchar(first) - 1L)
  identical(inner, .R_ANNOTATE_TEXT_GEOM)
}

# ---------------------------------------------------------------------------
# Scan one code line for whitelisted string literals -> sub-line spans.
# ---------------------------------------------------------------------------
#' Given one physical code line, return the user-facing string literals on it as
#' sub-line records. Each record:
#'   { inner, inner_start, inner_end }   (1-based char offsets into the line)
#' Only literals passing .is_whitelisted_literal() are returned. The caller tags
#' them with a segment kind and builds segment ids/addresses.
#'
#' This is the generic seam #325 plugs into: feed it a JS/OJS line plus its own
#' whitelist (by swapping the module-level whitelist tables) and it returns the
#' same sub-line span records.
#'
#' @param in_func_params cross-line context: TRUE when this line lies inside an
#'        open `function(` parameter list (so helper DEFAULT-arg literals are
#'        eligible). The caller maintains this with .update_func_param_context().
.scan_code_line_literals <- function(line, in_func_params = FALSE) {
  lits <- .tokenize_string_literals(line)
  keep <- list()
  for (lit in lits) {
    if (.is_whitelisted_literal(line, lit, in_func_params = in_func_params)) {
      keep[[length(keep) + 1L]] <- list(
        inner = lit$inner,
        inner_start = lit$inner_start,
        inner_end = lit$inner_end
      )
    }
  }
  keep
}

# ---------------------------------------------------------------------------
# Cross-line "inside a function() parameter list" context tracker.
# ---------------------------------------------------------------------------
# Helper default-argument labels (lsl_label = "...", x_title = "...") sit in a
# `function(...)` parameter list that usually spans MANY physical lines. To know
# a continuation line is still inside that list, we track paren depth statefully
# as we walk lines. State: list(in_params, depth) where `depth` counts open
# parens since the `function(` that opened the param list; the list ends when
# depth returns to 0.
#
# We deliberately ignore parens that appear INSIDE string literals (a default
# value could contain a "(" ); the tokenizer tells us the literal spans so we
# blank them out before counting. This keeps the depth count honest without a
# full parser.
.func_param_context_init <- function() list(in_params = FALSE, depth = 0L)

#' Advance the context by one line. Returns list(state, line_in_params) where
#' `line_in_params` is whether THIS line should be treated as inside the param
#' list (used for THIS line's scan), and `state` is the context to carry forward.
.update_func_param_context <- function(line, state) {
  # The status that applies to literals ON this line is the status BEFORE we
  # account for a `function(` that opens partway through it; but a `function(`
  # opening on this very line also makes the rest of this line param-context.
  # We therefore recompute char-by-char and report the context as "in_params if
  # we are inside the list at the moment we pass any given point". For the scan
  # we report TRUE if the line is in_params at its START or becomes so on it.
  line_starts_in <- state$in_params

  # Blank out string-literal content so parens within strings don't skew depth.
  lits <- .tokenize_string_literals(line)
  masked <- line
  if (length(lits)) {
    for (lit in lits) {
      if (lit$inner_end >= lit$inner_start) {
        masked <- paste0(
          substr(masked, 1L, lit$inner_start - 1L),
          strrep(" ", lit$inner_end - lit$inner_start + 1L),
          substr(masked, lit$inner_end + 1L, nchar(masked))
        )
      }
    }
  }

  in_params <- state$in_params
  depth <- state$depth
  becomes_in <- FALSE

  # Find `function(` openers on this (string-masked) line.
  fn_open <- gregexpr("function[ \t]*\\(", masked, perl = TRUE)[[1]]
  fn_open_cols <- if (fn_open[1] == -1L) integer(0) else
    fn_open + attr(fn_open, "match.length") - 1L  # column of the opening "("

  chars <- strsplit(masked, "", fixed = TRUE)[[1]]
  for (ci in seq_along(chars)) {
    ch <- chars[ci]
    if (!in_params) {
      if (ch == "(" && ci %in% fn_open_cols) {
        in_params <- TRUE
        depth <- 1L
        becomes_in <- TRUE
      }
    } else {
      if (ch == "(") depth <- depth + 1L
      else if (ch == ")") {
        depth <- depth - 1L
        if (depth == 0L) in_params <- FALSE
      }
    }
  }

  list(
    state = list(in_params = in_params, depth = depth),
    line_in_params = line_starts_in || becomes_in
  )
}

# ---------------------------------------------------------------------------
# Generalized intra-line (sub-line) reinjection.
# ---------------------------------------------------------------------------
#' Splice replacement text into sub-line segments, leaving every other byte
#' byte-identical. Works for ANY sub-line segment kind (r-string today,
#' ojs/js-string for #325).
#'
#' @param lines        the original line vector (character, no newlines).
#' @param subsegs      list of records with integer fields start_line,
#'                     start_col, end_col and the replacement string `repl`.
#'                     start_col..end_col is the INNER span (content between the
#'                     quotes); for an empty original literal end_col ==
#'                     start_col - 1 and the replacement is inserted at start_col.
#' @return the modified line vector.
#'
#' We process per line, and within a line in DESCENDING start_col order, so that
#' splicing a later literal never shifts the offsets of an earlier one.
.reinject_subline_segments <- function(lines, subsegs) {
  if (!length(subsegs)) return(lines)
  by_line <- split(subsegs, vapply(subsegs, function(s) s$start_line, integer(1)))
  for (ln_key in names(by_line)) {
    ln <- as.integer(ln_key)
    group <- by_line[[ln_key]]
    starts <- vapply(group, function(s) s$start_col, integer(1))
    ordg <- order(starts, decreasing = TRUE)
    line <- lines[[ln]]
    for (gi in ordg) {
      s <- group[[gi]]
      a <- s$start_col
      b <- s$end_col            # b == a-1 for an empty original literal
      before <- if (a > 1L) substr(line, 1L, a - 1L) else ""
      after  <- if (b < nchar(line)) substr(line, b + 1L, nchar(line)) else ""
      line <- paste0(before, s$repl, after)
    }
    lines[[ln]] <- line
  }
  lines
}
