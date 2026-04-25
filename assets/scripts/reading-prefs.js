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

  function build(initialFont, initialDark) {
    var trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "reading-prefs-toggle";
    trigger.setAttribute("aria-expanded", "false");
    trigger.setAttribute("aria-controls", "reading-prefs-panel");
    trigger.setAttribute("aria-label", "Reading preferences");
    trigger.innerHTML =
      '<span class="reading-prefs-toggle-icon" aria-hidden="true">Aa</span>' +
      '<span class="reading-prefs-toggle-label">Reading</span>';

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
      '<p class="reading-prefs-title" id="reading-prefs-title">Reading preferences</p>' +
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
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        trigger.classList.toggle("is-yielding", entry.isIntersecting);
        panel.classList.toggle("is-yielding", entry.isIntersecting);
      });
    });
    observer.observe(nav);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var fontOn = fontIsEnabled();
    applyFont(fontOn);
    var refs = build(fontOn, darkIsActive());
    wirePanel(refs);
    yieldToPageNav(refs.trigger, refs.panel);
  });
})();
