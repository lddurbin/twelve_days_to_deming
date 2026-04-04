#!/usr/bin/env bash
#
# validate-transcription.sh — Compare source PDF text against QMD transcriptions
#
# Usage: ./scripts/validate-transcription.sh <day-number>
#   e.g. ./scripts/validate-transcription.sh 3
#
# Requires: pdftotext (brew install poppler)
#
# PDF letter-prefix mapping:
#   D=Day1, E=Day2, F=Day3, G=Day4, H=Day5, I=Day6,
#   J=Day7, K=Day8, L=Day9, M=Day10, N=Day11, O=Day12

set -euo pipefail

# Force C locale to avoid multibyte issues with pdftotext output
export LC_ALL=C

# ── Configuration ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PDF_DIR="$REPO_ROOT/12-Days-to-Deming/PDFs"
CONTENT_DIR="$REPO_ROOT/content/days"

# Map day numbers (1-12) to PDF letter prefixes (D-O)
# ASCII: D=68, day 1 → offset 0 → D, day 2 → offset 1 → E, etc.
day_to_prefix() {
  local day=$1
  printf "\\$(printf '%03o' $((67 + day)))"
}

# Minimum paragraph length (chars) to consider for matching
MIN_PARA_LEN=40

# ── Helpers ────────────────────────────────────────────────────

usage() {
  echo "Usage: $0 <day-number>"
  echo "  day-number: 1-12"
  echo ""
  echo "Compares source PDF text against QMD transcriptions and reports"
  echo "potential gaps — paragraphs in the PDF with no close match in the QMD files."
  exit 1
}

check_deps() {
  if ! command -v pdftotext &>/dev/null; then
    echo "Error: pdftotext not found. Install with: brew install poppler"
    exit 1
  fi
}

