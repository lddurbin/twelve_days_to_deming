## 2026-04-21 — Remove inline "see Workbook p. N" page-reference call-outs

- **What** — Delete the `.workbook_callout` divs and their inline "see Workbook p. N" page-reference anchors throughout day chapters. Remove the associated CSS class and any manifest fields that validated their presence.
- **Where** — All `content/days/day-*/` chapters that previously carried `.workbook_callout` divs.
- **Source reference** — Neave's original materials include inline cross-references pointing readers at specific pages of the printed Workbook for response-capture (writing answers, notes, reflections).
- **Why** — The site captures reader responses through embedded text inputs and a notes-download feature, so page references to a printed Workbook were dead links in the new delivery model. The class name and manifest field were coupled to the div and removed alongside it.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D1/D3).
- **Landed in** — PRs [#196](https://github.com/lddurbin/twelve_days_to_deming/pull/196), [#197](https://github.com/lddurbin/twelve_days_to_deming/pull/197), [#202](https://github.com/lddurbin/twelve_days_to_deming/pull/202); commits `2198ed3`, `0cba98d`, `1b6ea4a`, `6375e17`.
