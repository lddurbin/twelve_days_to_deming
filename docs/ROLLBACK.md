# Deployment Rollback Procedure

Two rollback strategies are available, depending on the situation. Both restore the site by restoring files, which is complete and sufficient **only while the site has no database** — see [Stateful rollback](#stateful-rollback) for what changes once accounts or saved progress exist.

## How you find out something is wrong

The deploy workflow's **Verify production** step fetches a handful of real URLs after the rsync and asserts each is byte-identical to what was shipped ([scripts/verify-deployment.sh](../scripts/verify-deployment.sh)). A red run there means the bytes on the server are not the bytes that were deployed, and is the intended trigger for Option 1 below.

That step runs *before* the deployment is tagged, so a failed deploy never produces a `deploy-*` tag. Every tag listed in Option 2 is therefore a release that passed verification.

Read the failure before acting — the step distinguishes two cases:

| Failure | Meaning | Action |
|---|---|---|
| `HTTP <code>` or `content differs from deployed artifact` | The site is serving the wrong thing | Roll back — Option 1 |
| `not in the deployed artifact` | A checked page was renamed or removed, so the script is out of date | No rollback; update `PATHS` in the script |

## Option 1: Restore from server-side backup

Every deployment creates a timestamped backup on the server before rsync overwrites the site. Backups are kept at:

```
www/deming.leedurbin.co.nz/backups/public_html.backup.YYYYMMDDHHMMSS
```

The five most recent backups are retained automatically.

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

4. Verify the site loads correctly in a browser.

5. Once confirmed, remove the bad deployment:

   ```bash
   rm -rf "${DEPLOY}.bad"
   ```

## Option 2: Re-deploy from a tagged commit

Each successful deployment is tagged `deploy-YYYYMMDDHHMMSS`. To rebuild and deploy from a known-good tag:

### Steps

1. Find the tag to roll back to:

   ```bash
   git tag --list 'deploy-*' --sort=-creatordate | head -5
   ```

2. Trigger a workflow run from that tag via the GitHub Actions UI:
   - Go to **Actions > Build and Deploy > Run workflow**
   - Select the tag from the branch/tag dropdown

   Or use the CLI:

   ```bash
   gh workflow run deploy.yml --ref deploy-20260402150000  # adjust tag
   ```

3. Monitor the workflow run and verify the site once it completes.

## When to use which

| Scenario | Recommended option |
|---|---|
| Bad deployment discovered within minutes | Option 1 (fastest) |
| Need to revert to a specific older version | Option 2 (rebuild from source) |
| Server backup has already been rotated out | Option 2 |
| Suspect build environment issue, not code | Option 1 (avoids rebuilding) |

## Verification

After either rollback method, confirm:

- [ ] Site loads at `deming.leedurbin.co.nz`
- [ ] Interactive elements (funnel experiment, red beads) function correctly
- [ ] No console errors in the browser developer tools

## Stateful rollback

Options 1 and 2 above rest on the file-restore assumption from the top of this doc. It stops holding the moment there's a database, sessions, or server-side reader data: `cp -r` of a docroot does nothing for a schema, a Worker/function version, or a half-applied migration. Restoring yesterday's files *beside* today's schema is worse than doing nothing: it produces a running site that's making wrong assumptions about the shape of its own data. Once accounts or saved progress ship, do not reach for Option 1 or Option 2 to undo a bad data-touching deploy — they were never designed to, and this document isn't proposing to extend them to cover it. This section is written ahead of that work landing (see the [accounts epic](https://github.com/lddurbin/twelve_days_to_deming/issues/529)), so the constraint shapes the design instead of being discovered during the first incident.

### Forward-only migrations

The default stance is: never roll a schema backwards. If a migration causes a problem, fix forward with a new migration that corrects it, rather than reverting to an earlier schema version.

Reversible-migration discipline — writing and testing a working `down` for every `up` — is a legitimate approach, but it's ongoing overhead sized for a team and a rate of change this project doesn't have. Forward-only is cheaper and, for a solo project, safer: there's one direction to test, not two, and no migration ever runs against data shaped by a schema version it wasn't written for.

### Deploy ordering

Schema changes deploy before the code that depends on them, and the schema stays backwards-compatible with the *previous* release for at least one full deploy cycle. Concretely: a column or table a new feature needs is added in its own deploy first; the deploy that starts reading or writing it follows once that's live.

That gap is what keeps code rollback independent of data. If application code needs reverting, Option 1 or Option 2 above still work for the code — swap the files or redeploy an older tag — precisely because the schema they're running against didn't change out from under them. The moment code requires a schema that only the new release provides, code and data stop being independently reversible.

### What's actually reversible

| | Reversible via Option 1 / 2? |
|---|---|
| Static assets and application code | Yes, unchanged — this is what those procedures already do |
| A schema or migration | No — see Forward-only migrations above |
| User data (accounts, saved progress, workbook answers) | No |

There is no "restore the database to 10 minutes ago" that doesn't also silently discard every write made in those 10 minutes by every other reader. A bad deploy is a deploy incident; lost or corrupted reader data is a data incident. They call for different responses, and conflating them — restoring files and calling it done — is exactly the failure mode this section exists to head off.

### Backups of reader data

Once there is reader data, it needs a backup regime of its own, separate from the server-side docroot backup Option 1 relies on — that backup is files only and will not contain a database. At minimum, this means deciding and documenting:

- A retention window for data backups (it does not need to match the five-backup docroot retention above).
- Where backups are stored, and that the store is independent of the primary database's own infrastructure.
- A periodic restore test. An untested backup is unverified until the day it's needed — the same principle [already applied to deploys](#how-you-find-out-something-is-wrong), extended to data.

The concrete mechanism (which platform, which tool, what cadence) is deferred to the account data-model design note, not decided here — this section only fixes the *policy*: reader data gets backed up and restore-tested, on a footing separate from the file-based procedures above.
