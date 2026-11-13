// ============================================================
// "Found an error?" footer link (#929) — the route readers use to tell us
// that a word, number or emphasis differs from Neave's original.
//
// The footer markup is static and identical for every visitor and crawler
// (_quarto.yml, book.page-footer.right): one link to the GitHub
// transcription-error issue form, with no page identified, because
// book.page-footer has no per-page override. Everything per-page happens
// here, client-side, after load:
//
//   - the GitHub link gains `page` and `title` query parameters, which
//     GitHub's issue forms use to pre-fill the field with the matching id
//     in .github/ISSUE_TEMPLATE/transcription-error.yml;
//   - an "or by email" mailto is appended, for readers without a GitHub
//     account (GitHub's new-issue page needs one, so a logged-out reader
//     never even sees the form). It's added by script rather than written
//     into the footer for the same mild anti-scraper reason reading-prefs.js
//     gives: the address never appears as a literal in any page or file.
//
// Without JavaScript the reader still gets the GitHub link, just unfilled.
// ============================================================

import { track, pageContext } from "./telemetry.js";

const ISSUE_FORM =
  "https://github.com/lddurbin/twelve_days_to_deming/issues/new" +
  "?template=transcription-error.yml";

// Reports name the production address even from a preview or staging
// deploy, so every issue points at a page a maintainer can open as-is.
const CANONICAL_ORIGIN = "https://learndeming.org";

export function canonicalPageUrl(pathname, hash) {
  return CANONICAL_ORIGIN + (pathname || "/") + (hash || "");
}

export function githubReportHref(pageUrl, pageTitle) {
  return (
    ISSUE_FORM +
    "&title=" + encodeURIComponent("Transcription error: " + (pageTitle || pageUrl)) +
    "&page=" + encodeURIComponent(pageUrl)
  );
}

export function emailReportHref(pageUrl, pageTitle) {
  const addr = "hello" + "@" + "leedurbin.co.nz";
  const subject = "12 Days to Deming — possible transcription error";
  const body =
    "The passage (a sentence or two around the error):\n\n\n" +
    "What I think it should say:\n\n\n" +
    "Neave's page number (if you have it):\n\n\n" +
    "—\nPage: " + (pageTitle ? pageTitle + "\n" : "") + pageUrl;
  return (
    "mailto:" + addr +
    "?subject=" + encodeURIComponent(subject) +
    "&body=" + encodeURIComponent(body)
  );
}

function init() {
  const github = document.querySelector("a.report-error-github");
  if (!github) return;

  const pageUrl = canonicalPageUrl(window.location.pathname, window.location.hash);
  const pageTitle = document.title;
  github.href = githubReportHref(pageUrl, pageTitle);
  github.addEventListener("click", function () {
    track("Error report opened", Object.assign(pageContext(), { via: "github" }));
  });

  const email = document.createElement("a");
  email.className = "report-error-email";
  email.href = emailReportHref(pageUrl, pageTitle);
  email.textContent = "by email";
  // Visible text alone ("by email") doesn't say what the email is for when
  // read out of context, e.g. in a screen reader's links list. The label
  // keeps the visible words in it (WCAG 2.5.3, label in name).
  email.setAttribute("aria-label", "Report an error by email");
  email.addEventListener("click", function () {
    track("Error report opened", Object.assign(pageContext(), { via: "email" }));
  });
  github.after(" or ", email);

  // Hash changes don't reload the page, so keep the reported address in
  // step with whichever section the reader has since jumped to. The title
  // is reused as captured: a hash change never changes it on a static page.
  window.addEventListener("hashchange", function () {
    const url = canonicalPageUrl(window.location.pathname, window.location.hash);
    github.href = githubReportHref(url, pageTitle);
    email.href = emailReportHref(url, pageTitle);
  });
}

// Guarded on `document`, matching every other module in this directory:
// keeps the module side-effect-free (and therefore safely `import`able
// under Node/vitest, where `document` doesn't exist).
if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", init);
}
