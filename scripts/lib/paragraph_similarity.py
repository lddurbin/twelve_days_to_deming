#!/usr/bin/env python3
"""paragraph_similarity.py — score PDF-vs-QMD paragraph similarity.

Helper for scripts/validate-transcription.sh's "altered content" mode (#677).
That script already confirms a PDF paragraph is *present* in the QMD text via
a fingerprint (first-8-words) match against the whole QMD blob. That check
can't see a defect sitting past those first 8 words — a swapped word, a
paraphrased clause, dropped detail — since the fingerprint still matches.

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

Sentence pairs scoring below a threshold are flagged and grouped back under
their source PDF paragraph for the report, so a reviewer sees the paragraph
in context rather than a flat list of disconnected sentences.

Usage: paragraph_similarity.py <matched_pdf_paras.txt> <qmd_paras.txt> <threshold>

Input files: one paragraph per line, as produced by validate-transcription.sh's
text_to_paragraphs().

Output:
  Line 1: ALTERED_COUNT=<n>   (count of PDF PARAGRAPHS with >=1 flagged sentence)
  Line 2: (blank)
  Remaining lines: a formatted "Altered Content" report section (omitted
  entirely, past the count line, when <n> is 0).
"""
import difflib
import re
import sys

TRUNCATE_LEN = 200


def normalise(text: str) -> str:
    """Lowercase, rejoin line-wrap hyphenation, strip punctuation, drop
    literal 'f' (works around pdftotext silently eating fi/fl/ff ligatures),
    drop standalone digits (works around validate-transcription.sh's
    extract_pdf_text() stripping inline page-number-shaped numbers from the
    PDF side only -- "Day 1 page 35" vs "Day page" would otherwise score as
    a false difference), collapse whitespace.
    """
    text = re.sub(r"(\w)-\s+(\w)", r"\1\2", text)  # de-hyphenate line wraps
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    text = text.replace("f", "")
    text = re.sub(r"\b[0-9]+\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def split_sentences(text: str) -> list[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p.strip()]


def truncate(text: str, n: int = TRUNCATE_LEN) -> str:
    return text if len(text) <= n else text[:n] + "..."


def find_best_sentence(sent_norm: str, qmd_sents: list[str], qmd_sent_norms: list[str]) -> tuple[float, str]:
    best_score, best_qmd = -1.0, ""
    for qmd_sent, qmd_norm in zip(qmd_sents, qmd_sent_norms):
        if not qmd_norm:
            continue
        score = difflib.SequenceMatcher(None, sent_norm, qmd_norm).ratio()
        if score > best_score:
            best_score, best_qmd = score, qmd_sent
    return best_score, best_qmd


def main() -> None:
    if len(sys.argv) != 4:
        print(
            "Usage: paragraph_similarity.py <matched_pdf_paras.txt> <qmd_paras.txt> <threshold>",
            file=sys.stderr,
        )
        sys.exit(1)

    pdf_path, qmd_path, threshold_arg = sys.argv[1:4]
    threshold = float(threshold_arg)

    with open(pdf_path, encoding="utf-8") as f:
        pdf_paras = [line.rstrip("\n") for line in f if line.strip()]
    with open(qmd_path, encoding="utf-8") as f:
        qmd_paras = [line.rstrip("\n") for line in f if line.strip()]

    # Flatten QMD into a single chapter-wide sentence pool: PDF/QMD paragraph
    # boundaries don't reliably correspond, so search the whole pool per
    # PDF sentence rather than trying to pre-pair paragraphs.
    qmd_sents = [s for p in qmd_paras for s in split_sentences(p)]
    qmd_sent_norms = [normalise(s) for s in qmd_sents]

    # altered_by_para: pdf_para -> list of (score, pdf_sentence, best_qmd_sentence)
    altered_by_para: list[tuple[str, list[tuple[float, str, str]]]] = []
    for pdf_para in pdf_paras:
        flagged = []
        for pdf_sent in split_sentences(pdf_para):
            sent_norm = normalise(pdf_sent)
            if not sent_norm or not qmd_sents:
                continue
            score, best_qmd = find_best_sentence(sent_norm, qmd_sents, qmd_sent_norms)
            if score >= 0 and score < threshold:
                flagged.append((score, pdf_sent, best_qmd))
        if flagged:
            altered_by_para.append((pdf_para, flagged))

    print(f"ALTERED_COUNT={len(altered_by_para)}")
    print()

    if not altered_by_para:
        return

    print("==========================================")
    print("  Altered Content (present, but modified)")
    print("==========================================")
    print()
    print("Each PDF paragraph below matched a QMD paragraph closely enough to")
    print("not be flagged as missing, but one or more of its sentences differ")
    print(f"from their closest QMD match by more than the similarity threshold")
    print(f"({threshold:.0%}) allows. This can mean a swapped word, a paraphrased")
    print("sentence, or dropped detail -- or it can mean intentional")
    print("restructuring for the web version. Review each pair to tell which.")
    print()

    for i, (pdf_para, flagged) in enumerate(altered_by_para, start=1):
        print(f"--- Altered {i} ({len(flagged)} sentence(s) flagged) ---")
        print(f"Source paragraph (PDF): {truncate(pdf_para)}")
        print()
        for score, pdf_sent, qmd_sent in flagged:
            print(f"  [similarity {score:.0%}]")
            print(f"  Source (PDF):  {truncate(pdf_sent)}")
            print(f"  Current (QMD): {truncate(qmd_sent)}")
            print()


if __name__ == "__main__":
    main()
