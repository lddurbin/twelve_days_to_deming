#!/usr/bin/env python3
"""audit_population.py — the matched-cleanly population a Wave 3 audit draws from.

Part of #746, under epic #734. A results file in workflow/validation/results/
says how many PDF paragraphs matched cleanly, and nothing about which ones:
validate-transcription.sh writes counts, never lists. This module re-derives
the list, and then refuses to hand it over unless it re-derives the counts too.

**A reader of the comparison pipeline, not part of it.** None of this module is
in SCORER_VERSION_FILES (scripts/lib/scorer-version.sh), and nothing here may
become something the validator depends on. Two reasons, both load-bearing:

  - It must not move `scorer_version`. A hashed file edited to serve the audit
    would restale all eighteen results records and invalidate whatever Wave 2
    pass is open at the time — see the "Wave 2 is not serial" note in #734.
  - It must not be a second definition of what the pipeline does. Every step
    below calls the pipeline's own code: the PDF extraction is the validator's
    own `extract_pdf_text` function, lifted out of the shell script and run as
    written, and every Python stage is imported rather than copied. The one
    place this module has to restate the pipeline's order — attaching page
    numbers to paragraphs, which the pipeline computes and then discards — is
    checked against the pipeline's own output and fails if the two disagree.

The guard on all of it is the cross-check in `derive()`: the counts computed
here must equal the counts the validator recorded, and the recorded
`scorer_version` must be current. A population that passes both is the one the
validator classified; one that fails either is refused with the reason.
"""

from __future__ import annotations

import collections
import hashlib
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import paragraph_similarity as ps
import paragraphs as pg
import qmd_strip

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATION = REPO_ROOT / "workflow" / "validation"
PDF_DIR = REPO_ROOT / "12-Days-to-Deming" / "PDFs"
VALIDATOR = REPO_ROOT / "scripts" / "validate-transcription.sh"

# A PDF letter prefix per day, as validate-transcription.sh's day_to_prefix().
_DAY_PREFIX = {day: chr(67 + day) for day in range(1, 13)}


class PopulationError(Exception):
    """The population cannot be trusted to be the one the validator classified."""


@dataclass
class Record:
    """One validation record: which PDF, which chapters, which results file."""

    name: str  # "day-05", "appendix-main", "welcome"
    pdf: Path
    qmd_files: list[Path]  # sorted, no-source pages removed — as the validator
    results: Path


@dataclass
class Paragraph:
    """A matched-cleanly PDF paragraph, as the comparator saw it."""

    text: str
    page: int  # PDF page the paragraph starts on
    occurrence: int  # 0 for the first paragraph with this exact text, 1 for the next…


@dataclass
class Population:
    record: Record
    results: dict  # the parsed results file
    paragraphs: list[Paragraph]
    qmd_pool: list = field(repr=False, default_factory=list)
    short_pool: list = field(repr=False, default_factory=list)


# ── Records ────────────────────────────────────────────────────────────────


def resolve(name: str) -> Record:
    """A record from `day-05`, `5`, `appendix-main` or `welcome`.

    Mirrors the two ways validate-transcription.sh finds its inputs: a day by
    PDF letter prefix and directory glob, a manifest by its own chapter list.
    """
    if re.fullmatch(r"\d{1,2}", name):
        name = f"day-{int(name):02d}"
    day = re.fullmatch(r"day-(\d{2})", name)
    if day:
        number = int(day.group(1))
        if number not in _DAY_PREFIX:
            raise PopulationError(f"no such day: {name}")
        pdfs = sorted(PDF_DIR.glob(f"{_DAY_PREFIX[number]}.Day.*.pdf"))
        if not pdfs:
            raise PopulationError(f"no source PDF for {name} in {PDF_DIR}")
        rel = sorted(
            str(p.relative_to(REPO_ROOT))
            for p in (REPO_ROOT / "content" / "days" / name).glob("*.qmd")
        )
        pdf = pdfs[0]
    else:
        manifest = VALIDATION / f"{name}-manifest.yml"
        if not manifest.exists():
            raise PopulationError(f"no manifest for {name}: {manifest}")
        data = _manifest(manifest)
        pdf = PDF_DIR / data["pdf_file"]
        content = data["content_dir"]
        rel = sorted(
            ch if content == "." else f"{content}/{ch}" for ch in data["chapters"]
        )

    no_source = set(_no_source_pages())
    files = [REPO_ROOT / r for r in sorted(rel) if r not in no_source]
    if not pdf.exists():
        raise PopulationError(f"source PDF not found: {pdf}")
    return Record(name, pdf, files, VALIDATION / "results" / f"{name}.yml")


