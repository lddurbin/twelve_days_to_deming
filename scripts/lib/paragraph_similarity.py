#!/usr/bin/env python3
"""paragraph_similarity.py — find missing, altered, or unsourced content in a
transcription.

Helper for scripts/validate-transcription.sh (#677, #718, #719). Every PDF
paragraph is scored at SENTENCE granularity against every QMD sentence in the
chapter (not just those in some "corresponding" paragraph, since PDF and QMD
paragraph boundaries frequently don't align 1:1 -- e.g. a whole bulleted list
often collapses into one PDF paragraph, because pdftotext only splits on
blank lines, while each bullet is its own QMD paragraph). Sentence
granularity also catches what a paragraph-level check cannot: a single
substituted word (e.g. "he" -> "I") gets diluted to near-invisibility in a
whole-paragraph similarity score across ~100 surrounding unchanged words, but
stands out clearly once the comparison window shrinks to one sentence.

Until #719, presence was decided separately and first, by
validate-transcription.sh's own find_in_qmd(): a fingerprint of a paragraph's
first ~5 significant words, joined with `.*` and grepped against the whole
QMD text collapsed onto one line. That is a much weaker test than it looks --
five moderately common words, in order, at *any* distance, across several
thousand words of chapter text -- and measured against real content, it let
94 of 137 (69%) of Day 4's paragraphs read as "present" in the wholly
unrelated Day 7 chapter. classify_forward() below replaces it: a paragraph is
"missing" when even its single best-scoring sentence falls short of
MISSING_SIMILARITY_THRESHOLD, which is a direct read of the same
score distribution this module already computes for the "altered" check,
rather than a second, cruder test bolted on beside it.

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

That evidence has two channels, because the QMD side has two pools. The one
every score comes from holds only paragraphs above paragraphs.py's length
floor; blocks under it — which is how the site sets its cross-reference
pointers, one line to a paragraph — are searched separately. A short block
close enough to classify the pair clean anyway clears the flag outright
(#761); one that misses that gate but still beats the pooled match is printed
beside the surviving flag as a second, display-only line with its own score
(#763). Nothing about the verdict, the counts or the ordering reads that
second channel — see score_paragraph() for why it is added beside the pooled
match rather than substituted for it.

This same machinery also runs in reverse (#718): analyse()'s two paragraph
lists are direction-agnostic — one is "walked" sentence by sentence, the
other is flattened into the pool each of those sentences is matched against
— so calling it with the QMD paragraphs as the walk-list and the PDF
paragraphs as the pool finds QMD content with no credible PDF source at all,
which the forward direction can never see: a paragraph the presence check
never had a reason to doubt was "present" has no bearing on whether some
*other*, fabricated paragraph exists alongside it. This is scored against a
much lower threshold (UNSOURCED_SIMILARITY_THRESHOLD, not
ALTERED_SIMILARITY_THRESHOLD) because the reverse pool is QMD-authored prose
that was never meant to have a PDF counterpart — activity prompts, button
labels, figure captions — which routinely scores 0.3-0.7 against its nearest
PDF sentence by shared vocabulary alone.

Similarity alone cannot police reference tokens, whatever the threshold, so
a third comparison runs alongside the two above (#738): page, day and chapter
numbers, and bare numerals, are compared as multisets on every sentence pair
that scores at or above REFERENCE_PAIR_THRESHOLD — clean matches included. A
single wrong digit is one word in fifty, which scores above the altered
threshold and classifies as a faithful transcription, yet "page 18" where the
source says "page 19" sends every reader who follows the link to the wrong
content. Those findings are counted and reported separately, so they neither
distort the existing counts nor get buried under them.

This cannot catch every shape of fabrication. A sentence copied verbatim from
elsewhere in the *same* source PDF — present, but relocated or duplicated —
scores a perfect match against its true origin and is indistinguishable from
a legitimately placed quote by similarity alone. See #645, where a Rule 4
sentence was pasted into the Rule 3 section: it would not be flagged by
either direction of this scorer. What *would* be flagged is the numeric
defect that accompanied it — the wrong finishing-position numbers have no
close match anywhere in the PDF and score well under threshold. This limit is
pinned in tests/test_paragraph_similarity.py rather than left to be
rediscovered.

Usage: paragraph_similarity.py <pdf_paras.txt> <qmd_paras.txt> [threshold]

Input files: one paragraph per line, as produced by scripts/lib/paragraphs.py.
<pdf_paras.txt> is the full, unfiltered PDF paragraph list — it now serves
double duty as both the forward pass's walk-list (every PDF paragraph is
classified, not a pre-filtered "matched" subset) and the reverse pass's search
pool (a QMD paragraph's true source may be one the forward classification
marked missing).

Output: `KEY=VALUE` header lines, then a blank line, then formatted report
section(s) (absent when nothing is flagged). Callers should read the counts by
key and skip the header with `sed '1,/^$/d'` rather than by line number, so
new keys can be added without breaking them.

  MISSING_COUNT=<n>       PDF paragraphs with no sentence close enough to
                          anything in the QMD pool to count as present
  ALTERED_COUNT=<n>       PDF paragraphs with >=1 flagged sentence
  MATCHED_COUNT=<n>       PDF paragraphs with no flagged sentence, and not
                          missing — MISSING_COUNT + ALTERED_COUNT +
                          MATCHED_COUNT is every paragraph in <pdf_paras.txt>
  FLAGGED_SENTENCES=<n>   flagged sentences in total
  NEAR_MATCH_SENTENCES=<n>  flagged sentences at or above NEAR_MATCH_SCORE —
                          the high-confidence band to review first
  UNSOURCED_COUNT=<n>     QMD paragraphs with >=1 sentence with no credible
                          PDF source
  UNSOURCED_SENTENCES=<n>  such sentences in total
  REFERENCE_MISMATCHES=<n>  sentence pairs whose page/day/chapter numbers or
                          bare numerals disagree, counted independently of
                          the missing/altered/matched split — most of them
                          are *also* clean matches
  MISSING_THRESHOLD=<f>   the MISSING_SIMILARITY_THRESHOLD in effect
  ALTERED_THRESHOLD=<f>   the altered-sentence threshold in effect (the CLI
                          [threshold] override if given, else
                          ALTERED_SIMILARITY_THRESHOLD)
  UNSOURCED_THRESHOLD=<f>  the UNSOURCED_SIMILARITY_THRESHOLD in effect
  REFERENCE_THRESHOLD=<f>  the REFERENCE_PAIR_THRESHOLD in effect

These four threshold lines let a caller record exactly what a run was
scored against (see #720) without keeping its own copy of the numbers to
drift out of sync with this module.
"""
from __future__ import annotations  # `list[str]` annotations on Python < 3.9

