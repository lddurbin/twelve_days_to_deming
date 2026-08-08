import { describe, it, expect, afterEach, vi } from "vitest";

// ---------------------------------------------------------------------------
// workbook.js keeps its answers in module-level state, seeded from
// localStorage at import time (same shape as engagement.js's ledger/ratings).
// Each test that cares about that state re-imports through
// vi.resetModules() so one test's writes can't leak into the next, and the
// storage stub has to be installed BEFORE the import for the load path to
// see it — mirroring the freshEngagement() helper in engagement.test.js.
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

async function freshWorkbook(initial) {
  stubStorage(initial);
  vi.resetModules();
  return import("../assets/scripts/workbook.js");
}

// A minimal stand-in for an Inputs.textarea()/text()/number() return value:
// a settable .value plus the "input" event persist() listens for. Node's
// built-in EventTarget/Event give real addEventListener/dispatchEvent
// semantics without needing a DOM.
function fakeInput(initialValue = "") {
  const target = new EventTarget();
  target.value = initialValue;
  return target;
}

function typeInto(input, value) {
  input.value = value;
  input.dispatchEvent(new Event("input"));
}

afterEach(() => {
  delete globalThis.localStorage;
  vi.useRealTimers();
});

// ---------------------------------------------------------------------------
// persist — restore
// ---------------------------------------------------------------------------
describe("persist — restore", () => {
  it("pre-fills input.value from a previously stored answer", async () => {
    const { persist } = await freshWorkbook({
      "td:workbook": JSON.stringify({ "day-06#a": "existing answer" }),
    });
    const input = persist("day-06#a", fakeInput(""));
    expect(input.value).toBe("existing answer");
  });

  it("leaves input.value untouched when no stored answer exists for the key", async () => {
    const { persist } = await freshWorkbook({});
    const input = persist("day-06#a", fakeInput("placeholder default"));
    expect(input.value).toBe("placeholder default");
  });

  it("returns the same element instance it was given, unmodified otherwise", async () => {
    const { persist } = await freshWorkbook({});
    const input = fakeInput("");
    expect(persist("day-06#a", input)).toBe(input);
  });
});

