import { describe, it, expect, afterEach, vi } from "vitest";
import { attachRatingClicks } from "../assets/scripts/cooperation-tables.js";
import { track, pageContext } from "../assets/scripts/telemetry.js";

vi.mock("../assets/scripts/telemetry.js", () => ({
  track: vi.fn(),
  pageContext: vi.fn(() => ({ day: 8, chapter: 6 })),
}));

// A minimal fake container: only the ".rating-cell:not(.own-area)" query needs
// real cells, since attachRatingClicks and computeNetEffects (called from
// inside the click handler) don't need anything else to exercise the
// tracking call — every other selector's result is unused once found empty.
function makeContainer(cells) {
  return {
    querySelectorAll: (selector) =>
      selector === ".rating-cell:not(.own-area)" ? cells : [],
    querySelector: () => null,
  };
}

function makeCell() {
  const handlers = {};
  return {
    dataset: { area: "0", option: "0", col: "1", rating: "" },
    className: "",
    textContent: "",
    setAttribute: vi.fn(),
    addEventListener: vi.fn((event, handler) => {
      handlers[event] = handler;
    }),
    _handlers: handlers,
  };
}

describe("attachRatingClicks", () => {
  afterEach(() => {
    track.mockClear();
    pageContext.mockClear();
  });

  it("does not track merely from attaching handlers (page load)", () => {
    const cell = makeCell();
    attachRatingClicks(makeContainer([cell]), ["Sales", "Admin"]);
    expect(track).not.toHaveBeenCalled();
  });

  it("fires Cooperation table used with pageContext() on a click activation", () => {
    const cell = makeCell();
    attachRatingClicks(makeContainer([cell]), ["Sales", "Admin"]);
    cell._handlers.click();
    expect(track).toHaveBeenCalledTimes(1);
    expect(track).toHaveBeenCalledWith("Cooperation table used", { day: 8, chapter: 6 });
  });

  it("fires on keyboard activation (Enter/Space) as well as click", () => {
    const cell = makeCell();
    attachRatingClicks(makeContainer([cell]), ["Sales", "Admin"]);
    const preventDefault = vi.fn();
    cell._handlers.keydown({ key: "Enter", preventDefault });
    expect(preventDefault).toHaveBeenCalled();
    expect(track).toHaveBeenCalledTimes(1);
  });

  it("does not track on keydown for keys other than Enter/Space", () => {
    const cell = makeCell();
    attachRatingClicks(makeContainer([cell]), ["Sales", "Admin"]);
    cell._handlers.keydown({ key: "Tab", preventDefault: vi.fn() });
    expect(track).not.toHaveBeenCalled();
  });

  it("fires again on each subsequent rating cycle", () => {
    const cell = makeCell();
    attachRatingClicks(makeContainer([cell]), ["Sales", "Admin"]);
    cell._handlers.click();
    cell._handlers.click();
    cell._handlers.click();
    expect(track).toHaveBeenCalledTimes(3);
  });
});