import collections
import difflib
import re
import sys

TRUNCATE_LEN = 200

# A PDF paragraph is "missing" when even its single best-scoring sentence
# falls below this similarity against the whole QMD pool — i.e. nothing in
# the chapter resembles any part of it closely enough to call the paragraph
# present. This replaces find_in_qmd()'s fingerprint grep (#719), which
# tested presence by checking whether five moderately common words appeared
# in order at any distance across the whole chapter — a test so weak that
# pairing Day 4's real PDF against the wholly unrelated Day 7 chapter still
# read 94 of 137 (69%) of Day 4's paragraphs as "present".
#
# Measured across two independent day-pairs (Day 4 PDF vs Day 4 QMD / vs
# Day 7 QMD; Day 9 PDF vs Day 9 QMD / vs Day 2 QMD), scoring each PDF
# paragraph's best sentence against its own day's real QMD content
# ("same-day") versus an unrelated day's QMD content ("cross-day"):
#
#   cut   same-day flagged missing   cross-day flagged missing
#   0.30   3-4%                       54-60%
#   0.35   4-7%                       82%
#   0.40   5-9%                       87-91%
#   0.45   8-12%                      96-97%
#
# 0.40 is where cross-day noise (paragraphs that share no real passage)
# crosses into "substantially all flagged", while same-day paragraphs (which
# really are on the site) stay a single-digit-to-low-double-digit false-
# positive rate. Those same-day false positives were inspected by hand and
# are overwhelmingly PDF-only front matter with no prose counterpart by
# design — session itinerary lines ("Point 4: End lowest-tender contracts
# (p 22 [WB 62])"), table-of-contents entries — the same category of
# expected false positive this script's Notes section already tells readers
# to discount for headers and footers. Pushing the cut higher buys a lower
# cross-day residual at the cost of flagging more genuinely-present prose;
# 0.40 was chosen as the point past which further gains cost real content,
# not noise. See #719.
#
# The residual cross-day false negatives (13-9% at 0.40) are individual
# short, generic sentences ("I was right!", "Do you?", "There are several
# reasons.") that coincidentally score high against an unrelated day's
# equally short, generic sentence — a known limit of word-level similarity
# on short strings, not something a different cut fixes. See #645 for the
# same shape of blind spot in the "unsourced" direction.
MISSING_SIMILARITY_THRESHOLD = 0.40

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
#
# Counted from the *scored* pool's match, never from a short block's (#763):
# the band's meaning has to stay stable across the epic's recorded tables, and
# a short block admitted as display evidence has not passed the gate that makes
# a high score mean "the same sentence".
NEAR_MATCH_SCORE = 0.90

# How close a QMD short block must come before it is worth printing beside a
# flag as evidence (#763). Deliberately a reference to MISSING_SIMILARITY_THRESHOLD
# rather than a copy of its value: the question is the same question — is this
# credibly the same content? — and if that line ever moves, this one has to move
# with it or the report starts calling something evidence that the classifier
# would not call present.
#
# A candidate must also beat whatever the scored pool offered. Both conditions
# matter, and dropping either one costs something measurable across the fifteen
# records (2026-08-27, 1743 flagged sentences):
#
#   rule                                          findings gaining an evidence line
#   closer than the scored pool's match                 112
#   ... and at or above this floor                       85
#   ... at or above 0.70 instead                         42
#   ... at or above NEAR_MATCH_SCORE instead              2
#
# 0.40 rather than something tighter because the cost of the two errors is
# wildly asymmetric here. Printing a spurious short block costs one line beside
# a finding whose scored-pool match was, by construction, *worse* — the reader
# was already looking at noise. Withholding a real one costs the finding: a
# correct flag on a cross-reference pointing at the wrong page reads as
# unmatched debris and gets skipped. The band this floor admits and 0.70 would
# not is genuinely mixed — Day 5's mojibake'd "So what's in this lorry coming
# in?" at 0.52 and Day 3's "Technical Aid 10" at 0.50 sit beside coincidences
# like "Discussion 14" against the site's "Discussion" heading — and mixed is a
# reason to show it, not to hide it, because the evidence line is additive and
# hides nothing.
SHORT_EVIDENCE_FLOOR = MISSING_SIMILARITY_THRESHOLD

# Below this similarity, a QMD sentence has no credible PDF source and is
# flagged as "unsourced" — the reverse pass's counterpart to
# ALTERED_SIMILARITY_THRESHOLD above. Deliberately much lower: unlike the
# forward direction, where both sides are meant to be the same sentence, the
# reverse pool is QMD-authored prose that was never meant to have a PDF
# counterpart at all (activity prompts, button labels, figure captions,
# interactive-element copy), and that legitimate site-only text routinely
# scores 0.3-0.7 against its nearest PDF sentence just by sharing vocabulary —
# not because it's the same sentence, altered.
#
# Measured against real Day 1/3/4 paragraph pools, genuinely fabricated or
# absent content clustered under ~0.25 while every legitimate site-only
# paragraph inspected scored above it, so 0.25 sits in that gap. Set any
# higher and the standing baseline stops being "small enough to scan" — see
# #718's own acceptance criteria.
UNSOURCED_SIMILARITY_THRESHOLD = 0.25

