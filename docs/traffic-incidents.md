# Traffic incidents

What to do when `learndeming.org` is slow, down, or burning through its allowance because of **traffic**, not because of a deploy ([#912](https://github.com/lddurbin/twelve_days_to_deming/issues/912), part of [#910](https://github.com/lddurbin/twelve_days_to_deming/issues/910)). For a bad deploy, use [ROLLBACK.md](ROLLBACK.md) instead.

To tell them apart: if the trouble started right after a merge to `main`, and the newest **Build and Deploy** run's verify step is red, it's a deploy. If the site serves the right bytes but slowly, or the Usage page is climbing faster than readers explain, it's traffic.

## Before you start

Most commands below need a recent Vercel CLI and a directory linked to the project. The global install may be too old (54.20 has no `firewall traffic`, `attack-mode` or `metrics`), so use `npx vercel@latest`. The repo root has no Vercel link of its own, so link a throwaway directory, as [firewall.md](firewall.md) does:

```sh
cd "$(mktemp -d)"
vc() { npx -y vercel@latest "$@" --scope=lees-projects-5b4a1017; }
vc link --yes --project twelve-days-to-deming
```

The rest of this page uses that `vc` function.

## Where to look

- **The Usage page** (vercel.com → the `lees-projects-5b4a1017` team → **Usage**): Fast Data Transfer and CDN Requests against the Hobby allowance. The allowance belongs to the **team**, which hosts another production project as well, so check which project the usage is coming from.
- **The Firewall tab** of the `twelve-days-to-deming` project: traffic by action, with top IPs, JA4 fingerprints and user agents.
- **From the CLI**, the last day at a glance, including whether Attack Mode is on:

  ```sh
  vc firewall overview
  ```

  Then the busiest clients, as described in [firewall.md's Reading the logs](firewall.md#reading-the-logs):

  ```sh
  vc firewall traffic list --top 20 --dimension ip --dimension user-agent --dimension rule
  vc firewall traffic inspect ip <address>
  ```

  Without Observability Plus, which Hobby can't buy, these only reach back about 24 hours.

## What Hobby allows, and what a pause looks like

From [Vercel's Hobby plan page](https://vercel.com/docs/plans/hobby), as of November 2026, the team gets each month:

| Allowance | Included |
| --- | --- |
| Fast Data Transfer | 100 GB |
| CDN Requests (formerly Edge Requests) | 1,000,000 |
| Rate-limited requests (see [firewall.md](firewall.md#what-hobby-allows)) | 1,000,000 |

Hobby can't be billed for overage. Instead, in Vercel's words, "if you exceed your usage limits on the Hobby plan, you will have to wait until 30 days have passed before you can use the feature again." For serving the site, that means production is paused. Every visitor gets a **503** with the error code `DEPLOYMENT_PAUSED` ([Vercel KB](https://vercel.com/kb/guide/why-is-my-account-deployment-blocked)), which is easy to confirm:

```sh
curl -sI https://learndeming.org/ | head -5
```

The docs promise no warning email before this happens. That's why the [usage watch](#usage-watch) below exists.

**What lifts it:** waiting out the 30 days, or upgrading the team to Pro, which bills the overage instead. There's no warm copy of the site anywhere else to switch to. The old host only serves the bridge, which forwards readers to `learndeming.org` (see [ROLLBACK.md Option 3](ROLLBACK.md#option-3-restore-a-siteground-server-side-backup)). So if the site is paused and can't wait 30 days, upgrading is the only fast fix.

## Attack Mode

Attack Mode makes every **browser** visitor pass a challenge page before the site loads. Known bots get through without a challenge, including search engine crawlers like Googlebot and the webhook providers in Vercel's bot directory ([Vercel docs](https://vercel.com/docs/vercel-firewall/attack-mode)). Requests it blocks don't count toward the usage allowance. It's free on every plan, including Hobby.

**Use it for an active incident only, never as a standing setting.** While it's on:

- every reader sees a challenge page before the site loads;
- clients that can't run the challenge, such as curl, feed readers and link checkers, may be blocked. That includes the deploy job's **Verify Vercel production** step, so a merge during an incident goes red even when the deploy is fine;
- unknown crawlers, like the AI crawlers `robots.txt` invites, may be shut out.

Turn it on for the shortest window that covers the incident. It switches itself off at the end of the window, so a forgotten toggle can't become a standing setting:

```sh
vc firewall attack-mode enable --duration 1h   # or 6h, 24h
vc firewall attack-mode disable
```

Both take effect immediately, with no publish step. **A person has to run them, in an interactive terminal.** The CLI refuses `enable` from a script or an agent (`dangerous_operation_requires_user`), so this isn't something to hand to Claude mid-incident. In the dashboard it's under the project's **Firewall → Bot Management → Attack Mode**.

`vc firewall overview` shows `Attack Mode  On` or `Off`. Check it's `Off` once the incident is over.

## Blocking one source

When one address, or one range, is causing the trouble:

```sh
vc firewall ip-blocks block 203.0.113.7       # or a CIDR range, e.g. 203.0.113.0/24
vc firewall diff                              # read it
vc firewall publish --yes
```

Like every firewall change except Attack Mode, `block` only stages a draft. Nothing changes until `publish`. `vc firewall discard --yes` drops the draft instead. To lift a block later:

```sh
vc firewall ip-blocks list
vc firewall ip-blocks unblock <id-or-ip>
vc firewall publish --yes
```

Block by address, never by user agent. A rule keyed on what a client says it is would serve crawlers something different from readers, which the URL policy in `AGENTS.md` forbids.

## Raising or lowering the rate limit

The per-IP limit from [#911](https://github.com/lddurbin/twelve_days_to_deming/issues/911) is set by [`scripts/firewall-rate-limit.sh`](../scripts/firewall-rate-limit.sh). Change `REQUESTS` (or `WINDOW_SECONDS`) there, then follow [firewall.md's Changing the rule](firewall.md#changing-the-rule): `stage enforce`, read the diff, publish. Lower it to choke a bursty client that's hopping between addresses in one range. Raise it if a class or a workplace behind one address is getting 429s.

Don't change the number with `vercel firewall rules edit "Rate limit per IP" --rate-limit-requests …` alone. On 2026-11-08 that reported `No changes detected` and staged nothing, and a change made outside the script drifts from it anyway.

## The feedback form

Chapter feedback goes through Web3Forms, not Vercel, so it has its own quota ([#915](https://github.com/lddurbin/twelve_days_to_deming/issues/915)):

- **Check it monthly** at [app.web3forms.com](https://app.web3forms.com) → **Billing & Usage**, signed in as `hello@leedurbin.co.nz`. The free plan allows 250 submissions a month, resetting on the 1st, and **sends no alert** before they run out. Once they have, feedback fails silently into the mailto fallback.
- **During a spam flood**, open the form's **Settings → Advanced Options** and turn on **Disable form submissions**. That rejects new submissions and keeps everything else. You can also raise **Spam Protection Level** from Basic to Strict. Turn both back afterwards.

## The old host

`deming.leedurbin.co.nz` on SiteGround serves only the [#888](https://github.com/lddurbin/twelve_days_to_deming/issues/888) bridge pages and an `.htaccess` 301, so heavy traffic there costs little and doesn't touch the Vercel allowance. If it starts serving the old site instead of the bridge, that's SiteGround's cache. The deploy job's **Flush SiteGround cache** step in [`deploy.yml`](../.github/workflows/deploy.yml) has the command to flush it by hand.

## Usage watch

The site moved to `learndeming.org` on 2026-09-28. The first two months are when an unexpected crawler is most likely to show up, so check usage **weekly until 2026-12-05**, then monthly alongside the Web3Forms check.

**This is a manual check, not a workflow.** #912 asked whether usage could be read automatically, so that a workflow like `release-cadence.yml` could open an issue past a threshold. On Hobby it can't. Tested on 2026-11-08 with CLI 65.12:

| What | Result |
| --- | --- |
| `vercel billing usage` | Refused: no billing data for a team with no subscription |
| `vercel metrics vercel.request.fdt_out_bytes` (transfer) | Needs Observability Plus |
| `vercel metrics … --all` (the whole team) | Needs Observability Plus |
| `vercel metrics vercel.request.count -p twelve-days-to-deming --since 1d` | Works, for one project and the last 24 hours only |

One project's request count for one day can't tell you where the team's monthly transfer stands, so a workflow built on it would give false comfort.

**The weekly check:** open the Usage page and look at both allowances. **If either is past 50% before the middle of the month**, find the cause with [Where to look](#where-to-look) and record it on a new issue. The baseline to compare against: 2,256 requests in the 24 hours to 2026-11-07 17:00 UTC, or about 68,000 a month, around 7% of the CDN Requests allowance. The weekly reminder is a calendar entry, not something in this repo.

## When this was checked

On 2026-11-08, against production:

- `firewall overview`, `traffic`, `metrics` and `billing usage` were run as described above.
- `ip-blocks block 192.0.2.1` (a documentation-only address) was staged, read in `firewall diff`, and discarded.
- The rate limit was staged at 1,200 through a copy of the script, read in `firewall diff`, and discarded. `firewall-rate-limit.sh show` confirmed the live rule was still 600 a minute with nothing pending.
- `attack-mode enable` was refused when run by Claude, as described above, so it was toggled on and off by hand in a terminal. The result is recorded on #912.
