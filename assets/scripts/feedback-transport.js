// ============================================================
// Feedback transport — the only place free text leaves the reader's
// device (#494).
//
// The site is a static rsync'd docroot with no backend, so there is nothing
// on the origin that can receive a POST. Reader-written text therefore has
// to go to a third-party form processor. Every vendor-specific detail lives
// here and nowhere else, matching the stance telemetry.js takes for the
// analytics vendor: swapping Web3Forms for another processor should touch
// this file, plus the connect-src host in _quarto.yml's CSP, and nothing
// else.
//
// This is a genuine widening of what the site sends onward, and privacy.qmd
// discloses it explicitly. Keep the payload below minimal — it is the whole
// of what the reader's words travel with, and the "no identifier ties one
// visit to the next" promise on that page depends on nothing more being
// added here.
// ============================================================

// TODO(#494): replace with the real access key from the Web3Forms dashboard.
// Web3Forms access keys are designed to be public — they identify the
// destination inbox, not the sender — so this sitting in client-side source
// is the intended usage, not a leak.
const ACCESS_KEY = "REPLACE_WITH_WEB3FORMS_ACCESS_KEY";

// Kept out of any STRINGS object for the reason feedback-prompt.js documents
// at its own CTA_HREF: the FR extractor sweeps translatable prose, and a URL
// swept in as copy risks a translator "translating" it.
const ENDPOINT = "https://api.web3forms.com/submit";

// A stuck request must not leave the widget spinning forever. On timeout the
// reader gets the same failure state (and mailto fallback) as any other
// error, which is the honest outcome — we genuinely don't know if it landed.
const TIMEOUT_MS = 10000;

// Generous for a "what didn't work here?" box, but bounded: an accidental
// paste of an entire chapter shouldn't be silently truncated by the vendor
// or rejected wholesale. Trimming here keeps the failure visible to us.
const MAX_TEXT_LENGTH = 5000;

/**
 * Send a chapter-feedback note onward.
 *
 * Never throws and never rejects — the caller renders a failure state from
 * `{ok: false}`, and a transport problem must not be able to break a page.
 *
 * @param {{text: string, day: number|null, chapter: number|null, rating: string}} note
 * @returns {Promise<{ok: boolean}>}
 */
export async function sendFeedback({ text, day, chapter, rating }) {
  try {
    // AbortController rather than Promise.race: race leaves the underlying
    // request in flight, so a slow-but-eventually-successful POST would land
    // after we'd already told the reader it failed.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

    let response;
    try {
      response = await fetch(ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          access_key: ACCESS_KEY,
          subject: `12 Days to Deming — ${rating} on day ${day}, chapter ${chapter}`,
          from_name: "12 Days to Deming",
          // Web3Forms' honeypot field. Near-inert for a programmatic JSON
          // POST — there is no rendered form for a bot to autofill, and
          // anything targeting this endpoint directly would simply omit it.
          // Sent anyway to match the vendor's documented contract rather
          // than relying on undefined behaviour when it's absent.
          botcheck: "",
          rating,
          day,
          chapter,
          message: String(text ?? "").slice(0, MAX_TEXT_LENGTH),
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    // Web3Forms returns 200 with {success: false} for some rejections (bad
    // key, spam-flagged), so response.ok alone would report those as sent.
    if (!response.ok) return { ok: false };
    const body = await response.json();
    return { ok: body?.success === true };
  } catch (e) {
    // Network failure, CSP block, abort, or malformed JSON all land here.
    // The caller's failure state offers the mailto fallback, so this is
    // reported to the reader rather than swallowed.
    return { ok: false };
  }
}
