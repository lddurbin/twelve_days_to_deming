#!/usr/bin/env python3
"""undecodable_fonts.py — find the text poppler cannot decode, and take it out
of both comparison streams (#852).

Some of Neave's PDFs embed subset fonts whose glyphs poppler cannot map back
to Unicode, so it reports raw glyph codes instead. The subset assigns codes
in order from `!` (0x21), so what comes out is a consistent 1:1 substitution
cipher over ASCII punctuation and digits. Page 7 of Day 7's running banner:

    1"20,+*3$4552".*"6*3$7,2'&2-"/8,$9/:.8"+&2*3$;<&+"*3$ ...

which decodes (with `$` as the space) to "Targets, Appraisals, Performance
Indicators, ...". `pdftotext` and `pdftohtml -xml` return the identical
garbling, so both the paragraph comparator and the emphasis checker read it.

Until this module neither noticed. The garbled tokens entered both word
streams as ordinary words, aligned against nothing, and sat in each checker's
unaligned remainder as if they had been read and found different — when in
fact they were never read at all.

## Why not decode it

#852 weighed three options. Decoding recovers the text, but the map is
per-subset, there are 290 subsets across the corpus, and nothing
would check that a derived map stayed right. Documenting it alone leaves the
counts saying something untrue. This module takes the middle one — **detect
and exclude** — so the text lands in the unaligned remainder honestly, as
text nobody read, rather than as words.

## How a font is judged

By its whole text across the document, not per token or per page. A font is
undecodable when, over everything it sets in the PDF (runs of one repeated
character counted once, whitespace not counted),

  - under MAX_LETTER_SHARE of its characters are letters,
  - at least MIN_PUNCT_SHARE of them are ASCII punctuation, and
  - it uses at least MIN_DISTINCT_PUNCT different punctuation characters.

Each bound keeps real text in:

  - **Letters** keep prose in. The lowest letter share of any font setting
    real words is 0.34 (Day 11's `[WB 186]` workbook citations).
  - **Punctuation share** keeps figure fonts in. A control chart's tick labels
    (`0.10`, `6`, `10`) are letter-free too, but they are digits, and the
    paragraph comparator deliberately reads them. Bullets and arrows are
    non-ASCII, so they never count.
  - **Distinct punctuation** keeps bracket-and-label fonts in: a figure font
    setting `(`, `)`, `...` and one `UCL` label is 91% punctuation, but only
    three different characters. A cipher that assigns codes from `!` upward
    uses them all. Below six the only fonts it would catch that the other two
    bounds don't are fragments like `!"#` — no letters, no digits, nothing
    either checker could have matched — and a `().[]` figure font.
  - **Repeated characters counted once** keeps contents pages in: `Welcome
    .............. 1` is otherwise mostly punctuation, and the main
    Appendix's contents font read as undecodable on exactly that.

Measured 2026-09-23 over all 24 source PDFs (`pdftohtml -xml`, judged per font
family string, which carries the six-letter subset tag): 290 families, every
one of them a Cambria subset, 69,422 characters. The widest any of them comes
to a bound is a letter share of 0.17 and a punctuation share of 0.58. Every
flagged family that contains a letter run was read and is ciphertext.

Most of it is page furniture — running banners and footers — but not all:
Day 7's Hansard transcript page is almost entirely in one of these subsets,
and so is prose on a dozen other pages. None of it was ever compared before
this module either; it is now counted as unread rather than as words, and
workflow/validation/audits/README.md ("Text no tool reads") lists the pages a
human has to check by hand.

## The two consumers

  - scripts/lib/emphasis.py calls undecodable_fonts() and drops every
    character set in one of those fonts, so no garbled word enters the PDF
    stream. The emphasis side has the font id per character, so this is
    exact.

  - scripts/validate-transcription.sh runs this file as a filter over
    `pdftotext` output. That text carries no font information, so the filter
    removes the garbled strings themselves, scoped to the page they appear on
    (see strip()).
"""
import collections
import html
import re
import subprocess
import sys

# See "How a font is judged" above for the measurement behind both.
MAX_LETTER_SHARE = 0.25
MIN_PUNCT_SHARE = 0.4
MIN_DISTINCT_PUNCT = 6

# The shortest garbled token strip() will remove from `pdftotext` text. It
# works by substring, so a one- or two-character token such as `!` or `#$`
# would take real punctuation with it wherever it recurred on the page.
# Tokens that short carry no letters and at most two digits, so leaving them
# in costs the comparator nothing it could have matched.
MIN_STRIP_LEN = 3

_FONTSPEC = re.compile(r'<fontspec id="(\d+)" size="\d+" family="([^"]+)"')
_PAGE = re.compile(r'<page number="(\d+)".*?</page>', re.S)
_TEXT = re.compile(r'<text [^>]*font="(\d+)">(.*?)</text>', re.S)
_TAG = re.compile(r"<[^>]+>")

# A run of one repeated character counts once — see "How a font is judged".
_REPEAT = re.compile(r"(.)\1+")

