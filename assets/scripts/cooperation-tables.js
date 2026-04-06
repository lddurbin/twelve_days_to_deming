// Cooperation Tables Widget for Day 8 Major Activity
// Progressive cascade: Table One → Two → Three, Table Four → Five (merged with Three)

const RATINGS = ["+", "++", "+++", "0", "-", "--", "---"];

function nextRating(current) {
  const idx = RATINGS.indexOf(current);
  return RATINGS[(idx + 1) % RATINGS.length];
}

function ratingValue(r) {
  const map = { "+++": 3, "++": 2, "+": 1, "0": 0, "-": -1, "--": -2, "---": -3 };
  return map[r] ?? 0;
}

function formatNet(n) {
  if (n === 0) return "0";
  const sign = n > 0 ? "+" : "−";
  const abs = Math.abs(n);
  return sign.repeat(abs);
}

function ratingClass(r) {
  if (r.startsWith("+")) return "positive";
  if (r.startsWith("-") || r.startsWith("−")) return "negative";
  return "zero";
}

const TABLE_CSS = `
  .coop-table-container { margin: 1.5em 0; }
  .coop-table { border-collapse: collapse; width: 100%; font-size: 0.9em; }
  .coop-table th, .coop-table td {
    border: 1px solid #999; padding: 6px 8px; text-align: center;
  }
  .coop-table th { background: #f0f0f0; font-weight: 600; }
  .coop-table .area-header { font-weight: 700; text-align: left; }
  .coop-table .area-header-a { background: #5b9bd5; color: white; }
  .coop-table .area-header-b { background: #ed7d31; color: white; }
  .coop-table .area-header-c { background: #a5a510; color: white; }
  .coop-table .area-header-d { background: #7030a0; color: white; }
  .coop-table .option-name { text-align: left; min-width: 150px; }
  .coop-table .option-name input {
    border: 1px solid #ccc; padding: 3px 6px; width: 100%; font-size: 0.95em;
    background: #fffef0;
  }
  .coop-table .rating-cell {
    cursor: pointer; user-select: none; font-weight: 700; font-size: 1.1em;
    min-width: 45px; transition: background-color 0.15s;
  }
  .coop-table .rating-cell:hover { background: #e8e8e8; }
  .coop-table .rating-cell.positive { color: #1a7a1a; }
  .coop-table .rating-cell.negative { color: #c00; }
  .coop-table .rating-cell.zero { color: #888; }
  .coop-table .own-area { background: #d9d9d9; cursor: default; }
  .coop-table .own-area:hover { background: #d9d9d9; }
  .coop-table .net-cell { font-weight: 700; font-size: 1.1em; background: #f8f8f0; }
  .coop-table .net-cell.positive { color: #1a7a1a; }
  .coop-table .net-cell.negative { color: #c00; }
  .coop-table .net-cell.zero { color: #888; }
  .coop-table .net-row { background: #eee; font-weight: 700; }
  .coop-table .net-row td { border-top: 2px solid #666; }
  .coop-area-setup { margin: 1em 0; }
  .coop-area-setup label { font-weight: 600; margin-right: 0.5em; }
  .coop-area-setup input {
    border: 1px solid #ccc; padding: 4px 8px; margin-right: 1.5em; width: 180px;
  }
  .coop-add-option { margin: 0.5em 0; }
  .coop-add-option button {
    font-size: 0.85em; padding: 3px 10px; cursor: pointer;
    border: 1px solid #999; background: #f5f5f5; border-radius: 3px;
  }
  .coop-add-option button:hover { background: #e0e0e0; }
  .coop-download-btn {
    margin: 1.5em 0; padding: 8px 20px; font-size: 1em;
    cursor: pointer; border: none; border-radius: 4px;
    background: #0d6efd; color: white; font-weight: 600;
  }
  .coop-download-btn:hover { background: #0b5ed7; }
`;

