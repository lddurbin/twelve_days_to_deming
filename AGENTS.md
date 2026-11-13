# AGENTS.md

Guidance for coding agents working in this repository. It records commitments, rationale, and gotchas that the code itself doesn't show; for structure, read the tree, `_quarto.yml`, `renv.lock` and `.github/workflows/`.

## Project Overview

"12 Days to Deming" is an interactive web edition of Henry Neave's course on Dr. W. Edwards Deming's teachings, built as a Quarto book with an R backend. All 12 days are converted from Neave's source PDFs. CSS classes, R helpers, interactive-element templates, accessibility conventions and cross-reference rules are documented in `workflow/PATTERNS.md`.

## Content rules

- **Exact transcription required**: content is a word-for-word copy of Neave's original PDF text. The user always verifies transcription accuracy.
- **Material departures from the source get logged**: add a per-entry file under `docs/deviations/` in the same PR.
- Interactive elements enhance the original pedagogical flow; they never replace it.

## Source material

Neave's source PDFs and their page renders live in `12-Days-to-Deming/` (`PDFs/`, `PNGs/`), which is local-only — not in git, so not available to cloud agents or fresh clones. PNG filenames carry a letter prefix per day: D=Day 1, E=Day 2, … O=Day 12, then P=Appendix, Q=Contributions from Balaji Reddie, R=References and Sources, S=Optional Extras (e.g. `E.Day.2.12Oct21_page_046.png`).

To extract a figure, crop the page PNG iteratively with `magick "source.png" -crop WxH+X+Y "output.png"`, viewing each attempt and adjusting until the figure, its headers and its annotations are complete. Save to `assets/images/day-XX/` with a descriptive name. The pages are ~2550x3300, above the image API's limit for multi-image requests, so downscale copies before viewing many at once.

## Deployment Architecture

- **Production**: `learndeming.org`, served by the Vercel project `twelve-days-to-deming`. DNS is Vercel DNS
- **Old host**: `deming.leedurbin.co.nz` on SiteGround serves only the #888 bridge: a page per page of the site that carries readers' saved answers to the same path on `learndeming.org` (#887), plus an `.htaccess` 301 for everything else. The rsync `deploy` job ships it (`_bridge/`, built by `scripts/build-old-origin-bridge.R`) — never `_book/`
- **Never run `quarto render` concurrently** in one working directory (e.g. two profiles at once). It corrupts output-dir resolution and can write rendered HTML across the source tree instead of into `_book/`.

## URL and Content Policy

The accounts epic ([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)) commits that the current course content stays free permanently. That commitment needs to be a structural rule that future work is checked against, not a remembered intention — the failure mode is gradual, and each individual step toward gating content looks reasonable in isolation. There's also a concrete asset at stake: epic [#497](https://github.com/lddurbin/twelve_days_to_deming/issues/497) put hand-written `pagetitle` and `description` metadata on all 123 pages, and gating or relocating any of those pages discards that investment.

