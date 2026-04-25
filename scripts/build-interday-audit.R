#!/usr/bin/env Rscript
# build-interday-audit.R
#
# Regenerates workflow/inter-day-refs.csv — the authoritative list of every
# "Day N page M" reference in content/ and a 30-item fuzzy-mention sample.
#
# Policy for this audit and its columns is documented in
# workflow/PATTERNS.md under "Inter-Day Cross-References".
#
# Usage (from repo root):
#   Rscript scripts/build-interday-audit.R

suppressPackageStartupMessages({
  library(fs)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
  library(dplyr)   # load last so dplyr::filter/dplyr::lag mask stats:: equivalents
})

set.seed(199)

repo_root <- fs::path_wd()
content_dir <- fs::path(repo_root, "content")
out_csv <- fs::path(repo_root, "workflow", "inter-day-refs.csv")

# ---------------------------------------------------------------------------
# 1. Gather every .qmd file and its lines
# ---------------------------------------------------------------------------

qmd_files <- fs::dir_ls(content_dir, recurse = TRUE, glob = "*.qmd")

read_lines_tbl <- function(path) {
  lines <- readLines(path, warn = FALSE)
  tibble(
    source_file = as.character(fs::path_rel(path, repo_root)),
    source_line = seq_along(lines),
    text = lines
  )
}

all_lines <- map(qmd_files, read_lines_tbl) |> list_rbind()

# ---------------------------------------------------------------------------
# Helper: turn a vector of strings into a tidy tibble of regex matches with
# named capture groups. stringr::str_match_all returns a list of matrices,
# which doesn't round-trip through unnest_* cleanly, so convert per-row.
# ---------------------------------------------------------------------------

extract_matches <- function(df, pattern, group_names) {
  df <- df |>
    mutate(.matches = str_match_all(text, pattern))
  rows <- purrr::map2(
    seq_len(nrow(df)),
    df$.matches,
    function(i, mat) {
      if (nrow(mat) == 0L) return(NULL)
      out <- tibble::as_tibble(mat[, -1L, drop = FALSE], .name_repair = "minimal")
      names(out) <- group_names
      out$match_text <- mat[, 1L]
      out$.row_id <- i
      out
    }
  )
  matches <- dplyr::bind_rows(rows)
  if (nrow(matches) == 0L) return(df[0, ] |> select(-.matches))
  meta <- df |> select(-.matches, -text)
  meta$.row_id <- seq_len(nrow(meta))
  dplyr::left_join(matches, meta, by = ".row_id") |>
    dplyr::bind_cols(text = df$text[matches$.row_id]) |>
    dplyr::select(-.row_id)
}

# ---------------------------------------------------------------------------
# 2. Index existing {#sec-pageN} anchors per day directory
# ---------------------------------------------------------------------------
#
# For each day-NN directory, collect every chapter file that contains a
# {#sec-pageN} anchor (either attached to a heading or as a bare []{#sec-...}
# marker). When resolving a "Day N page M" reference, we look up whether any
# chapter in that target day already carries #sec-pageM.

anchors <- extract_matches(
  all_lines,
  pattern = "\\{#sec-page([0-9]+)\\}",
  group_names = "target_page_chr"
) |>
  transmute(
    source_file,
    source_line,
    target_page = as.integer(target_page_chr)
  ) |>
  dplyr::filter(!is.na(target_page))

# A single lookup table keyed by (day_dir, target_page) -> list of candidate
# files. In practice each (day, page) pair lives in one file; if it ever lives
# in several, the audit row flags multiple candidates in `notes`.
anchors_by_day <- anchors |>
  mutate(day_dir = str_extract(source_file, "(content/days/day-[0-9]+|content/appendix)"))  |>
  distinct(day_dir, target_page, source_file) |>
  group_by(day_dir, target_page) |>
  summarise(
    target_file = paste(sort(unique(source_file)), collapse = " | "),
    n_candidates = n(),
    .groups = "drop"
  )

# ---------------------------------------------------------------------------
# 3. Extract concrete "Day N page M" references (multiple per line allowed)
# ---------------------------------------------------------------------------