function injectCSS() {
  if (document.getElementById("coop-table-styles")) return;
  const style = document.createElement("style");
  style.id = "coop-table-styles";
  style.textContent = TABLE_CSS;
  document.head.appendChild(style);
}

function areaClass(idx) {
  return ["area-header-a", "area-header-b", "area-header-c", "area-header-d"][idx] || "area-header-a";
}

function buildTableHTML(areas, optionsPerArea, showNetColumn, showNetRow, ownAreaGreyed, allowOwnArea) {
  const cols = areas.length;
  const totalCols = 1 + cols + (showNetColumn ? 1 : 0);

  let html = `<table class="coop-table">`;
  // Header
  html += `<thead><tr><th rowspan="2">Areas and their Options</th>`;
  html += `<th colspan="${cols}">Effects of Options</th>`;
  if (showNetColumn) html += `<th rowspan="2">Net Effect on<br>the Company</th>`;
  html += `</tr><tr>`;
  areas.forEach((a, i) => {
    html += `<th class="${areaClass(i)}">Effect on<br>${a || `Area ${String.fromCharCode(65 + i)}`}</th>`;
  });
  html += `</tr></thead><tbody>`;

  areas.forEach((area, areaIdx) => {
    // Area header row
    html += `<tr><td class="area-header ${areaClass(areaIdx)}" colspan="${totalCols}">${area || `Area ${String.fromCharCode(65 + areaIdx)}`}:</td></tr>`;
    // Option rows
    const numOpts = optionsPerArea[areaIdx] || 0;
    for (let o = 0; o < numOpts; o++) {
      html += `<tr data-area="${areaIdx}" data-option="${o}">`;
      html += `<td class="option-name"><input type="text" data-area="${areaIdx}" data-option="${o}" placeholder="Option ${String.fromCharCode(97 + areaIdx)}${o + 1}"></td>`;
      areas.forEach((_, colIdx) => {
        const isOwn = colIdx === areaIdx;
        if (isOwn && ownAreaGreyed && !allowOwnArea) {
          html += `<td class="rating-cell own-area" data-area="${areaIdx}" data-option="${o}" data-col="${colIdx}"></td>`;
        } else {
          html += `<td class="rating-cell" data-area="${areaIdx}" data-option="${o}" data-col="${colIdx}" data-rating=""></td>`;
        }
      });
      if (showNetColumn) {
        html += `<td class="net-cell" data-area="${areaIdx}" data-option="${o}"></td>`;
      }
      html += `</tr>`;
    }
  });

  if (showNetRow) {
    html += `<tr class="net-row"><td>Net Effect of Adopted Options</td>`;
    areas.forEach((_, colIdx) => {
      html += `<td class="net-cell" data-col-total="${colIdx}"></td>`;
    });
    if (showNetColumn) html += `<td class="net-cell" data-grand-total></td>`;
    html += `</tr>`;
  }

  html += `</tbody></table>`;
  return html;
}

function getData(container) {
  const data = {};
  container.querySelectorAll(".rating-cell:not(.own-area)").forEach(cell => {
    const area = cell.dataset.area;
    const opt = cell.dataset.option;
    const col = cell.dataset.col;
    const rating = cell.dataset.rating || "";
    if (!data[area]) data[area] = {};
    if (!data[area][opt]) data[area][opt] = {};
    data[area][opt][col] = rating;
  });
  // Include own-area cells that are clickable (Table Four)
  container.querySelectorAll(".rating-cell.own-area-clickable").forEach(cell => {
    const area = cell.dataset.area;
    const opt = cell.dataset.option;
    const col = cell.dataset.col;
    const rating = cell.dataset.rating || "";
    if (!data[area]) data[area] = {};
    if (!data[area][opt]) data[area][opt] = {};
    data[area][opt][col] = rating;
  });
  const names = {};
  container.querySelectorAll(".option-name input").forEach(inp => {
    const area = inp.dataset.area;
    const opt = inp.dataset.option;
    if (!names[area]) names[area] = {};
    names[area][opt] = inp.value;
  });
  return { ratings: data, names };
}