- **Every published path is permanent.** Paths do not move, do not redirect behind auth, and do not change what they serve to an anonymous visitor.
- **The host changed exactly once**, from `deming.leedurbin.co.nz` to `learndeming.org` ([#884](https://github.com/lddurbin/twelve_days_to_deming/issues/884)), and is now permanent. Every path is served unchanged on the new host, and every path on the old host permanently redirects to the same path there — until [#901](https://github.com/lddurbin/twelve_days_to_deming/issues/901) lands, by way of a bridge page that carries readers' saved answers across first (see Deployment Architecture). `leedurbin.co.nz` stays renewed indefinitely, because the redirects only last as long as the old domain does.
- **Gating is additive only.** New paid or member surfaces get new routes. Nothing existing is ever relocated behind a login.
- **Anonymous and crawler views are byte-identical.** Serving a crawler something different from an anonymous reader is cloaking, and risks a manual action against the whole site. Any personalisation happens client-side, after load — never server-side by request signature.
- **Paid content lives in the same Quarto project**, under a distinct path, so it inherits the build, the CSS, the accessibility conventions, and the `workflow/PATTERNS.md` standards rather than forking into a parallel stack.
- **New gated routes need a CI story before they ship.** `.pa11yci.json` enumerates every current page explicitly (no auto-discovery) and `link-check` will 401 on anything gated, so accessibility coverage silently stops at the login wall unless someone deliberately extends it. Today's baseline is full coverage ([#569](https://github.com/lddurbin/twelve_days_to_deming/issues/569)) — don't let a new gated route quietly reopen that gap. Whoever adds the first gated route owns that extension.
- **This GitHub repo itself stays fully public.** GitHub visibility is per-repo, not per-path, so gating cannot be a folder permission on `twelve_days_to_deming` — only the paid content's source files live elsewhere, in a private repo pulled into the build during CI. See [`docs/paid-content-repository-split.md`](docs/paid-content-repository-split.md) for the mechanism and its open questions.

This rule is inert with respect to `structure-check.yml`, which validates `.qmd` files against `workflow/validation/*.yml` manifests, not against this file.

## Merge workflow

GitHub's merge queue is **not available** on `main` — it's a personal-account (non-org) repo, and the "Require merge queue" option is unavailable for that account type regardless of plan. See issue [#385](https://github.com/lddurbin/twelve_days_to_deming/issues/385) for the investigation; closed as won't-fix.

When merging an approved PR, use `--auto` anyway:

```
gh pr merge <pr-number> --auto --squash --delete-branch
```

Without a queue, `--auto` just waits for required checks to pass on the PR's current head and then merges immediately — there is no server-side batching or rebase-against-projected-main. This requires the repo's **"Allow auto-merge" setting to stay enabled**; if it's off, `--auto` fails outright (`enablePullRequestAutoMerge` GraphQL error) instead of falling back to anything.

The required checks are `pa11y`, `claude-review`, `scorer-tests`, `js-tests` and `r-tests`. Each runs on every PR with no `paths` filter, because a path-filtered required check never reports on a PR it skips and would block that PR forever. Unit tests run only on PRs, not again in `deploy.yml`, and `accessibility.yml` doesn't re-run on `push: main`. Under `strict: true`, what merges has already passed them, so a merge renders the book once. See [#858](https://github.com/lddurbin/twelve_days_to_deming/issues/858).

`main`'s branch protection requires status checks to be up to date (`strict: true`), so under concurrent merges each remaining open PR goes `BEHIND` as soon as another merges ahead of it, and needs an explicit branch update before it can merge — a cascade `--auto` does NOT resolve by itself (each PR still needs `gh api -X PUT repos/<owner>/<repo>/pulls/<n>/update-branch`, then a wait for CI, before merging). This rebase/re-CI cost was evaluated and explicitly accepted in #385 as tolerable for a solo project's occasional PR fleets, rather than migrating to an org to unlock a real queue.

The `merge_group` triggers in `.github/workflows/` are inert on this repo — `merge_group` never fires without a queue — but were left in place in case of a future org migration, at which point enabling "Require merge queue" in Settings → Rules → Rulesets is the only remaining step.

## Changelog and releases

`CHANGELOG.md` is not hand-edited. Each user-facing PR adds its own small
entry file to `docs/changesets/` (format documented in
`docs/changesets/README.md`) — additive, so parallel PRs never collide on
the same line the way a single shared changelog file would. This is the
same shape already used for the deviations log (`docs/deviations/`), for
the same reason: see [#384](https://github.com/lddurbin/twelve_days_to_deming/issues/384).

The `ship-it` skill adds this entry as part of shipping a PR — skip it for
internal-only changes (CI, refactors, dependency bumps). That skill is a
personal one and lives at `~/.agents/skills/`, not in this repo: it is
repo-agnostic, and the [agentcanon convention](https://buildermethods.com/agentcanon)
this repo follows keeps one real copy of a skill at the layer it belongs to.
It discovers this convention from `docs/changesets/README.md`, so that file —
not the skill — is what makes the rule binding here. `.agents/skills/` holds
only skills specific to this project. See
[#767](https://github.com/lddurbin/twelve_days_to_deming/issues/767).

Releases are always a reviewed, explicit action: `./scripts/cut-release.sh <version>`
deliberately stops short of committing, tagging, pushing or creating the
GitHub release. *When* to cut one stays a judgment call — the weekly
`release-cadence.yml` workflow only nudges, via a tracking issue, and never
cuts anything itself. See [#608](https://github.com/lddurbin/twelve_days_to_deming/issues/608).
