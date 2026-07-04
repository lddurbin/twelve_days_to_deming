#!/usr/bin/env Rscript
# prepare-glossary-review.R
#
# Regenerates glossary/glossary-for-review.csv (issue #327): adds fillable
# approved_fr/decision/reviewer_notes columns to the assembled draft (#416)
# for the native French speaker to complete. Safe to re-run after the draft
# changes -- any decisions already recorded in the existing review file are
# preserved by term_en, never clobbered.
#
# Usage (from repo root):
#   Rscript scripts/prepare-glossary-review.R

# write.csv()'s defaults break this file for its actual reader (a
# non-technical reviewer opening it in Excel): no BOM means Excel guesses
# the legacy system encoding instead of UTF-8, mangling every accented
# character (e.g. "expérience" -> "exp√©rience"); na = "NA" (the default)
# fills every not-yet-decided cell with the literal text "NA" instead of
# leaving it blank for them to fill in.
write_csv_utf8_bom <- function(df, path) {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  write.csv(df, tmp, row.names = FALSE, fileEncoding = "UTF-8", na = "")
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(readBin(tmp, "raw", file.size(tmp)), con)
}

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
if (is.na(.file_arg)) stop("Run this script with Rscript, not source().")
.this_file <- sub("^--file=", "", .file_arg)
.script_dir <- dirname(normalizePath(.this_file))
repo_root <- dirname(.script_dir)

source(file.path(repo_root, "R", "translation", "glossary-review.R"))
source(file.path(repo_root, "R", "translation", "glossary-lock.R"))

draft <- read.csv(
  file.path(repo_root, "glossary", "draft-glossary.csv"),
  stringsAsFactors = FALSE, fileEncoding = "UTF-8"
)

out_path <- file.path(repo_root, "glossary", "glossary-for-review.csv")
existing <- if (file.exists(out_path)) {
  read.csv(out_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
} else {
  NULL
}

review <- prepare_review_glossary(draft, existing)
write_csv_utf8_bom(review, out_path)

n_unresolved <- length(find_unresolved(review))
cat(sprintf(
  "Wrote %d rows to %s (%d pre-resolved, %d awaiting review)\n",
  nrow(review), out_path, nrow(review) - n_unresolved, n_unresolved
))
