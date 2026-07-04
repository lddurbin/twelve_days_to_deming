#!/usr/bin/env Rscript
# lock-glossary.R
#
# Locks the reviewer-completed glossary/glossary-for-review.csv (issue #327)
# into glossary/approved-glossary.json, the machine-readable termbase that
# becomes a hard constraint for all downstream translation work. Fails
# loudly -- non-zero exit, every offending term_en listed -- if any row is
# still undecided; no approved-glossary.json is written on failure.
#
# Usage (from repo root, after the reviewer has completed the CSV):
#   Rscript scripts/lock-glossary.R

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
if (is.na(.file_arg)) stop("Run this script with Rscript, not source().")
.this_file <- sub("^--file=", "", .file_arg)
.script_dir <- dirname(normalizePath(.this_file))
repo_root <- dirname(.script_dir)

source(file.path(repo_root, "R", "translation", "glossary-lock.R"))

review_path <- file.path(repo_root, "glossary", "glossary-for-review.csv")
if (!file.exists(review_path)) {
  stop(sprintf(
    "%s does not exist yet -- run scripts/prepare-glossary-review.R first.",
    review_path
  ))
}
review <- read.csv(review_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")

termbase <- lock_glossary(review)

out_path <- file.path(repo_root, "glossary", "approved-glossary.json")
jsonlite::write_json(termbase, out_path, auto_unbox = TRUE, pretty = TRUE, null = "null")

cat(sprintf("Locked %d terms to %s\n", length(termbase), out_path))
