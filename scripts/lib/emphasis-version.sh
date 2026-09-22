#!/usr/bin/env bash
#
# emphasis-version.sh — the single definition of `emphasis_version`, sourced
# by both the writer (scripts/check-emphasis.py, which stamps it into
# workflow/validation/emphasis/*.yml) and the reader
# (scripts/check-validation-staleness.sh, which compares recorded values
# against it). One definition, two consumers, so they cannot drift apart —
# the same coupling #737 established for `scorer_version`.
#
# ── Why this is separate from scorer_version ──
#
# The emphasis checker and the paragraph comparator answer different
# questions from different extractions: `pdftohtml -xml` and the pandoc AST
# here, `pdftotext` and qmd_strip.py there. Neither can change what the other
# reports. Folding them into one version would mean every edit to the
# emphasis checker restales all eighteen paragraph records — and under main's
# `strict: true` protection with no merge queue, that staleness is a real
# merge-ordering cost, not a compute one (see #734's "staleness tax" note).
# Two versions over two directories keeps each cost where it is earned.
#
# Usage:
#   source "$REPO_ROOT/scripts/lib/emphasis-version.sh"
#   version=$(compute_emphasis_version "$REPO_ROOT")

# Every file whose content can change what an emphasis run reports. Paths are
# repo-relative. This is the one line to edit when checker behaviour moves
# into a new module. undecodable_fonts.py is shared with scorer-version.sh
# (#852): it decides what text both pipelines read, so an edit to it
# restales both directories, as it should.
#
# .github/workflows/validation-staleness.yml must have a `paths:` entry for
# every file below, or an edit to one won't trigger the check that catches it.
# tests/test_scorer_version.py enforces that.
#
# Deliberately NOT self-referential, for the reason scorer-version.sh gives:
# any edit here that could change the value already changes it.
EMPHASIS_VERSION_FILES=(
  scripts/check-emphasis.py
  scripts/lib/emphasis.py
  scripts/lib/undecodable_fonts.py
)

# Print a single content hash covering every file in EMPHASIS_VERSION_FILES.
# Hashes a sorted "<path> <blob-hash>" manifest for the reasons
# compute_scorer_version() documents: order-independence, and a file joining
# or leaving the list moving the digest on its own.
compute_emphasis_version() {
  local repo_root=$1
  local f
  local ok=1

  # bash 3.2 (macOS, where this is run by hand) dies on an unbound expansion
  # where bash 4.4+ (CI) hashes the empty string into a valid-looking answer
  # for a pipeline covering no files. Guard it explicitly.
  if [[ "${#EMPHASIS_VERSION_FILES[@]}" -eq 0 ]]; then
    echo "emphasis-version.sh: EMPHASIS_VERSION_FILES is empty — nothing to hash." >&2
    return 1
  fi

  for f in "${EMPHASIS_VERSION_FILES[@]}"; do
    if [[ ! -f "$repo_root/$f" ]]; then
      echo "emphasis-version.sh: '$f' is listed in EMPHASIS_VERSION_FILES but does not exist." >&2
      ok=0
    fi
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "emphasis-version.sh: refusing to compute an emphasis_version from an incomplete file list." >&2
    return 1
  fi

  for f in "${EMPHASIS_VERSION_FILES[@]}"; do
    printf '%s %s\n' "$f" "$(git -C "$repo_root" hash-object "$repo_root/$f")"
  done | LC_ALL=C sort | git -C "$repo_root" hash-object --stdin
}
