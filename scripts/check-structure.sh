#!/usr/bin/env bash
#
# check-structure.sh — Structural inventory checker for QMD chapter completeness
#
# Usage: ./scripts/check-structure.sh <day-number>
#   e.g. ./scripts/check-structure.sh 3
#
# Compares each QMD chapter against a per-day manifest and reports PASS/FAIL
# per check per chapter. Checks: viewof count, figure existence, section
# headings, download button, workbook callout.
#
# Requires: ruby (for YAML parsing — ships with macOS)
# Note: CI (Ubuntu) does not install Ruby by default. If wiring into CI,
# add ruby to the workflow's setup steps.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTENT_DIR="$REPO_ROOT/content/days"
MANIFEST_DIR="$REPO_ROOT/workflow/validation"
TMPDIR_CLEANUP=""

# ── Colours ───────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────

usage() {
  echo "Usage: $0 <day-number>"
  echo "  day-number: 1-12"
  echo ""
  echo "Checks QMD chapters against a structural manifest and reports"
  echo "PASS/FAIL per check per chapter."
  exit 1
}

pass() { printf "  ${GREEN}PASS${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${RESET} %s\n" "$1"; }
warn() { printf "  ${YELLOW}WARN${RESET} %s\n" "$1"; }

# Expand manifest into a flat text format using Ruby, one file per chapter.
# Each chapter file contains key=value lines, with multi-value fields
# (figures, headings) on separate ITEM= lines.
expand_manifest() {
  local manifest="$1"
  local outdir="$2"
  ruby -ryaml -e '
    begin
      data = YAML.safe_load(File.read(ARGV[0]))
    rescue => e
      $stderr.puts "Error parsing manifest #{ARGV[0]}: #{e.message}"
      exit 1
    end
    outdir = ARGV[1]
    data["chapters"].each_with_index do |ch, i|
      File.open("#{outdir}/ch_#{format("%02d", i)}", "w") do |f|
        f.puts "FILE=#{ch["file"]}"
        f.puts "VIEWOF=#{ch["viewof_count"]}"
        f.puts "DOWNLOAD=#{ch["has_download_button"]}"
        f.puts "WORKBOOK=#{ch["has_workbook_callout"]}"
        (ch["figures"] || []).each { |fig| f.puts "FIGURE=#{fig}" }
        (ch["headings"] || []).each { |h| f.puts "HEADING=#{h}" }
      end
    end
  ' "$manifest" "$outdir"
}

# Count viewof declarations (viewof name =) in a QMD file
count_viewof() {
  local n
  n=$(grep -cE 'viewof [a-zA-Z_][a-zA-Z0-9_]* =' "$1" 2>/dev/null) || true
  echo "${n:-0}"
}

# Extract ## headings from a QMD file, stripping Quarto attributes and HTML tags
extract_headings() {
  grep '^## ' "$1" 2>/dev/null | sed -E '
    s/^## //
    s/ *\{[^}]*\}$//
    s/<[^>]+>//g
    s/^ +//
    s/ +$//
    s/  +/ /g
  ' || true
}

# ── Main ──────────────────────────────────────────────────────

