// ============================================================
// Share your experience — the two-state landing page #452 builds around
// the Tally feedback/testimonial form: a default view explaining why
// feedback matters and linking out to the form, and a `?submitted=1`
// thank-you view Tally's redirect-on-completion lands the reader on.
//
// Loaded globally (matching engagement.js/feedback-prompt.js), not per-page
// — it self-guards on the two view elements only present in
// share-your-experience.qmd, so it's a no-op everywhere else.
// ============================================================

import { track, pageContext } from "./telemetry.js";
import { recordFeedbackPending, recordFeedbackSubmitted } from "./engagement.js";

function init() {
  const formView = document.getElementById("share-form-view");
  const thankyouView = document.getElementById("share-thankyou-view");
  if (!formView || !thankyouView) return;

  const submitted = new URLSearchParams(window.location.search).get("submitted") === "1";

  if (submitted) {
    // Permanent, matching recordFeedbackPending's own precedent: nothing
    // in isFeedbackEligible (engagement.js) ever re-opens eligibility from
    // "submitted".
    recordFeedbackSubmitted();
    track("Feedback submitted", pageContext());
    formView.hidden = true;
    thankyouView.hidden = false;
    return;
  }

  const cta = formView.querySelector("#share-form-cta");
  if (!cta) return;
  cta.addEventListener("click", function () {
    // No preventDefault — the link navigates normally to the Tally form;
    // this only needs to fire before that navigation completes, which a
    // synchronous click handler guarantees (same reasoning as
    // feedback-prompt.js's CTA handler).
    recordFeedbackPending();
    track("Share experience CTA clicked", pageContext());
  });
}

// Guarded on `document`, matching every other module in this directory:
// keeps the module side-effect-free (and therefore safely `import`able
// under Node/vitest, where `document` doesn't exist).
if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", init);
}
