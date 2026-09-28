#!/usr/bin/env bash
#
# verify-old-origin.sh — post-deploy check of deming.leedurbin.co.nz as a
# bridge (#888, Stage 1)
#
# Usage: ./scripts/verify-old-origin.sh [OLD_ORIGIN] [NEW_ORIGIN]
#
# verify-deployment.sh already byte-checks a few bridge pages (with a cache
# bust). This covers the two things it can't:
#
#   1. Paths with no bridge page 301 to the same path, query included, on the
#      new origin. That's the .htaccess, which only Apache reads, so it's the
#      part most likely to be silently ignored.
#   2. The plain URL, with no cache-busting query, serves the bridge. On
#      2026-09-24 SiteGround's proxy kept serving cached HTML from before a
#      deploy, and the cache-busted check passed anyway. Here that would mean
#      readers keep getting the old site, and their answers never move.
#
# Requires: curl.

set -euo pipefail

OLD_ORIGIN="${1:-https://deming.leedurbin.co.nz}"
NEW_ORIGIN="${2:-https://learndeming.org}"
ATTEMPTS="${ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# One of each kind of path that has no bridge page behind it.
REDIRECT_PATHS=(
  /robots.txt                                   # crawlers must follow it to the new host
  "/sitemap.xml?from=verify"                    # query string must survive the 301
  /assets/scripts/origin-handoff.js             # an asset; bridge pages load it from the new origin
  /content/days/day-01/                         # a directory with no index.html
)

# Bridge pages fetched exactly as a reader's browser would, with no query.
PLAIN_PAGES=(/ /privacy.html)

# Every bridge page loads the handoff script, and no page of the old site did.
BRIDGE_MARKER="tdOriginHandoff"

failures=0
warnings=0

fail() { echo "  FAIL  $*"; failures=$((failures + 1)); }
warn() { echo "  WARN  $*"; warnings=$((warnings + 1)); }
ok()   { echo "  ok    $*"; }

# Prints "<status> <location>" for a single request that doesn't follow
# redirects, retrying transport failures.
head_of() {
  local url="$1" out attempt
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if out=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "$url" 2>/dev/null); then
      echo "$out"
      return 0
    fi
    [[ $attempt -lt $ATTEMPTS ]] && sleep "$RETRY_DELAY"
  done
  echo "000 "
}

echo "Redirects from ${OLD_ORIGIN} to ${NEW_ORIGIN}:"
for path in "${REDIRECT_PATHS[@]}"; do
  read -r status location <<<"$(head_of "${OLD_ORIGIN}${path}")"
  expected="${NEW_ORIGIN}${path}"
  if [[ "$status" == "202" ]]; then
    # The proxy's post-rsync warm-up (see verify-deployment.sh). Never
    # correlated with a bad deploy, so it's reported, not failed.
    warn "${path}: HTTP 202 (proxy warming up), not verified"
  elif [[ "$status" != "301" ]]; then
    fail "${path}: HTTP ${status}, expected 301"
  elif [[ "$location" != "$expected" ]]; then
    fail "${path}: 301 to ${location:-nothing}, expected ${expected}"
  else
    ok "${path} → 301 ${location}"
  fi
done

echo "Plain URLs serve the bridge, not a cached page of the old site:"
for path in "${PLAIN_PAGES[@]}"; do
  body=""
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if body=$(curl -sS --max-time 20 -w '\n%{http_code}' "${OLD_ORIGIN}${path}" 2>/dev/null); then
      break
    fi
    [[ $attempt -lt $ATTEMPTS ]] && sleep "$RETRY_DELAY"
  done
  status="${body##*$'\n'}"
  if [[ "$status" == "202" ]]; then
    warn "${path}: HTTP 202 (proxy warming up), not verified"
  elif [[ "$status" != "200" ]]; then
    fail "${path}: HTTP ${status}, expected 200"
  elif [[ "$body" != *"$BRIDGE_MARKER"* ]]; then
    fail "${path}: serves something other than the bridge, probably SiteGround's cached copy of the old site. Flush it in Site Tools → Speed → Caching, then re-run this job."
  else
    ok "${path} serves the bridge"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "${failures} check(s) failed, ${warnings} warning(s). See docs/ROLLBACK.md Option 3 to put the previous docroot back."
  exit 1
fi
echo "All old-origin checks passed (${warnings} warning(s))."
