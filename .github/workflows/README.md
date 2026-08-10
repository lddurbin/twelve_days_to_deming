# GitHub Actions Deployment Setup

This workflow automatically builds and deploys your Quarto book to your remote server whenever you push to the main branch.

## Setup Instructions

### 1. Add SSH Private Key Secret

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `SSH_PRIVATE_KEY`
5. Value: Copy the entire contents of your `key` file (including the `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----` lines)

### 2. How It Works

The workflow runs as three jobs.

**`test-js`** — runs the JavaScript unit tests.

**`build`** — produces the site, and never touches the server:
1. **Checkout** your repository
2. **Setup R**, Pandoc and Quarto (pinned to 1.10.18)
3. **Install dependencies** using `renv::restore()`
4. **Run** the R unit tests
5. **Build** the Quarto book with `quarto render`
6. **Smoke test** the build output — fails closed before anything can ship
7. **Upload** `_book` as the `site` artifact

**`deploy`** — ships that artifact. Runs only on `main` or a `deploy-*` tag:
1. **Download** the `site` artifact and check it arrived complete
2. **Back up** the current server-side deployment (5 retained)
3. **Deploy** via `rsync --delete`
4. **Verify production** — refetch live URLs and compare them against what was shipped
5. **Tag** the deployment `deploy-YYYYMMDDHHMMSS`
6. **Cleanup** SSH keys for security

Steps 4 and 5 are in that order deliberately: a deploy that fails verification never gets tagged, so every `deploy-*` tag is a known-good rollback target. See [docs/ROLLBACK.md](../../docs/ROLLBACK.md).

### 3. Triggers

- **Automatic**: Every push to the `main` branch
- **Manual**: Use the "workflow_dispatch" trigger in the Actions tab

### 4. Server Details

- **Host**: `ssh.leedurbin.co.nz`
- **Port**: `18765`
- **User**: `u197-gmrgybn3hkn2`
- **Path**: `www/deming.leedurbin.co.nz/public_html/`

### 5. Security Notes

- SSH private key is stored as a GitHub secret
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