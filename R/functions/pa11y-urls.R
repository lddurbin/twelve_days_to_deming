# Generate .pa11yci.json's `urls` array from _quarto-en.yml's chapter list,
# and flag any essay left out of it. See #630 — Phase 0 of #628's
# blog-location recommendation, docs/blog-location-spike.md.
#
# Only `urls` is generated. `.pa11yci.json`'s `defaults` block (the WCAG
# standard, timeouts, and its four ignores) is read back from the existing
# file and carried through unchanged, so it stays hand-maintained without
# being duplicated into this script.
#
# `pa11y_urls_orphaned_essays()` backs the essays orphan check described in
# the spike: in a book project, a .qmd under the essays directory that
# never made it into `chapters:` renders successfully but is silently
# absent from the site, the listing page, and the RSS feed — no error, no
# warning. This script already parses and flattens the chapter list for the
# URL generation above, so the assertion is nearly free here.

source(here::here("R/functions/llms-txt.R"))

.pa11y_urls_base <- "http://localhost:8765"

# Non-chapter URLs pa11y should still cover, keyed by the chapter path they
# vary from. Each is inserted immediately after that chapter's own URL.
.pa11y_urls_extras <- list(
  "share-your-experience.qmd" = "share-your-experience.html?submitted=1"
)

.pa11y_urls_essays_dir <- "essays"

#' A chapter path's pa11y URL. The book's index page renders to index.html
#' on disk but is served — and tested — at the site root.
.pa11y_urls_page_url <- function(path, base = .pa11y_urls_base) {
  if (identical(path, "index.qmd")) {
    return(paste0(base, "/"))
  }
  paste0(base, "/", sub(.llms_txt_ext_re, ".html", path))
}

#' Flatten `_quarto-en.yml`'s chapters + appendices into pa11y URLs, in
#' document order, with each path's extras (if any) immediately following.
pa11y_urls_build <- function(quarto_en_yml = "_quarto-en.yml") {
  book <- yaml::read_yaml(quarto_en_yml)$book
  paths <- c(
    .llms_txt_flatten_paths(book$chapters),
    .llms_txt_flatten_paths(book$appendices)
  )

  urls <- character(0)
  for (path in paths) {
    urls <- c(urls, .pa11y_urls_page_url(path))
    extra <- .pa11y_urls_extras[[path]]
    if (!is.null(extra)) {
      urls <- c(urls, paste0(.pa11y_urls_base, "/", extra))
    }
  }
  urls
}

#' Any .qmd under the essays directory missing from `chapters:` — scoped to
#' that directory only, never repo-wide: content-fr/ and the FR profile
#' legitimately hold .qmd files outside the EN chapter list.
#'
#' Deliberately checks `book$chapters` only, not `book$appendices`: essays
#' belong in `chapters:`, never `appendices:` (#637) — appendices collapse
#' into llms.txt's "Optional" section, the wrong signal for original essays.
#' An essay wrongly filed under `appendices:` would still render (so it
#' isn't the silent-drop failure this check exists to catch) but would be
#' reported here as an orphan, since it's absent from `chapters:`.
pa11y_urls_orphaned_essays <- function(quarto_en_yml = "_quarto-en.yml",
                                       essays_dir = .pa11y_urls_essays_dir) {
  if (!dir.exists(essays_dir)) {
    return(character(0))
  }
  book <- yaml::read_yaml(quarto_en_yml)$book
  chapters <- .llms_txt_flatten_paths(book$chapters)
  essays <- list.files(essays_dir, pattern = "\\.qmd$", recursive = TRUE)
  setdiff(file.path(essays_dir, essays), chapters)
}

.pa11y_urls_read_raw <- function(path) {
  readChar(path, file.info(path)$size, useBytes = TRUE)
}

#' Rebuild .pa11yci.json's full contents: the existing file's `defaults`
#' block verbatim, plus a freshly generated `urls`.
pa11y_urls_json <- function(quarto_en_yml = "_quarto-en.yml",
                            pa11yci_path = ".pa11yci.json") {
  existing <- jsonlite::fromJSON(pa11yci_path, simplifyVector = FALSE)
  existing$urls <- as.list(pa11y_urls_build(quarto_en_yml))
  paste0(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
}

#' Whether pa11yci_path already matches a fresh regeneration.
pa11y_urls_up_to_date <- function(quarto_en_yml = "_quarto-en.yml",
                                  pa11yci_path = ".pa11yci.json") {
  identical(
    pa11y_urls_json(quarto_en_yml, pa11yci_path),
    .pa11y_urls_read_raw(pa11yci_path)
  )
}

#' Write the regenerated .pa11yci.json to disk.
pa11y_urls_write <- function(pa11yci_path = ".pa11yci.json",
                             quarto_en_yml = "_quarto-en.yml") {
  content <- pa11y_urls_json(quarto_en_yml, pa11yci_path)
  writeChar(content, pa11yci_path, eos = NULL, useBytes = TRUE)
  invisible(pa11yci_path)
}
