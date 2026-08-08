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

// ---------------------------------------------------------------
// Per-device identity — a stable id generated once per device and kept in
// its own storage key, not inside the ledger itself. It has to live outside
// the ledger's own merge fields: it identifies *this* device across merges
// rather than being data that merges, and embedding it in the ledger would
// leave no principled way to pick a winner when two ledgers combine.
// ---------------------------------------------------------------

const DEVICE_ID_STORAGE_KEY = "td:deviceId";

function generateDeviceId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  // crypto.randomUUID needs a secure context; this fallback only needs to
  // be stable and distinct enough to key a merge map by, not unguessable.
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

let cachedDeviceId = null;

function getDeviceId() {
  if (cachedDeviceId) return cachedDeviceId;
  cachedDeviceId = safeGet(DEVICE_ID_STORAGE_KEY) || generateDeviceId();
  safeSet(DEVICE_ID_STORAGE_KEY, cachedDeviceId);
  return cachedDeviceId;
}

// ---------------------------------------------------------------
// Ledger — activeMs and acts are stored as per-device grow-only counters
// (a map of deviceId -> value, each device only ever incrementing its own
// entry) rather than plain numbers. days[]/chapters[] are already grow-only
// sets and maxDay is already a maximum, so those three merge correctly by
// construction; a plain counter doesn't, since overlapping activity across
// two devices makes max() undercount and sum() double-count. See
// mergeLedgers below. getLedger() sums each map back into a plain number,
// so this stays invisible to every existing caller.
// ---------------------------------------------------------------

function freshLedger() {
  return {
    firstSeen: new Date().toISOString(),
    activeMsByDevice: {},
    days: [],
    chapters: [],
    actsByDevice: {},
    maxDay: 0,
  };
}

// {} passes (every() on an empty array is vacuously true) - that's the
// correct read for a fresh ledger's empty maps, not an oversight.
// Number.isFinite (not just typeof) excludes Infinity, which JSON.parse can
// legitimately produce from an oversized literal like 1e400 - unlike NaN,
// which isn't valid JSON syntax and so can never reach here.
function isCounterMap(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.values(value).every((v) => typeof v === "number" && Number.isFinite(v))
  );
}

function isValidLedger(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    typeof value.firstSeen === "string" &&
    isCounterMap(value.activeMsByDevice) &&
    Array.isArray(value.days) &&
    Array.isArray(value.chapters) &&
    isCounterMap(value.actsByDevice) &&
    typeof value.maxDay === "number"
  );
}

// Pre-#546 shape: activeMs/acts were plain numbers. Detected by field type
// rather than a version flag, since none was ever recorded. Number.isFinite
// guards against a 1e400-style overflowed literal migrating straight into
// shouldPrompt()'s threshold comparisons - see isCounterMap above.
function isLegacyLedger(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    typeof value.firstSeen === "string" &&
    typeof value.activeMs === "number" &&
    Number.isFinite(value.activeMs) &&
    Array.isArray(value.days) &&
    Array.isArray(value.chapters) &&
    typeof value.acts === "number" &&
    Number.isFinite(value.acts) &&
    typeof value.maxDay === "number"
  );
}

// One-way, forward-only: a legacy single-counter ledger had exactly one
// device writing to it (this one), so its whole counter becomes that
// device's opening entry in the new map. No path back to the old shape.
function migrateLedger(legacy) {
  const id = getDeviceId();
  return {
    firstSeen: legacy.firstSeen,
    activeMsByDevice: { [id]: legacy.activeMs },
    days: legacy.days,
    chapters: legacy.chapters,
    actsByDevice: { [id]: legacy.acts },
    maxDay: legacy.maxDay,
  };
}

function loadLedger() {
  const raw = safeGet(STORAGE_KEY);
  if (!raw) return freshLedger();
  try {
    const parsed = JSON.parse(raw);
    if (isValidLedger(parsed)) return parsed;
    if (isLegacyLedger(parsed)) return migrateLedger(parsed);
    return freshLedger();
  } catch (e) {
    return freshLedger();
  }
}

let ledger = loadLedger();

function persist() {
  safeSet(STORAGE_KEY, JSON.stringify(ledger));
}

function sumCounter(map) {
  return Object.values(map).reduce((total, value) => total + value, 0);
}

