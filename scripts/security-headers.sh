#!/usr/bin/env bash
#
# security-headers.sh — The response headers every Vercel host serves (#681)
#
# Usage: ./scripts/security-headers.sh route BOOK_DIR
#          prints a Build Output API v3 route object carrying the headers,
#          for a job's config.json
#        ./scripts/security-headers.sh check BASE_URL BOOK_DIR
#          asserts BASE_URL serves exactly those headers
#   e.g. ./scripts/security-headers.sh route _book
#        ./scripts/security-headers.sh check https://learndeming.org _book
#
# Why a header as well as the meta tag: a <meta http-equiv> CSP can't carry
# frame-ancestors, and it never applies to a non-HTML response, which is all
# /api/* will return once the accounts work lands (#686).
#
# The policy is read out of BOOK_DIR's built HTML rather than written here,
# so _quarto.yml's meta tag stays its only source. The meta tag stays too:
# it's what `quarto preview` enforces locally, and the browser enforces both,
# so a header derived from it can only ever add frame-ancestors, never loosen
# anything. Every page must carry the identical policy, or this fails, since
# one header covers all of them.
#
# Strict-Transport-Security is left out: Vercel already sends
# `max-age=63072000` on every custom domain. Referrer-Policy states the
# browsers' own default, so it changes nothing today. It pins the value so a
# future default can't widen it.

set -euo pipefail

usage() {
  echo "Usage: $0 route BOOK_DIR | check BASE_URL BOOK_DIR" >&2
  exit 2
}

# The meta tag's content attribute, entity-decoded, from every page. Exactly
# one distinct value is allowed.
csp_policy() {
  local book="$1"
  local policies
  if [ ! -d "$book" ]; then
    echo "FAIL: $book is not a directory" >&2
    exit 1
  fi
  # `|| true`: grep exits 1 when nothing matches, and under pipefail that
  # would end the script here, silently, before the FAIL below can explain.
  policies=$( { find "$book" -name '*.html' \
      -exec grep -ho '<meta http-equiv="Content-Security-Policy" content="[^"]*"' {} + || true; } \
    | sed -e 's/.*content="//' -e 's/"$//' \
          -e "s/&#39;/'/g" -e "s/&apos;/'/g" -e 's/&quot;/"/g' -e 's/&amp;/\&/g' \
    | sort -u)

  if [ -z "$policies" ]; then
    echo "FAIL: no Content-Security-Policy meta tag found under $book" >&2
    exit 1
  fi
  if [ "$(printf '%s\n' "$policies" | wc -l)" -ne 1 ]; then
    echo "FAIL: pages under $book carry different CSPs; one header can't serve them all:" >&2
    printf '%s\n' "$policies" >&2
    exit 1
  fi

  # The sed above decodes only the entities Quarto emits in this attribute.
  # A CSP has no use for `&`, so any left over is an entity it missed, and
  # would reach the browser as a malformed header.
  if [[ "$policies" == *"&"* ]]; then
    echo "FAIL: the CSP under $book holds an entity this script doesn't decode: $policies" >&2
    exit 1
  fi

  printf "%s; frame-ancestors 'none';" "${policies%;}"
}

headers_json() {
  # Assigned on its own line: a failure inside `--arg "$(...)"` wouldn't stop
  # the script, and jq would emit the route with an empty CSP.
  local csp
  csp=$(csp_policy "$1")
  jq -n --arg csp "$csp" '{
    "Content-Security-Policy": $csp,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin"
  }'
}

case "${1:-}" in
  route)
    [ $# -eq 2 ] || usage
    headers_json "$2" | jq '{ src: "/(.*)", headers: ., continue: true }'
    ;;
  check)
    [ $# -eq 3 ] || usage
    base="${2%/}"
    expected=$(headers_json "$3")
    # Two paths, since the headers must cover every response, not just /.
    # Every path is checked before failing, so one log shows them all.
    failed=0
    for path in / /privacy.html; do
      # `|| true` so a curl error lands in the status check below, as HTTP
      # <none>, rather than ending the run before the other paths.
      served=$(curl -sS -D - -o /dev/null --max-time 30 "${base}${path}" | tr -d '\r') || true
      # A redirect's headers would stand in for the page's. Not following it
      # (-L) keeps this checking the response it asked for.
      status=$(head -n 1 <<<"$served" | awk '{print $2}')
      if [ "$status" != "200" ]; then
        echo "FAIL: ${base}${path} answered HTTP ${status:-<none>}, not 200"
        failed=1
        continue
      fi
      path_failed=0
      for name in $(jq -r 'keys[]' <<<"$expected"); do
        want=$(jq -r --arg n "$name" '.[$n]' <<<"$expected")
        got=$(grep -i "^${name}:" <<<"$served" | head -n 1 | sed 's/^[^:]*: *//' || true)
        if [ "$got" != "$want" ]; then
          echo "FAIL: ${base}${path} ${name}"
          echo "  want: ${want}"
          echo "  got:  ${got:-<missing>}"
          path_failed=1
        fi
      done
      if [ "$path_failed" -eq 0 ]; then
        echo "OK: ${base}${path} serves the security headers"
      else
        failed=1
      fi
    done
    [ "$failed" -eq 0 ] || exit 1
    ;;
  *)
    usage
    ;;
esac