# Reference tokens — page/day/chapter numbers and bare numerals — are compared
# on every sentence pair scoring at or above this, *including* the pairs
# ALTERED_SIMILARITY_THRESHOLD calls clean. That inclusion is the whole point
# (#738): a one-word error in a 50-word sentence scores 0.98 and classifies
# clean, and when the one wrong word is a number ("page 18" where the source
# says "page 19") it is the most consequential defect the site can carry,
# because the enriched cross-reference links built on it then send readers to
# the wrong content. Similarity fundamentally cannot police this — one digit
# among fifty words is noise to SequenceMatcher, which is why the check is a
# separate comparison rather than a tighter threshold.
#
# There is still a floor, because a numeral disagreement is only *evidence* of
# a defect when the two sentences are credibly the same sentence. Below it the
# "closest match" is a different sentence that happens to share vocabulary, and
# its numbers have nothing to say about this one. Findings across all 12 days,
# by where the floor is put:
#
#   floor   findings   per day
#   0.98         13       1.1
#   0.95         56       4.7
#   0.90        100       8.3
#   0.85        124      10.3
#   0.80        164      13.7
#   (none)      689      57.4
#
# 0.85 rather than 0.90 because of what sits in that one band. The enriched
# cross-reference links (#610) write a descriptor into the link text — "page
# 18, the guidance for the Second Project" — which adds four to eight words to
# a ~30-word sentence and costs 12-20% similarity all by itself. Measured,
# those pairs land at 0.86-0.89: a 0.90 floor would have excluded almost
# exactly the population this check exists for, including the page-19 defect
# named in #738 (0.8788 as it shipped). The 24 pairs the extra band adds
# include three further real defect candidates. Going lower stops paying:
# 0.80 adds 40 more, dominated by PDF/QMD sentence-split divergence, where the
# closest match is a fragment whose numbers legitimately differ.
#
# Deliberately a separate constant from NEAR_MATCH_SCORE, and now a different
# value: that one only labels a "review these first" band in the header, so
# re-tuning it must not silently change what this section reports.
REFERENCE_PAIR_THRESHOLD = 0.85

# Words that turn a following numeral into a pointer at specific content, so
# "page 19" and "Day 19" are distinguishable tokens rather than both "19".
# Plurals and the "p"/"pp" abbreviations fold onto the singular because the
# token names the *target*: "page 27" vs "pages 27" is a wording difference,
# which the altered check already owns.
_REFERENCE_QUALIFIERS = {
    "p": "page", "pp": "page", "page": "page", "pages": "page",
    "day": "day", "days": "day",
    "chapter": "chapter", "chapters": "chapter",
    "figure": "figure", "figures": "figure",
    "section": "section", "sections": "section",
    "part": "part", "parts": "part",
    "point": "point", "points": "point",
    "step": "step", "steps": "step",
    "rule": "rule", "rules": "rule",
    "stage": "stage", "stages": "stage",
    "level": "level", "levels": "level",
    "activity": "activity", "activities": "activity",
    "table": "table", "tables": "table",
    "volume": "volume", "volumes": "volume",
}

# The leading digit run of any word that starts with a digit, rather than a
# whitelist of suffixes. That folds together the several shapes one reference
# takes in this corpus — "11th", "1990s", and "2o", which is how
# pdftotext -layout renders "2°" — each of which would otherwise read as a
# token present on one side and absent on the other, for no defect at all.
_NUMERAL = re.compile(r"^(\d+)")


def reference_tokens(text: str) -> collections.Counter:
    """Multiset of the reference tokens in `text`.

    Runs on normalise()d text so it sees exactly the words the similarity score
    sees, and inherits its de-hyphenation of line wraps — a page number that
    pdftotext split across a line break, as "page 1-" then "9", must not read
    as a different number here than it does there.

    Since #740 that inheritance is symmetric for words: a hyphen between two
    letters is joined whether or not the PDF wrapped the line at it, so
    "Stats-level 0" reads the same on both sides. Digit-adjacent hyphens are
    deliberately not, since "pages 10-11" is two reference tokens and joining
    them would invent an "1011" that neither side contains.

    A multiset, not a set: "pages 10-11, 22-23 and 26-27" repeats numbers, and
    dropping one of a repeated pair is a defect a set would swallow.
    """
    words = normalise(text).split()
    tokens: collections.Counter = collections.Counter()
    for i, word in enumerate(words):
        numeral = _NUMERAL.match(word)
        if not numeral:
            continue
        qualifier = _REFERENCE_QUALIFIERS.get(words[i - 1]) if i else None
        tokens[f"{qualifier} {numeral.group(1)}" if qualifier else numeral.group(1)] += 1
    return tokens


def reference_mismatch(pdf_sent: str, qmd_sent: str) -> tuple[list[str], list[str]] | None:
    """(pdf_only, qmd_only) reference tokens, or None when the two agree.

    Both sides are returned because which one is empty is the first thing a
    reader needs: a token only the PDF has is content dropped or mis-copied,
    while one only the QMD has is content added — most often a descriptor the
    site wrote into an enriched cross-reference link.
    """
    pdf_refs, qmd_refs = reference_tokens(pdf_sent), reference_tokens(qmd_sent)
    if pdf_refs == qmd_refs:
        return None
    return sorted((pdf_refs - qmd_refs).elements()), sorted((qmd_refs - pdf_refs).elements())