function computeNetEffects(container, areas) {
  const cells = container.querySelectorAll(".rating-cell:not(.own-area)");
  const byRow = {};
  cells.forEach(cell => {
    const key = `${cell.dataset.area}-${cell.dataset.option}`;
    if (!byRow[key]) byRow[key] = [];
    byRow[key].push(ratingValue(cell.dataset.rating || "0"));
  });
  // Also include own-area-clickable cells
  container.querySelectorAll(".rating-cell.own-area-clickable").forEach(cell => {
    const key = `${cell.dataset.area}-${cell.dataset.option}`;
    if (!byRow[key]) byRow[key] = [];
    byRow[key].push(ratingValue(cell.dataset.rating || "0"));
  });

  // Update row net cells
  container.querySelectorAll(".net-cell[data-area]").forEach(cell => {
    const key = `${cell.dataset.area}-${cell.dataset.option}`;
    const vals = byRow[key] || [];
    const net = vals.reduce((a, b) => a + b, 0);
    cell.textContent = formatNet(net);
    cell.className = `net-cell ${net > 0 ? "positive" : net < 0 ? "negative" : "zero"}`;
  });

  // Update column totals
  const colTotals = new Array(areas.length).fill(0);
  let grandTotal = 0;
  Object.entries(byRow).forEach(([, vals]) => {
    // We need per-column data, not just row sums
  });

  // Recalculate column totals from individual cells
  for (let c = 0; c < areas.length; c++) {
    let total = 0;
    container.querySelectorAll(`.rating-cell[data-col="${c}"]:not(.own-area)`).forEach(cell => {
      total += ratingValue(cell.dataset.rating || "0");
    });
    container.querySelectorAll(`.rating-cell.own-area-clickable[data-col="${c}"]`).forEach(cell => {
      total += ratingValue(cell.dataset.rating || "0");
    });
    colTotals[c] = total;
    const colCell = container.querySelector(`[data-col-total="${c}"]`);
    if (colCell) {
      colCell.textContent = formatNet(total);
      colCell.className = `net-cell ${total > 0 ? "positive" : total < 0 ? "negative" : "zero"}`;
    }
  }

  grandTotal = colTotals.reduce((a, b) => a + b, 0);
  const grandCell = container.querySelector("[data-grand-total]");
  if (grandCell) {
    grandCell.textContent = formatNet(grandTotal);
    grandCell.className = `net-cell ${grandTotal > 0 ? "positive" : grandTotal < 0 ? "negative" : "zero"}`;
  }
}

function attachRatingClicks(container, areas, onChange) {
  container.querySelectorAll(".rating-cell:not(.own-area)").forEach(cell => {
    cell.addEventListener("click", () => {
      const current = cell.dataset.rating || "";
      const next = current === "" ? "+" : nextRating(current);
      cell.dataset.rating = next;
      cell.textContent = next;
      cell.className = `rating-cell ${ratingClass(next)}`;
      computeNetEffects(container, areas);
      if (onChange) onChange();
    });
  });
}

// === PUBLIC API ===

export function createAreaSetup(numAreas) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-area-setup";
  const inputs = [];
  for (let i = 0; i < numAreas; i++) {
    const label = document.createElement("label");
    label.textContent = `Area ${String.fromCharCode(65 + i)}:`;
    const input = document.createElement("input");
    input.type = "text";
    input.placeholder = `e.g. ${["Sales", "Manufacturing", "Admin", "Delivery"][i] || "Department"}`;
    input.dataset.areaIndex = i;
    container.appendChild(label);
    container.appendChild(input);
    inputs.push(input);
  }
  container._inputs = inputs;
  return container;
}

export function getAreaNames(setupContainer) {
  return setupContainer._inputs.map((inp, i) =>
    inp.value || `Area ${String.fromCharCode(65 + i)}`
  );
}

