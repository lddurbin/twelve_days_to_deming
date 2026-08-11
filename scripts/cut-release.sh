#!/usr/bin/env bash
#
# cut-release.sh — Roll up docs/changesets/ entries into CHANGELOG.md
#
# Usage: ./scripts/cut-release.sh <version> [--dry-run]
#   e.g. ./scripts/cut-release.sh 0.2.0
#        ./scripts/cut-release.sh 0.2.0 --dry-run
#
# Reads every entry file in docs/changesets/, groups them by their
# **Section** field, and writes a new "## [<version>] - <date>" section into
# CHANGELOG.md directly below "## [Unreleased]". On a real (non-dry-run) run
# it also `git rm`s the consumed entry files and leaves everything staged
# but uncommitted, so the diff can be reviewed before committing. It never
# commits, tags, pushes, or creates a GitHub release itself — those stay
# explicit manual steps, printed at the end.
#
# See docs/changesets/README.md for the entry file format.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGESETS_DIR="$REPO_ROOT/docs/changesets"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

VERSION=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version> [--dry-run]" >&2
  exit 1
fi

# ── Preferred section order ──────────────────────────────────
# Anything not in this list is grouped alphabetically after these, under
# its own literal Section heading.
PREFERRED_SECTIONS=(
  "Course Content"
  "Accessibility"
  "Reader Experience"
  "Infrastructure & Quality"
  "Fixed"
  "Changed"
  "Removed"
  "Polish & Refactors"
  "Documentation"
)

shopt -s nullglob
ALL_MD_FILES=("$CHANGESETS_DIR"/*.md)
shopt -u nullglob

ENTRY_FILES=()
for f in "${ALL_MD_FILES[@]}"; do
  [[ "$(basename "$f")" == "README.md" ]] && continue
  ENTRY_FILES+=("$f")
done

if [[ ${#ENTRY_FILES[@]} -eq 0 ]]; then
  echo "No changeset entries found in docs/changesets/ — nothing to release." >&2
  exit 1
fi

field() {
  local key="$1" file="$2"
  sed -n -E "s/^- \*\*${key}\*\*:[[:space:]]*//p" "$file" | head -n1
}

# ── Work out section order ───────────────────────────────────
# 1. Every distinct Section value that actually appears, in file order.
ALL_SECTIONS=()
for f in "${ENTRY_FILES[@]}"; do
  s="$(field "Section" "$f")"
  is_new=1
  if ((${#ALL_SECTIONS[@]} > 0)); then
    for existing in "${ALL_SECTIONS[@]}"; do
      if [[ "$existing" == "$s" ]]; then
        is_new=0
        break
      fi
    done
  fi
  ((is_new)) && ALL_SECTIONS+=("$s")
done

# 2. Preferred sections that are present, in preferred order.
ORDERED_SECTIONS=()
for s in "${PREFERRED_SECTIONS[@]}"; do
  for existing in "${ALL_SECTIONS[@]}"; do
    if [[ "$existing" == "$s" ]]; then
      ORDERED_SECTIONS+=("$s")
      break
    fi
  done
done

# 3. Anything else, alphabetically, appended at the end.
REMAINING=()
for existing in "${ALL_SECTIONS[@]}"; do
  is_known=0
  if ((${#ORDERED_SECTIONS[@]} > 0)); then
    for s in "${ORDERED_SECTIONS[@]}"; do
      if [[ "$existing" == "$s" ]]; then
        is_known=1
        break
      fi
    done
  fi
  ((is_known)) || REMAINING+=("$existing")
done
if ((${#REMAINING[@]} > 0)); then
  while IFS= read -r line; do
    ORDERED_SECTIONS+=("$line")
  done < <(printf '%s\n' "${REMAINING[@]}" | sort)
fi

# ── Build the release section ────────────────────────────────
DATE="$(date +%Y-%m-%d)"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

{
  echo
  echo "## [$VERSION] - $DATE"
  for section in "${ORDERED_SECTIONS[@]}"; do
    echo
    echo "### $section"
    for f in "${ENTRY_FILES[@]}"; do
      s="$(field "Section" "$f")"
      [[ "$s" != "$section" ]] && continue
      what="$(field "What" "$f")"
      pr="$(field "PR" "$f")"
      if [[ -n "$pr" ]]; then
        echo "- $what ($pr)"
      else
        echo "- $what"
      fi
    done
  done
} > "$BODY_FILE"

echo "── Draft release notes for v$VERSION ──"
tail -n +2 "$BODY_FILE"
echo "────────────────────────────────────────"

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "Dry run — CHANGELOG.md and docs/changesets/ left untouched."
  exit 0
fi

# ── Insert into CHANGELOG.md, right after "## [Unreleased]" ─────
awk -v bodyfile="$BODY_FILE" '
  { print }
  /^## \[Unreleased\]/ {
    while ((getline line < bodyfile) > 0) print line
  }
' "$CHANGELOG" > "$CHANGELOG.tmp"
mv "$CHANGELOG.tmp" "$CHANGELOG"

git -C "$REPO_ROOT" add "$CHANGELOG"

# Plain rm + `git add -A` (rather than `git rm`) so this works whether the
# entry files were already committed or are still sitting uncommitted from
# the same session that's cutting the release.
rm -f "${ENTRY_FILES[@]}"
git -C "$REPO_ROOT" add -A "$CHANGESETS_DIR"

echo
echo "CHANGELOG.md updated; ${#ENTRY_FILES[@]} changeset file(s) staged for removal."
echo
echo "Review with: git diff --cached"
echo
echo "Next steps once you're happy with the diff:"
echo "  git commit -m \"Cut v$VERSION\""
echo "  git tag v$VERSION"
echo "  git push origin main --tags"
echo "  gh release create v$VERSION --title \"v$VERSION\" --notes-file CHANGELOG.md"
echo "    (then trim the notes to just the v$VERSION section in the editor gh opens)"
