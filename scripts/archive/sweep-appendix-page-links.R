#!/usr/bin/env Rscript
# sweep-appendix-page-links.R (one-shot for #295)
#
# Reads workflow/inter-day-refs.csv, finds every kind=appendix-page row with
# anchor_present=Y and decision empty (i.e. unlinked), and rewrites each
# source line in place to wrap the match in a markdown link to the
# corresponding {#sec-pageN} anchor.
#
# Path resolution uses fs::path_rel against the source file's directory:
#   content/days/day-XX/    → ../../appendix/0Y-day-X.qmd
#   index.qmd / welcome.qmd → content/appendix/0Y-day-X.qmd
#   content/appendix/...    → ../0Y-day-X.qmd  (none in scope — all linked)
#
# Multi-mention lines: matches already preceded by "[" are skipped, so the
# script is idempotent and safe to re-run.

suppressPackageStartupMessages({
  library(fs)
  library(stringr)
  library(readr)
  library(dplyr)
})

repo_root <- fs::path_wd()
csv_path  <- fs::path(repo_root, "workflow/inter-day-refs.csv")
csv <- readr::read_csv(csv_path, show_col_types = FALSE)

todo <- csv |>
  dplyr::filter(kind == "appendix-page",
                anchor_present == "Y",
                is.na(decision))

if (nrow(todo) == 0L) {
  message("No unlinked appendix-page sites in audit — nothing to sweep.")
  quit(status = 0)
}

resolve_relpath <- function(source_file, target_file) {
  src_dir <- fs::path_dir(source_file)
  as.character(fs::path_rel(target_file, src_dir))
}

# Per row: locate every "Appendix pages? <target_page>(–N)?" occurrence in
# the source line and wrap each one (unless already preceded by '[').
rewrite_line <- function(line, target_page, rel_path) {
  pat <- sprintf("\\bAppendix pages?\\s+%d(?:[\\-\\u2013][0-9]+)?\\b",
                 target_page)
  matches <- str_locate_all(line, pat)[[1]]
  if (nrow(matches) == 0L) return(list(line = line, hits = 0L))

  keep <- vapply(matches[, "start"], function(s) {
    s == 1L || str_sub(line, s - 1L, s - 1L) != "["
  }, logical(1))
  if (!any(keep)) return(list(line = line, hits = 0L))

  anchor <- sprintf("#sec-page%d", target_page)
  # Walk right-to-left so prior positions stay valid.
  for (k in rev(which(keep))) {
    s <- matches[k, "start"]
    e <- matches[k, "end"]
    orig <- str_sub(line, s, e)
    line <- paste0(
      str_sub(line, 1, s - 1L),
      sprintf("[%s](%s%s)", orig, rel_path, anchor),
      str_sub(line, e + 1L)
    )
  }
  list(line = line, hits = sum(keep))
}

total_hits <- 0L
for (sf in unique(todo$source_file)) {
  rows <- todo |> dplyr::filter(source_file == sf)
  path <- fs::path(repo_root, sf)
  lines <- readLines(path, warn = FALSE)

  file_hits <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    rel <- resolve_relpath(r$source_file, r$target_file)
    res <- rewrite_line(lines[r$source_line], r$target_page, rel)
    lines[r$source_line] <- res$line
    file_hits <- file_hits + res$hits
  }
  writeLines(lines, path, useBytes = TRUE)
  total_hits <- total_hits + file_hits
  message(sprintf("Updated %s — %d sites rewritten across %d audit rows",
                  sf, file_hits, nrow(rows)))
}

message(sprintf("Sweep complete: %d total link insertions across %d files.",
                total_hits, length(unique(todo$source_file))))
