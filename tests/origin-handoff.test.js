import { describe, it, expect } from "vitest";
import { isValidAnswers } from "../assets/scripts/workbook.js";

// ---------------------------------------------------------------------------
// origin-handoff.js is a classic script (see its header for why), so it has
// no exports. Importing it runs it; with no `window` in this environment it
// skips the auto-run and only publishes globalThis.tdOriginHandoff.
// ---------------------------------------------------------------------------

// Top-level, not in beforeAll: the it.each tables below are built at
// collection time and already need the encoder.
await import("../assets/scripts/origin-handoff.js");
const H = globalThis.tdOriginHandoff;

// A Storage stand-in with the length/key() that collect() iterates by.
function makeStorage(initial = {}) {
  const store = { ...initial };
  return {
    store,
    get length() { return Object.keys(store).length; },
    key: (i) => Object.keys(store)[i] ?? null,
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
    removeItem: (k) => { delete store[k]; },
  };
}

// Runs send() on the old origin, returning the URL it navigated to.
function sendFrom(oldStorage, { pathname = "/content/days/day-01/01-overture.html", search = "", hash = "" } = {}) {
  let navigated = null;
  let offered = null;
  const location = { pathname, search, hash, replace: (u) => { navigated = u; } };
  const returned = H.send({
    location,
    storage: makeStorage(oldStorage),
    offerDownload: (url, json) => { offered = { url, json }; },
  });
  return { navigated, offered, returned };
}

// Runs receive() on the new origin at `url`, returning the result, the URL
// after replaceState, and the new origin's storage.
function receiveAt(url, { referrer = "https://deming.leedurbin.co.nz/", storage = makeStorage() } = {}) {
  const u = new URL(url);
  let replaced = null;
  const result = H.receive({
    location: { pathname: u.pathname, search: u.search, hash: u.hash },
    history: { state: null, replaceState: (_s, _t, next) => { replaced = next; } },
    document: { referrer },
    storage,
  });
  return { result, replaced, storage };
}

const WORKBOOK = {
  "content/days/day-06/03-activity-6b.qmd#activity_6b_pre": "Rank-and-yank, with “quotes” — and ünïcode 数字",
  "content/days/day-10/02-scoring.qmd#score_a": 4,
  "content/days/day-10/02-scoring.qmd#score_b": null,
};

describe("round trip through the bridge", () => {
  it("carries every td:*, quarto-* and dice key, and restores the page's own fragment", () => {
    const old = {
      "td:workbook": JSON.stringify(WORKBOOK),
      "td:ratings": JSON.stringify({ "1.1": "up" }),
      "td:dyslexic-font": "1",
      "quarto-reader-mode": "true",
      funnel_dice_sequence: "[]",
      "unrelated-key": "left behind",
    };
    const { navigated } = sendFrom(old, { search: "?x=1", hash: "#sec-page3" });
    expect(navigated.startsWith("https://learndeming.org/content/days/day-01/01-overture.html?x=1#td-import=")).toBe(true);

    const { result, replaced, storage } = receiveAt(navigated);
    expect(result.status).toBe("imported");
    expect(replaced).toBe("/content/days/day-01/01-overture.html?x=1#sec-page3");
    expect(JSON.parse(storage.store["td:workbook"])).toEqual(WORKBOOK);
    expect(storage.store["td:dyslexic-font"]).toBe("1");
    expect(storage.store["quarto-reader-mode"]).toBe("true");
    expect(storage.store.funnel_dice_sequence).toBe("[]");
    expect(storage.store).not.toHaveProperty("unrelated-key");
  });

  it("goes straight to the same path, fragment included, when nothing is saved", () => {
    const { navigated } = sendFrom({ "unrelated-key": "x" }, { hash: "#sec-page3" });
    expect(navigated).toBe("https://learndeming.org/content/days/day-01/01-overture.html#sec-page3");
  });

  it("uses only URL-safe characters in the fragment", () => {
    const { navigated } = sendFrom({ "td:workbook": JSON.stringify(WORKBOOK) });
    expect(navigated.split("#td-import=")[1]).toMatch(/^[A-Za-z0-9_-]+$/);
  });
});

describe("receive() guards", () => {
  const good = () => sendFrom({ "td:workbook": JSON.stringify(WORKBOOK) }).navigated;

  it("does nothing without the fragment", () => {
    const { result, replaced } = receiveAt("https://learndeming.org/index.html#sec-intro");
    expect(result.status).toBe("none");
    expect(replaced).toBeNull();
  });

  it.each([
    ["another site", "https://evil.example/"],
    ["no referrer", ""],
    ["the new origin itself", "https://learndeming.org/"],
    ["http on the old host", "http://deming.leedurbin.co.nz/"],
  ])("rejects a referrer from %s, but still strips the fragment", (_label, referrer) => {
    const { result, replaced, storage } = receiveAt(good(), { referrer });
    expect(result.status).toBe("rejected-referrer");
    expect(replaced).toBe("/content/days/day-01/01-overture.html");
    expect(storage.store).toEqual({});
  });

  it.each([
    ["not base64", "#td-import=%%%"],
    ["not JSON", "#td-import=" + btoa("not json")],
    ["wrong version", "#td-import=" + H.encodePayload({ v: 2, data: {} })],
    ["data not an object", "#td-import=" + H.encodePayload({ v: 1, data: [] })],
    ["a key the site doesn't use", "#td-import=" + H.encodePayload({ v: 1, data: { "other:key": "x" } })],
    ["a non-string value", "#td-import=" + H.encodePayload({ v: 1, data: { "td:workbook": { a: 1 } } })],
  ])("rejects a malformed payload: %s", (_label, fragment) => {
    const { result, replaced, storage } = receiveAt("https://learndeming.org/index.html" + fragment);
    expect(result.status).toBe("rejected-payload");
    expect(replaced).toBe("/index.html");
    expect(storage.store).toEqual({});
  });

  it("fails without throwing when storage is unusable", () => {
    const storage = { getItem: () => { throw new Error("disabled"); } };
    const { result } = receiveAt(good(), { storage });
    expect(result.status).toBe("failed");
  });
});

