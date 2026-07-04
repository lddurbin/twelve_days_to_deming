#!/usr/bin/env Rscript
# build-draft-glossary.R
#
# Regenerates glossary/draft-glossary.csv (issue #416): merges the seed's
# measured frequency/context (#413 + #414) with un-seeded discovered
# candidates (#415) into the single deliverable the reviewer lock (#327)
# consumes. Idempotent — re-running against an unchanged corpus produces a
# byte-identical file.
#
# Also applies glossary/discovery-exclusions.csv, a curated list of
# discovered candidates confirmed to be generic English collocations (not
# domain terminology) -- these are dropped before ever reaching the draft,
# the same way an already-seeded term is.
#
# Usage (from repo root):
#   Rscript scripts/build-draft-glossary.R

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
if (is.na(.file_arg)) stop("Run this script with Rscript, not source().")
.this_file <- sub("^--file=", "", .file_arg)
.script_dir <- dirname(normalizePath(.this_file))
repo_root <- dirname(.script_dir)

source(file.path(repo_root, "R", "translation", "glossary-corpus.R"))
source(file.path(repo_root, "R", "translation", "glossary-assemble.R"))

seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

exclusions_path <- file.path(repo_root, "glossary", "discovery-exclusions.csv")
exclusions <- if (file.exists(exclusions_path)) {
  read.csv(exclusions_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
} else {
  NULL
}

# glossary_segments() bakes its `root` argument into every segment's `file`
# column, which discover_candidates() then uses verbatim as the context
# snippet for ui-kind candidates. Scanning with the absolute repo_root would
# leak this machine's checkout path into the committed CSV, breaking
# cross-machine idempotence -- scan with a relative root instead.
#
# setwd() here is safe only because it never runs under source(): the
# is.na(.file_arg) guard above already stops that path, so this always
# executes once under Rscript and on.exit() restores the wd before exit.
.orig_wd <- setwd(repo_root)
on.exit(setwd(.orig_wd), add = TRUE)
segments <- glossary_segments(".")

draft <- build_draft_glossary(segments, seed, exclusions = exclusions)

out_path <- file.path(repo_root, "glossary", "draft-glossary.csv")
write.csv(draft, out_path, row.names = FALSE)

cat(sprintf("Wrote %d rows to %s\n", nrow(draft), out_path))