def _manifest(path: Path) -> dict:
    """pdf_file, content_dir and chapter files from a manifest.

    Read the way the validator reads it — through ruby's YAML — so there is
    one parser's idea of the file rather than two.
    """
    script = (
        'd = YAML.safe_load(File.read(ARGV[0])); '
        'puts d["pdf_file"].to_s; puts d["content_dir"].to_s; '
        '(d["chapters"] || []).each { |c| puts c["file"] }'
    )
    out = _run(["ruby", "-ryaml", "-e", script, str(path)]).splitlines()
    if len(out) < 2 or not out[0] or not out[1]:
        raise PopulationError(f"{path.name} declares no pdf_file or content_dir")
    return {"pdf_file": out[0], "content_dir": out[1], "chapters": out[2:]}


def _no_source_pages() -> list[str]:
    script = '(YAML.safe_load(File.read(ARGV[0]))["pages"] || {}).each_key { |k| puts k }'
    return _run(["ruby", "-ryaml", "-e", script, str(VALIDATION / "no-source.yml")]).split()


def read_results(path: Path) -> dict:
    """The flat `key: value` fields of a results file, with `counts:` nested.

    The results files are written by a heredoc in validate-transcription.sh
    and have exactly two levels, so this reads them as lines rather than
    shelling out to a YAML parser for twenty scalars.
    """
    if not path.exists():
        raise PopulationError(f"no results file: {path} — run the validator first")
    data: dict = {}
    section = None
    for line in path.read_text(encoding="utf-8").splitlines():
        top = re.fullmatch(r"([a-z0-9_]+):\s*(.*)", line)
        nested = re.fullmatch(r"  ([a-z0-9_]+):\s*(.+)", line)
        if top:
            key, value = top.groups()
            if value:
                data[key], section = value, None
            else:
                data[key], section = {}, key
        elif nested and section:
            data[section][nested.group(1)] = nested.group(2)
    return data


# ── The pipeline, run as the validator runs it ─────────────────────────────


def _run(argv: list[str], stdin: str | None = None) -> str:
    done = subprocess.run(
        argv, input=stdin, capture_output=True, text=True, encoding="utf-8", cwd=REPO_ROOT
    )
    if done.returncode != 0:
        raise PopulationError(f"{argv[0]} failed: {done.stderr.strip()}")
    return done.stdout


def scorer_version() -> str:
    return _run(
        ["bash", "-c", '. scripts/lib/scorer-version.sh && compute_scorer_version "$PWD"']
    ).strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract_pdf_text(pdf: Path, qmd_text: str) -> str:
    """The validator's own extract_pdf_text(), run exactly as written.

    Lifted out of validate-transcription.sh by its definition's first and last
    lines rather than copied here, because that function holds the one stage of
    the pipeline that is not Python — a sed program of page-furniture rules —
    and a second copy of it is the drift #737 exists to prevent. If the
    function is renamed or reshaped so the lift fails, this fails with it.
    """
    definition = lift_function(VALIDATOR.read_text(encoding="utf-8"), "extract_pdf_text")
    qmd_path = _scratch(qmd_text)
    try:
        script = (
            "set -euo pipefail\nexport LC_ALL=C\n"
            f'REPO_ROOT="{REPO_ROOT}"\n{definition}\n'
            'extract_pdf_text "$1" "$2"\n'
        )
        return _run(["bash", "-c", script, "extract", str(pdf), str(qmd_path)])
    finally:
        qmd_path.unlink(missing_ok=True)


