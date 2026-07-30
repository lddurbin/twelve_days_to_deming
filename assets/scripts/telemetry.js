// ============================================================
// Telemetry — thin wrapper around the Simple Analytics client.
//
// Every vendor-specific call lives here, and nowhere else, so a
// future vendor swap touches one file. A tracking failure must
// never be able to break a learning activity, so track() only
// ever no-ops on error — it never throws outward.
// ============================================================

export function track(name, props) {
  try {
    if (typeof window === "undefined" || typeof window.sa_event !== "function") {
      return;
    }
    if (props) {
      window.sa_event(name, props);
    } else {
      window.sa_event(name);
    }
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
