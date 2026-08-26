# Adjudications — what a human decided about each flag

`results/` next door records what the *validator* found: counts, thresholds,
the scorer version, all written by `scripts/validate-transcription.sh` itself
so the numbers can't drift from what was actually run. It deliberately holds no
verdicts.

This directory holds the other half — what a person concluded about each of
those flags, and why. One file per day or appendix, named to match:
`day-NN.json`, `appendix-<slug>.json`. See
[#765](https://github.com/lddurbin/twelve_days_to_deming/issues/765), under
epic [#734](https://github.com/lddurbin/twelve_days_to_deming/issues/734).

## Why this exists

#734's completion criteria include *"every day's and appendix's full flag list
is adjudicated: fixed, deviation-logged, or confirmed non-defect"*. Nothing was
recording that. A pass would work through a day's flags, the reasoning would
live in a chat transcript, and six months later the only evidence that a
sentence had been checked at all was that nobody had changed it.

So the record answers, per flag: what the source says, what the site says, what
the verdict is and on what evidence, and what Lee decided. It is the reason a
future reader can tell **"checked, and correct as it stands"** apart from
**"never looked at"** — two states that are otherwise identical in the QMD.

Per-file rather than one shared file, for the same reason
[`docs/changesets/`](../../../docs/changesets/README.md) and
[`docs/deviations/`](../../../docs/deviations/README.md) are: two passes in
flight the same week would otherwise collide on positional edits. Wave 2 is not
serial (see #734), so that is a live concern, not a hypothetical one.

## The review page is generated from this, not the other way round

```
python3 scripts/build-adjudication-page.py workflow/validation/adjudications/day-05.json
```

writes `workflow/validation/adjudication/day-05.html`, which is published as an
Artifact for Lee to work through. **The page is derived and gitignored; this
record is the source of truth.** Nothing about the page's markup is
pass-specific — palette, decision controls, filters and export all live in
`workflow/validation/adjudication/template.html`, so a pass writes data and
never HTML.

Decisions come back as a JSON file the page exports, and are merged into the
`decision` / `decision_note` fields here before the pass's PR is opened. A
record with decisions already in it reopens showing them, so a pass can be
picked up again after an interruption.

## Format

```json
{
  "pass": "day-05",
  "epic": 734,
  "issue": null,
  "source_pdf": "H.Day.5.08Feb22.pdf",
  "scorer_version": "d78c745…",
  "content_dir": "content/days/day-05",
  "export_filename": "day-05-decisions.json",
  "adjudicated_at": "2026-08-27",
  "decided_at": null,
  "report": { "flagged_sentences": 20, "near_certain": 8, "…": 0 },
  "pages_read": [5, 6, 10, 14, 22, 26, 28],
  "page": { "eyebrow": "…", "title": "…", "artifact_title": "…",
            "standfirst_html": "…", "provenance": [{"label": "…", "value": "…"}] },
  "sections": [ { "key": "fix", "kind": "k-fix", "title": "Fix proposed",
                  "count": "12 findings", "note_html": "…",
                  "labels": {"accept": "Apply fix", "reject": "Leave as-is",
                             "discuss": "Discuss"},
                  "items": [ … ] } ]
}
```

`issue` is the pass's own issue once it exists, and `null` before that.

`report` copies the counts from that pass's `results/` file, so the record says
what population it was adjudicating. **`pages_read` lists the source page images
actually opened** — #734 requires a pass to consult them rather than working
from `pdftotext` alone, and an empty list is a visible sign that didn't happen.

`scorer_version` pins which comparator produced the flags. If it no longer
matches `./scripts/check-validation-staleness.sh`, the adjudication was made
against a report the current pipeline would no longer produce, and the flags
need re-deriving before the verdicts can be trusted.

### Sections

Four are conventional, and `kind` picks the card's colour stripe:

| key | kind | what belongs in it |
|---|---|---|
| `fix` | `k-fix` | a real defect, with the exact replacement text |
| `emph` | `k-emph` | emphasis differences — invisible to every automated flag, since `pdftotext` discards italic and bold |
| `clear` | `k-clear` | checked and cleared: comparator artifacts, documented site-wide conventions |
| `scope` | `k-scope` | a genuine difference a per-day pass is the wrong instrument for |

`labels` sets the wording on that section's three decision buttons, because
"Apply fix / Leave as-is" reads wrong on a finding whose verdict is already
*no defect here*.

### Items

| field | notes |
|---|---|
| `id` | `D5-01`, `N-03`, `X-01` — unique across the whole record; the build fails on a duplicate, since two findings sharing an id would silently share one decision |
| `chip`, `chip_class` | short defect class; `crit` / `emph` / `clear` / `""` |
| `file`, `line` | relative to `content_dir`; `null` for a finding with no single home. A file without a line fails the build |
| `page` | where in the source, both PDF page and printed page — they differ by a fixed offset per day, and readers cite the printed one |
| `flag` | provenance: which report section and score this came from, or plainly that it was never flagged |
| `source_html`, `site_html` | the two texts. `<mark class='src'>` for what the source has, `<mark class='gone'>` for what the site says instead. Raw HTML, injected unescaped |
| `proposal` | exact replacement text, shown as code. Omit for a finding with nothing to apply |
| `evidence_html` | why the verdict goes this way. This is the part that has to survive without the conversation around it |
| `decision` | `null` until decided, then `accept` / `reject` / `discuss` |
| `decision_note` | Lee's note, if any |

A finding may be listed separately from one in the same sentence when the two
can be accepted independently — Day 5's `D5-11` and `D5-12` share a sentence and
are split for exactly that reason.
