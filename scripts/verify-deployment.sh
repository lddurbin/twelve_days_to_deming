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
#   ROUNDS_202       rounds of the shared wait while the proxy keeps answering
#                    202, applied once across all still-pending paths rather
#                    than separately per path (default 80) — see #653, #663
#   RETRY_DELAY_202  seconds between those rounds (default 15)
#   CACHE_BUST       token appended as ?v=… to defeat the proxy cache
#                    (default: timestamp-pid; CI passes the run id)
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

# HTTP 202 is handled on its own, more patient budget rather than folded into
# ATTEMPTS/RETRY_DELAY above. Production's proxy answers 202 ("accepted, not
# yet serving fresh content") for well over ten minutes after rsync touches
# files on disk, and the condition is proxy-wide rather than per-path: a run
# on 2026-08-16 (#663) saw all 6 checked paths still returning 202 after 12
# straight minutes of sequential per-path retrying, because that fix gave
# each path its own ~110s budget before moving to the next. An independent
# budget per path both wastes time re-discovering the same site-wide
# condition six times over, and still caps each path's *effective* patience
# at its own slice — never the full elapsed wait, since only the
# last-checked path benefits from everything that came before it. So 202s
# are pooled instead: every still-pending path is rechecked together each
# round, and all of them share one cumulative wait. A real error (4xx/5xx/
# timeout) still fails fast within ATTEMPTS/RETRY_DELAY above. See #653.
ROUNDS_202="${ROUNDS_202:-80}"
RETRY_DELAY_202="${RETRY_DELAY_202:-15}"

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
WARMUP_FAILURES=0

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

# Parallel indexed arrays rather than an associative array keyed by path:
# the runner for this script is macOS's default /bin/bash (3.2), which
# predates `declare -A` and also throws "unbound variable" under `set -u`
# when a genuinely empty array is expanded with "${arr[@]}" — the common
# case here, since the whole point of phase 2 below is to shrink toward
# empty. Every expansion of a maybe-empty array is guarded with a length
# check for that reason.
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

# Phase 1: one fast pass per path (ATTEMPTS/RETRY_DELAY) — catches a real
# error quickly and clears any path that's already warm. A 202 here is not
# retried in place; it's deferred to the shared warm-up phase below, since
# the 202 window is a proxy-wide condition rather than one particular to a
# single URL (see ROUNDS_202 comment above).
PENDING_IDX=()

for ((i = 0; i < ${#CHECK_PATHS[@]}; i++)); do
  path="${CHECK_PATHS[$i]}"

  attempt=0
  while true; do
    attempt=$((attempt + 1))
    check_once "$path" "${CHECK_HASHES[$i]}" "${CHECK_FILES[$i]}" "${CHECK_BODIES[$i]}"

    [[ "$CHECK_STATUS" == "202" || -z "$CHECK_REASON" ]] && break

    if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
      echo "        attempt ${attempt}/${ATTEMPTS} failed, retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
    else
      break
    fi
  done

  if [[ "$CHECK_STATUS" == "202" ]]; then
    PENDING_IDX+=("$i")
  elif [[ -n "$CHECK_REASON" ]]; then
    echo -e "  ${RED}FAIL${RESET}  ${path}"
    echo "        ${CHECK_REASON}"
    FAILURES=$((FAILURES + 1))
  else
    echo -e "  ${GREEN}PASS${RESET}  ${path}  ($(wc -c < "${CHECK_BODIES[$i]}" | tr -d ' ') bytes, matches artifact)"
  fi
done

# Phase 2: shared warm-up rounds. Every path still pending after phase 1 is
# rechecked together each round, so all of them draw on the same cumulative
# wait instead of each getting its own budget that's exhausted before the
# others even get their turn.
if [[ ${#PENDING_IDX[@]} -gt 0 ]]; then
  echo ""
  echo "  ${#PENDING_IDX[@]} path(s) still warming up (HTTP 202) — waiting up to $((ROUNDS_202 * RETRY_DELAY_202))s together…"
fi

round=0
while [[ ${#PENDING_IDX[@]} -gt 0 && "$round" -lt "$ROUNDS_202" ]]; do
  round=$((round + 1))
  sleep "$RETRY_DELAY_202"

  still_pending=()
  for i in "${PENDING_IDX[@]}"; do
    path="${CHECK_PATHS[$i]}"
    check_once "$path" "${CHECK_HASHES[$i]}" "${CHECK_FILES[$i]}" "${CHECK_BODIES[$i]}"

    if [[ "$CHECK_STATUS" == "202" ]]; then
      still_pending+=("$i")
    elif [[ -n "$CHECK_REASON" ]]; then
      echo -e "  ${RED}FAIL${RESET}  ${path}"
      echo "        ${CHECK_REASON}"
      FAILURES=$((FAILURES + 1))
    else
      echo -e "  ${GREEN}PASS${RESET}  ${path}  ($(wc -c < "${CHECK_BODIES[$i]}" | tr -d ' ') bytes, matches artifact)"
    fi
  done

  if [[ ${#still_pending[@]} -gt 0 ]]; then
    PENDING_IDX=("${still_pending[@]}")
    echo "        round ${round}/${ROUNDS_202}: ${#PENDING_IDX[@]} path(s) still 202, retrying in ${RETRY_DELAY_202}s…"
  else
    PENDING_IDX=()
  fi
done

if [[ ${#PENDING_IDX[@]} -gt 0 ]]; then
  for i in "${PENDING_IDX[@]}"; do
    echo -e "  ${RED}FAIL${RESET}  ${CHECK_PATHS[$i]}"
    echo "        HTTP 202 (expected 200) — still warming up after $((round * RETRY_DELAY_202))s"
    FAILURES=$((FAILURES + 1))
    WARMUP_FAILURES=$((WARMUP_FAILURES + 1))
  done
fi

echo ""

if [[ "$FAILURES" -gt 0 ]]; then
  echo -e "${RED}${BOLD}${FAILURES} of ${#PATHS[@]} checks failed.${RESET}"

  if [[ "$STALE_PATHS" -gt 0 ]]; then
    echo ""
    echo "${STALE_PATHS} path(s) are not in the deployed artifact at all, so this"
    echo "script is checking pages that no longer exist. Update PATHS in"
    echo "scripts/verify-deployment.sh to match the current site."
  fi

  if [[ "$WARMUP_FAILURES" -gt 0 ]]; then
    echo ""
    echo "${WARMUP_FAILURES} path(s) never left proxy warm-up (HTTP 202) within"
    echo "${ROUNDS_202} rounds. That is not the same as a bad deploy — rsync"
    echo "already succeeded before this script ran, and #653/#663 both turned"
    echo "out to be production serving the correct bytes once warm-up finally"
    echo "finished. Re-check by hand once the proxy settles and, if it now"
    echo "passes, recover the missing deploy tag with:"
    echo "  gh run rerun <run-id> --failed"
    echo "rather than rolling back."
  fi

  if [[ "$FAILURES" -gt "$((STALE_PATHS + WARMUP_FAILURES))" ]]; then
    echo ""
    echo "The site is serving something other than what was just deployed."
    echo "See docs/ROLLBACK.md — Option 1 restores the pre-deploy backup."
  fi

  exit 1
fi

echo -e "${GREEN}${BOLD}All ${#PATHS[@]} checks passed.${RESET}"
