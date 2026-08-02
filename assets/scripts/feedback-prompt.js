// ============================================================
// Testimonial prompt — dismissible inline block asking whether the reader
// would be willing to be quoted on the site.
//
// #451 built the markup/styling/dismiss control; #459 wired it to
// shouldPrompt() behind a scroll-depth and time-on-page poller. #494
// replaced that trigger: chapter-rating.js calls show() directly when a
// reader gives a chapter a thumbs-up and shouldPrompt() agrees. Asking
// someone who has just said "yes, this helped" is far better aim than
// inferring a formed opinion from dwell time, and it deletes the poller.
//
// General feedback is no longer this block's job — the rating widget's
// thumbs-down box handles that inline. This asks one thing only.
//
// Deliberately NOT a modal, toast, or floating popover: inline placement
// (appended inside #quarto-document-content, directly above .page-navigation)
// means it never covers content, needs no focus trap, and screen-reader
// users meet it in natural reading order. No aria-live — it appears as a
// consequence of the reader's own click, and chapter-rating.js already
// announces that outcome through its own status region.
//
// No side effects on load: this module now only exports. It is pulled into
// the graph by chapter-rating.js's import rather than its own script tag.
// ============================================================

import { track, pageContext } from "./telemetry.js";
import { recordFeedbackDismissal, recordFeedbackPending } from "./engagement.js";

const STRINGS = {
  heading: "Would you be willing to be quoted?",
  body: "If you'd be happy for a line of your feedback to appear on the site — anonymously, or with your name and role — I'd be glad to hear from you. It takes a couple of minutes.",
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

// Callers are responsible for the gating — chapter-rating.js checks
// shouldPrompt() before calling this. Kept dumb on purpose so the trigger
// policy lives in one place rather than being half-enforced here.
//
// @param {HTMLElement} [anchor] element to append after, instead of the
//   page-nav position. The rating widget passes itself so the ask appears
//   attached to the thumb the reader just clicked.
export function show(anchor) {
  const el = build();
  if (anchor && anchor.parentNode) {
    anchor.insertAdjacentElement("afterend", el);
  } else {
    insertBeforePageNav(el);
  }
  // Forced synchronous layout read, not a single requestAnimationFrame: rAF
  // genuinely races the insertion in some browsers and can get coalesced
  // away, silently skipping the transition. This costs nothing extra and
  // rules that out entirely rather than trusting this browser's timing.
  void el.offsetHeight;
  el.classList.add("is-visible");

  track("Feedback prompt shown", pageContext());

  el.querySelector(".feedback-prompt-cta").addEventListener("click", function () {
    // No preventDefault — the link navigates normally to
    // /share-your-experience.html; this only needs to fire before that
    // navigation completes, which a synchronous click handler guarantees.
    recordFeedbackPending();
    track("Feedback prompt clicked", pageContext());
  });

  el.querySelector(".feedback-prompt-dismiss").addEventListener("click", function () {
    recordFeedbackDismissal();
    track("Feedback prompt dismissed", pageContext());
    el.remove();
  });

  return el;
}
