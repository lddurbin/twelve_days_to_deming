// ============================================================
// Feedback prompt — dismissible inline block inviting feedback and
// testimonials.
//
// #451 built the static markup/styling/dismiss control behind a temporary
// dev flag. This wires it to the real trigger: shouldPrompt() (engagement.js)
// gates on ledger/feedback state, and this file adds the two DOM-only gates
// shouldPrompt() can't see — scroll depth and time-on-page — before the
// block actually renders.
//
// Deliberately NOT a modal, toast, or floating popover: inline placement
// (appended inside #quarto-document-content, directly above .page-navigation)
// means it never covers content, needs no focus trap, and screen-reader
// users meet it in natural reading order. No aria-live — announcing its
// appearance is exactly the intrusive behaviour to avoid.
// ============================================================

import { track, pageContext } from "./telemetry.js";
import {
  getLedger,
  getFeedback,
  shouldPrompt,
  recordFeedbackDismissal,
  recordFeedbackPending,
} from "./engagement.js";

const STRINGS = {
  heading: "Is this course helping you?",
  body: "If you've got a minute, we'd love to hear how it's going — what's working, what's confusing, anything at all.",
  cta: "Share your experience",
  dismiss: "Not now",
};

// Deliberately kept out of STRINGS: the FR extractor's whitelist (see
// R/translation/code-string-extract.R) is designed to sweep translatable
// prose, and its own stated discipline is "when in doubt, EXCLUDE" anything
// that isn't user-facing text — a URL swept in as if it were copy risks a
// translator "translating" a path and silently breaking the link. Still
// pulled out to its own named constant, not left inline in the innerHTML
// template, so it has one obvious place to update if it changes.
const CTA_HREF = "/share-your-experience.html";

// shouldPrompt() (engagement.js) covers everything decidable from ledger and
// feedback state alone; scroll depth and time-on-page are DOM-only concerns
// that function's own header comment leaves to this file.
const TIME_ON_PAGE_THRESHOLD_MS = 45 * 1000;
const SCROLL_THRESHOLD = 0.7;
const CHECK_INTERVAL_MS = 1000;

function scrollFraction() {
  const doc = document.documentElement;
  const scrollable = doc.scrollHeight - doc.clientHeight;
  // Nothing to scroll means there's nothing left to read before showing —
  // treat the page as fully seen rather than waiting on a scroll event that
  // can never come.
  if (scrollable <= 0) return 1;
  return (doc.scrollTop || window.scrollY) / scrollable;
}

function build() {
  const el = document.createElement("div");
  el.className = "feedback-prompt";
  // A <p>, not a heading element: this is page chrome inserted on every
  // page, not part of the document outline, so it shouldn't add a new
  // entry for screen-reader users navigating by heading (same reasoning
  // as reading-prefs.js's .reading-prefs-title).
  el.innerHTML =
    '<p class="feedback-prompt-heading">' + STRINGS.heading + "</p>" +
    '<p class="feedback-prompt-body">' + STRINGS.body + "</p>" +
    '<div class="feedback-prompt-actions">' +
    '  <a class="feedback-prompt-cta" href="' + CTA_HREF + '">' + STRINGS.cta + "</a>" +
    '  <button type="button" class="feedback-prompt-dismiss">' + STRINGS.dismiss + "</button>" +
    "</div>";
  return el;
}

function insertBeforePageNav(el) {
  // Quarto's book layout places .content and .page-navigation in the SAME
  // CSS grid, each pinned to its own explicit named row (content-top/
  // content-bottom and content-bottom/page-bottom — see the compiled
  // bootstrap CSS). A plain DOM sibling inserted between them with no grid
  // placement of its own falls through to grid auto-placement instead,
  // which lands it AFTER page-navigation, not before it (confirmed by
  // rendering: DOM order was correct, visual order wasn't). Appending
  // inside .content keeps it part of that row's normal block flow, so it
  // renders directly above the nav — and in DOM/reading order too.
  const content = document.getElementById("quarto-document-content");
  if (content) {
    content.appendChild(el);
    return;
  }
  const nav = document.querySelector(".page-navigation");
  if (nav && nav.parentNode) {
    nav.parentNode.insertBefore(el, nav);
  } else {
    document.body.appendChild(el);
  }
}

function show() {
  const el = build();
  insertBeforePageNav(el);
  // Forced synchronous layout read, not a single requestAnimationFrame: rAF
  // genuinely races the insertion in some browsers and can get coalesced
  // away, silently skipping the transition. This costs nothing extra and
  // rules that out entirely rather than trusting this browser's timing.
  void el.offsetHeight;
  el.classList.add("is-visible");

  track("Feedback prompt shown", pageContext());

  el.querySelector(".feedback-prompt-cta").addEventListener("click", function () {
    // No preventDefault — the link navigates normally to the Tally form
    // (#452); this only needs to fire before that navigation completes,
    // which a synchronous click handler guarantees.
    recordFeedbackPending();
    track("Feedback prompt clicked", pageContext());
  });

  el.querySelector(".feedback-prompt-dismiss").addEventListener("click", function () {
    recordFeedbackDismissal();
    track("Feedback prompt dismissed", pageContext());
    el.remove();
  });
}

// Guarded on `document`, matching storage.js/telemetry.js/engagement.js:
// keeps this module side-effect-free (and therefore safely `import`able
// under Node/vitest, where `document` doesn't exist).
if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", function () {
    // Cheap up-front gate: the overwhelming majority of pageviews are from
    // readers nowhere near eligible, and this skips arming the poller below
    // for all of them. Re-checked on every tick once armed (see below), so
    // this initial read only needs to decide whether polling is worth
    // starting at all — not to be the final word.
    if (!shouldPrompt(getLedger(), getFeedback(), new Date())) return;

    const pageLoadedAt = Date.now();
    const intervalId = setInterval(function () {
      const timeOnPageMs = Date.now() - pageLoadedAt;
      if (timeOnPageMs < TIME_ON_PAGE_THRESHOLD_MS) return;
      if (scrollFraction() < SCROLL_THRESHOLD) return;
      // Re-validated against live state, not the snapshot at
      // DOMContentLoaded: this tab's own engagement heartbeat can push
      // activeMs past the threshold during the wait. This does NOT catch
      // another tab dismissing or submitting the prompt in the meantime —
      // getLedger()/getFeedback() return engagement.js's in-memory state,
      // which that module only refreshes from localStorage on a fresh page
      // load, not live. A second open tab could still show the prompt just
      // after another tab suppressed it; narrow enough (simultaneous tabs,
      // both independently reaching the 45s/70% gate) that it isn't worth
      // a storage-event listener for now.
      clearInterval(intervalId);
      if (!shouldPrompt(getLedger(), getFeedback(), new Date())) return;
      show();
    }, CHECK_INTERVAL_MS);
  });
}
