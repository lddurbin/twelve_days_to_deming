// ============================================================
// Chapter rating — inline thumbs up/down at the end of every chapter (#494).
//
// Replaces the previous route, which sent anyone with anything to say to a
// separate page and then off-site to a form. That asked a lot for a little:
// a reader who wants to report "this chapter confused me" had roughly as
// much friction as composing an email from scratch.
//
// Two different jobs, deliberately split:
//   - a thumbs-down opens an optional text box, sent onward by
//     feedback-transport.js — the diagnostic path;
//   - a thumbs-up triggers feedback-prompt.js's testimonial ask, but only
//     when shouldPrompt() agrees — the advocacy path.
// One follow-up per thumb, never two, matching the epic's "ask at most
// twice, ever" stance.
//
// Loaded globally like every other module here, and a no-op off-chapter:
// pageContext() only resolves a day/chapter on /content/days/day-NN/NN-*,
// so the index, appendix and back-matter pages get nothing.
// ============================================================

import { track, pageContext } from "./telemetry.js";
import {
  getLedger,
  getFeedback,
  shouldPrompt,
  getRating,
  recordRating,
} from "./engagement.js";
import { sendFeedback } from "./feedback-transport.js";
import { show as showTestimonialPrompt } from "./feedback-prompt.js";

// One object so R/translation/code-string-extract.R can sweep the copy for
// the French edition (epic #461 constraint 3). URLs and addresses are built
// in code below, deliberately not here.
const STRINGS = {
  question: "Did this chapter work well for you?",
  yes: "Yes",
  no: "No",
  // Appended visually-hidden so the accessible name is specific while the
  // visible label stays short. WCAG 2.5.3 needs the accessible name to
  // contain the visible text, which it does — "Yes" leads both.
  //
  // Deliberately "worked well" rather than "useful": Neave's text is
  // transcribed verbatim and this site doesn't touch it, so a question
  // about its value would be asking readers to grade content nobody here
  // wrote. "Worked well" scopes the ask to what the site controls —
  // layout, pacing, activities — and matches detailLabel below, which asks
  // the same thing in its own words rather than pivoting the framing.
  yesContext: ", this chapter worked well for you",
  noContext: ", this chapter didn't work well for you",
  thanksUp: "Thanks — glad it's landing.",
  thanksDown: "Thanks for saying so.",
  detailLabel: "What didn't work here?",
  detailHint:
    "Optional. Sent to me with the chapter you were on and nothing else — no name, no email, no way to tie it to your other visits.",
  send: "Send",
  skip: "No thanks",
  sending: "Sending…",
  sent: "Thanks — that's been sent.",
  failed: "That didn't send, sorry — the connection or an extension may have blocked it.",
  failedCta: "Email it to me instead",
  alreadyRated: "Thanks for rating this chapter.",
};

// ---------------------------------------------------------------
// Screen-reader live region. Same pattern and same reasoning as
// funnel-experiment.js's: a single persistent, visually-hidden region
// created eagerly, because a region inserted and written in the same task
// gets swallowed by VoiceOver/NVDA. Announcements are reserved for things
// that just happened asynchronously (the send result) — the visible prose
// changes are not themselves live regions, so nothing is announced twice.
// ---------------------------------------------------------------

let liveRegion = null;

function ensureLiveRegion() {
  if (typeof document === "undefined") return null;
  if (liveRegion && liveRegion.isConnected) return liveRegion;
  const host = document.getElementById("quarto-document-content") || document.body;
  if (!host) return null;
  liveRegion = document.createElement("div");
  liveRegion.className = "cr-sr-live visually-hidden";
  liveRegion.setAttribute("role", "status");
  liveRegion.setAttribute("aria-live", "polite");
  liveRegion.setAttribute("aria-atomic", "true");
  host.appendChild(liveRegion);
  return liveRegion;
}

function announce(message) {
  const region = ensureLiveRegion();
  if (region) region.textContent = message;
}

// ---------------------------------------------------------------
// Mailto fallback, used only when the transport fails. Assembled from
// fragments for the same mild anti-scraper reason reading-prefs.js gives
// for its own feedback row; that file is a classic script and can't be
// imported from here, so the approach is repeated rather than shared.
// Carries whatever the reader already typed, so a failed send never costs
// them their words.
// ---------------------------------------------------------------

