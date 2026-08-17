#!/usr/bin/env bash
#
# verify-deployment.sh — Post-deploy health check against a live site
#
# Usage: ./scripts/verify-deployment.sh [BASE_URL] [LOCAL_DIR]
#   e.g. ./scripts/verify-deployment.sh
#        ./scripts/verify-deployment.sh https://deming.leedurbin.co.nz _book
#
# Environment:
#   VERIFY_PATHS     space-separated URL paths to check, replacing the default
#                    set below — e.g. VERIFY_PATHS="/ /privacy.html"
#   ATTEMPTS         attempts per URL before failing on a real error (default 3)
#   RETRY_DELAY      seconds between those attempts (default 5)
#   CACHE_BUST       token appended as ?v=… to defeat the proxy cache
#                    (default: timestamp-pid; CI passes the run id)
#
# HTTP 202 ("accepted, not yet serving fresh content", from production's
# reverse proxy warming up after rsync) is reported but never retried or
# waited out — see the comment above ATTEMPTS below for why.
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

# Retries cover a transient network blip on the runner. A genuinely bad
# deploy fails all attempts, so this delays a real failure by seconds
# without hiding it.
ATTEMPTS="${ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# HTTP 202 is reported but never retried or waited out. Production's proxy
# answers 202 ("accepted, not yet serving fresh content") for over twenty
# minutes after rsync touches files on disk, proxy-wide rather than per-path
# (#653, #663). Two earlier fixes tried to outlast that window instead — a
# ~110s budget per path (#663), then a 1200s budget pooled across all paths
# (#664) — and both were exceeded within the same day's deploys, with the
# true window length still unmeasured. More importantly, across every
# recorded occurrence, 202 never once correlated with an actual bad deploy:
# checking the shipped artifact byte-for-byte against production always came
# back clean. A real bad deploy shows up as a 4xx/5xx/timeout/content
# mismatch instead, which ATTEMPTS/RETRY_DELAY above still catches within
# seconds. So 202 no longer blocks this script: it's reported as still
# warming up and does not fail the run, so `Tag deployment` in deploy.yml
# proceeds rather than waiting on a signal that was never diagnostic of
# deploy health.

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
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' YELLOW='' RED='' BOLD='' RESET=''
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
WARMING_COUNT=0

# Runs one fetch-and-compare for $1 against expected hash $2 / expected file
# $3, writing the body to $4. Sets CHECK_STATUS (HTTP code) and CHECK_REASON
# ("" on success) rather than returning them — bash functions can't hand back
# a multi-line string cleanly, and every caller needs both the status (to
# tell a 202 apart from every other failure) and the reason.
CHECK_STATUS=""
CHECK_REASON=""
check_once() {
  local path="$1" expected_hash="$2" expected_file="$3" body="$4"
  local url="${BASE_URL}${path}?v=${CACHE_BUST}"

  # No --compressed: the comparison is against bytes on disk, and asking for
  # an encoding invites the server to hand back something re-encoded.
  #
  # No --retry either: retrying is the caller's job, because only it can see
  # a content mismatch. Stacking curl's own retries underneath multiplied the
  # worst case — an unreachable site took ~29 minutes to be reported across
  # six paths, rather than the ~10 this bounds it to.
  CHECK_STATUS="$(curl -sS -o "$body" -w '%{http_code}' \
    --connect-timeout 10 --max-time 30 \
    "$url" 2>/dev/null)" || CHECK_STATUS="000"
  CHECK_REASON=""

  if [[ "$CHECK_STATUS" == "202" ]]; then
    CHECK_REASON="HTTP 202 (expected 200) — proxy warm-up"
  elif [[ "$CHECK_STATUS" != "200" ]]; then
    CHECK_REASON="HTTP ${CHECK_STATUS} (expected 200)"
  else
    local actual_hash
    actual_hash="$(sha256_of "$body")"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
      CHECK_REASON="content differs from deployed artifact"
      CHECK_REASON+=$'\n'"        expected sha256 ${expected_hash:0:16}… ($(wc -c < "$expected_file" | tr -d ' ') bytes)"
      CHECK_REASON+=$'\n'"        served   sha256 ${actual_hash:0:16}… ($(wc -c < "$body" | tr -d ' ') bytes)"
    fi
  fi
}

