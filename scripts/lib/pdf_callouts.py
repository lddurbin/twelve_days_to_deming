#!/usr/bin/env python3
"""pdf_callouts.py — remove the printed page's footnote callouts from the PDF
side of the comparison.

Helper for scripts/validate-transcription.sh (#755). This is the PDF-side
counterpart to the `[^a]` / `^[a]^` rule in scripts/lib/qmd_strip.py: both
sides carry a footnote apparatus, both apparatuses are markup rather than
prose, and a comparison that strips one and keeps the other manufactures a
difference on every page that has a footnote.

Neave's pages hang superscript letters off words — `Improvement`^b^, `medal`^b^,
`care.”`^c^ — each defined in that day's *Approvals, Acknowledgments and
Information* section at the end of the file. `pdftotext` has no superscript,
so it renders the callout as an ordinary character glued onto whatever
precedes it, with no space. The site carries no such apparatus for most of
them, and correctly carries none where it doesn't: every callout is therefore
a token the PDF has and the QMD doesn't, sitting inside an otherwise-perfect
sentence. #732 catalogued the shape on Day 9; it is the last of that triage's
ten false-positive categories.

## Why this is bounded by evidence rather than by shape

**A rule that strips a trailing letter off a word is dangerous by
construction.** `extractd` -> `extract` is right; the same rule applied blindly
is how you hide `of` vs `off`, `manage` vs `managed`, `reason` vs `reasons` —
the substitutions this comparator exists to catch. paragraph_similarity.py
already carries a scar from exactly this (see normalise(), which records why
stripping the letter `f` from both sides was wrong), and the danger is not
hypothetical: Day 11's PDF reads "without good rea- sons" where the site reads
"without good reason", and that pair sits in the same near-certain band as the
callouts, five lines away from them.

So every bound below is justified by a count over the twelve source PDFs,
measured at `8d449e1`, and each one is load-bearing — removing any single one
re-admits false positives:

    rule                                            occurrences stripped
    trailing letter, shape alone                              10210
    ... only letters the day's own Approvals block defines        61
    ... and the stem is at least 3 characters                     35
    ... and the stem is a word attested in this day's text        71
    ... and the day's QMD never writes the glued form            369
    all four bounds together                                      9

Nine occurrences, corpus-wide, and all nine are callouts: `demingf`,
`extractd`, `medalb` (Day 1), `controlb`, `numbera` (Day 3), `finda` (Day 6),
`improvementb` (Day 9), `demingb`, `diagramc` (Day 11). Nothing else in
2,154 paragraphs of source text satisfies all four. The rule is inert on the
five days whose PDFs define no callouts at all (2, 4, 8, 10, 12), because
callout_letters() returns nothing for them and every candidate fails the first
bound.

The rule is *not* "letters a-f", which would be shape by another name.
callout_letters() reads each day's own Approvals block, so a day that defines
`a` alone (5, 7) protects `b` through `f` in its own text — and that is what
keeps the running-head prefixes `pdftotext` emits from being eaten. Days 4-7
open with "G DAY 4:", "H DAY 5:", "I DAY 6:", "J DAY 7:", which flag in the
same band as the callouts and look identical in shape; none is touched,
because no day defines a callout past `f`.

## The QMD veto, and what it does and does not license

The last bound is the only one that reads the transcription, so it is worth
being precise about what it can do. It can only ever *refuse* a strip: a word
the site writes somewhere in the day is a word, and the PDF's copy of it is
left alone. It can never cause one. So the worst a wrong transcription can do
here is leave a callout in place and let it flag — the same outcome as not
having this module at all.

What it cannot rule out is the reverse: if the site dropped a letter from a
word it uses nowhere else in the day, and that letter happens to be one the
day's Approvals block defines, this would treat the source's spelling as a
callout and the defect would go unreported. The other three bounds are what
keep that narrow: the stem has to be an attested word, so `board` -> `boar`
and `outline` -> `outlin` are refused before the veto is consulted at all.
tests/test_pdf_callouts.py pins that residual risk as a known limit rather
than leaving it to be rediscovered.

## The second shape: a callout glued to a closing quotation mark

A callout that annotates a quotation attaches to the quote mark that ends it —
`…difference in Japan.”`^a^ — and that is a different problem, because the
character it is glued to is punctuation rather than a letter, so there is no
stem and no vocabulary to test it against. None is needed: English does not
write a bare letter hard against a closing quotation mark. Counted the same
way over the same twelve PDFs, `”` followed by a callout letter and then a
word boundary matches **7 times, and all 7 are callouts** — `worse.”c` and
`waiting.”e` on Day 1, `education?”a` on Day 5, `Westminster”b` on Day 6,
`calls.”a` on Day 7, `Japan.”a` and `care.”c` on Day 9.

Only a closing *double* quote, and no other punctuation.

  - **The straight `"` is excluded.** `pdftotext` renders every real quotation
    mark on these pages typographically, so a straight double quote in the
    extracted text is almost always symbol-font page furniture (`!"#$%&'#()`)
    — 2,873 of them across the twelve days, none a quotation. It is also
    ambiguous where it is real: an *opening* straight quote followed by a word
    beginning with a callout letter would lose that word's first letter, and
    this branch has none of the four bounds above to stop it. Restricting the
    class to `”` costs nothing: the count is 7 either way.
  - **Apostrophes are excluded** because `’` is this corpus's apostrophe as
    well as its closing single quote: `they’d`, `you’d`, `he’d` and `I’d` all
    match the shape on Day 1, whose callout set runs to `f`, and not one of
    them is a callout.
  - **A bare full stop is excluded**, which costs one real callout: Day 1's
    overture reads "with me in 1989.^a^ *(Such superscript letters as ^a^
    refer to…)*", and that `a` is left in place. Two reasons, and either would
    be enough. The shape is not distinguishable from an abbreviation — `i.e.`
    and `c.f.` are 15 of the 20 raw matches on Day 1 alone, and separating
    them takes a "not followed by a period" guard that is a patch on a bad
    pattern rather than a bound. And removing that particular callout is a net
    loss: the site dropped the full stop after "1989", so restoring the
    source's sentence boundary splits a PDF paragraph the QMD keeps whole, and
    the comparator reports one missing full stop as two badly-scored fragments
    at 0.82 and 0.47. Segmentation asymmetry is #741's subject, not this
    module's, and the callout in question flags nothing where it stands.

Usage: pdf_callouts.py <qmd_text_file> < pdf_text > stripped_pdf_text
       pdf_callouts.py --letters < pdf_text     one callout letter per line

I/O is explicitly UTF-8 in both directions, for the reason given at the same
point in qmd_strip.py: the calling script runs under `LC_ALL=C` and the course
text is full of en dashes and curly quotes.
"""

