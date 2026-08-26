#!/usr/bin/env python3
"""paragraphs.py — assemble stripped text into the paragraphs that get compared.

Helper for scripts/validate-transcription.sh (#741). Both sides of the
comparison arrive here as a blank-line-separated text stream — the PDF side
from `pdftotext -layout`, the QMD side from scripts/lib/qmd_strip.py — and
leave as one paragraph per line, which scripts/lib/paragraph_similarity.py
reads back in.

Until #741 this was an awk function (`text_to_paragraphs`) inside
validate-transcription.sh doing two jobs: collapse each blank-line-delimited
block onto one line, and drop the blocks too short or too garbled to score.
It is Python now for a third job it could not do, because that one has to
look across block boundaries: **a blank line is not always a paragraph
break.**

Three of the false-positive categories in #732's Day 9 triage are the same
failure wearing different clothes — one side of the comparison breaks a
passage into blocks where the other side doesn't:

  - **Mid-sentence page breaks.** pdftotext puts a page boundary, and the
    page's symbol-font header, in the middle of a sentence: "…this was a poor
    system in dire" ends one block and "need of improvement anyway." starts
    another two blocks later. The QMD has one unbroken paragraph, so neither
    PDF half can match it and both flag.
  - **Blockquote splits.** The site renders a quotation as its own `>` block
    following the sentence that introduces it ("Let me quote Peter:"), where
    the printed page runs lead-in and quotation together in one paragraph.
  - **Letter-prefixed lists.** "…followed by its four parts: A. Appreciation
    for a system; B. …" is one printed paragraph and five QMD blocks — four
    of them then under the length floor, so they were dropped outright and
    the PDF's list had nothing left in the pool to match against.

join_continuations() closes all three by rejoining blocks that the text
itself says are unfinished, and it runs *between* the two filters. That order
is the whole point: the garbled header block sitting between the two halves
of a page-broken sentence has to be gone before they can be seen as adjacent,
and the list items have to be rejoined before the length floor gets a chance
to drop them.

Both sides run the same assembly, as they must. A join rule applied to one
side only would manufacture exactly the mismatch it was written to remove.

I/O is explicitly UTF-8 in both directions, for the reason given at the same
point in qmd_strip.py: the calling script runs under `LC_ALL=C` and the course
text is full of en dashes and curly quotes.

Usage: paragraphs.py < text        one paragraph per line, to stdout
       paragraphs.py --min-length  print MIN_PARA_LEN and exit
"""

from __future__ import annotations

import io
import sys

# Minimum paragraph length, in bytes (see _measured), to enter comparison at all.
#
# Short strings cannot support similarity scoring — a four-word heading finds
# a 0.5 "match" against any other four-word heading — so scoring them would
# produce noise, not findings. What that costs is that a mis-transcribed
# heading or a dropped one-line exclamation is invisible to the whole system;
# the secondary near-exact pass that answers for the dropped content is
# #742's, and #743 records how much of it there was.
MIN_PARA_LEN = 40

# Fraction of a block's non-space bytes that must be ASCII letters for it to be
# treated as prose. pdftotext renders this course's page headers in a symbol
# font, which comes out as runs like `! "#$!%!!&!!'#()!)!!!` — unmatchable by
# construction, and (before join_continuations()) sitting squarely between the
# two halves of every page-broken sentence.
MIN_LETTER_RATIO = 0.4


def _measured(block: str) -> bytes:
    """The bytes both filters below count.

    Bytes, not characters, because that is what the awk this replaced counted:
    it ran under `LC_ALL=C`, where a curly quote is three non-letter bytes and
    an en dash three more. The difference is not academic — it decides eight
    real blocks across the corpus, all of them sitting within a byte or two of
    a floor (a 39-character line of 43 bytes; a contents entry whose letter
    ratio is 0.4000 by character and 0.3925 by byte).

    A port is the wrong place to move a threshold. Keeping the byte count
    keeps this change measurable as *only* the rejoining it exists for, and
    leaves what the floors should be to #742, which owns the short-content
    question outright.
    """
    return block.encode("utf-8")


