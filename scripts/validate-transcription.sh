#!/usr/bin/env bash
#
# validate-transcription.sh — Compare source PDF text against QMD transcriptions
#
# Usage: ./scripts/validate-transcription.sh <day-number>
#        ./scripts/validate-transcription.sh --appendix <slug>
#   e.g. ./scripts/validate-transcription.sh 3
#        ./scripts/validate-transcription.sh --appendix contributions-balaji-reddie
#
# Reports five distinct kinds of gap, in five separate sections:
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
#   - Short:      a PDF block too short to score at all. The two filters in
#                 scripts/lib/paragraphs.py keep 40-byte, 40%-letter minimums
#                 on what enters similarity scoring, because a four-word
#                 heading finds a 0.5 "match" against any other four-word
#                 heading — but until #742 what they rejected simply vanished,
#                 576 blocks of it across the twelve days. Each one is now
#                 matched against the QMD's own short content and chapter
#                 headings, exactly rather than fuzzily, and whatever is not
#                 found is reported grouped by wording and stamped with its
#                 PDF page. See scripts/lib/short_content.py and issue #742.
#   - Reference:  a sentence pair that scores at or above
#                 REFERENCE_PAIR_THRESHOLD — credibly the same sentence —
#                 whose page/day/chapter numbers or bare numerals disagree.
#                 Cuts across the three above rather than refining them: a
#                 finding here is usually *also* a clean match, because one
#                 wrong digit in a long sentence scores above the altered
#                 threshold. "page 18" where the source says "page 19" is the
#                 most consequential defect the site can carry, since the
#                 enriched cross-reference link built on it sends the reader
#                 somewhere else entirely. See
#                 scripts/lib/paragraph_similarity.py and issue #738.
#
# Requires: pdftotext (brew install poppler)
#           ruby (YAML parsing for appendix manifests)
#           python3 (markup stripping and similarity scoring; stdlib only)
#           git, and shasum or sha256sum (recording validation provenance)
#
# Day mode uses the PDF letter-prefix mapping:
#   D=Day1, E=Day2, F=Day3, G=Day4, H=Day5, I=Day6,
#   J=Day7, K=Day8, L=Day9, M=Day10, N=Day11, O=Day12
#
# Appendix mode reads workflow/validation/appendix-<slug>-manifest.yml
# for `pdf_file` and `content_dir`.
#
# Every run overwrites a provenance record in workflow/validation/results/
# (day-NN.yml or appendix-<slug>.yml) with what was checked, against what,
# and what it found — see workflow/validation/results/README.md and #720.
# The `scorer_version` it stamps there covers every file that can change what
# a run reports, this script included: see scripts/lib/scorer-version.sh.
#
# That record also states what a run did *not* check (#743). Its `blocks:`
# section counts every block read on both sides and where each one went —
# rejected as page furniture, rejoined into the block before it, left under
# the length floor, or compared — because Day 3's bare `pdf_paragraphs: 288`
# gives a reader no way to see the 592 blocks it was distilled from.

set -euo pipefail

# Force C locale to avoid multibyte issues with pdftotext output
export LC_ALL=C

# ── Configuration ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Shared with scripts/check-validation-staleness.sh so the value this script
# stamps into results files and the value that script checks them against can
# only ever come from one definition — see #737.
# shellcheck source-path=SCRIPTDIR source=lib/scorer-version.sh
. "$REPO_ROOT/scripts/lib/scorer-version.sh"

PDF_DIR="$REPO_ROOT/12-Days-to-Deming/PDFs"
MANIFEST_DIR="$REPO_ROOT/workflow/validation"
TMPDIR_CLEANUP=""
SHA256_CMD=""  # set by check_deps()

# Map day numbers (1-12) to PDF letter prefixes (D-O)
# ASCII: D=68, day 1 → offset 0 → D, day 2 → offset 1 → E, etc.
day_to_prefix() {
  local day=$1
  printf "\\$(printf '%03o' $((67 + day)))"
}

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
  if ! command -v git &>/dev/null; then
    echo "Error: git not found (needed to record the scorer version)"
    exit 1
  fi
  # Cache the choice once here rather than re-probing PATH on every
  # sha256_of() call — SHA256_CMD is a script-level global, same pattern as
  # TMPDIR_CLEANUP, since check_deps() runs in the same shell as main().
  if command -v shasum &>/dev/null; then
    SHA256_CMD="shasum -a 256"
  elif command -v sha256sum &>/dev/null; then
    SHA256_CMD="sha256sum"
  else
    echo "Error: neither shasum nor sha256sum found (needed to hash the source PDF)"
    exit 1
  fi
}

