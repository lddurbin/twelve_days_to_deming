#!/usr/bin/env bash
#
# scorer-version.sh — the single definition of `scorer_version`, sourced by
# both the writer (scripts/validate-transcription.sh, which stamps it into
# workflow/validation/results/*.yml) and the reader
# (scripts/check-validation-staleness.sh, which compares recorded values
# against it). One definition, two consumers, so they cannot drift apart —
# see issue #737.
#
# Before #737 this was `git hash-object scripts/lib/paragraph_similarity.py`
# alone, which understated the pipeline: PDF text extraction, QMD stripping,
# and the paragraph-length filters all live in validate-transcription.sh, and
# a behaviour-changing edit to any of them produced results the staleness
# check happily called fresh.
#
# Usage:
#   source "$REPO_ROOT/scripts/lib/scorer-version.sh"
#   version=$(compute_scorer_version "$REPO_ROOT")

# Every file whose content can change what a comparison run reports. Paths are
# repo-relative. This is the one line to edit when comparator behaviour moves
# into a new module — as the strip_qmd() port in #739 did, adding qmd_strip.py,
# the paragraph-assembly port in #741 did, adding paragraphs.py, the
# short-content pass in #742 did, adding short_content.py, and the
# footnote-callout suppression in #755 did, adding pdf_callouts.py. A file
# belongs here whether it decides what gets *flagged* or only what gets
# *reported*: both change what a recorded result says.
#
# Deliberately NOT self-referential: this file computes the version, so any
# edit here that could change the value already changes it (adding or removing
# an entry changes the manifest; changing the hashing changes the digest).
# Listing it would only add false staleness on comment and docstring edits.
#
# .github/workflows/validation-staleness.yml must have a `paths:` entry for
# every file below, or an edit to one won't trigger the check that catches it.
# tests/test_scorer_version.py enforces that.
SCORER_VERSION_FILES=(
  scripts/lib/paragraph_similarity.py
  scripts/lib/paragraphs.py
  scripts/lib/pdf_callouts.py
  scripts/lib/qmd_strip.py
  scripts/lib/short_content.py
  scripts/validate-transcription.sh
)

# Print a single content hash covering every file in SCORER_VERSION_FILES.
#
# Hashes a sorted "<path> <blob-hash>" manifest rather than the concatenated
# file bytes: sorting makes the result independent of the array's order, and
# including the path means a file joining or leaving the list moves the digest
# even if some other file's content happens to compensate. Uses git as the
# hashing tool because both callers already require it, so this adds no new
# dependency. Content hashes, not commit SHAs — an uncommitted local edit to
# the pipeline has to invalidate recorded results just as a merged one does.
compute_scorer_version() {
  local repo_root=$1
  local f
  local ok=1

  # Guard the empty case explicitly, because the two shells this runs in
  # disagree about it: bash 3.2 (macOS, where the validator is run by hand)
  # dies on the unbound expansion below, while bash 4.4+ (the CI runner)
  # expands it to nothing and cheerfully hashes the empty string into a
  # valid-looking 40-character answer for a pipeline covering no files.
  if [[ "${#SCORER_VERSION_FILES[@]}" -eq 0 ]]; then
    echo "scorer-version.sh: SCORER_VERSION_FILES is empty — nothing to hash." >&2
    return 1
  fi

  for f in "${SCORER_VERSION_FILES[@]}"; do
    if [[ ! -f "$repo_root/$f" ]]; then
      echo "scorer-version.sh: '$f' is listed in SCORER_VERSION_FILES but does not exist." >&2
      ok=0
    fi
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "scorer-version.sh: refusing to compute a scorer_version from an incomplete file list." >&2
    return 1
  fi

  for f in "${SCORER_VERSION_FILES[@]}"; do
    printf '%s %s\n' "$f" "$(git -C "$repo_root" hash-object "$repo_root/$f")"
  done | LC_ALL=C sort | git -C "$repo_root" hash-object --stdin
}
