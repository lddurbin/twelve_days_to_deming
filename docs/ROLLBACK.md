# Deployment Rollback Procedure

Two rollback strategies are available, depending on the situation.

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
   - Go to **Actions > Build and Deploy (Current) > Run workflow**
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
