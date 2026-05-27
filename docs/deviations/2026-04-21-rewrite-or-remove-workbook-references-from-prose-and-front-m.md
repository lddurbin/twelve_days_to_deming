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
