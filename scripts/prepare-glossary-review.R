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

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
if (is.na(.file_arg)) stop("Run this script with Rscript, not source().")
.this_file <- sub("^--file=", "", .file_arg)
.script_dir <- dirname(normalizePath(.this_file))
repo_root <- dirname(.script_dir)

source(file.path(repo_root, "R", "translation", "glossary-review.R"))
source(file.path(repo_root, "R", "translation", "glossary-lock.R"))

draft <- read.csv(file.path(repo_root, "glossary", "draft-glossary.csv"), stringsAsFactors = FALSE)

out_path <- file.path(repo_root, "glossary", "glossary-for-review.csv")
existing <- if (file.exists(out_path)) read.csv(out_path, stringsAsFactors = FALSE) else NULL

review <- prepare_review_glossary(draft, existing)
write.csv(review, out_path, row.names = FALSE)

n_unresolved <- length(find_unresolved(review))
cat(sprintf(
  "Wrote %d rows to %s (%d pre-resolved, %d awaiting review)\n",
  nrow(review), out_path, nrow(review) - n_unresolved, n_unresolved
))
