# Security policy

## Reporting a vulnerability

Please report security problems privately, through GitHub's advisory form:
**[Report a vulnerability](https://github.com/lddurbin/twelve_days_to_deming/security/advisories/new)**.
Please don't open a public issue for anything that could be exploited before
it's fixed.

Helpful things to include: the URL or file affected, what an attacker could do,
and the steps to reproduce it.

## What to expect

This project has one maintainer, working on it in their spare time, so
responses are best effort:

- **Acknowledgement:** usually within a week, though it can take up to two.
- **Assessment and fix:** depends on severity and complexity. You'll hear what
  the plan is once the report has been looked at.
- **Credit:** you'll be credited in the published advisory, unless you'd rather
  not be.

## In scope

- **The site at [`learndeming.org`](https://learndeming.org)**, hosted on Vercel.
- **The old host, `deming.leedurbin.co.nz`**, which serves only a bridge page
  per page of the site, carrying readers' saved answers to `learndeming.org`,
  and redirects everything else there.
- **This repository's GitHub Actions workflows**, including how they handle
  secrets and deploy credentials.
- **The `/api/*` account endpoints**, once they ship. They don't exist yet.

## Out of scope

- **The Web3Forms access key** in `assets/scripts/feedback-transport.js`. It's
  public by design: a Web3Forms key can only submit to the feedback form, and
  it has to be in the page for the form to work.
- **Rate limits on static content.** The site is static files on a CDN, and
  its traffic controls are deliberately rate-based, not a security boundary.
- **Missing or weaker security headers with no demonstrated impact.** A report
  that shows a header's absence leads to a real attack is in scope.
- **Third-party services** the site loads from or links to, such as
  `cdn.jsdelivr.net` or YouTube. Please report those to their owners.

## `security.txt`

The site serves [`/.well-known/security.txt`](https://learndeming.org/.well-known/security.txt)
([RFC 9116](https://www.rfc-editor.org/rfc/rfc9116)), pointing at the same
advisory form. Its source is [`.well-known/security.txt`](.well-known/security.txt).
