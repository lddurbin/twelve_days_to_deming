(function () {
  // Glossary tooltips for <dfn data-definition="…">term</dfn>.
  // The dfn's data-definition becomes a sibling <span role="tooltip">; the
  // dfn is made focusable and points to that span via aria-describedby. CSS
  // handles the visible reveal on :hover and :focus; this script's job is
  // wiring the relationship and dismissing on Escape for keyboard users.

  var counter = 0;

  function nextId() {
    counter += 1;
    return "dfn-tooltip-" + counter;
  }

  function decorate(dfn) {
    var def = dfn.getAttribute("data-definition");
    if (!def) return;

    if (!dfn.hasAttribute("tabindex")) dfn.setAttribute("tabindex", "0");

    var tipId = nextId();
    var tip = document.createElement("span");
    tip.className = "dfn-tooltip";
    tip.id = tipId;
    tip.setAttribute("role", "tooltip");
    // The tooltip is a child of the dfn so the dfn's `position: relative`
    // establishes its containing block. aria-hidden keeps screen readers
    // from reading the definition inline when traversing the dfn's text
    // content — aria-describedby still consults this element by id.
    tip.setAttribute("aria-hidden", "true");
    tip.textContent = def;
    dfn.appendChild(tip);

    dfn.setAttribute("aria-describedby", tipId);
  }

  function dismissOnEscape(e) {
    if (e.key !== "Escape") return;
    var active = document.activeElement;
    if (active && active.matches && active.matches("dfn[data-definition]")) {
      active.blur();
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    var nodes = document.querySelectorAll("dfn[data-definition]");
    Array.prototype.forEach.call(nodes, decorate);
    if (nodes.length > 0) {
      document.addEventListener("keydown", dismissOnEscape);
    }
  });
})();
