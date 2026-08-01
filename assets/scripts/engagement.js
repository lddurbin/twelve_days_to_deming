// ============================================================
// Engagement — on-device ledger of active reading time, distinct
// days returned, chapters seen, and content interactions ("acts").
//
// This never leaves the reader's device: it exists to drive a later
// feedback-prompt predicate purely from local state, which is also why it
// needs no CSP change and no consent banner. See telemetry.js for the
// vendor-facing analytics wrapper this is deliberately separate from.
// ============================================================

import { safeGet, safeSet } from "./storage.js";
import { pageContext } from "./telemetry.js";

const STORAGE_KEY = "td:engagement";
const HEARTBEAT_MS = 5000;
const IDLE_THRESHOLD_MS = 60000;

function freshLedger() {
  return {
    firstSeen: new Date().toISOString(),
    activeMs: 0,
    days: [],
    chapters: [],
    acts: 0,
    maxDay: 0,
  };
}

function isValidLedger(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    typeof value.firstSeen === "string" &&
    typeof value.activeMs === "number" &&
    Array.isArray(value.days) &&
    Array.isArray(value.chapters) &&
    typeof value.acts === "number" &&
    typeof value.maxDay === "number"
  );
}

function loadLedger() {
  const raw = safeGet(STORAGE_KEY);
  if (!raw) return freshLedger();
  try {
    const parsed = JSON.parse(raw);
    return isValidLedger(parsed) ? parsed : freshLedger();
  } catch (e) {
    return freshLedger();
  }
}

let ledger = loadLedger();

function persist() {
  safeSet(STORAGE_KEY, JSON.stringify(ledger));
}

export function getLedger() {
  return structuredClone(ledger);
}

// Local calendar date, not UTC — "a distinct day returned" should match the
// reader's own clock, not a timezone-shifted one.
function todayKey(now) {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function recordVisit() {
  const day = todayKey(new Date());
  if (!ledger.days.includes(day)) ledger.days.push(day);

  const { day: courseDay, chapter } = pageContext();
  if (courseDay !== null) {
    ledger.maxDay = Math.max(ledger.maxDay, courseDay);
    if (chapter !== null) {
      const key = `${courseDay}.${chapter}`;
      if (!ledger.chapters.includes(key)) ledger.chapters.push(key);
    }
  }
  persist();
}

// Called from the notes-download, funnel-run, and cooperation-table hooks
// (functions.js, funnel-experiment.js, cooperation-tables.js) plus this
// module's own commentary-reveal listener below.
export function recordAct() {
  ledger.acts += 1;
  persist();
}

// ---------------------------------------------------------------
// Active-time heartbeat. Counts a tick only while the tab is visible AND
// there's been scroll/keyboard/pointer/click input within the last minute,
// so an open-but-idle foreground tab doesn't inflate active time.
// ---------------------------------------------------------------

let lastInputAt = Date.now();
function markInput() {
  lastInputAt = Date.now();
}

const INPUT_EVENTS = ["scroll", "keydown", "pointermove", "click"];

function startHeartbeat() {
  INPUT_EVENTS.forEach((type) => {
    document.addEventListener(type, markInput, { passive: true });
  });
  let lastTick = Date.now();
  setInterval(() => {
    const now = Date.now();
    // setInterval isn't exact - main-thread jank can delay a tick by a few
    // hundred ms, and a backgrounded/suspended tab can delay one by much
    // more. Measure the real gap so normal jitter is credited accurately,
    // but clamp it so a long-suspended tick (tab hidden, laptop asleep)
    // never gets credited as active time once visibility returns.
    const elapsed = Math.min(now - lastTick, HEARTBEAT_MS * 1.5);
    lastTick = now;
    const idleFor = now - lastInputAt;
    if (document.visibilityState === "visible" && idleFor <= IDLE_THRESHOLD_MS) {
      ledger.activeMs += elapsed;
      persist();
    }
  }, HEARTBEAT_MS);
}

// Same selector as telemetry.js's handleCommentaryReveal, duplicated rather
// than imported: engagement.js already imports pageContext from telemetry.js,
// so importing this listener back the other way would create a cycle.
const REVEAL_SELECTOR = '[data-bs-toggle="collapse"][data-bs-target^="#collapse_"]';

function handleCommentaryReveal(event) {
  if (event.target.closest(REVEAL_SELECTOR)) recordAct();
}

// Loaded as type="module" — see telemetry.js for the timing caveat. Guarded
// on `document` (rather than `window`) since every side effect below is
// DOM-driven and this also keeps the module import side-effect-free under
// Node/vitest, where `document` is undefined.
if (typeof document !== "undefined") {
  recordVisit();
  startHeartbeat();
  document.addEventListener("click", handleCommentaryReveal);
}