# A hyphen between two letters is joined however much whitespace sits after it,
# including none: "long-term", "long- term" and "indi-cated" all normalise to
# one word. Symmetry is the whole point (#740). `pdftotext` line-wraps a word
# at its hyphen in all three shapes, and the QMD's intact copy has to land on
# the same token stream as whichever shape the PDF happens to emit — under the
# old whitespace-requiring rule, a wrapped "long- term" became "longterm" while
# the QMD's "long-term" became "long term", and the same word on both sides
# scored as a difference. Four of Day 9's 55 catalogued false positives were
# this shape (#732), and it recurs wherever a line happens to break.
#
# Zero-width on both sides, so consecutive hyphens cannot shadow each other.
# Consuming the following letter would make the rule's own output depend on
# where the wrap fell: "x-y-z" would come out "xy z" (the second hyphen having
# lost its left-hand letter to the first match) while "x-y- z" came out "xyz" —
# reintroducing, on multiply-hyphenated words, exactly the asymmetry this
# removes.
_LETTER_HYPHEN = re.compile(r"(?<=[a-z])-\s*(?=[a-z])")

# Every other hyphen is a line wrap only when whitespace follows it, and that
# distinction is what keeps digit ranges intact. "page 1-\n9" is one number
# split across a line break and must rejoin; "3-4" and "1985-86" are two
# numbers each and must not, because the reference-token rule (#738) compares
# those numerals and joining them would invent a "34" that appears on neither
# side. So digit-adjacent hyphens keep the stricter, pre-#740 requirement.
_WRAPPED_HYPHEN = re.compile(r"(?<=\w)-\s+(?=\w)")

# A chart tick numeral that landed inside a hyphen wrap, which is the one
# arrangement the two rules above cannot handle between them (#760).
#
# `pdftotext -layout` lifts a control chart's y-axis tick labels off the figure
# and into the adjacent line of prose. When one lands between the two halves of
# a wrapped word, _LETTER_HYPHEN's `(?=[a-z])` sees the digit and declines,
# then _WRAPPED_HYPHEN's `\w` accepts it and welds the numeral onto the first
# half: "just for complete- 30 ness" becomes `complete30 ness` instead of
# `completeness`, and a faithful sentence flags. 27 of the Optional Extras
# appendix's 218 near-certain flags were this shape.
#
# Removing the numeral outright is safe *only* in this context, and that is why
# the rule is written this narrowly rather than as a general digit strip —
# normalise() deliberately keeps standalone digits, because "14 Points" against
# "12 Points" is exactly the defect worth catching. A digit run fenced by
# whitespace between a hyphen and the letters continuing the word it wrapped
# cannot be part of either word, and cannot be prose: it is figure furniture
# that fell into the line.
#
# Must run before both rules above — _WRAPPED_HYPHEN would otherwise consume
# the hyphen first and leave the numeral fused to the stem.
_TICK_IN_WRAP = re.compile(r"(?<=[a-z])-\s+\d+\s+(?=[a-z])")


