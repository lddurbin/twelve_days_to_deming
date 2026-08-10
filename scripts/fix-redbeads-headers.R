#!/usr/bin/env Rscript
#
# fix-redbeads-headers.R — project post-render step (see #586)
#
# Quarto sets QUARTO_PROJECT_OUTPUT_FILES to a newline-separated list of
# every file it just rendered, relative to the project root. This corrects
# the `headers` attribute that gt (pinned at 1.3.0) emits in the wrong
# token order — and referencing an unsanitised column name — on every
# red-beads results table's <td> cells. See
# R/functions/redbeads-headers-fix.R for why, and for the actual fix logic
# — this file is just the QUARTO_PROJECT_OUTPUT_FILES plumbing so that
# logic stays unit-testable.

source(here::here("R/functions/redbeads-headers-fix.R"))

output_files <- strsplit(Sys.getenv("QUARTO_PROJECT_OUTPUT_FILES"), "\n")[[1]]

if (all(nchar(trimws(output_files)) == 0)) {
  # Only happens if this is run outside a Quarto post-render context (e.g.
  # by hand, or from a CI step that doesn't chain through Quarto). Silent
  # no-ops here are exactly what makes a misfiring hook hard to diagnose.
  message("fix-redbeads-headers.R: QUARTO_PROJECT_OUTPUT_FILES is empty — nothing to fix")
} else {
  fixed_count <- fix_redbeads_headers(output_files)
  if (fixed_count > 0) {
    cat(sprintf(
      "fix-redbeads-headers.R: corrected gt headers attribute ordering on %d page(s)\n",
      fixed_count
    ))
  }
}
