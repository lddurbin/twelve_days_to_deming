# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"12 Days to Deming" is an interactive educational course based on Dr. W. Edwards Deming's teachings, built as a Quarto book with R backend. The project converts traditional PDF-based course materials into an interactive web experience with embedded activities, timing indicators, and modern web features.

## Development Commands

### Core Commands
- **Build the book**: `quarto render`
- **Preview during development**: `quarto preview` 
- **Clean build artifacts**: `rm -rf _book/`

### R Environment
- **Restore R dependencies**: `Rscript -e 'renv::restore()'`
- **Check environment status**: `Rscript -e 'renv::status()'`
- **Install new packages**: Use renv workflow - `Rscript -e 'renv::install("package_name"); renv::snapshot()'`

### Deployment
- **Manual deploy**: Handled via GitHub Actions on push to main
- **Force rebuild**: Use GitHub Actions workflow dispatch

## Architecture Overview

### Core Structure
- **Quarto Configuration**: `_quarto.yml` defines the book structure, theme, and build settings
- **Content Organization**: `/content/days/` contains structured course material organized by day
- **R Environment**: Uses `renv` for reproducible package management with `renv.lock`
- **Assets**: `/assets/` contains CSS, JavaScript, images, and templates

### Content Architecture
- **Modular Design**: Each day is broken into multiple `.qmd` files for specific topics/activities
- **Progressive Structure**: 12 days of content, with days 1-2 fully interactive, remaining days in development
- **Active Learning**: Embedded activities, exercises, and interactive elements throughout

### Key Components
- **Interactive Elements**: Custom JavaScript in `/assets/scripts/functions.js` handles user interactions like note downloading
- **Styling**: Custom CSS in `/assets/styles/main.css` with Cosmo theme base
- **R Integration**: R scripts in `/R/` handle data analysis, visualizations, and statistical content
- **Build Scripts**: `/scripts/` contains the PDF-to-PNG converter; obsolete tools are in `/scripts/archive/`

### Data Flow
1. **Source**: `.qmd` files with embedded R code and interactive elements
2. **Processing**: Quarto renders through R/knitr with renv environment
3. **Output**: Static HTML site in `/_book/` directory
4. **Deploy**: GitHub Actions automates build and deployment to production server

## Development Workflow

### Local Development
1. Ensure R and Quarto are installed
2. Use `renv::restore()` to set up R environment
3. Use `quarto preview` for live development
4. Make changes to `.qmd` files in `/content/days/`
5. Build with `quarto render` before committing

### Content Structure Guidelines
- Follow existing naming patterns: `day-XX/##-topic-name.qmd`
- **Exact transcription required**: Provide word-for-word copy of original content from PDF sources
- Interactive elements should enhance, not replace, original pedagogical flow
- Use consistent timing indicators and activity formatting
- User will always verify transcription accuracy

### Key Dependencies
- **Quarto**: Document publishing system
- **R 4.4.0+**: Statistical computing environment  
- **renv**: R package dependency management
- **Core R packages**: DiagrammeR, ggplot2, dplyr, knitr, rmarkdown
- **System dependencies**: pandoc, various system libraries for R package compilation

## Image Extraction Workflow

### Cropping Figures from PDF Sources
When extracting tables, charts, photos, or other figures from original PDF materials in `12-Days-to-Deming/PNGs/`:

1. **Identify Source**: Find the correct PNG file (e.g., `E.Day.2.12Oct21_page_046.png`)
2. **Check Image Dimensions**: Use `magick identify filename.png` to understand scale
3. **Iterative Cropping Process**:
   - Start with approximate coordinates: `magick "source.png" -crop WIDTHxHEIGHT+X+Y "output.png"`
   - View result with `Read` tool
   - Adjust boundaries incrementally until perfect
4. **Target Directory**: Save cropped images to `assets/images/day-XX/`
5. **Naming Convention**: Use descriptive names (e.g., `postscript-table.png`, `control-chart-example.png`)

**Key Tips**:
- PDF conversions are high-resolution (typically 2550x3300+), so coordinates need scaling
- Extend boundaries slightly in all directions to capture complete elements
- Include all relevant headers, labels, and annotations
- Stop cropping just before unwanted text or elements
- Test multiple coordinate adjustments to get precise boundaries

### Usage in Quarto
Reference cropped images in `.qmd` files:
```markdown
![Description](/assets/images/day-XX/filename.png)
```

## Deployment Architecture

- **GitHub Actions**: `.github/workflows/deploy.yml` handles automated builds
- **Production**: Deploys to `deming.leedurbin.co.nz`
- **Build Environment**: Ubuntu with R, Quarto, and system dependencies
- **Deploy Method**: rsync over SSH to production server

## URL and Content Policy

The accounts epic ([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)) commits that the current course content stays free permanently. That commitment needs to be a structural rule that future work is checked against, not a remembered intention — the failure mode is gradual, and each individual step toward gating content looks reasonable in isolation. There's also a concrete asset at stake: epic [#497](https://github.com/lddurbin/twelve_days_to_deming/issues/497) put hand-written `pagetitle` and `description` metadata on all 123 pages, and gating or relocating any of those pages discards that investment.