def normalise(text: str) -> str:
    """Lowercase, rejoin hyphenated words, strip punctuation, collapse
    whitespace.

    Deliberately does NOT strip the letter "f" or standalone digits, both of
    which earlier revisions did. Those were compensating for two bugs in
    validate-transcription.sh's own extract_pdf_text() — a `s/\\f//g` that BSD
    sed read as "delete every f", and a page-number rule that ate inline
    numbers like "the 14 Points". Both are fixed at source, and stripping
    either here would blind the scorer to real defects: "of" vs "or" and
    "14 Points" vs "12 Points" are exactly the mistakes worth catching.
    """
    text = text.lower()  # first, so _LETTER_HYPHEN's [a-z] sees every letter
    text = _TICK_IN_WRAP.sub("", text)
    text = _LETTER_HYPHEN.sub("", text)
    text = _WRAPPED_HYPHEN.sub("", text)
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
# The quote characters in both classes are typographic as well as straight,
# and that pairing is the whole point (#741). The printed page sets its quotes
# curly and the QMD sources them straight, so a straight-only class splits the
# QMD at `…said." Then` and leaves the PDF's `…said.” Then` as one fused
# sentence — an asymmetry manufactured by the comparator, on the side that
# cannot be proofread. Both sides run this one regex; it has to accept both
# conventions or it segments them differently.
#
# `(?<![:;,][.!?])` is the same concern from the other direction: pdftotext
# renders the printed page's superscript footnote callouts as a literal `!`,
# and a callout hanging off a lead-in colon comes out as `Let me quote Peter:!
# “A fundamental premise…`. Read as punctuation, that `!` splits a sentence
# the QMD keeps whole, stranding a four-word fragment that matches nothing.
# The shape is unambiguous: 55 occurrences of `[:;,][.!?]` across the twelve
# PDFs, and none at all in the QMD text, because no real sentence ends in a
# colon and a full stop. The marker itself is harmless once it stops being a
# boundary — normalise() drops it with the rest of the punctuation.
#
# Bullet glyphs are boundaries too. pdftotext puts a whole bullet list in one
# blank-line-delimited block, so without this a PDF "sentence" runs from the
# tail of one bullet across the marker into the head of the next — a shape no
# QMD sentence can match, and a steady source of mid-range false positives.
_SENTENCE_BOUNDARY = re.compile(
    r"""(?<=[.!?])(?<![:;,][.!?])["'”’)\]]?\s+(?=["'“‘(\[]?[A-Z0-9])|\s*[•‣▪]\s*"""
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


def build_pool(paras: list[str]) -> list[tuple[str, tuple[str, ...]]]:
    """Flatten paragraphs into a single chapter-wide sentence pool.

    PDF/QMD paragraph boundaries don't reliably correspond, so both analyse()
    and classify_forward() search the whole pool per sentence rather than
    trying to pre-pair paragraphs. Sentences that normalise to nothing (stray
    punctuation, page furniture) can never be a meaningful match, so they're
    dropped here instead of being re-tested inside the O(sentences x pool)
    inner loop.
    """
    return [
        (sent, tokens)
        for sent, tokens in ((s, tokenise(s)) for p in paras for s in split_sentences(p))
        if tokens
    ]


def score_paragraph(
    pdf_para: str,
    qmd_pool: list[tuple[str, tuple[str, ...]]],
    short_pool: list[tuple[str, tuple[str, ...]]] | None = None,
    admit_short_at: float = ALTERED_SIMILARITY_THRESHOLD,
    evidence_floor: float = SHORT_EVIDENCE_FLOOR,
) -> list[tuple[float, str, str, tuple[float, str] | None]]:
    """(score, pdf_sentence, best_qmd_sentence, short_block_evidence) for every
    scoreable sentence in `pdf_para`, unfiltered by any threshold.

    The first three fields are the verdict channel and mean exactly what they
    have always meant: `score` against `best_qmd_sentence` is what decides
    missing/altered/matched, what the near-certain band counts, what the
    reference-token check compares, and what the report orders by. The fourth
    is display-only (#763) — see below.

    Shared by analyse() (which keeps only the sentences a threshold flags)
    and classify_forward() (which needs every score, including the ones a
    threshold would discard, to find a paragraph's single best sentence).

    `short_pool` is the QMD's sub-floor blocks (#761), consulted only when the
    main pool cannot clear `admit_short_at` and admitted only when the short
    pool itself does. Both halves of that rule matter:

    - **Why they must be consulted at all.** paragraphs.py keeps everything
      under MIN_PARA_LEN out of `qmd_pool`, so a line the site sets as its own
      short paragraph is invisible as a match candidate — while the PDF, which
      sets the same words as the tail of a full paragraph, offers them for
      scoring. Day 5's eleven `(See Appendix page NN.)` pointers are all on the
      site and all flagged at the 20% floor for exactly this reason. Corpus-
      wide, 87 of the twelve days' flagged sentences are present verbatim on
      the site and reported missing.

    - **Why the gate is the altered threshold and not lower.** The floor exists
      because a four-word heading scores 0.5 against any other four-word
      heading; admitting short blocks unconditionally would buy this coverage
      in the currency of noise, and worse, could let a spurious short match
      become a sentence's "best" one and mask a real defect. Requiring
      `admit_short_at` — the score at or above which a pair is classified
      *clean* anyway — makes that impossible by construction. A short block
      either matches closely enough that the text genuinely is on the site, or
      it never competes. No existing score moves; the only effect a short block
      can have is to clear a flag that should never have been raised.

    Known limitation, shared with #645 and worth stating here because short
    blocks are where it is most likely: a QMD short block that legitimately
    appears once can clear *two* identical PDF sentences, hiding a dropped
    duplicate. Repeated `(See Appendix page N.)` pointers are exactly that
    shape. Spike #745 owns the general problem.

    A short pointer whose number is wrong — PDF "page 26" against the site's
    "page 27" — scores 0.75 on four word-tokens and so does not clear the gate.
    It stays flagged, correctly. What #761 left behind was that it was then
    *reported* against whatever the main pool offered, which for a four-word
    sentence is unrelated prose, so the most consequential defect the site can
    carry read as unmatched debris.

    `short_block_evidence` is the fix, and it is a second channel rather than a
    correction to the first: `(score, sentence)` for the closest short block
    when one beat the scored pool's match and cleared `evidence_floor`, else
    None. Renderers print it as an extra labelled line carrying its own score,
    so both lines say what they mean.

    **Why it is added beside the scored-pool match and never substituted for
    it.** The masking risk the gate exists to prevent applies to the display
    too. Take the case `test_a_short_block_cannot_win_below_the_gate` pins: the
    PDF reads "The Deadly Diseases of management.", the site says "leadership",
    and a bare "The Deadly Diseases of" heading sits in the short pool. The
    scored pool holds the true counterpart at 0.80 and shows the reader the
    swapped word; the heading scores 0.89 by being a prefix of both. Swap the
    display for the higher number and the defect disappears from the report
    that flagged it. Since which of the two is the real counterpart cannot be
    told apart by score, the report shows both and hides neither.

    A consequence worth stating: because the near-certain band is counted from
    the verdict score, an evidence line can read above NEAR_MATCH_SCORE without
    its finding being in that band. Two of the fifteen records carry one
    (2026-08-27). That is the band keeping its meaning, not a miscount.
    """
    scored = []
    for pdf_sent in split_sentences(pdf_para):
        sent_tokens = tokenise(pdf_sent)
        if not sent_tokens:
            continue
        score, best_qmd = (
            find_best_sentence(sent_tokens, qmd_pool) if qmd_pool else (0.0, "")
        )
        # One search of the short pool, two possible uses of its answer: it
        # either clears the flag outright (#761) or, failing that, is kept as
        # display evidence (#763). Both live under the same `score <
        # admit_short_at` guard the gate already required, so the evidence
        # channel costs no extra scanning — it keeps a result that used to be
        # computed and thrown away.
        evidence = None
        if short_pool and score < admit_short_at:
            short_score, short_qmd = find_best_sentence(sent_tokens, short_pool)
            if short_score >= admit_short_at:
                score, best_qmd = short_score, short_qmd
            elif short_score > score and short_score >= evidence_floor:
                evidence = (short_score, short_qmd)
        scored.append((score, pdf_sent, best_qmd, evidence))
    return scored


def analyse(
    pdf_paras: list[str], qmd_paras: list[str], threshold: float
) -> list[tuple[str, list[tuple[float, str, str, tuple[float, str] | None]]]]:
    """Flag altered sentences, grouped by their source PDF paragraph.

    Returns [(pdf_paragraph, [(score, pdf_sentence, best_qmd_sentence,
    short_block_evidence), ...]), ...] for paragraphs with at least one flagged
    sentence. Paragraphs are ordered by their highest-scoring flagged sentence,
    and sentences within a paragraph likewise, so the near-certain defects come
    first.

    No short pool is offered here, so every finding's evidence field is None.
    This is the reverse pass's entry point (QMD walking, PDF pooled), and the
    short-block channel is a property of the QMD side being length-filtered —
    it has no counterpart running the other way.
    """
    qmd_pool = build_pool(qmd_paras)
    if not qmd_pool:
        return []

    altered_by_para = []
    for pdf_para in pdf_paras:
        flagged = [f for f in score_paragraph(pdf_para, qmd_pool) if f[0] < threshold]
        if flagged:
            flagged.sort(key=lambda f: -f[0])
            altered_by_para.append((pdf_para, flagged))
    altered_by_para.sort(key=lambda p: -p[1][0][0])
    return altered_by_para


def classify_forward(
    pdf_paras: list[str],
    qmd_paras: list[str],
    missing_threshold: float,
    altered_threshold: float,
    reference_threshold: float = REFERENCE_PAIR_THRESHOLD,
    qmd_short: list[str] | None = None,
    evidence_floor: float = SHORT_EVIDENCE_FLOOR,
) -> tuple[
    list[str],
    list[tuple[str, list[tuple[float, str, str, tuple[float, str] | None]]]],
    int,
    list[tuple[float, str, str, list[str], list[str]]],
]:
    """Three-way split of every PDF paragraph: missing / altered / matched
    cleanly, plus the reference-token mismatches found along the way.
    Supersedes find_in_qmd()'s fingerprint grep (#719).

    A paragraph is "missing" when even its single best-scoring sentence
    falls below `missing_threshold` against the whole QMD pool — nothing in
    the chapter resembles any part of it closely enough to call it present.
    A paragraph that clears that bar but still has >=1 sentence below
    `altered_threshold` is "altered"; everything else is matched cleanly.

    A paragraph with no scoreable sentence at all (all punctuation, or an
    empty QMD pool to compare against) has a best score of 0.0 by
    construction, so it falls out as "missing" rather than defaulting to
    "matched" — the old find_in_qmd() fingerprint-empty case failed open
    into a false "matched"; this fails closed instead.

    Reference mismatches (#738) are collected here rather than by a second
    pass, because this walk already scores every PDF sentence against the
    whole QMD pool and that scan is the expensive part of a run — a separate
    function taking the same two paragraph lists would double it. They cut
    across the three-way split rather than refining it: a mismatch is
    reported whether its paragraph classified altered or matched cleanly, and
    the clean ones are the findings that motivated the check. No mismatch can
    come from a "missing" paragraph, since reference_threshold is well above
    missing_threshold, so a paragraph holding a qualifying pair cannot be one.

    `qmd_short` is the QMD's sub-floor blocks, offered as additional match
    candidates under the strict gate score_paragraph() documents (#761), and —
    where they miss that gate but still beat the scored pool — as display
    evidence beside the flag that survives (#763). It is optional and defaults
    to none, so every caller that predates it scores exactly the population it
    did before.

    Only the verdict channel feeds the three-way split and the reference
    comparison below. An evidence pair changes nothing that is counted: not
    whether a paragraph is missing, not whether a sentence is flagged, not the
    near-certain band, and not which pairs have their reference tokens compared.
    A short block that is the true counterpart of a "page 105 / Day 7 page 4"
    pointer therefore still does not get its numbers checked — that is #738's
    population, deliberately left where it was, since widening it would move a
    recorded count.

    `evidence_floor` is threaded rather than left to score_paragraph()'s
    default for the same reason `reference_threshold` above is: a floor only
    this module's own default can reach is one no test can vary, and the
    fixture needed to exercise it at the default alone has to be built
    backwards from the number. Production never passes it — like
    `reference_threshold`, it exists so the constant can be re-tuned against
    evidence rather than by argument.

    Returns (missing_paragraphs, altered_by_para, matched_count,
    reference_mismatches). altered_by_para has the same shape analyse()
    returns; reference_mismatches is (score, pdf_sentence, qmd_sentence,
    pdf_only_tokens, qmd_only_tokens), highest score first.
    """
    qmd_pool = build_pool(qmd_paras)
    # Admitted at `altered_threshold` — see score_paragraph() for why the gate
    # is that value and not a looser one.
    short_pool = build_pool(qmd_short or [])

    missing_paras = []
    altered_by_para = []
    reference_mismatches = []
    matched = 0
    for pdf_para in pdf_paras:
        scored = (
            score_paragraph(
                pdf_para, qmd_pool, short_pool, altered_threshold, evidence_floor
            )
            if qmd_pool or short_pool
            else []
        )
        for score, pdf_sent, qmd_sent, _evidence in scored:
            if score < reference_threshold:
                continue
            mismatch = reference_mismatch(pdf_sent, qmd_sent)
            if mismatch:
                reference_mismatches.append((score, pdf_sent, qmd_sent, *mismatch))
        best_score = max((s for s, _, _, _ in scored), default=0.0)
        if best_score < missing_threshold:
            missing_paras.append(pdf_para)
            continue
        flagged = [f for f in scored if f[0] < altered_threshold]
        if flagged:
            flagged.sort(key=lambda f: -f[0])
            altered_by_para.append((pdf_para, flagged))
        else:
            matched += 1

    altered_by_para.sort(key=lambda p: -p[1][0][0])
    reference_mismatches.sort(key=lambda m: -m[0])
    return missing_paras, altered_by_para, matched, reference_mismatches


def _format_findings(
    by_para: list[tuple[str, list[tuple[float, str, str, tuple[float, str] | None]]]],
    item_label: str,
    para_label: str,
    walk_label: str,
    pool_label: str,
) -> list[str]:
    """Per-finding block shared by render() and render_unsourced().

    The two directions differ only in which side is being walked and which is
    the search pool, so the labels are the only thing that needs to change.
    Both label pairs happen to be the same character length ("Source (PDF):"/
    "Source (QMD):", "Closest (QMD):"/"Closest (PDF):"), so a single field
    width keeps the excerpt columns aligned either way.

    The short-block evidence line (#763) is not parameterised alongside them,
    because it is structurally forward-only: it exists because the *QMD* side
    is length-filtered out of the match pool, and the reverse direction pools
    the PDF. analyse() is never handed a short pool, so every reverse finding's
    evidence field is None and this line never prints there.
    """
    out = []
    for i, (para, flagged) in enumerate(by_para, start=1):
        out += [f"--- {item_label} {i} ({len(flagged)} sentence(s) flagged) ---",
                f"{para_label}: {truncate(para)}",
                ""]
        for score, walk_sent, pool_sent, evidence in flagged:
            walk_excerpt, pool_excerpt = diff_window(walk_sent, pool_sent)
            out.append(f"  [similarity {score:.0%}]")
            out.append(f"  {walk_label:<16}{walk_excerpt}")
            out.append(f"  {pool_label:<16}{pool_excerpt}")
            if evidence is not None:
                # Its own score on its own line, next to the string that score
                # was computed against. The headline above stays the verdict
                # score against the pooled match — two numbers, each beside
                # what it measures, rather than one number floating between
                # two candidates.
                evidence_score, evidence_sent = evidence
                out.append(
                    f"  {'Closer (short):':<16}{truncate(evidence_sent)}"
                    f"  [{evidence_score:.0%}]"
                )
            out.append("")
    return out


def render_missing(missing_paras: list[str], threshold: float) -> list[str]:
    """Format the human-readable "potentially missing" report section.

    Unlike render()/render_unsourced(), there is no per-sentence finding to
    show — a "missing" paragraph's best sentence still fell below threshold,
    so nothing found is worth pointing at as "the closest match". The
    paragraph itself, truncated, is the whole of what there is to show.
    """
    out = [
        "==========================================",
        "  Potentially Missing Content",
        "==========================================",
        "",
        "The following PDF paragraphs had no sentence scoring a close match",
        f"(>= {threshold:.0%}) anywhere in the QMD files. Review these to",
        "determine if they are:",
        "  - Genuinely missing from the transcription",
        "  - Page headers/footers, tables of contents, or other boilerplate",
        "    with no prose counterpart by design",
        "  - Content intentionally omitted or restructured",
        "",
    ]
    for i, para in enumerate(missing_paras, start=1):
        out += [f"--- Gap {i} ---", truncate(para), ""]
    return out


def render(
    altered_by_para: list[tuple[str, list[tuple[float, str, str]]]],
    threshold: float,
) -> list[str]:
    """Format the human-readable "altered content" report section."""
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
        "A third line, \"Closer (short):\", appears where the genuinely closest",
        "QMD text is a block too short to be scored against — the site sets its",
        "cross-reference pointers as their own one-line paragraphs, and those",
        "fall under the length floor. It carries its own similarity, and it is",
        "evidence only: the flag, its headline score and the ordering above all",
        "come from the pooled match on the line before it. Read the pair that",
        "scores higher, but check both — either can be the real counterpart, and",
        "which is which is exactly what similarity cannot tell you here.",
        "",
    ]
    out += _format_findings(
        altered_by_para, "Altered", "Source paragraph (PDF)",
        "Source (PDF):", "Closest (QMD):",
    )
    return out


