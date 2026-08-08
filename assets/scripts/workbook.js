// ============================================================
// Workbook — keyed localStorage persistence for reader-written OJS
// inputs (activity textareas, scoring tables, etc).
//
// Wraps an already-constructed Inputs.* element rather than building one
// itself: `persist(key, Inputs.textarea({...}))`. Two reasons:
//
//   1. It works identically for Inputs.textarea, Inputs.text and
//      Inputs.number with one function, since all it touches is the
//      generic "view" contract (readable/settable .value, dispatches
//      "input" on change) — never the Inputs.* constructors themselves.
//   2. `Inputs` is a global Quarto's OJS runtime injects only inside
//      {ojs} cells, the same way d3/Plot/html/md are. A plain ES module
//      like this one, loaded via ordinary `import`, has no access to it —
//      so the cell calls Inputs.textarea() itself and hands the result to
//      persist().
//
// Key format: full repo-relative path + ".qmd" + the existing `viewof`
// name, e.g. "content/days/day-06/03-activity-6b.qmd#activity_6b_pre" —
// see #530 for why (a full path keys English and French answers apart for
// free once content-fr/ fills in). Keys are supplied by the caller, not
// derived here — a rename or split therefore orphans the keys it touches,
// a deliberate trade recorded in #530; the mitigation is a migration map
// applied at read time, not yet needed since no field has moved.
//
// Only one {ojs} cell per file should `import { persist }`. Quarto's OJS
// runtime treats an `import` inside an {ojs} cell as document-scoped, not
// cell-scoped, so importing it in more than one cell in the same file
// throws "persist is defined more than once" at render time — see #530.
// ============================================================

import { safeGet, safeSet } from "./storage.js";

const STORAGE_KEY = "td:workbook";
const SAVE_DEBOUNCE_MS = 400;

// One JSON object, `{ key: value }`, rather than one localStorage entry
// per field — matches td:ratings' shape in engagement.js, and means
// "export/delete all my answers" (#545, #547) is a single whole-object
// operation instead of a scan over hundreds of keys.
function isValidAnswers(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    // typeof [] is also "object", and an array would survive every check
    // below (no entries to iterate), so it has to be excluded explicitly.
    !Array.isArray(value) &&
    Object.values(value).every((v) => typeof v === "string")
  );
}

function loadAnswers() {
  const raw = safeGet(STORAGE_KEY);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return isValidAnswers(parsed) ? parsed : {};
  } catch (e) {
    return {};
  }
}

let answers = loadAnswers();

function saveAnswers() {
  safeSet(STORAGE_KEY, JSON.stringify(answers));
}

export function getAnswers() {
  return structuredClone(answers);
}

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

const scheduleSave = debounce(saveAnswers, SAVE_DEBOUNCE_MS);

// key: stable field identity (see header comment).
// input: the return value of an Inputs.textarea/text/number call.
//
// Returns the same element, unchanged in every other respect, so
// `viewof name = persist(key, Inputs.textarea({...}))` binds exactly as
// `viewof name = Inputs.textarea({...})` would have — downloadNotes (and
// anything else consuming `viewof name`) sees no difference.
export function persist(key, input) {
  const stored = answers[key];
  if (stored !== undefined) input.value = stored;

  input.addEventListener("input", () => {
    answers[key] = input.value;
    scheduleSave();
  });

  return input;
}

// Flushes a pending debounced save immediately on tab hide/close, so a
// keystroke inside the last SAVE_DEBOUNCE_MS window before navigation
// isn't lost. Doesn't affect downloadNotes either way — that reads
// input.value live off the DOM, never off storage.
if (typeof document !== "undefined") {
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") saveAnswers();
  });
}
