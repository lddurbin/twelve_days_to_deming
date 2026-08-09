# Repository split for gated/paid content

_Last updated: 2026-08-09_

Design note for [#570](https://github.com/lddurbin/twelve_days_to_deming/issues/570), part of the accounts epic ([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)). No code — there's no paid content to gate yet, so nothing here is wired into CI. This is the shape decided before that work starts, not an implementation.

## The constraint

GitHub repo visibility is per-repo, not per-path. There's no setting that makes one folder private while `twelve_days_to_deming` stays public. Gating "some of the code" has to mean keeping the gated material out of this repo, not restricting access to part of it.

## The decision

**This repo stays fully public** — the Quarto build, CSS/JS, R scripts, and eventually the auth/gating logic itself. None of that is what needs protecting; the paid course prose is. **A second, private repo holds only the paid content's source files**, pulled into the build during CI. This is the standard open-core shape: the tooling is the open-source project, the proprietary content is a private dependency of it.

## 1. Pull mechanism

**Recommendation: a plain CI checkout step, not a git submodule.**

A submodule embeds a reference to the private repo — its `.gitmodules` entry and pointer commits — permanently into this repo's public git history. That reveals the private repo's name and location to anyone who clones this repo, even though its *contents* stay inaccessible without credentials. It's not a real vulnerability (repo existence isn't sensitive, only contents are), but it's an unforced information leak, and it complicates plain `git clone` for external contributors unless `.gitmodules` is carefully configured to never auto-fetch.

A CI-only clone step avoids both problems: nothing about the private repo is recorded in this repo's git objects. Taken further, the private repo's clone URL should itself be a secret (e.g. `PAID_CONTENT_REPO_URL`) rather than hardcoded in the public `deploy.yml` — so the workflow file reveals only that gated content exists (already a public fact per #549), not which repo holds it.

Target layout: a `content-paid/` directory at the project root, parallel to `content/days/` and `content-fr/`, populated by CI before `quarto render` runs.

## 2. Credential scoping

**A read-only deploy key, scoped to the one private repo** — not a personal access token scoped more broadly across the account or org. A leaked deploy key exposes one repo; a leaked broad-scope PAT exposes everything the token's owner can reach. Store it as a GitHub Actions secret following the same Environment-scoping pattern already established for `SSH_PRIVATE_KEY` (closed under this epic's Phase 1 deploy-credentials work) rather than a repo-level secret.

## 3. Local dev without access

Contributors without access to the private repo won't have `content-paid/` populated, and the free-tier build must not fail because of that.

This is flagged as a real open question, not a solved one: Quarto book projects typically require every chapter listed in `_quarto.yml`'s `chapters:` to exist, or the render fails outright. A static chapter list won't tolerate an absent directory. The implementation issue will likely need a pre-render step that builds the paid-content chapter list dynamically — only including `content-paid/*.qmd` in the nav when the directory is non-empty — rather than declaring it statically. Worth sizing before committing to the `content-paid/` shape at all.

## 4. `.gitignore` discipline

`content-paid/` (or whatever it ends up named) must be gitignored in this repo from the moment CI starts populating it locally-during-build, so a maintainer's local checkout — or an incautious `git add -A` — can never commit paid prose into public history. Cheap to add, expensive to skip.

## 5. PR preview behaviour

GitHub Actions withholds repo secrets from workflow runs triggered by fork pull requests. That means an external contributor's preview build (per #535) correctly won't have `content-paid/` populated — it renders the free tier only, with no extra work required. That part is safe by default.

**What isn't safe by default:** same-repo branches and maintainer PRs *do* get secrets, so their previews will include paid content — rendered to a `noindex` preview URL. `noindex` stops search engines, not a person with the link. If the gating/auth middleware isn't applied inside preview builds the same way it's applied in production, every preview URL becomes an unauthenticated leak of paid content, which defeats the entire point of this repo split. **The gating logic must run in preview deployments too, not just production** — this is the one place the design intent could be silently undone by an implementation shortcut, so it's called out explicitly for whoever picks up the auth/gating build.

## 6. What this note does not decide

Whether paid content stays `.qmd`-authored, matching the free content's existing editorial workflow, or moves to a different authoring surface (a headless CMS, for instance) is a separate, later decision. This note assumes a private git repo of `.qmd` files because it requires the least new tooling and reuses everything #497's and #529's work already established — not because the format has been chosen as final. If paid material ends up needing something Quarto-unfriendly (video hosting, a different interaction model), revisit the mechanism, not just the content.

## Using this note

Before scoping the implementation issue: confirm the `_quarto.yml` dynamic-chapter-list question (§3) can actually be solved cleanly, since it's the one item here that could invalidate the `content-paid/`-directory shape rather than just needing configuration. Everything else (§1, §2, §4, §5) is a matter of following the pattern, not a risk to the approach itself.
