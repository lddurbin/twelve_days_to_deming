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
| Over the limit | `log` during the trial week, then a 429 |

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
4. `./scripts/firewall-rate-limit.sh show` confirms what's live.

To change the limit itself, edit `WINDOW_SECONDS` or `REQUESTS` in the script, update the table above, and go through the same steps.

## Reading the logs

The dashboard's Firewall tab shows traffic per rule, with top IPs, JA4 fingerprints and user agents. From a directory linked to the project, the CLI shows the same thing:

```sh
vercel firewall traffic list --since 7d --top 20 \
  --dimension ip --dimension user-agent --dimension rule \
  --scope lees-projects-5b4a1017
```

Before switching to `enforce`, record in #911:

- the busiest addresses and their peak requests per minute
- whether any were clearly a group of readers (a school or company network) rather than a crawler
- the limit chosen as a result, if it differs from 600

## Staging

The staging project (`twelve-days-to-deming-staging`) has no rule. It sits behind Basic Auth, isn't linked from anywhere, and a client that guesses its URL gets a 401. If it ever needs one, Hobby allows a separate rule per project.

## Checking it works

Once it's enforcing, a tight loop from one machine should start getting 429s past the limit:

```sh
for i in $(seq 700); do
  curl -s -o /dev/null -w '%{http_code}\n' https://learndeming.org/robots.txt
done | sort | uniq -c
```

Normal browsing from the same machine should recover once the minute's window has passed. Counters are kept per Vercel region, so a client spread across regions could exceed the limit overall without tripping it.
