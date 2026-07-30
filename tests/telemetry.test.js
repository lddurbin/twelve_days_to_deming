import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { track, pageContext, handleCommentaryReveal } from "../assets/scripts/telemetry.js";

// ---------------------------------------------------------------------------
// track
// ---------------------------------------------------------------------------
describe("track", () => {
  afterEach(() => {
    delete globalThis.window;
  });

  it("does not throw when window is undefined", () => {
    expect(() => track("Notes downloaded")).not.toThrow();
  });

  it("does not throw when window.sa_event is missing", () => {
    globalThis.window = { location: { pathname: "/" } };
    expect(() => track("Notes downloaded")).not.toThrow();
  });

  it("does not throw when window.sa_event is not a function", () => {
    globalThis.window = { sa_event: null };
    expect(() => track("Notes downloaded")).not.toThrow();
  });

  it("does not throw when window.sa_event throws", () => {
    globalThis.window = {
      sa_event: () => { throw new Error("blocked"); },
    };
    expect(() => track("Notes downloaded")).not.toThrow();
  });

  it("calls sa_event with just the name when no props are given", () => {
    const sa_event = vi.fn();
    globalThis.window = { sa_event };
    track("Notes downloaded");
    expect(sa_event).toHaveBeenCalledWith("Notes downloaded");
  });

  it("calls sa_event with name and props when props are given", () => {
    const sa_event = vi.fn();
    globalThis.window = { sa_event };
    track("Notes downloaded", { day: 3 });
    expect(sa_event).toHaveBeenCalledWith("Notes downloaded", { day: 3 });
  });
});

// ---------------------------------------------------------------------------
// pageContext
// ---------------------------------------------------------------------------
describe("pageContext", () => {
  afterEach(() => {
    delete globalThis.window;
  });

  it("returns nulls when window is undefined", () => {
    expect(pageContext()).toEqual({ day: null, chapter: null });
  });

  it("returns nulls for a non-chapter page", () => {
    globalThis.window = { location: { pathname: "/welcome.html" } };
    expect(pageContext()).toEqual({ day: null, chapter: null });
  });

  it("derives day and chapter from a chapter URL", () => {
    globalThis.window = {
      location: {
        pathname: "/content/days/day-03/12-rules-3-and-4-of-the-funnel.html",
      },
    };
    expect(pageContext()).toEqual({ day: 3, chapter: 12 });
  });

  it("parses double-digit days and single-digit chapters", () => {
    globalThis.window = {
      location: { pathname: "/content/days/day-12/06-activity-12d.html" },
    };
    expect(pageContext()).toEqual({ day: 12, chapter: 6 });
  });
});

// ---------------------------------------------------------------------------
// handleCommentaryReveal
// ---------------------------------------------------------------------------
describe("handleCommentaryReveal", () => {
  afterEach(() => {
    delete globalThis.window;
  });

  it("does nothing when the click did not land on a reveal button", () => {
    // closest() returning null covers both "clicked elsewhere" and "clicked
    // a non-reveal collapse toggle" (e.g. Quarto's own sidebar TOC sections,
    // which also carry data-bs-toggle="collapse" but don't match the
    // "#collapse_" target-id convention the real selector requires).
    const sa_event = vi.fn();
    globalThis.window = { sa_event };
    handleCommentaryReveal({ target: { closest: () => null } });
    expect(sa_event).not.toHaveBeenCalled();
  });

  it("fires Commentary revealed with day, chapter and the activity id", () => {
    const sa_event = vi.fn();
    globalThis.window = {
      sa_event,
      location: {
        pathname: "/content/days/day-03/01-variation-the-enemy-of-quality.html",
      },
    };
    const button = {
      getAttribute: (name) => (name === "data-bs-target" ? "#collapse_3a" : null),
    };
    handleCommentaryReveal({ target: { closest: () => button } });
    expect(sa_event).toHaveBeenCalledWith("Commentary revealed", {
      day: 3,
      chapter: 1,
      activity: "3a",
    });
  });
});
