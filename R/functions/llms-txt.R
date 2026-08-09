# Generate llms.txt (https://llmstxt.org) at the project root from the
# chapter list in _quarto-en.yml and each chapter's own front matter — see
# #511. Nothing here is hand-maintained: the moment #497's per-page
# `pagetitle`/`description` fields change, regenerating this file picks the
# change up for free.
#
# Runs as a project pre-render step (scripts/generate-llms-txt.R) rather
# than a knitr chunk like R/functions/deviations-log.R: llms.txt is a
# standalone file at the project root, not content rendered into any one
# page, and needs to exist before Quarto's `resources:` copy step runs.
#
# Link text uses each page's `pagetitle`, not its `title`. `title` is
# Neave's original heading, kept verbatim per this repo's transcription
# policy (e.g. "PLEASE START HERE", "DAY 1 (morning): THE OVERTURE") — good
# for on-page display, unreadable as a link list. `pagetitle` is the
# human-written field #497 added specifically for exactly this kind of
# external-facing index.
#
# Appendix content (book$appendices) is collapsed into a single "## Optional"
# section rather than one heading per appendix part: llmstxt.org reserves
# "Optional" for exactly this — material a consumer can skip for a shorter
# read — and that's a genuine fit for material this course itself already
# treats as supplementary.

.llms_txt_ext_re <- "\\.qmd$"

.llms_txt_page_meta <- function(path) {
  fm <- rmarkdown::yaml_front_matter(path)
  list(
    path = path,
    title = fm$pagetitle %||% fm$title %||% path,
    description = fm$description
  )
}

.llms_txt_url <- function(path, site_url) {
  paste0(site_url, "/", sub(.llms_txt_ext_re, ".html", path))
}

.llms_txt_bullet <- function(path, site_url) {
  meta <- .llms_txt_page_meta(path)
  link <- sprintf("- [%s](%s)", meta$title, .llms_txt_url(path, site_url))
  if (is.null(meta$description) || !nzchar(meta$description)) {
    return(link)
  }
  paste0(link, ": ", meta$description)
}

# A "part" entry's own `part:` value is either a title string ("Day 1: The
# Overture") or, in the appendices, a .qmd path that is itself a page (e.g.
# content/appendix/optional-extras/00-introduction.qmd). Only the latter
# case resolves to a heading via front matter and contributes its own path
# to the flattened page list.
.llms_txt_is_part_path <- function(part_value) {
  grepl(.llms_txt_ext_re, part_value)
}

#' Flatten a `chapters:`/`appendices:` list from _quarto-en.yml into a flat,
#' ordered vector of chapter .qmd paths, resolving one level of `part:`
#' nesting (the only depth present in this project's config).
.llms_txt_flatten_paths <- function(entries) {
  paths <- character(0)
  for (entry in entries) {
    if (is.character(entry)) {
      paths <- c(paths, entry)
    } else if (!is.null(entry$chapters)) {
      part_paths <- if (.llms_txt_is_part_path(entry$part)) entry$part else character(0)
      paths <- c(paths, part_paths, unlist(entry$chapters, use.names = FALSE))
    } else {
      stop("llms-txt: unrecognised chapters entry: ", paste(names(entry), collapse = ", "))
    }
  }
  paths
}

#' Group a `chapters:` list into a single leading block of ungrouped pages
#' (wherever they fall in the list — e.g. front-matter pages before Day 1
#' and meta pages like privacy after Day 12 both land here, so the heading
#' only ever appears once) followed by one block per `part:`, in document
#' order. Each block is `list(heading = ..., paths = ...)`.
.llms_txt_chapter_blocks <- function(chapters, ungrouped_heading = "Pages") {
  part_blocks <- list()
  ungrouped <- character(0)
  for (entry in chapters) {
    if (is.character(entry)) {
      ungrouped <- c(ungrouped, entry)
    } else if (!is.null(entry$chapters)) {
      heading <- if (.llms_txt_is_part_path(entry$part)) {
        .llms_txt_page_meta(entry$part)$title
      } else {
        entry$part
      }
      part_paths <- if (.llms_txt_is_part_path(entry$part)) entry$part else character(0)
      part_blocks[[length(part_blocks) + 1]] <- list(
        heading = heading,
        paths = c(part_paths, unlist(entry$chapters, use.names = FALSE))
      )
    } else {
      stop("llms-txt: unrecognised chapters entry: ", paste(names(entry), collapse = ", "))
    }
  }
  blocks <- list()
  if (length(ungrouped) > 0) {
    blocks[[1]] <- list(heading = ungrouped_heading, paths = ungrouped)
  }
  c(blocks, part_blocks)
}

.llms_txt_render_block <- function(block, site_url) {
  c(
    paste0("## ", block$heading),
    "",
    vapply(block$paths, .llms_txt_bullet, character(1), site_url = site_url, USE.NAMES = FALSE),
    ""
  )
}

#' Build llms.txt's full contents as a character vector of lines.
#'
#' @param quarto_yml Path to the top-level Quarto config (site title,
#'   description, and site-url live here).
#' @param quarto_en_yml Path to the language-profile config holding the
#'   authoritative `book$chapters`/`book$appendices` list.
#' @return Character vector of lines, ready for `writeLines()`.
llms_txt_build <- function(quarto_yml = "_quarto.yml",
                           quarto_en_yml = "_quarto-en.yml") {
  site <- yaml::read_yaml(quarto_yml)$book
  book <- yaml::read_yaml(quarto_en_yml)$book

  lines <- c(
    paste0("# ", site$title),
    "",
    paste0("> ", trimws(site$description)),
    ""
  )

  chapter_blocks <- .llms_txt_chapter_blocks(book$chapters)
  for (block in chapter_blocks) {
    lines <- c(lines, .llms_txt_render_block(block, site[["site-url"]]))
  }

  appendix_block <- list(heading = "Optional", paths = .llms_txt_flatten_paths(book$appendices))
  lines <- c(lines, .llms_txt_render_block(appendix_block, site[["site-url"]]))

  # Exactly one trailing blank line becomes the file's final newline; drop
  # any others so blocks don't accumulate doubled blank lines between them.
  while (length(lines) > 0 && !nzchar(lines[length(lines)])) {
    lines <- lines[-length(lines)]
  }
  lines
}

#' Build and write llms.txt.
#'
#' @param path Output path for the generated file.
#' @inheritParams llms_txt_build
#' @return Invisibly, the path written.
llms_txt_write <- function(path = "llms.txt",
                           quarto_yml = "_quarto.yml",
                           quarto_en_yml = "_quarto-en.yml") {
  lines <- llms_txt_build(quarto_yml, quarto_en_yml)
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}