// ---------------------------------------------------------------------------
// persist — keyed save, debounced
// ---------------------------------------------------------------------------
describe("persist — save", () => {
  it("stores a typed value under exactly the given key", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("content/days/day-06/01-introduction.qmd#activity_6a", fakeInput(""));
    typeInto(input, "hello");
    vi.advanceTimersByTime(400);

    expect(JSON.parse(store["td:workbook"])).toEqual({
      "content/days/day-06/01-introduction.qmd#activity_6a": "hello",
    });
  });

  it("does not write to storage before the debounce window elapses", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("day-06#a", fakeInput(""));
    typeInto(input, "mid-keystroke");

    expect(store["td:workbook"]).toBeUndefined();
  });

  it("collapses rapid keystrokes into a single save of the final value", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("day-06#a", fakeInput(""));
    typeInto(input, "h");
    vi.advanceTimersByTime(100);
    typeInto(input, "he");
    vi.advanceTimersByTime(100);
    typeInto(input, "hel");
    vi.advanceTimersByTime(400);

    expect(JSON.parse(store["td:workbook"])).toEqual({ "day-06#a": "hel" });
  });

  it("keeps two different keys independent — no collisions", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const pre = persist("content/days/day-06/03-activity-6b.qmd#activity_6b_pre", fakeInput(""));
    const post = persist("content/days/day-06/03-activity-6b.qmd#activity_6b_post", fakeInput(""));
    typeInto(pre, "pre-Deming notes");
    typeInto(post, "post-Deming notes");
    vi.advanceTimersByTime(400);

    expect(JSON.parse(store["td:workbook"])).toEqual({
      "content/days/day-06/03-activity-6b.qmd#activity_6b_pre": "pre-Deming notes",
      "content/days/day-06/03-activity-6b.qmd#activity_6b_post": "post-Deming notes",
    });
  });

  it("saves and restores a numeric value (Inputs.number) alongside a string field", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const textInput = persist("day-06#a", fakeInput(""));
    const numberInput = persist("day-06#b", fakeInput(0));
    typeInto(textInput, "a textarea answer");
    typeInto(numberInput, 42);
    vi.advanceTimersByTime(400);

    expect(JSON.parse(store["td:workbook"])).toEqual({
      "day-06#a": "a textarea answer",
      "day-06#b": 42,
    });

    // Simulate a reload: re-import against the same store.
    vi.resetModules();
    const { persist: persistAfterReload } = await import("../assets/scripts/workbook.js");
    const restoredText = persistAfterReload("day-06#a", fakeInput(""));
    const restoredNumber = persistAfterReload("day-06#b", fakeInput(0));
    expect(restoredText.value).toBe("a textarea answer");
    expect(restoredNumber.value).toBe(42);
  });

  it("saves and restores a cleared Inputs.number field (null) without invalidating a sibling field", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const textInput = persist("day-06#a", fakeInput(""));
    const numberInput = persist("day-06#b", fakeInput(0));
    typeInto(textInput, "a textarea answer");
    typeInto(numberInput, 42);
    vi.advanceTimersByTime(400);
    // Reader clears the number field — Inputs.number reports null, not 0 or NaN.
    typeInto(numberInput, null);
    vi.advanceTimersByTime(400);

    expect(JSON.parse(store["td:workbook"])).toEqual({
      "day-06#a": "a textarea answer",
      "day-06#b": null,
    });

    vi.resetModules();
    const { persist: persistAfterReload } = await import("../assets/scripts/workbook.js");
    const restoredText = persistAfterReload("day-06#a", fakeInput(""));
    const restoredNumber = persistAfterReload("day-06#b", fakeInput(0));
    expect(restoredText.value).toBe("a textarea answer");
    expect(restoredNumber.value).toBeNull();
  });

  it("does not throw when localStorage.setItem throws (quota exceeded)", async () => {
    vi.useFakeTimers();
    globalThis.localStorage = {
      getItem: () => null,
      setItem: () => { throw new Error("QuotaExceededError"); },
      removeItem: () => {},
    };
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("day-06#a", fakeInput(""));
    expect(() => {
      typeInto(input, "still typed even though storage is full");
      vi.advanceTimersByTime(400);
    }).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// corrupt-data fallback
// ---------------------------------------------------------------------------
describe("corrupt-data fallback", () => {
  it("falls back to empty when localStorage has nothing stored", async () => {
    const { getAnswers } = await freshWorkbook({});
    expect(getAnswers()).toEqual({});
  });

  it("falls back to empty when stored JSON is unparseable", async () => {
    const { getAnswers } = await freshWorkbook({ "td:workbook": "{not json" });
    expect(getAnswers()).toEqual({});
  });

  it("falls back to empty when stored data is an array", async () => {
    const { getAnswers } = await freshWorkbook({ "td:workbook": "[]" });
    expect(getAnswers()).toEqual({});
  });

  it("falls back to empty when stored data is not an object", async () => {
    const { getAnswers } = await freshWorkbook({ "td:workbook": "42" });
    expect(getAnswers()).toEqual({});
  });

  it("falls back to empty when a stored value is neither a string, a number, nor null", async () => {
    const { getAnswers } = await freshWorkbook({
      "td:workbook": JSON.stringify({ "day-06#a": true }),
    });
    expect(getAnswers()).toEqual({});
  });

  it("restores cleanly when stored data is valid", async () => {
    const { getAnswers } = await freshWorkbook({
      "td:workbook": JSON.stringify({ "day-06#a": "valid answer" }),
    });
    expect(getAnswers()).toEqual({ "day-06#a": "valid answer" });
  });

  it("accepts a numeric value (Inputs.number) without invalidating the rest of the store", async () => {
    const { getAnswers } = await freshWorkbook({
      "td:workbook": JSON.stringify({ "day-06#a": "a textarea answer", "day-06#b": 42 }),
    });
    expect(getAnswers()).toEqual({ "day-06#a": "a textarea answer", "day-06#b": 42 });
  });

  it("accepts a null value (cleared Inputs.number) without invalidating the rest of the store", async () => {
    const { getAnswers } = await freshWorkbook({
      "td:workbook": JSON.stringify({ "day-06#a": "a textarea answer", "day-06#b": null }),
    });
    expect(getAnswers()).toEqual({ "day-06#a": "a textarea answer", "day-06#b": null });
  });
});

// ---------------------------------------------------------------------------
// getAnswers
// ---------------------------------------------------------------------------
describe("getAnswers", () => {
  it("returns a copy, so callers can't mutate internal state", async () => {
    vi.useFakeTimers();
    const { persist, getAnswers } = await freshWorkbook({});
    const input = persist("day-06#a", fakeInput(""));
    typeInto(input, "original");
    vi.advanceTimersByTime(400);

    const snapshot = getAnswers();
    snapshot["day-06#a"] = "tampered";
    expect(getAnswers()).toEqual({ "day-06#a": "original" });
  });
});

// ---------------------------------------------------------------------------
// visibilitychange flush — saves a pending debounced write immediately on
// tab hide, so a keystroke inside the last SAVE_DEBOUNCE_MS window before
// navigation isn't lost.
// ---------------------------------------------------------------------------
describe("visibilitychange flush", () => {
  function fakeDocument() {
    const listeners = {};
    return {
      addEventListener: (type, cb) => { listeners[type] = cb; },
      fire: (type) => listeners[type]?.(),
      visibilityState: "visible",
    };
  }

  afterEach(() => {
    delete globalThis.document;
  });

  it("flushes a pending debounced save when the tab becomes hidden", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    const doc = fakeDocument();
    globalThis.document = doc;
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("day-06#a", fakeInput(""));
    typeInto(input, "about to navigate away");
    // No timer advance — the debounced save is still pending.
    expect(store["td:workbook"]).toBeUndefined();

    doc.visibilityState = "hidden";
    doc.fire("visibilitychange");

    expect(JSON.parse(store["td:workbook"])).toEqual({ "day-06#a": "about to navigate away" });
  });

  it("does not flush when the tab becomes visible again, not hidden", async () => {
    vi.useFakeTimers();
    const store = stubStorage({});
    const doc = fakeDocument();
    globalThis.document = doc;
    vi.resetModules();
    const { persist } = await import("../assets/scripts/workbook.js");

    const input = persist("day-06#a", fakeInput(""));
    typeInto(input, "still typing");
    doc.visibilityState = "visible";
    doc.fire("visibilitychange");

    expect(store["td:workbook"]).toBeUndefined();
  });
});
