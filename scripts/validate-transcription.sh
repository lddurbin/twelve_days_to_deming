#!/usr/bin/env bash
#
# validate-transcription.sh — Compare source PDF text against QMD transcriptions
#
# Usage: ./scripts/validate-transcription.sh <day-number>
#        ./scripts/validate-transcription.sh --appendix <slug>
#   e.g. ./scripts/validate-transcription.sh 3
#        ./scripts/validate-transcription.sh --appendix contributions-balaji-reddie
#
# Reports three distinct kinds of gap, in three separate sections:
#   - Missing:    a PDF paragraph whose single best-scoring sentence still
#                 falls below MISSING_SIMILARITY_THRESHOLD against every
#                 sentence in the QMD text — nothing in the chapter resembles
#                 any part of it closely enough to call it present. Derived
#                 from the same sentence-level score distribution as
#                 "Altered" below, rather than a separate presence check: see
#                 scripts/lib/paragraph_similarity.py and issue #719.
#   - Altered:    a PDF paragraph that IS present (cleared the missing bar),
#                 but that contains one or more sentences whose closest-matching
#                 QMD sentence differs from it by more than
#                 ALTERED_SIMILARITY_THRESHOLD — e.g. a swapped word, a
#                 paraphrased sentence, or dropped detail past the opening
#                 words, none of which the presence check alone can see.
#                 Scored at sentence (not paragraph) granularity: a single
#                 swapped word is diluted to near-invisibility across a whole
#                 paragraph of otherwise-unchanged text. See
#                 scripts/lib/paragraph_similarity.py and issue #677.
#   - Unsourced:  the reverse of both of the above — a QMD paragraph with a
#                 sentence that has no credible match anywhere in the PDF at
#                 all, at UNSOURCED_SIMILARITY_THRESHOLD. Missing/Altered can
#                 only report on paragraphs the PDF actually contains, so
#                 fabricated QMD content with no PDF counterpart was
#                 previously invisible to this script by construction. See
#                 scripts/lib/paragraph_similarity.py and issue #718. Cannot
#                 catch content copied verbatim from elsewhere in the same
#                 PDF — that scores a perfect match against its true,
#                 wrongly-relocated origin (see #645).
#
# Requires: pdftotext (brew install poppler)
#           ruby (YAML parsing for appendix manifests)
#           python3 (paragraph similarity scoring; no third-party packages)
#
# Day mode uses the PDF letter-prefix mapping:
#   D=Day1, E=Day2, F=Day3, G=Day4, H=Day5, I=Day6,
#   J=Day7, K=Day8, L=Day9, M=Day10, N=Day11, O=Day12
#
# Appendix mode reads workflow/validation/appendix-<slug>-manifest.yml
# for `pdf_file` and `content_dir`.

set -euo pipefail

# Force C locale to avoid multibyte issues with pdftotext output
export LC_ALL=C

# ── Configuration ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PDF_DIR="$REPO_ROOT/12-Days-to-Deming/PDFs"
MANIFEST_DIR="$REPO_ROOT/workflow/validation"
TMPDIR_CLEANUP=""

# Map day numbers (1-12) to PDF letter prefixes (D-O)
# ASCII: D=68, day 1 → offset 0 → D, day 2 → offset 1 → E, etc.
day_to_prefix() {
  local day=$1
  printf "\\$(printf '%03o' $((67 + day)))"
}

# Minimum paragraph length (chars) to consider for matching
MIN_PARA_LEN=40

# Similarity ratio (0-1) below which a sentence within a "present" paragraph
# is flagged as "altered" rather than a clean match. Scored by
# paragraph_similarity.py, which compares one PDF sentence against every QMD
# sentence in the day, word by word.
#
# The threshold itself lives in that module, as ALTERED_SIMILARITY_THRESHOLD,
# alongside the rationale for its value and the tests that pin it. This script
# deliberately keeps no copy of the number: a second definition here could drift
# from the one the test suite checks, leaving the suite green while validation
# ran at a different threshold.

