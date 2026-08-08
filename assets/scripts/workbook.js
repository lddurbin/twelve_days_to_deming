// ============================================================
// Workbook (prototype, #530) — keyed persistence for reader-written OJS
// inputs.
//
// Wraps an already-constructed Inputs.* element rather than building one
// itself: `persist(key, Inputs.textarea({...}))`, not
// `persistedTextarea(key, {...})`. Two reasons:
//
//   1. It works identically for Inputs.textarea, Inputs.text and
//      Inputs.number with one function, since all it touches is the
//      generic "view" contract (readable/settable .value, dispatches
//      "input" on change) — never the Inputs.* constructors themselves.
//   2. `Inputs` is a global Quarto's OJS runtime injects only inside
//      {ojs} cells, the same way d3/Plot/html/md are. A plain ES module
//      like this one, loaded via ordinary `import`, has no access to it —
//      so the cell has to call Inputs.textarea() itself and hand persist()
//      the result.
//
// This is the working proof for #530's recommendation, not the production
// helper. #538 builds that, informed by whatever this surfaces (likely a
// richer storage shape and real tests). Scratch-branch only — not wired
// into any chapter on main.
// ============================================================

import { safeGet, safeSet } from "./storage.js";

const STORAGE_KEY = "td:workbook";
const SAVE_DEBOUNCE_MS = 400;

// One JSON object, `{ key: value }`, rather than one localStorage entry per
// field — matches the td:ratings shape in engagement.js, and means "export
// all my answers" and "delete all my answers" (#545, #547) are both a
// single whole-object operation instead of a scan over hundreds of keys.
function isValidAnswers(value) {
  return (
    value !== null &&
    typeof value === "object" &&
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

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

const scheduleSave = debounce(saveAnswers, SAVE_DEBOUNCE_MS);

// key: stable field identity, e.g.
//   "content/days/day-06/03-activity-6b.qmd#activity_6b_pre"
// input: the return value of an Inputs.textarea/text/number call.
//
// Returns the same element, unchanged in every other respect, so
// `viewof name = persist(key, Inputs.textarea({...}))` binds exactly as
// `viewof name = Inputs.textarea({...})` would have. downloadNotes (and
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
// keystroke inside the last SAVE_DEBOUNCE_MS window before navigation isn't
// lost. Doesn't affect downloadNotes either way — that reads input.value
// live off the DOM, never off storage.
if (typeof document !== "undefined") {
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") saveAnswers();
  });
}
