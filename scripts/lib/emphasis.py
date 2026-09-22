#!/usr/bin/env python3
"""Find emphasis Neave's source PDFs carry that the site's .qmd files lost.

The paragraph comparator works on *stripped* text, so emphasis is invisible to
it by construction: a paragraph that drops every italic in it still scores a
perfect match. Spike #825 established that the gap is mechanically closeable —
`pdftohtml -xml` already tags each run <b>/<i> from the embedded font's own
descriptor, so no per-PDF calibration is needed — and measured 40/40 precision
on a seeded random sample of "lost" runs checked against the page images.
This module is that spike's recommendation 1, built for production.

    PDF side   `pdftohtml -xml`, read per character (a single <text> element
               can mix styles: `<i>DemDim</i> Chapter 18 provides…`)
    QMD side   the pandoc JSON AST, which gives Strong/Emph, headers, divs
               with their classes, links and tables without any markdown
               parsing of our own
    compare    align the two word streams with difflib and report every
               aligned word whose emphasis disagrees, grouped into runs

Both sides are read *per character* and cut into words at whitespace only, and
each word carries a **profile**: one (bold, italic) pair per letter of its
aligned form. That is what makes the comparison independent of markup, and
#850 is why it has to be. Neave emphasises part of a word — `outcome` bold
inside the printed word `outcomes,` — and pandoc hands `*two*-minute` over as
two inlines. Until #850 this module styled a word by the majority of its
letters and cut the .qmd side at every inline boundary, so the two streams
disagreed about what a word *was*: one PDF token faced two .qmd tokens
wherever the site's markup was correct, and a partial emphasis was rounded to
whichever half was longer. Splitting the PDF side to match was measured and
regresses — it moves `outcomes,` from *reported* to *unaligned*, which is the
case the checker exists for. A profile instead leaves the token stream alone
and makes a partial emphasis a mismatch on the letters it actually covers.

Three kinds of run, counted separately (#846):

    lost      emphasised in the PDF, plain on the site  — the fix backlog
    added     plain in the PDF, emphasised on the site
    swapped   bold on one side, italic on the other     — its own class,
              because it has never been sampled systematically and should
              not inflate the headline `lost` number

Colour is never emphasis here. Neave's red and blue text is detected (it is
available as `fontspec color`) but only ever recorded as an informational note
on a run some *other* rule already raised — it cannot create a finding. What
the site's equivalent of a coloured run should be is an editorial question,
and the site has its own colour conventions (`deming_blue`,
`text-highlight-red`, `.deming_quote`) that a mechanical rule would fight.
Colour-only emphasis stays a human-auditor blind spot: see
workflow/validation/audits/README.md.

Requires `pdftohtml` (poppler) and `quarto` on PATH. Python stdlib only.
"""
import collections
import difflib
import glob
import html
import json
import os
import re
import subprocess
import unicodedata

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFEST_DIR = os.path.join(REPO_ROOT, "workflow", "validation")
PDF_DIR = os.path.join(REPO_ROOT, "12-Days-to-Deming", "PDFs")

# Day number → the letter its source PDF is named with. Mirrors
# day_to_prefix() in scripts/validate-transcription.sh.
DAY_PREFIX = dict(zip(range(1, 13), "DEFGHIJKLMNO"))


# ── The convention allowlist ───────────────────────────────────────────────
#
# A disagreement between the two sides is only a defect if the site is not
# already rendering that word the way Neave set it. These are the ways it
# does so without any markup in the .qmd, so a run explained by one of them
# is reported as explained and kept out of the counts.
#
# ADDING A CLASS IS A ONE-LINE CHANGE, and that is deliberate: a new CSS rule
# that styles text would otherwise turn every word it covers into a false
# "lost" finding. Before adding one, check it really does set font-weight or
# font-style in assets/styles/main.css — an unjustified entry here silently
# suppresses real findings, which is the more expensive mistake.
#
# Every class below was verified against assets/styles/main.css when this
# module was written (#846): each sets font-weight bold/600 or font-style
# italic. `neave_note` is deliberately NOT among them — it sets neither, and
# needs the separate long-run rule below.
#
# Known over-suppression: several of these rule blocks also carry a nested
# `font-style: normal` reset, so being inside the class does not prove this
# particular word is styled. The rule is kept broad anyway, because a missed
# finding inside a callout is cheaper than a class of noise across every one.
STYLED_CLASSES = frozenset({
    "principle_callout",           # font-style: italic; font-weight: bold
    "aside_callout",               # font-style: italic; font-weight: bold
    "deming_quote",                # font-style: italic; font-weight: bold
    "foreman-remark",              # font-style: italic; font-weight: bold
    "activity_afterthought",       # font-style: italic
    "text-highlight-red",          # font-weight: bold
    "table-cell-highlight",        # font-weight: bold
    "callout-emphasis",            # font-style: italic; font-weight: bold
    "centered-bold-callout",       # font-weight: bold
    "analysis_box_title",          # font-weight: bold
    "major_activity_title",        # font-weight: bold
    "foreman-transcript-context",  # font-weight: 600
})