function mailtoHref(text, day, chapter) {
  const addr = "hello" + "@" + "leedurbin.co.nz";
  const subject = "12 Days to Deming — feedback";
  const body =
    text +
    "\n\n—\nDay " + day + ", chapter " + chapter + "\n" + window.location.href;
  return (
    "mailto:" + addr +
    "?subject=" + encodeURIComponent(subject) +
    "&body=" + encodeURIComponent(body)
  );
}

// ---------------------------------------------------------------
// Markup
// ---------------------------------------------------------------

function buttonMarkup(value, label, context) {
  return (
    '<button type="button" class="chapter-rating-btn" data-rating="' + value + '">' +
    '<span class="chapter-rating-icon" aria-hidden="true">' +
    (value === "up" ? "👍" : "👎") +
    "</span>" +
    "<span>" + label + "</span>" +
    '<span class="visually-hidden">' + context + "</span>" +
    "</button>"
  );
}

function build() {
  const el = document.createElement("div");
  el.className = "chapter-rating";
  // Programmatic focus target for after the detail form is replaced —
  // without it, removing the control that had focus drops the reader back
  // to <body> and loses their place. Not keyboard-reachable by tabbing,
  // and :focus-visible won't match a programmatic focus, so no stray ring.
  el.setAttribute("tabindex", "-1");
  // A <p>, not a heading: this is page chrome appended to every chapter,
  // not part of the document outline, so it shouldn't add an entry for
  // readers navigating by heading (same reasoning as feedback-prompt.js).
  el.innerHTML =
    '<p class="chapter-rating-question">' + STRINGS.question + "</p>" +
    '<div class="chapter-rating-actions">' +
    buttonMarkup("up", STRINGS.yes, STRINGS.yesContext) +
    buttonMarkup("down", STRINGS.no, STRINGS.noContext) +
    "</div>";
  return el;
}

// Marks the chosen thumb and closes both to further clicks. The buttons stay
// in the DOM and are NOT given the `disabled` attribute on purpose: a focused
// button that becomes disabled loses focus in most browsers, which is the
// same lost-place problem the tabindex above guards against. aria-disabled
// states it for assistive tech while the handler below enforces it.
function markChosen(el, rating) {
  el.querySelectorAll(".chapter-rating-btn").forEach((btn) => {
    btn.setAttribute("aria-disabled", "true");
    const isChosen = btn.dataset.rating === rating;
    btn.setAttribute("aria-pressed", isChosen ? "true" : "false");
    btn.classList.toggle("is-chosen", isChosen);
  });
}

function setNote(el, text) {
  const question = el.querySelector(".chapter-rating-question");
  if (question) question.textContent = text;
}

// ---------------------------------------------------------------
// The thumbs-down detail form
// ---------------------------------------------------------------

function buildDetailForm() {
  const wrap = document.createElement("div");
  wrap.className = "chapter-rating-detail";
  wrap.innerHTML =
    '<label class="chapter-rating-detail-label" for="chapter-rating-detail-text">' +
    STRINGS.detailLabel +
    "</label>" +
    '<p class="chapter-rating-detail-hint" id="chapter-rating-detail-hint">' +
    STRINGS.detailHint +
    "</p>" +
    '<textarea id="chapter-rating-detail-text" class="chapter-rating-detail-text" ' +
    'rows="4" aria-describedby="chapter-rating-detail-hint"></textarea>' +
    '<div class="chapter-rating-detail-actions">' +
    '<button type="button" class="chapter-rating-send">' + STRINGS.send + "</button>" +
    '<button type="button" class="chapter-rating-skip">' + STRINGS.skip + "</button>" +
    "</div>";
  return wrap;
}

// Replaces the form with a plain sentence and returns focus to the widget,
// so the reader is never left focused on a control that has been removed.
function closeDetail(el, form, message) {
  form.remove();
  setNote(el, message);
  el.focus();
}

function showFailure(el, form, text, day, chapter) {
  form.innerHTML =
    '<p class="chapter-rating-failed">' + STRINGS.failed + "</p>" +
    '<a class="chapter-rating-failed-cta"></a>';
  const link = form.querySelector(".chapter-rating-failed-cta");
  // href assigned rather than interpolated into the template above: the
  // reader's own text goes into it, and it should never touch innerHTML.
  link.href = mailtoHref(text, day, chapter);
  link.textContent = STRINGS.failedCta;
  announce(STRINGS.failed);
  link.focus();
}

