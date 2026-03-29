// ============================================================
// Funnel Experiment — shared pure-function module
// Used by OJS cells in chapters 11, 12, and 13 of Day 3
// ============================================================

// --- Constants ---

export const TARGET = 30;
let trackSvgId = 0;
export const TRACK_MIN = 20;
export const TRACK_MAX = 40;
export const TOTAL_STAGES = 40;

// Author's first 5 dice-scores (used for demonstration)
export const AUTHOR_FIRST_5 = [10, 8, 6, 7, 4];

// --- Dice mechanics ---

// Dice-score to displacement lookup (matches source table on p.39)
// dice-score 2 → 5 left, ..., 7 → under, ..., 12 → 5 right
const DISPLACEMENT_TABLE = {
  2: -5, 3: -4, 4: -3, 5: -2, 6: -1,
  7:  0,
  8:  1, 9:  2, 10: 3, 11: 4, 12: 5
};

export function diceToDisplacement(diceScore) {
  return DISPLACEMENT_TABLE[diceScore];
}

export function displacementToDirection(displacement) {
  if (displacement < 0) return `${Math.abs(displacement)}L`;
  if (displacement > 0) return `${displacement}R`;
  return "↓";
}

// Generate a full sequence of 40 dice rolls
// Each entry: { die1, die2, diceScore, displacement, direction }
export function generateDiceSequence(authorFirst5 = true) {
  const seq = [];
  for (let i = 0; i < TOTAL_STAGES; i++) {
    let die1, die2;
    if (authorFirst5 && i < 5) {
      // Use author's worked example for first 5 stages
      const ds = AUTHOR_FIRST_5[i];
      // Decompose into plausible die pair
      die1 = Math.min(6, Math.max(1, Math.ceil(ds / 2)));
      die2 = ds - die1;
    } else {
      die1 = Math.floor(Math.random() * 6) + 1;
      die2 = Math.floor(Math.random() * 6) + 1;
    }
    const diceScore = die1 + die2;
    const displacement = diceToDisplacement(diceScore);
    const direction = displacementToDirection(displacement);
    seq.push({ die1, die2, diceScore, displacement, direction });
  }
  return seq;
}

// --- Rule engines ---

// Compute marble position for a single stage
// funnelPos: current funnel position
// displacement: from dice (negative = left, positive = right)
// Returns: marble's absolute position on the track
export function computeMarble(funnelPos, displacement) {
  return funnelPos + displacement;
}

// Compute next funnel position given a rule
// rule: 1, 2, 3, or 4
// funnelPos: current funnel position
// marblePos: where the marble just landed
// target: the target position (default 30)
export function nextFunnel(rule, funnelPos, marblePos, target = TARGET) {
  switch (rule) {
    case 1:
      // Rule 1: Leave the funnel at the target. Never move it.
      return target;
    case 2:
      // Rule 2: Compensate. If marble is off-target, move funnel
      // by the same amount in the opposite direction.
      // e.g. marble at 33 (3 right of 30) → move funnel 3 left
      return funnelPos - (marblePos - target);
    case 3:
      // Rule 3: Place funnel on opposite side of target from marble,
      // at the same distance. Equivalent to: funnel = 2*target - marble
      return 2 * target - marblePos;
    case 4:
      // Rule 4: Place funnel exactly where the marble landed.
      return marblePos;
    default:
      throw new Error(`Unknown rule: ${rule}`);
  }
}

// Run all stages for a given rule and dice sequence
// Returns array of stage objects with full state
export function runAllStages(rule, diceSequence) {
  const stages = [];
  let funnelPos = TARGET; // Always start at target

  for (let i = 0; i < diceSequence.length; i++) {
    const dice = diceSequence[i];
    const marblePos = computeMarble(funnelPos, dice.displacement);

    // For Rule 2 book-keeping: marble relative to target
    const relativeToTarget = marblePos - TARGET;

    stages.push({
      stage: i + 1,
      funnelBefore: funnelPos,
      diceScore: dice.diceScore,
      displacement: dice.displacement,
      direction: dice.direction,
      marblePos: marblePos,
      relativeToTarget: relativeToTarget,
      funnelAfter: nextFunnel(rule, funnelPos, marblePos)
    });

    funnelPos = nextFunnel(rule, funnelPos, marblePos);
  }

  return stages;
}

