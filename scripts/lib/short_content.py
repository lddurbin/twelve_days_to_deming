#!/usr/bin/env python3
"""short_content.py — account for the PDF content that is too short to score.

Helper for scripts/validate-transcription.sh (#742). The similarity scorer in
scripts/lib/paragraph_similarity.py only ever sees paragraphs that cleared
scripts/lib/paragraphs.py's two filters — 40 bytes long, 40% letters. Those
filters are right: a four-word heading finds a 0.5 "match" against any other
four-word heading, so scoring short strings produces noise rather than
findings. What was wrong is that everything they rejected then vanished. 576
readable-but-short PDF blocks across the twelve days — headings, one-line
exclamations, table rows, captions, contents entries — entered no comparison
at all, and a mis-transcribed heading was invisible to the whole system.

This module is the secondary pass that answers for them. It asks a strictly
weaker question than the scorer does, because that is the only honest question
a four-word string can answer: **is this line's text present in the QMD at
all?** Not "has it drifted" — with seven words to work with, one substituted
word already scores 0.86, which no threshold can separate from a legitimately
reworded heading. So a line either matches something on the site, or it is
reported for a human to look at, with the closest candidate found alongside it
as evidence. Nothing here returns a verdict.

Three tiers of match, in order, all of them exact or near enough to be:

  1. **Exact** — the line normalises to exactly a QMD heading or short
     paragraph. This is 343 of the 576, and it is what the pass is mostly for.
  2. **Verbatim** — the line normalises to a run of words inside a longer QMD
     paragraph, which is what a printed page's standalone line looks like when
     the site folds it into the prose around it. 28 more. Needs two words at
     minimum: a single word is not evidence of anything, since "PROJECT"
     appears in any chapter about projects.
  3. **Near-exact** — SHORT_MATCH_THRESHOLD or better against the same pool.
     See the constant: at these lengths this tier is nearly unreachable by
     construction, and it exists to catch wording differences that normalise()
     does not already fold away, not to grade transcription.

The QMD pool is the mirror image of the PDF's discarded population — the short
blocks *its* filters dropped — plus the front-matter `title` of every chapter.
The titles are load-bearing: the site renders Neave's section headings as
chapter h1s from front matter, which qmd_strip.py removes wholesale, so
without them every printed heading in the corpus reads as unmatched.

Everything unmatched is grouped by wording, counted, and stamped with the PDF
pages it appears on, so a page image can be opened directly (page N of the PDF
is `..._page_00N.png` in 12-Days-to-Deming/PNGs/). Three groups of it are set
aside rather than listed for triage, because they are residue this comparison
cannot speak to:

  - **duplicated column** — `pdftotext -layout` reading a two-column table row
    twice ("Audrey 16 10 7 Audrey 16 10 7"). 67 lines, every one of them a row
    of Day 2's Red Beads tables. Table fidelity belongs to #725.
  - **contents entry** — a line ending in a printed page reference, "(p 27)",
    which is the shape of the itinerary pages the site does not reproduce. 39
    lines, spread across ten of the twelve days.
  - **fragment** — under two words, usually a heading `-layout` split across
    lines, or a stray letter from a rotated caption. 13 lines.

That leaves 86 lines, in 63 distinct wordings, for a human — the number this
issue existed to make visible, where before it was 576 lines of nothing.

#742 suggested digit-heavy lines as the table heuristic. Measured over the
corpus it is the wrong cut here: applied after the duplicated-column rule it
catches six further lines, while ahead of it it swallows contents entries like
"Activity 2–g (p 32)" — 40% numerals — and labels them tables. Column
doubling is the artifact this corpus actually has, and it is exact.

Usage: short_content.py <pdf_text> <qmd_text> [<chapter.qmd> ...]

  <pdf_text>  cleaned PDF text, carrying the page markers paragraphs.py
              writes (see mark_pages there)
  <qmd_text>  the same day's stripped QMD text, as qmd_strip.py emits it
  chapters    the .qmd sources, read only for their front-matter titles

Output: `KEY=VALUE` header lines, then a blank line, then the report section
when there is anything to report — the same contract as
paragraph_similarity.py, so the caller reads counts by key and skips the
header with `sed '1,/^$/d'`.

  SHORT_CHECKED=<n>    readable PDF blocks under the length floor
  SHORT_MATCHED=<n>    of those, found in the QMD by one of the three tiers
  SHORT_UNMATCHED=<n>  of those, not found, and not set aside below
  SHORT_UNJUDGED=<n>   of those, set aside as residue this cannot speak to
  SHORT_GARBLED=<n>    blocks the readability filter rejected — page furniture
                       in a symbol font, counted here so it is stated rather
                       than silently dropped. #743 records it in provenance.
  SHORT_THRESHOLD=<f>  the SHORT_MATCH_THRESHOLD in effect

CHECKED = MATCHED + UNMATCHED + UNJUDGED, a partition of every short block.
GARBLED is a separate population and is not part of that sum.
"""
from __future__ import annotations

