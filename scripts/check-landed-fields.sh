#!/usr/bin/env bash
#
# check-landed-fields.sh — catch deviation and changeset entries whose
# "landed" reference was never filled in.
#
# Both logs carry a field naming the PR that shipped the change:
# docs/deviations/ uses **Landed in**, docs/changesets/ uses **PR**. Both are
# filled in by hand, and #777 found that 24 of 52 deviation entries never got
# one — the field still read "Pending", a placeholder comment, or nothing at
# all, for work that had shipped months earlier. That log renders straight
# onto a public page (changes-from-source.qmd), so half of it was telling
# readers a change hadn't happened yet.
#
# A stale changeset field is worse than cosmetic: cut-release.sh interpolates
# **PR** into CHANGELOG.md verbatim and then deletes the entry file, so a
# "TBD" becomes permanent and the real number is unrecoverable.
#
# Two classes are checked:
#
#   1. Placeholders. "TBD", "<!-- filled at merge -->", "to be added", or a
#      bare "pending" with no issue behind it. Never legitimate — the format
#      in docs/deviations/README.md is "Pending — tracked in #NNN".
#
#   2. "Pending — tracked in #NNN" where #NNN is CLOSED. Pending is correct
#      while the work is genuinely outstanding, so the tracking issue's own
#      state is what separates a forgotten bump from a legitimate one. This
#      class needs network access; without gh it is skipped, not guessed.
#
# Usage: ./scripts/check-landed-fields.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVIATIONS_DIR="$REPO_ROOT/docs/deviations"
CHANGESETS_DIR="$REPO_ROOT/docs/changesets"

problems=()

# Entry files only: README.md documents the layout and _preamble.md defines
# the fields, so both legitimately contain the placeholder wording.
entry_files() {
  local dir="$1"
  shopt -s nullglob
  local f
  for f in "$dir"/*.md; do
    case "$(basename "$f")" in
      README.md | _preamble.md) continue ;;
    esac
    echo "$f"
  done
  shopt -u nullglob
}

# First line of a "- **Field** — value" / "- **Field**: value" bullet.
field_value() {
  local name="$1" file="$2"
  sed -n "s/^- \*\*${name}\*\*[[:space:]]*[—:-][[:space:]]*//p" "$file" | head -1
}

is_placeholder() {
  local v="$1"
  [[ -z "$v" ]] && return 0
  shopt -s nocasematch
  local hit=1
  if [[ "$v" == *TBD* \
     || "$v" == *"filled at merge"* \
     || "$v" == *"to be added"* \
     || "$v" == *"to be filled"* ]]; then
    hit=0
  # A bare "pending" with no issue reference. "Pending — tracked in #NNN" is
  # the documented, legitimate form and is judged by tracker state instead.
  elif [[ "$v" == *pending* && "$v" != *"#"* ]]; then
    hit=0
  fi
  shopt -u nocasematch
  return "$hit"
}

# ── Deviations: **Landed in** ────────────────────────────────
pending_trackers=()   # "file<TAB>issue"

while IFS= read -r f; do
  rel="${f#"$REPO_ROOT/"}"
  value="$(field_value "Landed in" "$f")"

  if [[ -z "$value" ]]; then
    problems+=("$rel — no **Landed in** field")
    continue
  fi

  if is_placeholder "$value"; then
    problems+=("$rel — **Landed in** is an unfilled placeholder: $value")
    continue
  fi

  # "Pending — tracked in #NNN" (with or without a markdown link).
  if [[ "$value" == *[Pp]ending* ]]; then
    issue="$(grep -oE '#[0-9]+' <<<"$value" | head -1 | tr -d '#')"
    if [[ -z "$issue" ]]; then
      problems+=("$rel — **Landed in** is pending with no tracking issue")
    else
      pending_trackers+=("$rel	$issue")
    fi
  fi
done < <(entry_files "$DEVIATIONS_DIR")

# ── Changesets: **PR** ───────────────────────────────────────
while IFS= read -r f; do
  rel="${f#"$REPO_ROOT/"}"
  value="$(field_value "PR" "$f")"

  if [[ -z "$value" ]]; then
    problems+=("$rel — no **PR** field (cut-release.sh would drop the reference)")
  elif is_placeholder "$value"; then
    problems+=("$rel — **PR** is an unfilled placeholder: $value (cut-release.sh would bake this into CHANGELOG.md)")
  fi
done < <(entry_files "$CHANGESETS_DIR")

# ── Tracker state for the legitimately-shaped pending entries ─
tracker_check_skipped=""
if [[ "${#pending_trackers[@]}" -gt 0 ]]; then
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    tracker_check_skipped="gh is unavailable or unauthenticated"
  else
    for row in "${pending_trackers[@]}"; do
      rel="${row%%	*}"
      issue="${row##*	}"
      state="$(gh issue view "$issue" --json state --jq .state 2>/dev/null || echo "")"
      if [[ -z "$state" ]]; then
        problems+=("$rel — **Landed in** tracks #$issue, which could not be read")
      elif [[ "$state" == "CLOSED" ]]; then
        problems+=("$rel — **Landed in** still says pending, but #$issue is closed")
      fi
    done
  fi
fi

# ── Report ───────────────────────────────────────────────────
if [[ "${#problems[@]}" -eq 0 ]]; then
  echo "All deviation and changeset entries name the PR that shipped them."
  if [[ -n "$tracker_check_skipped" ]]; then
    echo "Note: ${#pending_trackers[@]} pending entry/entries were not checked against their tracking issue ($tracker_check_skipped)."
  fi
  exit 0
fi

echo "Entries with an unresolved landed reference:"
for p in "${problems[@]}"; do
  echo "  - $p"
done
echo ""
echo "Fill the field in with the PR that shipped the change — see"
echo "docs/deviations/README.md and docs/changesets/README.md."
if [[ -n "$tracker_check_skipped" ]]; then
  echo ""
  echo "Note: tracking-issue state was not checked ($tracker_check_skipped)."
fi
exit 1
