#!/usr/bin/env python3
"""paragraph_similarity.py — find altered or dropped sentences in a transcription.

Helper for scripts/validate-transcription.sh's "altered content" mode (#677).
That script already confirms a PDF paragraph is *present* in the QMD text via
a fingerprint (first-8-words) match against the whole QMD blob. That check
can't see a defect sitting past those first 8 words — a swapped word, a
paraphrased clause, a whole sentence dropped from the end of the paragraph —
because the fingerprint still matches.

This script re-examines each paragraph the caller already judged "present",
at SENTENCE granularity rather than whole-paragraph: a single substituted
word (e.g. "he" -> "I") gets diluted to near-invisibility in a whole-paragraph
similarity score across ~100 surrounding unchanged words, but stands out
clearly once the comparison window shrinks to one sentence. For each PDF
sentence, it searches every QMD sentence in the chapter (not just those in
the "corresponding" paragraph) for the closest match, since PDF and QMD
paragraph boundaries frequently don't align 1:1 -- e.g. a whole bulleted list
often collapses into one PDF paragraph (pdftotext only splits on blank
lines) while each bullet is its own QMD paragraph. Restricting the search to
one (possibly wrongly-identified) "corresponding" paragraph was tried and
discarded: it missed real defects sitting in a different bullet than the
one a paragraph-level heuristic happened to pick.

Findings are ordered by similarity, highest first, which is a triage order
rather than a severity order. A sentence matching its closest QMD counterpart
at 96% is almost certainly the same sentence, so the 4% that differs is almost
certainly a real defect — and it is exactly the kind a human proofreader
skims straight past. Low-similarity findings are the ambiguous end: dropped
content, PDF front matter, and heavily restructured passages all land there
together.

An earlier revision tried to label each finding "dropped" (no counterpart on
the site) vs "reworded" (present but drifted). Two classifiers were tried and
both were dropped as untrustworthy, because a wrong label is worse than none:
an opening-words fingerprint flips to "dropped" whenever the defect happens to
fall inside the fingerprint ("Back then, those were..." is on the site, as
"Back then, there were..."), and rare-word containment scores a genuinely
absent sentence at 1.00 whenever its vocabulary is unremarkable ("But you
might find you have time for one or two of them."). Measured against
hand-checked Day 4 sentences the two classes overlapped across most of the
range, so the report states the evidence — the score, and the closest match
found — and leaves the judgement to the reader.

Usage: paragraph_similarity.py <matched_pdf_paras.txt> <qmd_paras.txt> <threshold>

Input files: one paragraph per line, as produced by validate-transcription.sh's
text_to_paragraphs().

Output: `KEY=VALUE` header lines, then a blank line, then a formatted report
section (absent when nothing is flagged). Callers should read the counts by
key and skip the header with `sed '1,/^$/d'` rather than by line number, so
new keys can be added without breaking them.

  ALTERED_COUNT=<n>       PDF paragraphs with >=1 flagged sentence
  FLAGGED_SENTENCES=<n>   flagged sentences in total
  NEAR_MATCH_SENTENCES=<n>  flagged sentences at or above NEAR_MATCH_SCORE —
                          the high-confidence band to review first
"""
from __future__ import annotations  # `list[str]` annotations on Python < 3.9

import difflib
import re
import sys

TRUNCATE_LEN = 200

# Below this similarity, a sentence is flagged as "altered" rather than counted
# as a clean match. This module is the single definition: validate-transcription.sh
# no longer carries its own copy, and the test suite imports this one, so the
# three consumers cannot drift apart.
#
# Two granularity choices were tried and discarded before word-level. Whole
# paragraphs: a single substituted word is diluted to near-invisibility across
# ~100 unchanged words. Then sentences compared character by character: better,
# but a one-digit change ("the 97% region" -> "the 37% region") is 1 character
# in 76 and scores 0.9865, indistinguishable from a clean match.
#
# At word granularity a faithful transcription normalises to an identical word
# sequence and scores exactly 1.0, while the worst-case (hardest to catch) of
# the known Day 4 defects scores 0.9778. 0.98 sits in that gap. The defect
# shapes are pinned in tests/test_paragraph_similarity.py, so re-tuning this
# without re-checking them will fail the suite rather than silently lose
# coverage. See #676 and #677.
ALTERED_SIMILARITY_THRESHOLD = 0.98

