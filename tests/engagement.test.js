import { describe, it, expect, afterEach, vi } from "vitest";
import { shouldPrompt } from "../assets/scripts/engagement.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = new Date("2026-08-01T12:00:00.000Z");

function engagement(overrides = {}) {
  return {
    firstSeen: "2026-07-01T00:00:00.000Z",
    activeMs: 0,
    days: [],
    chapters: [],
    acts: 0,
    maxDay: 1,
    ...overrides,
  };
}

function feedback(overrides = {}) {
  return {
    status: "none",
    dismissals: 0,
    at: null,
    ...overrides,
  };
}

function daysAgo(n) {
  return new Date(NOW.getTime() - n * DAY_MS).toISOString();
}

// ---------------------------------------------------------------------------
// shouldPrompt
// ---------------------------------------------------------------------------
describe("shouldPrompt", () => {
  it("returns false for a never-engaged reader", () => {
    expect(shouldPrompt(engagement(), feedback(), NOW)).toBe(false);
  });

  it("returns false for a one-day heavy user (single-day rule)", () => {
    const heavyOneDay = engagement({ activeMs: 60 * 60 * 1000, days: ["2026-08-01"], acts: 3 });
    expect(shouldPrompt(heavyOneDay, feedback(), NOW)).toBe(false);
  });

  it("returns false for a two-day light user (under 30 min)", () => {
    const twoDayLight = engagement({
      activeMs: 5 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    expect(shouldPrompt(twoDayLight, feedback(), NOW)).toBe(false);
  });

  it("returns true for a two-day qualifying user", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    expect(shouldPrompt(qualifying, feedback(), NOW)).toBe(true);
  });

  it("returns false when dismissed recently (under 45 days)", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    const dismissedRecently = feedback({ status: "dismissed", dismissals: 1, at: daysAgo(10) });
    expect(shouldPrompt(qualifying, dismissedRecently, NOW)).toBe(false);
  });

  it("returns true when dismissed 45+ days ago", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    const dismissedLongAgo = feedback({ status: "dismissed", dismissals: 1, at: daysAgo(45) });
    expect(shouldPrompt(qualifying, dismissedLongAgo, NOW)).toBe(true);
  });

  it("returns false when dismissed twice, permanently", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    const dismissedTwice = feedback({ status: "dismissed", dismissals: 2, at: daysAgo(100) });
    expect(shouldPrompt(qualifying, dismissedTwice, NOW)).toBe(false);
  });

  it("returns false when dismissed but at is missing (malformed feedback state)", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    const dismissedWithoutTimestamp = feedback({ status: "dismissed", dismissals: 1, at: null });
    expect(shouldPrompt(qualifying, dismissedWithoutTimestamp, NOW)).toBe(false);
  });

  it("returns false when a form is pending", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    expect(shouldPrompt(qualifying, feedback({ status: "pending" }), NOW)).toBe(false);
  });

  it("returns false when a form has been submitted, permanently", () => {
    const qualifying = engagement({
      activeMs: 30 * 60 * 1000,
      days: ["2026-07-31", "2026-08-01"],
      acts: 1,
    });
    expect(shouldPrompt(qualifying, feedback({ status: "submitted" }), NOW)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Chapter ratings (#494)
//
// Unlike shouldPrompt above, these read and write module-level state seeded
// from localStorage at import time. Each test therefore re-imports through
// vi.resetModules() so one test's ratings can't leak into the next, and the
// storage stub has to be installed BEFORE the import for the load path to
// see it.
// ---------------------------------------------------------------------------

function stubStorage(initial) {
  const store = { ...initial };
  globalThis.localStorage = {
    getItem: (key) => (key in store ? store[key] : null),
    setItem: (key, value) => { store[key] = String(value); },
    removeItem: (key) => { delete store[key]; },
  };
  return store;
}

async function freshEngagement(initial) {
  stubStorage(initial);
  vi.resetModules();
  return import("../assets/scripts/engagement.js");
}

describe("chapter ratings", () => {
  afterEach(() => {
    delete globalThis.localStorage;
  });

  it("builds a key matching the ledger's chapter format", async () => {
    const { ratingKey } = await freshEngagement({});
    expect(ratingKey(3, 12)).toBe("3.12");
  });

  it("returns null for an unrated chapter", async () => {
    const { getRating } = await freshEngagement({});
    expect(getRating(3, 12)).toBeNull();
  });

  it("records and reads back a rating", async () => {
    const { getRating, recordRating } = await freshEngagement({});
    recordRating(3, 12, "up");
    expect(getRating(3, 12)).toBe("up");
  });

  it("persists the rating to td:ratings", async () => {
    const store = stubStorage({});
    vi.resetModules();
    const { recordRating } = await import("../assets/scripts/engagement.js");
    recordRating(5, 2, "down");
    expect(JSON.parse(store["td:ratings"])).toEqual({ "5.2": "down" });
  });

  it("restores ratings written by a previous visit", async () => {
    const { getRating } = await freshEngagement({
      "td:ratings": JSON.stringify({ "7.3": "up" }),
    });
    expect(getRating(7, 3)).toBe("up");
  });

  it("ignores a value that isn't up or down", async () => {
    const { getRating, recordRating } = await freshEngagement({});
    recordRating(3, 12, "sideways");
    expect(getRating(3, 12)).toBeNull();
  });

  it("counts a first rating as an act", async () => {
    const { getLedger, recordRating } = await freshEngagement({});
    const before = getLedger().acts;
    recordRating(3, 12, "up");
    expect(getLedger().acts).toBe(before + 1);
  });

  it("does not double-count acts when the same chapter is rated again", async () => {
    const { getLedger, recordRating } = await freshEngagement({});
    recordRating(3, 12, "up");
    const afterFirst = getLedger().acts;
    recordRating(3, 12, "down");
    expect(getLedger().acts).toBe(afterFirst);
    expect(getLedger().acts).toBeGreaterThan(0);
  });

  it("counts separate chapters separately", async () => {
    const { getLedger, recordRating } = await freshEngagement({});
    const before = getLedger().acts;
    recordRating(3, 12, "up");
    recordRating(3, 13, "up");
    expect(getLedger().acts).toBe(before + 2);
  });

  it("resets to empty when stored ratings are unparseable", async () => {
    const { getRatings } = await freshEngagement({ "td:ratings": "{not json" });
    expect(getRatings()).toEqual({});
  });

  it("resets to empty when a stored rating value is invalid", async () => {
    const { getRatings } = await freshEngagement({
      "td:ratings": JSON.stringify({ "3.12": "maybe" }),
    });
    expect(getRatings()).toEqual({});
  });

  it("rejects a stored array, which would otherwise pass a typeof check", async () => {
    const { getRatings } = await freshEngagement({ "td:ratings": "[]" });
    expect(getRatings()).toEqual({});
  });

  it("returns a copy, so callers can't mutate internal state", async () => {
    const { getRatings, getRating, recordRating } = await freshEngagement({});
    recordRating(3, 12, "up");
    const snapshot = getRatings();
    snapshot["3.12"] = "down";
    expect(getRating(3, 12)).toBe("up");
  });
});
