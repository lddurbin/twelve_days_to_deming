# GitHub Actions Deployment Setup

This workflow automatically builds and deploys your Quarto book to your remote server whenever you push to the main branch.

## Setup Instructions

### 1. Add SSH Private Key Secret

1. Go to your GitHub repository
2. Navigate to **Settings** → **Environments** → **production**
3. Under **Environment secrets**, click **Add environment secret**. Not a repository secret: any workflow on any branch can read one of those (#534, #917)
4. Name: `SSH_PRIVATE_KEY`
5. Value: Copy the entire contents of your `key` file (including the `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----` lines)

### 2. How It Works

The workflow runs as three jobs: `build`, `deploy`, and `staging`.

It runs no unit tests. The JS and R suites (`unit-tests.yml`) and the Python
suite (`scorer-tests.yml`) are required checks on every PR, and `main` requires
branches to be up to date before merging, so what lands on `main` has already
passed them. See #858.

**`build`** — produces the site, and never touches the server:
1. **Checkout** your repository
2. **Setup R**, Pandoc and Quarto via the shared [`setup-r-quarto`](../actions/setup-r-quarto/action.yml) action, which declares every toolchain version once
3. **Install dependencies** using `renv::restore()`
4. **Build** the Quarto book with `quarto render`
5. **Smoke test** the build output — fails closed before anything can ship
6. **Verify canonical links** — every sitemap page names itself canonical (#896)
7. **Build the old-origin bridge** — `_bridge/`, a bridge page per page plus an `.htaccess` 301 (#888)
8. **Upload** `_book` as the `site` artifact, and `_bridge` as the `old-origin-bridge` artifact

**`deploy`** — ships the `old-origin-bridge` artifact to `deming.leedurbin.co.nz`, not the site (#888). It stays after #901 replaces the bridge with a permanent 301, shipping just the `.htaccess`, and SiteGround never holds a fallback copy of the site (#685). Runs only on `main`. That includes a rollback, which is a dispatch on `main` with a `deploy_tag` input (see [docs/ROLLBACK.md](../../docs/ROLLBACK.md) Option 2):
1. **Download** the `old-origin-bridge` artifact and check it arrived complete
2. **Back up** the current server-side deployment (5 retained)
3. **Deploy** via `rsync --delete`
4. **Flush** SiteGround's dynamic cache (`site-tools-client`), so no stale page outlives the deploy
5. **Verify production** — refetch bridge pages and compare them against what was shipped, then check the 301s and that plain URLs aren't served from SiteGround's cache (`scripts/verify-old-origin.sh`)
6. **Tag** the deployment `deploy-YYYYMMDDHHMMSS`
7. **Cleanup** SSH keys for security

Steps 5 and 6 are in that order deliberately: a deploy that fails verification never gets tagged, so every `deploy-*` tag is a known-good rollback target. See [docs/ROLLBACK.md](../../docs/ROLLBACK.md).

**`vercel-production`**: ships the same artifact to the production Vercel project (`twelve-days-to-deming`), beside `deploy` and with the same triggers. It serves `learndeming.org`, the canonical origin since #886, and it sends `X-Robots-Tag: noindex` on every host except `learndeming.org`. After deploying, it runs the same `verify-deployment.sh` byte-for-byte check against `learndeming.org` (#683). One run at a time, so an overlapping deploy can't move the alias mid-check. It needs a team-scoped `VERCEL_TOKEN` secret on the `production` environment. See #680.

### 3. Triggers

- **Automatic**: Every push to the `main` branch
- **Manual**: Use the "workflow_dispatch" trigger in the Actions tab. On a branch other than `main`, only `build` runs. On `main` with `deploy_tag` set, it's a rollback

### 4. Server Details

- **Host**: `ssh.leedurbin.co.nz`
- **Port**: `18765`
- **User**: `u197-gmrgybn3hkn2`
- **Path**: `www/deming.leedurbin.co.nz/public_html/`

### 5. Security Notes

- SSH private key is stored as a secret on the `production` environment
- The `production` and `staging` environments only accept runs on `main` (#917). A workflow on any other branch that names either one fails before its first step, so pushing a branch never gets anyone the deploy credentials. `preview` stays open to every branch, because PR previews need it
- **Accepted residual (#917):** the `preview` environment's `VERCEL_TOKEN` is team-scoped, like the staging and production ones, because Vercel can't scope a token to one project. So it can deploy to the production project too, and any branch can reach it. Treat it as a production credential: rotate it whenever you'd rotate the production token
- Key is only available during workflow execution
- Key is automatically cleaned up after deployment
- Your local `key` file is gitignored for security

### 6. Troubleshooting

If the workflow fails:
1. Check the Actions tab for detailed error logs
2. Verify your SSH private key secret is correctly set
3. Ensure your server is accessible
4. Check that the target directory exists on your server

### 7. Local Development

For local development, you can still use:
```bash
./upload.sh
```

The GitHub Action replaces this functionality for automated deployments. 