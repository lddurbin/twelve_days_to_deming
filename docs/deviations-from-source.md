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

---

## 2026-04-23 — Dead external links to deming.org.uk and rqoq.org.nz

- **What** — Six external hyperlinks retired because their domains no longer resolve. Two treatments were applied:
  1. **Wayback substitution (4 sites)** — `deming.org.uk` references in `content/days/day-01/02-rediscovered.qmd`, `content/days/day-01/06-outline.qmd`, `content/appendix/11-references-and-sources.qmd`, and `index.qmd` now link to the 2012-01-05 archived snapshot (`web.archive.org/web/20120105232234/…`) with an inline annotation that the live site is no longer online. The Feb 2022 "being upgraded" note in `11-references-and-sources.qmd` was rewritten accordingly.
  2. **De-linked with editorial note (2 sites)** — `welcome.qmd:109` (book-ordering footnote) de-linked and annotated "no longer trading"; `welcome.qmd:129` (PDF-hosting mirror list) de-linked and annotated "domain is no longer online and no archived snapshot is available", since `rqoq.org.nz` has zero Wayback captures.
- **Where** — `welcome.qmd`, `index.qmd`, `content/days/day-01/02-rediscovered.qmd`, `content/days/day-01/06-outline.qmd`, `content/appendix/11-references-and-sources.qmd`.
- **Source reference** — Neave's text treats both domains as live resources: the UK Deming Transformation Forum's Learning Store (bookshop/materials) and the NZOQ PDF-hosting mirror.
- **Why** — `deming.org.uk` no longer resolves and has only one Wayback capture (2012); the Forum appears to have wound down. `rqoq.org.nz` no longer resolves and was never archived. The two book-ordering footnote contexts (`welcome.qmd:109`, `index.qmd:568`) were split: `welcome.qmd:109` was fully de-linked because pointing readers at a 2012 snapshot to "order the book" is actively misleading; `index.qmd:568` retained the Wayback link with a clear archival note because its surrounding prose is informational rather than transactional.
- **Decided in** — Conversation on #239 (2026-04-23): user approved Wayback-where-available / editorial-note-where-not, with the welcome.qmd ordering footnote treated as "no longer trading".
- **Landed in** — *Pending — tracked in [#239](https://github.com/lddurbin/twelve_days_to_deming/issues/239).*

## 2026-04-21 — Rewrite or remove Workbook references from prose and front matter

- **What** — Drop or rewrite surviving references to "the Workbook" as a companion artefact, so readers are no longer pointed at a printed object that the site has replaced with in-page text inputs. Four distinct surfaces:
  1. Six prose sentences in day chapters (day-01, day-02, day-03, day-08, day-09, day-12) rewritten to drop the Workbook alternative while preserving the surrounding pedagogical point.
  2. Appendix return-navigation parentheticals of the form `(Return to Workbook page X / Day Y page Z.)` — ~40 instances across `content/appendix/*.qmd` reduced to `(Return to Day Y page Z.)`.
  3. Appendix section-heading cross-references (`## Point 7. … *(Workbook pages 70–71 / Day 5 pages 2–3)*`) reduced to just the Day-chapter half.
  4. `welcome.qmd:111` footnote rewritten to describe the site's in-page text-input model rather than the printed Workbook B1–B4.
- **Where** — See above. One sweep landing across day chapters, appendix, and the front-matter welcome page.
- **Source reference** — Neave's original course materials treat the Workbook as the reader's writing surface and use Workbook page numbers as a parallel reference system alongside Day-chapter page numbers.
- **Why** — The printed Workbook no longer exists as a separate artefact in this delivery; leaving the cross-references in place would send readers looking for something that isn't there. The Day-chapter page numbers carry the full navigation intent on their own.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D1/D2).
- **Landed in** — PR [#214](https://github.com/lddurbin/twelve_days_to_deming/pull/214) (closes #209, #210).
- **Related** — [#213](https://github.com/lddurbin/twelve_days_to_deming/issues/213) tracks the still-pending decision on inline `[WB NNN]` cross-reference suffixes; [#212](https://github.com/lddurbin/twelve_days_to_deming/issues/212) covers the `index.qmd` front-matter Workbook prose still to be addressed.

## 2026-04-21 — Remove the appendix Welcome Workbook passage

- **What** — Remove the standalone Welcome Workbook passage from the appendix, which introduced the printed Workbook as a companion artefact to the course.
- **Where** — `content/appendix/` (the Welcome Workbook appendix entry).
- **Source reference** — NZOQ appendix material introducing the printed Workbook and how to use it alongside the course.
- **Why** — The Workbook is not part of this site's delivery model; the passage exists solely to frame a printed artefact that the site has replaced with in-page interaction. Leaving it in would mislead readers about what the site provides.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D2). Neave's framing is pedagogically significant, so the removal is logged here rather than folded silently into a cleanup PR.
- **Landed in** — *Pending — tracked in [#208](https://github.com/lddurbin/twelve_days_to_deming/issues/208).*

## 2026-04-21 — Remove inline "see Workbook p. N" page-reference call-outs

- **What** — Delete the `.workbook_callout` divs and their inline "see Workbook p. N" page-reference anchors throughout day chapters. Remove the associated CSS class and any manifest fields that validated their presence.
- **Where** — All `content/days/day-*/` chapters that previously carried `.workbook_callout` divs.
- **Source reference** — Neave's original materials include inline cross-references pointing readers at specific pages of the printed Workbook for response-capture (writing answers, notes, reflections).
- **Why** — The site captures reader responses through embedded text inputs and a notes-download feature, so page references to a printed Workbook were dead links in the new delivery model. The class name and manifest field were coupled to the div and removed alongside it.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D1/D3).
- **Landed in** — PRs [#196](https://github.com/lddurbin/twelve_days_to_deming/pull/196), [#197](https://github.com/lddurbin/twelve_days_to_deming/pull/197), [#202](https://github.com/lddurbin/twelve_days_to_deming/pull/202); commits `2198ed3`, `0cba98d`, `1b6ea4a`, `6375e17`.
