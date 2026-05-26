# Deviations from Source

This log records **material departures** from Henry Neave's *12 Days to Deming* course where the site's text, structure, or content differs from the NZOQ PDF originals. The project's stated principle is verbatim transcription, so every material departure is a deliberate choice and is captured here.

## Why this log exists

Future contributors should be able to see at a glance where the site has diverged, and readers cross-referencing the NZOQ PDFs should have a single index of what's different. Without this log, each new deviation gets relitigated from scratch because prior precedent isn't surfaced.

## What counts

Record an entry when the change is **material**. Don't record mechanical changes.

**Material** (record):
- Whole sentences, paragraphs, or passages removed, added, or reworded.
- Pedagogical elements (activities, cross-references, call-outs) omitted or restructured.
- Interactive affordances substituted for static text in a way that changes what the reader does.
- Reorganisation that moves content across chapter or day boundaries.

**Mechanical** (don't record):
- Typography, whitespace, punctuation normalisation.
- Minor reflowing of paragraphs for web layout.
- Image extraction from scans.
- Clear typo corrections where Neave's intent is unambiguous.
- Hyperlinking existing cross-references (e.g. "see page 42" → an in-page anchor) without altering wording.

When in doubt, record it — readers and future contributors are better served by over-inclusion than by silent omission.

## Entry format

Each deviation is an `## YYYY-MM-DD — short title` section with the following fields:

- **What** — one-line description of the change.
- **Where** — site location (chapter, appendix, or surface area).
- **Source reference** — the corresponding location in Neave's PDF, where identifiable.
- **Why** — the reason for departing from the source.
- **Decided in** — link to the issue or PR comment where the decision was locked.
- **Landed in** — implementing PR(s) and/or commit(s), or *Pending — tracked in #NNN* if not yet merged.

Entries are listed newest-first.