def render_unsourced(
    unsourced_by_para: list[tuple[str, list[tuple[float, str, str]]]],
    threshold: float,
) -> list[str]:
    """Format the human-readable "unsourced content" report section — the
    reverse direction: QMD paragraphs with no credible PDF source."""
    out = [
        "==========================================",
        "  Unsourced Content (no credible PDF source)",
        "==========================================",
        "",
        "Each QMD paragraph below has one or more sentences whose closest",
        "match anywhere in the PDF scores below the similarity threshold",
        f"({threshold:.0%}) — nothing in the source resembles it closely enough",
        "to call it the same sentence, reworded.",
        "",
        "Most findings here are expected and harmless: activity prompts,",
        "button labels, figure captions, and other content that only ever",
        "existed on the site. The minority worth a second look is content",
        "invented during transcription with no PDF counterpart at all.",
        "",
        "Known blind spot: a sentence copied verbatim from elsewhere in the",
        "SAME PDF scores a perfect match against its true origin and will NOT",
        "appear here, even if it was pasted into the wrong place in the QMD.",
        "Only wording that resembles nothing in the source is caught — see",
        "#645 and the module docstring.",
        "",
    ]
    out += _format_findings(
        unsourced_by_para, "Unsourced", "QMD paragraph",
        "Source (QMD):", "Closest (PDF):",
    )
    return out


