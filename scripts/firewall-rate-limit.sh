#!/usr/bin/env bash
#
# firewall-rate-limit.sh — The production project's one rate-limit rule (#911)
#
# Usage: ./scripts/firewall-rate-limit.sh stage log|enforce
#          stages the rule as a draft (adding it, or editing it if it already
#          exists) and prints the draft diff: `log` only records clients over
#          the limit, `enforce` sends them a 429
#        ./scripts/firewall-rate-limit.sh show
#          prints the rule, then any changes still waiting to be published.
#          The rule is printed as the draft has it, so it only matches
#          what's live when the diff says there's nothing pending
#
# Firewall rules live in Vercel, not in this repo, so this script is the
# rule's source of truth: change the settings below and re-stage, rather
# than editing the rule in the dashboard. docs/firewall.md explains the
# numbers and how they were chosen.
#
# Like cut-release.sh, it deliberately stops short of the live change.
# Read the diff it prints, then publish it yourself:
#   vercel firewall publish --scope lees-projects-5b4a1017
# from a directory linked to the project, or with Review Changes → Publish
# in the dashboard's Firewall tab. `vercel firewall discard` throws the
# draft away instead.
#
# The rule counts requests per client IP across every path and never looks
# at the user agent. Every client over the limit gets the same response,
# which keeps anonymous and crawler views byte-identical, as the URL policy
# in AGENTS.md requires.
#
# Needs a terminal logged in to Vercel (`vercel login`) with access to the
# team below.

set -euo pipefail

SCOPE="lees-projects-5b4a1017"
PROJECT="twelve-days-to-deming"
RULE="Rate limit per IP"
DESCRIPTION="Caps what any one client IP can cost. Counts by rate across every path, never by user agent (#911)."

# Hobby allows the fixed window algorithm only (token bucket is Enterprise),
# one rate-limit rule per project, and a window of 10s to 10 minutes.
ALGO="fixed_window"
WINDOW_SECONDS=60
REQUESTS=600

usage() {
  echo "Usage: $0 stage log|enforce | show" >&2
  exit 2
}

# The repo root has no Vercel link of its own (the deploy jobs pass IDs
# instead), and `vercel link` also pulls an OIDC token into .env.local, so
# link a throwaway directory rather than the working tree.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

vc() {
  vercel "$@" --cwd "$workdir" --scope "$SCOPE"
}

case "${1:-}" in
  stage)
    case "${2:-}" in
      log) action="log" ;;
      enforce) action="rate_limit" ;;
      *) usage ;;
    esac
    settings=(
      --description "$DESCRIPTION"
      --condition '{"type":"path","op":"pre","value":"/"}'
      # The rule's type, always rate_limit. What happens to a client over
      # the limit is --rate-limit-action below.
      --action rate_limit
      --rate-limit-algo "$ALGO"
      --rate-limit-window "$WINDOW_SECONDS"
      --rate-limit-requests "$REQUESTS"
      --rate-limit-keys ip
      --rate-limit-action "$action"
      --yes
    )
    vc link --yes --project "$PROJECT" >/dev/null
    if vc firewall rules inspect "$RULE" --json >/dev/null 2>&1; then
      vc firewall rules edit "$RULE" "${settings[@]}"
    else
      vc firewall rules add "$RULE" "${settings[@]}"
    fi
    vc firewall diff
    ;;
  show)
    vc link --yes --project "$PROJECT" >/dev/null
    vc firewall rules inspect "$RULE"
    vc firewall diff
    ;;
  *)
    usage
    ;;
esac