export function createTableOne(areas, initialOptions) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-table-container";

  const optsPerArea = initialOptions || areas.map(() => 3);
  container.innerHTML = buildTableHTML(areas, optsPerArea, false, false, true, false);

  // Make own-area cells show "+" automatically (all options benefit own area)
  container.querySelectorAll(".rating-cell.own-area").forEach(cell => {
    cell.textContent = "";  // greyed out — own area effect not shown in Table One
  });

  attachRatingClicks(container, areas, () => {
    container.dispatchEvent(new Event("change", { bubbles: true }));
  });

  // Add option buttons
  areas.forEach((_, areaIdx) => {
    const addBtn = document.createElement("div");
    addBtn.className = "coop-add-option";
    addBtn.innerHTML = `<button data-area="${areaIdx}">+ Add option to ${areas[areaIdx]}</button>`;
    // Insert after the last option row for this area
    const areaRows = container.querySelectorAll(`tr[data-area="${areaIdx}"]`);
    if (areaRows.length > 0) {
      const lastRow = areaRows[areaRows.length - 1];
      lastRow.parentNode.insertBefore(createRowFromButton(addBtn, areaIdx, areas, container), lastRow.nextSibling);
    }
  });

  return container;
}

function createRowFromButton(btnDiv, areaIdx, areas, container) {
  // This is a placeholder — actual add-option logic would be more complex
  // For simplicity, we start with 3 options per area and let users type in them
  return document.createComment(""); // no-op for now
}

export function createTableTwo(areas, tableOneContainer) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-table-container";

  // Count options from Table One
  const optsPerArea = areas.map((_, i) => {
    return tableOneContainer.querySelectorAll(`tr[data-area="${i}"]`).length;
  });

  container.innerHTML = buildTableHTML(areas, optsPerArea, true, true, false, false);

  // Copy option names from Table One
  tableOneContainer.querySelectorAll(".option-name input").forEach(inp => {
    const target = container.querySelector(`.option-name input[data-area="${inp.dataset.area}"][data-option="${inp.dataset.option}"]`);
    if (target) {
      target.value = inp.value;
      target.readOnly = true;
      target.style.background = "#f0f0f0";
    }
  });

  // Copy ratings from Table One (non-own-area cells)
  tableOneContainer.querySelectorAll(".rating-cell:not(.own-area)").forEach(srcCell => {
    const rating = srcCell.dataset.rating || "";
    const tgtCell = container.querySelector(`.rating-cell[data-area="${srcCell.dataset.area}"][data-option="${srcCell.dataset.option}"][data-col="${srcCell.dataset.col}"]`);
    if (tgtCell && rating) {
      tgtCell.dataset.rating = rating;
      tgtCell.textContent = rating;
      tgtCell.className = `rating-cell ${ratingClass(rating)}`;
    }
  });

  attachRatingClicks(container, areas, () => {
    computeNetEffects(container, areas);
    container.dispatchEvent(new Event("change", { bubbles: true }));
  });
  computeNetEffects(container, areas);

  return container;
}