def lift_function(source: str, name: str) -> str:
    """The definition of shell function `name` in `source`, verbatim."""
    match = re.search(rf"^{re.escape(name)}\(\) \{{\n.*?^\}}\n", source, re.S | re.M)
    if not match:
        raise PopulationError(f"could not find {name}() in validate-transcription.sh")
    # The lift ends at the first `}` in column 0. The script indents every
    # function body, so that is the function's own closing brace — but if a
    # later edit puts a column-0 `}` inside the body, the lift would be cut
    # short. What follows a whole function is top-level code: a blank line, a
    # comment, or the next definition. Anything else means a truncated lift,
    # and it is named here rather than surfacing as a count mismatch in derive().
    rest = source[match.end():].lstrip("\n")
    if rest and not re.match(r"#|[A-Za-z_]\w*\(\) \{|main ", rest):
        raise PopulationError(
            f"{name}() did not lift cleanly out of validate-transcription.sh "
            "(a column-0 `}` inside its body?)"
        )
    return match.group(0)


def _scratch(text: str) -> Path:
    handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False)
    with handle:
        handle.write(text)
    return Path(handle.name)


def paged_paragraphs(text: str) -> list[pg.Block]:
    """to_paragraphs(), keeping the page each paragraph starts on.

    The pipeline computes these pages and drops them when it keeps only the
    text. Restating its order here — readable, rejoined, floored — is the one
    copy this module makes, so it is checked against to_paragraphs() itself.
    """
    readable = [b for b in pg.read_blocks(text) if pg.is_readable(b.text)]
    kept = [
        b for b in pg.join_continuations(readable) if len(b.text.encode("utf-8")) >= pg.MIN_PARA_LEN
    ]
    if [b.text for b in kept] != pg.to_paragraphs(text):
        raise PopulationError("paragraph assembly no longer matches paragraphs.py's order")
    return kept


def qmd_combined(files: list[Path]) -> str:
    """The QMD side's text, as `qmd_strip.py file…` writes it."""
    return "".join(
        qmd_strip.strip_qmd(f.read_text(encoding="utf-8")) + "\n" for f in files
    )


# ── The population ─────────────────────────────────────────────────────────


def derive(record: Record) -> Population:
    """Every matched-cleanly PDF paragraph of `record`, verified against its results.

    Refuses — raising PopulationError with the reason — when the results file
    is stale, was recorded against a different PDF, or describes a different
    classification than the one computed here. Any of those means the list
    below is not the population the recorded counts are about.
    """
    results = read_results(record.results)
    current = scorer_version()
    if results.get("scorer_version") != current:
        raise PopulationError(
            f"{record.results.name} was recorded by scorer {results.get('scorer_version')}, "
            f"not the current {current} — re-run the validator before drawing"
        )
    if results.get("source_sha256") != sha256(record.pdf):
        raise PopulationError(f"{record.results.name} was recorded against a different PDF")

    qmd_text = qmd_combined(record.qmd_files)
    qmd_paras = pg.to_paragraphs(qmd_text)
    qmd_short = [b.text for b in pg.sift(qmd_text).short]
    pdf_blocks = paged_paragraphs(extract_pdf_text(record.pdf, qmd_text))
    pdf_paras = [b.text for b in pdf_blocks]

    missing, altered, matched, _refs = ps.classify_forward(
        pdf_paras,
        qmd_paras,
        ps.MISSING_SIMILARITY_THRESHOLD,
        ps.ALTERED_SIMILARITY_THRESHOLD,
        qmd_short=qmd_short,
    )

    # Identical paragraphs score identically, so removing the flagged ones as a
    # multiset leaves exactly the matched ones, duplicates and order intact.
    flagged = collections.Counter(p for p, _best, _covered in missing) + collections.Counter(
        p for p, _ in altered
    )
    population, seen = [], collections.Counter()
    for block in pdf_blocks:
        if flagged[block.text]:
            flagged[block.text] -= 1
            continue
        population.append(Paragraph(block.text, block.page, seen[block.text]))
        seen[block.text] += 1

    counts = results.get("counts", {})
    computed = {
        "pdf_paragraphs": len(pdf_paras),
        "qmd_paragraphs": len(qmd_paras),
        "matched_cleanly": matched,
        "altered": len(altered),
        "missing": len(missing),
    }
    drift = {
        k: (counts.get(k), v) for k, v in computed.items() if str(v) != counts.get(k)
    }
    if drift or len(population) != matched:
        detail = ", ".join(f"{k} recorded {r} computed {c}" for k, (r, c) in drift.items())
        raise PopulationError(
            f"{record.name}: the content no longer classifies as recorded ({detail or 'population size'}) "
            "— re-run the validator and commit its results before drawing"
        )

    return Population(
        record,
        results,
        population,
        qmd_pool=ps.build_pool(qmd_paras),
        short_pool=ps.build_pool(qmd_short),
    )