# SHA-256 of a file, via whichever of shasum/sha256sum check_deps() found.
sha256_of() {
  $SHA256_CMD "$1" | awk '{print $1}'
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

# QMD markup stripping lives in scripts/lib/qmd_strip.py (#739). It used to be
# an untested awk + sed pipeline here; the constructs it has to take apart
# nest (an editorial `[...]` inside a `[...]{.deming_quote}` span), and a
# line-oriented regex cannot see that. This script keeps orchestration only.

# Extract text from PDF, normalise whitespace, filter boilerplate
#
# Form feeds become page-marker lines, and that stage runs first, before the
# `sed` below deletes anything (see mark_pages() in scripts/lib/paragraphs.py
# for the marker's shape and why the boundary cannot survive as a form feed).
# They used to be deleted outright by `tr`, which cost every downstream stage
# any way of saying which page a line came from — the page numbers #742's
# short-content report is triaged by.
#
# Never sed, either way. BSD sed (macOS, the only platform this script runs
# on) does not understand the `\f` escape and reads it as a literal `f`, so
# the `s/\f//g` this used to open with silently deleted every letter "f" from
# the PDF side of every comparison — "of far off" came out as "o ar o". That
# corruption was long misread as pdftotext mangling fi/fl/ff ligatures, and
# was "fixed" by stripping `f` from BOTH sides in normalise() so the two
# agreed. pdftotext in fact emits ligatures as plain ASCII here ("essential
# feature of" is byte-for-byte intact), so with the real bug fixed, both
# f-stripping workarounds are gone too.
extract_pdf_text() {
  local pdf="$1"
  # Note: no rule strips inline numbers. A previous `s/ [0-9]{1,3} / /g` meant
  # to drop layout-mode page numbers, but in a course built on "the 14 Points"
  # and "Day 1 page 33" it hit content instead — 18 occurrences of "the 14
  # Points" became "the Points" in Day 4 alone — while genuine page-number
  # lines are already handled by the /^[0-9]+$/d rule below. Keeping numbers
  # is also what lets similarity scoring see a mis-transcribed number at all.
  #
  # The trailing --workbook-refs pass drops the PDF's `[WB NN]` print-workbook
  # citations, which the site carries none of (the #195 decision) — so every
  # one of them was a guaranteed unmatched fragment, and its bare number a
  # standing reference mismatch under #738. It runs the same implementation
  # the QMD side runs, rather than a second sed copy free to drift from it.
  pdftotext -layout "$pdf" - \
    | python3 "$REPO_ROOT/scripts/lib/paragraphs.py" --mark-pages \
    | sed -E '
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
  ' | python3 "$REPO_ROOT/scripts/lib/qmd_strip.py" --workbook-refs
}

# Split text into paragraphs (blocks separated by blank lines)
# Output: one paragraph per line, ready for paragraph_similarity.py.
#
# Paragraph assembly lives in scripts/lib/paragraphs.py (#741). It used to be
# an awk function here that collapsed each block onto one line and dropped the
# ones too short or too garbled to score. The job it could not do is the one
# that needed adding: a blank line is not always a paragraph break, and three
# of #732's false-positive categories are just that — a mid-sentence PDF page
# break, a blockquote split from its lead-in, a lettered list split into one
# block per item. Rejoining those has to happen after the readability filter
# (the garbled page header sits between the two halves of a broken sentence)
# and before the length floor (the list items are under it individually),
# which is a three-stage pipeline, not a line-at-a-time awk rule.
#
# This script keeps orchestration only, as it does for qmd_strip.py.
text_to_paragraphs() {
  python3 "$REPO_ROOT/scripts/lib/paragraphs.py"
}

# Count what that assembly did with every block of one side's text (#743).
# Prints five `KEY=VALUE` lines — TOTAL, UNREADABLE, REJOINED, SHORT, COMPARED
# — which partition exactly, so the provenance record can state what a run did
# *not* check beside what it did. Before this, Day 3's results file said
# `pdf_paragraphs: 288` and nothing about the 592 blocks that were read to
# reach it. See Accounting in scripts/lib/paragraphs.py.
account_blocks() {
  python3 "$REPO_ROOT/scripts/lib/paragraphs.py" --counts < "$1"
}

# ── Main ───────────────────────────────────────────────────────

main() {
  check_deps

  # ── Argument parsing ──
  local pdf_file="" qmd_dir="" label="" result_file="" result_identity=""

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
    result_file="$MANIFEST_DIR/results/appendix-${slug}.yml"
    result_identity="appendix: $slug"
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
    result_file="$MANIFEST_DIR/results/day-$(printf '%02d' "$day_num").yml"
    result_identity="day: $day_num"
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
  #
  # The length floor is paragraphs.py's to define — the same reasoning as the
  # similarity thresholds below, which this script also reads back rather than
  # keeping its own copy of. Asked for once here, not per progress line.
  local min_para_len
  min_para_len=$(python3 "$REPO_ROOT/scripts/lib/paragraphs.py" --min-length)
  echo "Extracting PDF text..."
  # Kept as a file rather than piped straight through, because the
  # short-content pass (#742) reads the same extracted text: one extraction,
  # two consumers, so the two can't disagree about what the PDF says.
  local pdf_text="$tmpdir/pdf_text.txt"
  extract_pdf_text "$pdf_file" > "$pdf_text"
  text_to_paragraphs < "$pdf_text" > "$tmpdir/pdf_paras.txt"
  local pdf_para_count
  pdf_para_count=$(wc -l < "$tmpdir/pdf_paras.txt" | tr -d ' ')
  echo "  Found $pdf_para_count paragraphs in PDF (>=${min_para_len} bytes each)"

  # Step 2: Extract and normalise QMD text (all files concatenated)
  echo "Extracting QMD text..."
  local qmd_combined="$tmpdir/qmd_combined.txt"
  # One process for the whole day, not one per chapter: the module writes the
  # blank line that separates chapters itself, so the paragraph boundary
  # between the last paragraph of one chapter and the first of the next is
  # part of its tested contract rather than a detail of this loop.
  if ! python3 "$REPO_ROOT/scripts/lib/qmd_strip.py" "${qmd_files[@]}" > "$qmd_combined"; then
    echo "Error: QMD markup stripping failed (see the Python error above)." >&2
    echo "       scripts/lib/qmd_strip.py" >&2
    exit 1
  fi

  text_to_paragraphs < "$qmd_combined" > "$tmpdir/qmd_paras.txt"
  local qmd_para_count
  qmd_para_count=$(wc -l < "$tmpdir/qmd_paras.txt" | tr -d ' ')
  echo "  Found $qmd_para_count paragraphs in QMD files (>=${min_para_len} bytes each)"

  # Step 2b: account for every block on both sides (#743). The two counts
  # above say what entered comparison; these say what was read to get there
  # and where the rest went, so the provenance record can state the residue
  # instead of leaving it invisible.
  local pdf_counts="$tmpdir/pdf_counts.txt" qmd_counts="$tmpdir/qmd_counts.txt"
  account_blocks "$pdf_text" > "$pdf_counts"
  account_blocks "$qmd_combined" > "$qmd_counts"

  local pdf_blocks pdf_unreadable pdf_rejoined pdf_short pdf_compared
  local qmd_blocks qmd_unreadable qmd_rejoined qmd_short qmd_compared
  pdf_blocks=$(sed -n 's/^TOTAL=//p' "$pdf_counts")
  pdf_unreadable=$(sed -n 's/^UNREADABLE=//p' "$pdf_counts")
  pdf_rejoined=$(sed -n 's/^REJOINED=//p' "$pdf_counts")
  pdf_short=$(sed -n 's/^SHORT=//p' "$pdf_counts")
  pdf_compared=$(sed -n 's/^COMPARED=//p' "$pdf_counts")
  qmd_blocks=$(sed -n 's/^TOTAL=//p' "$qmd_counts")
  qmd_unreadable=$(sed -n 's/^UNREADABLE=//p' "$qmd_counts")
  qmd_rejoined=$(sed -n 's/^REJOINED=//p' "$qmd_counts")
  qmd_short=$(sed -n 's/^SHORT=//p' "$qmd_counts")
  qmd_compared=$(sed -n 's/^COMPARED=//p' "$qmd_counts")
  if ! [[ "$pdf_blocks" =~ ^[0-9]+$ && "$pdf_unreadable" =~ ^[0-9]+$ \
       && "$pdf_rejoined" =~ ^[0-9]+$ && "$pdf_short" =~ ^[0-9]+$ \
       && "$pdf_compared" =~ ^[0-9]+$ \
       && "$qmd_blocks" =~ ^[0-9]+$ && "$qmd_unreadable" =~ ^[0-9]+$ \
       && "$qmd_rejoined" =~ ^[0-9]+$ && "$qmd_short" =~ ^[0-9]+$ \
       && "$qmd_compared" =~ ^[0-9]+$ ]]; then
    echo "Error: block accounting returned no usable counts." >&2
    exit 1
  fi
  # The one cross-check worth making here: `compared` is counted by
  # paragraphs.py from its own partition, while the two counts above come from
  # `wc -l` over what it wrote. They are the same population by construction,
  # so a disagreement means the paragraph stream and the accounting have
  # stopped describing the same run — and every residue number below would be
  # measured against the wrong denominator.
  if (( pdf_compared != pdf_para_count || qmd_compared != qmd_para_count )); then
    echo "Error: block accounting disagrees with the paragraphs written" >&2
    echo "       (PDF $pdf_compared vs $pdf_para_count, QMD $qmd_compared vs $qmd_para_count)." >&2
    exit 1
  fi

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
  local reference
  local missing_threshold altered_threshold unsourced_threshold reference_threshold
  missing=$(sed -n 's/^MISSING_COUNT=//p' "$altered_report")
  matched=$(sed -n 's/^MATCHED_COUNT=//p' "$altered_report")
  altered=$(sed -n 's/^ALTERED_COUNT=//p' "$altered_report")
  flagged=$(sed -n 's/^FLAGGED_SENTENCES=//p' "$altered_report")
  near_match=$(sed -n 's/^NEAR_MATCH_SENTENCES=//p' "$altered_report")
  unsourced=$(sed -n 's/^UNSOURCED_COUNT=//p' "$altered_report")
  unsourced_sentences=$(sed -n 's/^UNSOURCED_SENTENCES=//p' "$altered_report")
  reference=$(sed -n 's/^REFERENCE_MISMATCHES=//p' "$altered_report")
  missing_threshold=$(sed -n 's/^MISSING_THRESHOLD=//p' "$altered_report")
  altered_threshold=$(sed -n 's/^ALTERED_THRESHOLD=//p' "$altered_report")
  unsourced_threshold=$(sed -n 's/^UNSOURCED_THRESHOLD=//p' "$altered_report")
  reference_threshold=$(sed -n 's/^REFERENCE_THRESHOLD=//p' "$altered_report")
  # A non-numeric count here would corrupt the arithmetic below into a silently
  # wrong report, so fail loudly instead. Thresholds get the same treatment
  # as the counts (a real numeric-shape check, not just non-empty) — Python's
  # float formatting always includes a decimal point, even for a whole
  # number like 1.0, so this shape is safe for every value main() can print.
  if ! [[ "$missing" =~ ^[0-9]+$ && "$matched" =~ ^[0-9]+$ && "$altered" =~ ^[0-9]+$ \
       && "$flagged" =~ ^[0-9]+$ && "$near_match" =~ ^[0-9]+$ \
       && "$unsourced" =~ ^[0-9]+$ && "$unsourced_sentences" =~ ^[0-9]+$ \
       && "$reference" =~ ^[0-9]+$ \
       && "$missing_threshold" =~ ^[0-9]+\.[0-9]+$ \
       && "$altered_threshold" =~ ^[0-9]+\.[0-9]+$ \
       && "$unsourced_threshold" =~ ^[0-9]+\.[0-9]+$ \
       && "$reference_threshold" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Error: similarity scoring returned no usable counts." >&2
    exit 1
  fi

  # Step 3b: account for what the paragraph filters dropped (#742). Everything
  # under the length floor is too short for the scoring above to say anything
  # useful about, so it is matched exactly instead — against the QMD's own
  # short content and its chapter headings — and whatever isn't found is
  # reported rather than silently discarded, as it was until now.
  local short_report="$tmpdir/short_report.txt"
  if ! python3 "$REPO_ROOT/scripts/lib/short_content.py" \
       "$pdf_text" "$qmd_combined" "${qmd_files[@]}" \
       > "$short_report"; then
    echo "Error: the short-content pass failed (see the Python error above)." >&2
    echo "       scripts/lib/short_content.py" >&2
    exit 1
  fi

  local short_checked short_matched short_unmatched short_unjudged
  short_checked=$(sed -n 's/^SHORT_CHECKED=//p' "$short_report")
  short_matched=$(sed -n 's/^SHORT_MATCHED=//p' "$short_report")
  short_unmatched=$(sed -n 's/^SHORT_UNMATCHED=//p' "$short_report")
  short_unjudged=$(sed -n 's/^SHORT_UNJUDGED=//p' "$short_report")
  if ! [[ "$short_checked" =~ ^[0-9]+$ && "$short_matched" =~ ^[0-9]+$ \
       && "$short_unmatched" =~ ^[0-9]+$ && "$short_unjudged" =~ ^[0-9]+$ ]]; then
    echo "Error: the short-content pass returned no usable counts." >&2
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
  echo "  Reference mismatches:        $reference"
  echo "  Short content (below floor): $short_checked"
  echo "    - matched in the QMD:            $short_matched"
  echo "    - not found:                     $short_unmatched"
  echo "    - set aside (tables, contents):  $short_unjudged"
  # A separate population, not part of the three above: blocks the readability
  # filter rejected as page furniture. From the block accounting rather than
  # the short-content pass, so the number printed here and the one recorded in
  # provenance can only ever come from one measurement.
  echo "  Unreadable blocks (furniture): $pdf_unreadable"
  echo "  Rejoined into the block before: $pdf_rejoined of $pdf_blocks read"
  echo ""

  if (( missing == 0 && altered == 0 && unsourced == 0 && reference == 0 )); then
    echo "All PDF paragraphs appear to have clean matches in the QMD files,"
    echo "no QMD content is without a credible source in the PDF, and every"
    echo "page, day and chapter number agrees with the source."
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

    if (( missing > 0 || altered > 0 || unsourced > 0 || reference > 0 )); then
      # Skip the KEY=VALUE header block (everything up to its trailing blank
      # line) rather than a fixed line count — see paragraph_similarity.py.
      # The body holds the Reference, Missing, Altered, and Unsourced
      # sections when non-empty; paragraph_similarity.py separates them
      # itself, and leads with Reference — see render_reference_mismatches().
      sed '1,/^$/d' "$altered_report"
    fi
  fi

  # Printed outside the split above, not inside either branch of it: these
  # findings are about content the similarity pass never scored, so a day can
  # be clean by every count above and still be missing a heading.
  if (( short_unmatched > 0 || short_unjudged > 0 )); then
    sed '1,/^$/d' "$short_report"
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
  echo "  - Reference mismatches are counted separately from everything above"
  echo "    and mostly overlap it: a pair can be a clean match and still point"
  echo "    at the wrong page. Read that section first — it is the shortest"
  echo "    and the one similarity scoring cannot see for you."
  echo "  - Short content is matched exactly, not scored: a line of four words"
  echo "    cannot support a similarity judgement, so that section says only"
  echo "    whether the wording is present on the site, never whether it drifted."
  echo ""

  # Step 5: record provenance (#720). The script writes this itself, rather
  # than a human transcribing numbers by hand, so it can't drift from what
  # was actually run. One file per day/appendix (not a shared file) for the
  # same additive-not-positional reason docs/changesets/ and
  # docs/deviations/ already use — see workflow/validation/results/README.md.
  mkdir -p "$MANIFEST_DIR/results"
  local source_sha256 scorer_version
  source_sha256=$(sha256_of "$pdf_file")
  scorer_version=$(compute_scorer_version "$REPO_ROOT")
  cat > "$result_file" <<EOF
$result_identity
validated_at: $(date +%Y-%m-%d)
source_pdf: $(basename "$pdf_file")
source_sha256: $source_sha256
scorer_version: $scorer_version
thresholds:
  missing: $missing_threshold
  altered: $altered_threshold
  unsourced: $unsourced_threshold
  reference: $reference_threshold
counts:
  pdf_paragraphs: $total
  qmd_paragraphs: $qmd_para_count
  matched_cleanly: $matched
  altered: $altered
  flagged_sentences: $flagged
  near_certain: $near_match
  missing: $missing
  unsourced: $unsourced
  unsourced_sentences: $unsourced_sentences
  reference_mismatches: $reference
  short_checked: $short_checked
  short_matched: $short_matched
  short_unmatched: $short_unmatched
  short_unjudged: $short_unjudged
blocks:
  pdf:
    total: $pdf_blocks
    unreadable: $pdf_unreadable
    rejoined: $pdf_rejoined
    short: $pdf_short
    compared: $pdf_compared
  qmd:
    total: $qmd_blocks
    unreadable: $qmd_unreadable
    rejoined: $qmd_rejoined
    short: $qmd_short
    compared: $qmd_compared
EOF
  echo "Provenance recorded: ${result_file#"$REPO_ROOT/"}"
}

main "$@"
