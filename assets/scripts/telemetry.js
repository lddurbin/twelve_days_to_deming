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
  var match = PAGE_PATH.exec(window.location.pathname);
  if (!match) return { day: null, chapter: null };
  return { day: Number(match[1]), chapter: Number(match[2]) };
}

if (typeof window !== "undefined") {
  window.track = track;
  window.pageContext = pageContext;
}