# ── Where a paragraph lives on the site ────────────────────────────────────

# A line strip_qmd() passes through untouched: no bracket, tag, asterisk,
# caret, leading `#`, `>` or `:`, and no dashes to read as a rule. Interleaved
# after every source line, it lets the stripper's own output say which source
# line each output line came from — see stripped_lines().
_SENTINEL = "@@qmd-line {}@@"
_SENTINEL_LINE = re.compile(r"^@@qmd-line (\d+)@@$")


@dataclass
class Block:
    """A blank-line-delimited run of stripped lines, with where it came from."""

    file: Path
    pieces: list[tuple[int, str]]  # (1-based source line, its stripped text, whitespace collapsed)

    @property
    def first(self) -> int:
        return self.pieces[0][0]

    @property
    def text(self) -> str:
        """Collapsed as paragraphs.read_blocks() collapses a block."""
        return " ".join(t for _, t in self.pieces)


def stripped_lines(source: str) -> list[tuple[int, str]]:
    """(source line number, stripped text) for every line strip_qmd() keeps.

    strip_qmd() writes one output line per kept input line but does not say
    which, and the state it carries (front matter, code fences) means a line
    cannot be stripped on its own. So a sentinel line is placed after every
    source line and the whole file stripped once: whatever output sits between
    sentinel N-1 and sentinel N is line N's. A line the stripper dropped leaves
    nothing there. Checked against a plain strip of the same file, so a future
    rule that alters the sentinel fails here rather than misnumbering silently.
    """
    lines = source.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    marked = "".join(f"{line}\n{_SENTINEL.format(n)}\n" for n, line in enumerate(lines, 1))
    kept, pending = [], []
    for out in qmd_strip.strip_qmd(marked).split("\n")[:-1]:
        sentinel = _SENTINEL_LINE.match(out)
        if sentinel:
            if len(pending) > 1:
                raise PopulationError("strip_qmd() wrote two lines for one source line")
            kept.extend((int(sentinel.group(1)), text) for text in pending)
            pending = []
        else:
            pending.append(out)
    if "".join(f"{t}\n" for _, t in kept) != qmd_strip.strip_qmd(source):
        raise PopulationError("line provenance disagrees with strip_qmd()")
    return kept


def site_blocks(path: Path) -> list[Block]:
    """A .qmd file's stripped text as blocks, each line still carrying its number.

    Collapsing each line's whitespace and joining lines with one space gives
    the same string read_blocks() makes of the block, which is what lets a
    character offset in a matched sentence be traced back to a source line.
    """
    blocks, current = [], []
    for number, text in stripped_lines(path.read_text(encoding="utf-8")) + [(0, "")]:
        if text.strip():
            current.append((number, " ".join(text.split())))
        elif current:
            blocks.append(Block(path, current))
            current = []
    return blocks


# How many consecutive readable blocks one matched QMD sentence can straddle.
# join_continuations() chains blocks at a colon or semicolon, so a lead-in
# and the first item it introduces become one sentence; no matched sentence in
# the corpus needs more than two (measured 2026-09-13), and this leaves room.
_MAX_JOIN = 4


@dataclass
class Excerpt:
    """The site passage a matched PDF paragraph was matched against."""

    file: Path
    lines: list[tuple[int, int]]  # (block index within the run, 1-based source line)
    text: str  # those lines' stripped text, joined as join_continuations() joins
    spans: list[tuple[int, int]]  # [start, end) of each sentence found in `text`
    # (sentence, file, line) matched outside it; file and line are None when no
    # run of blocks holds the sentence at all, so there is no line to point to.
    elsewhere: list[tuple[str, Path | None, int | None]]


