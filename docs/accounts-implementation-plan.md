# Accounts and saved notes — implementation plan

_Last updated: 2026-08-24_

Implementation plan for the accounts feature, following the closed groundwork epic
([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)). It converts three
existing design notes — [`accounts-data-model.md`](accounts-data-model.md),
[`accounts-cookie-consent.md`](accounts-cookie-consent.md),
[`paid-content-repository-split.md`](paid-content-repository-split.md) — into a buildable
shape, and records one deliberate reversal of a commitment in the first of those.

The feature is narrow on purpose: **a reader can create an account and their workbook
answers follow them across devices.** Nothing else.

## 1. What is already true

Established by #529 and verified against the working tree:

| Fact | Where |
|---|---|
| Workbook answers already persist locally, keyed by a stable identity | `assets/scripts/workbook.js`, `td:workbook` |
| Key format is repo-relative path + `viewof` name | e.g. `content/days/day-06/03-activity-6b.qmd#activity_6b_pre` |
| 412 `Inputs.*` fields across 48 `.qmd` files are already keyed | #539–#544 |
| A whole-object read hook exists for sync | `getAnswers()` in `workbook.js` |
| Vercel is the chosen edge platform, with artifact-only deploy proven | #531 |
| Two Build Output API v3 payloads already ship, one with an edge function | `deploy.yml` staging job, `accessibility.yml` preview job |
| Production does **not** run on Vercel | `deploy.yml:312` rsyncs `_book/` to a shared host |

That last row is the blocker. There is nowhere on production to run a request handler, so
**the hosting cutover is a prerequisite, not a parallel track.** #529 explicitly deferred it.

## 2. The encryption decision, reversed

[`accounts-data-model.md` §3](accounts-data-model.md) committed to client-side encryption of
workbook answers, with the key derived from something only the reader's device holds. **That
commitment is withdrawn.** Workbook answers will be stored server-side in a form the operator
can technically read.

