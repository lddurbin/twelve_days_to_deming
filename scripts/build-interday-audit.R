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

qmd_files <- c(
  fs::dir_ls(content_dir, recurse = TRUE, glob = "*.qmd"),
  fs::dir_ls(repo_root, recurse = FALSE, glob = "*.qmd")
)

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
# 3b. Extract concrete "Appendix page N" references (#295)
# ---------------------------------------------------------------------------
#
# Parallel surface form to "Day N page M". Page numbers are *global* across
# the appendix (continuous numbering, not per-file): pages 2–6 live in
# 01-day-1.qmd, 7–13 in 02-day-2.qmd, 14–21 in 03-day-3.qmd, 22–23 in
# 04-day-4.qmd, 24–30 in 05-day-5.qmd, 31–37 in 06-day-7.qmd, 38 in
# 07-day-9.qmd, 39–40 in 08-day-10.qmd, 41–42 in 09-day-11.qmd, and
# 43+ in 10-optional-extras.qmd. Resolution is therefore page-number-based:
# look up which file contains {#sec-pageN}.

# Build the appendix-file × page anchor index from the existing anchors df.
appendix_anchor_lookup <- anchors |>
  dplyr::filter(stringr::str_detect(source_file, "^content/appendix/")) |>
  distinct(source_file, target_page) |>
  rename(target_file = source_file)

