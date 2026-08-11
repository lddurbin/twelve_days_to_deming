# Changelog

All notable user-facing changes to this project are documented in this file.

New entries are **not** added here directly — see
[`docs/changesets/README.md`](docs/changesets/README.md) for how to add one,
and `scripts/cut-release.sh` for how this file gets its release sections.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-08-11

Retroactive release covering everything merged between v0.1.0 and this tag —
compiled by hand from the merged-PR history since the changeset workflow
didn't exist yet. Every release from here on is assembled from
`docs/changesets/` via `scripts/cut-release.sh` instead.

### Reader Experience
- Reading-time indicator now sources `session_minutes` from Neave's original clock budgets for Days 2–6, with the two-number meaning clarified in the UI (#469, #473, #485, #519, #526, #555)
- Reader inputs (workbook answers) now persist locally across all 12 days via a shared keyed-localStorage module, surviving page reloads (#557, #558, #559, #560, #561, #562, #563)
- Engagement-based feedback prompt and inline chapter-rating widget replace the earlier form-first feedback route (#487, #488, #491, #492, #493, #495, #496)
- Language switcher added to the reading-preferences panel, linking EN ↔ FR editions, hidden until the French edition ships (#406, #409, #427)
- New FAQ page with FAQPage structured data (#576)
- New Concepts Index page with DefinedTermSet markup (#577)
- Privacy page discloses locally-saved workbook answers and analytics (#468, #564)

### SEO & Discoverability
- Site-level description, Open Graph, Twitter card, and favicon metadata (#515)
- Site-level JSON-LD (Course/Person) on the site root (#518)
- Hand-written pagetitle + description metadata for all 123 pages (#520, #522, #523, #524, #525, #527, #528)
- robots.txt explicitly invites AI crawlers; llms.txt generated from chapter descriptions at build time (#516, #573)
- README positioning copy published on-site (#574)

### Accessibility (WCAG 2.1 AA)
- pa11y coverage gap closed ahead of the first gated route shipping (#587)
- Cooperation-table widget pa11y remediation on Day 8 (#292)
- iOS auto-detection of number sequences as phone links disabled (#588)
- MathJax display-math overflow contained on narrow viewports, including non-Safari WKWebView (#589, #596)

### Infrastructure & Quality
- Build and deploy split into separate CI jobs sharing one build artifact (#550)
- Post-deploy production URL verification (#551)
- Deploy SSH key scoped to a dedicated production GitHub Environment (#552)
- Per-PR preview deployments and a persistent staging site, both on Vercel (#553, #554)
- Quarto upgraded to 1.10.18 (#579)
- Nightly external link-rot watch via lychee (#337)
- CI regenerates and fails the build on inter-day cross-reference drift (#306)
- Freeze-cache key now invalidates on R/Lua source changes (#599)

### Analytics & Feedback
- Privacy-respecting analytics via Simple Analytics behind a vendor-agnostic wrapper (#462)
- Notes downloads, commentary reveals, and funnel/cooperation-widget interactions instrumented (#463, #464)
- Engagement ledger (active-time heartbeat) driving the feedback prompt's trigger logic (#487, #488)
- Engagement counters made merge-safe across devices (#565)

### Visual & Content Polish
- Nearly all remaining hand-drawn/PDF-sourced charts across Day 3 and the Optional Extras appendix replaced with dark-mode-safe, R-generated figures — histograms, funnel-track illustrations, six-processes panels, subgroup illustrations, CLT distributions, and the Day 12 radar diagram; see PRs #339–#383 for the full sequence
- Chart gridline weight rebalanced so control limits read as the dominant line (#590)
- `gt` table header-attribute ordering fixed on Red Beads results tables (#595)
- Part F table horizontal overflow on narrow viewports fixed (#601)

### Fixed
- Five Deadly Diseases YouTube link corrected (#420)
- FAQ heading tense corrected — Henry Neave is alive (#578)
- `og:description`/`twitter:description` no longer falls back to book-level text on individual pages (#572)
- MathJax web font blocked by CSP in some browsers (#490)

### Multilingual (French Edition) — groundwork, not yet public
- French build profile, `DEPLOY_FR`-gated deploy step, and stub welcome chapter (#399, #400, #403, #404)
- Prose and UI/ARIA string extraction + reinjection tooling with identity round-trip (#407, #410, #411)
- Glossary corpus, term matcher, and validation/lock tooling for translation review (#418, #417, #431, #432, #434, #435, #437, #438, #439, #440, #441, #442)

### Documentation
- SRI audit findings documented for externally-loaded CDN resources (#598)
- Design notes for the accounts/paid-content epic: data model, cookie/consent position, repository split (#566, #567, #571)
- Free-tier URL freeze and additive-gating rule documented as a structural policy (#568)

## [0.1.0] - 2026-04-27 — Course Complete

First public release. All 12 days of the course are converted from Neave's
source PDFs and live as an interactive Quarto book at
[deming.leedurbin.co.nz](https://deming.leedurbin.co.nz), with full appendix
material, inter-day cross-references, glossary tooltips, WCAG 2.1 AA
accessibility, and structural guardrails in CI.

### Course Content
- All 12 days converted from source PDFs (#61, #119, #125–#130)
- Appendix: References & Sources (#188), Optional Extras (#192), Welcome Booklet (#193), Balaji Reddie contributions (#187), *About this Edition* foreword (#248)
- Inter-day cross-reference policy + per-day rewiring across all 12 days plus appendix (#199, #200, #216–#238, #240, #244)
- Final link-check sweep + dead external URL replacement (#241, #242)

### Accessibility (WCAG 2.1 AA)
- Accessible labels on all OJS form inputs (#62, #89, #171)
- Skip-to-content link (#110), keyboard focus restoration on funnel (#180), ARIA on callouts (#111)
- Non-colour indicators for status and callouts (#97, #163, #266)
- Long descriptions for every chart (#159, #160, #270, #272)
- Heading hierarchy fixes across Days 1–4 (#94)
- Brand-colour contrast lift to AA (#215)
- pa11y-ci CI guard + lang-attribute convention (#183)
- Screen-reader announcements for funnel updates (#177)
- OpenDyslexic font toggle for readers with dyslexia (#174, #176)

### Reader Experience
- Light/dark mode toggle via dual Quarto theme (#256)
- Per-chapter reading-time indicator (#253)
- Glossary tooltips backed by appendix glossary (#262, #263, #267, #269)
- Reading preferences consolidated into a single panel (#258)
- Per-page anchors for Optional Extras Parts D/E/F (#251)
- Foreman reaction textareas for Spaniards' Red Bead data (#254)
- Welcome Booklet as front-matter chapter (#193)

### Infrastructure & Quality
- Build smoke test (#90), pre-deploy backup (#91), pinned tool versions (#95, #103)
- Single deployment workflow (#146), CI/CD permissions hardening (#140)
- Quarto freeze cache in CI (#198)
- Self-hosted fonts to eliminate third-party IP leak (#108)
- Stored-XSS protection on `localStorage` fields (#109)
- Unit tests for funnel JS (#101) and R helpers (#102)
- Transcription validation (#117), structural inventory checker (#118), appendix coverage (#252)
- Structure check enforced in CI; manifest drift now fails the build (#276)

### Polish & Refactors
- CSS callout refactor + colour token consolidation (#131)
- Visually-hidden CSS migration off deprecated `clip` (#181)
- Helper extractions: download buttons (#114), funnel-experiment OJS (#99), R chart functions (#96), R setup chunk (#100)
- Heading and download-button drift sweeps (#272, #273)
- README site-scope reframe (#275)

### Documentation
- pa11y ignore rationales documented (#260)
- Conversion briefs retained as historical record (#144)
- Pattern reference at `workflow/PATTERNS.md`; deviations-from-source log at `docs/deviations-from-source.md`

[Unreleased]: https://github.com/lddurbin/twelve_days_to_deming/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/lddurbin/twelve_days_to_deming/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lddurbin/twelve_days_to_deming/releases/tag/v0.1.0
