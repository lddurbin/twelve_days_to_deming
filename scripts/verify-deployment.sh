#!/usr/bin/env bash
#
# verify-deployment.sh — Post-deploy health check against a live site
#
# Usage: ./scripts/verify-deployment.sh [BASE_URL] [LOCAL_DIR]
#   e.g. ./scripts/verify-deployment.sh
#        ./scripts/verify-deployment.sh https://deming.leedurbin.co.nz _book
#
# Environment:
#   VERIFY_PATHS   space-separated URL paths to check, replacing the default
#                  set below — e.g. VERIFY_PATHS="/ /privacy.html"
#   ATTEMPTS       attempts per URL before failing (default 3)
#   RETRY_DELAY    seconds between attempts (default 5)
#   CACHE_BUST     token appended as ?v=… to defeat the proxy cache
#                  (default: timestamp-pid; CI passes the run id)
#
# Fetches a short, fixed set of URLs from a deployed site and asserts each is
# byte-identical to the file that was shipped.
#
# The smoke test in deploy.yml validates the build artifact *before* rsync, and
# the artifact verification validates the download. Neither can see anything
# that goes wrong during or after the transfer — a partial rsync, a permissions
# problem, a server-side failure. Without this, the first signal is a reader.
# See #533.
#
# Why byte equality rather than a content marker: a marker such as "the page
# contains the site title" also passes on a stale page, a truncated page, and a
# page that lost every interactive cell. Hashing against LOCAL_DIR derives the
# expectation from what was actually shipped, so the check is both stricter and
# incapable of rotting as content changes — there is no expected string in this
# file to fall out of date.
#
# That only works because this host serves files verbatim. Measured against
# production on 2026-08-07 by diffing the live responses for /, /privacy.html,
# /robots.txt and /sitemap.xml against the artifact of the run that deployed
# them: all four hashes matched, so there is no minification, no injection, and
# no rewriting in the path. A host that transformed HTML would need content
# markers instead.
#
# Requires: curl, and sha256sum (Linux/CI) or shasum (macOS).

set -euo pipefail

BASE_URL="${1:-https://deming.leedurbin.co.nz}"
LOCAL_DIR="${2:-_book}"

# Retries cover both a transient network blip on the runner and the brief
# window where a proxy may not yet have caught up. A genuinely bad deploy fails
# all attempts, so this delays a real failure by seconds without hiding it.
ATTEMPTS="${ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# The site sits behind a proxy (`x-proxy-cache-info` in production response
# headers). Appending a token unique to this run guarantees the origin answers,
# so a cached copy of the *previous* deploy cannot make a failed deploy look
# healthy. Confirmed the host serves an unknown query string normally rather
# than 404ing on it.
CACHE_BUST="${CACHE_BUST:-$(date +%s)-$$}"

# Deliberately short and stable — one representative of each thing that could
# independently break, not broad coverage. Broad coverage is the build smoke
# test's job; this one has to stay quiet enough that a red run means something.
#
# Override via the environment to point the same checks at another deployment,
# e.g. VERIFY_PATHS="/ /privacy.html" for a preview build.
if [[ -n "${VERIFY_PATHS:-}" ]]; then
  # shellcheck disable=SC2206  # deliberate word-splitting: space-separated list
  PATHS=( ${VERIFY_PATHS} )
else
  PATHS=(
    /                                                 # root — the redirect target of the bare domain
    /privacy.html                                     # top-level page, served by nginx rather than Apache
    /content/days/day-11/05-activity-11a.html         # deep path, 40 OJS cells — exercises rsync recursion
    /content/appendix/glossary.html                   # appendix tree, separate from content/days
    /robots.txt                                       # crawler directives — silent SEO damage if lost
    /sitemap.xml                                      # ditto, and the only file listing all 123 URLs
  )
fi

# ── Colours ───────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' RED='' BOLD='' RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────

