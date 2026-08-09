# Cookie/consent position for session auth

Design note for [#548](https://github.com/lddurbin/twelve_days_to_deming/issues/548), part of the accounts epic ([#529](https://github.com/lddurbin/twelve_days_to_deming/issues/529)). No code.

`privacy.qmd` currently states that Simple Analytics sets no cookies, "so no cookie banner is needed." That's a real, valuable property of the site today, and accounts don't have to cost it. Under GDPR/ePrivacy, a **strictly-necessary** cookie — one that exists solely to keep a logged-in reader logged in, and does nothing else — is exempt from consent requirements. The exemption is narrow and easy to lose by accident (any analytics, personalisation, or measurement use forfeits it), which is why the position is decided here, before a vendor or a consent banner gets bolted on.

## 1. What the session cookie contains and does

An opaque, random session identifier and nothing else — no embedded analytics ID, no personalisation payload, no tracking use. Its only function is: does this request belong to a logged-in reader, and which account.

This is a constraint on the eventual implementation, not just a description: whatever auth mechanism gets chosen (see §6) must not attach anything to the session token beyond what authentication itself requires.

## 2. Cookie attributes

| Attribute | Value | Why |
|---|---|---|
| `HttpOnly` | yes | The cookie is never read by page JavaScript — nothing in `functions.js` or elsewhere needs it, and keeping it out of `document.cookie` removes an entire XSS exfiltration path. |
| `Secure` | yes | The site is HTTPS-only already; the cookie should never be sent in the clear. |
| `SameSite` | `Lax` | `Strict` would drop the cookie on a top-level cross-site navigation into the site — e.g. a reader clicking a bookmarked or shared link from another tab — which reads as "you got logged out" for no reason. `Lax` still blocks the cookie on cross-site subresource requests and non-GET requests, which is what actually matters for CSRF protection on a session cookie. |
| Expiry | sliding, 30 days idle timeout (proposed) | Balances "don't make readers log in every visit" against not keeping a valid session alive indefinitely on a shared device. This is a default for whoever scopes the auth issue to confirm, not a hard requirement of this note — it depends on the auth mechanism chosen. |
| Name | `__Host-session` (or similar `__Host-` prefix) | Browser-enforced, not just a naming convention: the `__Host-` prefix is rejected by the browser unless the cookie also has `Secure`, no `Domain` attribute, and `Path=/`. That closes the class of attack where a compromised or malicious subdomain sets a same-named cookie to shadow the real session cookie. The site is HTTPS-only with no auth subdomain planned, so this costs nothing to adopt. |

## 3. Third-party cookies are a hard vendor-selection criterion

If an auth vendor sets its own cookie (for its own session tracking, fraud detection, etc.), the strictly-necessary exemption may not survive — the site would be relying on the vendor's cookie being *also* strictly necessary, which is not guaranteed and not this project's call to make. This isn't a detail to reconcile after picking a vendor; it should be checked before signing up for one, alongside the NZ/AU data-residency requirement from [#547](https://github.com/lddurbin/twelve_days_to_deming/issues/547).

## 4. The logged-out reader is unaffected

No cookie, no banner, nothing changes. `privacy.qmd`'s existing promise — "there's no identifier that ties one of your visits to the next" (currently the "No personal data" bullet under Analytics) — holds exactly as written for anyone who never creates an account.

## 5. How `privacy.qmd` should be restructured (when accounts ship)

Not done in this PR — `privacy.qmd` describes a site with no accounts yet, and rewriting it now would describe a feature that doesn't exist. When accounts ship, the page should split into two honest states rather than layering a caveat onto the existing text:

- **If you're not logged in** — today's section, unchanged, so the anonymous case doesn't read as though it's been quietly weakened.
- **If you're logged in** — a new section covering: the session cookie (per §1–2 above), what's stored on the account and where (per [#547](https://github.com/lddurbin/twelve_days_to_deming/issues/547)), and a link to account deletion/export.

## 6. Related: auth mechanism (not decided here)

**Passkeys or email magic links** avoid storing passwords entirely — smaller breach surface, and a better fit for a site that already tries to collect as little as possible. Worth recording here because it interacts directly with cookie behaviour (a magic link is itself a cross-site navigation into the site, which is part of why §2 recommends `SameSite=Lax` over `Strict`), but the actual choice belongs to the not-yet-created auth implementation issue, not to this note.