# A flagged sentence at or above this score is near-certainly the same sentence
# as its match, so the difference is near-certainly a defect rather than a
# restructuring. Used only to count a "review these first" band in the header —
# it does not affect what gets flagged.
NEAR_MATCH_SCORE = 0.90


def normalise(text: str) -> str:
    """Lowercase, rejoin line-wrap hyphenation, strip punctuation, collapse
    whitespace.

    Deliberately does NOT strip the letter "f" or standalone digits, both of
    which earlier revisions did. Those were compensating for two bugs in
    validate-transcription.sh's own extract_pdf_text() — a `s/\\f//g` that BSD
    sed read as "delete every f", and a page-number rule that ate inline
    numbers like "the 14 Points". Both are fixed at source, and stripping
    either here would blind the scorer to real defects: "of" vs "or" and
    "14 Points" vs "12 Points" are exactly the mistakes worth catching.
    """
    text = re.sub(r"(\w)-\s+(\w)", r"\1\2", text)  # de-hyphenate line wraps
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def tokenise(text: str) -> tuple[str, ...]:
    """Normalised text as a word tuple — the unit similarity is measured in.

    Comparing words rather than characters is what makes a small edit visible.
    A one-digit change ("the 97% region" -> "the 37% region") is 1 character in
    76, which scores 0.9865 and slips past any threshold loose enough to
    tolerate ordinary noise; the same edit is 1 word in 14, and scores 0.9375.
    Across the known Day 4 defects the worst-case (hardest to catch) score
    improves from 0.9865 to 0.9778, while a faithful transcription still
    normalises to an identical word sequence and scores exactly 1.0.
    """
    return tuple(normalise(text).split())


# Split on sentence punctuation only when what follows looks like a new
# sentence (optional quote/bracket, then a capital or digit). Splitting on
# bare `[.!?]\s+` shattered "e.g. when working on the 11th Point" into
# fragments too short to match anything, which showed up as false positives.
#
# Bullet glyphs are boundaries too. pdftotext puts a whole bullet list in one
# blank-line-delimited block, so without this a PDF "sentence" runs from the
# tail of one bullet across the marker into the head of the next — a shape no
# QMD sentence can match, and a steady source of mid-range false positives.
_SENTENCE_BOUNDARY = re.compile(
    r"""(?<=[.!?])["')\]]?\s+(?=["'(\[]?[A-Z0-9])|\s*[•‣▪]\s*"""
)


def split_sentences(text: str) -> list[str]:
    return [p for p in _SENTENCE_BOUNDARY.split(text.strip()) if p.strip()]


def truncate(text: str, n: int = TRUNCATE_LEN) -> str:
    return text if len(text) <= n else text[:n] + "..."