// --- localStorage bridge ---

const STORAGE_KEY = "funnel_dice_sequence";

export function saveDiceSequence(seq) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(seq));
  } catch (e) {
    // localStorage unavailable — silently continue
  }
}

export function loadDiceSequence() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (Array.isArray(parsed) && parsed.length === TOTAL_STAGES) {
        return parsed;
      }
    }
  } catch (e) {
    // localStorage unavailable or corrupt
  }
  return null;
}

export function clearDiceSequence() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch (e) {
    // silently continue
  }
}

// --- Track helpers ---

// Compute the visible range of the track for a set of stages
// For Rules 1 & 2, track stays within 20-40
// For Rules 3 & 4, track may need to extend
export function computeTrackRange(stages) {
  if (stages.length === 0) return { min: TRACK_MIN, max: TRACK_MAX };

  let lo = TRACK_MIN;
  let hi = TRACK_MAX;

  for (const s of stages) {
    lo = Math.min(lo, s.marblePos, s.funnelBefore, s.funnelAfter);
    hi = Math.max(hi, s.marblePos, s.funnelBefore, s.funnelAfter);
  }

  // Add 2-cell padding
  lo = Math.min(lo - 2, TRACK_MIN);
  hi = Math.max(hi + 2, TRACK_MAX);

  return { min: lo, max: hi };
}

// --- SVG track renderer ---

// Returns an SVG string for the track visualisation
export function renderTrackSVG(currentStage, trackRange) {
  const cellW = 36;
  const cellH = 40;
  const padding = 10;
  const cells = trackRange.max - trackRange.min + 1;
  const totalW = cells * cellW + padding * 2;
  const totalH = cellH + 60 + padding * 2; // room for icons above

  const funnelLabel = currentStage ? `Funnel at ${currentStage.funnelBefore}, marble at ${currentStage.marblePos}.` : "No stage active.";
  const titleId = `track-title-${++trackSvgId}`;
  const descId = `track-desc-${trackSvgId}`;
  let svg = `<svg role="img" aria-labelledby="${titleId}" aria-describedby="${descId}" width="${totalW}" height="${totalH}" viewBox="0 0 ${totalW} ${totalH}" xmlns="http://www.w3.org/2000/svg" style="font-family: sans-serif; max-width: 100%;">`;
  svg += `<title id="${titleId}">Funnel Experiment Track</title>`;
  svg += `<desc id="${descId}">Track showing positions ${trackRange.min} to ${trackRange.max}. ${funnelLabel}</desc>`;

  // Draw cells
  for (let pos = trackRange.min; pos <= trackRange.max; pos++) {
    const x = (pos - trackRange.min) * cellW + padding;
    const y = 50 + padding;
    const isTarget = pos === TARGET;
    const inNormalRange = pos >= TRACK_MIN && pos <= TRACK_MAX;

    let fill;
    if (isTarget) {
      fill = "#90EE90"; // green for target
    } else if (!inNormalRange) {
      fill = "#d9d9d9"; // grey for extended range
    } else if (pos % 2 === 0) {
      fill = "#ffff66"; // yellow
    } else {
      fill = "#66cc66"; // green
    }

    // Highlight marble position
    if (currentStage && pos === currentStage.marblePos) {
      fill = "#ff6666"; // red for marble
    }

    svg += `<rect x="${x}" y="${y}" width="${cellW}" height="${cellH}" fill="${fill}" stroke="#333" stroke-width="1.5"/>`;
    svg += `<text x="${x + cellW / 2}" y="${y + cellH / 2 + 5}" text-anchor="middle" font-size="14" font-weight="bold">${pos}</text>`;
  }

  // Draw funnel icon (blue triangle) if we have a current stage
  if (currentStage) {
    const funnelX = (currentStage.funnelBefore - trackRange.min) * cellW + padding + cellW / 2;
    const funnelY = padding + 10;
    svg += `<polygon points="${funnelX - 10},${funnelY} ${funnelX + 10},${funnelY} ${funnelX},${funnelY + 18}" fill="#3366cc" stroke="#1a3366" stroke-width="1.5"/>`;
    svg += `<text x="${funnelX}" y="${funnelY - 4}" text-anchor="middle" font-size="10" fill="#3366cc" font-weight="bold">▼</text>`;

    // Draw marble icon (brown/orange circle)
    const marbleX = (currentStage.marblePos - trackRange.min) * cellW + padding + cellW / 2;
    const marbleY = 50 + padding + cellH + 15;
    svg += `<circle cx="${marbleX}" cy="${marbleY}" r="10" fill="#cc6633" stroke="#663300" stroke-width="1.5"/>`;
  }

  svg += `</svg>`;
  return svg;
}

