import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { downloadNotes } from "../assets/scripts/functions.js";
import { track, pageContext } from "../assets/scripts/telemetry.js";

vi.mock("../assets/scripts/telemetry.js", () => ({
  track: vi.fn(),
  pageContext: vi.fn(() => ({ day: 3, chapter: 1 })),
}));

describe("downloadNotes", () => {
  beforeEach(() => {
    globalThis.document = {
      createElement: vi.fn(() => ({ click: vi.fn() })),
    };
    globalThis.URL = {
      createObjectURL: vi.fn(() => "blob:mock-url"),
      revokeObjectURL: vi.fn(),
    };
    globalThis.alert = vi.fn();
  });

  afterEach(() => {
    delete globalThis.document;
    delete globalThis.URL;
    delete globalThis.alert;
    track.mockClear();
    pageContext.mockClear();
  });

  it("does not track when the notes are empty", () => {
    downloadNotes([{ value: "   " }], "notes.txt");
    expect(globalThis.alert).toHaveBeenCalled();
    expect(track).not.toHaveBeenCalled();
  });

  it("fires Notes downloaded with pageContext() once per successful download", () => {
    downloadNotes([{ value: "Some notes" }], "notes.txt");
    expect(track).toHaveBeenCalledTimes(1);
    expect(track).toHaveBeenCalledWith("Notes downloaded", { day: 3, chapter: 1 });
  });
});