describe("existing data on the new origin is preserved", () => {
  it("never overwrites a whole key that already has a value", () => {
    const url = sendFrom({ "td:dyslexic-font": "1", "td:deviceId": "old-device" }).navigated;
    const storage = makeStorage({ "td:dyslexic-font": "0" });
    const { result } = receiveAt(url, { storage });
    expect(storage.store["td:dyslexic-font"]).toBe("0");
    expect(storage.store["td:deviceId"]).toBe("old-device");
    expect(result.changed).toEqual(["td:deviceId"]);
  });

  it("merges workbook answers field by field, keeping the new origin's own", () => {
    const url = sendFrom({ "td:workbook": JSON.stringify({ a: "old a", b: "old b" }) }).navigated;
    const storage = makeStorage({ "td:workbook": JSON.stringify({ a: "new a", c: "new c" }) });
    receiveAt(url, { storage });
    expect(JSON.parse(storage.store["td:workbook"])).toEqual({ a: "new a", c: "new c", b: "old b" });
  });

  it("merges ratings the same way", () => {
    const url = sendFrom({ "td:ratings": JSON.stringify({ "1.1": "up", "1.2": "down" }) }).navigated;
    const storage = makeStorage({ "td:ratings": JSON.stringify({ "1.1": "down" }) });
    receiveAt(url, { storage });
    expect(JSON.parse(storage.store["td:ratings"])).toEqual({ "1.1": "down", "1.2": "down" });
  });

  it("is idempotent, so a second trip through the bridge changes nothing", () => {
    const url = sendFrom({ "td:workbook": JSON.stringify(WORKBOOK), "td:feedback": "{}" }).navigated;
    const storage = makeStorage();
    receiveAt(url, { storage });
    const once = { ...storage.store };
    const { result } = receiveAt(url, { storage });
    expect(result.changed).toEqual([]);
    expect(storage.store).toEqual(once);
  });

  it("drops an imported workbook with any invalid value, rather than poisoning the existing one", () => {
    const url = sendFrom({ "td:workbook": JSON.stringify({ a: "fine", b: { nested: true } }) }).navigated;
    const storage = makeStorage({ "td:workbook": JSON.stringify({ c: "mine" }) });
    receiveAt(url, { storage });
    expect(JSON.parse(storage.store["td:workbook"])).toEqual({ c: "mine" });
  });

  it("replaces an existing workbook the owner couldn't read anyway", () => {
    const url = sendFrom({ "td:workbook": JSON.stringify({ a: "old a" }) }).navigated;
    const storage = makeStorage({ "td:workbook": "not json" });
    receiveAt(url, { storage });
    expect(JSON.parse(storage.store["td:workbook"])).toEqual({ a: "old a" });
  });
});

describe("the workbook rule matches workbook.js", () => {
  it.each([
    ["a string", "text"],
    ["an empty string", ""],
    ["a number", 3],
    ["zero", 0],
    ["null", null],
    ["a boolean", true],
    ["an object", { a: 1 }],
    ["an array", [1]],
  ])("agrees with isValidAnswers() on %s", (_label, value) => {
    expect(H.workbookValueIsValid(value)).toBe(isValidAnswers({ field: value }));
  });
});

describe("size", () => {
  // The fullest workbook the site can hold: one answer in each of the 412
  // persist() fields, with realistic key lengths.
  function workbookOf(charsPerAnswer) {
    const answers = {};
    for (let i = 0; i < 412; i++) {
      answers[`content/days/day-${String((i % 12) + 1).padStart(2, "0")}/0${i % 9}-activity-${i}.qmd#field_${i}`] =
        "Deming’s point about variation — ".repeat(Math.ceil(charsPerAnswer / 34)).slice(0, charsPerAnswer);
    }
    return JSON.stringify(answers);
  }

  it("carries a heavily used workbook (412 answers of 1,000 characters) in the URL", () => {
    const { navigated, offered } = sendFrom({ "td:workbook": workbookOf(1000) });
    expect(offered).toBeNull();
    expect(navigated.length).toBeLessThan(H.MAX_URL_LENGTH);
    expect(receiveAt(navigated).result.status).toBe("imported");
  });

  it("offers a download instead of navigating when the URL would be too long", () => {
    const { navigated, offered, returned } = sendFrom({ "td:workbook": workbookOf(3000) }, { hash: "#sec-x" });
    expect(navigated).toBeNull();
    expect(returned).toBeNull();
    expect(offered.url).toBe("https://learndeming.org/content/days/day-01/01-overture.html#sec-x");
    expect(Object.keys(JSON.parse(JSON.parse(offered.json)["td:workbook"]))).toHaveLength(412);
  });
});
