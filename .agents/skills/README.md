# Project skills

Skills specific to *this* project live here. `.claude/skills` is a symlink to
this directory, so Claude Code finds the same single copy —
the [agentcanon convention](https://buildermethods.com/agentcanon), which this
repo follows along with `CLAUDE.md → AGENTS.md`.

## What belongs here, and what doesn't

A skill belongs here when it can only make sense inside this repo: it names our
issues, our scripts, our content, our source PDFs. `wave-2-pass` is the shape of
it — it cannot run anywhere else, and changes to it should be reviewed alongside
the work it governs.

A skill that would work unchanged in any repo — commit, push, open a PR, sync a
branch — belongs at the personal layer, `~/.agents/skills/`. `ship-it`,
`merge-pr` and `sync-main` used to be duplicated in both places, and the two
copies drifted in opposite directions; which one a bare invocation resolved to
was not predictable, and it bit us twice
([#605](https://github.com/lddurbin/twelve_days_to_deming/issues/605),
[#767](https://github.com/lddurbin/twelve_days_to_deming/issues/767)). agentcanon
is silent on precedence, but its principle is one real copy — so the fix is to
not have two, rather than to work out which wins.

**Consequence worth knowing:** those workflow skills are no longer reviewed
through this repo's PRs. Where a convention has to bind regardless of who runs
what, it is written down in the repo and the skill merely discovers it — the
changeset rule lives in [`docs/changesets/README.md`](../../docs/changesets/README.md),
and `ship-it` reads it from there rather than carrying its own copy.
