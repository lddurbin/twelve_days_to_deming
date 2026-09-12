#!/usr/bin/env bash
#
# landed-placeholder.sh — the single definition of "this field was never
# filled in", sourced by both consumers: scripts/check-landed-fields.sh
# (which flags it continuously) and scripts/cut-release.sh (which refuses to
# consume an entry carrying one). One definition, two consumers, so they
# cannot drift apart — the same shape as scripts/lib/scorer-version.sh and
# #737.
#
# Review of #777 caught the two lists already diverging on their first day:
# "to be filled" was in the check and not in the release gate. That is the
# exact failure this whole PR is about — a rule written down in two places,
# one of which someone forgets — so it belongs in one place.
#
# Usage:
#   source "$REPO_ROOT/scripts/lib/landed-placeholder.sh"
#   if is_landed_placeholder "$value"; then ...

# Substrings that mean "nobody filled this in", matched case-insensitively.
# An empty value counts too. A bare "pending" with no "#NNN" behind it counts
# as well, and is handled separately below, because the documented legitimate
# form is "Pending — tracked in #NNN": pending *with* an issue is a real
# state, judged by that issue's own state rather than by its wording.
LANDED_PLACEHOLDER_SUBSTRINGS=(
  "TBD"
  "filled at merge"
  "to be added"
  "to be filled"
)

# is_landed_placeholder <value> — true when the value is missing or is one of
# the never-legitimate placeholders above.
is_landed_placeholder() {
  local v="$1"
  [[ -z "$v" ]] && return 0

  local needle hit=1
  shopt -s nocasematch
  for needle in "${LANDED_PLACEHOLDER_SUBSTRINGS[@]}"; do
    if [[ "$v" == *"$needle"* ]]; then
      hit=0
      break
    fi
  done
  # A bare "pending" with no issue reference. Unfilled, not outstanding.
  if ((hit)) && [[ "$v" == *pending* && "$v" != *"#"* ]]; then
    hit=0
  fi
  shopt -u nocasematch

  return "$hit"
}
