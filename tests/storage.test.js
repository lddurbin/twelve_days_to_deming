import { describe, it, expect, afterEach } from "vitest";
import { safeGet, safeSet } from "../assets/scripts/storage.js";

afterEach(() => {
  delete globalThis.localStorage;
});

// ---------------------------------------------------------------------------
// safeGet
// ---------------------------------------------------------------------------
describe("safeGet", () => {
  it("returns null when localStorage is unavailable", () => {
    expect(safeGet("td:example")).toBeNull();
  });

  it("returns the stored value", () => {
    globalThis.localStorage = { getItem: () => "1" };
    expect(safeGet("td:example")).toBe("1");
  });

  it("returns null when localStorage.getItem throws", () => {
    globalThis.localStorage = {
      getItem: () => { throw new Error("disabled"); },
    };
    expect(safeGet("td:example")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// safeSet
// ---------------------------------------------------------------------------
describe("safeSet", () => {
  it("does not throw when localStorage is unavailable", () => {
    expect(() => safeSet("td:example", "1")).not.toThrow();
  });

  it("calls setItem when value is non-null", () => {
    const setItem = (key, value) => {
      expect(key).toBe("td:example");
      expect(value).toBe("1");
    };
    globalThis.localStorage = { setItem, removeItem: () => { throw new Error("should not be called"); } };
    safeSet("td:example", "1");
  });

  it("calls removeItem when value is null", () => {
    const removeItem = (key) => {
      expect(key).toBe("td:example");
    };
    globalThis.localStorage = { removeItem, setItem: () => { throw new Error("should not be called"); } };
    safeSet("td:example", null);
  });

  it("does not throw when localStorage.setItem throws", () => {
    globalThis.localStorage = {
      setItem: () => { throw new Error("disabled"); },
    };
    expect(() => safeSet("td:example", "1")).not.toThrow();
  });
});
