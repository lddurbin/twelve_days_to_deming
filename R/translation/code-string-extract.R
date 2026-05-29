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

# ---------------------------------------------------------------------------
# The whitelist of label-bearing positions for OJS / JS / HTML (issue #325).
# ---------------------------------------------------------------------------
# Same DISCIPLINE as the R whitelist above: only USER-FACING string literals at
# a tight set of positions are extracted; a false positive that rewrote an
# element id, a CSS class, an ARIA role token, a selector, an event name or a
# file path would corrupt the UI and is far worse than a missed label. When in
# doubt, EXCLUDE. The JS files lean HEAVILY on backtick template literals
# (~76/file), the vast majority of which are NOT user-facing (id templates, CSS
# class lists, SVG markup, selectors), so the matcher is positional, never
# "extract every string".
#
# Each surface maps to a segment KIND so a translator sees the interface context:
#   * `ui-string`  — visible UI text (input labels/placeholders, button text).
#   * `aria-label` — assistive-technology text (aria-label values, live-region
#                    announcements). These are invisible to sighted users but
#                    must still be translated.
#
# OJS named-argument labels. In a call to one of these `Inputs.*` constructors,
# the VALUE of a `label:` / `placeholder:` property is user-facing UI text.
# (OJS object literals use `name: value`, not R's `name = value`.) The enclosing
# call must be one of these constructors so an unrelated `label:`/`placeholder:`
# key elsewhere is never grabbed.
.OJS_INPUT_FUNCS <- c("Inputs.textarea", "Inputs.text", "Inputs.button")
.OJS_LABEL_PROPS <- c("label", "placeholder")

# JS object-PROPERTY assignments whose RHS string literal is user-facing. Keyed
# by the property name appearing immediately before `= ` (e.g. `x.textContent =`,
# `x.placeholder =`). RHS values that are NOT string literals (a variable, a
# function call like `formatNet(net)` / `buildCellLabel(...)`, a concatenation)
# are skipped naturally because the matcher only fires when a quote/backtick
# sits immediately after the `= `. Each maps to its segment kind.
.JS_ASSIGN_PROPS <- list(
  textContent = "ui-string",
  placeholder = "ui-string"
)

# JS DOM functions whose FIRST POSITIONAL string-literal argument is user-facing
# assistive text (a live-region / status announcement). The whole point of the
# call is to speak a message, so its literal first arg is an `aria-label`.
.JS_ANNOUNCE_FUNCS <- c("announceFunnelStatus")

# setAttribute(NAME, VALUE): the VALUE is user-facing ONLY when NAME is one of
# these accessibility/label attributes. We gate on the NAME argument so
# setAttribute("role", "button") / ("tabindex","0") / ("aria-live","polite") are
# never touched. The kind is chosen by the attribute name.
.JS_SETATTR_LABEL_ATTRS <- list(
  "aria-label" = "aria-label",
  "placeholder" = "ui-string",
  "title"       = "ui-string"
)

