#!/usr/bin/env Rscript
#
# add-canonical-links.R — project post-render step (see #896)
#
# Gives every page Quarto just rendered (QUARTO_PROJECT_OUTPUT_FILES) a
# self-referencing <link rel="canonical"> built from _quarto.yml's site-url.
# See R/functions/canonical-links.R for why and for the logic; this file is
# only the plumbing, so that logic stays unit-testable.
#
# With --check, it instead verifies the rendered _book/: every page in
# sitemap.xml must have exactly one canonical link, pointing at its own
# sitemap URL. CI runs that after rendering, so a Quarto upgrade that breaks
# the insertion fails the build instead of shipping pages without one.

source(here::here("R/functions/canonical-links.R"))

site_url <- yaml::read_yaml(here::here("_quarto.yml"))$book$`site-url`
site_root <- here::here("_book")

if ("--check" %in% commandArgs(trailingOnly = TRUE)) {
  problems <- check_canonical_links(site_root, site_url)
  if (length(problems) > 0) {
    cat("add-canonical-links.R --check failed:\n")
    cat(paste0("  ", problems, "\n"), sep = "")
    quit(status = 1)
  }
  cat("add-canonical-links.R --check: every sitemap page is self-canonical\n")
  quit(status = 0)
}

output_files <- strsplit(Sys.getenv("QUARTO_PROJECT_OUTPUT_FILES"), "\n")[[1]]

if (all(nchar(trimws(output_files)) == 0)) {
  message("add-canonical-links.R: QUARTO_PROJECT_OUTPUT_FILES is empty — nothing to do")
} else {
  added <- add_canonical_links(output_files, site_url, site_root)
  cat(sprintf("add-canonical-links.R: added a canonical link to %d page(s)\n", added))
}
