# Changelog

All notable user-facing changes to this project are documented in this file.

New entries are **not** added here directly — see
[`docs/changesets/README.md`](docs/changesets/README.md) for how to add one,
and `scripts/cut-release.sh` for how this file gets its release sections.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-09-12

### Reader Experience
- 15 same-day "page N" mentions in Day 2 (e.g. "the table on page 11, in A Brief Overview", "pages 85–88, starting with 'More on the binomial and normal distributions' in the Optional Extras section") are now clickable links, with 5 new `{#sec-pageN}` anchors added where none existed. One reference — "page 11 of the introductory Welcome section" — turned out to point outside Day 2 entirely, to the "Out-of-hours" work section of `index.qmd` ("A. PLEASE START HERE"), which needed its own new anchor. Genuine references to other books (*Out of the Crisis*, *The Deming Dimension*) were left as plain text. (#673)
- 7 same-day "page N" mentions in Day 4 now link to a real destination, with 3 new `{#sec-pageN}` anchors added where none existed; one "page 3" mention was reclassified from anchor-needed to a genuine external reference (Out of the Crisis) and left as plain text, along with the 12 other confirmed external-book mentions (DemDim, Out of the Crisis, Statistics Tables). (#675)
- 6 same-day/cross-day "page N" mentions in Day 5 now link to a real destination (the Day 5 introduction, Point 11, Point 13, and Day 6's case study and Major Activity), with one range approximated to the nearest existing anchor since no exact-page anchor exists; genuine references to other books (DemDim, Out of the Crisis) were left as plain text, including one row the audit misclassified as needing a new anchor. (#672)
- 5 same-day "page N" mentions in Day 6 (e.g. "the table on page 5 in Activity 6-a", "page 9, in the Winners and Losers section") are now clickable links, with 3 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (*The New Economics*, *Out of the Crisis*) and to the external Francis Inquiry report into Mid-Staffordshire were left as plain text. (#671)
- 10 same-day "page N" mentions in Day 10 (e.g. "Prelude A page 2, in 'Understanding a System'", "pages 20–27, starting with Part B below") are now clickable links. Several point into Balaji Reddie's Preludes in the appendix, which needed 5 new `{#sec-pageN}` anchors authored there; 2 more new anchors were added within Day 10 itself. Genuine references to other books (*DemDim*, *The New Economics*) were left as plain text. (#674)
- Added Neave's recommended session time to Day 8's four New Climate chapters (A New Climate, Joy in Work, Innovation, Cooperation), dictated from the original book's pacing clocks. (#713)

### Infrastructure & Quality
- The pinned `@observablehq/plot@0.6.16` dynamic import behind Day 3's funnel-experiment histograms now enforces Subresource Integrity via an import map, so a compromised or altered CDN response fails closed instead of executing silently. (#712)

### Fixed
- 24 sentences across nine Day 3 chapters now match `F.Day.3.13Jan20.pdf` word-for-word. Most are single-word substitutions, dropped words, or misplaced punctuation, but one is more consequential: a garbled paragraph about baseline length in the "How Do We Compute Control Limits" Technical Aid had a source reference wrong ("Springwater" → "Springboard"), a whole clause missing ("or if you're in a hurry to get started!"), and a nonsensical sentence about the "baseline" term that has now been restored to what the source actually says. (#730) (#731)
- Day 4 pointed readers to the wrong day twice (Day 8's material on creativity and innovation, and Day 8's Major Activity, both mislabelled as Day 9) and sent a same-day page reference to the wrong day entirely, producing a sentence that read "On Day 11 ... look ahead to Day 11". All three now match the source PDF and the page reference is a proper link. (#716) (#726)
- Day 4's "The First Project" chapter now matches its source pages word-for-word — a subject swap had the wrong person describing how Deming's statements evolved over time, and a bullet on further reading had lost roughly a third of its detail to paraphrasing. (#676) (#714)
- 28 more sentences across all four Day 4 chapters now match `G.Day.4.09Jan20.pdf` word-for-word. Most are single-word substitutions or dropped clauses, but two are more consequential: a direct Deming quote had been altered ("you can learn all you can" → "you can learn all you need to know in an hour"), and a biographical claim about Deming's later years in Japan had been rewritten to say something the source doesn't — including flipping "the final ten years of his life" to "the first ten years". (#727) (#728)
- 9 sentences across six Day 9 chapters now match `L.Day.9.15Feb22.pdf` word-for-word. Most are single-word substitutions or small drops, but a few are worth calling out: a word duplicated in the source ("Why did it finish up there there?") had been transcribed as a single "there" and is now correctly doubled, a dropped letter turned "I am" into the nonsensical "If am", and a cross-day reference that pointed preparation work at "Day 5" now correctly points at "Day 6", where the 0–5 relationship scale was actually introduced. (#732) (#733)
- Two Day 9 passages now match `L.Day.9.15Feb22.pdf` word-for-word. The organisation-charts paragraph said Deming's flow diagram invited "innovative comparison" where Neave wrote "immediate comparison!", dropped "on the following page" from the Figure 25 pointer, and lost two closing sentences about the chart being perpendicular to the conventional one; and a cross-reference in the introductions chapter pointed readers at page 18 where the source says page 19, sending anyone who followed the link to the wrong guidance. (#735) (#747)
- Fourteen corrections bring Day 5 into word-for-word agreement with `H.Day.5.08Feb22.pdf`. Two restore lost meaning: Deming's Disease 1 quotation had dropped "to stay in business", and the note on his Attributes of a Leader list had lost the instruction it exists to give — "don't focus on the technology… but on the wisdom" — with the following sentence pulled inside the parenthesis. The rest correct single words the eye skips ("perhaps" for "maybe", "have a look" for "take a look", "those actions" for "action"), restore a dropped pointer to Appendix page 24, put back two emphases the source sets in bold, and fix a line-break hyphen transcribed as a real one in "*DemDim*". (#771) (#774)
- Forty-three corrections bring Day 6 into word-for-word agreement with `I.Day.6.19Feb22.pdf`. Four restore lost meaning: the seminar photo caption had dropped two colleagues' roles and Ed Baker's chairing of the session while splicing in fifty words about Bill Scherkenbach that belong to no caption; the Grade C club story had lost the clause explaining what the grade boundary actually did ("Grades C and above counted toward the school's 'score'"); an inserted "never" had Mack saying he had *not* grown up in a world of competition, the opposite of his point; and a whole paragraph of Neave's advice on Major Activity 6-b was missing, leaving the next paragraph pointing back at an "out-of-hours" note nothing had introduced. The rest correct single words that change the fact stated — the national furniture industry average was 24%, not 33%; the Joiner Triangle learning was 1986, not 1988; the seminars were "downlinks", not "downfalls" — restore Neave's bracketed editorial inserts that had been flattened to parentheses, and put back fifteen emphasis runs visible only in the page images, including the *leap*/*hop* contrast that the two section headings are built on. (#775) (#776)
- Twelve corrections bring Day 7 into word-for-word agreement with `J.Day.7.14Feb22.pdf`. The largest restores a substantially rewritten paragraph: the Major Activity's introduction was missing two whole source paragraphs (a manufacturing analogy and Neave's seminar-stories anecdote), had an invented bulleted list standing in for the source's own sentences, substituted a claim about education for one about American manufacturing, and cited the wrong source in its NB callout ("Appendix page 31" instead of *DemDim* page 10). The rest correct single words that change the fact stated (an Upper Control Limit of 92.4%, not 92.1%; £8,907 booked, not £8,597; "fake" calls, not "false"; "popular" not "populate" demand in a quoted Robert Reich passage), a page range of 128–129 not 128–128, a sentence merge that left a clause with no subject, a duplicated "I nodded again." that flattened a deliberate escalation, and three emphasis runs visible only in the page images. (#778) (#779)
- Fifteen corrections bring Day 11 into word-for-word agreement with `N.Day.11.18Jan20.pdf`, headlined by seven wrong page numbers in Neave's own cross-references to *The New Economics*, *DemDim* and Bill Scherkenbach's second book, plus word substitutions including "mere" read as "more" (near-reversing Deming's point about facts falling short of knowledge) and "Variety is" read as "diversity is" (breaking a deliberate callback to the idiom). Seven underline/italic emphasis runs, invisible to `pdftotext`, are also restored. Two of Neave's own PDF typos ("syppose", "Mazlow's") were already silently corrected on the site at some earlier point and are kept, logged retroactively rather than reverted. (#780) (#781)
- Three corrections bring Day 8 into word-for-word agreement with `K.Day.8.11Jan20.pdf`, headlined by restoring three whole source paragraphs missing from the Major Activity introduction (the "basic version" caveat, the "darkness" phase description, and the second-phase flow-diagram paragraph) and repairing the one paragraph that did survive: a wrong cross-reference (Day 1 page 27 read as page 37), a Deming quotation replaced with nonsense ("transformation of Western style of management" became "This formation of a System was of management"), a fabricated closing sentence with no source at all, two word substitutions, and a dropped numbered list item. The other two fixes restore a deliberate echo ("Mack did what he did because he learned from Dr Deming", mirroring the next sentence) and a dropped clause naming where a table total is recorded. Two of Neave's own PDF typos ("echos", "innovaton") were already silently corrected on the site at some earlier point and are kept, logged retroactively rather than reverted. (#783) (#785)
- Fifteen corrections bring Day 10 into word-for-word agreement with `M.Day.10.16Feb22.pdf`, headlined by a pair of wrong cross-references pointing in opposite directions around the same Scherkenbach "boxes and lines" diagram (one paragraph's "Day 9 page 9" had become "Day 9 page 2"; a separate bare same-day "page 3" reference had been sent to Day 9 instead). Also restores a dropped Deming quote and its attribution clause ("the aim or purpose of the system is subjective..."), a "1990"/"1992" version-year swap, a meaning-reversing "when do"/"when no" typo, a spurious "Chapter 18" inserted where the source has none, and Neave's own "wibble-wobble" callback broken by a substituted phrase, plus several smaller word-level drops and substitutions. (#787) (#788)
- Repairs a dead link and nine smaller departures from Neave's page in the References and Sources appendix, the first time that page has been checked against its own source PDF. The site's link to the *A Prophet Unheard* video playlist has been broken since the page was created — one digit of the YouTube playlist ID was mistranscribed (`PLCADAD0F2F91BD570` for Neave's `PLCADAD3F2F91BD570`), three lines below his own warning that "0 and 1 are digits and O and I are capital letters"; it now resolves again. Also restores Neave's wording in the two cross-references that name the "Internet Contacts and Addresses" section, and matches the source's emphasis in seven places — the five Deming Library volume titles, which Neave sets upright while italicising every other title in that list, and the two *The Deming* Prize entries, where his italics stop one word short. (#804) (#806)
- Fourteen corrections bring Day 1 into word-for-word agreement with `D.Day.1.07Feb22.pdf`, headlined by a whole missing source note — Neave's aside on why he writes "variation" rather than "variability", absent between "bare bones" 1 and 2 — and a missing acknowledgment SPC Press requires, whose undefined footnote marker was printing as a literal `[^f]` on the live page. Two `{#sec-pageN}` anchors turned out to be named for the wrong page, misdirecting six cross-references: "Day 1 page 6" landed on printed p4 from five places in the appendix and Optional Extras (two of which name what they expect to find there), and "Day 1 page 41" landed on the Major Activity rather than the chapter that introduces it; both anchors are renamed, the two real pages given anchors of their own, and every reference repointed. Also restores a *Sunday Times* citation's year and closing bracket ("London, 14 February Tom Peters asked"), a dropped cross-reference parenthetical, a book title broken by a misplaced italic ("from T*he New Economics…*"), a missing full stop, the exclamation mark in "SOME LIGHT RELIEF!", a true ellipsis in a heading, one emphasis run, and three stray `!` characters that are a subset font's space glyph mistaken for punctuation during transcription — none of which any flag could see. (#792) (#794)
- Sixty-six corrections bring Day 9 into word-for-word agreement with `L.Day.9.15Feb22.pdf`. The headline is a ~300-word source passage restored on printed p20 — Neave's "explain it to a friend" suggestion, which he frames as preparation for the final Major Activity on Day 12 — which the site had replaced with two paragraphs that appear nowhere in the source, one of them attributing an invented quotation to a Day 2 page that is about reading a control chart. Day 9's missing "Approvals, Acknowledgments and Information" page (printed p31) is restored in full, carrying the permissions for the Scherkenbach diagram the site reproduces and the two Deming Transformation Forum booklet acknowledgments, and repairing a reference to a page that did not exist. Four of Neave's own bracketed comments — including a reading list and a pointer to the Optional Extras — were printed in Deming-blue, attributing his words to Deming; they are now plain. Also restores a missing closing sentence in Step 1, a dropped clause ("it takes time"), five dropped words ("still", "rather", "own", "if", "as") and a spurious one, a cross-reference pointing at Day 1 page 25 instead of page 35, John's quotation closed a paragraph early, three source section rules, twenty-nine emphasis runs the comparator cannot see by construction, and assorted punctuation the transcription had flattened. (#795) (#800)
- The "Changes from the source" page listed 24 of its 52 entries as not yet shipped — showing "Pending", an unfilled placeholder, or nothing at all — for work that had in fact landed, the oldest of them back in April. Every entry now names the pull request that shipped it, so a reader cross-referencing Neave's PDFs can see when each difference actually took effect. (#777) (#807)

## [0.2.1] - 2026-08-17

### Course Content
- Day 3's Funnel Experiment (Chapter 11) now includes the reference table mapping each dice-score to the marble's displacement, which the surrounding text already pointed to but the transcription had dropped. (#606)
- The site footer now credits course content to Dr Henry R. Neave and any other original writing to its own author(s), instead of a single Neave copyright line covering every page. (#639)
- Day 3's Rules 3 and 4 chapter now includes a new figure comparing Rule 2 and Rule 3 side by side at the first stage where they disagree, making clear that both rules move the funnel by the same distance but measure that distance from different starting points. (#651)

### Accessibility
- The interactive track widget in Day 3's Funnel Experiment (Rules 1–4) now stays full-size and scrolls horizontally on narrow screens instead of shrinking the digits down to a few pixels, and auto-scrolls to keep the funnel and marble in view as each stage advances. (#607)

### Reader Experience
- The reading-time indicator on Day 7's introduction, numerical targets, thirteenth obstacle, and Taguchi reflections sections now also shows Dr Neave's recommended pace, dictated from the original book. (#640)
- Bare "page N" mentions across `content/appendix/` (including Optional Extras and Balaji Reddie's Contributions) are now clickable links to the section they refer to, instead of dead text; confirmed-external book citations (Out of the Crisis, DemDim, Shewhart, Wheeler, Walton) are left as plain prose. (#658)
- 76 previously-unlinked "page N" mentions across Day 3's 13 chapters now link to the section they refer to, with descriptive link text naming the destination; confirmed book references (Out of the Crisis, DemDim, Elementary Statistics Tables) are left as plain prose. (#657)
- The 28 same-day "page N" mentions in Day 9 that pointed to a real destination (e.g. "the diagram on page 3", "the table on page 28") are now clickable links, with 9 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (Shewhart, DemDim, Out of the Crisis, The New Economics) were left as plain text. (#656)
- 9 same-day "page N" mentions in Day 1 that pointed to a real destination (e.g. "Don Wheeler's book mentioned on page 5", "the Deming Prize and the Nashua Corporation... on page 2") are now clickable links, with 2 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (Out of the Crisis, The New Economics, Shewhart's 1931 book, The Deming Prize, Ceil Kilian's biography) were left as plain text. (#660)
- 18 same-day "page N"/"pages N–M" mentions in Day 7 that pointed to a real destination (e.g. "the diagram on page 19", "the further true stories on pages 9–18") are now clickable links, with 5 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (*Out of the Crisis*, *DemDim*, Peter Scholtes's *The Leader's Handbook*, *The New Economics*) were left as plain text. (#659)
- 23 same-day "page N" mentions in Day 8 (including two reclassified from an external-book false-positive) now link to a real destination, with 9 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (DemDim, Out of the Crisis, The New Economics) were left as plain text. (TBD)
- 8 same-day "page N" mentions in Day 11 (e.g. "today's material: pages 4–6", the footnoted page references in the Coda) are now clickable links, with 6 new `{#sec-pageN}` anchors added where none existed; the 44 remaining bare mentions are genuine citations to other books (DemDim, The New Economics, Out of the Crisis, The Essential Deming, Scherkenbach) or to Balaji Reddie's un-anchored "Preludes" appendix, so were left as plain text. (#662)
- The 28 same-day "page N"/"pages N–M" mentions in Day 12 that pointed to a real destination (e.g. "the table on page 4", "Guidance for Staff (pages 14–18)") are now clickable links, with 12 new `{#sec-pageN}` anchors added where none existed; genuine references to other books (*Out of the Crisis*, *DemDim*, *The New Economics*, Peter Scholtes's *The Leader's Handbook*, Balaji Reddie's "Contributions") were left as plain text. (#661)

### Fixed
- Charts C2 and C3 in Day 3's "Six Processes" material now correctly show the Red Beads process going out of statistical control, matching the surrounding reading material. (#604)
- Four "page N" links in the Optional Extras appendix used a bare `#sec-pageN` fragment instead of an explicit file path; one of them (`#sec-page43`) collided with an identical anchor id on a Day 2 page. All four now link explicitly to their own file. (#644)
- Ten same-day "page N" links in Day 1 used a bare `#sec-pageN` fragment instead of an explicit file path; two silently misrouted readers to Day 2 or Day 3, and one pointed at a page anchor that doesn't exist. All ten now link to their correct target with an explicit path. (#642)
- The Rule 3 worked example in Day 3 now shows the correct Stage 4–5 finishing positions (29→31, 28→32) and no longer contains a fabricated closing sentence that belonged to Rule 4, so the text matches the source, the R simulations, and the page's own interactive widget. (#648)

### Visual & Content Polish
- The Rule 3 marble-position lookup table in Day 3's Funnel Experiment (and the Rules 1–4 summary statistics table) now scrolls horizontally within its own container on narrow screens instead of forcing the whole page to overflow. (#609)

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
