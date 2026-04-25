# Glossary audit

This document records the editorial audit conducted under [#261](https://github.com/lddurbin/twelve_days_to_deming/issues/261) to decide which course-defining terms warrant `<dfn>` semantic markup and an entry in the appendix glossary. The original tooltip mechanism was introduced in [#167](https://github.com/lddurbin/twelve_days_to_deming/issues/167) and revised in [#265](https://github.com/lddurbin/twelve_days_to_deming/issues/265): the inline-tooltip layer is gone, but the audit's seven terms are unchanged. The `<dfn>` element is retained at each defining instance as a **screen-reader signal** and as a **link target** from the appendix glossary page at [`content/appendix/glossary.qmd`](../content/appendix/glossary.qmd).

## Why a cap, and why this audit

The audit's audience is **non-linear and returning readers** — someone on Day 7 who's forgotten what "special cause" means a week after Day 3. The appendix glossary is the primary affordance for that audience; the in-prose `<dfn>` markers point back to where the term is first taught. Two costs still apply once `<dfn>` markers are sprinkled across many chapters:

1. **Anchor-namespace pollution.** Every `<dfn id="…">` claims a stable URL slug. Forty marked terms = forty global anchors that have to stay valid forever.
2. **Pedagogical short-circuiting.** A glossary entry that lists every term Neave introduces invites readers to look up rather than read; the smaller the glossary, the more its presence signals "this one is genuinely worth a separate entry".

The cap of **at most ~10** course-defining terms is the discipline. The marginal benefit drops quickly past the most-recurring terms, so the audit's bias is to **reject candidates that don't have a clean defining sentence in Neave's prose** rather than to synthesise from general knowledge or stretch the cap.

## Sourcing rule

Every glossary entry is sourced from Neave's own prose (or a Deming quote that Neave reproduces verbatim). No editorial paraphrase from general knowledge.

If Neave does not give a clean defining sentence anywhere — only describes the term across many paragraphs — the term is **rejected**, not synthesised.

## First-defining-instance rule

Markup is applied at the **first chapter where Neave's prose does the defining work**, not the first chronological mention. Subsequent uses stay plain. The dfn is not placed inside `<span class="deming_quote">` (per the convention in `workflow/PATTERNS.md` § Glossary terms).

The `id` attribute on each `<dfn>` matches the slug used by the appendix glossary, so the appendix can deep-link back to the in-context defining instance.

## Result

**7 terms marked up** (3 from #167, 4 added in this audit). 3 candidates rejected with rationale.

| # | Term | Anchor slug | First defining instance | Source location | Glossary wording |
|---|------|-------------|-------------------------|-----------------|------------------|
| 1 | common cause / common-cause variation | `common-cause` | `content/days/day-01/11-deming-story.qmd` | Day 1 page 32 (line 145) | Variation inherent to the process and the circumstances in which it is being operated — the way it has been designed, built, set up, and operated. Common causes are always there until the process itself is changed. |
| 2 | special cause / special-cause variation | `special-cause` | `content/days/day-01/11-deming-story.qmd` | Day 1 page 32 (line 152) | Additional causes of variation that are not there all the time — one-off happenings or temporary changes that noticeably affect how the process behaves. Shewhart called them "assignable" causes. |
| 3 | PDSA cycle (Plan-Do-Study-Act) | `pdsa-cycle` | `content/days/day-01/11-deming-story.qmd` | Day 1 page 21 (line 47) | An iterative improvement cycle: Plan, Do, Study, Act. Deming preferred "Study" over the simpler "Check" because the third step is where the real learning takes place. He always referred to it as the Shewhart Cycle. |
| 4 | "in statistical control" | `in-statistical-control` | `content/days/day-01/11-deming-story.qmd` | Day 1 page 32 (line 154); Neave's items 5–6 of the Shewhart breakthrough summary | A process exhibiting variation whose nature does not noticeably change — also called "stable" or "predictable". The opposite, "out of statistical control", means the process is being affected by special causes and is unstable and unpredictable. |
| 5 | System of Profound Knowledge | `system-of-profound-knowledge` | `content/days/day-01/11-deming-story.qmd` | Day 1 page 39 (line 504); Peter Scholtes representation paragraph | Deming's attempt to summarise the essence of his whole life's work. It comprises four major parts — Appreciation for a System, Theory of Variation, Theory of Knowledge, and Psychology — whose strength lies in how they interlink and inter-depend. |
| 6 | operational definition | `operational-definition` | `content/days/day-11/04-theory-of-knowledge-operational-definitions.qmd` | Day 11 page 14 (line 21); rhetorical contrast plus Deming quote from *Out of the Crisis* p. 231 | Deming: "An operational definition puts communicable meaning into a concept." It specifies how something is to be observed, measured, counted, or decided — preventing ambiguity and ensuring fitness for purpose. |
| 7 | transformation (Deming-specific sense) | `transformation` | `content/days/day-12/04-but-what-can-i-do.qmd` | Day 12 page 14 (line 14); blockquote of Deming from *The New Economics* Chapter 4 | A discontinuous shift that comes from understanding the System of Profound Knowledge. The individual, transformed, perceives new meaning in events, numbers, and interactions, and applies these principles in every relationship with other people. |

## Rejected candidates

| Term | Decision | Rationale |
|------|----------|-----------|
| Joiner triangle | **Rejected** | Neave introduces the triangle as Joiner Associates' "attempt to summarise some foundations on which they saw the Deming philosophy as being built" (Day 4 ch 1, line 31), but the three corners themselves are conveyed *visually* in the diagram that follows — they are not stated in a single defining sentence. A tooltip would have to enumerate the corners by paraphrase, which crosses the synthesis line. The diagram is on the same page as the first mention, so a reader who needs the definition has it within a glance. |
| funnel experiment | **Rejected** | Day 3 ch 10 (lines 14–24) describes the apparatus and the experiment's history (created by Lloyd Nelson), but the *conceptual takeaway* — that reactive adjustment to common-cause variation makes things worse, i.e. the "tampering" lesson — is taught experientially in the activity itself, not stated in a defining sentence. A tooltip that captured the takeaway would short-circuit the pedagogy; one that captured only the apparatus would be unhelpful. |
| appreciation for a system | **Rejected** | This is Part A of the System of Profound Knowledge and a major concept, but Neave's prose treats the phrase as one Deming uses, references, and develops over many paragraphs (Day 9 ch 1, Day 9 ch 2, Day 10 ch 2). The only tightly defining sentence on the page is Deming's own definition of "system" ("A system is a network of functions or activities…") — which defines *system*, not *appreciation for a system*. A tooltip would have to synthesise. The phrase's meaning is built up across the morning of Day 9, and the chapter title on Day 10 carries the framing weight that a tooltip can't substitute for. |

## Headroom

The cap of ~10 leaves three slots unused. This is deliberate: future audits may find a stronger candidate that warrants displacing one of the seven, but the headroom is **not** a backlog to be filled. Each addition still has to clear the same bar — a clean defining sentence in Neave's prose, at the first chapter that does the defining work.

## Verification

- pa11y CI continues to pass (the appendix glossary page is listed in `.pa11yci.json`; the chapters that host the seven defining instances are either already covered or rely on coverage of nearby chapters).
- One entry summarising the audit is recorded in `docs/deviations-from-source.md`.
- The pattern documentation in `workflow/PATTERNS.md` § Glossary terms is the canonical "how to add a new dfn" reference and now describes the post-#265 markup (`<dfn id="anchor-slug">term</dfn>` plus a glossary entry, no `data-definition`).
