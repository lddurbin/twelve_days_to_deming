#!/usr/bin/env python3
"""audit_sample.py — the seeded draw, the blind plants, and the arithmetic of a
Wave 3 sampling audit (#746, under epic #734).

Everything here is pure: no PDFs, no pandoc, no git. The command that drives it
is scripts/sample-audit.py, and the population it draws from comes from
scripts/lib/audit_population.py. Kept apart so the parts a published fidelity
claim rests on — which paragraphs were drawn, which were planted, and what
bound the verdicts support — can be tested in CI, where the source PDFs are not.

**Determinism.** A draw is a function of the seed, the record name and the
population's text, and nothing else. Every choice is made by ranking
candidates on a SHA-256 digest rather than by `random`: Python guarantees only
`random.random()`'s sequence across versions, not `sample()` or `choice()`, and
an audit has to be reproducible years later by whoever re-checks it. Ranking on
a digest of each candidate's own content also makes the draw independent of
the order the population arrives in.

**Why plants.** Lee audits (decided in #734, 2026-09-13), and Lee also verified
the original conversion that Wave 2 then found hundreds of defects in. So the
auditor's sensitivity is measured, not assumed: a few sampled paragraphs have a
change injected into the *displayed* site text — never the .qmd — of a kind
Wave 2 actually found, and the published bound is divided by the share caught.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass

import qmd_strip

# ── Seeded choice ──────────────────────────────────────────────────────────


def digest(*parts: object) -> int:
    """A stable integer for `parts`, the sort key every seeded choice uses."""
    joined = "\x1f".join(str(p) for p in parts)
    return int.from_bytes(hashlib.sha256(joined.encode("utf-8")).digest(), "big")


def unit(*parts: object) -> float:
    """`digest(parts)` as a number in [0, 1)."""
    return digest(*parts) / 2**256


def planted_count(seed: int, record: str, cards: int) -> int:
    """How many of `cards` sampled paragraphs carry a plant.

    Roughly 10–20% of the sample, so ~20 cards carry 2, 3 or 4 — varying per
    record because a fixed count tells the auditor when to stop looking, and
    low because a sample that is a quarter errors is a proofing exercise, which
    inflates the catch rate against real, rare defects (#734).
    """
    lo = max(1, round(cards * 0.10))
    hi = max(lo, round(cards * 0.20))
    return lo + math.floor(unit(seed, record, "planted-count") * (hi - lo + 1))


def rank(items, key, seed: int, record: str, purpose: str):
    """`items` in seeded order: sorted by the digest of each one's `key`."""
    return sorted(items, key=lambda item: digest(seed, record, purpose, *key(item)))


# ── Plants ─────────────────────────────────────────────────────────────────

# Drawn from the defect classes Wave 2's adjudication records hold, not
# invented: "may" for "will" (Day 12's "will require special help"), "a" for
# "the" (index I-23, "into *a* statement"), "merely" for "hardly" and
# "particularly" for "well beyond" (Day 4), a dropped or stray `!` (Day 1's
# encoded space glyph, Day 12's word-level diff), one wrong digit (Day 12's
# "28 years" read as "58"; "6 to 12 months" as 8), dropped words (Day 9's
# five), and emphasis, which no automated flag can see (Day 9's 29).
SUBSTITUTIONS = {
    "will": "may", "may": "will", "must": "should", "should": "must",
    "can": "could", "could": "can", "always": "often", "often": "always",
    "never": "rarely", "all": "most", "most": "all", "more": "most",
    "first": "final", "final": "first", "before": "after", "after": "before",
    "some": "many", "many": "some", "these": "those", "those": "these",
    "which": "that", "of": "for", "for": "of", "hardly": "merely",
    "particularly": "especially", "important": "essential", "increase": "decrease",
    "a": "the", "the": "a",
}
DROPPABLE = {
    "the", "a", "also", "only", "very", "still", "just", "even", "all", "not",
    "really", "quite", "then", "so", "both", "now", "often",
}
INSERT_AFTER = {
    "is", "are", "was", "were", "will", "would", "can", "could", "should",
    "may", "might", "must", "has", "have", "had",
}
INSERTABLE = ("also", "still", "often", "only", "really", "just")
# An insertion reads as a transcription slip only before a content word: "is
# also devoted" is a defect a careful reader skims past, "has still much" is a
# proofreading catch, and planting the second kind would flatter the catch rate.
_NOT_AFTER_INSERT = {
    "much", "more", "most", "very", "quite", "rather", "being", "been", "that",
    "this", "these", "those", "there", "their", "they", "then", "than", "with",
    "from", "into", "onto", "upon", "also", "still", "often", "only", "really",
    "just", "even", "never", "always", "what", "which", "when", "where", "about",
    "therefore", "however", "thus", "indeed", "perhaps", "already", "sometimes",
    "here", "once", "again", "able",
}
# Wave 2's emphasis findings were a word or a short phrase; unbolding a whole
# principle statement is a change nobody could miss.
MAX_EMPHASIS_WORDS = 4

KINDS = ("substitution", "dropped-word", "inserted-word", "number", "exclamation", "emphasis")

_WORD = re.compile(r"(?<![\w’'-])([A-Za-z]+)(?![\w’'-])")
_NUMBER = re.compile(r"(?<![\w.,/–-])(\d+)(?![\w/–-])")
_SENTENCE_STOP = re.compile(r"(?<=[a-z]{3})\.(?=\s+[A-Z“\"‘']|\s*$)")
_BANG = re.compile(r"!(?!\[)(?=[\s”\"’')]|$)")
# `\*` is a literal asterisk in Pandoc markdown, never a marker — Balaji
# Reddie's "the \*\*\* wire" is three of them.
_EMPHASIS = re.compile(
    r"(?<![*\w\\])\*\*(?!\s)([^*\n]+?)(?<![\s\\])\*\*(?![*\w])"
    r"|(?<![*\w\\])\*(?![*\s])([^*\n]+?)(?<![\s\\])\*(?![*\w])"
    r"|(?<![_\w\\])_(?![_\s])([^_\n]+?)(?<![\s\\])_(?![_\w])"
)
# Spans a change must not land in even when it would be visible: MathJax
# source, inline code, and a list marker's own number.
_UNPLANTABLE = re.compile(r"\$[^$\n]+\$|`[^`\n]+`|^\s*\d+[.)]\s")

# Stands in for a change while checking where it lands — a private-use
# character no source text contains and no stripping rule touches.
_PROBE = ""


@dataclass(frozen=True)
class Plant:
    kind: str
    line: int  # 1-based source line
    start: int  # character offsets in that raw source line
    end: int
    replacement: str

    def apply(self, raw: str) -> str:
        return raw[: self.start] + self.replacement + raw[self.end :]

    def describe(self, raw: str) -> dict:
        """The key entry: what was on the line, and what the card showed instead."""
        lo, hi = max(0, self.start - 30), min(len(raw), self.end + 30)
        return {
            "kind": self.kind,
            "line": self.line,
            "from": raw[self.start : self.end],
            "to": self.replacement,
            "context_before": raw[lo:hi],
            "context_after": self.apply(raw)[lo : hi - (self.end - self.start) + len(self.replacement)],
        }


def _cased(word: str, like: str, following: str = "") -> str:
    """`word` in the case of the word it replaces.

    A one-letter "A" says nothing about whether its line is set in capitals,
    so the next word decides: "A SYSTEM" becomes "THE SYSTEM", not "The SYSTEM".
    """
    nxt = re.match(r"\W*([A-Za-z]{2,})", following)
    if (like.isupper() and len(like) > 1) or (like.isupper() and nxt and nxt.group(1).isupper()):
        return word.upper()
    if like[:1].isupper():
        return word[:1].upper() + word[1:]
    return word


def candidates(number: int, raw: str) -> list[Plant]:
    """Every change of every kind that could be planted in one source line.

    Deliberately over-generous — a candidate inside a link target or an
    attribute block is still listed. validate() is what decides whether a
    change would be visible, and where, so that question has one answer.
    """
    blocked = [m.span() for m in _UNPLANTABLE.finditer(raw)]

    def free(start, end):
        return not any(s < max(end, start + 1) and start < e for s, e in blocked)

    out: list[Plant] = []
    for m in _WORD.finditer(raw):
        word, (start, end) = m.group(1), m.span(1)
        if not free(start, end):
            continue
        lower = word.lower()
        swap = SUBSTITUTIONS.get(lower)
        if swap:
            following = raw[end:].lstrip()
            # "the" becomes "a" only before a consonant; "a" before a vowel is
            # "an", which is not the defect being planted.
            if not (lower == "the" and not re.match(r"[b-df-hj-np-tv-z]", following, re.I)):
                out.append(Plant("substitution", number, start, end, _cased(swap, word, following)))
        if lower in DROPPABLE and raw[end : end + 1] == " " and start > 0:
            out.append(Plant("dropped-word", number, start, end + 1, ""))
        following_word = re.match(r" ([a-z]{4,})\b", raw[end:])
        if (
            lower in INSERT_AFTER
            and following_word
            and following_word.group(1) not in _NOT_AFTER_INSERT
            and not following_word.group(1).endswith("ly")
        ):
            for extra in INSERTABLE:
                out.append(Plant("inserted-word", number, end, end, " " + extra))
    for m in _NUMBER.finditer(raw):
        start, end = m.span(1)
        if free(start, end):
            digits = m.group(1)
            last = int(digits[-1])
            out.append(Plant("number", number, end - 1, end, str(last + 1 if last < 9 else 8)))
    for m in _SENTENCE_STOP.finditer(raw):
        if free(*m.span()):
            out.append(Plant("exclamation", number, m.start(), m.end(), "!"))
    for m in _BANG.finditer(raw):
        if free(*m.span()):
            out.append(Plant("exclamation", number, m.start(), m.end(), "."))
    for m in _EMPHASIS.finditer(raw):
        if free(*m.span()):
            inner = next(g for g in m.groups() if g is not None)
            if len(inner.split()) <= MAX_EMPHASIS_WORDS:
                out.append(Plant("emphasis", number, m.start(), m.end(), inner))
    return out


def strip_line(raw: str) -> str:
    """One prose line's stripped text, whitespace collapsed.

    Only valid for a line strip_qmd() kept in context: the stripper's state is
    front matter and code fences, and neither applies to a kept prose line.
    """
    return " ".join(qmd_strip.strip_qmd(raw + "\n").split())


def excerpt_text(lines: list[tuple[int, str]], line: int | None = None, raw: str | None = None) -> str:
    """The stripped text of an excerpt, optionally with one line replaced."""
    return " ".join(strip_line(raw if n == line else text) for n, text in lines)


def validate(plant: Plant, lines: list[tuple[int, str]], spans: list[tuple[int, int]]) -> bool:
    """Would `plant` show on the card, and only inside a sentence the paragraph matched?

    `lines` is the excerpt as (source line, raw text) in order and `spans` the
    matched sentences' offsets in its stripped text. The planted excerpt is
    re-stripped and diffed against the original, which answers three questions
    at once. A change that strips away was inside markup the reader never sees
    — a link target, an attribute block, an enriched link's descriptor. A diff
    wider than the change itself means it disturbed the markup around it. And
    a change outside every span would ask the auditor to catch something in
    text this paragraph does not cover.

    Emphasis is the exception, because removing it leaves the stripped text
    identical by design. Its position comes instead from a probe character put
    where the emphasised run was — which cannot be used for the other kinds,
    since a probe inside "page 19" stops qmd_strip.py recognising an enriched
    reference at all, and the most consequential plant would never validate.
    """
    raw = dict(lines)[plant.line]
    before = excerpt_text(lines)
    if plant.kind == "emphasis":
        after = excerpt_text(lines, plant.line, raw[: plant.start] + _PROBE + raw[plant.end :])
        if after.count(_PROBE) != 1 or excerpt_text(lines, plant.line, plant.apply(raw)) != before:
            return False
        at = after.index(_PROBE)
        lo, hi = at, len(before) - (len(after) - at - 1)
        if before[:lo] != after[:at] or before[hi:] != after[at + 1 :]:
            return False
    else:
        after = excerpt_text(lines, plant.line, plant.apply(raw))
        if after == before:
            return False
        shortest = min(len(before), len(after))
        lo = next((i for i in range(shortest) if before[i] != after[i]), shortest)
        tail = 0
        while tail < shortest - lo and before[-1 - tail] == after[-1 - tail]:
            tail += 1
        hi = len(before) - tail
        if hi - lo > plant.end - plant.start + 1 or (len(after) - tail) - lo > len(plant.replacement) + 1:
            return False
    return any(a <= lo and hi <= b and (hi > lo or a < lo < b) for a, b in spans)


def choose_plant(
    seed: int, record: str, card_key: str, lines: list[tuple[int, str]], spans: list[tuple[int, int]]
) -> Plant | None:
    """The one plant this card carries, or None if no kind fits it.

    Three seeded choices, coarse to fine. The kind comes first, among the kinds
    this passage can take, so a passage rich in function words does not always
    get a substitution. The change comes second — "will" → "may" as a whole,
    before any one occurrence of it — because otherwise "the" and "of", which
    outnumber every other candidate, would be nearly every word planted. The
    occurrence comes last.
    """
    by_kind: dict[str, dict[str, list[Plant]]] = {}
    for number, raw in lines:
        for plant in candidates(number, raw):
            change = f"{raw[plant.start:plant.end].lower()}\x1f{plant.replacement.lower()}"
            if plant.kind in ("number", "exclamation", "emphasis"):
                change = plant.kind
            by_kind.setdefault(plant.kind, {}).setdefault(change, []).append(plant)
    for kind in rank(by_kind, lambda k: (card_key, k), seed, record, "plant-kind"):
        for change in rank(by_kind[kind], lambda c: (card_key, c), seed, record, "plant-change"):
            ordered = rank(
                by_kind[kind][change],
                lambda p: (card_key, p.line, p.start, p.end, p.replacement),
                seed,
                record,
                "plant",
            )
            for plant in ordered:
                if validate(plant, lines, spans):
                    return plant
    return None


# ── Verdicts and the bound ─────────────────────────────────────────────────

# The review page is the Wave 2 adjudication template, whose three decision
# buttons are keyed accept / reject / discuss. An audit relabels them; this is
# the one place those keys are read back as audit verdicts.
#
# Day 5's audit found the middle bucket was the problem. Labelled "Trivial", it
# read as "small but real", and swallowed four genuine deviations and one
# planted defect that the auditor had described correctly in the notes beside
# them — scoring the record at zero sensitivity and a bound of 1.0. So the
# middle button carries severity instead. A difference the site's own
# conventions account for (a heading's case, an enriched cross-reference, curly
# quotes) is not a deviation at all and belongs under Exact, which frees three
# buttons to say: none, one that does not change meaning, one that does.
VERDICTS = {"accept": "exact", "discuss": "minor", "reject": "substantive"}

# The two verdicts that say the site departs from Neave. Both are real, and both
# go through the Wave 2 fix path. They are counted apart because one bounds the
# rate of *wrong words* and the other the rate of *wrong anything*, and those
# support very different published claims: lumping them, as the binary rubric
# did, degrades the headline to the weaker of the two while hiding whether any
# substantive error escaped at all.
DEVIATIONS = ("minor", "substantive")

# Which severity each plant kind stands in for, so sensitivity is measured
# against the kind of defect it approximates. An auditor who reliably catches a
# swapped word but never a lost italic has two very different detection rates,
# and one pooled p̂ would hide that — Day 5 caught its `!` and missed both its
# word-level plants, which a single figure reports as "1 of 3".
SEVERITY = {
    "substitution": "substantive",
    "dropped-word": "substantive",
    "inserted-word": "substantive",
    "number": "substantive",
    "exclamation": "minor",
    "emphasis": "minor",
}


def upper_bound(defects: int, n: int, confidence: float = 0.95) -> float:
    """One-sided exact (Clopper–Pearson) upper bound on a rate, from `defects` in `n`.

    With no defects this is 1 − α^(1/n), which the rule of three approximates
    as 3/n: 13.9% for n = 20, against the rule's 15%.
    """
    if n <= 0:
        return 1.0
    if defects >= n:
        return 1.0
    alpha = 1 - confidence

    def cdf(p):
        return sum(math.comb(n, k) * p**k * (1 - p) ** (n - k) for k in range(defects + 1))

    lo, hi = defects / n, 1.0
    for _ in range(100):
        mid = (lo + hi) / 2
        if cdf(mid) > alpha:
            lo = mid
        else:
            hi = mid
    return hi


def adjusted_bound(defects: int, n: int, planted: int, caught: int, confidence: float = 0.95) -> dict:
    """The escape-rate bound, divided by the auditor's measured sensitivity.

    A defect the auditor would miss is not in the count, so the raw bound
    assumes perfect detection. Dividing by caught/planted is the protocol #734
    adopts — ≈ 3/(n·p̂) with no defects found — and it is a point correction:
    it does not carry the uncertainty in p̂ itself, which on one record's two
    to four plants is large. That is why the headline claim pools records.
    """
    raw = upper_bound(defects, n, confidence)
    sensitivity = caught / planted if planted else None
    adjusted = 1.0 if not sensitivity else min(1.0, raw / sensitivity)
    return {
        "confidence": confidence,
        "audited": n,
        "real_defects": defects,
        "upper": round(raw, 4),
        "sensitivity": None if sensitivity is None else round(sensitivity, 4),
        "adjusted_upper": round(adjusted, 4),
    }


def severity_bounds(real: dict, audited: int, plants: list, confidence: float = 0.95) -> dict:
    """Two bounds over one sample: substantive-only, and any deviation at all.

    `real` counts unplanted cards by verdict, and `plants` holds one
    `{"severity", "caught"}` dict per planted card, as sample-audit.py's
    score() builds them. Both bounds run over the same n — every unplanted card was read against the source, whatever it
    turned out to say — and differ only in what counts as a defect and which
    plants measure the detection of it.

    Reported apart because they answer different questions. "At most this share
    of clean text has a wrong word" is the claim the epic set out to make; "at
    most this share differs from Neave in any way, punctuation and emphasis
    included" is true, weaker, and the only claim a binary rubric can support.
    Publishing one without the other either overstates fidelity or buries it.

    On one record a severity often has no plants at all — two to four plants
    cannot cover both — so its sensitivity is None and its adjusted bound 1.0.
    That is honest rather than useful, and is why the headline pools records.
    """
    counts = {
        "substantive": (real.get("substantive", 0),
                        [p for p in plants if p["severity"] == "substantive"]),
        "any_deviation": (sum(real.get(v, 0) for v in DEVIATIONS), list(plants)),
    }
    out = {"confidence": confidence, "audited": audited}
    for scope, (defects, group) in counts.items():
        bound = adjusted_bound(defects, audited, len(group),
                               sum(1 for p in group if p["caught"]), confidence)
        out[scope] = {
            "real_defects": defects,
            "planted": len(group),
            "caught": sum(1 for p in group if p["caught"]),
            "upper": bound["upper"],
            "sensitivity": bound["sensitivity"],
            "adjusted_upper": bound["adjusted_upper"],
        }
    return out


# ── The committed record ───────────────────────────────────────────────────


def to_yaml(value, indent: int = 0) -> str:
    """A small, strict YAML emitter for audit records.

    Stdlib has no YAML writer, and the record's shape is fixed, so this emits
    block mappings and sequences with every string as a JSON literal — a JSON
    string is a valid YAML double-quoted scalar, which sidesteps every quoting
    rule plain scalars have (a note beginning "No:" or "- ", a bare "yes").
    """
    pad = "  " * indent
    if isinstance(value, dict):
        if not value:
            return " {}\n"
        out = "\n" if indent else ""
        for key, item in value.items():
            out += f"{pad}{key}:" + (_scalar_line(item) if _is_scalar(item) else to_yaml(item, indent + 1))
        return out
    if isinstance(value, list):
        if not value:
            return " []\n"
        out = "\n"
        for item in value:
            if _is_scalar(item):
                out += f"{pad}-{_scalar_line(item)}"
            else:
                body = to_yaml(item, indent + 1)
                out += f"{pad}- " + body.lstrip("\n").lstrip(" ")
        return out
    return _scalar_line(value)


def _is_scalar(value) -> bool:
    return not isinstance(value, (dict, list)) or not value


def _scalar_line(value) -> str:
    if isinstance(value, (dict, list)):
        return " {}\n" if isinstance(value, dict) else " []\n"
    if value is None:
        return " null\n"
    if isinstance(value, bool):
        return f" {'true' if value else 'false'}\n"
    if isinstance(value, (int, float)):
        return f" {value}\n"
    return f" {json.dumps(str(value), ensure_ascii=False)}\n"
