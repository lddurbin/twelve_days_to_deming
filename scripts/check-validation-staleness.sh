#!/usr/bin/env bash
#
# check-validation-staleness.sh — flag recorded validation results whose
# scorer_version predates the current scripts/lib/paragraph_similarity.py.
#
# Runs entirely without the source PDFs (which are gitignored and only ever
# exist on the maintainer's machine — see workflow/validation/results/README.md
# and issue #720): it compares each result file's recorded scorer_version
# against `git hash-object` of the scorer as it exists right now. A mismatch
# means the scoring logic changed since that day/appendix was last validated,
# not that the transcription itself regressed.
#
# Usage: ./scripts/check-validation-staleness.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$REPO_ROOT/workflow/validation/results"
SCORER="$REPO_ROOT/scripts/lib/paragraph_similarity.py"

current_version=$(git -C "$REPO_ROOT" hash-object "$SCORER")

shopt -s nullglob
results=("$RESULTS_DIR"/*.yml)
shopt -u nullglob

if [[ "${#results[@]}" -eq 0 ]]; then
  echo "No recorded validation results found in ${RESULTS_DIR#"$REPO_ROOT/"} — nothing to check."
  exit 0
fi

stale=()
for f in "${results[@]}"; do
  recorded=$(sed -n 's/^scorer_version: *//p' "$f")
  if [[ "$recorded" != "$current_version" ]]; then
    stale+=("$(basename "$f")")
  fi
done

if [[ "${#stale[@]}" -eq 0 ]]; then
  echo "All ${#results[@]} recorded validation result(s) match the current scorer ($current_version)."
  exit 0
fi

echo "scripts/lib/paragraph_similarity.py has changed since these results were recorded:"
for f in "${stale[@]}"; do
  echo "  - workflow/validation/results/$f"
done
echo ""
echo "Re-run ./scripts/validate-transcription.sh for the affected day(s)/appendix(es)"
echo "and commit the refreshed result file(s) once you've reviewed the new findings."
exit 1