# GNU coreutils on the runner, BSD on macOS. Supporting both is what makes the
# negative test runnable on a laptop instead of only in CI.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# A directory URL is served by its index.html; everything else maps straight to
# a file of the same name, because rsync ships _book/ to the docroot verbatim.
local_file_for() {
  local path="$1"
  case "$path" in
    */) echo "${LOCAL_DIR}/${path#/}index.html" ;;
    *)  echo "${LOCAL_DIR}/${path#/}" ;;
  esac
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Checks ────────────────────────────────────────────────────

echo -e "${BOLD}Verifying ${BASE_URL} against ${LOCAL_DIR}${RESET}"
echo ""

FAILURES=0
STALE_PATHS=0

for path in "${PATHS[@]}"; do
  expected_file="$(local_file_for "$path")"

  # A renamed or removed page shows up here. Failing loudly beats skipping,
  # which would silently reduce this to a shorter and shorter check. Counted
  # separately because it means this script is out of date, not that the
  # deploy went wrong — opposite remediations.
  if [[ ! -f "$expected_file" ]]; then
    echo -e "  ${RED}FAIL${RESET}  ${path}"
    echo "        not in the deployed artifact: ${expected_file}"
    FAILURES=$((FAILURES + 1))
    STALE_PATHS=$((STALE_PATHS + 1))
    continue
  fi

  expected_hash="$(sha256_of "$expected_file")"
  body="${WORK_DIR}/body"
  url="${BASE_URL}${path}?v=${CACHE_BUST}"
  reason=""

  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    reason=""

    # No --compressed: the comparison is against bytes on disk, and asking for
    # an encoding invites the server to hand back something re-encoded.
    #
    # No --retry either: retrying is the outer loop's job, because only it can
    # see a content mismatch. Stacking curl's own retries underneath multiplied
    # the worst case — an unreachable site took ~29 minutes to be reported
    # across six paths, rather than the ~10 this bounds it to.
    status="$(curl -sS -o "$body" -w '%{http_code}' \
      --connect-timeout 10 --max-time 30 \
      "$url" 2>/dev/null)" || status="000"

    if [[ "$status" != "200" ]]; then
      reason="HTTP ${status} (expected 200)"
    else
      actual_hash="$(sha256_of "$body")"
      if [[ "$actual_hash" != "$expected_hash" ]]; then
        reason="content differs from deployed artifact"
        reason+=$'\n'"        expected sha256 ${expected_hash:0:16}… ($(wc -c < "$expected_file" | tr -d ' ') bytes)"
        reason+=$'\n'"        served   sha256 ${actual_hash:0:16}… ($(wc -c < "$body" | tr -d ' ') bytes)"
      fi
    fi

    [[ -z "$reason" ]] && break

    if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
      echo "        attempt ${attempt}/${ATTEMPTS} failed, retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
    fi
  done

  if [[ -n "$reason" ]]; then
    echo -e "  ${RED}FAIL${RESET}  ${path}"
    echo "        ${reason}"
    FAILURES=$((FAILURES + 1))
  else
    echo -e "  ${GREEN}PASS${RESET}  ${path}  ($(wc -c < "$body" | tr -d ' ') bytes, matches artifact)"
  fi
done

echo ""

if [[ "$FAILURES" -gt 0 ]]; then
  echo -e "${RED}${BOLD}${FAILURES} of ${#PATHS[@]} checks failed.${RESET}"

  if [[ "$STALE_PATHS" -gt 0 ]]; then
    echo ""
    echo "${STALE_PATHS} path(s) are not in the deployed artifact at all, so this"
    echo "script is checking pages that no longer exist. Update PATHS in"
    echo "scripts/verify-deployment.sh to match the current site."
  fi

  if [[ "$FAILURES" -gt "$STALE_PATHS" ]]; then
    echo ""
    echo "The site is serving something other than what was just deployed."
    echo "See docs/ROLLBACK.md — Option 1 restores the pre-deploy backup."
  fi

  exit 1
fi

echo -e "${GREEN}${BOLD}All ${#PATHS[@]} checks passed.${RESET}"
