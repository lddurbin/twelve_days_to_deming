# Assemble the deviations log from per-entry source files in
# docs/deviations/. Called from a chunk in changes-from-source.qmd so the
# full log renders into the site at build time — no committed build
# artifact, no rebase tax on a stitched file.
#
# Sort order: filenames sorted descending. The YYYY-MM-DD prefix gives
# newest-first chronological order across days; within the same date,
# entries fall in alphabetical order by slug.

deviations_log_assemble <- function(deviations_dir = "docs/deviations",
                                    downshift_headings = TRUE) {
  if (!dir.exists(deviations_dir)) {
    stop("Deviations directory not found: ", deviations_dir)
  }

  entry_files <- list.files(
    deviations_dir,
    pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\\.md$",
    full.names = TRUE
  )
  entry_files <- sort(entry_files, decreasing = TRUE)

  if (length(entry_files) == 0L) {
    return(character(0))
  }

  entry_blocks <- lapply(seq_along(entry_files), function(i) {
    body <- readLines(entry_files[[i]], encoding = "UTF-8")
    if (downshift_headings) {
      body <- sub("^## ", "### ", body)
    }
    if (i == 1L) body else c("", "---", "", body)
  })

  unlist(entry_blocks)
}

deviations_log_emit <- function(deviations_dir = "docs/deviations",
                                downshift_headings = TRUE) {
  lines <- deviations_log_assemble(deviations_dir, downshift_headings)
  cat(lines, sep = "\n")
  invisible(lines)
}