from __future__ import annotations

import io
import re
import sys

# The heading that opens the block defining a day's callouts. Neave spells the
# middle word both ways across the twelve files — "Acknowledgments" in the
# section heading, "Acknowledgements" where Day 1's overture refers to it in
# prose — so both are accepted rather than one being assumed.
_APPROVALS_HEADING = re.compile(r"^Approvals,\s+Acknowledge?ments\s+and\s+Information\s*$")

# Inside that block, a definition opens with its letter alone on a line:
#
#     Approvals, Acknowledgments and Information
#
#     a
#     (page 3) Dr Deming's presentation at the Queen Elizabeth Conference…
#     b
#     (page 9) This diagram from Deming's Road to Continual Improvement…
#
# Only the letter is read, not the `(page N)` that follows it. Day 1's `b` has
# no `(page N)` line at all — the two shapes are not reliably paired — and the
# printed page number it names is not the PDF page the callout sits on, so
# using it to narrow the rule would need a printed-to-PDF page mapping this
# module has no way to derive.
_DEFINITION_LETTER = re.compile(r"^([a-z])$")

# A word, including one `pdftotext` line-wrapped at a hyphen. Mirrors
# _LETTER_HYPHEN in paragraph_similarity.py's normalise(), which joins a hyphen
# between two letters however much whitespace follows it, so that this module
# sees the same tokens the scorer will: without it, "contri-\nbute very little"
# offers `bute` as a candidate (stem `but`, attested, and absent from the QMD,
# which writes the word whole) and Day 1 loses a letter out of "contribute".
_WORD_RUN = re.compile(r"[A-Za-z]+(?:-\s*[A-Za-z]+)*")
_HYPHEN_WRAP = re.compile(r"-\s*")

# Everything that is not part of a word, for the vocabulary the bounds test
# against. Deliberately not paragraph_similarity.normalise(): that also folds
# digits in, and a vocabulary is a set of words.
_NON_WORD = re.compile(r"[^a-z]+")

# The shortest stem a callout may be glued to. Below three characters the
# candidates are pdftotext's own debris — `ab`, `ka`, `oa`, `inc`, `2e`, `4b`
# — and none of them is a callout.
MIN_STEM_LENGTH = 3

# Lines that carry a page marker rather than prose (see paragraphs.py). They
# are structural, so nothing in them is ever a callout, and both passes below
# run *between* them rather than across them.
#
# Kept as a capturing split so the markers themselves come back through
# untouched. Splitting rather than skipping line by line is what lets the
# word-run pass still see a hyphen wrap, which straddles a newline by
# definition; the cost is that a word wrapped across a page boundary is two
# runs here rather than one, which can only ever mean a strip not made.
_PAGE_MARKER = re.compile(r"^@@pdf-page \d+@@$")
_PAGE_MARKER_SPLIT = re.compile(r"(?m)^(@@pdf-page \d+@@)$")