# Strip QMD markup to produce plain text
# Removes: YAML frontmatter, code fences (R/OJS/python), HTML tags,
# Quarto layout directives, markdown image syntax, link syntax
strip_qmd() {
  local file="$1"
  # First strip YAML frontmatter (only at start of file), then strip markup
  awk '
    # Skip YAML frontmatter: first line must be ---, skip until closing ---
    NR == 1 && /^---$/ { in_front = 1; next }
    in_front && /^---$/ { in_front = 0; next }
    in_front { next }
    # Skip code fence blocks
    /^```/ { in_code = !in_code; next }
    in_code { next }
    { print }
  ' "$file" | sed -E '
    # Remove Quarto layout directives
    /^:{2,}/d

    # Remove HTML tags
    s/<[^>]+>//g

    # Remove markdown image syntax ![alt](path){attrs}
    s/!\[[^]]*\]\([^)]*\)(\{[^}]*\})?//g

    # Remove markdown link syntax [text](url) → keep text
    s/\[([^]]*)\]\([^)]*\)/\1/g

    # Remove markdown emphasis markers
    s/\*\*([^*]*)\*\*/\1/g
    s/\*([^*]*)\*/\1/g

    # Remove markdown heading markers
    s/^#{1,6} //

    # Remove horizontal rules
    /^---+$/d
    /^\*\*\*+$/d

    # Remove blockquote markers (keep text)
    s/^> //
  '
}

# Extract text from PDF, normalise whitespace, filter boilerplate
extract_pdf_text() {
  local pdf="$1"
  pdftotext -layout "$pdf" - | sed -E '
    # Remove form feed characters
    s/\f//g
    # Remove embedded page numbers (standalone 1-3 digit numbers from layout mode)
    s/ [0-9]{1,3} / /g
    # Collapse runs of spaces
    s/  +/ /g
    # Trim leading/trailing whitespace
    s/^ +//
    s/ +$//
    # Remove copyright lines
    /Copyright/d
    # Remove page number lines (just a number alone)
    /^[0-9]+$/d
    # Remove "Page intentionally" lines
    /[Pp]age intentionally/d
    # Remove garbled encoding lines (non-empty, mostly non-alphanumeric)
    /^[!"#$%&()*+,.\/:;<=>?@^_{}|~ -][!"#$%&()*+,.\/:;<=>?@^_{}|~ -]*$/d
  '
}

# Split text into paragraphs (blocks separated by blank lines)
# Output: one paragraph per line (newlines within paragraph replaced with spaces)
# Filters: minimum length, and rejects paragraphs where <40% of chars are letters
# (catches garbled page headers/footers from pdftotext)
text_to_paragraphs() {
  awk '
    function is_readable(s,    letters, total, i, c) {
      total = 0; letters = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c != " ") {
          total++
          if (c ~ /[a-zA-Z]/) letters++
        }
      }
      return (total > 0 && (letters / total) >= 0.4)
    }

    /^[[:space:]]*$/ {
      if (para != "") {
        gsub(/[[:space:]]+/, " ", para)
        gsub(/^ +| +$/, "", para)
        if (length(para) >= '"$MIN_PARA_LEN"' && is_readable(para))
          print para
        para = ""
      }
      next
    }
    { para = (para == "") ? $0 : para " " $0 }
    END {
      if (para != "") {
        gsub(/[[:space:]]+/, " ", para)
        gsub(/^ +| +$/, "", para)
        if (length(para) >= '"$MIN_PARA_LEN"' && is_readable(para))
          print para
      }
    }
  '
}

# Normalise text for comparison: lowercase, strip punctuation, collapse whitespace.
# Also strips f/F to handle pdftotext ligature issues — many PDFs use fi/fl/ff/ffi
# ligature glyphs that pdftotext silently drops, producing "or" for "for",
# "irst" for "first", etc. Removing f from both sides makes them matchable.
normalise() {
  tr '[:upper:]' '[:lower:]' | sed -E '
    s/[^a-z0-9 ]/ /g
    s/f//g
    s/  +/ /g
    s/^ +//
    s/ +$//
  '
}

# Extract a "fingerprint" — first N significant words of a paragraph
fingerprint() {
  local text="$1"
  local n="${2:-8}"
  echo "$text" | normalise | awk -v n="$n" '{
    count = 0
    for (i = 1; i <= NF && count < n; i++) {
      if (length($i) > 2) {
        printf "%s ", $i
        count++
      }
    }
    print ""
  }' | sed 's/ *$//'
}

# Check if a PDF paragraph fingerprint appears in the QMD text
# Returns 0 if found, 1 if not
find_in_qmd() {
  local fingerprint="$1"
  local qmd_normalised="$2"

  # Split fingerprint into words and check if they appear in sequence
  # We check for a sliding window match: at least 5 consecutive words
  local words
  IFS=' ' read -ra words <<< "$fingerprint"
  local n_words=${#words[@]}

  if (( n_words < 5 )); then
    # For short fingerprints, require all words in order
    local pattern
    pattern=$(echo "$fingerprint" | sed 's/ /.*/g')
    grep -qiE "$pattern" <<< "$qmd_normalised" && return 0
    return 1
  fi

  # Try matching sliding windows of 5 consecutive words
  for (( i=0; i <= n_words - 5; i++ )); do
    local window="${words[$i]} ${words[$((i+1))]} ${words[$((i+2))]} ${words[$((i+3))]} ${words[$((i+4))]}"
    local pattern
    pattern=$(echo "$window" | sed 's/ /.*/g')
    if grep -qiE "$pattern" <<< "$qmd_normalised"; then
      return 0
    fi
  done

  return 1
}

# ── Main ───────────────────────────────────────────────────────

main() {
  local day_num="${1:-}"

  if [[ -z "$day_num" || ! "$day_num" =~ ^[0-9]+$ ]]; then
    usage
  fi

  if (( day_num < 1 || day_num > 12 )); then
    echo "Error: day-number must be between 1 and 12"
    exit 1
  fi

  check_deps

  local prefix
  prefix=$(day_to_prefix "$day_num")
  local day_dir
  day_dir=$(printf "day-%02d" "$day_num")

  # Find the source PDF
  local pdf_file
  pdf_file=$(ls "$PDF_DIR"/"${prefix}".Day.*.pdf 2>/dev/null | head -1)
  if [[ -z "$pdf_file" ]]; then
    echo "Error: No PDF found for Day $day_num (prefix $prefix) in $PDF_DIR"
    exit 1
  fi

  # Check QMD directory exists
  local qmd_dir="$CONTENT_DIR/$day_dir"
  if [[ ! -d "$qmd_dir" ]]; then
    echo "Error: No content directory found at $qmd_dir"
    exit 1
  fi

  local qmd_files
  qmd_files=$(ls "$qmd_dir"/*.qmd 2>/dev/null)
  if [[ -z "$qmd_files" ]]; then
    echo "Error: No QMD files found in $qmd_dir"
    exit 1
  fi

  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir" 2>/dev/null || true' EXIT

  echo "=========================================="
  echo "  Transcription Validation Report"
  echo "  Day $day_num"
  echo "=========================================="
  echo ""
  echo "Source PDF: $(basename "$pdf_file")"
  echo "QMD dir:   $day_dir/"
  echo "QMD files: $(echo "$qmd_files" | wc -l | tr -d ' ')"
  echo ""

  # Step 1: Extract and normalise PDF text
  echo "Extracting PDF text..."
  extract_pdf_text "$pdf_file" > "$tmpdir/pdf_raw.txt"
  extract_pdf_text "$pdf_file" | text_to_paragraphs > "$tmpdir/pdf_paras.txt"
  local pdf_para_count
  pdf_para_count=$(wc -l < "$tmpdir/pdf_paras.txt" | tr -d ' ')
  echo "  Found $pdf_para_count paragraphs in PDF (>=${MIN_PARA_LEN} chars each)"

  # Step 2: Extract and normalise QMD text (all files concatenated)
  echo "Extracting QMD text..."
  local qmd_combined="$tmpdir/qmd_combined.txt"
  > "$qmd_combined"
  while IFS= read -r qmd; do
    strip_qmd "$qmd" >> "$qmd_combined"
    echo "" >> "$qmd_combined"
  done <<< "$qmd_files"

  cat "$qmd_combined" | text_to_paragraphs > "$tmpdir/qmd_paras.txt"
  local qmd_para_count
  qmd_para_count=$(wc -l < "$tmpdir/qmd_paras.txt" | tr -d ' ')
  echo "  Found $qmd_para_count paragraphs in QMD files (>=${MIN_PARA_LEN} chars each)"

  # Normalise the full QMD text for searching — join into single line
  # so grep can match fingerprints that span original line boundaries
  local qmd_normalised
  qmd_normalised=$(cat "$qmd_combined" | normalise | tr '\n' ' ' | sed -E 's/  +/ /g')

  # Step 3: Check each PDF paragraph against QMD content
  echo ""
  echo "Comparing paragraphs..."
  echo ""

  local missing=0
  local matched=0
  local total=0
  local missing_paras=()

  while IFS= read -r para; do
    total=$((total + 1))
    local fp
    fp=$(fingerprint "$para")

    if [[ -z "$fp" ]]; then
      matched=$((matched + 1))
      continue
    fi

    if find_in_qmd "$fp" "$qmd_normalised"; then
      matched=$((matched + 1))
    else
      missing=$((missing + 1))
      missing_paras+=("$para")
    fi
  done < "$tmpdir/pdf_paras.txt"

  # Step 4: Report
  echo "=========================================="
  echo "  Results"
  echo "=========================================="
  echo ""
  echo "  PDF paragraphs checked:  $total"
  echo "  Matched in QMD:          $matched"
  echo "  Potentially missing:     $missing"
  echo ""

  if (( missing == 0 )); then
    echo "All PDF paragraphs appear to have matches in the QMD files."
    echo ""
  else
    local match_pct
    if (( total > 0 )); then
      match_pct=$(( (matched * 100) / total ))
    else
      match_pct=0
    fi
    echo "Match rate: ${match_pct}%"
    echo ""
    echo "=========================================="
    echo "  Potentially Missing Content"
    echo "=========================================="
    echo ""
    echo "The following PDF paragraphs had no close match in the QMD files."
    echo "Review these to determine if they are:"
    echo "  - Genuinely missing from the transcription"
    echo "  - Page headers/footers or boilerplate (false positives)"
    echo "  - Content intentionally omitted or restructured"
    echo ""

    local i=1
    for para in "${missing_paras[@]}"; do
      echo "--- Gap $i ---"
      # Show first 200 chars of the paragraph
      if (( ${#para} > 200 )); then
        echo "${para:0:200}..."
      else
        echo "$para"
      fi
      echo ""
      i=$((i + 1))
    done
  fi

  echo "=========================================="
  echo "  Notes"
  echo "=========================================="
  echo ""
  echo "  - False positives are expected for page headers, footers,"
  echo "    figure captions, and table content that pdftotext garbles"
  echo "  - Interactive elements (OJS/R code) in QMD have no PDF equivalent"
  echo "  - Some content may be intentionally restructured for the web version"
  echo ""
}

main "$@"