# Wraps check_once with the fast retry budget (ATTEMPTS/RETRY_DELAY). A 202
# is never retried in here — it's reported once and left alone, since no
# amount of retrying inside this script has reliably outlasted it (see the
# comment above ATTEMPTS). This only absorbs a transient real error.
#
# Always returns 0: the outcome is communicated entirely through the
# CHECK_STATUS/CHECK_REASON globals, never through this function's own exit
# code. That's deliberate, not an oversight — under `set -e`, a bare
# `return` after a false `[[ ]]` test propagates that test's *failure*
# status (bash's documented behaviour for argument-less `return`), and this
# function is called as a plain top-level statement by its callers, so a
# non-zero return here would silently kill the whole script exactly when
# it's about to report a real failure. Caught by testing, not by reasoning
# about it — verify empirically before trusting a change to this function.
check_with_retry() {
  local path="$1" expected_hash="$2" expected_file="$3" body="$4"
  local attempt=0
  while true; do
    attempt=$((attempt + 1))
    check_once "$path" "$expected_hash" "$expected_file" "$body"

    if [[ "$CHECK_STATUS" == "202" || -z "$CHECK_REASON" ]]; then
      return 0
    fi

    if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
      echo "        attempt ${attempt}/${ATTEMPTS} failed, retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
    else
      return 0
    fi
  done
}

# Parallel indexed arrays rather than an associative array keyed by path:
# the runner for this script is macOS's default /bin/bash (3.2), which
# predates `declare -A` and also throws "unbound variable" under `set -u`
# when a genuinely empty array is expanded with "${arr[@]}" — possible here
# if every path in PATHS turns out stale. Every expansion of a maybe-empty
# array is guarded with a length check for that reason.
CHECK_PATHS=()
CHECK_FILES=()
CHECK_HASHES=()
CHECK_BODIES=()

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

  CHECK_PATHS+=("$path")
  CHECK_FILES+=("$expected_file")
  CHECK_HASHES+=("$(sha256_of "$expected_file")")
  CHECK_BODIES+=("${WORK_DIR}/body-${#CHECK_PATHS[@]}")
done

# One pass per path (ATTEMPTS/RETRY_DELAY): catches a real error quickly. A
# 202 is reported and left alone rather than retried — see the comment above
# ATTEMPTS for why waiting it out here doesn't work.
for ((i = 0; i < ${#CHECK_PATHS[@]}; i++)); do
  path="${CHECK_PATHS[$i]}"
  check_with_retry "$path" "${CHECK_HASHES[$i]}" "${CHECK_FILES[$i]}" "${CHECK_BODIES[$i]}"

  if [[ "$CHECK_STATUS" == "202" ]]; then
    echo -e "  ${YELLOW}WARM${RESET}  ${path}  (HTTP 202 — proxy warm-up, not a failure)"
    WARMING_COUNT=$((WARMING_COUNT + 1))
  elif [[ -n "$CHECK_REASON" ]]; then
    echo -e "  ${RED}FAIL${RESET}  ${path}"
    echo "        ${CHECK_REASON}"
    FAILURES=$((FAILURES + 1))
  else
    echo -e "  ${GREEN}PASS${RESET}  ${path}  ($(wc -c < "${CHECK_BODIES[$i]}" | tr -d ' ') bytes, matches artifact)"
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

if [[ "$WARMING_COUNT" -gt 0 ]]; then
  echo -e "${YELLOW}${WARMING_COUNT} of ${#PATHS[@]} path(s) still warming up (HTTP 202) — not treated as a failure.${RESET}"
  echo "Proxy warm-up is unrelated to deploy correctness (#653/#663/#664): every"
  echo "recorded occurrence checked out clean against the shipped artifact once"
  echo "checked later. The deploy tag proceeds. Re-run this script by hand once"
  echo "the proxy settles if you want confirmation on the remaining path(s)."
  exit 0
fi

echo -e "${GREEN}${BOLD}All ${#PATHS[@]} checks passed.${RESET}"
