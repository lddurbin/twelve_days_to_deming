#!/usr/bin/env Rscript
# build-draft-glossary.R
#
# Regenerates glossary/draft-glossary.csv (issue #416): merges the seed's
# measured frequency/context (#413 + #414) with un-seeded discovered
# candidates (#415) into the single deliverable the reviewer lock (#327)
# consumes. Idempotent — re-running against an unchanged corpus produces a
# byte-identical file.
#
# Usage (from repo root):
#   Rscript scripts/build-draft-glossary.R

.this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.script_dir <- dirname(normalizePath(.this_file))
repo_root <- dirname(.script_dir)

source(file.path(repo_root, "R", "translation", "glossary-corpus.R"))
source(file.path(repo_root, "R", "translation", "glossary-assemble.R"))

seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)
segments <- glossary_segments(repo_root)
draft <- build_draft_glossary(segments, seed)

out_path <- file.path(repo_root, "glossary", "draft-glossary.csv")
write.csv(draft, out_path, row.names = FALSE)

cat(sprintf("Wrote %d rows to %s\n", nrow(draft), out_path))