# Neave sets long asides in italics throughout; the site carries them with the
# `neave_note` class, which styles the block rather than the words. Short
# emphasis *inside* such a note is still real, so this applies only to runs
# long enough to be the aside itself rather than a phrase within it.
NEAVE_NOTE_CLASS = "neave_note"
NEAVE_NOTE_MIN_WORDS = 5

# Maths is italic because the renderer makes it so. The site writes `$n$` and
# `$\bar{X}$`; MathJax sets the variables in italic without the .qmd ever
# saying `*n*`, and Neave's source sets them in an italic font for the same
# typographic reason. So a disagreement inside maths is the two renderers
# agreeing, not the site losing anything.
#
# This is the single largest class in the corpus: 285 of the Optional Extras
# appendix's 379 raw "lost" runs before this rule, which is the same root
# cause #744's triage found dominating that appendix's near-certain band (93
# of 221) on the paragraph-similarity side.
MATH_CONTEXT = "math"

# Site conventions that produce emphasis the PDF does not have. Both are
# "added" runs by construction, so they are only consulted for that kind.
#
# The checklist labels are the site's own scaffolding for the Activity
# 10A/10B/11A/11B point-by-point lists — `**POINT 7.**`, `**DISEASE 3.**` —
# and have no counterpart in Neave's running text.
CHECKLIST_LABEL = re.compile(r"^(POINT|DISEASE)S?$|^\d{1,2}[.)]?$", re.I)

# Runs of pure page furniture: nothing to say about emphasis on a word that is
# only ever a page number.
PAGE_FURNITURE = re.compile(r"^\d+$")

SPLIT = re.compile(r"[\s—–/]+")


def _fold(text):
    """The letters `text` contributes to the form the streams align on."""
    return re.sub(r"[^a-z0-9]", "",
                  unicodedata.normalize("NFKD", text).lower())


def norm(word):
    """Fold a word to the form the two streams are aligned on.

    Case, accents and punctuation all differ harmlessly between `pdftohtml`
    output and the .qmd (curly vs straight quotes, most often), and none of
    them bears on whether a word is emphasised.
    """
    return _fold(word)


def profile(chars):
    """One word's aligned form, and the style each letter of it carries.

    `chars` is a sequence of (character, bold, italic). Returns
    (aligned form, styles) where `styles` has exactly one (bold, italic) pair
    per character of the aligned form, so two words that aligned — which
    means their aligned forms are equal — have profiles that compare position
    by position.

    Folding per character is what keeps those two in step, and it also
    disposes of the problem the old majority-of-letters rule existed to
    solve: punctuation folds to nothing, so a trailing italic comma
    contributes no position and cannot make the word italic. Only letters a
    reader would see emphasised are ever compared.
    """
    folded, styles = [], []
    for character, bold, italic in chars:
        letters = _fold(character)
        folded.append(letters)
        styles.extend(((bold, italic),) * len(letters))
    return "".join(folded), tuple(styles)


# ── Record resolution ──────────────────────────────────────────────────────


class RecordError(Exception):
    """A record could not be resolved — unknown name, or a broken manifest."""


class Record:
    """What one run of the checker addresses: a PDF, and the chapters that
    claim to transcribe it.

    The chapter list comes from the manifest rather than from globbing the
    content directory, for the reason #802 gives: a chapter is answerable to a
    PDF because someone said it came from that PDF, not because of where it
    sits on disk.
    """

    def __init__(self, name, pdf_path, content_dir, chapters):
        self.name = name
        self.pdf_path = pdf_path
        self.content_dir = content_dir
        self.chapters = chapters

    @property
    def qmd_paths(self):
        return [os.path.join(self.content_dir, c) for c in self.chapters]


