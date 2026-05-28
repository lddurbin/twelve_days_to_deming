# Multilingual architecture decision

> Status: **accepted** · Spike for issue [#320](https://github.com/lddurbin/twelve_days_to_deming/issues/320) · Scaffolding is tracked separately by [#321](https://github.com/lddurbin/twelve_days_to_deming/issues/321).

## Context

The web edition is currently English-only: `lang: en` in [_quarto.yml](../_quarto.yml#L1), one chapter list, one render, one rsync of `_book/` to `deming.leedurbin.co.nz/public_html/`. The French edition (milestone *French Edition (EN→FR)*, issues #320–#336) needs to coexist with the English source, share assets and R/JS helpers where possible, and ship from the same CI pipeline.

Quarto has no first-class "multilingual book" mode. The book project type assumes one chapter list, one language, one output directory per render. Anything multilingual is built on top of project-level **profiles** and chosen directory conventions. This spike picks the convention before #321 starts moving files.

## Constraints specific to this repo

- **Single deploy target.** [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) does one `rsync -avz --delete _book/` to a single `public_html`. Any layout that produces two separate `_book/` trees has to merge them in CI before that step, or the deploy contract has to change.
- **Smoke test gates the deploy.** The same workflow asserts `_book/index.html` exists, that ≥10 HTML files were produced, and that every `content/days/day-XX/*.html` is present. The FR layout will need a parallel set of assertions or a refactored gate.
- **Frozen R outputs (two cache layers).** At the CI layer, [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) caches the whole `_freeze/` directory under a key built from `renv.lock` + the commit SHA, with restore-key fallbacks. Inside `_freeze/`, Quarto stores one subdirectory per source `.qmd` (e.g. `_freeze/content/days/day-01/01-overture/`) and hashes the chunk inputs to decide whether to re-execute. The two layers are independent: a CI cache miss costs a full freeze rebuild; a Quarto per-file miss costs one chunk. Whatever layout we pick has to behave well at both layers — and in particular, FR sources at distinct paths get distinct Quarto freeze entries, which is a constraint, not a feature, for cross-language reuse.
- **Cross-references.** Quarto resolves `@sec-…`, `@fig-…`, `@tbl-…` within a project. Inter-day links currently sit in [workflow/inter-day-refs.csv](inter-day-refs.csv) and are written as relative paths in `.qmd`. The FR layout must keep IDs stable so EN→FR translation doesn't break the link graph.
- **R helpers leak English strings.** `labs(y = "Loss")` at [R/functions/main-functions.R:1776](../R/functions/main-functions.R#L1776) and similar are user-facing. Issue [#324](https://github.com/lddurbin/twelve_days_to_deming/issues/324) tracks extracting these into a translatable resource; the architecture decision here just has to not preclude that.
- **Deviations log and switcher.** [docs/deviations/](../docs/deviations/) is currently per-PR-entry; the FR build needs its own surface, or the existing surface needs a `lang:` field. The switcher (#322) needs to map EN page → FR page deterministically; that's much easier when the URL paths are isomorphic.

## Options evaluated

### Option A — Quarto profiles over a mirrored `content/` tree *(chosen)*

EN sources stay where they are. FR sources live in a mirrored tree:

```
content/days/day-01/01-overture.qmd          (EN)
content-fr/days/day-01/01-overture.qmd       (FR, identical filenames)
```

…and analogously for top-level chapters (`welcome.qmd` ↔ `welcome.fr.qmd` or a top-level `fr/welcome.qmd`) and appendices.

Two profiles in the project config:

- **default profile** — current `_quarto.yml`, `lang: en`, output to `_book/`.
- **`fr` profile** (`_quarto-fr.yml`) — `lang: fr`, chapter list pointed at `content-fr/...`, `output-dir: _book/fr`.

CI runs `quarto render` then `quarto render --profile fr`, producing the merged `_book/{,fr/}` tree, and the existing single rsync ships the lot. The site lives at `/` (EN) and `/fr/` (FR).

**Pros**
- Sticks to a documented Quarto feature; no custom build orchestration beyond a second `render` line.
- Mirrored paths make the EN↔FR mapping trivial for the extract/reinject pipeline (#323), the segment-alignment tooling (#331), the switcher (#322), and pa11y parity (#334) — given any EN URL, the FR URL is `s|^/|/fr/|`.
- Frozen R outputs naturally split because each `.qmd` is a distinct file at a distinct path; FR sources get their own `_freeze/content-fr/...` entries with no extra cache keying needed. The first FR-enabled CI run executes every FR chunk (no shared cache with EN, even for byte-identical chunks — Quarto keys per source path); subsequent runs reuse FR frozen outputs the same way EN already does.
- Cross-reference IDs (`@sec-…`, etc.) can be kept identical in EN and FR sources, so the inter-day reference graph survives translation without rewriting `inter-day-refs.csv`.
- Branch model unchanged; PRs touch EN and FR side by side, making cross-edition reviews and the deviations log straightforward.

**Cons**
- Doubles the number of `.qmd` files in the repo (~85 EN files → ~170 with FR). File-explorer overhead is real but manageable; the mirror is regular.
- Top-level English files (`index.qmd`, `welcome.qmd`, `about-this-edition.qmd`, `accessibility.qmd`, `changes-from-source.qmd`) need a parallel set under the FR profile. The cleanest expression is to move them under `content/` and `content-fr/` too, or to keep them at the root and use `.fr.qmd` siblings; either is straightforward but is a decision for #321.
- Two `quarto render` invocations roughly double the build wall time on the first FR-enabled CI run. At steady state the cost is bounded to whichever language's chunks actually changed since the previous render, because `_freeze/` persists across runs (GitHub Actions cache) and Quarto skips unchanged chunks per source path.

### Option B — Standalone `fr/` sub-project

`fr/` at the repo root is its own Quarto book project, with its own `_quarto.yml`, its own `_book/`, its own (or shared via `..`) R helpers and assets.

**Pros**
- Each project is internally simple — no profile machinery, no overrides.
- Profile-shy editors can reason about one project at a time.

**Cons**
- Two `_quarto.yml`s drift. Theme, header-includes, CSP, filters, accessibility scripts already live in [_quarto.yml](../_quarto.yml#L190-L226); keeping both copies in sync by hand is a maintenance tax we'd pay forever, and the worst failures (CSP drift, missing reading-prefs script) are silent at build time.
- Asset paths get awkward. Either FR re-references `../assets/…` (works in source but generated HTML paths and CSP `default-src 'self'` need careful sanity-checking), or assets get duplicated.
- CI has to render two projects and explicitly stitch their `_book/` outputs before the existing rsync.
- The switcher and pa11y parity work (#322, #334) gain no advantage over Option A, because URL isomorphism is just as easy to enforce.

### Option C — Long-lived `fr` branch

`main` carries EN; an `fr` branch carries the French edition.

**Pros**
- Zero changes to `main`'s layout. Editors working on EN never see FR files in their tree.

**Cons**
- The single maintainer (Lee) is doing both editions. A branch model only helps when a separate translation team owns FR — here it just creates a constant cherry-pick / rebase obligation. Every editorial improvement to EN ([docs/deviations/](../docs/deviations/) lists how often these land) would need re-application on `fr`, with diff drift each time.
- Deploys collapse: either two sites (`deming.leedurbin.co.nz` + a sibling for FR) or a manual merge dance on every deploy. Both are worse than rendering both languages from one tree.
- Pipeline work in #323–#332 (extract → translate → reinject) becomes much more painful when EN source and FR target live on different branches. Tooling has to checkout both, write to one, and the round-trip identity test (#323) crosses a branch boundary.
- Kills the switcher (#322) — there's no single deploy that can serve both editions from one origin without already-merged trees.

## Decision

**Adopt Option A: Quarto profiles over a mirrored `content-fr/` tree, with EN at `/` and FR at `/fr/` on the same deploy.**

The decisive factors are:

1. **Pipeline shape (#323–#336).** The EN↔FR pipeline issues are written assuming a deterministic per-segment mapping. Mirrored paths give that for free; the branch option destroys it; the sub-project option keeps it but adds drift surface.
2. **Single rsync stays.** The deploy contract is the one piece of infrastructure that's actively load-bearing in production — keeping it untouched means the FR rollout is reversible. (Profiles drop back to EN-only by removing the second `render` line. Branch model can't roll back without re-architecting the deploy.)
3. **Asset and theme reuse.** One `_quarto.yml` base (with profile overrides) means the CSP, the reading-prefs script, the lightbox config, and the accessibility filter are defined once and applied to both editions. Drift can't happen because there's only one source.
4. **Build cost is bounded.** Two renders, one cache, ~2x wall time worst case; near-EN-only steady state because `_freeze` saves the R-heavy chapters. Branch and sub-project options pay the same render cost and don't recoup it elsewhere.

## What this commits us to (and what it doesn't)

**This decision specifies:**

- **Where FR sources live:** in a `content-fr/` tree that mirrors `content/` symmetrically, plus `.fr.qmd` siblings for top-level chapters at the project root (e.g. `welcome.fr.qmd` next to `welcome.qmd`, `index.fr.qmd` next to `index.qmd`, and analogously for `about-this-edition`, `accessibility`, and `changes-from-source`). The mirrored `content-fr/` name gives the translation pipeline (#323, #331) a trivial `s|^content/|content-fr/|` path mapping and the switcher (#322) URL isomorphism for free (`s|^/|/fr/|`). The `.fr.qmd`-siblings convention for top-level chapters keeps the existing `content/` tree and every existing chapter-list reference in `_quarto.yml` untouched, avoids redirect bookkeeping for already-published EN URLs, and leaves the project root browsable as a single index of "what's at the top" for both editions.
- **How the build targets them:** a second `_quarto-fr.yml` profile activated by `quarto render --profile fr`, with `lang: fr`, an FR-specific chapter list, and `output-dir: _book/fr`. The base `_quarto.yml` continues to drive the default EN render.
- **What ships:** one `_book/` tree containing `_book/index.html` (EN root) and `_book/fr/index.html` (FR root). The existing rsync ships both. The deploy smoke test grows a parallel set of assertions for `_book/fr/content/days/day-XX/*.html`.

**This decision does not specify** — these belong to #321 and downstream tickets:

- Switcher UI (#322).
- The extract/reinject toolchain (#323).
- Glossary, MT/LLM adapters, alignment, parity (#326–#334).
- Whether `R/` helpers gain a `lang` argument or load strings from an external table (#324).

## Open questions to revisit during #321

- **R helpers with embedded labels.** Once #324 starts, the cleanest pattern is for `R/functions/*.R` to accept a language argument or read from a per-locale table. Until #324 lands, FR chapters may need to override individual `labs(...)` calls in-line. That's tolerable for the scaffold step.
- **Frozen-output reuse across languages.** Quarto keys frozen outputs by source path, so an FR `.qmd` carrying a chunk byte-identical to its EN sibling re-executes on the first FR render and is then cached separately. If build time becomes a problem, the right move is to push shared computation into `R/` helpers (preferred, and already half-done) so each `.qmd` is a thin call site; symlinking `_freeze` paths is theoretically possible but fragile and not worth attempting until measured.
- **Deviations log.** Whether `docs/deviations/` gains a `lang:` field or whether we keep a separate `docs/deviations-fr/`. Recommend the former for searchability, but it's a #321 detail.