export function getLedger() {
  return {
    firstSeen: ledger.firstSeen,
    activeMs: sumCounter(ledger.activeMsByDevice),
    days: [...ledger.days],
    chapters: [...ledger.chapters],
    acts: sumCounter(ledger.actsByDevice),
    maxDay: ledger.maxDay,
  };
}

function unionCounterMap(a, b) {
  const merged = { ...a };
  for (const [id, value] of Object.entries(b)) {
    merged[id] = Math.max(merged[id] ?? 0, value);
  }
  return merged;
}

// Combines two ledgers — e.g. two devices reconciling saved progress once
// sync exists. days/chapters union as sets, maxDay takes the max, firstSeen
// takes the earliest, and the per-device counters take a per-key max rather
// than a sum, so re-merging the same pair (or a device merging its own
// entry back in) never double-counts. No network calls happen here — this
// is sync-*readiness*, exercised only by tests until sync itself ships.
//
// Expects the internal per-device ledger shape (activeMsByDevice/
// actsByDevice maps), not getLedger()'s flattened activeMs/acts numbers.
export function mergeLedgers(a, b) {
  return {
    firstSeen: a.firstSeen < b.firstSeen ? a.firstSeen : b.firstSeen,
    activeMsByDevice: unionCounterMap(a.activeMsByDevice, b.activeMsByDevice),
    days: [...new Set([...a.days, ...b.days])],
    chapters: [...new Set([...a.chapters, ...b.chapters])],
    actsByDevice: unionCounterMap(a.actsByDevice, b.actsByDevice),
    maxDay: Math.max(a.maxDay, b.maxDay),
  };
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
  const id = getDeviceId();
  ledger.actsByDevice[id] = (ledger.actsByDevice[id] || 0) + 1;
  persist();
}

// ---------------------------------------------------------------
// Feedback state — separate from the engagement ledger above because it
// tracks the prompt's own lifecycle (never shown/dismissed/pending a form
// submission/submitted), not reading activity. Kept in its own storage key
// so the two can be reasoned about, seeded, and reset independently — the
// manual DevTools testing in #459 relies on setting td:feedback without
// disturbing td:engagement, and vice versa.
// ---------------------------------------------------------------

const FEEDBACK_STORAGE_KEY = "td:feedback";

function freshFeedback() {
  return { status: "none", dismissals: 0, at: null };
}

const FEEDBACK_STATUSES = ["none", "dismissed", "pending", "submitted"];

function isValidFeedback(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    FEEDBACK_STATUSES.includes(value.status) &&
    typeof value.dismissals === "number" &&
    (value.at === null || typeof value.at === "string")
  );
}

function loadFeedback() {
  const raw = safeGet(FEEDBACK_STORAGE_KEY);
  if (!raw) return freshFeedback();
  try {
    const parsed = JSON.parse(raw);
    return isValidFeedback(parsed) ? parsed : freshFeedback();
  } catch (e) {
    return freshFeedback();
  }
}

let feedbackState = loadFeedback();

function persistFeedback() {
  safeSet(FEEDBACK_STORAGE_KEY, JSON.stringify(feedbackState));
}

export function getFeedback() {
  return structuredClone(feedbackState);
}

// Called from feedback-prompt.js's dismiss control.
export function recordFeedbackDismissal() {
  feedbackState.status = "dismissed";
  feedbackState.dismissals += 1;
  feedbackState.at = new Date().toISOString();
  persistFeedback();
}

// Called from feedback-prompt.js's CTA click, before the browser navigates
// to /share-your-experience.html (which in turn links out to the Tally
// testimonial form, #452). isFeedbackEligible below only re-opens
// eligibility from "dismissed", never from "pending" — so this suppresses
// the prompt indefinitely, even if the reader abandons the form without
// submitting, until #452's redirect page moves status to "submitted" (or
// some other mechanism explicitly resets it).
export function recordFeedbackPending() {
  feedbackState.status = "pending";
  persistFeedback();
}

// Called from share-your-experience.js (#452) when the reader lands back
// from Tally with ?submitted=1. Permanent, same as "pending" above —
// isFeedbackEligible never re-opens eligibility from "submitted" either.
export function recordFeedbackSubmitted() {
  feedbackState.status = "submitted";
  persistFeedback();
}