def _read_manifest(path):
    """Parse a manifest with ruby, as scripts/validate-transcription.sh does.

    Ruby rather than Python: this repo cannot rely on PyYAML being installed
    (it is not, on the maintainer's machine), and the shell validator already
    took this dependency, so it adds nothing new.
    """
    if not os.path.isfile(path):
        raise RecordError(f"No manifest found at {path}")
    script = """
      begin
        data = YAML.safe_load(File.read(ARGV[0]))
      rescue => e
        $stderr.puts "Error parsing manifest #{ARGV[0]}: #{e.message}"
        exit 1
      end
      puts "PDF_FILE=#{data["pdf_file"] || ""}"
      puts "CONTENT_DIR=#{data["content_dir"] || ""}"
      (data["chapters"] || []).each { |ch| puts "CHAPTER=#{ch["file"]}" }
    """
    proc = subprocess.run(["ruby", "-ryaml", "-e", script, path],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RecordError(proc.stderr.strip() or f"Could not read {path}")
    pdf_file = content_dir = ""
    chapters = []
    for line in proc.stdout.splitlines():
        key, _, value = line.partition("=")
        if key == "PDF_FILE":
            pdf_file = value
        elif key == "CONTENT_DIR":
            content_dir = value
        elif key == "CHAPTER":
            chapters.append(value)
    return pdf_file, content_dir, chapters


def resolve(name):
    """Resolve a record name to a Record.

    `name` is a day number ("5", "05") or a manifest name ("appendix-main",
    "welcome"). Day records take their PDF from the letter-prefix mapping and
    their content directory from the conventional path, exactly as day mode
    does in the shell validator; every other record declares both in its own
    manifest.
    """
    day_match = re.fullmatch(r"(?:day-)?(\d{1,2})", str(name))
    if day_match:
        day = int(day_match.group(1))
        if not 1 <= day <= 12:
            raise RecordError(f"Day number must be between 1 and 12, got {day}")
        prefix = DAY_PREFIX[day]
        found = sorted(glob.glob(os.path.join(PDF_DIR, f"{prefix}.Day.*.pdf")))
        if not found:
            raise RecordError(
                f"No PDF found for Day {day} (prefix {prefix}) in {PDF_DIR}. "
                "The source PDFs are gitignored and local-only — see #734."
            )
        manifest = os.path.join(MANIFEST_DIR, f"day-{day:02d}-manifest.yml")
        _, _, chapters = _read_manifest(manifest)
        if not chapters:
            raise RecordError(f"{manifest} declares no chapters")
        return Record(f"day-{day:02d}", found[0],
                      os.path.join(REPO_ROOT, "content", "days", f"day-{day:02d}"),
                      chapters)

    if not re.fullmatch(r"[A-Za-z0-9_-]+", str(name)):
        raise RecordError(
            f"Record name must contain only letters, digits, hyphens and "
            f"underscores, got {name!r}"
        )
    manifest = os.path.join(MANIFEST_DIR, f"{name}-manifest.yml")
    pdf_file, content_dir, chapters = _read_manifest(manifest)
    if not pdf_file or not content_dir:
        raise RecordError(f"{manifest} must declare pdf_file and content_dir")
    if not chapters:
        raise RecordError(f"{manifest} declares no chapters, so there is "
                          "nothing to compare")
    pdf_path = os.path.join(PDF_DIR, pdf_file)
    if not os.path.isfile(pdf_path):
        raise RecordError(
            f"Source PDF not found at {pdf_path}. The source PDFs are "
            "gitignored and local-only — see #734."
        )
    return Record(name, pdf_path, os.path.join(REPO_ROOT, content_dir), chapters)


def all_records():
    """Every record the checker can run: the twelve days, then each named
    manifest in alphabetical order.

    Day manifests are excluded from the named sweep — they carry no `pdf_file`
    and are reached through day mode, the same split the shell validator
    makes.
    """
    names = [f"{d}" for d in range(1, 13)]
    for path in sorted(glob.glob(os.path.join(MANIFEST_DIR, "*-manifest.yml"))):
        stem = os.path.basename(path)[: -len("-manifest.yml")]
        if not re.fullmatch(r"day-\d{2}", stem):
            names.append(stem)
    return names


# ── PDF side ───────────────────────────────────────────────────────────────

_FONTSPEC = re.compile(
    r'<fontspec id="(\d+)" size="(\d+)" family="([^"]+)" color="([^"]+)"')
_PAGE = re.compile(r'<page number="(\d+)".*?</page>', re.S)
_TEXT = re.compile(
    r'<text top="(\d+)" left="(\d+)" width="(\d+)" height="\d+" '
    r'font="(\d+)">(.*?)</text>', re.S)
_STYLE_TOKEN = re.compile(r"(</?[bi]>|<[^>]+>)")


def _styled_segments(inner):
    """Split one <text> element's inner markup into (text, style) segments.

    Poppler nests <b>/<i> *inside* an element rather than giving one style per
    element, so `<i>DemDim</i> Chapter 18 provides…` is one element carrying
    two styles. Reading the element's first tag — or any per-element
    shortcut — attributes the whole run to whichever style happened to open
    it. #825 calls this out as the one parsing trap in the approach.
    """
    segments, bold, italic = [], False, False
    for token in _STYLE_TOKEN.split(inner):
        if token in ("<b>", "</b>", "<i>", "</i>"):
            closing = token[1] == "/"
            if token[-2] == "b":
                bold = not closing
            else:
                italic = not closing
        elif token and not token.startswith("<"):
            segments.append((html.unescape(token), bold, italic))
    return segments


def pdf_words(pdf_path, xml=None):
    """The PDF's words, each with the emphasis its own font carries.

    `xml` lets a caller supply `pdftohtml -xml` output directly, which is what
    the tests do — the source PDFs are gitignored and local-only (#734), so
    nothing in CI can run poppler over a real one.
    """
    if xml is None:
        xml = subprocess.run(
            ["pdftohtml", "-xml", "-i", "-q", "-stdout", pdf_path],
            capture_output=True, text=True, errors="replace").stdout

    specs = {m[1]: (int(m[2]), m[3], m[4]) for m in _FONTSPEC.finditer(xml)}
    chars = []          # (char, bold, italic, page, font-id)
    size_chars = collections.Counter()

    for page in _PAGE.finditer(xml):
        page_no = int(page[1])
        previous = None
        for element in _TEXT.finditer(page[0]):
            top, left, width = int(element[1]), int(element[2]), int(element[3])
            font_id, inner = element[4], element[5]
            segments = _styled_segments(inner)
            text = "".join(t for t, _, _ in segments)
            if font_id in specs:
                size_chars[specs[font_id][0]] += len(text)
            if previous is not None:
                previous_top, previous_right = previous
                if abs(top - previous_top) > 4:
                    # A line break. Join end-of-line hyphenation rather than
                    # letting "compari- son" become two words that align
                    # against nothing — the same normalisation #740 made on
                    # the similarity side.
                    trailing = len(chars)
                    while trailing and chars[trailing - 1][0].isspace():
                        trailing -= 1
                    if (trailing and chars[trailing - 1][0] == "-"
                            and text.lstrip()[:1].islower()):
                        del chars[trailing - 1:]
                    else:
                        chars.append((" ", False, False, page_no, font_id))
                elif left - previous_right > 2:
                    chars.append((" ", False, False, page_no, font_id))
            for segment_text, bold, italic in segments:
                for character in segment_text:
                    chars.append((character, bold, italic, page_no, font_id))
            previous = (top, left + width)
        chars.append((" ", False, False, page_no, None))

    body_size = size_chars.most_common(1)[0][0] if size_chars else 0
    words, current = [], []

    def flush():
        if not current:
            return
        raw = "".join(c[0] for c in current)
        folded, styles = profile((c[0], c[1], c[2]) for c in current)
        if folded:
            font_id = collections.Counter(
                c[4] for c in current).most_common(1)[0][0]
            size, _family, colour = specs.get(font_id, (body_size, "", "#000000"))
            words.append(dict(
                n=folded, raw=raw, styles=styles, page=current[0][3],
                font=font_id, size=size,
                # Informational only — colour never creates a finding.
                coloured=colour.lower() not in ("#000000", "#000"),
                large=size > body_size + 1,
            ))
        current.clear()

    for character in chars:
        if SPLIT.fullmatch(character[0]):
            flush()
        else:
            current.append(character)
    flush()
    return words


# ── QMD side ───────────────────────────────────────────────────────────────

_OJS_FENCE = re.compile(r"^```\{[^}]*\}", re.M)
_RAW_EMPHASIS = re.compile(r"<(/?)(em|i|strong|b)\b[^>]*>", re.I)


def pandoc_ast(markdown):
    """Parse markdown to a pandoc JSON AST via the pandoc Quarto ships.

    ```{ojs}``` and other Quarto fences are not valid pandoc attribute syntax,
    so pandoc reads the code inside them as prose and its words enter the
    stream. Rewriting the fence to a plain one makes pandoc treat it as the
    code block it is.
    """
    source = _OJS_FENCE.sub("```", markdown)
    proc = subprocess.run(
        ["quarto", "pandoc", "-f", "markdown", "-t", "json"],
        input=source, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"pandoc failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


class WordStream:
    """Assembles .qmd characters into whitespace-delimited words.

    Per character rather than per AST node, because a word can span several
    inline nodes and only an explicit `Space` (or `SoftBreak`, or the end of
    a block) ends one: pandoc hands `*two*-minute` over as an `Emph` and a
    `Str`, with nothing between them. Emitting per node — which this module
    did until #850 — cut the site's word in two while the PDF side kept it
    whole, so the site's *correct* markup was what broke the alignment.

    A word's emphasis is the profile of the characters that built it, and its
    context is every context they were in, in the order first seen. The
    common case, a word wholly inside one node, gives exactly the single
    node's context, so the contiguity test in group_runs is unaffected.
    """

    def __init__(self):
        self.words = []
        self._chars = []
        self._ctx = []
        self._file = None

    def text(self, text, state, chapter):
        for character in text:
            if SPLIT.fullmatch(character):
                self.gap()
                continue
            self._chars.append((character, state["bold"], state["italic"]))
            for item in state["ctx"]:
                if item not in self._ctx:
                    self._ctx.append(item)
            self._file = chapter

    def gap(self):
        """End the word in progress, if there is one.

        Called for whitespace, and at every boundary a word cannot cross: the
        end of a block, of a table cell, of a footnote, of a file.
        """
        if self._chars:
            folded, styles = profile(self._chars)
            if folded:
                self.words.append(dict(
                    n=folded, raw="".join(c[0] for c in self._chars),
                    styles=styles, ctx=tuple(self._ctx), file=self._file))
        self._chars, self._ctx = [], []


def _push(state, **changes):
    updated = dict(state)
    if "ctx" in changes:
        changes["ctx"] = state["ctx"] + tuple(changes["ctx"])
    updated.update(changes)
    return updated


def walk_inlines(inlines, state, out, chapter):
    state = dict(state)
    for node in inlines:
        kind, content = node["t"], node.get("c")
        if kind == "Str":
            out.text(content, state, chapter)
        elif kind in ("Space", "SoftBreak", "LineBreak"):
            out.gap()
        elif kind == "Strong":
            walk_inlines(content, _push(state, bold=True), out, chapter)
        elif kind == "Emph":
            walk_inlines(content, _push(state, italic=True), out, chapter)
        elif kind in ("Underline", "Strikeout", "Superscript", "Subscript",
                      "SmallCaps"):
            walk_inlines(content, state, out, chapter)
        elif kind in ("Quoted", "Cite"):
            walk_inlines(content[1], state, out, chapter)
        elif kind == "Link":
            walk_inlines(content[1], _push(state, ctx=["link"]), out, chapter)
        elif kind == "Image":
            # Alt text is not part of the sentence around the image.
            out.gap()
            walk_inlines(content[1], _push(state, ctx=["image"]), out, chapter)
            out.gap()
        elif kind == "Span":
            walk_inlines(content[1],
                         _push(state, ctx=list(content[0][1]) or ["span"]),
                         out, chapter)
        elif kind == "Code":
            out.text(content[1], _push(state, ctx=["code"]), chapter)
        elif kind == "Note":
            # A footnote's prose is not continuous with the word it hangs off.
            out.gap()
            walk_blocks(content, _push(state, ctx=["note"]), out, chapter)
            out.gap()
        elif kind == "RawInline":
            # Days 11 and others set emphasis with literal HTML, which pandoc
            # keeps as a raw inline rather than Strong/Emph. Track it, or
            # every word inside reads as plain and flags as lost.
            #
            # This mutates the local copy made above, so it carries to later
            # siblings in the same inline list — which is the whole point,
            # since `<em>` and `</em>` are separate nodes. An *unclosed* tag
            # therefore bleeds to the end of the inline list, and no further:
            # walk_blocks hands each block the caller's state and walk_inlines
            # copies it, so a paragraph is the blast radius. The corpus is
            # balanced today (76 `<em>`/76 `</em>`, 17 `<strong>`/17
            # `</strong>`), and test_an_unclosed_raw_tag_does_not_bleed_past_
            # its_paragraph pins the containment so a future refactor that
            # shared state between blocks would fail rather than quietly
            # italicise the rest of a chapter.
            tag = _RAW_EMPHASIS.fullmatch(content[1].strip())
            if tag:
                key = "italic" if tag[2].lower() in ("em", "i") else "bold"
                state[key] = not tag[1]
        elif kind == "Math":
            out.text(content[1], _push(state, ctx=["math"]), chapter)
        # RawInline that is not emphasis contributes no words.


def walk_blocks(blocks, state, out, chapter):
    """Walk block nodes, ending the word in progress at every block boundary.

    The trailing `out.gap()` is what keeps a word from spanning two blocks —
    and it is also why `out.words` is complete as soon as this returns, with
    nothing left buffered.
    """
    for node in blocks:
        kind, content = node["t"], node.get("c")
        if kind in ("Para", "Plain"):
            walk_inlines(content, state, out, chapter)
        elif kind == "Header":
            walk_inlines(content[2], _push(state, ctx=["header"]), out, chapter)
        elif kind == "Div":
            walk_blocks(content[1],
                        _push(state, ctx=list(content[0][1]) or ["div"]),
                        out, chapter)
        elif kind == "BlockQuote":
            walk_blocks(content, _push(state, ctx=["blockquote"]), out, chapter)
        elif kind == "BulletList":
            for item in content:
                walk_blocks(item, _push(state, ctx=["list"]), out, chapter)
        elif kind == "OrderedList":
            for item in content[1]:
                walk_blocks(item, _push(state, ctx=["list"]), out, chapter)
        elif kind == "LineBlock":
            for line in content:
                walk_inlines(line, state, out, chapter)
                out.gap()
        elif kind == "Table":
            _walk_table(content, _push(state, ctx=["table"]), out, chapter)
        elif kind == "Figure":
            walk_blocks(content[2], state, out, chapter)
        # CodeBlock, RawBlock and HorizontalRule carry no prose.
        out.gap()


def _walk_table(content, state, out, chapter):
    """Walk a pandoc Table: [attr, caption, colspecs, head, bodies, foot].

    Header cells are marked `th` rather than merged with body cells, because
    the site renders them bold and a "lost" run inside one is that rendering,
    not a defect.
    """
    for row in content[3][1]:
        for cell in row[1]:
            walk_blocks(cell[4], _push(state, ctx=["th"]), out, chapter)
    for body in content[4]:
        for row in body[2] + body[3]:
            for cell in row[1]:
                walk_blocks(cell[4], state, out, chapter)


def _read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def qmd_words(paths, read=None):
    """The site's words, each with the emphasis its markup gives it."""
    reader = read or _read_text
    stream = WordStream()
    base = dict(bold=False, italic=False, ctx=())
    for path in paths:
        ast = pandoc_ast(reader(path))
        walk_blocks(ast["blocks"], base, stream, os.path.basename(path))
        stream.gap()
    return stream.words


# ── Compare ────────────────────────────────────────────────────────────────


def align(pdf_stream, qmd_stream):
    """Pair up words that appear in both streams, in order.

    `difflib.SequenceMatcher` over the folded forms, with autojunk off: at
    corpus scale the popular-element heuristic would discard exactly the
    common words that hold the alignment together. 92% of PDF words align
    corpus-wide; the rest is figure labels, tables rebuilt as images,
    reflowed lists and genuinely differing text, and emphasis in it is not
    checked — see the blind spots in docs/emphasis-detection-spike.md.
    """
    matcher = difflib.SequenceMatcher(
        None, [w["n"] for w in pdf_stream], [w["n"] for w in qmd_stream],
        autojunk=False)
    pairs = []
    for pdf_start, qmd_start, size in matcher.get_matching_blocks():
        for offset in range(size):
            pairs.append((pdf_start + offset, qmd_start + offset))
    return pairs


def _disagreement(pdf_word, qmd_word):
    """How one aligned word's emphasis differs between the two sides.

    The two profiles are the same length, because the words aligned at all
    only by having equal folded forms and a profile carries one style per
    letter of that form — so they compare position by position.

    Only the positions that disagree decide the kind, which is what lets a
    partial emphasis be reported for the letters it covers: `outcome` bold
    inside `outcomes,` disagrees on seven of eight letters, all of them bold
    against plain, and is `lost`. Where the disagreeing letters are
    emphasised on both sides — bold here, italic there — it is `swapped`, the
    same three-way split as before, and a word whose profiles match exactly
    is no finding at all.

    Returns (kind, pdf styles, qmd styles, span) over the disagreeing letters,
    or None where the two sides agree.
    """
    pdf_styles, qmd_styles = pdf_word["styles"], qmd_word["styles"]
    at = [i for i, (p, q) in enumerate(zip(pdf_styles, qmd_styles)) if p != q]
    if not at:
        return None
    pdf_at = {pdf_styles[i] for i in at}
    qmd_at = {qmd_styles[i] for i in at}
    pdf_emphasised = any(bold or italic for bold, italic in pdf_at)
    qmd_emphasised = any(bold or italic for bold, italic in qmd_at)
    if pdf_emphasised and not qmd_emphasised:
        kind = "lost"
    elif qmd_emphasised and not pdf_emphasised:
        kind = "added"
    else:
        kind = "swapped"
    return kind, pdf_at, qmd_at, (at[0], at[-1] + 1)


def group_runs(pairs, pdf_stream, qmd_stream):
    """Collapse consecutive disagreeing words of the same kind into one run.

    Emphasis is set on phrases, not words: reporting `in` and `America`
    separately would double-count one lost italic and read as two defects.
    """
    runs, current = [], None
    for pdf_index, qmd_index in pairs:
        difference = _disagreement(pdf_stream[pdf_index], qmd_stream[qmd_index])
        kind = difference[0] if difference else None
        contiguous = (current is not None
                      and current["kind"] == kind
                      and pdf_index == current["pdf"][-1] + 1
                      and qmd_index == current["qmd"][-1] + 1
                      # Same context, or a run that ends a paragraph merges
                      # with the heading after it and is then explained away
                      # by `header` — an allowlist rule reaching text it was
                      # never meant to cover.
                      and qmd_stream[qmd_index]["ctx"]
                      == qmd_stream[current["qmd"][-1]]["ctx"])
        if kind and contiguous:
            current["pdf"].append(pdf_index)
            current["qmd"].append(qmd_index)
            current["differences"].append(difference)
        elif kind:
            current = dict(kind=kind, pdf=[pdf_index], qmd=[qmd_index],
                           differences=[difference])
            runs.append(current)
        else:
            current = None
    return runs


def explain(kind, pdf_words_in_run, qmd_words_in_run):
    """Why this run is the site rendering Neave correctly, not a defect.

    Returns a list of reasons; empty means the run is a candidate finding.
    Each reason is a short stable token so a report can be grouped by it and
    a reader can tell which rule spoke.
    """
    contexts = set(c for w in qmd_words_in_run for c in w["ctx"])
    reasons = []

    # ── Rules that hold whichever way the disagreement runs ──

    # MathJax italicises `$n$` without the .qmd saying so, and Neave's source
    # sets the same variable in an italic font. Either direction is the two
    # renderers agreeing.
    if MATH_CONTEXT in contexts:
        reasons.append("math")

    styled = contexts & STYLED_CLASSES
    if styled:
        reasons.append("css:" + ",".join(sorted(styled)))

    # Neave's long asides are italic in the source and carried by the
    # `neave_note` class on the site. That one fact surfaces as `lost` where
    # the source aside is in an italic font and as `added` where it is in
    # Comic Sans, whose slant is a text-matrix skew poppler reports as upright
    # (blind spot 1 in docs/emphasis-detection-spike.md). The word floor keeps
    # short emphasis *inside* an aside reportable.
    if (NEAVE_NOTE_CLASS in contexts
            and len(qmd_words_in_run) >= NEAVE_NOTE_MIN_WORDS):
        reasons.append("neave-note-aside")

    if all(PAGE_FURNITURE.fullmatch(w["raw"].strip()) for w in pdf_words_in_run):
        reasons.append("page-furniture")

    # ── Rules that depend on which side added the emphasis ──

    if kind in ("lost", "swapped"):
        if "header" in contexts:
            reasons.append("header")
        if "th" in contexts:
            reasons.append("table-header")

    if kind == "added":
        # The site's own `**POINT 7.**` / `**DISEASE 3.**` scaffolding in the
        # Activity 10A/10B/11A/11B lists, which Neave's running text has no
        # counterpart for.
        if all(CHECKLIST_LABEL.fullmatch(w["raw"].strip(".,:;()"))
               for w in qmd_words_in_run):
            reasons.append("checklist-label")
        # Deming's quotations: blue and upright in Neave's source, italic on
        # the site. This is the one place colour is consulted, and note the
        # direction — it can only ever *suppress* an `added` finding. Colour
        # never creates a finding and never explains a `lost` one; colour-only
        # emphasis stays a human-auditor blind spot. See the module docstring.
        if any(w["coloured"] for w in pdf_words_in_run):
            reasons.append("deming-quote-colour")

    return reasons


def _style_label(styles):
    """`b`, `i`, `bi` or `-` for the styles one side carries on the letters a
    run disagrees about — not on the whole word, which for a partial emphasis
    would report the half that is not the finding."""
    labels = {("b" if bold else "") + ("i" if italic else "")
              for bold, italic in styles}
    return "".join(sorted(s for s in labels if s)) or "-"


# Guillemets rather than brackets: 59 of the corpus's finding texts contain a
# square bracket of Neave's own — `[law-]suits`, `[my italics]` — and `[[law]-]`
# is not something a reader should have to parse. No finding text anywhere in
# the corpus contains « or ».
MARK_OPEN, MARK_CLOSE = "\u00ab", "\u00bb"


def _mark(word, span):
    """`word`'s raw text with the letters the run disagrees about marked.

    `outcomes,` where only `outcome` is bold reads `«outcome»s,`. Once
    emphasis is a profile rather than a flag the word alone no longer says
    which part of it is the finding, and that is exactly what an adjudicator
    has to go and find on the page.

    A word that disagrees end to end — every finding before #850, and still
    most of them — is returned unmarked, so the marks appear only where they
    carry information.
    """
    low, high = span
    if (low, high) == (0, len(word["n"])):
        return word["raw"]
    out, position = [], 0
    for character in word["raw"]:
        letters = _fold(character)
        if letters and position == low:
            out.append(MARK_OPEN)
        out.append(character)
        position += len(letters)
        if letters and position == high:
            out.append(MARK_CLOSE)
    return "".join(out)


def compare(record, pdf_stream=None, qmd_stream=None):
    """Run the whole comparison for one record.

    Returns (stats, findings). `findings` holds every run, explained or not,
    so a report can show its own workings; `stats` counts only the
    unexplained ones, which are what a fix pass would work.
    """
    if pdf_stream is None:
        pdf_stream = pdf_words(record.pdf_path)
    if qmd_stream is None:
        qmd_stream = qmd_words(record.qmd_paths)

    pairs = align(pdf_stream, qmd_stream)
    findings = []
    for run in group_runs(pairs, pdf_stream, qmd_stream):
        pdf_run = [pdf_stream[i] for i in run["pdf"]]
        qmd_run = [qmd_stream[i] for i in run["qmd"]]
        reasons = explain(run["kind"], pdf_run, qmd_run)
        low = max(0, run["qmd"][0] - 8)
        high = min(run["qmd"][-1] + 9, len(qmd_stream))
        snippet = " ".join(
            ("[" if i == run["qmd"][0] else "") + qmd_stream[i]["raw"]
            + ("]" if i == run["qmd"][-1] else "")
            for i in range(low, high))
        differences = run["differences"]
        spans = [d[3] for d in differences]
        # A run nobody has to read letter by letter: every word disagrees
        # end to end, which is what every finding looked like before #850.
        partial = any(span != (0, len(word["n"]))
                      for span, word in zip(spans, pdf_run))
        findings.append(dict(
            kind=run["kind"],
            words=len(pdf_run),
            text=" ".join(w["raw"] for w in pdf_run),
            # The same text with the disagreeing letters marked. Equal to
            # `text` unless `partial`, and the only place a sub-word finding
            # says which part of the word it is about.
            marked=" ".join(_mark(w, span)
                            for w, span in zip(pdf_run, spans)),
            partial=partial,
            pdf_style=_style_label(set().union(*(d[1] for d in differences))),
            qmd_style=_style_label(set().union(*(d[2] for d in differences))),
            page=pdf_run[0]["page"],
            file=qmd_run[0]["file"],
            ctx=sorted(set(c for w in qmd_run for c in w["ctx"])),
            explained=reasons,
            # Informational: colour, size and extent are never why a run is
            # reported, but they help a human triage one that already is.
            notes=(["pdf-coloured"] if any(w["coloured"] for w in pdf_run) else [])
                  + (["pdf-large"] if any(w["large"] for w in pdf_run) else [])
                  + (["partial-word"] if partial else []),
            snippet=snippet,
        ))

    open_findings = [f for f in findings if not f["explained"]]
    stats = dict(
        pdf_words=len(pdf_stream),
        qmd_words=len(qmd_stream),
        aligned=len(pairs),
        runs_total=len(findings),
        runs_explained=len(findings) - len(open_findings),
    )
    for kind in ("lost", "added", "swapped"):
        of_kind = [f for f in open_findings if f["kind"] == kind]
        stats[kind] = len(of_kind)
        stats[f"{kind}_words"] = sum(f["words"] for f in of_kind)
    return stats, findings