def render_reference_mismatches(
    mismatches: list[tuple[float, str, str, list[str], list[str]]],
    threshold: float,
) -> list[str]:
    """Format the human-readable "reference mismatches" report section.

    Kept separate from the altered/unsourced sections, and counted separately
    in the header, so it can't distort the counts those sections have been
    tracked by since #720 — most of what appears here is *also* a clean match,
    which is the point.
    """
    out = [
        "==========================================",
        "  Reference Mismatches (numbers that disagree)",
        "==========================================",
        "",
        "Each pair below is a PDF sentence and its closest QMD match at",
        f"{threshold:.0%} similarity or better — credibly the same sentence — whose",
        "reference tokens disagree: page, day and chapter numbers, and bare",
        "numerals.",
        "",
        "This section is deliberately independent of the missing/altered/matched",
        "split above, and a finding here is usually *also* a clean match. That is",
        "what it is for: one wrong digit in a long sentence scores above the",
        "altered threshold, so a cross-reference pointing at the wrong page — the",
        "most consequential defect this site can carry, since the reader is sent",
        "somewhere else entirely — is invisible to similarity alone. See #738.",
        "",
        "Two large and mostly harmless categories are expected here:",
        "",
        "  PDF only    Often a page number that `pdftotext -layout` dropped into",
        "              the middle of a line of prose (\"the control 5 chart\"), or",
        "              a workbook cross-reference the site omits by design.",
        "  QMD only    Often a descriptor the site writes into an enriched",
        "              cross-reference link, or a citation tail on a quotation.",
        "",
        "Check the excerpts before treating any of these as a defect — as with",
        "the altered flags, this is a triage filter, not a verdict.",
        "",
    ]
    for i, (score, pdf_sent, qmd_sent, pdf_only, qmd_only) in enumerate(mismatches, start=1):
        pdf_excerpt, qmd_excerpt = diff_window(pdf_sent, qmd_sent)
        out += [
            f"--- Reference mismatch {i} [similarity {score:.0%}] ---",
            f"  {'PDF only:':<16}{', '.join(pdf_only) or '(none)'}",
            f"  {'QMD only:':<16}{', '.join(qmd_only) or '(none)'}",
            f"  {'Source (PDF):':<16}{pdf_excerpt}",
            f"  {'Closest (QMD):':<16}{qmd_excerpt}",
            "",
        ]
    return out


