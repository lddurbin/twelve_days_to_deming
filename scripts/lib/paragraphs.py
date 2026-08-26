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

What assembly *discards* is now returned rather than dropped on the floor
(#742). sift() splits every block three ways — the paragraphs that go on to be
scored, the readable ones under the length floor, and the ones the readability
filter rejected — and stamps each with the PDF page it starts on, which is
what makes the residue triageable. scripts/lib/short_content.py takes it from
there; nothing here decides whether dropped content is a defect.

account() counts that same split for the provenance record (#743), so a
results file states what a run did *not* check alongside what it did. See
Accounting for the partition it guarantees.

Page numbers come from the form feeds `pdftotext` emits, turned into marker
lines by mark_pages() before the caller's `sed` cleanup runs, because that
cleanup deletes whole lines and would otherwise destroy any positional link
back to a page. A marker is transparent to assembly: it sets the current page
and is neither content nor a paragraph break, so the paragraphs this module
produces are byte-for-byte what it produced before markers existed.

I/O is explicitly UTF-8 in both directions, for the reason given at the same
point in qmd_strip.py: the calling script runs under `LC_ALL=C` and the course
text is full of en dashes and curly quotes.

Usage: paragraphs.py < text        one paragraph per line, to stdout
       paragraphs.py --mark-pages < text  form feeds -> page markers, to stdout
       paragraphs.py --counts < text      KEY=VALUE block accounting, to stdout
       paragraphs.py --short < text       the sub-floor blocks, one per line
       paragraphs.py --min-length  print MIN_PARA_LEN and exit
"""

from __future__ import annotations

import io
import re
import sys
from typing import NamedTuple

# Minimum paragraph length, in bytes (see _measured), to enter comparison at all.
#
# Short strings cannot support similarity scoring — a four-word heading finds
# a 0.5 "match" against any other four-word heading — so scoring them would
# produce noise, not findings.
#
# #742 asked whether the floor itself should move, and the answer is no: what
# was wrong was never its height but that everything under it disappeared. It
# is a floor on *similarity scoring*, which is the one thing short strings
# cannot support, so lowering it would buy coverage in the currency of noise.
# The content below it is answered for instead, by the exact-matching pass in
# scripts/lib/short_content.py that sift() now feeds. Keeping the floor where
# it is also keeps that change measurable: the paragraphs scored under this
# module are the same ones scored before it.
MIN_PARA_LEN = 40

# How a page boundary is carried through the caller's cleanup pipeline.
#
# `pdftotext` marks one with a form feed at the start of a line, which
# validate-transcription.sh used to delete outright — so by the time text
# reached this module there was nothing left to say which page a block came
# from, and the short-content residue #742 reports could only be described by
# its wording. The form feed cannot simply be left in place: the `sed` pass
# between there and here deletes bare page-number lines with `/^[0-9]+$/`, and
# a leading form feed would hide the digits from that rule.
#
# So it becomes a line of its own, before `sed` runs, in a shape that pass
# leaves alone: it has letters, so the garbled-line rule ignores it; it has no
# double spaces and no leading or trailing space, so the whitespace rules are
# no-ops on it.
#
# It is read back as a whole line and only in this exact shape, which is what
# makes it safe to put a sentinel in a stream of arbitrary text. No line in
# any of the twenty-four source PDFs matches it. Three lines of Day 7 do
# contain `@@`, inside `pdftotext`'s rendering of a symbol-font page in
# gibberish (`@@@$`) — they match nothing here, and the garbled-line rule in
# validate-transcription.sh deletes them long before this module runs.
_PAGE_MARKER_FORMAT = "@@pdf-page {}@@"
_PAGE_MARKER = re.compile(r"^@@pdf-page (\d+)@@$")

# The page a block is attributed to when nothing has said otherwise: the first.
# The QMD side carries no markers at all (it has no pages), so every QMD block
# reads as page 1 — meaningless there, and never reported.
FIRST_PAGE = 1

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
    kept #741 measurable as *only* the rejoining it existed for — and #742,
    which owned the short-content question, left both floors alone as well,
    for the reason recorded beside MIN_PARA_LEN.
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


class Block(NamedTuple):
    """One blank-line-delimited block, and the page it starts on.

    Where it *starts*, not where it ends: a block rejoined across a page break
    belongs to the page a reader would turn to first to find it.
    """

    text: str
    page: int


class Sifted(NamedTuple):
    """Every block of a text, split by what assembly did with it.

    The three lists partition the input, which is the point (#742): before
    this, `paragraphs` was the whole return value and the other two were
    discarded inside a comprehension, so a mis-transcribed heading or a
    dropped one-line exclamation left no trace anywhere in the system.
    """

    paragraphs: list[str]  # long and readable enough to be scored
    short: list[Block]  # readable prose under MIN_PARA_LEN
    garbled: list[Block]  # rejected by the readability filter


class Accounting(NamedTuple):
    """Where every block of a text ended up, as counts rather than lists.

    The provenance record's side of sift() (#743). A results file that says
    `pdf_paragraphs: 288` gives a reader no way to know how many blocks the
    filters dropped to get there, so the unchecked residue was invisible in
    exactly the file that exists to say what was checked.

    `total` is the count *before* assembly — blank-line-delimited blocks, not
    paragraphs, a distinction that has mattered since join_continuations()
    started merging blocks the text says are one passage. The four that follow
    partition it exactly:

        total == unreadable + rejoined + short + compared

    and only `compared` entered similarity scoring. `rejoined` is the benign
    one of the three residues — those blocks are inside the paragraph before
    them, not missing from the comparison.
    """

    total: int  # blocks read, before either filter or any rejoining
    unreadable: int  # rejected by the readability filter — page furniture
    rejoined: int  # merged into the block before them by join_continuations()
    short: int  # readable, assembled, and still under MIN_PARA_LEN
    compared: int  # what to_paragraphs() returns: the scored population


def mark_pages(text: str) -> str:
    """`text` with each form feed replaced by a page-marker line.

    Run this on `pdftotext` output before any other cleanup — see
    _PAGE_MARKER_FORMAT for why the boundary cannot survive as a form feed.

    Every form feed in the twelve source PDFs sits at the start of a line, so
    the marker slots cleanly between two lines; the newline guard below is for
    a stream where one doesn't, where appending the marker to a line of prose
    would corrupt content in order to record where it was.
    """
    pages = text.split("\f")
    marked = [pages[0]]
    for number, page in enumerate(pages[1:], start=FIRST_PAGE + 1):
        if marked[-1] and not marked[-1].endswith("\n"):
            marked.append("\n")
        marked.append(_PAGE_MARKER_FORMAT.format(number) + "\n" + page)
    return "".join(marked)


def read_blocks(text: str) -> list[Block]:
    """Blank-line-delimited blocks, each collapsed onto a single line.

    A page marker is transparent here: it moves the page counter on and is
    neither content nor a paragraph break. That transparency is what keeps
    page numbering free — the block list is identical with markers and
    without, so nothing downstream of it can tell that pages are being
    tracked at all.
    """
    out: list[Block] = []
    current: list[str] = []
    page = start = FIRST_PAGE
    for line in text.splitlines():
        marker = _PAGE_MARKER.match(line)
        if marker:
            page = int(marker.group(1))
        elif line.strip():
            if not current:
                start = page
            current.append(line)
        elif current:
            out.append(Block(" ".join(" ".join(current).split()), start))
            current = []
    if current:
        out.append(Block(" ".join(" ".join(current).split()), start))
    return out


def blocks(text: str) -> list[str]:
    """read_blocks() for a caller that has no use for the page numbers."""
    return [block.text for block in read_blocks(text)]


def join_continuations(items: list[Block]) -> list[Block]:
    """Rejoin every block that continues the one before it.

    Tests the *accumulated* text's tail rather than the original block's, so a
    run of list items joins in one pass: "…four parts:" pulls in "A. …system;",
    whose semicolon then pulls in "B. …", and so on.
    """
    joined: list[Block] = []
    for item in items:
        if joined and continues(joined[-1].text, item.text):
            joined[-1] = Block(f"{joined[-1].text} {item.text}", joined[-1].page)
        else:
            joined.append(item)
    return joined


def _sift_blocks(items: list[Block]) -> Sifted:
    """sift(), for a caller that has already read the blocks.

    Filter order is load-bearing and unchanged from #741: the readability
    filter first (a garbled page header sits between the two halves of a
    page-broken sentence), then rejoining, then the length floor (a lettered
    list's items are under it individually).

    Split out from sift() so that account() can count the blocks going in as
    well as the three lists coming out, without either re-reading the text or
    keeping a second copy of that order to count against.
    """
    readable, garbled = [], []
    for block in items:
        (readable if is_readable(block.text) else garbled).append(block)

    paragraphs, short = [], []
    for block in join_continuations(readable):
        if len(_measured(block.text)) >= MIN_PARA_LEN:
            paragraphs.append(block.text)
        else:
            short.append(block)
    return Sifted(paragraphs, short, garbled)


def sift(text: str) -> Sifted:
    """Split `text` into what gets scored, what is too short, and what is junk."""
    return _sift_blocks(read_blocks(text))


def account(text: str) -> Accounting:
    """Count what assembly did with every block of `text`.

    sift() answers *which* blocks; this answers *how many*, which is the shape
    provenance needs (#743). `rejoined` is the one number the three lists
    cannot show between them — a block merged into its predecessor leaves no
    trace in any of them — so it is recovered by difference against the block
    count going in, which is also what makes the partition below exact by
    construction rather than by a second traversal that could disagree.
    """
    items = read_blocks(text)
    sifted = _sift_blocks(items)
    compared, short, unreadable = (
        len(sifted.paragraphs),
        len(sifted.short),
        len(sifted.garbled),
    )
    return Accounting(
        total=len(items),
        unreadable=unreadable,
        rejoined=len(items) - unreadable - short - compared,
        short=short,
        compared=compared,
    )


def to_paragraphs(text: str) -> list[str]:
    """The comparable paragraphs of `text`: split, de-garbled, rejoined, floored."""
    return sift(text).paragraphs


def main(argv: list[str]) -> int:
    if argv == ["--min-length"]:
        print(MIN_PARA_LEN)
        return 0
    if argv and argv not in (["--mark-pages"], ["--counts"], ["--short"]):
        print(f"Usage: {sys.argv[0]} < text", file=sys.stderr)
        print(f"       {sys.argv[0]} --mark-pages < text", file=sys.stderr)
        print(f"       {sys.argv[0]} --counts < text", file=sys.stderr)
        print(f"       {sys.argv[0]} --short < text", file=sys.stderr)
        print(f"       {sys.argv[0]} --min-length", file=sys.stderr)
        return 1

    text = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8").read()
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    if argv == ["--mark-pages"]:
        out.write(mark_pages(text))
    elif argv == ["--counts"]:
        # `KEY=VALUE` lines, the contract validate-transcription.sh already
        # reads the other helpers' headers by, so it parses these by name too
        # rather than by position.
        for key, value in account(text)._asdict().items():
            print(f"{key.upper()}={value}", file=out)
    elif argv == ["--short"]:
        # The blocks the floor rejected, in the same one-per-line shape as the
        # default mode — so a caller that already reads paragraphs can read
        # these the same way. sift() has always computed them; until #761 the
        # only consumer was short_content.py, which reads the raw text and
        # re-sifts it. This mode exists because paragraph_similarity.py needs
        # the QMD's short blocks as *match candidates*, not as a population to
        # report on, and re-implementing the partition there would give the
        # comparison two disagreeing ideas of what "short" means.
        for block in sift(text).short:
            print(block.text, file=out)
    else:
        for paragraph in to_paragraphs(text):
            print(paragraph, file=out)
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
