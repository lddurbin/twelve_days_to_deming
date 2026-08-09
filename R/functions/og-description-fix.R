# Fix for #521: on this book project, og:description and twitter:description
# always fall back to _quarto.yml's book-level description, ignoring each
# page's own `description:` front matter — even though <meta
# name="description"> (the tag Google actually reads) uses the page-level
# value correctly.
#
# Root cause, traced through quarto.js's opengraphMetadata()/
# twitterMetadata()/mergedSiteAndDocumentData(): this project sets
# `open-graph: true` and `twitter-card: true` as literal booleans in
# _quarto.yml. Quarto copies those booleans verbatim onto the internal
# website-shaped config it derives from `book:`, and its per-page-override
# lookup only extracts a description when that config is an *object*
# (`typeof openGraph === "object"`) — a boolean never qualifies, so the
# page-level description is never consulted and the book-level description
# leaks into every page's OG/Twitter tags instead. Confirmed against both
# quarto.js's source and an actual rendered page.
#
# A Pandoc Lua filter can't fix this: Quarto resolves this metadata from its
# own YAML parse of front matter before the filter chain ever runs, so
# mutating `doc.meta` in a filter has no effect on it (verified empirically
# against a minimal reproduction). This has to run after Quarto has already
# written the HTML, hence a project post-render step (see
# scripts/fix-og-description.R) rather than a filter alongside
# filters/reading-time.lua.

.og_description_fix_description_tag_re <-
  '<meta name="description" content="[^"]*">'
# All three patterns assume Quarto's current attribute order (name/property
# first, then content) and an unclosed <meta ...> tag — both verified against
# actual rendered output as of Quarto 1.4.549/1.10.18. If a future Quarto
# version reorders attributes or switches to a self-closing <meta .../> form,
# these silently stop matching: fix_og_description_in_file() returns FALSE
# rather than erroring, so this would regress quietly. A rendered-output spot
# check (as in this PR's test plan) after any Quarto version bump is the way
# to catch that.
.og_description_fix_og_tag_re <-
  '<meta property="og:description" content="[^"]*">'
.og_description_fix_twitter_tag_re <-
  '<meta name="twitter:description" content="[^"]*">'

.og_description_fix_extract_content_attr <- function(tag) {
  sub('^.*content="([^"]*)".*$', "\\1", tag, perl = TRUE)
}

# Splices `replacement` in place of the first match of `pattern`, by string
# position rather than as a gsub() replacement string — so arbitrary
# characters in `replacement` (a backslash, a literal "\1") are never
# reinterpreted as backreferences.
.og_description_fix_replace_first_match <- function(content, pattern, replacement) {
  loc <- regexpr(pattern, content, perl = TRUE)
  if (loc == -1) {
    return(content)
  }
  start <- as.integer(loc)
  len <- attr(loc, "match.length")
  paste0(
    substr(content, 1, start - 1),
    replacement,
    substr(content, start + len, nchar(content))
  )
}

#' Copy a rendered HTML page's <meta name="description"> content into its
#' og:description and twitter:description tags, if present.
#'
#' @param path Path to a rendered .html file.
#' @return TRUE if the file was modified, FALSE otherwise (including when no
#'   description tag is found, or the file doesn't exist).
fix_og_description_in_file <- function(path) {
  if (!file.exists(path)) {
    return(FALSE)
  }

  size <- file.info(path)$size
  content <- readChar(path, size, useBytes = TRUE)
  Encoding(content) <- "UTF-8"

  desc_match <- regmatches(
    content,
    regexpr(.og_description_fix_description_tag_re, content, perl = TRUE)
  )
  if (length(desc_match) == 0) {
    return(FALSE)
  }
  description <- .og_description_fix_extract_content_attr(desc_match)

  og_tag <- sprintf('<meta property="og:description" content="%s">', description)
  twitter_tag <- sprintf('<meta name="twitter:description" content="%s">', description)

  new_content <- .og_description_fix_replace_first_match(
    content, .og_description_fix_og_tag_re, og_tag
  )
  new_content <- .og_description_fix_replace_first_match(
    new_content, .og_description_fix_twitter_tag_re, twitter_tag
  )

  if (identical(content, new_content)) {
    return(FALSE)
  }

  writeChar(new_content, path, eos = NULL, useBytes = TRUE)
  TRUE
}

#' Run fix_og_description_in_file() over every .html path in `files`.
#'
#' @param files Character vector of file paths, typically Quarto's
#'   QUARTO_PROJECT_OUTPUT_FILES post-render list (non-.html entries, e.g.
#'   supporting assets, are ignored).
#' @return Integer count of files actually modified.
fix_og_description <- function(files) {
  html_files <- files[grepl("\\.html$", files)]
  sum(vapply(html_files, fix_og_description_in_file, logical(1)))
}