This is taking a branch §3 itself drafted: it names the fallback ("a server-side per-user key,
which the operator *could* decrypt with database and key-store access") and attaches one
condition — that the weaker guarantee be **disclosed as the weaker guarantee it actually is**,
in the note and in `privacy.qmd`, rather than left implied as the stronger one. That condition
is binding on this plan.

Three reasons, in order of weight:

1. **It is structurally incompatible with sharing.** The second feature the site wants —
   readers sharing notes with each other — cannot be built on top of answers only the writing
   device can decrypt. Under §3 as written, sharing needs an entire second mechanism running
   alongside the first. Sharing itself stays parked behind
   [#652](https://github.com/lddurbin/twelve_days_to_deming/issues/652), but the encryption
   commitment would foreclose it before that spike reports.
2. **The cost lands on the reader, not the operator.** A client-held key means a passphrase or
   a passkey, a recovery code, an unlock step on every new device, and a failure mode where
   forgetting one thing destroys the notes irrecoverably with no reset path — because any
   email-based reset would imply the server holds something sufficient to decrypt, which is
   exactly what §3 forbade. That is a heavy price for a free educational site.
3. **The threat it defends against is not the likely one.** Client-side encryption uniquely
   defends against the operator and against legal compulsion. It adds little against the
   realistic risk, which is a database breach — addressed by platform encryption at rest,
   row-level security, and credential discipline.

### What does not change

The sensitivity §3 identified is real and is not being waved away. Days 10–11 hold 194 inputs
about the reader's actual workplace and Day 12 asks for a report to a named Chief Executive.
The harm model is employment consequence, not fraud, and it does not require regulated-category
data to be serious.

The mitigation moves from cryptography to disclosure, on the principle that a reader who knows
their notes are stored can decide for themselves what to write — a choice encryption makes on
their behalf and charges them a passphrase for:

- `privacy.qmd` states plainly that notes are stored on the site's servers, that the operator
  can technically access them, and the narrow circumstances in which that would happen.
- A short line appears near activity inputs **for logged-in readers only**, at the point of
  writing rather than only in a policy page.
- Row-level security is load-bearing, not decorative — see §4.

### What is kept from the existing notes

Unchanged and not up for renegotiation in implementation PRs:

- **§1 Email only.** No display name, no organisation. Signup collects an email address and
  nothing else.
- **§2 `ap-southeast-2` (Sydney).** Chosen at project creation and not changeable afterwards.
- **§4 Export** and **§5 Deletion** — GDPR obligations, which attach to an email address alone.
- **§7 Anonymous readers are unaffected**, and the URL freeze in `CLAUDE.md`. Every one of the
  123 current URLs serves an anonymous visitor byte-identical bytes. Account routes are new
  URLs, added alongside.
- **Cookie note §1–2** — an opaque session identifier, `HttpOnly`, `Secure`, `SameSite=Lax`,
  `__Host-` prefixed, sliding 30-day idle expiry. Nothing but authentication rides on it, so
  the strictly-necessary exemption holds and no cookie banner appears.

## 3. The reader's experience

**Signing up.** Enter an email address. Click the link in the email. That is the whole flow —
no password, no passphrase, no recovery code, nothing to remember and nothing that can be
permanently lost. On arrival, any notes already saved on the device are adopted into the
account and the reader is told so, as a confirmation rather than a question.

**Returning.** The session cookie carries them for 30 idle days. After that, or on a new
device, it is the same magic link again.

**Logged out, or never signed up.** Byte-identical to today. Notes save to `localStorage`
exactly as they do now; the account link in the footer is a static link that behaves the same
for a crawler as for a reader.

## 4. Architecture

Quarto stays. The site remains a static book; accounts are one more ES module plus a handful of
own-origin functions deployed beside the static output.

```
Browser ──same-origin──> /api/*  (Vercel Edge Function)
                            │
                            ├── Supabase Auth   (magic link issue + verify)
                            └── Supabase Postgres (RLS-enforced, ap-southeast-2)
```

Four decisions worth recording:

**The browser never talks to Supabase.** All traffic goes to `/api/*` on the site's own origin.
This is not incidental — it resolves three separate conflicts at once. The CSP at
`_quarto.yml:116` is `connect-src 'self' …`, which already permits this and would otherwise
need `supabase.co` added. Supabase's browser client stores its JWT in `localStorage`, the exact
thing cookie note §2 was written to avoid. And keeping the vendor behind an own-origin boundary
means it stays swappable rather than becoming load-bearing on the client.

**The session cookie is an opaque random identifier**, resolved server-side against a `sessions`
row holding the Supabase tokens. A sealed/encrypted cookie carrying the tokens directly was
considered — it avoids a lookup per request — and rejected because cookie note §1 commits to
"an opaque, random session identifier and nothing else", and a lookup per request is free at
this traffic level.

**Row-level security must actually enforce.** The edge function mints a short-lived Supabase
JWT scoped to the session's user and calls PostgREST with it, rather than using the service-role
key with a `where user_id = …` clause. Service-role bypasses RLS entirely, which would make the
policies decorative — a single missing predicate in one handler would expose every reader's
notes. Under the scoped-JWT model, the database refuses the query regardless of what the
handler forgot.

**Conflict resolution is per-key last-write-wins.** `td:workbook` is a flat `{key: value}`
object with no timestamps, and `workbook.js`'s `isValidAnswers` rejects any other shape — so
changing it in place would invalidate every existing reader's store on their next load. Instead
a **parallel** `td:workbook:meta` key holds `{key: updatedAt}`, leaving `td:workbook` untouched
and backwards compatible. A key with no recorded timestamp is treated as older than the server's
copy.

**Account pages are Quarto-rendered but outside the book's nav.** A book project renders what
its `chapters:`/`appendices:` lists name; anything else is dropped from the site. Adding account
pages as chapters would put "Sign in" in the reading sidebar between Day 6 and Day 7. The
mechanism to confirm is `project: render:`, which renders a file with the project's format and
theme without placing it in the book structure. This also has to be reflected in
`scripts/generate-pa11y-urls.R`, which derives `.pa11yci.json` from the chapter list and would
otherwise leave the new routes with no accessibility coverage.

### The production Vercel project (#679)

Created on the same team as the existing staging/preview projects, matching the naming
established there:

| Setting | Value |
|---|---|
| Project name | `twelve-days-to-deming` |
| Team | `lees-projects-5b4a1017` (`team_hSkXjMnjfuh3SG292of3TunJ`) |
| Project ID | `prj_hHI1fHKOBw4xqzETztVeeXzq5MGv` |
| Framework preset | Other (none) |
| Build / install command | None — no git repo connected, no build ever runs. Deploys are always a prebuilt Build Output API v3 payload, per #680. |
| Region | Not project-configurable pre-deploy; the existing staging/preview projects observe Vercel routing edge responses through Sydney (`syd1`), per #531. |

`VERCEL_PROJECT_ID` and `VERCEL_ORG_ID` are recorded as **variables** (not secrets) on the
`production` GitHub Environment — they identify the project but aren't credentials. The
credential is `VERCEL_TOKEN`, added separately when #680 wires up the deploy job, matching the
per-environment token isolation `staging` and `preview` already use.

No DNS change and no traffic yet: `deming.leedurbin.co.nz` still points at the shared host.

## 5. Delivery

Two epics, sequential. Epic A is a prerequisite for Epic B: without it there is no server-side
execution on production.

**Epic A — Move production to Vercel.** Replace the rsync-to-shared-host deploy with a Build
Output API v3 deployment, reusing the payload assembly that already ships twice. Rewrite the
rollback model around platform instant-rollback, since `docs/ROLLBACK.md` describes restoring a
docroot with `cp -r`, which does nothing once a database is involved.

**Epic B — Saved notes on an account.** Provisioning, schema, session layer, sync, account
surface, then policy and CI coverage.

Merge sequentially, not as a fleet: `main` has `strict: true` protection and no merge queue
(#385), so concurrent PRs cascade into `BEHIND` and each needs an explicit `update-branch` and a
full CI wait.

## 6. Deliberately out of scope

- **Sharing notes between readers** — parked behind #652, which must report on the free/paid
  boundary first. This plan removes the encryption obstacle to it but does not build it.
- **Any paid surface**, and any gating of existing content. The URL freeze in `CLAUDE.md` stands.
- **Progress and ratings sync.** `engagement.js` counters were made merge-safe in #546, so this
  is cheap to add later; it is left out to keep the first release to one feature.
- **Community, profiles, display names.**

## 7. Open questions

1. **Email deliverability.** Supabase's built-in SMTP is rate-limited and explicitly not for
   production use; magic links are the entire login flow, so a real transactional sender is on
   the critical path, not an optimisation.
2. **Whether the shared host is retired or kept warm** as a fallback docroot for some period
   after DNS cuts over.
3. **Dormancy deletion (data-model §6)** needs a scheduled execution context, which the cutover
   provides for the first time. Whether it ships in the first release or immediately after is a
   sizing call, not a policy one — the 2-year commitment stands either way.