def callout_letters(pdf_text: str) -> list[str]:
    """The callout letters this day's own Approvals block defines, in order.

    Empty for the five days that carry no such block (2, 4, 8, 10, 12) and for
    the Optional Extras appendix, which makes every bound unsatisfiable and this
    module a no-op on them — the correct behaviour, since a file that defines no
    callouts has none to strip.

    Reading stops at the page's garbled symbol-font footer, or at the next page
    marker — whichever comes first, which in every source file is the footer.
    Both stops fail in the safe direction: an Approvals block that ever did run
    onto a second page would yield a short list, and a letter this misses is a
    callout left in place to flag, never a word wrongly eaten.

    Only the first Approvals block is read. Day 1's overture mentions the
    section by name mid-sentence, but that line is not a heading on its own and
    cannot match.
    """
    lines = pdf_text.split("\n")
    letters: list[str] = []
    for i, line in enumerate(lines):
        if not _APPROVALS_HEADING.match(line.strip()):
            continue
        for following in lines[i + 1:]:
            stripped = following.strip()
            if not stripped:
                continue
            if _PAGE_MARKER.match(stripped):
                break  # the block sits on one page in all twenty source files
            match = _DEFINITION_LETTER.match(stripped)
            if match:
                letters.append(match.group(1))
            elif not _has_letters(stripped):
                break  # the page's symbol-font footer: the block has ended
        break
    return letters


def _has_letters(text: str) -> bool:
    return any(c.isalpha() for c in text)


def vocabulary(text: str) -> set[str]:
    """Every distinct word in `text`, lowercased and de-hyphenated."""
    joined = _HYPHEN_WRAP.sub("", text.lower())
    return {word for word in _NON_WORD.split(joined) if word}


def is_callout(token: str, letters: set[str], pdf_words: set[str], qmd_words: set[str]) -> bool:
    """Does `token` end in a callout letter that isn't part of the word?

    `token` is a de-hyphenated, lowercased word. The four bounds, in the order
    the docstring above counts them, and each one load-bearing.
    """
    if not token or token[-1] not in letters:
        return False
    stem = token[:-1]
    if len(stem) < MIN_STEM_LENGTH:
        return False
    if stem not in pdf_words and stem not in qmd_words:
        return False
    return token not in qmd_words


def strip_callouts(pdf_text: str, qmd_text: str) -> str:
    """`pdf_text` with this day's footnote callouts removed.

    `qmd_text` is the same day's stripped QMD prose, and is read only for the
    vocabulary that vetoes a strip — see the module docstring on what that
    veto can and cannot do.
    """
    letters = set(callout_letters(pdf_text))
    if not letters:
        return pdf_text

    pdf_words = vocabulary(pdf_text)
    qmd_words = vocabulary(qmd_text)

    def drop_glued_letter(match: re.Match) -> str:
        raw = match.group(0)
        token = _HYPHEN_WRAP.sub("", raw.lower())
        return raw[:-1] if is_callout(token, letters, pdf_words, qmd_words) else raw

    # The typographic closing quote only: see the module docstring for the
    # 7-of-7 count, and for why the straight `"`, apostrophes and bare full
    # stops are all out of the class.
    after_quote = re.compile(r'(?<=”)[' + "".join(sorted(letters)) + r'](?![A-Za-z])')

    def strip_segment(text: str) -> str:
        return _WORD_RUN.sub(drop_glued_letter, after_quote.sub("", text))

    # re.split with a capturing group alternates content, marker, content, …
    # so the odd indices are the marker lines and pass through as they are.
    parts = _PAGE_MARKER_SPLIT.split(pdf_text)
    return "".join(
        part if i % 2 else strip_segment(part) for i, part in enumerate(parts)
    )


def main(argv: list[str]) -> int:
    stdin = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8")
    stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

    if len(argv) == 2 and argv[1] == "--letters":
        for letter in callout_letters(stdin.read()):
            print(letter, file=stdout)
        stdout.flush()
        return 0

    if len(argv) != 2:
        print(
            "Usage: pdf_callouts.py <qmd_text_file> < pdf_text\n"
            "       pdf_callouts.py --letters < pdf_text",
            file=sys.stderr,
        )
        return 1

    with open(argv[1], encoding="utf-8") as handle:
        qmd_text = handle.read()
    stdout.write(strip_callouts(stdin.read(), qmd_text))
    stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