def is_readable(block: str) -> bool:
    """Is `block` prose, rather than pdftotext's rendering of page furniture?"""
    raw = _measured(block)
    total = sum(1 for b in raw if b != 0x20)
    if not total:
        return False
    letters = sum(1 for b in raw if 0x41 <= b <= 0x5A or 0x61 <= b <= 0x7A)
    return letters / total >= MIN_LETTER_RATIO


def continues(prev: str, nxt: str) -> bool:
    """Is `nxt` the rest of `prev` — a blank line that isn't a paragraph break?

    Two signals, and the text has to supply one of them; nothing here infers a
    join from position alone.

    A trailing colon or semicolon is an explicit promise of more: a colon
    introduces the quotation or the list that follows it, and a semicolon is
    the middle of a list, not the end of one. Those two carry the blockquote
    and letter-prefixed-list shapes, and they chain — each rejoined item ends
    in the semicolon that pulls in the next, until one finally ends in a full
    stop.

    Deliberately no capitalisation check on that branch, unlike the one below.
    What a colon introduces is usually capitalised — a quotation opens with a
    capital, and every lettered list item here starts `A.`, `B.`, `C.` —  so
    requiring a lower-case head would refuse exactly the joins this exists to
    make. The cost is that a colon-terminated *heading* would swallow the prose
    under it. No such heading survives to this point in the current corpus
    (headings are short enough that the length floor drops them), but a future
    long heading ending in a colon would merge, and this is the branch to
    revisit if one appears.

    Anything else that isn't terminal punctuation means the block simply
    stopped mid-thought — mid-clause at a page break, or mid-word at a
    hyphenated line wrap ("Never-" / "theless,"). That is a weaker signal than
    a colon, because a heading also ends without punctuation, so it is only
    trusted when what follows *also* reads as a continuation rather than a
    fresh start: a lower-case opening word. A heading is followed by a
    capital, and so is a new paragraph.
    """
    if not prev or not nxt:
        return False
    tail = prev[-1]
    if tail in ":;":
        return True
    if tail.isalnum() or tail in "-,–—":
        return nxt[0].islower()
    return False


def blocks(text: str) -> list[str]:
    """Blank-line-delimited blocks, each collapsed onto a single line."""
    out, current = [], []
    for line in text.splitlines():
        if line.strip():
            current.append(line)
        elif current:
            out.append(" ".join(" ".join(current).split()))
            current = []
    if current:
        out.append(" ".join(" ".join(current).split()))
    return out


def join_continuations(items: list[str]) -> list[str]:
    """Rejoin every block that continues the one before it.

    Tests the *accumulated* text's tail rather than the original block's, so a
    run of list items joins in one pass: "…four parts:" pulls in "A. …system;",
    whose semicolon then pulls in "B. …", and so on.
    """
    joined: list[str] = []
    for item in items:
        if joined and continues(joined[-1], item):
            joined[-1] = f"{joined[-1]} {item}"
        else:
            joined.append(item)
    return joined


def to_paragraphs(text: str) -> list[str]:
    """The comparable paragraphs of `text`: split, de-garbled, rejoined, floored."""
    readable = [b for b in blocks(text) if is_readable(b)]
    return [p for p in join_continuations(readable) if len(_measured(p)) >= MIN_PARA_LEN]


def main(argv: list[str]) -> int:
    if argv == ["--min-length"]:
        print(MIN_PARA_LEN)
        return 0
    if argv:
        print(f"Usage: {sys.argv[0]} < text", file=sys.stderr)
        print(f"       {sys.argv[0]} --min-length", file=sys.stderr)
        return 1

    text = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8").read()
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    for paragraph in to_paragraphs(text):
        print(paragraph, file=out)
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
