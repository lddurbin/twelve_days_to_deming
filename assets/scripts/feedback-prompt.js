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

const DEV_FLAG_PARAM = "feedback_prompt";

function devFlagForcesOn() {
  if (typeof window === "undefined") return false;
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
    '  <a class="feedback-prompt-cta" href="/share-your-experience.html">' + STRINGS.cta + "</a>" +
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

document.addEventListener("DOMContentLoaded", function () {
  if (!devFlagForcesOn()) return;

  const el = build();
  insertBeforePageNav(el);
  // Added on the next frame, not in the same pass as insertion, so the
  // opacity/transform transition in main.css actually runs instead of
  // snapping straight to its end state. prefers-reduced-motion is handled
  // globally (main.css:735 zeroes all transition durations), so no
  // matchMedia check is needed here.
  requestAnimationFrame(function () {
    el.classList.add("is-visible");
  });

  el.querySelector(".feedback-prompt-dismiss").addEventListener("click", function () {
    el.remove();
  });
});
