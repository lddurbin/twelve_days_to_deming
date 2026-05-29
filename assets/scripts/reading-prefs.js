(function () {
  var FONT_KEY = "td:dyslexic-font";

  function safeGet(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }
  function safeSet(key, value) {
    try {
      if (value === null) localStorage.removeItem(key);
      else localStorage.setItem(key, value);
    } catch (e) { /* localStorage may be disabled */ }
  }

  function fontIsEnabled() {
    return safeGet(FONT_KEY) === "1";
  }
  function applyFont(on) {
    document.documentElement.classList.toggle("dyslexic-font", on);
    if (document.body) document.body.classList.toggle("dyslexic-font", on);
    safeSet(FONT_KEY, on ? "1" : null);
  }

  function darkIsActive() {
    return document.body.classList.contains("quarto-dark");
  }
  function toggleDark() {
    // Defer to Quarto's built-in handler — it swaps the active stylesheet,
    // updates localStorage, and re-applies syntax-highlighting CSS in one
    // call. Reimplementing would duplicate logic that already exists.
    if (typeof window.quartoToggleColorScheme === "function") {
      window.quartoToggleColorScheme();
    }
  }

  // ----- Language switch ----------------------------------------------------
  // The panel doubles as the language switcher, so there is one corner control
  // rather than two. EN<->FR correspondence is explicit because the editions
  // are not a clean path-prefix mirror (EN: /content/…, home /index.html; FR:
  // /fr/content-fr/…, home /fr/index.fr.html). A page with no known counterpart
  // falls back to the other edition's home, so the link can never 404.
  var PAGE_MAP = {
    "/index.html": "/fr/index.fr.html",
    "/welcome.html": "/fr/content-fr/welcome.html"
  };
  var EN_HOME = "/index.html";
  var FR_HOME = "/fr/index.fr.html";
  var FR_TO_EN = {};
  Object.keys(PAGE_MAP).forEach(function (en) { FR_TO_EN[PAGE_MAP[en]] = en; });

  function currentIsFr() {
    return /(^|\/)fr\//.test(window.location.pathname);
  }
  function normaliseLangPath(path) {
    if (path === "" || path === "/") return EN_HOME;
    if (/\/fr\/?$/.test(path)) return FR_HOME;
    return path;
  }
  function languageTarget(isFr) {
    var path = normaliseLangPath(window.location.pathname);
    return isFr ? (FR_TO_EN[path] || EN_HOME) : (PAGE_MAP[path] || FR_HOME);
  }

  function build(initialFont, initialDark) {
    // Language row content, resolved for the current edition. The link text is
    // the destination language's autonym (lang-tagged for correct
    // pronunciation); the row label is in the current page's language.
    var isFr = currentIsFr();
    var langTarget = languageTarget(isFr);
    var langRowLabel = isFr ? "Langue" : "Language";
    var langName = isFr ? "English" : "Français";
    var langDest = isFr ? "en" : "fr";

    var trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "reading-prefs-toggle";
    trigger.setAttribute("aria-expanded", "false");
    trigger.setAttribute("aria-controls", "reading-prefs-panel");
    trigger.setAttribute("aria-label", "Preferences");
    trigger.innerHTML =
      '<span class="reading-prefs-toggle-icon" aria-hidden="true">Aa</span>' +
      '<span class="reading-prefs-toggle-label">Preferences</span>';

    var panel = document.createElement("div");
    panel.id = "reading-prefs-panel";
    panel.className = "reading-prefs-panel";
    // Disclosure pattern: trigger carries aria-expanded/aria-controls; the
    // revealed region is labelled by its own heading. A dialog role would
    // imply modal semantics (focus trap, aria-modal) that don't match the
    // outside-click-to-dismiss behaviour.
    panel.setAttribute("aria-labelledby", "reading-prefs-title");
    panel.hidden = true;
    panel.innerHTML =
      '<p class="reading-prefs-title" id="reading-prefs-title">Preferences</p>' +
      '<div class="reading-prefs-row">' +
      '  <span class="reading-prefs-row-label" id="reading-prefs-theme-label">Theme</span>' +
      '  <button type="button" class="reading-prefs-control" data-pref="theme"' +
      '    aria-pressed="' + (initialDark ? "true" : "false") + '"' +
      '    aria-labelledby="reading-prefs-theme-label reading-prefs-theme-state">' +
      '    <span class="reading-prefs-state" id="reading-prefs-theme-state">' +
            (initialDark ? "Dark" : "Light") + '</span>' +
      '  </button>' +
      '</div>' +
      '<div class="reading-prefs-row">' +
      '  <span class="reading-prefs-row-label" id="reading-prefs-font-label">Dyslexia font</span>' +
      '  <button type="button" class="reading-prefs-control" data-pref="font"' +
      '    aria-pressed="' + (initialFont ? "true" : "false") + '"' +
      '    aria-labelledby="reading-prefs-font-label reading-prefs-font-state">' +
      '    <span class="reading-prefs-state" id="reading-prefs-font-state">' +
            (initialFont ? "On" : "Off") + '</span>' +
      '  </button>' +
      '</div>' +
      '<div class="reading-prefs-row">' +
      '  <span class="reading-prefs-row-label" id="reading-prefs-lang-label">' +
            langRowLabel + '</span>' +
      '  <a class="reading-prefs-lang-link" href="' + langTarget + '"' +
      '    hreflang="' + langDest + '"' +
      '    aria-labelledby="reading-prefs-lang-label reading-prefs-lang-name">' +
      '    <span class="reading-prefs-lang-name" id="reading-prefs-lang-name"' +
      '      lang="' + langDest + '">' + langName + '</span>' +
      '    <span class="reading-prefs-lang-arrow" aria-hidden="true">→</span>' +
      '  </a>' +
      '</div>';

    document.body.appendChild(trigger);
    document.body.appendChild(panel);

    var themeBtn = panel.querySelector('[data-pref="theme"]');
    var themeState = panel.querySelector("#reading-prefs-theme-state");
    var fontBtn = panel.querySelector('[data-pref="font"]');
    var fontState = panel.querySelector("#reading-prefs-font-state");

    themeBtn.addEventListener("click", function () {
      toggleDark();
      var on = darkIsActive();
      themeBtn.setAttribute("aria-pressed", on ? "true" : "false");
      themeState.textContent = on ? "Dark" : "Light";
    });

    fontBtn.addEventListener("click", function () {
      var on = fontBtn.getAttribute("aria-pressed") !== "true";
      applyFont(on);
      fontBtn.setAttribute("aria-pressed", on ? "true" : "false");
      fontState.textContent = on ? "On" : "Off";
    });

    return { trigger: trigger, panel: panel };
  }

  function wirePanel(refs) {
    var trigger = refs.trigger;
    var panel = refs.panel;
    var firstControl = panel.querySelector("button");
    var lastFocused = null;

    function open() {
      lastFocused = document.activeElement;
      panel.hidden = false;
      trigger.setAttribute("aria-expanded", "true");
      // Focus the first control so keyboard users land inside the panel.
      if (firstControl) firstControl.focus();
    }
    function close(restoreFocus) {
      panel.hidden = true;
      trigger.setAttribute("aria-expanded", "false");
      if (restoreFocus) {
        (lastFocused && lastFocused.focus ? lastFocused : trigger).focus();
      }
    }

    trigger.addEventListener("click", function () {
      if (panel.hidden) open(); else close(true);
    });

    document.addEventListener("keydown", function (e) {
      if (panel.hidden) return;
      if (e.key === "Escape") {
        e.preventDefault();
        close(true);
      }
    });

    document.addEventListener("click", function (e) {
      if (panel.hidden) return;
      if (panel.contains(e.target) || trigger.contains(e.target)) return;
      close(false);
    });
  }

  function yieldToPageNav(trigger, panel) {
    if (!("IntersectionObserver" in window)) return;
    var nav = document.querySelector(".page-navigation");
    if (!nav) return;
    // Only yield on pages that can actually scroll. On a short, unscrollable
    // page the page-nav is statically on screen, so hiding the control to
    // "make way" for it would hide the control permanently and leave it
    // unreachable. There, keep the control usable. (A percentage rootMargin
    // band was tried first but Firefox ignores it, and on a short viewport the
    // nav genuinely sits where the control does — so scrollability, not
    // overlap, is the right test.)
    var navVisible = false;
    function apply() {
      var scrollable =
        document.documentElement.scrollHeight > window.innerHeight + 4;
      var yielding = scrollable && navVisible;
      trigger.classList.toggle("is-yielding", yielding);
      panel.classList.toggle("is-yielding", yielding);
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) { navVisible = entry.isIntersecting; });
      apply();
    });
    observer.observe(nav);
    // Re-evaluate when the viewport resizes (e.g. DevTools opening can flip a
    // page between scrollable and not) without waiting for an observer event.
    window.addEventListener("resize", apply);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var fontOn = fontIsEnabled();
    applyFont(fontOn);
    var refs = build(fontOn, darkIsActive());
    wirePanel(refs);
    yieldToPageNav(refs.trigger, refs.panel);
  });
})();
