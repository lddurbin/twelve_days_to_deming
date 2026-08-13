# Where should the blog live? — spike outcome

**Issue:** [#628](https://github.com/lddurbin/twelve_days_to_deming/issues/628)
**Status:** Recommendation. No production code ships from this document.
**Date:** 2026-08-13
**Quarto version tested:** 1.10.18 (the version pinned in `deploy.yml` and `accessibility.yml`)

---

## Question zero: what is the blog for?

**Essays on Deming's ideas** — original writing that sits alongside Neave's
transcribed text. Decided by the repo owner when commissioning this spike,
not inferred here.

This is the answer that most constrains the outcome, for three reasons:

1. **Essays are long-lived.** They accrue SEO value over years, which argues
   hard against anything that splits domain authority or parks content
   outside the repo.
2. **Essays want the course's authoring affordances.** An essay about
   variation wants a control chart; an essay about tampering wants the funnel
   simulation. Those are R chunks and OJS cells that only exist inside this
   Quarto project.
3. **Essays raise an authorship problem the other candidate purposes don't.**
   Release notes are obviously the maintainer's voice. Essays sitting near
   Neave's text are not obviously anyone's voice, and this project has been
   deliberate about that boundary. See [Constraint 9](#9-authorship-separation-the-real-cost-of-option-a).

The two purposes explicitly **not** adopted:

- **Course news / release notes** — already served by `docs/changesets/` →
  `CHANGELOG.md` (#384). Building a second surface for this would duplicate a
  solved problem.
- **Build-in-public diary** — belongs on [leedurbin.co.nz](https://leedurbin.co.nz),
  not the course domain.

If either is wanted later, both fit the recommended structure without
rework — but neither should shape the decision now.

---

## Recommendation

> **Option A — essays live inside the existing book project, as a final
> `part:` in `_quarto-en.yml`'s `chapters:` list, with a Quarto `listing:`
> page as the part's entry point.**
>
> **Plus one prerequisite that is worth doing regardless of the blog:**
> generate `.pa11yci.json`'s URL list from the chapter list instead of
> hand-maintaining it.

The issue framed Option A as the cheap-but-lossy choice: "no listing page,
no RSS, no post dates". **That premise is wrong**, and testing it is the
main thing this spike contributes. Quarto's listing engine is not gated on
`project: type: website`. It runs in book projects and produces the full
feature set.

### What was actually tested

A minimal book project was built under Quarto 1.10.18 mirroring this repo's
relevant config (`type: book`, `sidebar.collapse-level: 1`,
`number-sections: false`, `site-url` set), with a `listing:` page and two
posts. Results:

| Capability | Works in a book project? | Evidence |
|---|---|---|
| Listing page with post cards | **Yes** | `quarto-listing` container, `list.min.js` + `quarto-listing.js` loaded |
| Sort by date descending | **Yes** | `data-listing-date-sort` attributes emitted, order correct |
| Post dates | **Yes** | `Aug 10, 2026` / `Aug 1, 2026` rendered in card metadata |
| Categories + clickable filtering | **Yes** | `quarto-listing-category` sidebar with per-category counts |
| Reading time | **Yes** | `listing-reading-time` field populated |
| Descriptions | **Yes** | From each post's `description:` front matter |
| **RSS feed** | **Yes** | Valid RSS 2.0 at `blog.xml` — `<item>`, `<dc:creator>`, `<category>`, `<pubDate>`, full content |
| `<link rel="alternate">` autodiscovery | **Yes** | Emitted into `<head>` |

The one defect found — book chapter numbers leaking into feed titles
(`<title>4  Variation Is Not Noise</title>`) — **is already neutralised by
this repo's existing `number-sections: false`**
([`_quarto.yml:252`](../_quarto.yml#L252)). Re-rendering with that setting
produced clean titles, a clean `<h1>`, and no `chapter-number` spans anywhere.

Two caveats found during testing. The second is minor; **the first is the
sharpest ergonomic cost of this recommendation** and needs an explicit
mitigation.

- **Every post must be listed as a chapter in `_quarto-en.yml`, by hand.**
  In a book project only enumerated chapters get rendered, and only rendered
  pages become listing candidates. Two things were tested here:

  - **Globs are rejected outright.** `chapters: [essays/*.qmd]` fails the
    build with `ERROR: Book chapter 'essays/*.qmd' not found`. There is no
    drop-a-file-in-a-folder workflow available.
  - **A post that exists on disk but isn't listed is dropped *silently*.**
    Tested with two essays where only one was a chapter: the render
    succeeded with **no error and no warning**, and the unlisted post was
    absent from the rendered output, the listing page, *and* the feed. The
    `WARN: The listing ... doesn't match any files or folders` message only
    appears when the listing directory resolves to nothing at all — it does
    **not** fire for individual orphaned posts.

  So the realistic failure mode is: write an essay, forget the config edit,
  get a green build, and publish nothing. That is a trap rather than a
  papercut, and it should not be left to author discipline.

  **Mitigation, and it is nearly free:** the Phase 0 pa11y generator
  ([Constraint 2](#2-accessibility-ci--the-treadmill-and-how-it-ends))
  already has to parse `_quarto-en.yml` and flatten the chapter list. The
  same script can assert that every `.qmd` under the essays directory
  appears in that list, turning the silent drop into a CI failure. This is
  folded into follow-up issue #1 below rather than tracked separately.

- **`feed: true` requires `site-url`.** Already set at
  [`_quarto.yml:50`](../_quarto.yml#L50).

---

## How Option A lands against each of the issue's constraints

### 1. URL policy — additive only

Satisfied. Every current URL is a rendered chapter path and none move. Essays
add new paths under a new directory. No redirects, no relocation, nothing
served differently to anonymous readers or crawlers. The blog is not gated,
so the gated-route CI clause doesn't bind — but its *reasoning* does, and
Constraint 2 is this spike's answer to it.

### 2. Accessibility CI — the treadmill, and how it ends

This was correctly identified as the most important thing to solve. The
finding is better than expected.

`.pa11yci.json` was compared against the flattened chapter list from
`_quarto-en.yml`:

```
chapters (incl. appendices): 126
pa11y urls:                  127

in chapters but not in pa11y: 0
in pa11y but not a chapter:   1  → share-your-experience.html?submitted=1
```

**The pa11y URL list is exactly the chapter list, plus one deliberate
query-string variant.** Zero drift today, and a completely mechanical
derivation.

That turns the treadmill into a small script. `R/functions/llms-txt.R`
already contains `.llms_txt_flatten_paths()`, which resolves one level of
`part:` nesting into a flat, ordered vector of chapter paths — precisely the
transformation needed. A `scripts/generate-pa11y-urls.R` reusing that
function, plus a short hand-maintained extras list for the query-string case,
regenerates `.pa11yci.json` from the single source of truth.

Because essays are chapters under Option A, **every new post is enumerated
automatically**. The treadmill never starts.

The same script should also carry the **orphan check** described in the
caveat above: assert that every `.qmd` under the essays directory appears in
`_quarto-en.yml`. The parsing work is already done by then, and it closes the
one silent failure mode Option A introduces. Note this check is specific to
the essays directory — it must *not* be generalised to the whole repo, since
`content-fr/` and the FR profile legitimately hold `.qmd` files outside the
EN chapter list.

This is worth doing on its own merits, independent of whether any essay is
ever written: today's zero drift is luck plus discipline, not a guarantee,
and #569 spent a dedicated pass closing a ~60-page gap. Do this first, as
Phase 0.

### 3. `llms.txt` — automatic, correctly grouped, free

`.llms_txt_chapter_blocks()` emits one `## <part title>` block per `part:`
in document order, and collapses `book$appendices` into a single `## Optional`
section.

So essays as a **final part in `chapters:`** get their own `## Essays`
heading, populated from each post's own `pagetitle`/`description` — no
generator change whatsoever.

This is also the reason **essays must not go in `appendices:`**: they would
be filed under "Optional", which llmstxt.org reserves for skippable material.
That is the wrong signal to send an answer engine about original essays.

### 4. SEO metadata and the og:description fix

- Per-post `pagetitle`/`description` discipline carries over unchanged from
  #497. The listing page needs its own pair.
- **`scripts/fix-og-description.R` needs no evaluation at all under Option A**,
  because the project stays `type: book` — the exact shape the fix was
  written for. Under Option B this would have been an open question requiring
  its own verification pass; Option A deletes the question.
- **One sitemap.** The book emits a single `_book/sitemap.xml` covering every
  chapter, and [`robots.txt:1`](../robots.txt#L1) already declares exactly
  that URL. Essays enter it automatically.

### 5. Deploy — `rsync --delete`

Satisfied without structural change: essays render into `_book/` in the same
pass as everything else, so the single existing rsync ships them.

One small addition: `deploy.yml`'s smoke test loops `content/days/day-*/` and
asserts HTML exists per day. It should gain an equivalent assertion for the
essays directory and for the generated feed XML, so a listing that silently
stops emitting posts fails the build rather than quietly deploying an empty
page.

### 6. Never render concurrently — a decisive advantage

Option A keeps **one render target**. `quarto preview` shows the listing
page, the feed link and every post exactly as production will serve them.
Authors need no new workflow and the #514 concurrency rule is untouched.

This is the sharpest practical difference between A and B, and it was
verified rather than assumed — see [Option B](#b-a-second-quarto-project-typewebsite-rendering-into-_bookblog) below.

### 7. `structure-check.yml`

**Automatically exempt, no change needed.** The workflow iterates
`seq 1 12` for days and globs `workflow/validation/appendix-*-manifest.yml`
for appendices. An essays directory matches neither, so posts are not
validated against any manifest.

That is the right outcome: manifests encode *fidelity to Neave's source
PDFs*, and essays have no source to be faithful to. Recommend leaving them
exempt explicitly, and noting why in the manifest README so it reads as a
decision rather than an oversight.

### 8. The FR edition — EN-only, and automatically so

`_quarto-fr.yml` overrides `book.chapters` **wholesale** (it lists exactly
two files). Quarto profile merging replaces arrays rather than concatenating
them, so essays added to `_quarto-en.yml` cannot leak into an FR build.

**Position: essays are EN-only.** This is a real decision, not a deferral,
and it needs no enforcement mechanism — the config shape already guarantees
it. If FR essays are ever wanted, they get their own part in `_quarto-fr.yml`.
A `DEPLOY_FR` flip at launch cannot ship a half-configured blog.

### 9. Authorship separation — the real cost of Option A

**This is the strongest argument against the recommendation and it must be
answered before any essay ships.**

[`_quarto.yml:63-67`](../_quarto.yml#L63-L67) sets a **global** `page-footer`:

> Course content © Dr Henry R. Neave. Reproduced with permission (May 2026).

On an essay page — the maintainer's own writing, not Neave's — that footer
is not merely redundant, it misattributes authorship. Given that this edition
exists under Neave's explicit personal permission, and that the project has
been careful to keep commentary distinct from transcription, shipping essays
under a blanket Neave copyright line would be a genuine error.

`book.page-footer` is a book-level key with no per-page override in Quarto
1.10.18. So this needs a deliberate fix, and it is the one piece of real
design work Option A requires. Three candidate approaches, in rough order of
preference:

1. **Reword the global footer** so it attributes course content to Neave and
   original commentary to the web edition's author, correctly on all 126
   existing pages *and* on essays.
2. **A per-post authorship callout** at the top of each essay, using the same
   convention as any existing editorial-note styling in
   `workflow/PATTERNS.md`.
3. A post-render rewrite of the footer on essay pages — technically possible
   given the existing post-render script infrastructure, but adds a moving
   part for a problem option 1 solves in config.

Options 1 and 2 are complementary and should probably both happen.

### 10. PR previews

Free and unchanged. `accessibility.yml`'s `build` job runs plain
`quarto render` and uploads `_book` as one artifact; both pa11y and the
Vercel preview consume it. Essays are in that artifact by construction.

### 11. Link checking

**Free and automatic.** `link-check.yml` scans `./**/*.qmd` source directly
rather than rendered HTML, so external links in essays are covered by the
weekly link-rot watch the moment a post file exists.

### 12. Changesets

**Recommendation: publishing an essay does not warrant a
`docs/changesets/` entry.**

`docs/changesets/README.md` scopes entries to "anything a reader or
contributor of the live site would notice: new content, new features, fixes
to visible bugs". An essay is arguably new content — but the RSS feed *is*
the publication channel for essays, and duplicating each post into release
notes would make `CHANGELOG.md` mostly a list of blog posts, drowning the
software changes it exists to communicate.

Do add a changeset for the **infrastructure**: the listing page, the feed,
and the pa11y generator each land once and are exactly the kind of change a
reader would notice.

Similarly, `docs/deviations/` does **not** apply — essays depart from nothing,
because they are not transcriptions.

---

## Options considered and discarded

### B. A second Quarto project (`type: website`) rendering into `_book/blog/`

**Discarded.** This was the issue's presumed front-runner. Testing showed its
costs are real and its benefits are now nil, since Option A delivers listings
and RSS anyway.

The issue described the FR edition as "direct prior art" for this. **It isn't**,
and the correction matters: `_quarto-fr.yml` is a *profile overlay* on the same
project — it inherits `project: type: book` and overrides only `lang`,
`output-dir` and the chapter list. This repo has **one Quarto project rendered
twice**, not two projects. A blog under Option B would be the repo's first
genuinely second project, with no prior art to lean on.

Verified costs:

- **The output-dir wipe is real.** Rendering the child into `../_book/blog`
  worked; re-rendering the parent then **deleted `_book/blog/` entirely**.
  The FR ordering note is accurate and would apply here — but FR is gated
  behind `DEPLOY_FR` and rarely rendered locally, whereas a blog would be
  rendered constantly. Under the #514 no-concurrent-render rule, previewing a
  post means a strict serial two-render dance, and any plain `quarto preview`
  silently destroys the blog output.
- **No config inheritance.** A child project with no `theme:` produced a
  different Bootstrap bundle hash from the parent — it inherits nothing.
- **Sharing is partial at best.** `metadata-files: [../_shared-format.yml]`
  *does* work — a marker injected via a shared file appeared in child output.
  But `metadata-files` merges document metadata, not `project:` keys. The
  `resources:`, `pre-render:` and `post-render:` blocks — and the ~180-line
  `header-includes` carrying CSP, analytics gating, the staging banner, the
  skip link and eight script tags — would need duplicating or restructuring.
  Every one of those is load-bearing and separately commented.
- **A second sitemap, invisible to crawlers.** The child emitted its own
  `_book/blog/sitemap.xml`, unreferenced by `_book/sitemap.xml`.
  `robots.txt` declares only the root one, so the blog's sitemap would need
  a `robots.txt` change to be discovered at all.
- **`fix-og-description.R` unverified on website projects.** It fixes a
  Quarto bug specific to book projects; whether it is correct, a no-op, or
  harmful elsewhere would need its own investigation.

Paying all of that to obtain features Option A already provides is not a
trade worth making.

### C. A separate project on its own host or subdomain

**Discarded on the strength of question zero.** #531 proved Vercel
artifact-only deploys work, so this is *feasible* — but essays exist partly to
build the course's search and answer-engine authority, and a subdomain splits
that authority at exactly the wrong moment. It also means a second deploy
pipeline, a second a11y story, a second SEO metadata regime, and a reader
journey that leaves the course.

Everything it offers over Option A is isolation, which is not a problem this
project has.

### D. An external platform (Substack, Ghost, …)

**Discarded, most decisively of the four.** Near-zero build cost, but for
*essays on Deming's ideas* it gives up the things that would make them worth
reading:

- No R, no OJS, no control charts, no funnel simulation — an essay on
  variation loses its central affordance.
- Content leaves the repo, so it is outside version control, PR review,
  link-checking and the deviations/changeset discipline.
- Styling and accessibility fall outside `workflow/PATTERNS.md` and pa11y
  entirely, on a site whose accessibility posture is a stated feature with
  its own public page.
- SEO value accrues to someone else's domain.

Viable only if the goal were reach-with-minimum-effort. It isn't.

---

## Suggested follow-up issues

Sized from the findings above. Phase 0 is independent of the blog and should
land first.

| # | Phase | Issue | Size | Notes |
|---|---|---|---|---|
| 1 | 0 | Generate `.pa11yci.json` URL list from `_quarto-en.yml`, **plus an orphan check** | **S–M** | Reuse `.llms_txt_flatten_paths()`; hand-maintained extras list for `?submitted=1`; CI check that the committed file matches regeneration. Verified zero drift today, so this lands green. Also assert no `.qmd` under the essays directory is missing from the chapter list — scoped to that directory only, not repo-wide (`content-fr/` is legitimately outside it). |
| 2 | 0 | Fix global `page-footer` authorship attribution | **S** | Constraint 9. Blocks the first essay. Benefits all 126 existing pages. |
| 3 | 1 | Add the Essays part, listing page, and directory scaffold | **M** | Final part in `chapters:` (not `appendices:`); `listing:` with `feed: true`; `pagetitle`/`description` on the listing page. |
| 4 | 1 | Authoring conventions for essays | **S** | Front-matter contract (`title`, `pagetitle`, `description`, `date`, `categories`, `author`); authorship callout convention; note in `workflow/PATTERNS.md`. **Must document the `_quarto-en.yml` edit as a required publishing step** — authors used to dropping a file in a folder will otherwise hit the silent-drop failure above. |
| 5 | 1 | Document structure-check exemption | **XS** | Record in the manifest README that essays are deliberately unvalidated, and why. |
| 6 | 2 | Deploy smoke-test assertions for essays + feed | **S** | Mirror the existing per-day assertion loop; assert the feed XML is non-empty. |
| 7 | 2 | Changeset for the blog infrastructure | **XS** | Per Constraint 12 — the infrastructure gets an entry, individual posts don't. |

Two smaller decisions to fold into #3 rather than track separately:

- **Reading time is computed twice, and the fix is card-only.**
  `filters/reading-time.lua` is a project-level filter
  ([`_quarto.yml:69-71`](../_quarto.yml#L69-L71)), so it runs on every
  rendered document — essays included — injecting an estimate under the
  page's `<h1>`. Quarto's listing separately computes `listing-reading-time`
  for the card. Both use ~200 wpm but are independent implementations and may
  disagree. **Fix: drop `reading-time` from the listing `fields:` only.** The
  per-page estimate under the `<h1>` stays, and is wanted — it is the same
  affordance every course chapter already offers. The listing page itself
  won't gain a spurious estimate, since the filter's `MIN_WORDS = 50`
  threshold suppresses output on prose-light pages.
- **Category filtering is client-side only.** Quarto's category chips filter
  the listing in-page; there are no per-category URLs. Acceptable, and it
  keeps the URL surface small — but worth knowing before anyone expects
  `/essays/category/variation.html` to exist.

## When to revisit

Option A's one genuinely unbounded cost is the sidebar. Testing confirmed
`collapse-level: 1` keeps the Essays part **collapsed on every page outside
it** and expands it only when the reader is inside — so the cost to the
12-day spine is exactly one collapsed line, no matter how many essays exist.

That holds comfortably for tens of essays. At somewhere around 50+, the
expanded list becomes unwieldy and essays' presence in the book's linear
`prev`/`next` chain starts to feel wrong. If that day comes, Option B is
still available and nothing in this recommendation forecloses it — the posts
are already `.qmd` files with listing-compatible front matter, so the
migration is a config change plus a redirect story, not a rewrite.