- **The current 123 URLs are permanent.** They do not move, do not redirect behind auth, and do not change what they serve to an anonymous visitor.
- **Gating is additive only.** New paid or member surfaces get new routes. Nothing existing is ever relocated behind a login.
- **Anonymous and crawler views are byte-identical.** Serving a crawler something different from an anonymous reader is cloaking, and risks a manual action against the whole site. Any personalisation happens client-side, after load — never server-side by request signature.
- **Paid content lives in the same Quarto project**, under a distinct path, so it inherits the build, the CSS, the accessibility conventions, and the `workflow/PATTERNS.md` standards rather than forking into a parallel stack.
- **New gated routes need a CI story before they ship.** `.pa11yci.json` enumerates every current page explicitly (no auto-discovery) and `link-check` will 401 on anything gated, so accessibility coverage silently stops at the login wall unless someone deliberately extends it. This used to be an existing ~60-page backlog gap too (#569 closed it), so today's baseline is full coverage — don't let a new gated route quietly reopen the gap it took a dedicated pass to close. Whoever adds the first gated route owns that extension.
- **This GitHub repo itself stays fully public.** GitHub visibility is per-repo, not per-path, so gating cannot be a folder permission on `twelve_days_to_deming` — only the paid content's source files live elsewhere, in a private repo pulled into the build during CI. See [`docs/paid-content-repository-split.md`](docs/paid-content-repository-split.md) for the mechanism and its open questions.

This rule is inert with respect to `structure-check.yml`, which validates `.qmd` files against `workflow/validation/*.yml` manifests, not against this file.

## Merge workflow

GitHub's merge queue is **not available** on `main` — it's a personal-account (non-org) repo, and the "Require merge queue" option is unavailable for that account type regardless of plan. See issue [#385](https://github.com/lddurbin/twelve_days_to_deming/issues/385) for the investigation; closed as won't-fix.

When merging an approved PR, use `--auto` anyway:

```
gh pr merge <pr-number> --auto --squash --delete-branch
```

Without a queue, `--auto` just waits for required checks to pass on the PR's current head and then merges immediately — there is no server-side batching or rebase-against-projected-main. This requires the repo's **"Allow auto-merge" setting to stay enabled**; if it's off, `--auto` fails outright (`enablePullRequestAutoMerge` GraphQL error) instead of falling back to anything.

`main`'s branch protection requires status checks to be up to date (`strict: true`), so under concurrent merges each remaining open PR goes `BEHIND` as soon as another merges ahead of it, and needs an explicit branch update before it can merge — a cascade `--auto` does NOT resolve by itself (each PR still needs `gh api -X PUT repos/<owner>/<repo>/pulls/<n>/update-branch`, then a wait for CI, before merging). This rebase/re-CI cost was evaluated and explicitly accepted in #385 as tolerable for a solo project's occasional PR fleets, rather than migrating to an org to unlock a real queue.

The four workflows that were wired for `merge_group` triggers (`accessibility`, `claude-code-review`, `interday-audit`, `structure-check`) are inert on this repo — `merge_group` never fires without a queue — but were left in place in case of a future org migration, at which point enabling "Require merge queue" in Settings → Rules → Rulesets is the only remaining step.

## Changelog and releases

`CHANGELOG.md` is not hand-edited. Each user-facing PR adds its own small
entry file to `docs/changesets/` (format documented in
`docs/changesets/README.md`) — additive, so parallel PRs never collide on
the same line the way a single shared changelog file would. This is the
same shape already used for the deviations log (`docs/deviations/`), for
the same reason: see [#384](https://github.com/lddurbin/twelve_days_to_deming/issues/384).

The `ship-it` skill adds this entry as part of shipping a PR — skip it for
internal-only changes (CI, refactors, dependency bumps). When it's time to
cut a release, `./scripts/cut-release.sh <version>` rolls up every pending
entry into a new `CHANGELOG.md` section and stages the consumed entry files
for removal; it deliberately stops short of committing, tagging, pushing, or
calling `gh release create` itself, so a release is always a reviewed,
explicit action rather than something that happens as a side effect of a
script run.

The project's only release before this workflow existed is
[`v0.1.0`](https://github.com/lddurbin/twelve_days_to_deming/releases/tag/v0.1.0)
(2026-04-27, "Course Complete"), cut by hand from a manually assembled PR
list. `CHANGELOG.md` is seeded with that release's notes as a baseline.

There's deliberately no automated trigger for *when* to cut a release —
that stays a judgment call. What there is instead is a nudge:
`.github/workflows/release-cadence.yml` runs weekly (same slot as
`link-check`) and opens/updates a tracking issue titled
`[release-cadence] docs/changesets/ ready for a release cut` once pending
entries in `docs/changesets/` cross 5 files or the oldest entry is 14+
days old. It's read-only — it never runs `cut-release.sh` or touches
`CHANGELOG.md` — and it closes that issue automatically on a later run
once the count/age drops back under threshold (i.e. once someone cuts a
release). See [#608](https://github.com/lddurbin/twelve_days_to_deming/issues/608).
