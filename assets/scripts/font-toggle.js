(function () {
  var STORAGE_KEY = "td:dyslexic-font";

  function isEnabled() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "1";
    } catch (e) {
      return false;
    }
  }

  function setEnabled(on) {
    try {
      if (on) {
        localStorage.setItem(STORAGE_KEY, "1");
      } else {
        localStorage.removeItem(STORAGE_KEY);
      }
    } catch (e) {
      /* localStorage may be disabled; the toggle still works in-session */
    }
  }

  function applyClass(on) {
    document.documentElement.classList.toggle("dyslexic-font", on);
    if (document.body) {
      document.body.classList.toggle("dyslexic-font", on);
    }
  }

  function build(initialOn) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "dyslexia-toggle";
    button.setAttribute("aria-pressed", initialOn ? "true" : "false");
    button.setAttribute("aria-label", "Dyslexia font");
    button.innerHTML =
      '<span class="dyslexia-toggle-icon" aria-hidden="true">Aa</span>' +
      '<span class="dyslexia-toggle-label">Dyslexia font</span>';

    button.addEventListener("click", function () {
      var next = button.getAttribute("aria-pressed") !== "true";
      applyClass(next);
      button.setAttribute("aria-pressed", next ? "true" : "false");
      setEnabled(next);
    });

    document.body.appendChild(button);
    return button;
  }

  function yieldToPageNav(button) {
    if (!("IntersectionObserver" in window)) return;
    var nav = document.querySelector(".page-navigation");
    if (!nav) return;
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        button.classList.toggle("is-yielding", entry.isIntersecting);
      });
    });
    observer.observe(nav);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var on = isEnabled();
    applyClass(on);
    var button = build(on);
    yieldToPageNav(button);
  });
})();