def _window(text: str, lo: int, hi: int, width: int) -> str:
    """`width` characters of `text` centred on [lo, hi), snapped to word bounds."""
    if len(text) <= width:
        return text
    start = max(0, min((lo + hi) // 2 - width // 2, len(text) - width))
    end = start + width
    if start > 0:  # snap outward to whole words so the excerpt reads cleanly
        space = text.find(" ", start)
        start = start if space == -1 else space + 1
    if end < len(text):
        space = text.rfind(" ", start, end)
        end = end if space == -1 else space
    return ("..." if start > 0 else "") + text[start:end] + ("..." if end < len(text) else "")


def diff_window(pdf_sent: str, qmd_sent: str, width: int = TRUNCATE_LEN) -> tuple[str, str]:
    """Excerpt both sentences around the region where they actually differ.

    Truncating from the start hid the finding for a quarter of Day 4's flagged
    sentences: the Malcolm Gall sentence differs at character 241 of 249, so a
    200-character head showed two identical-looking strings and asserted they
    differed. Whatever the report can't show, a human has to re-derive by hand.

    This is a display-only comparison, deliberately over raw characters rather
    than the tokens used for scoring — characters give exact offsets into the
    original text, which is what a window needs. `autojunk=False` because the
    heuristic it disables treats any character occurring in more than 1% of a
    200+-character string as ignorable, which for prose means the spaces and
    vowels; the resulting opcodes would point at the wrong place.
    """
    ops = [
        op
        for op in difflib.SequenceMatcher(None, pdf_sent, qmd_sent, autojunk=False).get_opcodes()
        if op[0] != "equal"
    ]
    if not ops:  # differ only in characters normalise() discards, e.g. quote style
        return truncate(pdf_sent, width), truncate(qmd_sent, width)
    return (
        _window(pdf_sent, ops[0][1], ops[-1][2], width),
        _window(qmd_sent, ops[0][3], ops[-1][4], width),
    )


def find_best_sentence(
    sent_tokens: tuple[str, ...], qmd_pool: list[tuple[str, tuple[str, ...]]]
) -> tuple[float, str]:
    """Closest QMD sentence to `sent_tokens`, as (score, original_sentence).

    `qmd_pool` is (original, tokens) pairs and must be non-empty.

    Follows difflib.get_close_matches()'s idiom: the string held constant
    across the scan goes in seq2, whose index SequenceMatcher caches, so only
    the varying candidate is re-indexed. real_quick_ratio()/quick_ratio() are
    documented upper bounds on ratio(), so skipping candidates that cannot
    beat the current best is exact, not approximate.
    """
    # autojunk=False: from 200 elements up, the heuristic marks anything
    # occurring in more than 1% of seq2 as ignorable junk. On word tuples that
    # is "the", "of", "to" — structural words whose presence is real evidence —
    # and excluding them deflates ratio() into false positives. No Day 4
    # sentence reaches 200 tokens, but pdftotext collapses a whole bulleted list
    # into one blank-line-delimited block, so another day's could.
    matcher = difflib.SequenceMatcher(autojunk=False)
    matcher.set_seq2(sent_tokens)
    best_score, best_qmd = 0.0, qmd_pool[0][0]
    for qmd_sent, qmd_tokens in qmd_pool:
        matcher.set_seq1(qmd_tokens)
        if (
            matcher.real_quick_ratio() > best_score
            and matcher.quick_ratio() > best_score
        ):
            score = matcher.ratio()
            if score > best_score:
                best_score, best_qmd = score, qmd_sent
    return best_score, best_qmd


def analyse(
    pdf_paras: list[str], qmd_paras: list[str], threshold: float
) -> list[tuple[str, list[tuple[float, str, str]]]]:
    """Flag altered sentences, grouped by their source PDF paragraph.

    Returns [(pdf_paragraph, [(score, pdf_sentence, best_qmd_sentence), ...]),
    ...] for paragraphs with at least one flagged sentence. Paragraphs are
    ordered by their highest-scoring flagged sentence, and sentences within a
    paragraph likewise, so the near-certain defects come first.
    """
    # Flatten QMD into a single chapter-wide sentence pool: PDF/QMD paragraph
    # boundaries don't reliably correspond, so search the whole pool per PDF
    # sentence rather than trying to pre-pair paragraphs. Sentences that
    # normalise to nothing (stray punctuation, page furniture) can never be a
    # meaningful match, so drop them here instead of re-testing them inside
    # the O(pdf_sentences x qmd_sentences) inner loop.
    qmd_pool = [
        (sent, tokens)
        for sent, tokens in ((s, tokenise(s)) for p in qmd_paras for s in split_sentences(p))
        if tokens
    ]
    if not qmd_pool:
        return []

    altered_by_para = []
    for pdf_para in pdf_paras:
        flagged = []
        for pdf_sent in split_sentences(pdf_para):
            sent_tokens = tokenise(pdf_sent)
            if not sent_tokens:
                continue
            score, best_qmd = find_best_sentence(sent_tokens, qmd_pool)
            if score < threshold:
                flagged.append((score, pdf_sent, best_qmd))
        if flagged:
            flagged.sort(key=lambda f: -f[0])
            altered_by_para.append((pdf_para, flagged))
    altered_by_para.sort(key=lambda p: -p[1][0][0])
    return altered_by_para


def render(
    altered_by_para: list[tuple[str, list[tuple[float, str, str]]]],
    threshold: float,
) -> list[str]:
    """Format the human-readable report section."""
    out = [
        "==========================================",
        "  Altered Content (present, but modified)",
        "==========================================",
        "",
        "Each PDF paragraph below matched a QMD paragraph closely enough to",
        "not be flagged as missing, but one or more of its sentences differ",
        "from their closest QMD match by more than the similarity threshold",
        f"({threshold:.0%}) allows.",
        "",
        "Ordered by similarity, highest first — that is triage order, not",
        "severity order. Work down from the top:",
        "",
        f"  {NEAR_MATCH_SCORE:.0%} and up  Near-certainly the same sentence, so the difference",
        "              is near-certainly a real defect — a swapped word, a",
        "              dropped qualifier. These are the ones the eye skips.",
        "  lower       Ambiguous: content dropped from the page, PDF front",
        "              matter that was never meant to be transcribed, or a",
        "              passage deliberately restructured for the web. The",
        "              closest match found is shown so you can tell which.",
        "",
    ]
    for i, (pdf_para, flagged) in enumerate(altered_by_para, start=1):
        out += [f"--- Altered {i} ({len(flagged)} sentence(s) flagged) ---",
                f"Source paragraph (PDF): {truncate(pdf_para)}",
                ""]
        for score, pdf_sent, qmd_sent in flagged:
            pdf_excerpt, qmd_excerpt = diff_window(pdf_sent, qmd_sent)
            out.append(f"  [similarity {score:.0%}]")
            out.append(f"  Source (PDF):   {pdf_excerpt}")
            out.append(f"  Closest (QMD):  {qmd_excerpt}")
            out.append("")
    return out


def read_paragraphs(path: str) -> list[str]:
    with open(path, encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def main(argv: list[str]) -> int:
    if not 3 <= len(argv) <= 4:
        print(
            "Usage: paragraph_similarity.py <matched_pdf_paras.txt> "
            "<qmd_paras.txt> [threshold]",
            file=sys.stderr,
        )
        return 1

    pdf_path, qmd_path = argv[1:3]
    # Callers normally omit the threshold and take ALTERED_SIMILARITY_THRESHOLD,
    # so there is one definition of it rather than a copy per caller. The
    # override exists for tuning experiments against a single day.
    threshold = ALTERED_SIMILARITY_THRESHOLD
    if len(argv) == 4:
        try:
            threshold = float(argv[3])
        except ValueError:
            print(f"Error: threshold must be a number, got {argv[3]!r}", file=sys.stderr)
            return 1

    pdf_paras = read_paragraphs(pdf_path)
    qmd_paras = read_paragraphs(qmd_path)

    # Warn before scoring, not after: analyse() returns [] on an empty pool, so
    # a warning printed afterwards reads like a comment on the (empty) result.
    if not qmd_paras:
        print("Warning: no QMD paragraphs to compare against", file=sys.stderr)

    altered_by_para = analyse(pdf_paras, qmd_paras, threshold)

    scores = [f[0] for _, flagged in altered_by_para for f in flagged]
    print(f"ALTERED_COUNT={len(altered_by_para)}")
    print(f"FLAGGED_SENTENCES={len(scores)}")
    print(f"NEAR_MATCH_SENTENCES={sum(1 for s in scores if s >= NEAR_MATCH_SCORE)}")
    print()

    if altered_by_para:
        print("\n".join(render(altered_by_para, threshold)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
