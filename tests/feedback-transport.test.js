import { describe, it, expect, afterEach, vi } from "vitest";
import { sendFeedback } from "../assets/scripts/feedback-transport.js";

// The contract that matters here is that this module NEVER throws and never
// rejects: chapter-rating.js renders its failure state (and the mailto
// fallback) from `{ok: false}`, so an exception escaping would leave the
// reader looking at a "Sending…" button forever.

const NOTE = { text: "The funnel bit lost me.", day: 3, chapter: 12, rating: "down" };

function mockFetch(impl) {
  const spy = vi.fn(impl);
  globalThis.fetch = spy;
  return spy;
}

function jsonResponse(body, { ok = true } = {}) {
  return { ok, json: async () => body };
}

afterEach(() => {
  delete globalThis.fetch;
  vi.restoreAllMocks();
});

describe("sendFeedback", () => {
  it("posts JSON to the Web3Forms endpoint", async () => {
    const spy = mockFetch(async () => jsonResponse({ success: true }));
    await sendFeedback(NOTE);

    const [url, options] = spy.mock.calls[0];
    expect(url).toBe("https://api.web3forms.com/submit");
    expect(options.method).toBe("POST");
    expect(options.headers["Content-Type"]).toBe("application/json");
  });

  it("sends the text, chapter and rating, and nothing identifying", async () => {
    const spy = mockFetch(async () => jsonResponse({ success: true }));
    await sendFeedback(NOTE);

    const body = JSON.parse(spy.mock.calls[0][1].body);
    expect(body.message).toBe(NOTE.text);
    expect(body.day).toBe(3);
    expect(body.chapter).toBe(12);
    expect(body.rating).toBe("down");

    // The privacy page promises nothing else travels with the reader's
    // words. This asserts the payload's whole shape so adding a field has
    // to be a deliberate act that updates that promise too.
    expect(Object.keys(body).sort()).toEqual(
      ["access_key", "botcheck", "chapter", "day", "from_name", "message", "rating", "subject"],
    );
  });

  it("reports success only when the body says success", async () => {
    mockFetch(async () => jsonResponse({ success: true }));
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: true });
  });

  it("reports failure on a 200 that carries success: false", async () => {
    // Web3Forms answers 200 with success:false for a bad key or a
    // spam-flagged submission, so response.ok alone would call those sent.
    mockFetch(async () => jsonResponse({ success: false, message: "invalid key" }));
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: false });
  });

  it("reports failure on a non-2xx response", async () => {
    mockFetch(async () => jsonResponse({ success: true }, { ok: false }));
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: false });
  });

  it("resolves rather than rejecting when the network fails", async () => {
    mockFetch(async () => { throw new TypeError("Failed to fetch"); });
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: false });
  });

  it("resolves rather than rejecting when the response isn't JSON", async () => {
    mockFetch(async () => ({ ok: true, json: async () => { throw new SyntaxError("bad"); } }));
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: false });
  });

  it("resolves rather than rejecting when fetch is unavailable entirely", async () => {
    delete globalThis.fetch;
    await expect(sendFeedback(NOTE)).resolves.toEqual({ ok: false });
  });

  it("truncates a runaway paste rather than sending it whole", async () => {
    const spy = mockFetch(async () => jsonResponse({ success: true }));
    await sendFeedback({ ...NOTE, text: "x".repeat(9000) });

    const body = JSON.parse(spy.mock.calls[0][1].body);
    expect(body.message).toHaveLength(5000);
  });

  it("survives a missing text field without throwing", async () => {
    const spy = mockFetch(async () => jsonResponse({ success: true }));
    await expect(sendFeedback({ day: 1, chapter: 1, rating: "down" })).resolves.toEqual({ ok: true });

    const body = JSON.parse(spy.mock.calls[0][1].body);
    // Coerced to "", not the string "undefined", which would land in my inbox.
    expect(body.message).toBe("");
  });

  it("passes an abort signal so a stuck request can't hang the widget", async () => {
    const spy = mockFetch(async () => jsonResponse({ success: true }));
    await sendFeedback(NOTE);
    expect(spy.mock.calls[0][1].signal).toBeInstanceOf(AbortSignal);
  });
});