function wireDetailForm(el, form, day, chapter) {
  const textarea = form.querySelector(".chapter-rating-detail-text");
  const sendBtn = form.querySelector(".chapter-rating-send");
  const skipBtn = form.querySelector(".chapter-rating-skip");

  skipBtn.addEventListener("click", function () {
    closeDetail(el, form, STRINGS.thanksDown);
  });

  sendBtn.addEventListener("click", async function () {
    // The await below yields, so without this a double-click posts twice.
    // aria-disabled is set (not the `disabled` attribute, which would move
    // focus off the button mid-send), so it has to be enforced here.
    if (sendBtn.getAttribute("aria-disabled") === "true") return;

    const text = textarea.value.trim();
    // An empty box is a skip, not a send — no point posting a blank note.
    if (!text) {
      closeDetail(el, form, STRINGS.thanksDown);
      return;
    }

    sendBtn.setAttribute("aria-disabled", "true");
    sendBtn.textContent = STRINGS.sending;

    const { ok } = await sendFeedback({ text, day, chapter, rating: "down" });

    if (ok) {
      track("Feedback detail sent", pageContext());
      closeDetail(el, form, STRINGS.sent);
      announce(STRINGS.sent);
      return;
    }

    // Worth its own event: without it a broken transport looks exactly like
    // nobody having anything to say.
    track("Feedback detail failed", pageContext());
    showFailure(el, form, text, day, chapter);
  });

  return textarea;
}

// ---------------------------------------------------------------
// Rating handlers
// ---------------------------------------------------------------

function handleUp(el) {
  setNote(el, STRINGS.thanksUp);
  // Checked after recordRating() has already counted this rating as an act,
  // so a reader whose only interaction is rating chapters can still qualify.
  if (shouldPrompt(getLedger(), getFeedback(), new Date())) {
    showTestimonialPrompt(el);
  }
}

function handleDown(el, day, chapter) {
  setNote(el, STRINGS.thanksDown);
  const form = buildDetailForm();
  el.appendChild(form);
  const textarea = wireDetailForm(el, form, day, chapter);
  // Moving focus is the announcement here — the label and hint are read on
  // arrival, so no live-region message is needed and nothing doubles up.
  textarea.focus();
}

function handleRating(el, rating, day, chapter) {
  recordRating(day, chapter, rating);
  track("Chapter rated", { ...pageContext(), rating });
  markChosen(el, rating);
  if (rating === "up") handleUp(el);
  else handleDown(el, day, chapter);
}

// ---------------------------------------------------------------
// Init
// ---------------------------------------------------------------

function insertIntoContent(el) {
  // Quarto's book layout places .content and .page-navigation in the SAME
  // CSS grid, each pinned to its own named row, so a plain DOM sibling
  // inserted between them falls through to grid auto-placement and lands
  // AFTER the nav. Appending inside .content keeps it in that row's normal
  // block flow. See feedback-prompt.js's fuller note on the same bug.
  const content = document.getElementById("quarto-document-content");
  if (content) {
    content.appendChild(el);
    return true;
  }
  const nav = document.querySelector(".page-navigation");
  if (nav && nav.parentNode) {
    nav.parentNode.insertBefore(el, nav);
    return true;
  }
  return false;
}

function init() {
  const { day, chapter } = pageContext();
  // Off-chapter pages (index, appendix, privacy, back matter) get nothing.
  if (day === null || chapter === null) return;

  const el = build();
  if (!insertIntoContent(el)) return;

  const existing = getRating(day, chapter);
  if (existing !== null) {
    // Revisit: show what they chose and never ask again. Nothing has just
    // happened, so this is plain text and is deliberately not announced.
    markChosen(el, existing);
    setNote(el, STRINGS.alreadyRated);
    return;
  }

  el.querySelectorAll(".chapter-rating-btn").forEach((btn) => {
    btn.addEventListener("click", function () {
      // aria-disabled is advisory only — the handler has to enforce it.
      if (btn.getAttribute("aria-disabled") === "true") return;
      handleRating(el, btn.dataset.rating, day, chapter);
    });
  });
}

// Guarded on `document`, matching every other module in this directory:
// keeps the module side-effect-free (and therefore safely `import`able
// under Node/vitest, where `document` doesn't exist).
if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", function () {
    // Created before the first interaction so assistive tech is already
    // monitoring it — see ensureLiveRegion's note.
    ensureLiveRegion();
    init();
  });
}