import io
import re
import sys
from typing import NamedTuple

import paragraphs
import qmd_strip
from paragraph_similarity import find_best_sentence, tokenise

# Similarity at or above which a short line counts as found rather than
# reported. Deliberately far above the scorer's own thresholds, and it has to
# be: this population is 2-7 words long, where SequenceMatcher scores a single
# substituted word in a seven-word line at 0.86 and in a four-word line at
# 0.75. Any cut low enough to absorb those would also absorb a genuinely
# different heading — "ALL ONE SCIENTIFIC TEAM APPROACH" against the site's
# "All One Team" scores 0.75 — and the whole value of this pass is that a
# heading nobody transcribed gets *seen*.
#
# So the tier is nearly unreachable by construction, and that is the intended
# shape rather than a defect in the number: measured across all twelve days it
# matches nothing that exact and verbatim matching had not already matched,
# and the highest-scoring unmatched line in the corpus is 0.80. It is a guard
# against wording differences normalise() does not fold away, not a grader.
SHORT_MATCH_THRESHOLD = 0.90

# Words a line needs before its presence inside a longer QMD paragraph counts
# as evidence, and below which it is set aside as a fragment. One word is not
# evidence: the corpus's single-word lines ("E", "FIRST", "PROJECT") would
# each "match" any chapter that happens to use that word once.
MIN_VERBATIM_WORDS = 2

# A line ending in a printed page reference — "Read DemDim Chapter 6 (p 27)",
# "— Stage 3 (p 13)". That is the shape of Neave's per-day contents and
# itinerary pages, which the site does not reproduce; nothing about them is a
# transcription question.
_CONTENTS_ENTRY = re.compile(r"\(\s*pp?\.?\s*\d+\s*\)\s*$")

BUCKET_DUPLICATED = "duplicated column"
BUCKET_CONTENTS = "contents entry"
BUCKET_FRAGMENT = "fragment"


class Line(NamedTuple):
    """One short PDF block, as it entered the pass."""

    text: str
    page: int
    words: tuple[str, ...]


class Finding(NamedTuple):
    """One wording, everywhere it appears, and the best the QMD could offer.

    Grouped by wording rather than listed per occurrence because the residue
    repeats heavily: "Net Effect of Adopted Options" heads a table on nine of
    Day 8's pages. One entry reading "x9, pages 25-42" is one decision to
    make; nine entries are nine.
    """

    text: str
    pages: list[int]
    occurrences: int
    closest: str
    score: float
    bucket: str | None


class Result(NamedTuple):
    checked: int
    matched: int
    garbled: int
    unmatched: list[Finding]  # for triage, highest-scoring first
    unjudged: list[Finding]  # set aside: table rows, contents entries, fragments