// ---------------------------------------------------------------
// Chapter ratings (#494) — which chapters this reader has given a thumbs
// up or down, so chapter-rating.js can render its "already rated" state
// and never re-ask. A third storage key for the same reason td:feedback is
// separate from td:engagement above: each can be seeded and reset in
// DevTools without disturbing the others.
//
// Keyed "<day>.<chapter>" to match ledger.chapters in recordVisit(), so the
// two can be compared directly — e.g. chapters seen but not rated.
// ---------------------------------------------------------------

const RATINGS_STORAGE_KEY = "td:ratings";

const RATING_VALUES = ["up", "down"];

function isValidRatings(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    // typeof [] is also "object", and an array would survive every check
    // below (no entries to iterate), so it has to be excluded explicitly.
    !Array.isArray(value) &&
    Object.values(value).every((v) => RATING_VALUES.includes(v))
  );
}

function loadRatings() {
  const raw = safeGet(RATINGS_STORAGE_KEY);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return isValidRatings(parsed) ? parsed : {};
  } catch (e) {
    return {};
  }
}

let ratings = loadRatings();

function persistRatings() {
  safeSet(RATINGS_STORAGE_KEY, JSON.stringify(ratings));
}

export function ratingKey(day, chapter) {
  return `${day}.${chapter}`;
}

export function getRatings() {
  return structuredClone(ratings);
}

// null (not undefined) for an unrated chapter, matching the null-means-absent
// convention pageContext() already uses for day/chapter.
export function getRating(day, chapter) {
  const existing = ratings[ratingKey(day, chapter)];
  return existing === undefined ? null : existing;
}

// Rating a chapter is a genuine content interaction, so it counts toward
// shouldPrompt()'s MIN_ACTS — but only the first time for a given chapter.
// The widget never re-asks once a chapter is rated, so a second call here
// shouldn't happen; guarding anyway keeps acts honest if it ever does.
export function recordRating(day, chapter, value) {
  if (!RATING_VALUES.includes(value)) return;
  const key = ratingKey(day, chapter);
  const isFirst = ratings[key] === undefined;
  ratings[key] = value;
  persistRatings();
  if (isFirst) recordAct();
}

// ---------------------------------------------------------------
// shouldPrompt — pure trigger predicate for the feedback/testimonial
// prompt (#459 renders it). Takes all state as arguments, no I/O or DOM
// access, so it's unit-testable in isolation.
//
// #494 replaced the scroll-depth/time-on-page gating this originally left
// to the caller: the prompt now fires off a thumbs-up in chapter-rating.js
// instead of a timer, so "has this reader formed an opinion?" is answered
// by the rating itself rather than inferred from dwell time. The thresholds
// below are deliberately unchanged pending real rating data.
// ---------------------------------------------------------------

const ACTIVE_MS_THRESHOLD = 30 * 60 * 1000;
const MIN_DAYS_RETURNED = 2;
const MIN_ACTS = 1;
const MAX_DISMISSALS = 2;
const DISMISSAL_COOLDOWN_MS = 45 * 24 * 60 * 60 * 1000;

function isFeedbackEligible(feedback, now) {
  if (feedback.status === "none") return true;
  // "pending" and "submitted" are both permanently excluded here, since
  // only "dismissed" ever re-opens eligibility (subject to the checks below).
  if (feedback.status !== "dismissed") return false;
  if (feedback.dismissals >= MAX_DISMISSALS) return false;
  // A dismissed status implies a dismissal was recorded. If `at` is missing,
  // `new Date(null)` resolves to the Unix epoch rather than an invalid date,
  // which would otherwise satisfy the cooldown immediately.
  if (!feedback.at) return false;
  return now.getTime() - new Date(feedback.at).getTime() >= DISMISSAL_COOLDOWN_MS;
}

export function shouldPrompt(engagement, feedback, now) {
  return (
    isFeedbackEligible(feedback, now) &&
    engagement.activeMs >= ACTIVE_MS_THRESHOLD &&
    engagement.days.length >= MIN_DAYS_RETURNED &&
    engagement.acts >= MIN_ACTS
  );
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
      const id = getDeviceId();
      ledger.activeMsByDevice[id] = (ledger.activeMsByDevice[id] || 0) + elapsed;
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
