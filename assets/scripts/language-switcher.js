/* Language switcher (issue #322).
 *
 * Renders a fixed, keyboard-operable control on every page of both editions
 * that links the reader to the corresponding page in the other language.
 *
 * It is a sibling affordance to the reading-preferences toggle
 * (assets/scripts/reading-prefs.js): same fixed-corner placement language,
 * same focus-ring and dark-mode conventions, same "inject once at
 * DOMContentLoaded" lifecycle. It is rendered by JS rather than baked into the
 * Quarto sidebar because the book project type has no per-page navbar slot,
 * and header-includes (shared by both profiles in _quarto.yml) is the one
 * place guaranteed to run on every page of both editions.
 *
 * GRACEFUL DEGRADATION RULE
 * -------------------------
 * EN and FR pages are NOT a clean path-prefix mirror: EN content lives under
 * /content/... with the home page at /index.html, while FR content lives under
 * /fr/content-fr/... with the home page at /fr/index.fr.html. So the EN<->FR
 * correspondence is expressed explicitly in PAGE_MAP below (EN path -> FR
 * path). The link target is resolved as:
 *
 *   1. If the current page has a known counterpart in PAGE_MAP -> link to it.
 *   2. Otherwise (the common case today, since FR is still a stub) -> link to
 *      the OTHER edition's home page.
 *
 * Either way the target is a path this build is known to emit, so the switcher
 * can never produce a 404. As FR pages are translated, add their EN<->FR pair
 * to PAGE_MAP and the switcher upgrades from "home fallback" to "same page"
 * automatically.
 */
(function () {
  // EN root-relative path  ->  FR root-relative path.
  // Paths are site-root-relative (leading slash) and include the .html suffix
  // exactly as emitted, so the lookup is a direct string match.
  var PAGE_MAP = {
    "/index.html": "/fr/index.fr.html",
    "/welcome.html": "/fr/content-fr/welcome.html"
  };

  var EN_HOME = "/index.html";
  var FR_HOME = "/fr/index.fr.html";

  // Reverse map FR -> EN, derived from PAGE_MAP so there is one source of truth.
  var FR_TO_EN = {};
  Object.keys(PAGE_MAP).forEach(function (en) {
    FR_TO_EN[PAGE_MAP[en]] = en;
  });

  // Current page is FR if it sits under the /fr/ tree.
  function currentIsFr() {
    return /(^|\/)fr\//.test(window.location.pathname);
  }

  // Normalise the current pathname to a map key. The build always emits
  // explicit *.html, but a trailing-slash request to a directory should still
  // resolve to the relevant home page so the lookup succeeds.
  function normalisePath(path) {
    if (path === "" || path === "/") return EN_HOME;
    if (/\/fr\/?$/.test(path)) return FR_HOME;
    return path;
  }

  // Resolve the counterpart URL, applying the graceful-degradation rule.
  function resolveTarget(isFr) {
    var path = normalisePath(window.location.pathname);
    if (isFr) {
      return FR_TO_EN[path] || EN_HOME; // FR -> EN, fall back to EN home
    }
    return PAGE_MAP[path] || FR_HOME;   // EN -> FR, fall back to FR home
  }

  function build(isFr) {
    var target = resolveTarget(isFr);

    // The visible label names the destination language in that language
    // (autonym), which is the accessible convention for a language switch.
    var destLang = isFr ? "en" : "fr";
    var destLabelText = isFr ? "English" : "Français";
    // aria-label is written in the *current* page language for screen readers.
    var ariaLabel = isFr
      ? "Lire cette page en anglais"
      : "Read this page in French";

    var link = document.createElement("a");
    link.className = "lang-switcher";
    link.href = target;
    link.setAttribute("lang", destLang);
    link.setAttribute("hreflang", destLang);
    link.setAttribute("aria-label", ariaLabel);
    link.innerHTML =
      '<span class="lang-switcher-icon" aria-hidden="true">🌐</span>' +
      '<span class="lang-switcher-label">' + destLabelText + "</span>";

    document.body.appendChild(link);
    return link;
  }

  // Mirror reading-prefs.js: yield (fade out) only when the page-navigation
  // footer reaches the bottom band where this control sits, so the two corner
  // controls never fight for the corner — while staying usable on short pages
  // whose nav is on screen but well above the control. The negative-top
  // rootMargin shrinks the observation root to the bottom ~10% of the viewport.
  function yieldToPageNav(link) {
    if (!("IntersectionObserver" in window)) return;
    var nav = document.querySelector(".page-navigation");
    if (!nav) return;
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        link.classList.toggle("is-yielding", entry.isIntersecting);
      });
    }, { rootMargin: "-90% 0px 0px 0px" });
    observer.observe(nav);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var link = build(currentIsFr());
    yieldToPageNav(link);
  });
})();
