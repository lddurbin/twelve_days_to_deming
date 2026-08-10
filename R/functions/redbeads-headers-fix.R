# Fix for #586: gt (pinned at 1.3.0 in renv.lock, which is also the current
# CRAN release — there is no newer version to bump to) hardcodes the wrong
# `headers` attribute on every `<td>` cell of a table built with a
# single-column stub (`rowname_col =`), such as the 24 red-beads results
# tables on content/days/day-02/06-your-turn.qmd.
#
# Root cause, traced to gt's internal `render_row_data()`. The installed
# binary doesn't ship readable R source, so this was confirmed by
# downloading the CRAN source tarball for gt 1.3.0
# (https://cran.r-project.org/src/contrib/gt_1.3.0.tar.gz) and cross-checking
# `gt/R/utils_render_html.R` against `deparse(getFromNamespace(
# "render_row_data", "gt"))` on the installed package — both match. The
# relevant lines:
#
#   header <- paste0(
#     ifelse(has_group, current_group_id, ""), ifelse(has_group, " ", ""),
#     row_id_i, ifelse(has_group | nzchar(row_id_i), " ", ""),
#     col_id_i
#   )
#
# This puts the row-stub id (e.g. "stub_1_1") BEFORE the column id, where
# WCAG technique H43 (and pa11y/HTMLCS's H43.IncorrectAttr check) expects
# column id(s) first, then row id(s). There's a second, compounding bug:
# `col_id_i` here is taken straight from the raw column name
# (`dt_boxhead_get_vars_default()`), and is never passed through gt's own
# `valid_html_id()` sanitiser (`gsub("\\s+", "-", x)`) — the same sanitiser
# gt DOES use when it writes the actual `<th id="...">` for that column's
# label. So for a column literally named "Day 1", gt emits
# `<th id="Day-1">Day 1</th>` for the header cell, but
# `<td headers="stub_1_1 Day 1">` for every body cell in that column — the
# `headers` value doesn't even reference an id that exists anywhere in the
# document, on top of being in the wrong order.
#
# No `tab_options()`/`tab_style()` argument controls any of this — it's
# compiled into the gt namespace, not user-configurable. Confirmed 1.3.0 is
# also the current CRAN release (checked
# https://cran.r-project.org/web/packages/gt/index.html), so neither a
# gt-level option nor a version bump is viable; this has to be a post-render
# HTML fix, following the precedent in R/functions/og-description-fix.R
# (#521 — a similar "upstream tool emits markup we can't reach from R"
# problem).
#
# render_redbeads_table() (R/functions/main-functions.R) is used ONLY on
# content/days/day-02/06-your-turn.qmd (confirmed via
# `grep -rn render_redbeads_table content/`), and every table it builds has
# exactly one stub column (`rowname_col = "Name"`) and no row groups, so the
# malformed `headers` value is always exactly two space-separated tokens:
# `stub_<n>_<n>` followed by the (possibly space-containing) raw column
# name. The regex below is scoped to that literal `stub_<digits>_<digits>`
# prefix, so it can only ever match gt's own mis-ordered output — never a
# correctly-ordered `headers` attribute elsewhere in the document.

.redbeads_headers_fix_re <- 'headers="(stub_[0-9]+_[0-9]+) ([^"]+)"'

#' Fix gt's row-id-before-column-id `headers` attribute ordering
#'
#' Rewrites `headers="stub_<n>_<n> <col>"` (gt 1.3.0's emitted order, which
#' fails WCAG technique H43) to `headers="<col-id> stub_<n>_<n>"`, sanitising
#' the column token the same way gt's own `valid_html_id()` sanitises the
#' matching `<th id="...">` (runs of whitespace collapsed to a single "-"),
#' so the reference actually resolves to an id that exists in the document.
#'
#' @param path Path to a rendered .html file.
#' @return TRUE if the file was modified, FALSE otherwise (including when no
#'   matching `headers` attribute is found, or the file doesn't exist).
fix_redbeads_headers_in_file <- function(path) {
  if (!file.exists(path)) {
    return(FALSE)
  }

  size <- file.info(path)$size
  content <- readChar(path, size, useBytes = TRUE)
  Encoding(content) <- "UTF-8"

  match_pos <- gregexpr(.redbeads_headers_fix_re, content, perl = TRUE)
  matches <- regmatches(content, match_pos)[[1]]

  if (length(matches) == 0) {
    return(FALSE)
  }

  stub_ids <- sub(.redbeads_headers_fix_re, "\\1", matches, perl = TRUE)
  col_tokens <- sub(.redbeads_headers_fix_re, "\\2", matches, perl = TRUE)
  col_ids <- gsub("\\s+", "-", col_tokens)

  replacements <- sprintf('headers="%s %s"', col_ids, stub_ids)
  regmatches(content, match_pos) <- list(replacements)

  writeChar(content, path, eos = NULL, useBytes = TRUE)
  TRUE
}

#' Run fix_redbeads_headers_in_file() over every .html path in `files`.
#'
#' @param files Character vector of file paths, typically Quarto's
#'   QUARTO_PROJECT_OUTPUT_FILES post-render list (non-.html entries, e.g.
#'   supporting assets, are ignored).
#' @return Integer count of files actually modified.
fix_redbeads_headers <- function(files) {
  html_files <- files[grepl("\\.html$", files)]
  sum(vapply(html_files, fix_redbeads_headers_in_file, logical(1)))
}
