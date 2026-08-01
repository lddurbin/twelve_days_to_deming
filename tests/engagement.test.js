import { describe, it, expect } from "vitest";
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
