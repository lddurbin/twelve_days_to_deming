#!/usr/bin/env Rscript
#
# generate-pa11y-urls.R — regenerates .pa11yci.json's `urls` array from
# _quarto-en.yml's chapter list (see #630, Phase 0 of #628's blog-location
# recommendation, docs/blog-location-spike.md). Also asserts every essay
# .qmd is enumerated as a chapter: an essay left out of `chapters:` renders
# successfully but is silently dropped from the site, the listing page, and
# the RSS feed.
#
# Run with no arguments to regenerate .pa11yci.json in place, after editing
# `chapters:`/`appendices:`. Run with --check to verify the committed file
# is already current without writing — this is what CI runs, so a chapter
# added without regenerating fails the build.

source(here::here("R/functions/pa11y-urls.R"))

orphans <- pa11y_urls_orphaned_essays()
if (length(orphans) > 0) {
  cat("generate-pa11y-urls.R: essay(s) missing from _quarto-en.yml's chapters:\n")
  cat(paste0("  - ", orphans, "\n"), sep = "")
  quit(status = 1)
}

if ("--check" %in% commandArgs(trailingOnly = TRUE)) {
  if (!pa11y_urls_up_to_date()) {
    cat("generate-pa11y-urls.R: .pa11yci.json is stale: run `Rscript scripts/generate-pa11y-urls.R` and commit the result.\n")
    quit(status = 1)
  }
  cat("generate-pa11y-urls.R: .pa11yci.json is up to date.\n")
} else {
  path <- pa11y_urls_write()
  cat(sprintf("generate-pa11y-urls.R: wrote %s\n", path))
}