# Raw-HTML attributes in `.qmd` (e.g. `<div ... aria-label="Commentary">`) whose
# VALUE is user-facing. role=/class=/id=/data-*=/aria-controls= etc. are NEVER
# extracted. The kind is chosen by the attribute name.
.HTML_LABEL_ATTRS <- list(
  "aria-label"  = "aria-label",
  "title"       = "ui-string",
  "alt"         = "ui-string",
  "placeholder" = "ui-string"
)

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
  # JS template-literal interpolation: ${var} or ${expr}. Listed BEFORE glue so a
  # `${...}` is consumed as one unit and never mistaken for glue's `{...}` (which
  # would leave a stray `$` on the translator surface and split the placeholder).
  # An interpolation is live CODE; a translator must never see or edit it.
  js_interp   = "\\$\\{[^}]*\\}",
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
#
# NOT supported: R 4.0+ raw strings (`r"(...)"`, `r"[...]"`, `R'(...)'`). The
# scanner treats the leading `r`/`R` as an ordinary identifier char and would
# mis-span the delimiter as inner content. This is safe in practice on two
# counts: (1) the whitelist matcher only fires when a `(` or `name = ` sits
# IMMEDIATELY before the opening quote, but a raw string puts `r`/`R` there
# instead, so a raw-string literal is never accepted as a label nor emitted as a
# segment; and (2) the identity round-trip reinjects original bytes, so
# byte-identity holds even where a raw string is mis-spanned. If a future label
# position ever needs raw strings, add an `r"`/`R"` prefix guard here rather than
# relying on the whitelist to exclude it.
.tokenize_string_literals <- function(line) {
  chars <- strsplit(line, "", fixed = TRUE)[[1]]
  n <- length(chars)
  out <- list()
  i <- 1L
  while (i <= n) {
    c1 <- chars[i]
    # Recognise double-quote, single-quote AND JS backtick (template literal)
    # delimiters. Backtick template literals (issue #325) escape with `\` exactly
    # like the quoted forms — a literal backtick inside is `\``, a newline `\n`,
    # etc. — so the SAME escape-aware scan below closes them correctly. The
    # `${...}` interpolations a template literal may contain are masked later by
    # .mask_code_string(); the tokenizer treats their bytes as ordinary content
    # (any `"`/`'` inside `${...}` cannot prematurely close a backtick literal
    # because we are tracking the backtick delimiter, not the quote chars).
    if (c1 == '"' || c1 == "'" || c1 == "`") {
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
# OJS / JS whitelist matching for one literal on a line (issue #325).
# ---------------------------------------------------------------------------
# Mirrors .is_whitelisted_literal() but for the OJS/JS surfaces. It looks at the
# bytes immediately BEFORE the opening quote/backtick (and, for setAttribute, a
# little context AFTER) to decide whether the literal sits at a user-facing
# position. Returns NULL when NOT whitelisted, or the segment KIND string
# (`ui-string` / `aria-label`) when it is — the caller tags the segment with it.
#
# Why return the kind (not just TRUE/FALSE): unlike R (one kind, `r-string`), the
# JS/OJS surfaces emit TWO kinds, chosen by the position (an aria-label attribute
# vs a visible textContent). Threading the kind out of the matcher keeps the
# decision in one place.
.ojs_js_literal_kind <- function(line, lit) {
  pre <- substr(line, 1L, lit$open_col - 1L)

  # --- OJS object property: `name: "..."` immediately before the quote --------
  # OJS object literals use `key: value`. A `label:` / `placeholder:` whose
  # enclosing call is one of the Inputs.* constructors is user-facing UI text.
  prop_m <- regexec("([A-Za-z_][A-Za-z0-9_]*)[ \t]*:[ \t]*$", pre, perl = TRUE)
  prop_g <- regmatches(pre, prop_m)[[1]]
  if (length(prop_g) == 2 && prop_g[2] %in% .OJS_LABEL_PROPS) {
    enclosing <- .nearest_enclosing_call(pre)
    if (!is.null(enclosing) && enclosing %in% .OJS_INPUT_FUNCS) {
      return("ui-string")
    }
  }

  # --- JS property assignment: `x.PROP = "..."` immediately before the quote --
  # Match the dotted property name on the LHS of an assignment `=` directly
  # before the literal. Only a literal sitting flush after `= ` is taken; a
  # non-literal RHS (variable / call like `formatNet(net)` / concatenation)
  # leaves something other than a quote there and is skipped. The lookbehind on
  # the `=` excludes the comparison operators `==`/`===`/`!=`/`<=`/`>=` AND the
  # compound-assignment operators `+=`/`-=`/`*=`/`/=`/`%=`/`&=`/`|=`/`^=` (the
  # logical-assignment forms `&&=`/`||=` are covered too, since their last char
  # before `=` is `&`/`|`), so neither an equality test nor an append
  # (`x.textContent += "…"`, which is not the full UI text) is mistaken for a
  # plain assignment. NOT excluded: `??=` (nullish-coalescing assignment) —
  # absent from the corpus, and a `??=` default is often a legitimate user-facing
  # fallback string, so extracting it would usually be correct rather than a
  # false positive. Left in deliberately; revisit if a non-label `??=` appears.
  asn_m <- regexec("\\.([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?<![=<>!+*/%&|^-])=[ \t]*$", pre, perl = TRUE)
  asn_g <- regmatches(pre, asn_m)[[1]]
  if (length(asn_g) == 2 && !is.null(.JS_ASSIGN_PROPS[[asn_g[2]]])) {
    return(.JS_ASSIGN_PROPS[[asn_g[2]]])
  }

  # --- JS announce-function first positional arg: `FUNC(` before the quote ----
  pos_m <- regexec("([A-Za-z_][A-Za-z0-9_]*)[ \t]*\\([ \t]*$", pre, perl = TRUE)
  pos_g <- regmatches(pre, pos_m)[[1]]
  if (length(pos_g) == 2 && pos_g[2] %in% .JS_ANNOUNCE_FUNCS) {
    return("aria-label")
  }

  # --- JS setAttribute(NAME, VALUE): the VALUE arg, gated on NAME --------------
  # The literal under test must be the SECOND argument of a setAttribute call
  # whose FIRST argument is a whitelisted attribute name. We detect this by
  # looking for `setAttribute("<attr>", ` (the comma + space before our literal),
  # then mapping <attr> to its kind. setAttribute("role"/"tabindex"/"aria-live",
  # …) is excluded because those names aren't in .JS_SETATTR_LABEL_ATTRS.
  sa_m <- regexec(
    "setAttribute[ \t]*\\([ \t]*[\"']([A-Za-z-]+)[\"'][ \t]*,[ \t]*$",
    pre, perl = TRUE
  )
  sa_g <- regmatches(pre, sa_m)[[1]]
  if (length(sa_g) == 2 && !is.null(.JS_SETATTR_LABEL_ATTRS[[sa_g[2]]])) {
    return(.JS_SETATTR_LABEL_ATTRS[[sa_g[2]]])
  }

  NULL
}

# ---------------------------------------------------------------------------
# Raw-HTML attribute-value scanning for one line (issue #325).
# ---------------------------------------------------------------------------
# A raw-HTML line in a `.qmd` (e.g. `<div class="thought" role="note"
# aria-label="Commentary">`) is classified STRUCTURAL by prose-extract.R and
# skipped — but a whitelisted ATTRIBUTE VALUE on it (aria-label, title, alt,
# placeholder) is user-facing and must be extracted BEFORE the line is skipped.
# role=/class=/id=/data-*=/aria-controls= etc. are NEVER extracted.
#
# Returns a list of sub-line records { inner, inner_start, inner_end, kind } for
# each whitelisted attribute value, the same span shape .scan_code_line_literals
# returns (plus a per-record `kind`, since HTML mixes aria-label / ui-string).
.scan_html_attr_values <- function(line) {
  keep <- list()
  # Iterate the whitelisted attribute names; for each, find every `attr="value"`
  # (or single-quoted) occurrence and record the INNER span of the value. We use
  # an explicit per-attribute pattern so we never grab role/class/id (not in the
  # whitelist). The attribute name must NOT be preceded by a word char OR a
  # hyphen, so a whitelisted name is never matched as the TAIL of a longer
  # attribute: `aria-label` must not fire inside `data-aria-label`, nor `title`
  # inside `data-title`, nor `alt` inside `data-alt`. A `\b` boundary is WRONG
  # here — `\b` sits between the `-` and the name in `data-aria-label`, so it
  # matches the wrong attribute; a negative lookbehind on [A-Za-z0-9-] is the
  # correct guard.
  for (attr in names(.HTML_LABEL_ATTRS)) {
    kind <- .HTML_LABEL_ATTRS[[attr]]
    pat <- sprintf("(?<![A-Za-z0-9-])%s[ \t]*=[ \t]*([\"'])", attr)
    m <- gregexpr(pat, line, perl = TRUE)[[1]]
    if (m[1] == -1L) next
    starts <- as.integer(m)
    lens <- attr(m, "match.length")
    for (k in seq_along(starts)) {
      # The opening quote is the LAST char of the matched `attr="` prefix.
      open_col <- starts[k] + lens[k] - 1L
      lit <- .one_literal_at(line, open_col)
      if (is.null(lit)) next
      keep[[length(keep) + 1L]] <- list(
        inner = lit$inner,
        inner_start = lit$inner_start,
        inner_end = lit$inner_end,
        kind = kind
      )
    }
  }
  keep
}

#' Tokenize the single string literal whose opening quote is at `open_col`.
#' Reuses the same escape-aware scan as .tokenize_string_literals but for ONE
#' known literal start, returning its inner span (or NULL if unterminated on the
#' line). Used by the HTML attribute scanner where we already know the quote
#' position from the attribute-name match.
.one_literal_at <- function(line, open_col) {
  chars <- strsplit(line, "", fixed = TRUE)[[1]]
  n <- length(chars)
  if (open_col > n) return(NULL)
  quote <- chars[open_col]
  inner_start <- open_col + 1L
  j <- inner_start
  escaped <- FALSE
  closed <- FALSE
  while (j <= n) {
    cj <- chars[j]
    if (escaped) escaped <- FALSE
    else if (cj == "\\") escaped <- TRUE
    else if (cj == quote) { closed <- TRUE; break }
    j <- j + 1L
  }
  if (!closed) return(NULL)
  inner_end <- j - 1L
  inner <- if (inner_end >= inner_start) paste(chars[inner_start:inner_end], collapse = "") else ""
  list(inner = inner, inner_start = inner_start, inner_end = inner_end)
}

# ---------------------------------------------------------------------------
# Scan one OJS/JS code line for whitelisted literals -> kinded sub-line spans.
# ---------------------------------------------------------------------------
#' The OJS/JS counterpart of .scan_code_line_literals(). Returns records
#'   { inner, inner_start, inner_end, kind }
#' for each user-facing literal on the line. Like the R scanner it tokenizes the
#' line (now including backtick template literals) and applies a whitelist, but
#' the OJS/JS matcher returns the segment KIND (ui-string / aria-label) per
#' literal rather than a single fixed kind.
#' @param in_announce_call cross-line context: TRUE when this line lies inside an
#'        open announce-function call (e.g. `announceFunnelStatus(` opened on a
#'        PRIOR line). When TRUE, a string literal that is the FIRST token on the
#'        line is taken as the announce message (kind `aria-label`). The caller
#'        maintains this with .update_announce_call_context().
.scan_ojs_js_line_literals <- function(line, in_announce_call = FALSE) {
  lits <- .tokenize_string_literals(line)
  keep <- list()
  for (li in seq_along(lits)) {
    lit <- lits[[li]]
    kind <- .ojs_js_literal_kind(line, lit)
    # Multi-line announce call: the message literal sits on its OWN line, flush
    # after the opener on the previous line. We accept ONLY the FIRST literal on
    # such a continuation line, and only when nothing but whitespace precedes it,
    # so a stray later literal on the line isn't swept in.
    if (is.null(kind) && in_announce_call && li == 1L &&
        !grepl("\\S", substr(line, 1L, lit$open_col - 1L))) {
      kind <- "aria-label"
    }
    # Skip EMPTY literals: an empty string (e.g. `cell.textContent = ""` to clear
    # a greyed-out cell) carries no translatable text and would only pollute the
    # translator surface. Whitelisted-but-empty is treated as nothing to extract.
    if (!is.null(kind) && nzchar(lit$inner)) {
      keep[[length(keep) + 1L]] <- list(
        inner = lit$inner,
        inner_start = lit$inner_start,
        inner_end = lit$inner_end,
        kind = kind
      )
    }
  }
  keep
}

# ---------------------------------------------------------------------------
# Cross-line "inside an announce-function call" context tracker (issue #325).
# ---------------------------------------------------------------------------
# Live-region announcements like
#   announceFunnelStatus(
#     `Rule ${rule}, stage ${counter} of ${totalStages}. ...`
#   );
# put the user-facing message literal on a CONTINUATION line, so a single-line
# positional match (`FUNC(` immediately before the quote) misses it. We track,
# statefully across lines, whether we are inside an open announce-func call by
# counting parens AFTER an announce opener, ignoring parens inside string
# literals (same blanking trick as the function-param tracker). State:
# list(in_call, depth).
.announce_call_context_init <- function() list(in_call = FALSE, depth = 0L)

#' Advance the announce-call context by one line. Returns
#' list(state, line_in_call) where `line_in_call` is whether THIS line should be
#' treated as a continuation inside an open announce call (used for THIS line's
#' scan). A line that OPENS the call reports FALSE for itself (its own inline
#' literal, if any, is already caught by the positional matcher); only the
#' SUBSEQUENT continuation lines report TRUE.
.update_announce_call_context <- function(line, state) {
  line_starts_in <- state$in_call

  # Blank out string-literal content so parens inside strings don't skew depth.
  lits <- .tokenize_string_literals(line)
  masked <- line
  for (lit in lits) {
    if (lit$inner_end >= lit$inner_start) {
      masked <- paste0(
        substr(masked, 1L, lit$inner_start - 1L),
        strrep(" ", lit$inner_end - lit$inner_start + 1L),
        substr(masked, lit$inner_end + 1L, nchar(masked))
      )
    }
  }

  in_call <- state$in_call
  depth <- state$depth

  # Columns of the `(` that opens an announce call on this line.
  funcs <- paste(.JS_ANNOUNCE_FUNCS, collapse = "|")
  op <- gregexpr(sprintf("(?:%s)[ \t]*\\(", funcs), masked, perl = TRUE)[[1]]
  open_cols <- if (op[1] == -1L) integer(0) else op + attr(op, "match.length") - 1L

  chars <- strsplit(masked, "", fixed = TRUE)[[1]]
  for (ci in seq_along(chars)) {
    ch <- chars[ci]
    if (!in_call) {
      if (ch == "(" && ci %in% open_cols) { in_call <- TRUE; depth <- 1L }
    } else {
      if (ch == "(") depth <- depth + 1L
      else if (ch == ")") {
        depth <- depth - 1L
        if (depth == 0L) in_call <- FALSE
      }
    }
  }

  list(
    state = list(in_call = in_call, depth = depth),
    # Report TRUE only if the line STARTED inside an already-open call — i.e. a
    # continuation line. A line that merely opens (and maybe closes) the call
    # here is handled by the inline positional matcher, not the continuation path.
    line_in_call = line_starts_in
  )
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
  #
  # #324 follow-up note (flagged for the next reader): when a `function(` opens
  # on THIS line, `line_in_params = TRUE` is reported for the WHOLE line —
  # including any literal that appears textually BEFORE the `function` keyword on
  # the same line. That is technically too eager (such a pre-keyword literal is
  # not really inside the param list), but it is benign in this corpus: nothing
  # places a whitelisted helper-default literal to the LEFT of a `function(` on
  # the same physical line. If that ever changes, gate eligibility on the
  # literal's column being to the right of the opener column.
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