# The page-marker line paragraphs.py --mark-pages writes. Duplicated rather
# than imported so this file stays runnable on its own; test_undecodable_fonts
# pins the two together.
_PAGE_MARKER = re.compile(r"^@@pdf-page (\d+)@@$")
FIRST_PAGE = 1


def is_punct(character):
    return "!" <= character <= "~" and not character.isalnum()


def pdftohtml_xml(pdf_path):
    return subprocess.run(
        ["pdftohtml", "-xml", "-i", "-q", "-stdout", pdf_path],
        capture_output=True, text=True, errors="replace").stdout


def _elements(xml):
    """Yield (page, font id, text) for every <text> element in `xml`."""
    for page in _PAGE.finditer(xml):
        for element in _TEXT.finditer(page[0]):
            yield (int(page[1]), element[1],
                   html.unescape(_TAG.sub("", element[2])))


def undecodable_fonts(xml):
    """The fontspec ids in `xml` whose text poppler could not decode.

    Judged per font *family* (which carries the subset tag), not per id:
    pdftohtml gives one subset several ids when it is used at several sizes,
    and a judgement per id would read a two-character use of the subset in
    isolation.
    """
    family = {m[1]: m[2] for m in _FONTSPEC.finditer(xml)}
    totals = collections.defaultdict(lambda: [0, 0, 0])  # chars, letters, punct
    distinct = collections.defaultdict(set)
    for _page, font_id, text in _elements(xml):
        counts = totals[family.get(font_id, font_id)]
        for character in _REPEAT.sub(r"\1", text):
            if character.isspace():
                continue
            counts[0] += 1
            if character.isalpha():
                counts[1] += 1
            elif is_punct(character):
                counts[2] += 1
                distinct[family.get(font_id, font_id)].add(character)
    garbled = {
        name for name, (chars, letters, punct) in totals.items()
        if chars and letters / chars < MAX_LETTER_SHARE
        and punct / chars >= MIN_PUNCT_SHARE
        and len(distinct[name]) >= MIN_DISTINCT_PUNCT
    }
    return {font_id for font_id, name in family.items() if name in garbled}


def garbled_tokens(xml):
    """{page: set of whitespace-delimited tokens} set in undecodable fonts."""
    fonts = undecodable_fonts(xml)
    pages = collections.defaultdict(set)
    for page, font_id, text in _elements(xml):
        if font_id in fonts:
            pages[page].update(text.split())
    return pages


def strip(text, tokens):
    """Remove each page's garbled tokens from marked `pdftotext` output.

    `text` carries paragraphs.py's page-marker lines; `tokens` is
    garbled_tokens()'s result. Removal is by substring, because `pdftotext
    -layout` glues neighbouring elements together — Day 7's footer comes out
    as `!"#$%$$&$$'"()$#$`, one garbled token from one subset with `#$` from
    another stuck to its end. Two bounds keep that from touching real text:
    it only ever runs on the page the token was read from, and only for
    tokens of at least MIN_STRIP_LEN characters. Longest first, so a token
    that contains a shorter one is removed whole.

    Returns (stripped text, number of characters removed).
    """
    page = FIRST_PAGE
    removed = 0
    ordered = {p: sorted((t for t in ts if len(t) >= MIN_STRIP_LEN),
                         key=len, reverse=True)
               for p, ts in tokens.items()}
    out = []
    for line in text.splitlines(keepends=True):
        marker = _PAGE_MARKER.match(line.rstrip("\n"))
        if marker:
            page = int(marker.group(1))
        else:
            for token in ordered.get(page, ()):
                if token in line:
                    removed += line.count(token) * len(token)
                    line = line.replace(token, " ")
        out.append(line)
    return "".join(out), removed


def main(argv):
    if len(argv) == 2 and argv[0] == "--strip":
        text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        stripped, _removed = strip(text, garbled_tokens(pdftohtml_xml(argv[1])))
        sys.stdout.buffer.write(stripped.encode("utf-8"))
        return 0
    if len(argv) == 2 and argv[0] == "--report":
        # How much of a PDF is undecodable, and where. `KEY=VALUE` lines, the
        # contract validate-transcription.sh reads its other helpers by. Page
        # counts include furniture; workflow/validation/audits/README.md says
        # which pages carry body prose.
        xml = pdftohtml_xml(argv[1])
        fonts = undecodable_fonts(xml)
        family = {m[1]: m[2] for m in _FONTSPEC.finditer(xml)}
        pages = collections.Counter()
        for page, font_id, text in _elements(xml):
            if font_id in fonts:
                pages[page] += len("".join(text.split()))
        print(f"FONTS={len({family[f] for f in fonts})}")
        print(f"CHARS={sum(pages.values())}")
        for page in sorted(pages):
            print(f"PAGE_{page}={pages[page]}")
        return 0
    print(f"Usage: {sys.argv[0]} --strip <pdf> < marked-pdftotext-text",
          file=sys.stderr)
    print(f"       {sys.argv[0]} --report <pdf>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