export function createTableThree(areas, tableTwoContainer) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-table-container";

  // Find rows with positive net effect from Table Two
  const positiveRows = [];
  tableTwoContainer.querySelectorAll(".net-cell[data-area]").forEach(cell => {
    const net = parseInt(cell.textContent.replace(/[^0-9-]/g, "")) || 0;
    // Check if net is positive by looking at the formatted text
    const text = cell.textContent;
    const isPositive = text.includes("+") && !text.startsWith("−") && text !== "0";
    if (isPositive || ratingValue(cell.textContent.replace(/−/g, "-")) > 0) {
      positiveRows.push({ area: cell.dataset.area, option: cell.dataset.option });
    }
  });

  // Build a filtered version — just show positive rows
  // Count positive options per area
  const optsPerArea = areas.map((_, i) =>
    positiveRows.filter(r => r.area === String(i)).length
  );

  container.innerHTML = buildTableHTML(areas, optsPerArea, true, true, false, false);

  // Copy data from Table Two for positive rows only
  let optCounter = {};
  positiveRows.forEach(({ area, option }) => {
    if (!optCounter[area]) optCounter[area] = 0;
    const newOpt = optCounter[area];

    // Copy name
    const srcName = tableTwoContainer.querySelector(`.option-name input[data-area="${area}"][data-option="${option}"]`);
    const tgtName = container.querySelector(`.option-name input[data-area="${area}"][data-option="${newOpt}"]`);
    if (srcName && tgtName) {
      tgtName.value = srcName.value;
      tgtName.readOnly = true;
      tgtName.style.background = "#f0f0f0";
    }

    // Copy ratings
    areas.forEach((_, colIdx) => {
      const srcCell = tableTwoContainer.querySelector(`.rating-cell[data-area="${area}"][data-option="${option}"][data-col="${colIdx}"]`);
      const tgtCell = container.querySelector(`.rating-cell[data-area="${area}"][data-option="${newOpt}"][data-col="${colIdx}"]`);
      if (srcCell && tgtCell) {
        const rating = srcCell.dataset.rating || "";
        tgtCell.dataset.rating = rating;
        tgtCell.textContent = rating;
        tgtCell.className = `rating-cell ${ratingClass(rating)}`;
      }
    });

    optCounter[area]++;
  });

  // Make all cells read-only in Table Three
  container.querySelectorAll(".rating-cell").forEach(cell => {
    cell.style.cursor = "default";
  });

  computeNetEffects(container, areas);
  return container;
}

export function createTableFour(areas, initialOptions) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-table-container";

  const optsPerArea = initialOptions || areas.map(() => 2);
  container.innerHTML = buildTableHTML(areas, optsPerArea, true, true, false, true);

  // In Table Four, own-area cells ARE clickable (and typically negative)
  // Remove the own-area grey styling but mark them
  container.querySelectorAll(".rating-cell").forEach(cell => {
    // All cells are clickable in Table Four
  });

  attachRatingClicks(container, areas, () => {
    computeNetEffects(container, areas);
    container.dispatchEvent(new Event("change", { bubbles: true }));
  });

  return container;
}

