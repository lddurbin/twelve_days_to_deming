# Deployment Rollback Procedure

Every merge to `main` deploys the same build to two hosts. Before doing anything, work out which host is serving the bad version, because each one rolls back differently.

| Host | What it serves | Deployed by | Fastest rollback |
|---|---|---|---|
| **Vercel**, project `twelve-days-to-deming` | `learndeming.org` once #886 launches it. Until then, only `twelve-days-to-deming.vercel.app`, which isn't indexed and has no readers | `vercel-production` job | [Option 1: Instant Rollback](#option-1-vercel-instant-rollback) |
| **SiteGround** | `deming.leedurbin.co.nz`: the public site until #886, then a redirect only (#888) | `deploy` job (rsync) | [Option 3: server-side backup](#option-3-restore-a-siteground-server-side-backup) |

[Option 2](#option-2-rebuild-from-a-deploy--tag) rebuilds from a known-good tag and redeploys to both hosts.

To check which host is answering on a domain, run `curl -sI https://<domain>/ | grep -i '^server'`. Vercel answers `server: Vercel`.

Options 1–3 all restore **files**. That's a complete rollback **only while the site has no database**. Once accounts or saved progress exist, read [Stateful rollback](#stateful-rollback) before using any of them.

## How you find out something is wrong

Each deploy job ends by fetching a handful of real URLs and checking that each one is byte-identical to what was shipped ([scripts/verify-deployment.sh](../scripts/verify-deployment.sh)):

| Step that went red | Job | Host it checked |
|---|---|---|
| **Verify Vercel production** | `vercel-production` | `twelve-days-to-deming.vercel.app` (`learndeming.org` after #886) |
| **Verify production** | `deploy` | `deming.leedurbin.co.nz` |

Read the failure before acting. The script distinguishes two cases:

| Failure | Meaning | Action |
|---|---|---|
| `HTTP <code>` or `content differs from deployed artifact` | The host is serving the wrong thing | Roll back that host: Option 1 for Vercel, Option 3 for SiteGround |
| `not in the deployed artifact` | A checked page was renamed or removed, so the script is out of date | No rollback. Update `PATHS` in the script |

HTTP 202 from SiteGround's proxy warming up after an rsync doesn't turn the run red. It's unrelated to whether the deploy is correct, and it's reported separately.

The `deploy-*` tag is minted by the `deploy` job, and only after SiteGround's verification passes. It says nothing about Vercel. Before treating a tag as known-good for Vercel, check that the same run's `vercel-production` job also passed.

## Option 1: Vercel Instant Rollback

This points production back at an earlier deployment without rebuilding anything. It takes effect within seconds.

**On the Hobby plan, you can only roll back to the deployment immediately before the current one.** That's usually what you want, since the latest deploy is the bad one. If you need to go back further, use Option 2. The team (`lees-projects-5b4a1017`) was on Hobby as of 2026-09-28. Pro can roll back to any earlier production deployment.

### Steps

1. **Roll back.** Using the dashboard is simplest: go to [vercel.com](https://vercel.com), open the **twelve-days-to-deming** project, find the **Production Deployment** tile, click **Instant Rollback**, check which domains it lists, then **Confirm Rollback**.

   Or, from a terminal logged in to Vercel:

   ```bash
   # Newest first. The second row is the deployment to roll back to.
   vercel list twelve-days-to-deming --environment production --scope lees-projects-5b4a1017

   vercel rollback <previous-deployment-url> --scope lees-projects-5b4a1017
   vercel rollback status twelve-days-to-deming --scope lees-projects-5b4a1017
   ```

   Each run's job summary in GitHub Actions also records the deployment URL it created (*Vercel production deployment: https://…*).

2. **Check the site.** See [Verification](#verification) below.

### After rolling back: new merges don't go live

**A rollback switches off automatic promotion.** From then on, every merge to `main` still deploys to Vercel, but the domains stay on the rolled-back deployment. As a result, **Verify Vercel production fails on every run until you end the rollback**, because the alias is serving older bytes than the run just shipped. That's expected, not a new incident.

To end the rollback, merge the fix, let its run deploy, then either:

- in the dashboard, click **Undo Rollback** on the Production Deployment tile and select the fixed deployment, or
- run `vercel promote <fixed-deployment-url> --scope lees-projects-5b4a1017`.

Either one promotes that deployment and switches automatic promotion back on. Then re-run the failed `vercel-production` job so its verification passes against what's actually live.

## Option 2: Rebuild from a `deploy-*` tag

Every deploy that passes SiteGround verification is tagged `deploy-YYYYMMDDHHMMSS`. Dispatching the workflow against a tag rebuilds that version from source and redeploys it to **both** hosts.

**Tags before `deploy-20260927193853` predate the Vercel job.** Dispatching one of those redeploys SiteGround only.

### Steps

1. Find the tag to roll back to:

   ```bash
   git fetch --tags
   git tag --list 'deploy-*' --sort=-creatordate | head -5
   ```

2. Trigger a run from that tag. In the GitHub UI, go to **Actions → Build and Deploy → Run workflow** and select the tag. Or use the CLI:

   ```bash
   gh workflow run deploy.yml --ref deploy-20260927200556  # adjust tag
   ```

3. Watch the run. If Vercel was in a rolled-back state from Option 1, the rebuilt deployment won't go live there by itself. Promote it with `vercel promote` as described in [After rolling back](#after-rolling-back-new-merges-dont-go-live).

4. Check the site. See [Verification](#verification).

## Option 3: Restore a SiteGround server-side backup

This only applies to `deming.leedurbin.co.nz`, and only while the rsync `deploy` job exists (#685 decides its future).

Every rsync deploy first takes a timestamped backup on the server, and the five most recent are kept:

```
www/deming.leedurbin.co.nz/backups/public_html.backup.YYYYMMDDHHMMSS
```

### Steps

1. SSH into the server:

   ```bash
   ssh -p 18765 u197-gmrgybn3hkn2@ssh.leedurbin.co.nz
   ```

2. List available backups (most recent last):

   ```bash
   ls -1d www/deming.leedurbin.co.nz/backups/public_html.backup.* | sort
   ```

3. Swap the current site with the chosen backup:

   ```bash
   DEPLOY=www/deming.leedurbin.co.nz/public_html
   BACKUP=www/deming.leedurbin.co.nz/backups/public_html.backup.20260403120000  # adjust timestamp

   mv "$DEPLOY" "${DEPLOY}.bad"
   cp -r "$BACKUP" "$DEPLOY"
   ```

4. Check the site. See [Verification](#verification).

5. Once confirmed, remove the bad deployment:

   ```bash
   rm -rf "${DEPLOY}.bad"
   ```

## When to use which

| Scenario | Use |
|---|---|
| Vercel is serving a bad deploy, and it's the latest one | Option 1 |
| Vercel needs to go back more than one deploy (Hobby plan) | Option 2 |
| SiteGround is serving a bad deploy | Option 3, which is fastest, or Option 2 |
| Both hosts are bad | Option 2, or Options 1 and 3 together |
| You suspect the build environment, not the code | Option 1 or 3, which avoid a rebuild |
| The SiteGround backup has already been rotated out | Option 2 |

## Verification

After any rollback, on the host you rolled back:

- [ ] The site loads at every domain that host serves (see the table at the top)
- [ ] Interactive elements (funnel experiment, red beads) work
- [ ] The browser developer tools show no console errors
- [ ] Optionally, byte-check against the version you restored. Download that run's `site` artifact (kept for 7 days) and run the script:

  ```bash
  gh run download <run-id> -n site -D /tmp/site
  ./scripts/verify-deployment.sh https://twelve-days-to-deming.vercel.app /tmp/site
  ```

## Stateful rollback

Options 1–3 all rest on the file-restore assumption from the top of this doc. It stops holding the moment there's a database, sessions or server-side reader data. Neither `cp -r` of a docroot nor Vercel's Instant Rollback does anything for a schema, a function's data, or a half-applied migration. Instant Rollback also leaves environment variables and external services exactly as they are now. Running yesterday's code *beside* today's schema can be worse than doing nothing: it produces a site that's making wrong assumptions about the shape of its own data. This section was written before the accounts work landed (see the [accounts epic](https://github.com/lddurbin/twelve_days_to_deming/issues/529)), so the constraint shapes the design instead of being discovered during the first incident.

### Before an Instant Rollback, once a database exists

Answer these in order:

1. **Was the bad change itself a migration?** Then don't roll anything back. Fix forward with a new migration that corrects it (see [Forward-only migrations](#forward-only-migrations)).
2. **Has any migration run since the deployment you'd roll back to?** If not, Option 1 is safe: the code you're restoring was written for the schema that's there.
3. **If a migration has run, are you going back exactly one release?** [Deploy ordering](#deploy-ordering) keeps the schema compatible with the *previous* release for a full deploy cycle, so rolling back one deploy is still safe. That also happens to be the Hobby plan's limit. Going back further than that, past a migration, isn't safe. Fix forward instead.

Option 2 follows the same rule, because a rebuild from an old tag is old code too.

### Forward-only migrations

The default stance is: never roll a schema backwards. If a migration causes a problem, fix forward with a new migration that corrects it, rather than reverting to an earlier schema version.

Reversible-migration discipline, meaning a working and tested `down` for every `up`, is a legitimate approach. But it's ongoing overhead sized for a team and a rate of change this project doesn't have. Forward-only is cheaper and, for a solo project, safer: there's one direction to test, not two, and no migration ever runs against data shaped by a schema version it wasn't written for.

### Deploy ordering

Schema changes deploy before the code that depends on them, and the schema stays backwards-compatible with the *previous* release for at least one full deploy cycle. Concretely: a column or table a new feature needs is added in its own deploy first, and the deploy that starts reading or writing it follows once that's live.

That gap is what keeps code rollback independent of data. If application code needs reverting, Options 1–3 above still work for the code, because the schema they're running against didn't change underneath them. The moment code requires a schema that only the new release provides, code and data stop being independently reversible.

### What's actually reversible

| | Reversible via Options 1–3? |
|---|---|
| Static assets and application code | Yes. This is what those procedures already do |
| A schema or migration | No. See Forward-only migrations above |
| User data (accounts, saved progress, workbook answers) | No |

There is no "restore the database to 10 minutes ago" that doesn't also silently discard every write made in those 10 minutes by every other reader. A bad deploy is a deploy incident. Lost or corrupted reader data is a data incident. They call for different responses, and conflating them (restoring code and calling it done) is exactly the failure this section exists to head off.

### Backups of reader data

Once there is reader data, it needs a backup regime of its own. The SiteGround docroot backup (Option 3) and Vercel's deployment history (Option 1) hold files only, and neither contains a database. At minimum, this means deciding and documenting:

- A retention window for data backups. It doesn't need to match the five-backup docroot retention above.
- Where backups are stored, and that the store is independent of the primary database's own infrastructure.
- A periodic restore test. An untested backup is unverified until the day it's needed. This is the same principle [already applied to deploys](#how-you-find-out-something-is-wrong), extended to data.

The concrete mechanism (which platform, which tool, what cadence) is deferred to the account data-model design note, not decided here. This section only fixes the *policy*: reader data gets backed up and restore-tested, separately from the file-based procedures above.
