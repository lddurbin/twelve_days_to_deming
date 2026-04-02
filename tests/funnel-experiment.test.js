import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  TARGET,
  TRACK_MIN,
  TRACK_MAX,
  TOTAL_STAGES,
  AUTHOR_FIRST_5,
  diceToDisplacement,
  displacementToDirection,
  computeMarble,
  nextFunnel,
  runAllStages,
  generateDiceSequence,
  computeTrackRange,
  loadDiceSequence,
  saveDiceSequence,
  clearDiceSequence,
  escapeHTML,
  renderDataTable,
} from "../assets/scripts/funnel-experiment.js";

// ---------------------------------------------------------------------------
// diceToDisplacement
// ---------------------------------------------------------------------------
describe("diceToDisplacement", () => {
  it("maps dice-score 7 to 0 (directly under funnel)", () => {
    expect(diceToDisplacement(7)).toBe(0);
  });

  it("maps the lowest dice-score (2) to -5 (far left)", () => {
    expect(diceToDisplacement(2)).toBe(-5);
  });

  it("maps the highest dice-score (12) to +5 (far right)", () => {
    expect(diceToDisplacement(12)).toBe(5);
  });

  it("maps all valid dice-scores (2–12) to the correct displacement", () => {
    const expected = {
      2: -5, 3: -4, 4: -3, 5: -2, 6: -1,
      7: 0,
      8: 1, 9: 2, 10: 3, 11: 4, 12: 5,
    };
    for (const [score, displacement] of Object.entries(expected)) {
      expect(diceToDisplacement(Number(score))).toBe(displacement);
    }
  });

  it("returns undefined for an out-of-range dice-score", () => {
    expect(diceToDisplacement(1)).toBeUndefined();
    expect(diceToDisplacement(13)).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// displacementToDirection
// ---------------------------------------------------------------------------
describe("displacementToDirection", () => {
  it('formats negative displacement as left (e.g. -3 → "3L")', () => {
    expect(displacementToDirection(-3)).toBe("3L");
  });

  it('formats positive displacement as right (e.g. 4 → "4R")', () => {
    expect(displacementToDirection(4)).toBe("4R");
  });

  it('formats zero displacement as "↓" (straight down)', () => {
    expect(displacementToDirection(0)).toBe("↓");
  });
});

// ---------------------------------------------------------------------------
// computeMarble
// ---------------------------------------------------------------------------
describe("computeMarble", () => {
  it("adds displacement to funnel position", () => {
    expect(computeMarble(30, -3)).toBe(27);
  });

  it("handles zero displacement (marble lands at funnel)", () => {
    expect(computeMarble(30, 0)).toBe(30);
  });

  it("works with off-target funnel positions", () => {
    expect(computeMarble(25, 5)).toBe(30);
  });

  it("can produce positions outside the normal track range", () => {
    expect(computeMarble(22, -5)).toBe(17);
    expect(computeMarble(38, 5)).toBe(43);
  });
});

// ---------------------------------------------------------------------------
// nextFunnel
// ---------------------------------------------------------------------------
describe("nextFunnel", () => {
  describe("Rule 1 — never move the funnel", () => {
    it("always returns the target regardless of marble position", () => {
      expect(nextFunnel(1, 30, 33)).toBe(TARGET);
      expect(nextFunnel(1, 30, 25)).toBe(TARGET);
      expect(nextFunnel(1, 30, 30)).toBe(TARGET);
    });
  });

  describe("Rule 2 — compensate (opposite direction)", () => {
    it("moves funnel left when marble lands right of target", () => {
      // marble at 33 → 3 right of 30 → move funnel 3 left
      expect(nextFunnel(2, 30, 33)).toBe(27);
    });

    it("moves funnel right when marble lands left of target", () => {
      // marble at 27 → 3 left of 30 → move funnel 3 right
      expect(nextFunnel(2, 30, 27)).toBe(33);
    });

    it("does not move funnel when marble hits target exactly", () => {
      expect(nextFunnel(2, 30, 30)).toBe(30);
    });

    it("adjusts relative to current funnel position, not just target", () => {
      // funnel at 28, marble at 32 → 2 right of target → move 2 left from 28
      expect(nextFunnel(2, 28, 32)).toBe(26);
    });
  });

  describe("Rule 3 — place funnel on opposite side of target", () => {
    it("mirrors marble position about the target", () => {
      // marble at 33 → funnel goes to 2*30 - 33 = 27
      expect(nextFunnel(3, 30, 33)).toBe(27);
    });

    it("mirrors left-of-target to right-of-target", () => {
      expect(nextFunnel(3, 30, 25)).toBe(35);
    });

    it("stays at target when marble hits target", () => {
      expect(nextFunnel(3, 30, 30)).toBe(30);
    });

    it("ignores current funnel position (only uses marble and target)", () => {
      // Same marble position, different funnel → same result
      expect(nextFunnel(3, 22, 33)).toBe(27);
      expect(nextFunnel(3, 38, 33)).toBe(27);
    });
  });

  describe("Rule 4 — place funnel where marble landed", () => {
    it("sets funnel to marble position", () => {
      expect(nextFunnel(4, 30, 33)).toBe(33);
    });

    it("works for any marble position", () => {
      expect(nextFunnel(4, 30, 17)).toBe(17);
      expect(nextFunnel(4, 25, 42)).toBe(42);
    });
  });

  it("throws for an unknown rule", () => {
    expect(() => nextFunnel(5, 30, 30)).toThrow("Unknown rule: 5");
  });
});

// ---------------------------------------------------------------------------
// runAllStages
// ---------------------------------------------------------------------------
describe("runAllStages", () => {
  // Fixed dice sequence for deterministic testing (5 entries)
  const shortDice = [
    { diceScore: 10, displacement: 3, direction: "3R" },
    { diceScore: 8, displacement: 1, direction: "1R" },
    { diceScore: 6, displacement: -1, direction: "1L" },
    { diceScore: 7, displacement: 0, direction: "↓" },
    { diceScore: 4, displacement: -3, direction: "3L" },
  ];

  it("returns one stage object per dice entry", () => {
    const stages = runAllStages(1, shortDice);
    expect(stages).toHaveLength(shortDice.length);
  });

  it("starts the funnel at TARGET", () => {
    const stages = runAllStages(1, shortDice);
    expect(stages[0].funnelBefore).toBe(TARGET);
  });

  it("numbers stages starting from 1", () => {
    const stages = runAllStages(1, shortDice);
    expect(stages[0].stage).toBe(1);
    expect(stages[4].stage).toBe(5);
  });

  describe("Rule 1 — funnel never moves", () => {
    it("keeps funnelBefore at TARGET for every stage", () => {
      const stages = runAllStages(1, shortDice);
      for (const s of stages) {
        expect(s.funnelBefore).toBe(TARGET);
        expect(s.funnelAfter).toBe(TARGET);
      }
    });

    it("computes marble positions as TARGET + displacement", () => {
      const stages = runAllStages(1, shortDice);
      expect(stages[0].marblePos).toBe(33); // 30 + 3
      expect(stages[1].marblePos).toBe(31); // 30 + 1
      expect(stages[2].marblePos).toBe(29); // 30 - 1
      expect(stages[3].marblePos).toBe(30); // 30 + 0
      expect(stages[4].marblePos).toBe(27); // 30 - 3
    });
  });

  describe("Rule 2 — compensating adjustment", () => {
    it("adjusts funnel position across stages", () => {
      const stages = runAllStages(2, shortDice);

      // Stage 1: funnel at 30, marble at 33, → funnel moves to 30 - (33-30) = 27
      expect(stages[0].funnelBefore).toBe(30);
      expect(stages[0].marblePos).toBe(33);
      expect(stages[0].funnelAfter).toBe(27);

      // Stage 2: funnel at 27, marble at 27+1=28, → funnel = 27 - (28-30) = 29
      expect(stages[1].funnelBefore).toBe(27);
      expect(stages[1].marblePos).toBe(28);
      expect(stages[1].funnelAfter).toBe(29);
    });
  });

  describe("Rule 4 — funnel follows marble", () => {
    it("sets funnel to previous marble position", () => {
      const stages = runAllStages(4, shortDice);

      // Stage 1: funnel at 30, marble at 33, funnel moves to 33
      expect(stages[0].funnelAfter).toBe(33);

      // Stage 2: funnel at 33, marble at 33+1=34, funnel moves to 34
      expect(stages[1].funnelBefore).toBe(33);
      expect(stages[1].marblePos).toBe(34);
      expect(stages[1].funnelAfter).toBe(34);
    });
  });

  it("computes relativeToTarget for each stage", () => {
    const stages = runAllStages(1, shortDice);
    expect(stages[0].relativeToTarget).toBe(3);  // 33 - 30
    expect(stages[2].relativeToTarget).toBe(-1); // 29 - 30
    expect(stages[3].relativeToTarget).toBe(0);  // 30 - 30
  });
});

// ---------------------------------------------------------------------------
// generateDiceSequence
// ---------------------------------------------------------------------------
describe("generateDiceSequence", () => {
  it("returns exactly TOTAL_STAGES entries", () => {
    const seq = generateDiceSequence(false);
    expect(seq).toHaveLength(TOTAL_STAGES);
  });

  it("produces dice scores in the valid range (2–12)", () => {
    const seq = generateDiceSequence(false);
    for (const entry of seq) {
      expect(entry.diceScore).toBeGreaterThanOrEqual(2);
      expect(entry.diceScore).toBeLessThanOrEqual(12);
    }
  });

  it("each entry has die1 and die2 summing to diceScore", () => {
    const seq = generateDiceSequence(false);
    for (const entry of seq) {
      expect(entry.die1 + entry.die2).toBe(entry.diceScore);
    }
  });

  it("uses author's first 5 dice scores when authorFirst5 is true", () => {
    const seq = generateDiceSequence(true);
    for (let i = 0; i < AUTHOR_FIRST_5.length; i++) {
      expect(seq[i].diceScore).toBe(AUTHOR_FIRST_5[i]);
    }
  });
});

// ---------------------------------------------------------------------------
// computeTrackRange
// ---------------------------------------------------------------------------
describe("computeTrackRange", () => {
  it("returns default TRACK_MIN/TRACK_MAX for empty stages", () => {
    const range = computeTrackRange([]);
    expect(range.min).toBe(TRACK_MIN);
    expect(range.max).toBe(TRACK_MAX);
  });

  it("adds 2-cell padding even when all positions are within default range", () => {
    const stages = [
      { marblePos: 28, funnelBefore: 30, funnelAfter: 30 },
      { marblePos: 32, funnelBefore: 30, funnelAfter: 30 },
    ];
    const range = computeTrackRange(stages);
    // Padding: min(20-2, 20) = 18, max(40+2, 40) = 42
    expect(range.min).toBe(18);
    expect(range.max).toBe(42);
  });

  it("extends the range with padding when positions fall outside", () => {
    const stages = [
      { marblePos: 15, funnelBefore: 30, funnelAfter: 18 },
    ];
    const range = computeTrackRange(stages);
    // min: min(15, 30, 18) = 15, then min(15-2, 20) = 13
    // max: max(30, 30, 18) = 30, but default hi is 40, then max(40+2, 40) = 42
    expect(range.min).toBe(13);
    expect(range.max).toBe(42);
  });

  it("extends both ends when positions exceed both limits", () => {
    const stages = [
      { marblePos: 10, funnelBefore: 50, funnelAfter: 45 },
    ];
    const range = computeTrackRange(stages);
    expect(range.min).toBe(8);  // 10 - 2
    expect(range.max).toBe(52); // 50 + 2
  });
});

// ---------------------------------------------------------------------------
// escapeHTML
// ---------------------------------------------------------------------------
describe("escapeHTML", () => {
  it("escapes angle brackets", () => {
    expect(escapeHTML("<script>")).toBe("&lt;script&gt;");
  });

  it("escapes ampersands and quotes", () => {
    expect(escapeHTML('a&b"c')).toBe("a&amp;b&quot;c");
  });

  it("passes through safe strings unchanged", () => {
    expect(escapeHTML("3R")).toBe("3R");
    expect(escapeHTML("↓")).toBe("↓");
  });

  it("converts numbers to strings", () => {
    expect(escapeHTML(42)).toBe("42");
  });
});

// ---------------------------------------------------------------------------
// loadDiceSequence — field validation
// ---------------------------------------------------------------------------
describe("loadDiceSequence", () => {
  // Minimal localStorage mock
  let store;
  beforeEach(() => {
    store = {};
    globalThis.localStorage = {
      getItem: (k) => store[k] ?? null,
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: (k) => { delete store[k]; },
    };
  });

  function validEntry() {
    return { die1: 3, die2: 4, diceScore: 7, displacement: 0, direction: "↓" };
  }

  it("returns a valid sequence from localStorage", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toEqual(seq);
  });

  it("rejects data where direction contains HTML (XSS payload)", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    seq[0].direction = '<img src=x onerror="alert(1)">';
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toBeNull();
  });

  it("rejects data where direction contains script tags", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    seq[5].direction = "<script>alert(1)</script>";
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toBeNull();
  });

  it("rejects data where a numeric field is a string", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    seq[0].die1 = "3";
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toBeNull();
  });

  it("rejects data with wrong array length", () => {
    const seq = Array.from({ length: 10 }, validEntry);
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toBeNull();
  });

  it("rejects data where direction doesn't match expected pattern", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    seq[0].direction = "bad";
    saveDiceSequence(seq);
    expect(loadDiceSequence()).toBeNull();
  });

  it("accepts valid direction patterns: digits+L, digits+R, ↓", () => {
    const seq = Array.from({ length: TOTAL_STAGES }, validEntry);
    seq[0].direction = "3L";
    seq[1].direction = "5R";
    seq[2].direction = "↓";
    saveDiceSequence(seq);
    expect(loadDiceSequence()).not.toBeNull();
  });

  it("returns null when localStorage is empty", () => {
    expect(loadDiceSequence()).toBeNull();
  });

  it("returns null when localStorage contains invalid JSON", () => {
    store["funnel_dice_sequence"] = "not valid json {{{";
    expect(loadDiceSequence()).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// renderDataTable — HTML escaping of direction field
// ---------------------------------------------------------------------------
describe("renderDataTable", () => {
  it("HTML-escapes the direction field in output", () => {
    const stages = [{
      stage: 1,
      funnelBefore: 30,
      diceScore: 10,
      displacement: 3,
      direction: '<img src=x onerror="alert(1)">',
      marblePos: 33,
      relativeToTarget: 3,
      funnelAfter: 30,
    }];
    const html = renderDataTable(1, stages, 0);
    expect(html).not.toContain("<img");
    expect(html).toContain("&lt;img");
  });
});