def duplicated_column(words: tuple[str, ...]) -> bool:
    """Does `words` open with a run repeated immediately after itself?

    `pdftotext -layout` reads a two-column table row as its left column
    followed by its right, and where the two columns hold the same row header
    the result is a doubled sequence: "Carol 7 11 Carol 7 11 14". Any repeat
    length counts, since the doubling happens at whatever width the row is.

    The repeated run has to account for nearly the whole line (2k >= n - 2),
    which is what stops the rule reaching into prose: a sentence that happens
    to open "That that" is not a table row, and a line long enough to be prose
    is not one either.
    """
    n = len(words)
    return any(words[:k] == words[k : 2 * k] and 2 * k >= n - 2 for k in range(1, n // 2 + 1))


def bucket_of(line: Line) -> str | None:
    """Which residue group `line` belongs to, or None if it is for triage."""
    if duplicated_column(line.words):
        return BUCKET_DUPLICATED
    if _CONTENTS_ENTRY.search(line.text):
        return BUCKET_CONTENTS
    if len(line.words) < MIN_VERBATIM_WORDS:
        return BUCKET_FRAGMENT
    return None


def to_lines(blocks: list[paragraphs.Block]) -> list[Line]:
    """Short blocks as comparable lines, dropping any that normalise to nothing.

    Nothing in the current corpus can be dropped there — a block only reaches
    this function by passing is_readable(), which demands 40% ASCII letters,
    and normalise() keeps every one of them. The guard is here so that a
    future change to either filter cannot put an empty word tuple into the
    pool, where it would match everything.
    """
    lines = ((block, tokenise(block.text)) for block in blocks)
    return [Line(block.text, block.page, words) for block, words in lines if words]


def chapter_titles(paths: list[str]) -> list[str]:
    """The front-matter `title` of each .qmd in `paths` that declares one."""
    titles = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            title = qmd_strip.front_matter_title(handle.read())
        if title:
            titles.append(title)
    return titles


def build_pool(
    qmd: paragraphs.Sifted, titles: list[str]
) -> list[tuple[str, tuple[str, ...]]]:
    """The short QMD strings a PDF line is matched against, as (text, words).

    Its short blocks and its chapter titles: the two places a printed heading
    or one-line exclamation lands on the site. Longer QMD paragraphs are not
    in here — a short line is compared against those by containment instead,
    since a scored similarity between four words and eighty is meaningless.
    """
    candidates = [block.text for block in qmd.short] + titles
    pool = ((text, tokenise(text)) for text in candidates)
    return [(text, words) for text, words in pool if words]


def group(lines: list[Line], scores: dict[tuple[str, ...], tuple[float, str]]) -> list[Finding]:
    """Collapse `lines` to one Finding per distinct wording."""
    order: list[tuple[str, ...]] = []
    occurrences: dict[tuple[str, ...], list[Line]] = {}
    for line in lines:
        if line.words not in occurrences:
            occurrences[line.words] = []
            order.append(line.words)
        occurrences[line.words].append(line)

    findings = []
    for words in order:
        same = occurrences[words]
        score, closest = scores[words]
        findings.append(
            Finding(
                text=same[0].text,
                pages=sorted({line.page for line in same}),
                occurrences=len(same),
                closest=closest,
                score=score,
                bucket=bucket_of(same[0]),
            )
        )
    return findings


def compare(pdf_text: str, qmd_text: str, titles: list[str]) -> Result:
    """Run the pass: every short PDF line matched, set aside, or reported."""
    pdf = paragraphs.sift(pdf_text)
    qmd = paragraphs.sift(qmd_text)
    lines = to_lines(pdf.short)
    pool = build_pool(qmd, titles)

    exact = {words for _, words in pool}
    # Joined per paragraph, never into one chapter-wide string, so a verbatim
    # match cannot be manufactured across a paragraph boundary out of the tail
    # of one and the head of the next.
    #
    # Padded with a space at each end — as the needle is in _appears_in() — so
    # that a match has to land on whole words. Without the padding a line is
    # found inside any token it is a prefix or suffix of, which in this corpus
    # is not theoretical: "DAY 1" reads as present in a chapter that merely
    # mentions Day 12, and "Rule 1" in one that mentions Rule 10.
    haystacks = [f" {' '.join(tokenise(text))} " for text in qmd.paragraphs]
    haystacks += [f" {' '.join(words)} " for _, words in pool]

    scores: dict[tuple[str, ...], tuple[float, str]] = {}
    matched, reported = 0, []
    for line in lines:
        if line.words in exact or _appears_in(line.words, haystacks):
            matched += 1
            continue
        if line.words not in scores:
            scores[line.words] = find_best_sentence(line.words, pool) if pool else (0.0, "")
        if scores[line.words][0] >= SHORT_MATCH_THRESHOLD:
            matched += 1
            continue
        reported.append(line)

    findings = group(reported, scores)
    return Result(
        checked=len(lines),
        matched=matched,
        garbled=len(pdf.garbled),
        unmatched=sorted(
            (f for f in findings if f.bucket is None), key=lambda f: (-f.score, f.text)
        ),
        unjudged=sorted((f for f in findings if f.bucket), key=lambda f: (f.bucket, f.text)),
    )


def _appears_in(words: tuple[str, ...], haystacks: list[str]) -> bool:
    """Is `words` a run of consecutive words in any of `haystacks`?

    `haystacks` are the space-padded strings compare() builds; the needle is
    padded here to match, which is what makes this a word-run test rather than
    a substring test. See the comment there for what goes wrong without it.
    """
    if len(words) < MIN_VERBATIM_WORDS:
        return False
    needle = f" {' '.join(words)} "
    return any(needle in hay for hay in haystacks)


def _pages(pages: list[int]) -> str:
    return ", ".join(str(page) for page in pages)


def render(result: Result) -> list[str]:
    """Format the human-readable "short content" report section."""
    out = [
        "==========================================",
        "  Short Content (below the comparison floor)",
        "==========================================",
        "",
        f"{result.checked} PDF block(s) were under the {paragraphs.MIN_PARA_LEN}-byte floor for",
        f"similarity scoring, and a further {result.garbled} were page furniture the",
        f"readability filter rejected. Of the short ones, {result.matched} were found in",
        "the QMD text: exactly, verbatim inside a longer paragraph, or at",
        f"{SHORT_MATCH_THRESHOLD:.0%} similarity or better against a heading.",
        "",
        "This pass answers presence, not fidelity — a four-word heading cannot",
        "support a similarity score, so a line is either found on the site or",
        "shown below with the closest candidate as evidence. Confirm against the",
        "page image before treating anything here as a defect: PDF page N is",
        "`..._page_00N.png` under 12-Days-to-Deming/PNGs/.",
        "",
    ]

    if result.unmatched:
        out += [
            "------------------------------------------",
            f"  Not found in the QMD ({len(result.unmatched)} wording(s))",
            "------------------------------------------",
            "",
        ]
        for i, finding in enumerate(result.unmatched, start=1):
            # A zero score means find_best_sentence() never beat its starting
            # best and handed back the first pool entry as a placeholder.
            # Printing that would put an unrelated heading beside the line as
            # if it were evidence; there is simply nothing to show.
            closest = (
                f"{finding.closest} [{finding.score:.0%}]"
                if finding.score > 0
                else "(nothing in the QMD resembles it)"
            )
            out += [
                f"--- Short line {i} (x{finding.occurrences}, "
                f"PDF page(s) {_pages(finding.pages)}) ---",
                f"  {'Source (PDF):':<16}{finding.text}",
                f"  {'Closest (QMD):':<16}{closest}",
                "",
            ]

    if result.unjudged:
        out += [
            "------------------------------------------",
            f"  Set aside ({len(result.unjudged)} wording(s))",
            "------------------------------------------",
            "",
            "Residue this comparison cannot speak to, listed so it is accounted",
            "for rather than hidden: table rows `pdftotext` read twice across two",
            "columns (figure and table fidelity is #725's), entries from the",
            "contents and itinerary pages the site does not reproduce, and",
            "fragments of under two words.",
            "",
        ]
        for finding in result.unjudged:
            out += [
                f"  [{finding.bucket}] x{finding.occurrences}, "
                f"PDF page(s) {_pages(finding.pages)}",
                f"    {finding.text}",
            ]
        out.append("")

    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "Usage: short_content.py <pdf_text> <qmd_text> [<chapter.qmd> ...]",
            file=sys.stderr,
        )
        return 1

    with open(argv[1], encoding="utf-8") as handle:
        pdf_text = handle.read()
    with open(argv[2], encoding="utf-8") as handle:
        qmd_text = handle.read()

    result = compare(pdf_text, qmd_text, chapter_titles(argv[3:]))

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    print(f"SHORT_CHECKED={result.checked}", file=out)
    print(f"SHORT_MATCHED={result.matched}", file=out)
    print(f"SHORT_UNMATCHED={sum(f.occurrences for f in result.unmatched)}", file=out)
    print(f"SHORT_UNJUDGED={sum(f.occurrences for f in result.unjudged)}", file=out)
    print(f"SHORT_GARBLED={result.garbled}", file=out)
    print(f"SHORT_THRESHOLD={SHORT_MATCH_THRESHOLD}", file=out)
    print(file=out)
    if result.unmatched or result.unjudged:
        print("\n".join(render(result)), file=out)
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
