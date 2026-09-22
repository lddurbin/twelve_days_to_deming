#!/usr/bin/env bash
#
# check-validation-staleness.sh — flag recorded validation results whose
# recorded version predates the pipeline that produced them, as it exists
# right now.
#
# Two independent pipelines, two directories, two versions:
#
#   results/    the paragraph comparator   scorer_version    (#720, #737)
#   emphasis/   the emphasis checker       emphasis_version  (#846)
#
# They are kept apart deliberately. Neither can change what the other reports
# — different extractions, different questions — so folding them into one
# version would mean every emphasis-checker edit restaling all eighteen
# paragraph records, which under main's `strict: true` protection with no
# merge queue is a real merge-ordering cost. See scripts/lib/emphasis-version.sh.
#
# Runs entirely without the source PDFs (which are gitignored and only ever
# exist on the maintainer's machine — see workflow/validation/results/README.md
# and issue #720): it compares each result file's recorded scorer_version
# against a hash recomputed from the pipeline's current contents. A mismatch
# means the comparison logic changed since that day/appendix was last
# validated, not that the transcription itself regressed.
#
# Which files count as "the pipeline" is defined once, in
# scripts/lib/scorer-version.sh, and shared with the script that writes the
# recorded values — see #737.
#
# Usage: ./scripts/check-validation-staleness.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source-path=SCRIPTDIR source=lib/scorer-version.sh
. "$REPO_ROOT/scripts/lib/scorer-version.sh"
# shellcheck source-path=SCRIPTDIR source=lib/emphasis-version.sh
. "$REPO_ROOT/scripts/lib/emphasis-version.sh"

failed=0
checked_any=0

# Compare every record in one directory against one current version.
#
# $1 directory under workflow/validation/, $2 the YAML key holding the
# recorded version, $3 that version as it is now, $4 what changing it means,
# and the remaining arguments the files the version covers.
check_dir() {
  local dir=$1 key=$2 current=$3 description=$4
  shift 4
  local pipeline_files=("$@")
  local path="$REPO_ROOT/workflow/validation/$dir"

  shopt -s nullglob
  local records=("$path"/*.yml)
  shopt -u nullglob

  if [[ "${#records[@]}" -eq 0 ]]; then
    echo "No recorded results in workflow/validation/$dir — nothing to check."
    return 0
  fi
  checked_any=1

  local stale=() f recorded
  for f in "${records[@]}"; do
    recorded=$(sed -n "s/^$key: *//p" "$f")
    if [[ "$recorded" != "$current" ]]; then
      stale+=("$(basename "$f")")
    fi
  done

  if [[ "${#stale[@]}" -eq 0 ]]; then
    echo "All ${#records[@]} record(s) in workflow/validation/$dir match the current $description ($current)."
    return 0
  fi

  echo ""
  echo "The $description has changed since these results were recorded:"
  for f in "${stale[@]}"; do
    echo "  - workflow/validation/$dir/$f"
  done
  echo ""
  echo "Pipeline files:"
  for f in "${pipeline_files[@]}"; do
    echo "  - $f"
  done
  failed=1
  return 0
}

check_dir results scorer_version "$(compute_scorer_version "$REPO_ROOT")" \
  "comparison pipeline" "${SCORER_VERSION_FILES[@]}"
check_dir emphasis emphasis_version "$(compute_emphasis_version "$REPO_ROOT")" \
  "emphasis checker" "${EMPHASIS_VERSION_FILES[@]}"

if [[ "$checked_any" -eq 0 ]]; then
  echo "No recorded validation results found at all — nothing to check."
  exit 0
fi

if [[ "$failed" -eq 0 ]]; then
  exit 0
fi

echo ""
echo "Re-run the tool that owns the affected directory and commit the refreshed"
echo "record(s) once you have reviewed the new findings:"
echo "  results/   ./scripts/validate-transcription.sh <day>|--manifest <name>"
echo "  emphasis/  ./scripts/check-emphasis.py <day>|<manifest>|--all"
exit 1
