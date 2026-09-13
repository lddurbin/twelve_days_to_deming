#!/usr/bin/env python3
"""Draw, and later reveal, a Wave 3 sampling audit of one validation record.

Wave 2 of epic #734 adjudicates every flag the comparator raises. What it
cannot say anything about is the text the comparator matched *cleanly* —
around 2,200 paragraphs corpus-wide that no human has checked since the
original conversion. This samples that population so the fidelity claim about
it is measured rather than assumed (#746).

Two steps, run a few days apart:

  draw     picks a seeded sample of matched-cleanly paragraphs, plants a few
           blind changes in what the page displays, and builds the review page
           from the Wave 2 adjudication template. The key stays in a gitignored
           file beside the page, off the page itself.

  reveal   reads the verdicts the page exported, scores them against the key,
           and writes the committed record workflow/validation/audits/<record>.yml.
           A DEFECT on a paragraph that carried no plant is a real finding, and
           goes through the Wave 2 fix path.

Usage:
    python3 scripts/sample-audit.py draw day-05
    python3 scripts/sample-audit.py reveal day-05 --verdicts ~/Downloads/audit-day-05-verdicts.json

See workflow/validation/audits/README.md for the protocol and the statistics.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import html
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

import audit_population as ap  # noqa: E402
import audit_sample as sample  # noqa: E402

VALIDATION = REPO_ROOT / "workflow" / "validation"
WORK_DIR = VALIDATION / "audit"  # gitignored: page, sample, key
AUDITS = VALIDATION / "audits"  # committed: one record per audit
ADJUDICATIONS = VALIDATION / "adjudications"
BUILDER = REPO_ROOT / "scripts" / "build-adjudication-page.py"

DEFAULT_CARDS = 20

LABELS = {
    "appendix-main": "the Appendix",
    "appendix-optional-extras": "Optional Extras",
    "appendix-contributions-balaji-reddie": "the Balaji Reddie contributions",
    "appendix-references": "References and Sources",
    "welcome": "the Welcome booklet",
    "index": "PLEASE START HERE",
}


def fail(msg: str):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def label(record: str) -> str:
    day = re.fullmatch(r"day-(\d{2})", record)
    return f"Day {int(day.group(1))}" if day else LABELS.get(record, record)


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()


# ── Rendering the site text ────────────────────────────────────────────────


def pandoc_command() -> list[str]:
    """Pandoc as the site's build runs it: standalone, or the copy Quarto ships."""
    if shutil.which("pandoc"):
        return ["pandoc"]
    if shutil.which("quarto"):
        return ["quarto", "pandoc"]
    fail("pandoc not found (install Quarto, or pandoc on its own)")


_SPLIT = "<!-- sample-audit card break -->"


def render(markdowns: list[str]) -> list[str]:
    """Each card's site markdown as the reader sees it, in one pandoc run.

    Rendered by pandoc rather than approximated, because the auditor is
    comparing emphasis and punctuation, and pandoc is what turns `--` into an
    en dash and straight quotes into curly ones on the live site. Links lose
    their targets (they point into the book, not into this page) and footnote
    callouts keep their marker as a superscript.
    """
    prepared = []
    for md in markdowns:
        md = re.sub(r"\[\^([^\]]+)\]", r"^\1^", md)
        md = re.sub(r"\{\{<.*?>\}\}", "", md)
        prepared.append(md)
    source = f"\n\n{_SPLIT}\n\n".join(prepared)
    done = subprocess.run(
        [*pandoc_command(), "-f", "markdown", "-t", "html", "--wrap=none"],
        input=source, capture_output=True, text=True, encoding="utf-8",
    )
    if done.returncode != 0:
        fail(f"pandoc failed: {done.stderr.strip()}")
    parts = done.stdout.split(_SPLIT)
    if len(parts) != len(markdowns):
        fail("pandoc output did not split back into one part per card")
    cleaned = []
    for part in parts:
        part = re.sub(r"<a\b[^>]*>", '<span class="link">', part).replace("</a>", "</span>")
        part = re.sub(r"<img\b[^>]*>", "[image]", part)
        part = re.sub(r'\s(id|data-[a-z-]+)="[^"]*"', "", part)
        cleaned.append(balance(part.strip()))
    return cleaned


_VOID = {"br", "hr", "img", "input", "wbr", "col", "area", "base", "link", "meta", "source", "track"}