// --- Data table renderer ---

// Returns an HTML string for the book-keeping table
// rule: which rule (affects which rows to show)
// stages: array of computed stages to display
// tableIndex: 0, 1, or 2 (for the three sub-tables: 1-14, 15-27, 28-40)
export function renderDataTable(rule, stages, tableIndex) {
  const ranges = [
    { start: 1, end: 14 },
    { start: 15, end: 27 },
    { start: 28, end: 40 }
  ];
  const range = ranges[tableIndex];
  const cols = range.end - range.start + 1;

  let html = `<table class="fe-data-table">`;
  html += `<caption>Rule ${rule} — Stages ${range.start} to ${range.end}</caption>`;
  html += `<thead><tr><th scope="col">Stage number</th>`;
  for (let s = range.start; s <= range.end; s++) {
    html += `<th scope="col">${s}</th>`;
  }
  html += `</tr></thead><tbody>`;

  // Row: Funnel is at
  html += `<tr><th scope="row">▼ is at</th>`;
  for (let s = range.start; s <= range.end; s++) {
    const st = stages.find(x => x.stage === s);
    html += `<td>${st ? st.funnelBefore : ""}</td>`;
  }
  html += `</tr>`;

  // Row: Dice-score
  html += `<tr><th scope="row">Dice-score =</th>`;
  for (let s = range.start; s <= range.end; s++) {
    const st = stages.find(x => x.stage === s);
    html += `<td>${st ? st.diceScore : ""}</td>`;
  }
  html += `</tr>`;

  // Row: Direction
  html += `<tr><th scope="row">From ▼, ● goes</th>`;
  for (let s = range.start; s <= range.end; s++) {
    const st = stages.find(x => x.stage === s);
    html += `<td>${st ? st.direction : ""}</td>`;
  }
  html += `</tr>`;

  // Row: Outcome (marble position) — yellow bg, red text
  html += `<tr class="fe-row-outcome"><th scope="row">Outcome: ● is at</th>`;
  for (let s = range.start; s <= range.end; s++) {
    const st = stages.find(x => x.stage === s);
    html += `<td>${st ? st.marblePos : ""}</td>`;
  }
  html += `</tr>`;

  // Rows specific to Rule 2: relative to target, move funnel
  if (rule === 2) {
    html += `<tr><th scope="row">● relative to ◎ is ...</th>`;
    for (let s = range.start; s <= range.end; s++) {
      const st = stages.find(x => x.stage === s);
      if (st) {
        const rel = st.relativeToTarget;
        const label = rel === 0 ? "0" : (rel > 0 ? `${rel}R` : `${Math.abs(rel)}L`);
        html += `<td>${label}</td>`;
      } else {
        html += `<td></td>`;
      }
    }
    html += `</tr>`;

    html += `<tr><th scope="row">... move ▼</th>`;
    for (let s = range.start; s <= range.end; s++) {
      const st = stages.find(x => x.stage === s);
      if (st) {
        const rel = st.relativeToTarget;
        const label = rel === 0 ? "–" : (rel > 0 ? `${rel}L` : `${Math.abs(rel)}R`);
        html += `<td>${label}</td>`;
      } else {
        html += `<td></td>`;
      }
    }
    html += `</tr>`;
  }

  // Rows for Rule 3: relative to target, place funnel
  if (rule === 3) {
    html += `<tr><th scope="row">● relative to ◎ is ...</th>`;
    for (let s = range.start; s <= range.end; s++) {
      const st = stages.find(x => x.stage === s);
      if (st) {
        const rel = st.relativeToTarget;
        const label = rel === 0 ? "0" : (rel > 0 ? `${rel}R` : `${Math.abs(rel)}L`);
        html += `<td>${label}</td>`;
      } else {
        html += `<td></td>`;
      }
    }
    html += `</tr>`;

    html += `<tr><th scope="row">... place ▼ relative to ◎</th>`;
    for (let s = range.start; s <= range.end; s++) {
      const st = stages.find(x => x.stage === s);
      if (st) {
        const rel = st.relativeToTarget;
        const label = rel === 0 ? "0" : (rel > 0 ? `${Math.abs(rel)}L` : `${rel}R`);
        html += `<td>${label}</td>`;
      } else {
        html += `<td></td>`;
      }
    }
    html += `</tr>`;
  }

  // Row: Funnel is now at (for Rules 2, 3, 4)
  if (rule !== 1) {
    html += `<tr><th scope="row">So ▼ is now at</th>`;
    for (let s = range.start; s <= range.end; s++) {
      const st = stages.find(x => x.stage === s);
      html += `<td>${st ? st.funnelAfter : ""}</td>`;
    }
    html += `</tr>`;
  }

  html += `</tbody></table>`;
  return html;
}