# ── Helpers ────────────────────────────────────────────────────

usage() {
  echo "Usage: $0 <day-number>"
  echo "       $0 --appendix <slug>"
  echo ""
  echo "  day-number:        1-12"
  echo "  --appendix <slug>: uses workflow/validation/appendix-<slug>-manifest.yml"
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
  if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found (needed for paragraph similarity scoring)"
    exit 1
  fi
}

# Read `pdf_file` and `content_dir` from an appendix manifest.
# Prints two lines: PDF_FILE=... then CONTENT_DIR=...
read_appendix_manifest() {
  local manifest="$1"
  if ! command -v ruby &>/dev/null; then
    echo "Error: ruby not found (needed for YAML parsing)" >&2
    exit 1
  fi
  ruby -ryaml -e '
    begin
      data = YAML.safe_load(File.read(ARGV[0]))
    rescue => e
      $stderr.puts "Error parsing manifest #{ARGV[0]}: #{e.message}"
      exit 1
    end
    puts "PDF_FILE=#{data["pdf_file"] || ""}"
    puts "CONTENT_DIR=#{data["content_dir"] || ""}"
  ' "$manifest"
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
#
# Form feeds are stripped with `tr`, not sed. BSD sed (macOS, the only
# platform this script runs on) does not understand the `\f` escape and reads
# it as a literal `f`, so the `s/\f//g` this used to open with silently
# deleted every letter "f" from the PDF side of every comparison — "of far
# off" came out as "o ar o". That corruption was long misread as pdftotext
# mangling fi/fl/ff ligatures, and was "fixed" by stripping `f` from BOTH
# sides in normalise() so the two agreed. pdftotext in fact emits ligatures
# as plain ASCII here ("essential feature of" is byte-for-byte intact), so
# with the real bug fixed, both f-stripping workarounds are gone too.
extract_pdf_text() {
  local pdf="$1"
  # Note: no rule strips inline numbers. A previous `s/ [0-9]{1,3} / /g` meant
  # to drop layout-mode page numbers, but in a course built on "the 14 Points"
  # and "Day 1 page 33" it hit content instead — 18 occurrences of "the 14
  # Points" became "the Points" in Day 4 alone — while genuine page-number
  # lines are already handled by the /^[0-9]+$/d rule below. Keeping numbers
  # is also what lets similarity scoring see a mis-transcribed number at all.
  pdftotext -layout "$pdf" - | tr -d '\014' | sed -E '
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

# ── Main ───────────────────────────────────────────────────────

main() {
  check_deps

  # ── Argument parsing ──
  local pdf_file="" qmd_dir="" label=""

  if [[ "${1:-}" == "--appendix" ]]; then
    local slug="${2:-}"
    if [[ -z "$slug" ]]; then
      echo "Error: --appendix requires a slug (e.g. contributions-balaji-reddie)"
      usage
    fi
    if [[ ! "$slug" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Error: slug must contain only letters, digits, hyphens, and underscores"
      exit 1
    fi
    local manifest="$MANIFEST_DIR/appendix-${slug}-manifest.yml"
    if [[ ! -f "$manifest" ]]; then
      echo "Error: No manifest found at $manifest"
      exit 1
    fi

    local manifest_pdf="" manifest_content=""
    while IFS='=' read -r key value; do
      case "$key" in
        PDF_FILE)    manifest_pdf="$value" ;;
        CONTENT_DIR) manifest_content="$value" ;;
      esac
    done < <(read_appendix_manifest "$manifest")

    if [[ -z "$manifest_pdf" || -z "$manifest_content" ]]; then
      echo "Error: appendix manifest must declare pdf_file and content_dir"
      exit 1
    fi

    pdf_file="$PDF_DIR/$manifest_pdf"
    qmd_dir="$REPO_ROOT/$manifest_content"
    label="Appendix: $slug"
  elif [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
    local day_num="$1"
    if (( day_num < 1 || day_num > 12 )); then
      echo "Error: day-number must be between 1 and 12"
      exit 1
    fi

    local prefix
    prefix=$(day_to_prefix "$day_num")
    local day_dir
    day_dir=$(printf "day-%02d" "$day_num")

    local pdf_glob=( "$PDF_DIR/${prefix}".Day.*.pdf )
    pdf_file="${pdf_glob[0]}"
    if [[ ! -e "$pdf_file" ]]; then
      echo "Error: No PDF found for Day $day_num (prefix $prefix) in $PDF_DIR"
      exit 1
    fi

    qmd_dir="$REPO_ROOT/content/days/$day_dir"
    label="Day $day_num"
  else
    usage
  fi

  if [[ ! -e "$pdf_file" ]]; then
    echo "Error: PDF not found at $pdf_file"
    exit 1
  fi

  if [[ ! -d "$qmd_dir" ]]; then
    echo "Error: No content directory found at $qmd_dir"
    exit 1
  fi

  local qmd_files=( "$qmd_dir"/*.qmd )
  if [[ ! -e "${qmd_files[0]}" ]]; then
    echo "Error: No QMD files found in $qmd_dir"
    exit 1
  fi

  # TMPDIR_CLEANUP is a script-level global so the EXIT trap can still see
  # it after main() returns (under set -u, a local would be unbound).
  TMPDIR_CLEANUP=$(mktemp -d)
  local tmpdir="$TMPDIR_CLEANUP"
  trap 'rm -rf "$TMPDIR_CLEANUP" 2>/dev/null || true' EXIT

  echo "=========================================="
  echo "  Transcription Validation Report"
  echo "  $label"
  echo "=========================================="
  echo ""
  echo "Source PDF: $(basename "$pdf_file")"
  echo "QMD dir:   ${qmd_dir#"$REPO_ROOT/"}/"
  echo "QMD files: ${#qmd_files[@]}"
  echo ""

  # Step 1: Extract and normalise PDF text
  echo "Extracting PDF text..."
  extract_pdf_text "$pdf_file" | text_to_paragraphs > "$tmpdir/pdf_paras.txt"
  local pdf_para_count
  pdf_para_count=$(wc -l < "$tmpdir/pdf_paras.txt" | tr -d ' ')
  echo "  Found $pdf_para_count paragraphs in PDF (>=${MIN_PARA_LEN} chars each)"

  # Step 2: Extract and normalise QMD text (all files concatenated)
  echo "Extracting QMD text..."
  local qmd_combined="$tmpdir/qmd_combined.txt"
  > "$qmd_combined"
  for qmd in "${qmd_files[@]}"; do
    strip_qmd "$qmd" >> "$qmd_combined"
    echo "" >> "$qmd_combined"
  done

  text_to_paragraphs < "$qmd_combined" > "$tmpdir/qmd_paras.txt"
  local qmd_para_count
  qmd_para_count=$(wc -l < "$tmpdir/qmd_paras.txt" | tr -d ' ')
  echo "  Found $qmd_para_count paragraphs in QMD files (>=${MIN_PARA_LEN} chars each)"

  # Step 3: score every PDF paragraph's best-matching QMD sentence. The
  # missing/altered/matched split is derived entirely from that score
  # distribution (see MISSING_SIMILARITY_THRESHOLD in paragraph_similarity.py
  # and issue #719) rather than a separate presence check, so there is one
  # source of truth instead of two disagreeing ones. The same call also runs
  # the reverse pass (#718): QMD paragraphs walking the full PDF paragraph
  # pool, to catch QMD content with no credible PDF source at all.
  echo ""
  echo "Comparing paragraphs..."
  echo ""

  local total="$pdf_para_count"
  local altered_report="$tmpdir/altered_report.txt"
  if ! python3 "$REPO_ROOT/scripts/lib/paragraph_similarity.py" \
       "$tmpdir/pdf_paras.txt" "$tmpdir/qmd_paras.txt" \
       > "$altered_report"; then
    echo "Error: similarity scoring failed (see the Python error above)." >&2
    echo "       scripts/lib/paragraph_similarity.py" >&2
    exit 1
  fi

  # Read counts by key, not by line number, so the helper can grow new header
  # fields without silently shifting what this parses.
  local missing matched altered flagged near_match unsourced unsourced_sentences
  missing=$(sed -n 's/^MISSING_COUNT=//p' "$altered_report")
  matched=$(sed -n 's/^MATCHED_COUNT=//p' "$altered_report")
  altered=$(sed -n 's/^ALTERED_COUNT=//p' "$altered_report")
  flagged=$(sed -n 's/^FLAGGED_SENTENCES=//p' "$altered_report")
  near_match=$(sed -n 's/^NEAR_MATCH_SENTENCES=//p' "$altered_report")
  unsourced=$(sed -n 's/^UNSOURCED_COUNT=//p' "$altered_report")
  unsourced_sentences=$(sed -n 's/^UNSOURCED_SENTENCES=//p' "$altered_report")
  # A non-numeric count here would corrupt the arithmetic below into a silently
  # wrong report, so fail loudly instead.
  if ! [[ "$missing" =~ ^[0-9]+$ && "$matched" =~ ^[0-9]+$ && "$altered" =~ ^[0-9]+$ \
       && "$flagged" =~ ^[0-9]+$ && "$near_match" =~ ^[0-9]+$ \
       && "$unsourced" =~ ^[0-9]+$ && "$unsourced_sentences" =~ ^[0-9]+$ ]]; then
    echo "Error: similarity scoring returned no usable counts." >&2
    exit 1
  fi

  # Step 4: Report
  echo "=========================================="
  echo "  Results"
  echo "=========================================="
  echo ""
  echo "  PDF paragraphs checked:      $total"
  echo "  Matched cleanly:             $matched"
  echo "  Altered (present, modified): $altered"
  echo "    - sentences flagged:             $flagged"
  echo "    - near-certain defects (>=90%):  $near_match"
  echo "  Potentially missing:         $missing"
  echo "  Unsourced QMD content:       $unsourced"
  echo "    - sentences flagged:             $unsourced_sentences"
  echo ""

  if (( missing == 0 && altered == 0 && unsourced == 0 )); then
    echo "All PDF paragraphs appear to have clean matches in the QMD files,"
    echo "and no QMD content is without a credible source in the PDF."
    echo ""
  else
    local match_pct
    if (( total > 0 )); then
      match_pct=$(( (matched * 100) / total ))
    else
      match_pct=0
    fi
    echo "Clean match rate: ${match_pct}%"
    echo ""

    if (( missing > 0 || altered > 0 || unsourced > 0 )); then
      # Skip the KEY=VALUE header block (everything up to its trailing blank
      # line) rather than a fixed line count — see paragraph_similarity.py.
      # The body holds the Missing, Altered, and Unsourced sections when
      # non-empty; paragraph_similarity.py separates them itself.
      sed '1,/^$/d' "$altered_report"
    fi
  fi

  echo "=========================================="
  echo "  Notes"
  echo "=========================================="
  echo ""
  echo "  - False positives are expected for page headers, footers,"
  echo "    figure captions, and table content that pdftotext garbles"
  echo "  - Interactive elements (OJS/R code) in QMD have no PDF equivalent"
  echo "  - Some content may be intentionally restructured for the web version"
  echo "  - Altered flags are a triage filter, not a verdict: they only say"
  echo "    the closest QMD match differs from the source by more than the"
  echo "    threshold. Confirm against the actual page image before treating"
  echo "    a flag as a defect."
  echo "  - Unsourced flags are expected for legitimate site-only content:"
  echo "    activity prompts, button labels, figure captions. They cannot"
  echo "    catch a sentence copied verbatim from elsewhere in the same PDF —"
  echo "    that scores a perfect match against its true, wrongly-relocated"
  echo "    origin. See scripts/lib/paragraph_similarity.py and issue #645."
  echo ""
}

main "$@"
