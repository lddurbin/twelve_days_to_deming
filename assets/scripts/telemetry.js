// ============================================================
// Telemetry — thin wrapper around the Simple Analytics client.
//
// Every vendor-specific call lives here, and nowhere else, so a
// future vendor swap touches one file. A tracking failure must
// never be able to break a learning activity, so track() only
// ever no-ops on error — it never throws outward.
// ============================================================

function sendNow(name, props) {
  if (props) {
    window.sa_event(name, props);
  } else {
    window.sa_event(name);
  }
}

// latest.js loads via <script async>, so a call made in the first moment
// after page load can land before window.sa_event exists yet — not
// blocked, just not ready. Queue calls made in that window and retry on a
// short, exponentially-backed-off timer rather than silently dropping a
// real interaction. Retries stop after MAX_RETRIES so a genuinely
// blocked/absent script (ad-blocker, CSP failure) still gives up cleanly.
let pending = [];
const MAX_RETRIES = 5;
const BASE_DELAY_MS = 100;

function flushPending() {
  const queued = pending;
  pending = [];
  for (const [name, props] of queued) {
    try {
      sendNow(name, props);
    } catch (e) {
      // A tracking failure must never be able to break a learning activity.
    }
  }
}

function scheduleRetry(attempt) {
  const delay = BASE_DELAY_MS * 2 ** (attempt - 1);
  setTimeout(() => {
    if (typeof window === "undefined") {
      pending = [];
      return;
    }
    if (typeof window.sa_event === "function") {
      flushPending();
    } else if (attempt < MAX_RETRIES) {
      scheduleRetry(attempt + 1);
    } else {
      pending = [];
    }
  }, delay);
}

export function track(name, props) {
  try {
    if (typeof window === "undefined") {
      return;
    }
    if (typeof window.sa_event === "function") {
      sendNow(name, props);
      return;
    }
    const wasEmpty = pending.length === 0;
    pending.push([name, props]);
    if (wasEmpty) scheduleRetry(1);
  } catch (e) {
    // A tracking failure must never be able to break a learning activity.
  }
}

// Rendered chapter URLs preserve the content/ source layout, e.g.
// /content/days/day-03/12-rules-3-and-4-of-the-funnel.html
const PAGE_PATH = /\/content\/days\/day-(\d+)\/(\d+)-[^/]+\.html$/;

export function pageContext() {
  if (typeof window === "undefined") return { day: null, chapter: null };
  const match = PAGE_PATH.exec(window.location.pathname);
  if (!match) return { day: null, chapter: null };
  return { day: Number(match[1]), chapter: Number(match[2]) };
}

// Loaded as type="module", which defers execution until after the document
// has parsed — later than classic <script> tags in <head>, but always before
// DOMContentLoaded. window.track/pageContext are safe to call from event
// handlers (clicks, toggles) but not from a classic script's top-level body,
// which can run before this assignment happens.
if (typeof window !== "undefined") {
  window.track = track;
  window.pageContext = pageContext;
}

// ============================================================
// Commentary reveals — one delegated listener covers all 16
// "Pause for Thought" buttons across the site, so a new reveal
// button in a future chapter needs no per-page JS to be tracked.
// ============================================================

// Quarto's own sidebar TOC also uses [data-bs-toggle="collapse"] for its
// collapsible sections, so the selector must key on the "#collapse_" target
// naming convention shared by all 16 reveal buttons — not the bare
// data-bs-toggle attribute, which would also fire on sidebar navigation.
const REVEAL_SELECTOR = '[data-bs-toggle="collapse"][data-bs-target^="#collapse_"]';

export function handleCommentaryReveal(event) {
  const button = event.target.closest(REVEAL_SELECTOR);
  if (!button) return;
  const activity = button.getAttribute("data-bs-target").replace(/^#collapse_/, "");
  track("Commentary revealed", { ...pageContext(), activity });
}

if (typeof document !== "undefined") {
  document.addEventListener("click", handleCommentaryReveal);
}