// --- Chapter-level helpers ---
// These reduce duplication across OJS cells in chapters 11, 12, and 13.
// Each returns an HTML string; OJS cells wrap with html`${...}`.

// Status bar showing rule info, current stage, last outcome, and funnel position
export function renderStatusHTML(rule, description, counter, visible, totalStages, target) {
  const lastOutcome = counter > 0 ? visible[visible.length - 1].marblePos : null;
  const funnelPos = counter > 0 ? visible[visible.length - 1].funnelAfter : target;
  const funnelLabel = rule === 1 ? "Funnel always at" : (counter > 0 ? "Funnel now at" : "Funnel at");

  let s = `<div class="fe-status" role="status" aria-live="polite" aria-atomic="true">`;
  s += `<strong>Rule ${rule} — ${description}</strong><br>`;
  s += `Stage: <strong>${counter}</strong> of ${totalStages}`;
  if (lastOutcome !== null) {
    s += ` | Last outcome: <strong class="fe-outcome-value">${lastOutcome}</strong>`;
  }
  s += ` | ${funnelLabel}: <strong class="fe-funnel-value">${funnelPos}</strong>`;
  s += `</div>`;
  return s;
}

// Track SVG wrapped in its scroll container
export function renderTrackHTML(counter, visible, allStages) {
  const currentStage = counter > 0 ? visible[visible.length - 1] : null;
  const trackRange = computeTrackRange(allStages);
  return `<div class="fe-track-container">${renderTrackSVG(currentStage, trackRange)}</div>`;
}

// Next/Complete buttons — returns HTML with .fe-stage-next and .fe-stage-complete classes
// Callers attach onclick handlers via querySelector in OJS
export function renderStageButtonsHTML(counter, totalStages) {
  const d = counter >= totalStages ? " disabled" : "";
  return `<div><button class="fe-button fe-stage-next"${d}>Next Stage \u2192</button>`
       + `<button class="fe-button fe-button-complete fe-stage-complete"${d}>Complete Remaining Stages</button></div>`;
}

// Three sub-tables (stages 1-14, 15-27, 28-40) wrapped in scroll containers
export function renderDataTablesHTML(rule, visible) {
  return `<div class="fe-track-container">${renderDataTable(rule, visible, 0)}</div>`
       + `<div class="fe-track-container">${renderDataTable(rule, visible, 1)}</div>`
       + `<div class="fe-track-container">${renderDataTable(rule, visible, 2)}</div>`;
}