concrete <- extract_matches(
  all_lines,
  pattern = "([Dd]ay)\\s+([0-9]+)\\s+page\\s+([0-9]+)",
  group_names = c("day_word", "target_day_chr", "target_page_chr")
) |>
  transmute(
    source_file,
    source_line,
    match_text,
    target_day = as.integer(target_day_chr),
    target_page = as.integer(target_page_chr),
    context = str_trim(text)
  ) |>
  mutate(
    context = if_else(
      str_length(context) > 200,
      paste0(str_sub(context, 1, 197), "..."),
      context
    )
  )

# Join against the anchor index to autofill target_file and anchor_present.
concrete <- concrete |>
  mutate(
    target_day_dir = sprintf("content/days/day-%02d", target_day)
  ) |>
  left_join(
    anchors_by_day,
    by = c(target_day_dir = "day_dir", target_page = "target_page")
  ) |>
  mutate(
    anchor_present = if_else(!is.na(target_file), "Y", "N"),
    kind = "concrete",
    decision = NA_character_,
    notes = case_when(
      !is.na(n_candidates) & n_candidates > 1 ~
        sprintf("multiple candidate anchors: %s", target_file),
      .default = NA_character_
    )
  ) |>
  select(
    kind,
    source_file,
    source_line,
    match_text,
    target_day,
    target_page,
    target_file,
    anchor_present,
    decision,
    notes,
    context
  )

# ---------------------------------------------------------------------------
# 4. 30-item fuzzy-mention sample
# ---------------------------------------------------------------------------
#
# Captures whole-day mentions that are *not* immediately followed by "page".
# Includes common lead-ins ("see", "on", "we saw on", "from"). The idea is a
# representative sample, not exhaustive — so sample 30 lines rather than
# trying to classify everything.

fuzzy_re <- "\\b([Dd]ay)\\s+([0-9]+)\\b(?!\\s+page)"

fuzzy_all <- extract_matches(
  all_lines,
  pattern = fuzzy_re,
  group_names = c("day_word", "target_day_chr")
) |>
  transmute(
    source_file,
    source_line,
    match_text,
    target_day = as.integer(target_day_chr),
    context = str_trim(text)
  ) |>
  # Drop lines that are part of a heading, YAML, or code fence — they are
  # almost never prose cross-references.
  dplyr::filter(
    !str_detect(context, "^---"),
    !str_detect(context, "^```"),
    !str_detect(context, "^#{1,6}\\s")
  ) |>
  mutate(
    context = if_else(
      str_length(context) > 200,
      paste0(str_sub(context, 1, 197), "..."),
      context
    )
  )

n_sample <- min(30, nrow(fuzzy_all))
fuzzy_sample <- fuzzy_all |>
  slice_sample(n = n_sample) |>
  arrange(source_file, source_line) |>
  mutate(
    target_page = NA_integer_,
    target_file = NA_character_,
    anchor_present = NA_character_,
    kind = "fuzzy",
    decision = NA_character_,
    notes = NA_character_
  ) |>
  select(
    kind,
    source_file,
    source_line,
    match_text,
    target_day,
    target_page,
    target_file,
    anchor_present,
    decision,
    notes,
    context
  )

# ---------------------------------------------------------------------------
# 5. Write CSV
# ---------------------------------------------------------------------------

out <- bind_rows(
  concrete |> arrange(source_file, source_line),
  fuzzy_sample
)

fs::dir_create(fs::path_dir(out_csv))
write_csv(out, out_csv, na = "")

message(sprintf(
  "Wrote %s — %d concrete refs, %d fuzzy sampled (of %d fuzzy matches in total).",
  fs::path_rel(out_csv, repo_root),
  sum(out$kind == "concrete"),
  sum(out$kind == "fuzzy"),
  nrow(fuzzy_all)
))

# Autofill summary — useful for judging how much anchor infrastructure needs
# adding during #200/#201.
autofill_summary <- out |>
  dplyr::filter(kind == "concrete") |>
  count(anchor_present, name = "n")
message("Anchor-present distribution for concrete refs:")
print(autofill_summary)