main() {
  local day_num="${1:-}"

  if [[ -z "$day_num" || ! "$day_num" =~ ^[0-9]+$ ]]; then
    usage
  fi

  if (( day_num < 1 || day_num > 12 )); then
    echo "Error: day-number must be between 1 and 12"
    exit 1
  fi

  if ! command -v ruby &>/dev/null; then
    echo "Error: ruby not found (needed for YAML parsing)"
    exit 1
  fi

  local day_dir
  day_dir=$(printf "day-%02d" "$day_num")
  local manifest="$MANIFEST_DIR/${day_dir}-manifest.yml"
  local qmd_dir="$CONTENT_DIR/$day_dir"

  if [[ ! -f "$manifest" ]]; then
    echo "Error: No manifest found at $manifest"
    echo "Create one before running this check."
    exit 1
  fi

  if [[ ! -d "$qmd_dir" ]]; then
    echo "Error: No content directory at $qmd_dir"
    exit 1
  fi

  echo "=========================================="
  echo "  Structural Inventory Report"
  echo "  Day $day_num"
  echo "=========================================="
  echo ""
  echo "Manifest: $(basename "$manifest")"
  echo "QMD dir:  $day_dir/"
  echo ""

  # Expand manifest into per-chapter temp files
  TMPDIR_CLEANUP=$(mktemp -d)
  local tmpdir="$TMPDIR_CLEANUP"
  trap 'rm -rf "$TMPDIR_CLEANUP"' EXIT
  expand_manifest "$manifest" "$tmpdir"

  local total_checks=0
  local total_pass=0
  local total_fail=0
  local total_warn=0

  for ch_file in "$tmpdir"/ch_*; do
    # Read chapter metadata
    local file="" expected_viewof=0 expected_dl="false" expected_wc="false"
    local figures="" headings=""

    while IFS='=' read -r key value; do
      case "$key" in
        FILE)     file="$value" ;;
        VIEWOF)   expected_viewof="$value" ;;
        DOWNLOAD) expected_dl="$value" ;;
        WORKBOOK) expected_wc="$value" ;;
        FIGURE)
          if [[ -n "$figures" ]]; then
            figures="$figures"$'\n'"$value"
          else
            figures="$value"
          fi
          ;;
        HEADING)
          if [[ -n "$headings" ]]; then
            headings="$headings"$'\n'"$value"
          else
            headings="$value"
          fi
          ;;
      esac
    done < "$ch_file"

    local qmd_path="$qmd_dir/$file"
    printf "${BOLD}%s${RESET}\n" "$file"

    # Check file exists
    if [[ ! -f "$qmd_path" ]]; then
      fail "File not found: $qmd_path"
      total_checks=$((total_checks + 1))
      total_fail=$((total_fail + 1))
      echo ""
      continue
    fi

    # ── Check 1: viewof count ──
    local actual_viewof
    actual_viewof=$(count_viewof "$qmd_path")
    total_checks=$((total_checks + 1))
    if [[ "$actual_viewof" -eq "$expected_viewof" ]]; then
      pass "viewof declarations: $actual_viewof (expected $expected_viewof)"
      total_pass=$((total_pass + 1))
    else
      fail "viewof declarations: $actual_viewof (expected $expected_viewof)"
      total_fail=$((total_fail + 1))
    fi

    # ── Check 2: figure references ──
    # Check manifest figures exist on disk
    if [[ -n "$figures" ]]; then
      while IFS= read -r fig_path; do
        [[ -z "$fig_path" ]] && continue
        total_checks=$((total_checks + 1))
        local full_path="$REPO_ROOT$fig_path"
        if [[ -f "$full_path" ]]; then
          pass "figure exists: $(basename "$fig_path")"
          total_pass=$((total_pass + 1))
        else
          fail "figure missing: $fig_path"
          total_fail=$((total_fail + 1))
        fi
      done <<< "$figures"
    else
      total_checks=$((total_checks + 1))
      pass "figures: none expected"
      total_pass=$((total_pass + 1))
    fi

    # Check all ![...](path) refs in QMD point to existing files
    # Use Ruby for reliable parsing — regex alone can't handle parentheses in alt text
    local qmd_figs
    qmd_figs=$(ruby -e '
      ARGF.each_line do |line|
        line.scan(/!\[[^\]]*\]\(([^)]+)\)/) { |m| puts m[0] }
      end
    ' "$qmd_path" 2>/dev/null | sed 's/%20/ /g' || true)
    if [[ -n "$qmd_figs" ]]; then
      while IFS= read -r ref_path; do
        [[ -z "$ref_path" ]] && continue
        [[ "$ref_path" == http* ]] && continue
        total_checks=$((total_checks + 1))
        local full_ref="$REPO_ROOT$ref_path"
        if [[ -f "$full_ref" ]]; then
          pass "image ref OK: $(basename "$ref_path")"
          total_pass=$((total_pass + 1))
        else
          fail "image ref broken: $ref_path"
          total_fail=$((total_fail + 1))
        fi
      done <<< "$qmd_figs"
    fi

    # ── Check 3: section headings ──
    if [[ -n "$headings" ]]; then
      local actual_hdgs
      actual_hdgs=$(extract_headings "$qmd_path")

      # Build temporary files for comparison (normalise smart quotes to ASCII)
      local exp_file="$tmpdir/exp_hdg"
      local act_file="$tmpdir/act_hdg"
      echo "$headings" | sed -E 's/^ +//; s/ +$//; s/  +/ /g' \
        | ruby -e 'STDIN.each_line{|l| puts l.gsub(/[\u2018\u2019]/,"'\''").gsub(/[\u201C\u201D]/,"\"") }' > "$exp_file"
      echo "$actual_hdgs" | sed -E 's/^ +//; s/ +$//; s/  +/ /g' \
        | ruby -e 'STDIN.each_line{|l| puts l.gsub(/[\u2018\u2019]/,"'\''").gsub(/[\u201C\u201D]/,"\"") }' > "$act_file"

      total_checks=$((total_checks + 1))
      if diff -q "$exp_file" "$act_file" >/dev/null 2>&1; then
        local hdg_count
        hdg_count=$(wc -l < "$exp_file" | tr -d ' ')
        pass "headings: $hdg_count match"
        total_pass=$((total_pass + 1))
      else
        fail "headings: mismatch"
        total_fail=$((total_fail + 1))
        diff --label expected --label actual "$exp_file" "$act_file" | head -10 | sed 's/^/       /'
      fi
    else
      total_checks=$((total_checks + 1))
      local actual_hdg_count
      actual_hdg_count=$(grep -c '^## ' "$qmd_path" 2>/dev/null) || true
      actual_hdg_count="${actual_hdg_count:-0}"
      if [[ "$actual_hdg_count" -eq 0 ]]; then
        pass "headings: none expected, none found"
        total_pass=$((total_pass + 1))
      else
        warn "headings: $actual_hdg_count found but none in manifest"
        total_pass=$((total_pass + 1))
        total_warn=$((total_warn + 1))
      fi
    fi

    # ── Check 4: download button ──
    total_checks=$((total_checks + 1))
    if [[ "$expected_dl" == "true" ]]; then
      if grep -q 'createDownloadButton' "$qmd_path" 2>/dev/null; then
        pass "download button: present"
        total_pass=$((total_pass + 1))
      else
        fail "download button: missing (expected)"
        total_fail=$((total_fail + 1))
      fi
    else
      if grep -q 'createDownloadButton' "$qmd_path" 2>/dev/null; then
        warn "download button: found but not in manifest"
        total_pass=$((total_pass + 1))
        total_warn=$((total_warn + 1))
      else
        pass "download button: none expected"
        total_pass=$((total_pass + 1))
      fi
    fi

    # ── Check 5: workbook callout ──
    total_checks=$((total_checks + 1))
    if [[ "$expected_wc" == "true" ]]; then
      if grep -q 'workbook_callout' "$qmd_path" 2>/dev/null; then
        pass "workbook callout: present"
        total_pass=$((total_pass + 1))
      else
        fail "workbook callout: missing (expected)"
        total_fail=$((total_fail + 1))
      fi
    else
      if grep -q 'workbook_callout' "$qmd_path" 2>/dev/null; then
        warn "workbook callout: found but not in manifest"
        total_pass=$((total_pass + 1))
        total_warn=$((total_warn + 1))
      else
        pass "workbook callout: none expected"
        total_pass=$((total_pass + 1))
      fi
    fi

    echo ""
  done

  # ── Summary ──
  echo "=========================================="
  echo "  Summary"
  echo "=========================================="
  echo ""
  echo "  Total checks:  $total_checks"
  printf "  Passed:         ${GREEN}%d${RESET}\n" "$total_pass"
  if (( total_fail > 0 )); then
    printf "  Failed:         ${RED}%d${RESET}\n" "$total_fail"
  else
    echo "  Failed:         0"
  fi
  if (( total_warn > 0 )); then
    printf "  Warnings:       ${YELLOW}%d${RESET}  (elements found but not in manifest)\n" "$total_warn"
  fi
  echo ""

  if (( total_fail == 0 )); then
    printf "${GREEN}All structural checks passed.${RESET}\n"
  else
    printf "${RED}%d check(s) failed — review above for details.${RESET}\n" "$total_fail"
  fi
  echo ""

  # Exit with failure count (capped at 125 for valid exit codes)
  if (( total_fail > 125 )); then
    return 125
  fi
  return "$total_fail"
}

main "$@"
