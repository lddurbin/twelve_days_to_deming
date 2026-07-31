import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { track, pageContext, handleCommentaryReveal } from "../assets/scripts/telemetry.js";

// ---------------------------------------------------------------------------
// track
// ---------------------------------------------------------------------------
describe("track", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.runAllTimers(); // fully drain any recursive retry chain queued by this test before the next one runs
    vi.useRealTimers();
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
// track — queueing before sa_event is ready
//
// latest.js loads async, so a call made in the first moment after page
// load can arrive before window.sa_event exists. These cover the retry
// queue that catches that race instead of silently dropping the event.
// ---------------------------------------------------------------------------
describe("track — queueing before sa_event is ready", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.runOnlyPendingTimers(); // drain any in-flight retry chain before the next test
    vi.useRealTimers();
    delete globalThis.window;
  });

  it("queues a call made before sa_event exists and sends it once sa_event appears", () => {
    globalThis.window = {};
    track("Notes downloaded", { day: 3 });

    const sa_event = vi.fn();
    globalThis.window.sa_event = sa_event;
    vi.advanceTimersByTime(100); // first retry check

    expect(sa_event).toHaveBeenCalledTimes(1);
    expect(sa_event).toHaveBeenCalledWith("Notes downloaded", { day: 3 });
  });

  it("flushes multiple queued calls in order once sa_event appears", () => {
    globalThis.window = {};
    track("Notes downloaded");
    track("Commentary revealed", { activity: "3a" });

    const sa_event = vi.fn();
    globalThis.window.sa_event = sa_event;
    vi.advanceTimersByTime(100);

    expect(sa_event).toHaveBeenNthCalledWith(1, "Notes downloaded");
    expect(sa_event).toHaveBeenNthCalledWith(2, "Commentary revealed", { activity: "3a" });
  });

  it("gives up after the retry window and does not throw when sa_event never appears", () => {
    globalThis.window = {};
    expect(() => track("Notes downloaded")).not.toThrow();
    expect(() => vi.advanceTimersByTime(10000)).not.toThrow();
  });

  it("does not replay a given-up call once sa_event eventually appears", () => {
    globalThis.window = {};
    track("Notes downloaded");
    vi.advanceTimersByTime(10000); // exhaust all retries — queued call is dropped

    const sa_event = vi.fn();
    globalThis.window.sa_event = sa_event;
    vi.advanceTimersByTime(10000); // nothing left scheduled to flush it

    expect(sa_event).not.toHaveBeenCalled();
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
