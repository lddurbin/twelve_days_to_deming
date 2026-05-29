#!/usr/bin/env Rscript
# roundtrip.R
#
# Identity round-trip gate for the prose extract/reinject toolchain (#323).
# Extracts every translatable segment from every `.qmd` in the corpus, reinjects
# each segment's ORIGINAL text, and asserts the reconstructed file is
# byte-identical to the source. Exits non-zero on any mismatch.
#
# Usage (from repo root):
#   Rscript R/translation/roundtrip.R
#
# Optional: pass `--json <path>` to also write the full extraction sidecar for
# inspection (one object per file).

# Resolve this script's own directory so it works regardless of caller CWD.
.this_file <- (function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) return(normalizePath(sub("^--file=", "", m[1])))
  NA_character_
})()
.script_dir <- if (!is.na(.this_file)) dirname(.this_file) else file.path("R", "translation")

suppressPackageStartupMessages({
  source(file.path(.script_dir, "prose-extract.R"))
})

args <- commandArgs(trailingOnly = TRUE)
json_out <- NULL
if (length(args) >= 2 && args[1] == "--json") json_out <- args[2]

# The gate covers BOTH the .qmd corpus (prose + in-chunk r-string segments) and
# the .R helper corpus (default-label r-string segments) — see issues #323/#324.
files <- c(qmd_corpus("."), r_corpus("."))
if (length(files) == 0) stop("no source files found in corpus")

results <- vector("list", length(files))
fail <- 0L
total_segments <- 0L
sidecar <- list()

for (k in seq_along(files)) {
  f <- files[[k]]
  rel <- sub("^\\./", "", f)
  r <- roundtrip_file(f, rel_path = rel)
  results[[k]] <- r
  total_segments <- total_segments + r$n_segments
  if (!isTRUE(r$ok)) {
    fail <- fail + 1L
    cat(sprintf("FAIL  %s  (first diff byte %s; lens orig=%s rebuilt=%s)\n",
                rel, r$first_diff_byte, r$orig_len, r$rebuilt_len))
  }
  if (!is.null(json_out)) {
    sidecar[[rel]] <- if (grepl("[.][Rr]$", f)) extract_r_file(f, rel_path = rel)
                      else extract_qmd(f, rel_path = rel)
  }
}

passed <- length(files) - fail
cat(sprintf("\nIdentity round-trip: %d/%d files byte-identical (%d segments extracted).\n",
            passed, length(files), total_segments))

if (!is.null(json_out)) {
  jsonlite::write_json(sidecar, json_out, auto_unbox = FALSE, pretty = TRUE)
  cat(sprintf("Wrote extraction sidecar -> %s\n", json_out))
}

if (fail > 0L) {
  cat(sprintf("\n%d file(s) FAILED the byte-identical gate.\n", fail))
  quit(status = 1L)
}
cat("PASS: all files byte-identical.\n")
