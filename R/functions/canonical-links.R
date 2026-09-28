# Self-referencing <link rel="canonical"> on every page (#896).
#
# `site-url` in _quarto.yml does not make Quarto emit canonical links on this
# book project: on Quarto 1.10.18 it drives only the sitemap, llms.txt and the
# absolute og:image/twitter:image URLs. Since #886 two hosts serve the same
# bytes (learndeming.org and, until #888 redirects it,
# deming.leedurbin.co.nz), so each page has to name its canonical URL itself.
#
# Like og-description-fix.R, this runs as a project post-render step (see
# scripts/add-canonical-links.R), so the link is in the served bytes: crawler
# and anonymous views stay identical, as AGENTS.md's URL policy requires.
#
# The URL is site-url plus the page's path under _book/, in the same form the
# sitemap uses (/index.html, not /). Paths are taken relative to _book/, not to
# the profile's output-dir, so a French page rendered into _book/fr/ gets its
# /fr/ URL.

.canonical_link_tag_re <- '<link rel="canonical"[^>]*>'
.canonical_link_href_re <- '^.*href="([^"]*)".*$'

# Pages that must not declare themselves canonical: an error page, a page
# asking not to be indexed, and a meta-refresh stub (the French edition's
# index.html redirects to index.fr.html).
.canonical_link_skip_re <- paste0(
  '<meta name="robots" content="[^"]*noindex|',
  '<meta http-equiv="refresh"'
)

.canonical_link_read <- function(path) {
  content <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(content) <- "UTF-8"
  content
}

#' The canonical URL for a page at `rel_path` under the site root.
canonical_url <- function(rel_path, site_url) {
  paste0(sub("/$", "", site_url), "/", sub("^/", "", rel_path))
}

#' Insert a canonical link into one rendered page, just before </head>.
#'
#' @param path Path to a rendered .html file.
#' @param url The page's canonical URL.
#' @return TRUE if the file was modified, FALSE otherwise: the file is missing,
#'   has no </head>, is a page that shouldn't be canonical (404, noindex,
#'   redirect stub), or already has a canonical link.
add_canonical_link_in_file <- function(path, url) {
  if (!file.exists(path) || basename(path) == "404.html") {
    return(FALSE)
  }

  content <- .canonical_link_read(path)
  if (grepl(.canonical_link_tag_re, content, perl = TRUE) ||
      grepl(.canonical_link_skip_re, content, perl = TRUE)) {
    return(FALSE)
  }

  loc <- regexpr("</head>", content, fixed = TRUE)
  if (loc == -1) {
    return(FALSE)
  }

  # Spliced by position rather than via sub(), so nothing in `url` is ever
  # read as a backreference.
  start <- as.integer(loc)
  new_content <- paste0(
    substr(content, 1, start - 1),
    sprintf('<link rel="canonical" href="%s">\n', url),
    substr(content, start, nchar(content))
  )

  writeChar(new_content, path, eos = NULL, useBytes = TRUE)
  TRUE
}

#' Run add_canonical_link_in_file() over every .html path in `files`.
#'
#' @param files Character vector of file paths, typically Quarto's
#'   QUARTO_PROJECT_OUTPUT_FILES post-render list. Entries outside `site_root`
#'   and non-.html entries are ignored.
#' @param site_url The book's `site-url`.
#' @param site_root The directory that is served at `site_url` (`_book`).
#' @return Integer count of files actually modified.
add_canonical_links <- function(files, site_url, site_root) {
  html_files <- files[grepl("\\.html$", files)]
  root <- paste0(normalizePath(site_root, mustWork = TRUE), "/")

  modified <- vapply(html_files, function(f) {
    if (!file.exists(f)) {
      return(FALSE)
    }
    abs <- normalizePath(f)
    if (!startsWith(abs, root)) {
      return(FALSE)
    }
    rel <- substring(abs, nchar(root) + 1)
    add_canonical_link_in_file(abs, canonical_url(rel, site_url))
  }, logical(1))

  sum(modified)
}

#' Check that every page in the sitemap declares itself canonical.
#'
#' @param site_root The rendered site (`_book`), containing sitemap.xml.
#' @param site_url The book's `site-url`.
#' @return Character vector of problems, empty when every page passes.
check_canonical_links <- function(site_root, site_url) {
  sitemap <- file.path(site_root, "sitemap.xml")
  if (!file.exists(sitemap)) {
    return(sprintf("%s is missing", sitemap))
  }

  sitemap_text <- .canonical_link_read(sitemap)
  locs <- regmatches(
    sitemap_text,
    gregexpr("(?<=<loc>)[^<]+(?=</loc>)", sitemap_text, perl = TRUE)
  )[[1]]
  if (length(locs) == 0) {
    return(sprintf("%s lists no URLs", sitemap))
  }

  prefix <- canonical_url("", site_url)
  problems <- character(0)
  for (loc in locs) {
    if (!startsWith(loc, prefix)) {
      problems <- c(problems, sprintf("%s: not under %s", loc, prefix))
      next
    }
    path <- file.path(site_root, substring(loc, nchar(prefix) + 1))
    if (!file.exists(path)) {
      problems <- c(problems, sprintf("%s: %s is missing", loc, path))
      next
    }
    page_text <- .canonical_link_read(path)
    tags <- regmatches(
      page_text,
      gregexpr(.canonical_link_tag_re, page_text, perl = TRUE)
    )[[1]]
    if (length(tags) != 1) {
      problems <- c(problems, sprintf("%s: %d canonical links, expected 1", loc, length(tags)))
      next
    }
    href <- sub(.canonical_link_href_re, "\\1", tags)
    if (!identical(href, loc)) {
      problems <- c(problems, sprintf("%s: canonical points at %s", loc, href))
    }
  }
  problems
}
