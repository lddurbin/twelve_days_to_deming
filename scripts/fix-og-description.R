#!/usr/bin/env Rscript
#
# fix-og-description.R — project post-render step (see #521)
#
# Quarto sets QUARTO_PROJECT_OUTPUT_FILES to a newline-separated list of
# every file it just rendered, relative to the project root. This copies
# each rendered page's (correct) <meta name="description"> content into its
# og:description and twitter:description tags, which Quarto otherwise
# leaves pointed at the book-level description regardless of the page. See
# R/functions/og-description-fix.R for why, and for the actual fix logic —
# this file is just the QUARTO_PROJECT_OUTPUT_FILES plumbing so that logic
# stays unit-testable.

source(here::here("R/functions/og-description-fix.R"))

output_files <- strsplit(Sys.getenv("QUARTO_PROJECT_OUTPUT_FILES"), "\n")[[1]]

if (all(nchar(trimws(output_files)) == 0)) {
  # Only happens if this is run outside a Quarto post-render context (e.g.
  # by hand, or from a CI step that doesn't chain through Quarto). Silent
  # no-ops here are exactly what makes a misfiring hook hard to diagnose.
  message("fix-og-description.R: QUARTO_PROJECT_OUTPUT_FILES is empty — nothing to fix")
} else {
  fixed_count <- fix_og_description(output_files)
  if (fixed_count > 0) {
    cat(sprintf(
      "fix-og-description.R: corrected og:description/twitter:description on %d page(s)\n",
      fixed_count
    ))
  }
}
