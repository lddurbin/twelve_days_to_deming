# Firewall rate limit

The production Vercel project, `twelve-days-to-deming`, has one custom firewall rule: a per-IP rate limit across every path on `learndeming.org` ([#911](https://github.com/lddurbin/twelve_days_to_deming/issues/911), part of [#910](https://github.com/lddurbin/twelve_days_to_deming/issues/910)). This page records why it exists, what its numbers are, and how to change it.

Firewall rules live in Vercel, not in this repo. [`scripts/firewall-rate-limit.sh`](../scripts/firewall-rate-limit.sh) is the rule's source of truth: change its settings and re-stage, and never edit the rule in the dashboard alone, or the two drift apart.

## Why

The project is on Vercel **Hobby**, which can't be billed for overage. Running out of the monthly allowance doesn't produce an invoice. It pauses the project, which takes the site down for every reader. That allowance belongs to the Vercel team, not this project, and the team hosts another production project, so traffic here can pause both.

Vercel's automatic DDoS mitigation works on every plan, but it targets floods. A rate limit is the one control a client can't opt out of. `robots.txt` is only advisory.

## The rule

| Setting | Value |
| --- | --- |
| Name | `Rate limit per IP` |
| Applies to | every path (`path` starts with `/`) |
| Counted by | client IP |
| Algorithm | fixed window |
| Limit | 600 requests per 60 seconds |
| Over the limit | a 429, since 2026-10-25 (log mode from 2026-10-17) |

It counts by rate, never by user agent. Every client over the limit gets the same response, whatever it says it is. That keeps anonymous and crawler views byte-identical, as the URL policy in `AGENTS.md` requires.

### What Hobby allows

From [Vercel's rate-limiting docs](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting), as of October 2026:

- **Fixed window only.** Token bucket, which #911 originally proposed for its tolerance of a page load's burst, is Enterprise-only.
- **One rate-limit rule per project**, out of three custom rules in total.
- **A window of 10 seconds to 10 minutes.**
- **1,000,000 allowed rate-limited requests a month** are included. Because the rule covers every path, every request it lets through counts toward this, so it tracks the edge-request count closely. The docs don't say what happens on Hobby once it runs out. [#912](https://github.com/lddurbin/twelve_days_to_deming/issues/912)'s usage watch should cover it.

Requests the firewall blocks, rate-limits or challenges don't count as edge requests or data transfer. So once the rule is enforcing, a client over the limit stops costing the allowance.

### Why 600 a minute

One page view costs about 35 requests, not one: the page plus its same-origin CSS, JavaScript, fonts and images. Every response is served with `cache-control: public, max-age=0, must-revalidate`, so a browser revalidates each asset on every page view. A revalidation that returns 304 is still a request.

At 600 a minute, then, a single address can view about 17 pages a minute. One reader comes nowhere near that. A classroom or workplace behind one NAT address could: thirty people opening a page in the same minute is about 1,000 requests. That's exactly this course's use case, and it's why the rule runs in log mode before it blocks anything.

### What it doesn't protect

A per-IP limit stops one client from bursting. It can't protect the monthly allowance on its own. Even at the limit, one address could make 864,000 requests a day. A crawler that re-fetches the whole site every 15 minutes makes about 24 requests a minute and never comes close. Slow, steady overuse is what the usage watch in #912 is for.

## Changing the rule

Each change is a draft first and goes live only when someone publishes it:

1. `./scripts/firewall-rate-limit.sh stage log` or `stage enforce`. This creates the rule, or edits it if it already exists, and prints the draft diff.
2. Read the diff.
3. Publish it with **Review Changes → Publish** in the project's Firewall tab, or run `vercel firewall publish --scope lees-projects-5b4a1017` from a directory linked to the project. `vercel firewall discard` drops the draft.
4. `./scripts/firewall-rate-limit.sh show` prints the rule, then any changes still waiting to be published. The rule includes unpublished changes, so it's only what's live once the diff says `No pending changes`.

To change the limit itself, edit `WINDOW_SECONDS` or `REQUESTS` in the script, update the table above, and go through the same steps.

## Reading the logs

The dashboard's Firewall tab shows traffic per rule, with top IPs, JA4 fingerprints and user agents. From a directory linked to the project, the CLI shows the same thing:

```sh
vercel firewall traffic list --top 20 \
  --dimension ip --dimension user-agent --dimension rule \
  --scope lees-projects-5b4a1017
```

`firewall traffic` needs a recent CLI. 54.20 doesn't have it, so run `npm i -g vercel@latest` first, or use `npx vercel@latest firewall traffic …` without changing the global install. Without Observability Plus, which Hobby doesn't have, a query can only reach back about 24 hours. `--since 7d` is refused. So a trial week has to be read **once a day**, noting each day's busiest addresses, not in one query at the end. `traffic inspect ip <address>` breaks one address down by minute and by path.

The log week's findings are in [#911](https://github.com/lddurbin/twelve_days_to_deming/issues/911#issuecomment-6392813080). The rule never fired. Site-wide traffic peaked at 150 requests an hour, and no address looked like a group of readers, so the limit stayed at 600. If the limit changes later, record the same three things on the issue that prompts it: the busiest addresses and their peak requests per minute, whether any were a group of readers rather than a crawler, and the limit chosen as a result.

## Staging

The staging project (`twelve-days-to-deming-staging`) has no rule. It sits behind Basic Auth, isn't linked from anywhere, and a client that guesses its URL gets a 401. If it ever needs one, Hobby allows a separate rule per project.

## Checking it works

A plain loop from one machine **doesn't reach this rule**. Vercel's own DDoS mitigation runs first and challenges a tight loop long before it gets to 600 a minute. On 2026-10-25, 700 back-to-back requests from one address got 39 × 200, then a challenge for every request after that. curl can't answer a challenge, so it sees each one as a 403. `traffic inspect ip <address> --group-by rule` shows them as `sys_dos_mitigation`, not this rule. The challenge outlasts the minute's window, so the same address keeps getting 403s afterwards (about 8 minutes that time), and `security-headers.sh check` fails from it until the challenge lapses.

Exempting your own address from the system mitigations (`vercel firewall system-bypass add`) would let a loop through, but Hobby refuses it with a 402. IP bypass needs Pro.

So the check narrows the rule to your own address, with a limit low enough to reach at one request a second, which is far too slow to trip the DDoS mitigation. Nobody else can be rate-limited while it runs. Everyone else is simply unlimited for those couple of minutes, and the system mitigations still cover floods. From a directory linked to the project:

```sh
S=--scope=lees-projects-5b4a1017
IP=$(curl -s https://api.ipify.org)
vercel firewall rules edit "Rate limit per IP" \
  --condition "{\"type\":\"ip_address\",\"op\":\"eq\",\"value\":\"$IP\"}" \
  --action rate_limit --rate-limit-algo fixed_window --rate-limit-window 60 \
  --rate-limit-requests 10 --rate-limit-keys ip --rate-limit-action rate_limit \
  --yes $S
vercel firewall publish --yes $S
for i in $(seq 20); do
  curl -s -o /dev/null -w '%{http_code}\n' https://learndeming.org/robots.txt; sleep 1
done
```

The loop prints each status as it arrives. Expect about ten 200s, then 429s. Then restore the real rule from the script and publish it, straight away:

```sh
./scripts/firewall-rate-limit.sh stage enforce
vercel firewall publish --yes $S
./scripts/firewall-rate-limit.sh show
```

`show` should print `path starts with /` and 600 requests, then `No pending changes`. `traffic inspect ip <your-ip> --group-by rule` confirms the test afterwards: the 429s appear as `Rate Limited` under the rule's id. That's how it was verified on 2026-10-25.

Counters are kept per Vercel region, so a client spread across regions could exceed the limit overall without tripping it.
