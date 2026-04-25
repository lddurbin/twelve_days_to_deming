# pa11y Ignore Rules

`.pa11yci.json` cannot carry inline comments (it is plain JSON). This file records the rationale for each WCAG rule listed in the `ignore` array, so future audits don't need to spelunk through `git log` to understand why a rule was suppressed.

Each entry should record:

- **Rule code** and a one-line description of what HTMLCS checks for.
- **Why suppressed** — typically upstream Quarto emission, framework-level false positive, or scoped-to-a-different-issue.
- **Last verified** — date the suppression was last confirmed still necessary, so stale entries can be re-audited.

If you remove a rule from `.pa11yci.json`, also remove the entry below.

## Active suppressions

### `WCAG2AA.Principle4.Guideline4_1.4_1_2.H91.A.EmptyNoId`

**What it checks.** Anchors must have accessible text; the `H91.A.EmptyNoId` variant fires when a link has no visible text and no `id`.

**Why suppressed.** Quarto's sidebar accordion toggles are anchors that use `aria-label` rather than visible text for their accessible name. pa11y/HTMLCS does not recognise `aria-label` as an accessible-name source for this rule, producing a false positive on a correctly-labelled control.

**Source.** Added in #183 baseline triage (#164).

**Last verified.** 2026-04-25.

### `WCAG2AA.Principle1.Guideline1_1.1_1_1.H37`

**What it checks.** `<img>` elements must have an `alt` attribute.

**Why suppressed.** R/ggplot figures are emitted by Quarto without `alt` text. The substantive fix is long-descriptions on charts, which is scoped to its own work in #159 (Days 2–3) and #160 (remaining days). Suppressing here prevents the pa11y check from blocking unrelated PRs while that audit is in progress; the long-description issues will close out the underlying gap.

**Source.** Added in #183 baseline triage (#164).

**Last verified.** 2026-04-25. Re-audit when #159 and #160 close — the suppression should likely be lifted then.

### `WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2`

**What it checks.** `<form>` elements must contain a submit-style control (`<input type="submit">`, `<button type="submit">`, etc.).

**Why suppressed.** OJS-driven interactive inputs (used across the activity widgets on Days 2, 3, and 6) are reactive controls — they update their bound values on change rather than on form submit. They are not traditional submit-based forms, so the rule does not apply.

**Source.** Added in #183 baseline triage (#164).

**Last verified.** 2026-04-25.

### `WCAG2AA.Principle4.Guideline4_1.4_1_1.F77`

**What it checks.** Element IDs must be unique within a document (the historical "duplicate id" parsing rule).

**Why suppressed.** Quarto's dual-theme configuration emits two `<link>` tags for the active and prefetched stylesheet, sharing `id="quarto-bootstrap"` and `id="quarto-text-highlighting-styles"`, so its built-in `quartoToggleColorScheme` JS can swap between them. The duplicate IDs are intrinsic to the upstream theme-toggle mechanism, not project code. Note that **WCAG 2.2 removed the duplicate-id criterion entirely** (Success Criterion 4.1.1 Parsing), reflecting that modern browsers and assistive technologies tolerate non-unique IDs without harm — so this suppression aligns with the criterion's evolution.

**Source.** Added during #256 review (commit `a3a59a8`).

**Last verified.** 2026-04-25.