appendix_page <- extract_matches(
  all_lines,
  pattern = "Appendix pages?\\s+([0-9]+)",
  group_names = "target_page_chr"
) |>
  transmute(
    source_file,
    source_line,
    match_text,
    target_page = as.integer(target_page_chr),
    context = str_trim(text)
  ) |>
  mutate(
    # Already-linked sites: a markdown link wraps the match. Detected by
    # (a) literal "[<match_text>" appearing in the line — i.e. the match is
    # preceded by "[" — *and* (b) the line carrying a "](" link signature.
    # The two-clause form handles range-form linked sites like
    # "[Appendix pages 15–18](...)" without a position-aware regex.
    already_linked =
      stringr::str_detect(context, stringr::fixed(paste0("[", match_text))) &
        stringr::str_detect(context, stringr::fixed("](")),
    # Notation-example sites: the match is exact-bounded by scare quotes
    # (e.g. `"Appendix page 3"`) — these are demonstrations of the page-
    # reference convention itself rather than navigation pointers. Linking
    # them takes a reader to a page unrelated to the prose they were
    # reading. Today this only matches the puzzle paragraph in
    # `index.qmd`'s "Page references and call-outs" section.
    notation_example = stringr::str_detect(
      context,
      stringr::fixed(paste0('"', match_text, '"'))
    )
  ) |>
  left_join(appendix_anchor_lookup, by = "target_page") |>
  mutate(
    anchor_present = if_else(!is.na(target_file), "Y", "N"),
    kind = "appendix-page",
    target_day = NA_integer_,
    decision = case_when(
      already_linked ~ "already-linked",
      notation_example ~ "notation-example",
      anchor_present == "N" ~ "anchor-needed",
      .default = NA_character_
    ),
    notes = case_when(
      already_linked ~ "site already wraps match in markdown link",
      notation_example ~ "match is scare-quoted as a notation example",
      .default = NA_character_
    ),
    context = if_else(
      str_length(context) > 200,
      paste0(str_sub(context, 1, 197), "..."),
      context
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
  appendix_page |> arrange(source_file, source_line),
  fuzzy_sample
)

fs::dir_create(fs::path_dir(out_csv))
write_csv(out, out_csv, na = "")

message(sprintf(
  "Wrote %s — %d concrete refs, %d appendix-page refs, %d fuzzy sampled (of %d fuzzy matches in total).",
  fs::path_rel(out_csv, repo_root),
  sum(out$kind == "concrete"),
  sum(out$kind == "appendix-page"),
  sum(out$kind == "fuzzy"),
  nrow(fuzzy_all)
))

# Autofill summary — useful for judging how much anchor infrastructure needs
# adding during #200/#201/#295.
message("Anchor-present distribution for concrete refs:")
print(out |> dplyr::filter(kind == "concrete") |> count(anchor_present, name = "n"))

message("Decision distribution for appendix-page refs:")
print(out |>
  dplyr::filter(kind == "appendix-page") |>
  count(anchor_present, decision, name = "n"))

# ---------------------------------------------------------------------------
# 6. Validate every markdown link containing '#sec-' (#613)
# ---------------------------------------------------------------------------
#
# Two anchor namespaces exist — see PATTERNS.md "Inter-Day Cross-References":
#
#   - {#sec-pageN} is deliberately duplicated across all 12 days (every day
#     restarts its print-page numbering at 1), so a bare `](#sec-pageN)`
#     fragment is *always* forbidden — even when it happens to resolve to the
#     right page today — because Quarto resolves #sec- ids book-wide and the
#     id collides with every other day's #sec-pageN.
#   - {#sec-optional-extras-page-N} is unique across the whole Optional
#     Extras booklet (continuous 1–91 numbering), so a bare fragment is fine
#     there, but only for a genuine same-file link.
#
# The check below is namespace-agnostic: for any '#sec-' link (bare or
# explicit-path), resolve the file the anchor should live in — explicit path
# -> that path relative to the linking file's directory; bare fragment ->
# the linking file itself, since a bare fragment can only ever *correctly*
# mean "the anchor is here". Then verify the target file exists and actually
# defines that anchor. Separately, and unconditionally, flag any bare
# fragment whose id matches the Day pattern (^sec-page[0-9]+$) as a style
# violation even when it resolves correctly, per the "no same-file
# exception" rule in PATTERNS.md.

content_lines <- all_lines |> dplyr::filter(str_detect(source_file, "^content/"))

sec_links <- extract_matches(
  content_lines,
  pattern = "\\]\\(([^()#]*)#(sec-[A-Za-z0-9_-]+)\\)",
  group_names = c("link_path", "anchor_id")
)

# Every {#id} definition in the corpus (headings or bare []{#id} markers),
# keyed by the file it's defined in. Attributes after the id (e.g. the
# `.unnumbered` on some Optional Extras headings) are tolerated.
anchor_defs <- extract_matches(
  all_lines,
  pattern = "\\{#([A-Za-z0-9_-]+)(?:\\s[^}]*)?\\}",
  group_names = "anchor_id"
) |>
  distinct(source_file, anchor_id)

if (nrow(sec_links) > 0) {
  sec_links <- sec_links |>
    mutate(
      is_bare = link_path == "",
      target_file = if_else(
        is_bare,
        source_file,
        as.character(fs::path_norm(fs::path(fs::path_dir(source_file), link_path)))
      ),
      target_exists = fs::file_exists(fs::path(repo_root, target_file)),
      day_pattern_bare = is_bare & str_detect(anchor_id, "^sec-page[0-9]+$")
    ) |>
    dplyr::left_join(
      anchor_defs |> dplyr::mutate(anchor_defined = TRUE),
      by = c("target_file" = "source_file", "anchor_id")
    ) |>
    dplyr::mutate(anchor_defined = tidyr::replace_na(anchor_defined, FALSE))

  violations <- sec_links |>
    dplyr::filter(day_pattern_bare | !target_exists | !anchor_defined) |>
    dplyr::arrange(source_file, source_line)

  if (nrow(violations) > 0) {
    message(sprintf(
      "::error::Found %d invalid '#sec-' link(s) among %d checked in content/**/*.qmd.",
      nrow(violations), nrow(sec_links)
    ))
    purrr::pwalk(violations, function(...) {
      row <- list(...)
      reasons <- character(0)
      if (isTRUE(row$day_pattern_bare)) {
        reasons <- c(reasons, sprintf(
          "bare '#%s' fragment is forbidden — {#sec-pageN} ids repeat in every day, so PATTERNS.md requires an explicit file path even for a same-file link",
          row$anchor_id
        ))
      }
      if (!isTRUE(row$target_exists)) {
        reasons <- c(reasons, sprintf("target file '%s' does not exist", row$target_file))
      } else if (!isTRUE(row$anchor_defined)) {
        reasons <- c(reasons, sprintf(
          "'{#%s}' is not defined in '%s'", row$anchor_id, row$target_file
        ))
      }
      message(sprintf(
        "::error file=%s,line=%d::%s:%d — link '%s' — %s",
        row$source_file, row$source_line,
        row$source_file, row$source_line,
        row$match_text, paste(reasons, collapse = "; ")
      ))
    })
    message(
      "\nSee workflow/PATTERNS.md 'Inter-Day Cross-References' for the anchor conventions ",
      "(Day pages: {#sec-pageN}, always explicit path; Optional Extras: ",
      "{#sec-optional-extras-page-N}, bare only within the same file)."
    )
    quit(status = 1, save = "no")
  }

  message(sprintf(
    "All %d '#sec-' link(s) checked in content/**/*.qmd resolve correctly.",
    nrow(sec_links)
  ))
}