def locate(para: Paragraph, pop: Population, blocks: dict[Path, list[Block]]) -> Excerpt:
    """Where on the site `para` was matched, as one contiguous run of blocks.

    The comparator pools every sentence of the record and never records where
    a match came from, so this asks it again — score_paragraph() returns each
    PDF sentence's best QMD sentence — and finds those sentences among the
    source blocks. The run chosen is the one holding the most of them in the
    fewest blocks.

    A paragraph can match cleanly with a sentence that lives somewhere else
    entirely: a short "Why?" or a stock phrase scores 1.0 against any copy of
    itself. Stretching the excerpt to reach it would put chapters of unrelated
    text in front of the auditor (measured: 11 blocks for one Day 1
    paragraph), so such a sentence is left out of the run and returned in
    `elsewhere`, for the card to name. 4 of the 2207 paragraphs corpus-wide
    have one (2026-09-13).
    """
    scored = ps.score_paragraph(para.text, pop.qmd_pool, pop.short_pool, ps.ALTERED_SIMILARITY_THRESHOLD)
    sentences = [qmd for _score, _pdf, qmd, _evidence in scored]
    readable = {f: [b for b in bl if pg.is_readable(b.text)] for f, bl in blocks.items()}

    def windows(sentence):
        """(file, lo, hi) for every run the sentence starts in and fits inside."""
        found = []
        for f, bl in readable.items():
            for i in range(len(bl)):
                for w in range(1, min(_MAX_JOIN, len(bl) - i) + 1):
                    if sentence in " ".join(b.text for b in bl[i : i + w]):
                        # Starting in block i, not merely reaching past it.
                        if w == 1 or sentence not in " ".join(b.text for b in bl[i + 1 : i + w]):
                            found.append((f, i, i + w))
                        break
        return found

    candidates = [windows(s) for s in sentences]
    if not sentences or not any(candidates):
        raise PopulationError(f"could not find PDF p{para.page}'s matched sentences on the site")

    # A paragraph legitimately spans one block per sentence at most (a lettered
    # list set as separate site paragraphs), plus one for a lead-in.
    width = max(len(sentences) + 1, _MAX_JOIN)
    best = None  # (-sentences placed, blocks spanned, file, chosen windows)
    for f in readable:
        for start in range(len(readable[f])):
            chosen = []
            for options in candidates:
                inside = [o for o in options if o[0] == f and start <= o[1] and o[2] <= start + width]
                chosen.append(min(inside, key=lambda o: o[1]) if inside else None)
            placed = [o for o in chosen if o]
            if not placed:
                continue
            span = max(o[2] for o in placed) - min(o[1] for o in placed)
            key = (-len(placed), span)
            if best is None or key < best[:2]:
                best = (-len(placed), span, f, chosen)

    _, _, f, chosen = best
    lo = min(o[1] for o in chosen if o)
    hi = max(o[2] for o in chosen if o)
    run = readable[f][lo:hi]
    text = " ".join(b.text for b in run)
    spans, elsewhere, cursor = [], [], 0
    for sentence, window, options in zip(sentences, chosen, candidates):
        if window is None:
            if options:
                other_file, i, _ = options[0]
                elsewhere.append((sentence, other_file, readable[other_file][i].first))
            else:
                elsewhere.append((sentence, None, None))
            continue
        at = text.find(sentence, cursor)
        if at < 0:
            at = text.find(sentence)
        spans.append((at, at + len(sentence)))
        cursor = max(cursor, at + len(sentence))

    # Trim to the source lines the matched sentences touch. A block is a
    # blank-line-delimited run, and the site sets some lists as one run of
    # hard-wrapped lines: Day 1's "optimum system" list is a single block of
    # fourteen lines, where the PDF makes each bullet its own paragraph.
    placed, offset = [], 0
    for index, block in enumerate(run):
        for number, piece in block.pieces:
            placed.append((index, number, offset, offset + len(piece)))
            offset += len(piece) + 1
    touched = [i for i, (_, _, s, e) in enumerate(placed) if any(s < b and a < e for a, b in spans)]
    shown = placed[touched[0] : touched[-1] + 1]
    start, end = shown[0][2], shown[-1][3]
    return Excerpt(
        file=f,
        lines=[(index, number) for index, number, _, _ in shown],
        text=text[start:end],
        spans=[(a - start, b - start) for a, b in spans],
        elsewhere=elsewhere,
    )