def read_paragraphs(path: str) -> list[str]:
    with open(path, encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def main(argv: list[str]) -> int:
    # `--qmd-short PATH` is optional and parsed out before the positionals, so
    # the existing three-or-four-argument shape is unchanged for every caller
    # that does not pass it.
    argv = list(argv)
    qmd_short_path = None
    if "--qmd-short" in argv:
        i = argv.index("--qmd-short")
        if i + 1 >= len(argv):
            print("Error: --qmd-short needs a path", file=sys.stderr)
            return 1
        qmd_short_path = argv[i + 1]
        del argv[i : i + 2]

    if not 3 <= len(argv) <= 4:
        print(
            "Usage: paragraph_similarity.py <pdf_paras.txt> <qmd_paras.txt> "
            "[threshold] [--qmd-short <qmd_short.txt>]",
            file=sys.stderr,
        )
        return 1

    pdf_path, qmd_path = argv[1:3]
    # Callers normally omit the threshold and take ALTERED_SIMILARITY_THRESHOLD,
    # so there is one definition of it rather than a copy per caller. The
    # override exists for tuning experiments against a single day, and applies
    # only to the forward "altered" cut — nothing yet needs to override
    # MISSING_SIMILARITY_THRESHOLD or UNSOURCED_SIMILARITY_THRESHOLD from the CLI.
    threshold = ALTERED_SIMILARITY_THRESHOLD
    if len(argv) == 4:
        try:
            threshold = float(argv[3])
        except ValueError:
            print(f"Error: threshold must be a number, got {argv[3]!r}", file=sys.stderr)
            return 1

    pdf_paras = read_paragraphs(pdf_path)
    qmd_paras = read_paragraphs(qmd_path)
    qmd_short = read_paragraphs(qmd_short_path) if qmd_short_path else []

    # Warn before scoring, not after: classify_forward()/analyse() return
    # everything-missing / [] on an empty pool, so a warning printed
    # afterwards reads like a comment on the (empty/all-missing) result.
    if not qmd_paras:
        print("Warning: no QMD paragraphs to compare against", file=sys.stderr)
    if not pdf_paras:
        print("Warning: no PDF paragraphs to compare against", file=sys.stderr)

    missing_paras, altered_by_para, matched_count, reference_mismatches = classify_forward(
        pdf_paras,
        qmd_paras,
        MISSING_SIMILARITY_THRESHOLD,
        threshold,
        qmd_short=qmd_short,
    )
    # Reverse direction (#718): QMD paragraphs walk, the full PDF paragraph
    # pool is searched — analyse() needs no changes to run backwards. The
    # full pool is pdf_paras itself now that the forward pass no longer
    # pre-filters to a "matched" subset (#719).
    unsourced_by_para = analyse(qmd_paras, pdf_paras, UNSOURCED_SIMILARITY_THRESHOLD)

    scores = [f[0] for _, flagged in altered_by_para for f in flagged]
    print(f"MISSING_COUNT={len(missing_paras)}")
    print(f"ALTERED_COUNT={len(altered_by_para)}")
    print(f"MATCHED_COUNT={matched_count}")
    print(f"FLAGGED_SENTENCES={len(scores)}")
    print(f"NEAR_MATCH_SENTENCES={sum(1 for s in scores if s >= NEAR_MATCH_SCORE)}")
    print(f"UNSOURCED_COUNT={len(unsourced_by_para)}")
    print(f"UNSOURCED_SENTENCES={sum(len(flagged) for _, flagged in unsourced_by_para)}")
    print(f"REFERENCE_MISMATCHES={len(reference_mismatches)}")
    print(f"MISSING_THRESHOLD={MISSING_SIMILARITY_THRESHOLD}")
    print(f"ALTERED_THRESHOLD={threshold}")
    print(f"UNSOURCED_THRESHOLD={UNSOURCED_SIMILARITY_THRESHOLD}")
    print(f"REFERENCE_THRESHOLD={REFERENCE_PAIR_THRESHOLD}")
    print()

    # Reference mismatches lead the report, ahead of the far longer altered
    # list, because they are the shortest section and the highest-consequence
    # one — burying ~9 findings under 130 altered ones is how they get skipped.
    sections = []
    if reference_mismatches:
        sections.append(
            "\n".join(render_reference_mismatches(reference_mismatches, REFERENCE_PAIR_THRESHOLD))
        )
    if missing_paras:
        sections.append("\n".join(render_missing(missing_paras, MISSING_SIMILARITY_THRESHOLD)))
    if altered_by_para:
        sections.append("\n".join(render(altered_by_para, threshold)))
    if unsourced_by_para:
        sections.append(
            "\n".join(render_unsourced(unsourced_by_para, UNSOURCED_SIMILARITY_THRESHOLD))
        )
    if sections:
        print("\n\n".join(sections))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
