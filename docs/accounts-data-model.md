# Account data model, storage location, export and deletion

_Last updated: 2026-08-24_

Design note for [#547](https://github.com/lddurbin/twelve_days_to_deming/issues/547), part of the accounts epic ([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)). No code. This is written before any account data is collected, so every question here is answered on paper rather than discovered later while already holding data.

The current site's promise, from `privacy.qmd`, is that "there's no identifier that ties one of your visits to the next." Accounts change that for logged-in readers. The goal of this note is to change it deliberately and minimally — this document is the specification that promise gets rewritten against, not a rewrite of `privacy.qmd` itself, and not something wired into the build yet.

## 1. Fields on an account

**Email only.** No name, no organisation, no profile fields.

Every additional field needs a reason it cannot work without — "might be nice to have" is not that reason. Two candidates were considered and rejected for now:

- **Display name** — not needed until there's a members-facing surface that addresses the reader by name. Nothing in this epic's scope requires that.
- **Organisation/role** — not needed for saved progress or paid content delivery. If a future paid tier wants this for tailoring content, it should be collected at that point, for that stated purpose, not speculatively now.

If a future issue wants to add a field, it should link back here and state the reason.

## 2. Storage location and jurisdiction

**Commitment: account and synced data is stored in an NZ/AU region.** This is the more conservative reading of NZ Privacy Act 2020 IPP 12, which governs disclosure of personal information outside New Zealand — keeping storage in-region avoids the cross-border disclosure question entirely rather than relying on a vendor's contractual safeguards.

Two things this does *not* resolve:

- **No storage vendor is chosen yet.** The platform spike ([#531](https://github.com/lddurbin/twelve_days_to_deming/issues/531)) picked Vercel for static hosting and observed edge responses from Sydney (`syd1`), but explicitly deferred the choice of any future KV/Postgres store to provisioning time. This commitment narrows that future choice — the store must offer an AU (or NZ, if one becomes available) region — rather than picking the store itself.
- **GDPR applies regardless of storage location.** GDPR's territorial scope is based on where the data subject is, not where the server sits — an EU reader's data is still GDPR-governed even stored in Sydney. NZ/AU storage satisfies IPP 12; it does not exempt the site from GDPR obligations (lawful basis, data-subject rights, breach notification) for EU readers. Those obligations apply to the account model described here regardless of region.

## 3. What syncs, and what's sensitive about it

Two categories, deliberately handled differently:

- **Progress and ratings** (which chapters are read, funnel-experiment state, thumbs up/down) — low sensitivity, no free text, synced in plain form.
- **Written workbook answers** — free text a reader has written about their own workplace. Day 12 explicitly asks for a report to a named Chief Executive. This is the one category where "what can the operator read" matters.

**Decision (2026-08-09) — superseded, see the amendment below.** Workbook answers are encrypted at rest, using a client-side model. The encryption key is derived from something only the reader's device or credential holds — for example a WebAuthn PRF-derived key, if passkeys are chosen as the auth mechanism (see [#548](https://github.com/lddurbin/twelve_days_to_deming/issues/548)) — never a key the server holds on the reader's behalf. That's the only model consistent with the guarantee this note is making: the operator (me) should not be able to read a reader's saved answers by querying the database directly, even with full database *and* key-store access, because no single thing the server holds is sufficient to decrypt them.

This is a real cost, not a checkbox. It constrains the auth-mechanism choice — a pure email-magic-link flow hands the server no client-held secret to derive a key from — and it rules out server-side search over workbook answers. **If the auth issue lands on a mechanism that can't supply a client-held secret, this guarantee doesn't hold**, and the fallback (a server-side per-user key, which the operator *could* decrypt with database and key-store access) must be disclosed as the weaker guarantee it actually is — here and in `privacy.qmd` — rather than left implied as the stronger one.

### Amendment, 2026-08-24: the client-side model is withdrawn

**Workbook answers are stored server-side in a form the operator can technically read.** This takes the fallback branch the paragraph above already drafted, and it is bound by the condition that paragraph attached: the weaker guarantee must be **stated plainly** in `privacy.qmd`, not left implied as the stronger one.

The reasoning is recorded in full in [`accounts-implementation-plan.md` §2](accounts-implementation-plan.md). In short:

1. **It is structurally incompatible with sharing.** Notes only the writing device can decrypt cannot be shared with another reader without building a second mechanism alongside the first. Sharing stays parked behind [#652](https://github.com/lddurbin/twelve_days_to_deming/issues/652), but this commitment would foreclose it before that spike reports.
2. **The cost falls on the reader.** A client-held key means a passphrase or passkey, a recovery code, an unlock step per device, and permanent irrecoverable loss if either is forgotten — with no reset path possible, since any email-based reset would imply the server holds enough to decrypt.
3. **It defends the wrong threat.** Client-side encryption uniquely defends against the operator and against legal compulsion. Against the realistic risk — a database breach — platform encryption at rest, enforced row-level security, and credential discipline do the work.

What this does **not** change: the sensitivity identified above is real. The harm model is employment consequence, not fraud, and does not need regulated-category data to be serious. The mitigation moves from cryptography to disclosure — `privacy.qmd` says what is stored and who can read it, and a short line appears near activity inputs for logged-in readers, at the point of writing rather than only in a policy page.

Progress and ratings are not encrypted at rest; there's nothing in them to protect beyond normal access control.

## 4. Export

Readers can export everything on their account in a usable format (JSON, containing progress, ratings, and workbook answers) on request.

This extends an existing precedent rather than inventing one: `functions.js`'s `downloadNotes` already lets a reader download their per-page written answers as a `.txt` file. A whole-account export is the same idea at account scope, and should ship as part of the same feature rather than as a follow-up.

## 5. Deletion

"Delete my account" removes the account record, all synced progress/ratings, and all workbook answers from the primary store **immediately** on confirmed request.

Proposed defaults, for the maintainer to confirm or adjust when the implementation issue is scoped (not fixed by this note, since no storage vendor exists yet to size the real numbers against):

- A short **soft-delete window** (proposed: 14 days) during which a reader who deleted by mistake can restore the account, after which it's hard-deleted.
- **Backup/snapshot purge within 30 days** of hard deletion — the honest answer for "what survives in backups" is "nothing, but not instantly," and 30 days is a common default for backup rotation rather than a promise this note can verify against a real vendor yet.

## 6. Retention

**Dormant accounts are auto-deleted after 2 years of inactivity**, with advance notice to the reader before deletion happens (proposed: an email warning 30 days out, to the account's email address, with a one-click "keep my account" action).

"Inactivity" means no login and no reading-progress event in that window — matching the existing `engagement.js` model of what counts as activity today.

## 7. Anonymous readers are unaffected

This is a constraint on everything above, not a feature of it: **the logged-out experience keeps today's guarantees exactly.** No identifier ties one visit to the next, no cookie is set, `privacy.qmd:17`'s promise holds unchanged. Accounts are additive — a reader who never creates one sees no difference at all.

## Using this note

This is meant to be sufficient to evaluate any candidate auth or storage vendor against: does it support an AU/NZ region, does it avoid setting its own cookies (see [#548](https://github.com/lddurbin/twelve_days_to_deming/issues/548)), can encryption-at-rest be scoped per-field, does it support a real deletion API rather than a soft "deactivate" flag. Whoever picks up the storage-vendor decision should check candidates against sections 2, 3, and 5 above before anything else.