def balance(fragment: str) -> str:
    """`fragment` with every element it opens closed, and stray closers dropped.

    An excerpt is a slice of a .qmd file, so it can open raw HTML whose closing
    tag sits on a line outside the slice. The page writes every card into one
    innerHTML assignment, where an unclosed <div> in one card would swallow
    every card after it.
    """
    from html.parser import HTMLParser

    out, stack = [], []

    class Balancer(HTMLParser):
        def handle_starttag(self, tag, attrs):
            out.append(self.get_starttag_text())
            if tag not in _VOID:
                stack.append(tag)

        def handle_startendtag(self, tag, attrs):
            out.append(self.get_starttag_text())

        def handle_endtag(self, tag):
            if tag in stack:
                while stack:
                    open_tag = stack.pop()
                    out.append(f"</{open_tag}>")
                    if open_tag == tag:
                        break

        def handle_data(self, data):
            out.append(html.escape(data, quote=False))

        def handle_entityref(self, name):
            out.append(f"&{name};")

        def handle_charref(self, name):
            out.append(f"&#{name};")

        def handle_comment(self, data):
            pass

    parser = Balancer(convert_charrefs=False)
    parser.feed(fragment)
    parser.close()
    out.extend(f"</{tag}>" for tag in reversed(stack))
    return "".join(out)


# ── draw ───────────────────────────────────────────────────────────────────