export function createTableFive(areas, tableThreeContainer, tableFourContainer) {
  injectCSS();
  const container = document.createElement("div");
  container.className = "coop-table-container";

  // Count options: Table Three rows + positive Table Four rows
  const threeOpts = areas.map((_, i) =>
    tableThreeContainer.querySelectorAll(`tr[data-area="${i}"]`).length
  );

  // Find positive rows from Table Four
  const fourPositiveRows = [];
  tableFourContainer.querySelectorAll(".net-cell[data-area]").forEach(cell => {
    const text = cell.textContent;
    const val = text.split("").reduce((sum, ch) => {
      if (ch === "+") return sum + 1;
      if (ch === "−" || ch === "-") return sum - 1;
      return sum;
    }, 0);
    if (val > 0) {
      fourPositiveRows.push({ area: cell.dataset.area, option: cell.dataset.option });
    }
  });

  const fourOpts = areas.map((_, i) =>
    fourPositiveRows.filter(r => r.area === String(i)).length
  );

  const totalOpts = areas.map((_, i) => threeOpts[i] + fourOpts[i]);
  container.innerHTML = buildTableHTML(areas, totalOpts, true, true, false, true);

  // Copy from Table Three
  areas.forEach((_, areaIdx) => {
    for (let o = 0; o < threeOpts[areaIdx]; o++) {
      const srcName = tableThreeContainer.querySelector(`.option-name input[data-area="${areaIdx}"][data-option="${o}"]`);
      const tgtName = container.querySelector(`.option-name input[data-area="${areaIdx}"][data-option="${o}"]`);
      if (srcName && tgtName) {
        tgtName.value = srcName.value;
        tgtName.readOnly = true;
        tgtName.style.background = "#f0f0f0";
      }
      areas.forEach((_, colIdx) => {
        const srcCell = tableThreeContainer.querySelector(`.rating-cell[data-area="${areaIdx}"][data-option="${o}"][data-col="${colIdx}"]`);
        const tgtCell = container.querySelector(`.rating-cell[data-area="${areaIdx}"][data-option="${o}"][data-col="${colIdx}"]`);
        if (srcCell && tgtCell) {
          const rating = srcCell.dataset.rating || "";
          tgtCell.dataset.rating = rating;
          tgtCell.textContent = rating;
          tgtCell.className = `rating-cell ${ratingClass(rating)}`;
        }
      });
    }
  });

  // Copy positive rows from Table Four
  let fourOptCounter = {};
  fourPositiveRows.forEach(({ area, option }) => {
    if (!fourOptCounter[area]) fourOptCounter[area] = 0;
    const newOpt = threeOpts[parseInt(area)] + fourOptCounter[area];

    const srcName = tableFourContainer.querySelector(`.option-name input[data-area="${area}"][data-option="${option}"]`);
    const tgtName = container.querySelector(`.option-name input[data-area="${area}"][data-option="${newOpt}"]`);
    if (srcName && tgtName) {
      tgtName.value = srcName.value;
      tgtName.readOnly = true;
      tgtName.style.background = "#f0f0f0";
    }
    areas.forEach((_, colIdx) => {
      const srcCell = tableFourContainer.querySelector(`.rating-cell[data-area="${area}"][data-option="${option}"][data-col="${colIdx}"]`);
      const tgtCell = container.querySelector(`.rating-cell[data-area="${area}"][data-option="${newOpt}"][data-col="${colIdx}"]`);
      if (srcCell && tgtCell) {
        const rating = srcCell.dataset.rating || "";
        tgtCell.dataset.rating = rating;
        tgtCell.textContent = rating;
        tgtCell.className = `rating-cell ${ratingClass(rating)}`;
      }
    });

    fourOptCounter[area]++;
  });

  // Make all cells read-only
  container.querySelectorAll(".rating-cell").forEach(cell => {
    cell.style.cursor = "default";
  });

  computeNetEffects(container, areas);
  return container;
}

export function createCoopDownloadButton(areas, containers, fileName) {
  const button = document.createElement("button");
  button.className = "coop-download-btn";
  button.type = "button";
  button.textContent = "Download Your Exercise";
  button.onclick = () => {
    let text = "MAJOR ACTIVITY 8-d: Cooperation Exercise\n";
    text += "=" .repeat(50) + "\n\n";
    text += `Areas: ${areas.join(", ")}\n\n`;

    const tableNames = ["TABLE ONE", "TABLE TWO", "TABLE THREE", "TABLE FOUR", "TABLE FIVE"];
    containers.forEach((cont, idx) => {
      if (!cont) return;
      text += `${tableNames[idx]}\n${"─".repeat(40)}\n`;
      const rows = cont.querySelectorAll("tr[data-area]");
      rows.forEach(row => {
        const nameInput = row.querySelector(".option-name input");
        const name = nameInput ? nameInput.value : "";
        const ratings = [];
        row.querySelectorAll(".rating-cell").forEach(cell => {
          ratings.push(cell.dataset.rating || cell.textContent || "—");
        });
        const netCell = row.querySelector(".net-cell");
        const net = netCell ? netCell.textContent : "";
        text += `  ${name || "(unnamed)"}: ${ratings.join(" | ")}${net ? ` → Net: ${net}` : ""}\n`;
      });
      const grandTotal = cont.querySelector("[data-grand-total]");
      if (grandTotal) text += `  Grand Total: ${grandTotal.textContent}\n`;
      text += "\n";
    });

    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 100);
  };
  return button;
}
