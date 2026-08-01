// ============================================================
// Feedback prompt — dismissible inline block inviting feedback and
// testimonials (#451: markup, styling, dismiss control only).
//
// Engagement-gated trigger logic, suppression-state persistence, and
// analytics events are wired in #459. Until then this renders behind a
// temporary dev flag (?feedback_prompt=1) so the visual block can go
// through accessibility and dark-mode review as ordinary page furniture,
// rather than something only reachable after real engagement.
//
// Deliberately NOT a modal, toast, or floating popover: inline placement
// (inserted before .page-navigation, same selector reading-prefs.js's
// yieldToPageNav uses) means it never covers content, needs no focus trap,
// and screen-reader users meet it in natural reading order. No aria-live —
// announcing its appearance is exactly the intrusive behaviour to avoid.
// ============================================================

const STRINGS = {
  heading: "Is this course helping you?",
  body: "If you've got a minute, we'd love to hear how it's going — what's working, what's confusing, anything at all.",
  cta: "Share your experience",
  dismiss: "Not now",
};

// Deliberately kept out of STRINGS: the future FR extractor's whitelist (see
// R/translation/code-string-extract.R) is designed to sweep translatable
// prose, and its own stated discipline is "when in doubt, EXCLUDE" anything
// that isn't user-facing text — a URL swept in as if it were copy risks a
// translator "translating" a path and silently breaking the link. Still
// pulled out to its own named constant, not left inline in the innerHTML
// template, so it has one obvious place to update if it changes.
const CTA_HREF = "/share-your-experience.html";

const DEV_FLAG_PARAM = "feedback_prompt";

function devFlagForcesOn() {
  try {
    return new URLSearchParams(window.location.search).get(DEV_FLAG_PARAM) === "1";
  } catch (e) {
    return false;
  }
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

// Guarded on `document`, matching storage.js/telemetry.js/engagement.js:
// keeps this module side-effect-free (and therefore safely `import`able
// under Node/vitest, where `document` doesn't exist) if a future change
// ever needs to test something here directly, the way #459's wiring likely
// will once it imports shouldPrompt()/track() into this file.
if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", function () {
    if (!devFlagForcesOn()) return;

    const el = build();
    insertBeforePageNav(el);
    // A single requestAnimationFrame is the common pattern for triggering a
    // transition on a just-inserted element, and it does work here (verified
    // in Chromium: the opacity/transform transition plays smoothly either
    // way). Using a forced synchronous layout read instead removes any
    // reliance on this browser's specific rAF/style-recalc timing — general
    // CSS-transition folklore has real cross-browser cases where a single
    // rAF gets coalesced with the insertion and the transition never starts,
    // and this costs nothing extra to rule out entirely rather than trust
    // that Chromium's current behaviour holds everywhere.
    void el.offsetHeight;
    el.classList.add("is-visible");

    el.querySelector(".feedback-prompt-dismiss").addEventListener("click", function () {
      el.remove();
    });
  });
}