def locator(text: str) -> str:
    """Enough of the extracted paragraph to find it on the page image.

    Not the whole paragraph: extracted text has no emphasis, and a full copy
    on the card invites checking the site against it instead of against the
    page — which is how emphasis defects went unseen for a whole conversion.
    """
    words = text.split()
    if len(words) <= 6:
        return f"The heading or line <q>{html.escape(text)}</q>"
    head, tail = min(9, len(words) // 2), min(6, len(words) // 3)
    return (
        f"The paragraph beginning <q>{html.escape(' '.join(words[:head]))}…</q> "
        f"and ending <q>…{html.escape(' '.join(words[-tail:]))}</q>"
    )


def page_label(pdf_page: int, offset: int | None) -> str:
    printed = pdf_page - offset if offset is not None else 0
    return f"PDF p{pdf_page}" + (f" · printed p{printed}" if printed > 0 else "")


def adjudication(record: str) -> dict | None:
    path = ADJUDICATIONS / f"{record}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def content_dir(record: ap.Record) -> Path:
    """The directory card locations are given relative to."""
    parents = {f.parent for f in record.qmd_files}
    return parents.pop() if len(parents) == 1 else REPO_ROOT


def draw(args):
    try:
        record = ap.resolve(args.record)
    except ap.PopulationError as error:
        fail(str(error))
    name = record.name
    if (AUDITS / f"{name}.yml").exists():
        fail(f"{name} has already been audited: {AUDITS / f'{name}.yml'}. "
             "An audit is drawn once; re-drawing with another seed after seeing a sample is how a sample gets chosen.")

    adj = adjudication(name)
    if not (adj and adj.get("decided_at")) and not args.allow_unadjudicated:
        fail(f"{name} has no decided Wave 2 adjudication in {ADJUDICATIONS}. The audit measures what "
             "a finished pass missed; pass --allow-unadjudicated to draw anyway.")
    # The seed is fixed before anyone has seen a sample: the record's Wave 2
    # pass issue. See workflow/validation/audits/README.md.
    if args.seed is None:
        args.seed = (adj or {}).get("issue")
        if not isinstance(args.seed, int):
            fail(f"{name}'s adjudication record names no pass issue to seed from; pass --seed")

    try:
        dirty = git("status", "--porcelain", "--", *[str(f) for f in record.qmd_files], str(record.results))
        if dirty and not args.allow_dirty:
            fail(f"uncommitted changes to {name}'s content or results — the audit samples a commit:\n{dirty}")
        population = ap.derive(record)
    except ap.PopulationError as error:
        fail(str(error))

    paragraphs = population.paragraphs
    cards = min(args.size, len(paragraphs))
    planted = sample.planted_count(args.seed, name, cards)
    if cards - planted < 1:
        fail(f"{name} has only {len(paragraphs)} matched-cleanly paragraphs — too few to audit")

    order = {id(p): i for i, p in enumerate(paragraphs)}
    drawn = sample.rank(paragraphs, lambda p: (p.occurrence, p.text), args.seed, name, "draw")[:cards]
    drawn.sort(key=lambda p: order[id(p)])

    blocks = {f: ap.site_blocks(f) for f in record.qmd_files}
    raw = {f: f.read_text(encoding="utf-8").split("\n") for f in record.qmd_files}
    cards_data = []
    for number, para in enumerate(drawn, 1):
        try:
            excerpt = ap.locate(para, population, blocks)
        except ap.PopulationError as error:
            fail(str(error))
        lines = [(n, raw[excerpt.file][n - 1]) for _, n in excerpt.lines]
        if sample.excerpt_text(lines) != excerpt.text:
            fail(f"PDF p{para.page}: re-stripping the excerpt's lines does not reproduce its text")
        cards_data.append({"id": f"A-{number:02d}", "para": para, "excerpt": excerpt, "lines": lines})

    hosts = {}
    for card in sample.rank(cards_data, lambda c: (c["para"].occurrence, c["para"].text), args.seed, name, "host"):
        if len(hosts) == planted:
            break
        plant = sample.choose_plant(args.seed, name, card["id"], card["lines"], card["excerpt"].spans)
        if plant:
            hosts[card["id"]] = plant
    if len(hosts) < planted:
        fail(f"only {len(hosts)} of the sampled paragraphs can carry a plant; need {planted}")

    markdowns = []
    for card in cards_data:
        plant = hosts.get(card["id"])
        shown, previous = [], None
        for (block, n), (_, text) in zip(card["excerpt"].lines, card["lines"]):
            if previous is not None and block != previous:
                shown.append("")
            shown.append(plant.apply(text) if plant and plant.line == n else text)
            previous = block
        markdowns.append("\n".join(shown))
    rendered = render(markdowns)

    base = content_dir(record)
    offset = adj.get("page_offset") if adj else None
    commit = git("rev-parse", "HEAD")
    scorer = population.results["scorer_version"]
    fingerprint = hashlib.sha256(
        "\x1f".join([name, str(args.seed), str(cards), commit, scorer, *[c["para"].text for c in cards_data]]).encode()
    ).hexdigest()[:10]
    today = datetime.date.today().isoformat()

    items = []
    for card, site_html in zip(cards_data, rendered):
        excerpt, para = card["excerpt"], card["para"]
        first, last = excerpt.lines[0][1], excerpt.lines[-1][1]
        notes = [f"Site text from source line{'s' if last > first else ''} {first}{f'–{last}' if last > first else ''}."]
        for sentence, where, line in excerpt.elsewhere:
            place = (
                f"at <code>{html.escape(str(where.relative_to(REPO_ROOT)))}:{line}</code>"
                if where else "somewhere this tool could not pin to a line"
            )
            notes.append(
                f"One sentence of this paragraph matched elsewhere on the site, {place}, not in the "
                f"text shown: <q>{html.escape(sentence)}</q> — check it is where the source puts it."
            )
        items.append({
            "id": card["id"],
            "chip": "Unflagged",
            "chip_class": "",
            "file": str(excerpt.file.relative_to(base)),
            "line": first,
            "page": page_label(para.page, offset),
            "pdf_page": para.page,
            "page_pos": order[id(para)],
            "lines": f"{first}–{last}" if last > first else str(first),
            "flag": "Matched cleanly — never flagged by the comparator",
            "source_html": locator(para.text),
            "site_html": site_html,
            "evidence_html": " ".join(notes),
        })

    page = {
        "pass": f"audit-{name}-{fingerprint}",
        "epic": 734,
        "issue": 746,
        "source_pdf": record.pdf.name,
        "scorer_version": scorer,
        "content_dir": str(base.relative_to(REPO_ROOT)) if base != REPO_ROOT else ".",
        "export_filename": f"audit-{name}-verdicts.json",
        "page_offset": offset,
        "audit": {
            "record": name,
            "seed": args.seed,
            "cards": cards,
            "population": len(paragraphs),
            "commit": commit,
            "drawn_at": today,
        },
        "page": {
            "eyebrow": "Epic #734 · Wave 3 · Sampling audit",
            "title": f"{label(name)}, sampled against Neave's manual",
            "artifact_title": f"{label(name)} Audit",
            "standfirst_html": (
                f"{cards} paragraphs drawn at random from the {len(paragraphs)} the comparator matched "
                f"cleanly in <strong>{html.escape(record.pdf.name)}</strong> — text no pass has ever flagged, "
                "so nobody has read it against the source since it was transcribed. For each card, "
                "<strong>open the page image first</strong> and read the source clause by clause, then the "
                "site text. Some cards carry a change planted in what they display; which ones, and how "
                "many, stay hidden until your verdicts are exported. Judge the card, not the live site."
            ),
            "provenance": [
                {"label": "Source", "value": record.pdf.name},
                {"label": "Population", "value": f"{len(paragraphs)} matched cleanly"},
                {"label": "Sample", "value": f"{cards} · seed {args.seed}"},
                {"label": "Scorer", "value": scorer[:7]},
                {"label": "Commit", "value": commit[:7]},
                {"label": "Drawn", "value": today},
            ],
        },
        "ui": {
            "noun": "paragraphs",
            "filters": {"accept": "Exact", "reject": "Defect", "discuss": "Trivial"},
            "keys": {"accept": "exact", "reject": "defect", "discuss": "trivial"},
            "reject_tone": "critical",
            "note_placeholder": "What differs from the source? Quote both sides.",
            "outro_html": (
                f"Export writes <code>audit-{html.escape(name)}-verdicts.json</code> to your downloads folder. "
                "Tell me it's there and I'll run the reveal: which cards carried a plant, which of those you "
                "caught, and every defect you found on a card that carried none — those are real, and go "
                "through the Wave 2 fix path. Your verdicts are also kept in this browser."
            ),
        },
        "sections": [{
            "key": "sample",
            "kind": "k-scope",
            "title": "Sampled paragraphs",
            "tag": "Sample",
            "count": f"{cards} paragraphs",
            "note_html": (
                "Page image first, then the card. <b>Exact</b>: the site says what the source says — words, "
                "numbers, punctuation and emphasis. <b>Trivial</b>: a difference the site's own conventions "
                "account for, such as a heading's case or an enriched cross-reference. <b>Defect</b>: "
                "anything else, with a note saying what."
            ),
            "labels": {"accept": "Exact", "reject": "Defect", "discuss": "Trivial"},
            "items": items,
        }],
    }

    source_line = {c["id"]: dict(c["lines"]) for c in cards_data}
    key = {
        "pass": page["pass"],
        "record": name,
        "planted": [
            {"id": card_id, **plant.describe(source_line[card_id][plant.line])}
            for card_id, plant in sorted(hosts.items())
        ],
    }

    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    sample_path = out / f"{name}.sample.json"
    sample_path.write_text(json.dumps(page, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / f"{name}.key.json").write_text(json.dumps(key, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    load_builder().build(sample_path, out / f"{name}.html")
    print(f"Key kept off the page, in {out / f'{name}.key.json'} — the auditor should not open it.")


def load_builder():
    spec = importlib.util.spec_from_file_location("build_adjudication_page", BUILDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ── reveal ─────────────────────────────────────────────────────────────────


def reveal(args):
    try:
        name = ap.resolve(args.record).name
    except ap.PopulationError as error:
        fail(str(error))
    out = args.output_dir
    try:
        page = json.loads((out / f"{name}.sample.json").read_text(encoding="utf-8"))
        key = json.loads((out / f"{name}.key.json").read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        fail(f"no draw to reveal for {name}: {error.filename}")
    verdicts = json.loads(args.verdicts.read_text(encoding="utf-8"))
    try:
        result = score(
            page, key, verdicts,
            auditor=args.auditor or git("config", "user.name"),
            other_defects=set(args.other_defect),
        )
    except ValueError as error:
        fail(str(error))

    AUDITS.mkdir(parents=True, exist_ok=True)
    path = AUDITS / f"{name}.yml"
    header = (
        f"# Wave 3 sampling audit of {name} (epic #734, #746). Written by\n"
        "# scripts/sample-audit.py reveal — see workflow/validation/audits/README.md.\n"
    )
    path.write_text(header + sample.to_yaml(result), encoding="utf-8")

    bound = result["bound"]
    print(f"{name}: {result['sample']['audited']} audited, {result['plants']['planted']} planted")
    print(f"  plants caught:  {result['plants']['caught']} of {result['plants']['planted']}")
    print(f"  real defects:   {bound['real_defects']}")
    print(f"  95% bound:      {bound['upper']:.1%} raw, {bound['adjusted_upper']:.1%} adjusted for sensitivity")
    for entry in result["paragraphs"]:
        plant = entry["planted"]
        if plant and entry["verdict"] == "defect":
            print(f"  {entry['id']} planted {plant['kind']} ({plant['from']!r} → {plant['to']!r}); note: {entry['note']!r}")
            print("         confirm the note names the plant; if it names something else, re-run with "
                  f"--other-defect {entry['id']}")
        elif plant:
            print(f"  {entry['id']} MISSED {plant['kind']} ({plant['from']!r} → {plant['to']!r}), verdict {entry['verdict']}")
        if entry["id"] in {f["id"] for f in result["findings"]}:
            print(f"  {entry['id']} REAL DEFECT at {entry['file']}:{entry['lines']} — {entry['note']!r}")
    print(f"Record written: {path.relative_to(REPO_ROOT)}")


def score(
    page: dict, key: dict, verdicts: dict, auditor: str,
    other_defects: set[str] = frozenset(), today: str | None = None,
) -> dict:
    """The committed audit record, from the draw, its key and the exported verdicts.

    `other_defects` names planted cards whose Defect note turned out to describe
    something other than the plant. That is a real finding — it goes in
    `findings` for the fix path — and the plant itself was missed. It stays out
    of the bound all the same: a planted card's text was altered on the page,
    so it was never part of the audited sample the rate is measured over.
    """
    if verdicts.get("pass") != page["pass"] or key.get("pass") != page["pass"]:
        raise ValueError(
            f"verdicts are for {verdicts.get('pass')!r} and the key for {key.get('pass')!r}, "
            f"but the draw is {page['pass']!r} — they are not from the same draw"
        )
    items = page["sections"][0]["items"]
    decided = {d["id"]: d for d in verdicts.get("decisions", [])}
    if set(decided) != {i["id"] for i in items}:
        raise ValueError("the verdicts do not cover exactly the cards that were drawn")
    open_cards = [i for i, d in decided.items() if d.get("decision") not in sample.VERDICTS]
    if open_cards:
        raise ValueError(f"undecided cards: {', '.join(sorted(open_cards))} — every card needs a verdict")
    plants = {p["id"]: p for p in key["planted"]}
    stray = {i for i in other_defects if i not in plants or sample.VERDICTS[decided[i]["decision"]] != "defect"}
    if stray:
        raise ValueError(f"--other-defect names cards that are not planted Defect verdicts: {', '.join(sorted(stray))}")

    tally = {"exact": 0, "trivial": 0, "defect": 0}
    paragraphs, findings, caught, real = [], [], 0, 0
    for item in items:
        verdict = sample.VERDICTS[decided[item["id"]]["decision"]]
        tally[verdict] += 1
        plant = plants.get(item["id"])
        entry = {
            "id": item["id"],
            "pdf_page": item["pdf_page"],
            "file": str(Path(page["content_dir"]) / item["file"]) if page["content_dir"] != "." else item["file"],
            "lines": item["lines"],
            "verdict": verdict,
            "note": decided[item["id"]].get("note"),
            "planted": None,
        }
        if plant:
            hit = verdict == "defect" and item["id"] not in other_defects
            entry["planted"] = {k: plant[k] for k in ("kind", "line", "from", "to")} | {"caught": hit}
            caught += hit
        elif verdict == "defect":
            real += 1
        if verdict == "defect" and (not plant or item["id"] in other_defects):
            findings.append({k: entry[k] for k in ("id", "pdf_page", "file", "lines", "note")})
        paragraphs.append(entry)

    audit = page["audit"]
    audited = len(items) - len(plants)
    return {
        "record": audit["record"],
        "epic": 734,
        "source_pdf": page["source_pdf"],
        "scorer_version": page["scorer_version"],
        "commit": audit["commit"],
        "seed": audit["seed"],
        "drawn_at": audit["drawn_at"],
        "revealed_at": today or datetime.date.today().isoformat(),
        "auditor": auditor,
        "population": audit["population"],
        "sample": {"cards": len(items), "audited": audited, "planted": len(plants)},
        "verdicts": tally,
        "plants": {"planted": len(plants), "caught": caught},
        "bound": sample.adjusted_bound(real, audited, len(plants), caught),
        "findings": findings,
        "paragraphs": paragraphs,
    }


# ── main ───────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    d = sub.add_parser("draw", help="draw a seeded sample and build its review page")
    d.add_argument("record", help="day-05, 5, appendix-main, welcome, …")
    d.add_argument("--seed", type=int, help="default: the record's Wave 2 pass issue number")
    d.add_argument("--size", type=int, default=DEFAULT_CARDS, help=f"cards on the page (default {DEFAULT_CARDS})")
    d.add_argument("--allow-unadjudicated", action="store_true", help="draw before the record's Wave 2 pass is decided")
    d.add_argument("--allow-dirty", action="store_true", help="draw from uncommitted content (testing only)")
    d.add_argument("--output-dir", type=Path, default=WORK_DIR)

    r = sub.add_parser("reveal", help="score exported verdicts and write the audit record")
    r.add_argument("record")
    r.add_argument("--verdicts", type=Path, required=True, help="the JSON file the page exported")
    r.add_argument("--auditor", help="who audited (default: git config user.name)")
    r.add_argument("--other-defect", action="append", default=[], metavar="ID",
                   help="a planted card whose Defect note names something other than the plant (repeatable)")
    r.add_argument("--output-dir", type=Path, default=WORK_DIR)

    args = parser.parse_args()
    if args.command == "draw":
        if args.size < 5:
            fail("--size must be at least 5")
        draw(args)
    else:
        reveal(args)


if __name__ == "__main__":
    main()
