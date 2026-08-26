#!/usr/bin/env python3
"""qmd_strip.py — reduce Quarto markup to the prose a source PDF can be
compared against.

Helper for scripts/validate-transcription.sh (#739). This is the QMD half of
the comparison; scripts/lib/paragraph_similarity.py scores what comes out of
it. Anything this module fails to strip survives as a junk token inside an
otherwise-faithful sentence, depresses its similarity score, and shows up as
a flagged "altered" sentence that no amount of proofreading can clear —
because there is nothing wrong with the transcription. Day 9's triage put a
number on that: 55 of 62 residual near-certain flags were markup artifacts
rather than defects (#732).

Until #739 this lived as an untested awk + sed pipeline inside
validate-transcription.sh. It is Python now for one reason above the others:
the constructs it has to take apart nest, and a line-oriented regex cannot
see that. The site wraps Deming's own words in `[...]{.deming_quote}`, and
editorial interpolations inside those quotes get a second, nested `[...]`
layer — so the outer span's closing bracket is not the first `]` on the line.
The old `s/\\[([^]]*)\\]\\{[^}]*\\}//` shape cannot match it by construction,
which is why 138 `.deming_quote` spans leaked class tokens into the compared
text while the `<span>` form of the same markup was stripped cleanly.

What the two sides are expected to agree on, and therefore what gets removed:

  Removed entirely (markup with no counterpart in the printed page)
    - YAML front matter, fenced code/R/OJS blocks, `:::` layout directives
    - HTML tags, and Pandoc attribute blocks like `{#sec-page12}`
    - Images — the printed figure is not text on either side
    - Bare `[]{#sec-pageN}` anchors, the site's own cross-reference scaffolding
    - Footnote reference markers, in both shapes the site uses: `[^a]` and `^[a]^`
    - `[WB NN]` workbook citations — see strip_workbook_refs() below

  Kept, with the markup peeled off (the words are Neave's, the syntax is ours)
    - Bracketed spans: `[text]{.deming_quote}` -> `text`
    - Links: `[text](target)` -> `text`
    - Emphasis, heading markers, blockquote markers

  Kept exactly as they are (they are content, not markup)
    - Plain bracketed text: `[A]`, `[B]`, `pages 154–155[180–181]`, and the
      editorial interpolations nested inside quote spans. Neave brackets all
      of these in the source too, so removing them here would manufacture a
      difference rather than remove one.

One field of the front matter this removes is not metadata at all: `title` is
Neave's section heading, which the site renders as the chapter's h1 instead of
repeating it in the body. front_matter_title() hands it back for the callers
that need the headings — today the short-content pass in
scripts/lib/short_content.py (#742). It stays out of strip_qmd()'s output,
because putting it in would add a paragraph to the QMD side that #741's
assembly would then have to reason about, and would move every recorded
result for a reason unrelated to what this module is for.

Usage: qmd_strip.py <file.qmd> [<file.qmd> ...]
       qmd_strip.py --workbook-refs < text

Prints each file's stripped text to stdout, followed by a blank line, in the
order given. That separator is part of the contract, not incidental: the
caller concatenates every chapter in a day into one text before splitting it
into paragraphs, and without it the last paragraph of one chapter would fuse
with the first paragraph of the next.

`--workbook-refs` applies just strip_workbook_refs() to stdin, and exists so
the PDF side of the comparison can run the same rule the QMD side runs. That
rule is only meaningful as a symmetric one, and a second copy of it written
as a sed line in validate-transcription.sh would be free to drift from this
one — the failure mode #737 was raised to close off.

I/O is explicitly UTF-8 in both directions. The calling script runs under
`LC_ALL=C` (load-bearing there — see the comment beside it), and the course
text is full of en dashes and curly quotes, so neither end of this module can
be left to the ambient locale.
"""

from __future__ import annotations  # `int | None` annotations on Python < 3.10

import re
import sys

# ── Line-level filters, applied before anything else ───────────

_FRONT_MATTER_FENCE = re.compile(r"^---$")
_FRONT_MATTER_TITLE = re.compile(r"^title:\s*(.*)$")
_CODE_FENCE = re.compile(r"^```")
_LAYOUT_DIRECTIVE = re.compile(r"^:{2,}")

# ── Inline rules ───────────────────────────────────────────────

_HTML_TAG = re.compile(r"<[^>]+>")

# `[^a]: text` (definition, keep the text) and `[^a]` (reference, drop it).
# The definitions are approvals and acknowledgements the printed edition
# carries as an end-of-file section, so the prose is kept and only the marker
# goes; the superscript callout in the body has no textual counterpart at all.
#
# The site writes the same callout two ways. Pandoc's own `[^a]` syntax is the
# usual one — 17 occurrences across Days 1 and 6 and the Balaji Reddie appendix
# — but `content/days/day-07/04-many-more-true-stories.qmd` hand-rolls its two
# as `^[a]^`, Pandoc's superscript span around a literal letter, with the
# definition written out as ordinary prose rather than a footnote. Until #755
# only the first form was stripped, and the second was not merely cosmetic:
# line 168 ends `Quoting from a BBC News report:^[a]^`, so paragraphs.py's
# continues() saw a tail of `^` instead of `:` and refused a blockquote join
# that #741 would otherwise have made.
_FOOTNOTE_DEFINITION = re.compile(r"^\[\^[^\]]+\]:\s*")
_FOOTNOTE_REFERENCE = re.compile(r"\[\^[^\]]+\]")
_SUPERSCRIPT_MARKER = re.compile(r"\^\[[^\]]+\]\^")

# `[WB 5]`, `[WB 38–39]`, `[WB 190--191]`, `[WB 105 and 106]`, `[or on WB 123]`
# — every single-line shape the twenty source PDFs actually use, which is 171
# of the 179 citations in them. See strip_workbook_refs().
#
# `[^\S\n]` throughout rather than `\s`, so this can never match across a line
# break. Eight citations do wrap onto a second line and are left alone as a
# result, which is the cheap side of the trade: a pattern that ate newlines
# could fuse two paragraphs across a blank line, and a stray paragraph
# boundary moving is a far more expensive error than eight fragments of
# citation surviving in a report.
#
# That guarantee is made twice over — the pattern excludes newlines AND
# strip_workbook_refs() applies it a line at a time — which is deliberate
# redundancy rather than an oversight. Either half alone holds it today, so
# neither shows up as load-bearing on its own; the point is that whichever
# one a later edit reaches for, the other still stands.
_WORKBOOK_REF = re.compile(
    r"""[^\S\n]*                                   # the space in front of it
        \[
        (?:(?:or|also|on|see)[^\S\n]+){0,2}         # "[or on WB 123]"
        [*_]*WB[*_]*[^\S\n]*                       # "[*WB* 154–165]", the site's form
        \d+(?:[^\S\n]*(?:[–—-]+|and)[^\S\n]*\d+)*  # 38–39, 190--191, 105 and 106
        \]""",
    re.VERBOSE,
)

_BOLD = re.compile(r"\*\*([^*]*)\*\*")
_ITALIC = re.compile(r"\*([^*]*)\*")
_HEADING_MARKER = re.compile(r"^#{1,6} ")
# `^> ` in the sed this replaced, which left a bare `>` — the blank line
# *inside* a blockquote — standing as a non-blank line. Three quoted
# paragraphs then fused into one on the QMD side while the source had them
# separate. The space is optional here so the separator empties out and the
# paragraph break survives.
_BLOCKQUOTE_MARKER = re.compile(r"^> ?")
_HORIZONTAL_RULE = re.compile(r"^(?:---+|\*\*\*+)$")

# A Pandoc attribute block left stranded at the end of a line once the
# bracket pass has consumed every `]{...}` construct — i.e. a heading's own
# id or classes: `## The Deming Prize {#sec-page2}`, `## Notes {.unnumbered}`.
# Anchored to the line end, and to a `{` immediately followed by `#` or `.`,
# so it cannot reach into the CSS that a few chapters carry inline.
_TRAILING_ATTRIBUTES = re.compile(r"\s*\{[#.][^{}]*\}\s*$")

# Link text of the enriched cross-reference form introduced by #610:
# `[page 18, the guidance for the Second Project](...#sec-page18)`. The
# descriptor after the comma is the site's own addition — the source says
# "page 18" and nothing else — so it is four to eight words of unmatched
# prose dropped into a ~30-word sentence, which measured out at 12-20% of the
# sentence's similarity score all by itself.
#
# Deliberately narrow. It fires only when the link text OPENS with the
# reference and the descriptor is appended after a comma, which is the shape
# the convention actually produces. The other common shape weaves the page
# number into the sentence's own words — `[the table on page 4](...)` — and
# there the descriptor is Neave's prose, not ours; canonicalising that one to
# "page 4" would delete source text and manufacture a difference.
_ENRICHED_REFERENCE = re.compile(
    r"""^(
          (?:Day\s+\d+\s+|Appendix\s+)?
          pages?\s+\d+(?:\s*[–—-]\s*\d+)?
        )
        \s*,\s+\S""",
    re.IGNORECASE | re.VERBOSE,
)


def front_matter_title(text: str) -> str | None:
    """The `title:` a .qmd declares in its front matter, or None.

    strip_qmd() deletes front matter wholesale, and rightly — `pagetitle` and
    `description` are the site's own SEO metadata (#497), with no counterpart
    on the printed page. But `title` is different: it is Neave's section
    heading, and the site renders it as the chapter's h1 rather than repeating
    it in the body. So for all 88 chapters the printed heading has no
    comparable text anywhere in the stripped QMD, and the short-content pass
    (#742) would report every one of them as unmatched — "SOME LIGHT RELIEF!"
    is on the site, as the title of `day-01/10-relief.qmd`.

    Read as a line, not as YAML: every title in the corpus is a single
    quoted scalar on one line, and the alternative is a ruby YAML shell-out
    (as the appendix manifests use) for one field. Both quoting styles appear
    — `title: "A SYSTEM ..."` and `title: '"OUT-OF-HOURS" NOTE'` — so the
    outer quotes come off whichever they are, and a title carrying neither is
    taken as it stands. Returns the title only from the front matter block,
    never from a `title:` line appearing later in the body.
    """
    lines = text.split("\n")
    if not lines or not _FRONT_MATTER_FENCE.match(lines[0]):
        return None
    for line in lines[1:]:
        if _FRONT_MATTER_FENCE.match(line):
            return None
        match = _FRONT_MATTER_TITLE.match(line)
        if match:
            value = match.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            return value or None
    return None


def strip_workbook_refs(text: str) -> str:
    """Remove `[WB NN]` print-workbook citations.

    Applied to BOTH sides of the comparison, and it has to be. The source
    PDFs cite the printed workbook throughout; the site mostly drops those
    markers, having no physical workbook to send anyone to (the #195
    decision, Option A) — but not entirely. Seven chapters across Days 10 and
    11 kept them, italicised, as `[*WB* 154–165]`. So the citations are
    PDF-only in most of the corpus and present on both sides in a little of
    it, and stripping only one side would trade one asymmetry for another:
    the days that kept them would start reporting QMD-only numbers exactly
    as the rest of the corpus stopped reporting PDF-only ones.

    Removing them from the PDF side is not only about the four or five words
    each one costs. `[WB 145]` puts a bare `145` into the PDF sentence's
    reference-token multiset with nothing to match it on the site, so every
    one of them was also a standing reference mismatch under #738's check.
    """
    kept = (strip_workbook_refs_line(line) for line in text.split("\n"))
    return "\n".join(line for line in kept if line is not None)


def strip_workbook_refs_line(line: str) -> str | None:
    """`line` without its `[WB NN]` citations, or None if that empties it.

    A caller must drop a None rather than emit a blank line in its place.
    Downstream, a blank line is a paragraph boundary — so a line holding
    nothing but a citation would, once emptied, split the paragraph it sat
    inside into two, and the half that lost its opening would read as
    unmatched content. No line in the current sources is citation-only, so
    this changes nothing today; it is here because the alternative failure is
    silent and would be attributed to the transcription rather than to this.
    """
    stripped = _WORKBOOK_REF.sub("", line)
    if line.strip() and not stripped.strip():
        return None
    return stripped


def _matching(text: str, start: int, open_ch: str, close_ch: str) -> int | None:
    """Index of the delimiter closing the one at `start`, or None if unclosed.

    Depth-counted rather than "the next closing character", which is the whole
    reason this module exists — see the nested `.deming_quote` case in the
    docstring above.
    """
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
    return None


def _canonicalise_link_text(text: str, target: str) -> str:
    """Link text as it should read once the site's own enrichment is peeled off."""
    if "#sec-" not in target:
        return text
    match = _ENRICHED_REFERENCE.match(text)
    return match.group(1) if match else text


def resolve_brackets(text: str) -> str:
    """Rewrite the bracket constructs in one line, innermost first.

    Four shapes, distinguished by what follows the closing `]`:

      `![alt](path){attrs}`  image      -> removed entirely
      `[text](target){attrs}`  link     -> visible text, canonicalised
      `[text]{attrs}`          span     -> visible text
      `[]{#sec-pageN}`         anchor   -> removed entirely
      `[text]`                 content  -> left alone, brackets included
    """
    out: list[str] = []
    i = 0
    while i < len(text):
        char = text[i]
        if char != "[":
            # An image's `!` is only a marker when a bracket construct
            # actually follows it; a bare `!` is punctuation.
            out.append(char)
            i += 1
            continue

        close = _matching(text, i, "[", "]")
        if close is None:
            out.append(char)
            i += 1
            continue

        inner = text[i + 1 : close]
        after = close + 1
        is_image = bool(out) and out[-1] == "!"

        if after < len(text) and text[after] == "(":
            target_close = _matching(text, after, "(", ")")
            if target_close is not None:
                target = text[after + 1 : target_close]
                end = _skip_attributes(text, target_close + 1)
                if is_image:
                    out.pop()  # the `!` we already emitted
                else:
                    out.append(resolve_brackets(_canonicalise_link_text(inner, target)))
                i = end
                continue

        if after < len(text) and text[after] == "{":
            attr_close = _matching(text, after, "{", "}")
            if attr_close is not None:
                # `[]{#sec-page12}` — an anchor, not a span: nothing visible.
                if inner:
                    out.append(resolve_brackets(inner))
                i = attr_close + 1
                continue

        out.append("[" + resolve_brackets(inner) + "]")
        i = close + 1

    return "".join(out)


def _skip_attributes(text: str, start: int) -> int:
    """Index past a `{...}` attribute block at `start`, or `start` if none."""
    if start < len(text) and text[start] == "{":
        close = _matching(text, start, "{", "}")
        if close is not None:
            return close + 1
    return start


def strip_qmd(text: str) -> str:
    """Plain prose for one .qmd file's contents, one output line per kept line.

    Rule order is load-bearing in a couple of places and is a faithful port of
    the awk + sed pipeline this replaced, deliberately including one wart:
    emphasis is stripped before horizontal rules are dropped, so a `***`
    divider has already been eaten down to a single `*` by the italic rule
    before the rule that was meant to delete it ever sees the line. Left as
    it was rather than fixed here, because "port it, then change it" keeps
    the re-recorded results in this change attributable to the new stripping
    rather than to a silent extra edit. A `*` alone on a line is below
    MIN_PARA_LEN anyway, so nothing downstream can see the difference.
    """
    out: list[str] = []
    in_front_matter = False
    in_code = False

    # A file ending in a newline has as many lines as it has newlines, which
    # is how awk read it and how the caller's blank-line separator was sized.
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    for number, line in enumerate(lines, start=1):
        if number == 1 and _FRONT_MATTER_FENCE.match(line):
            in_front_matter = True
            continue
        if in_front_matter:
            in_front_matter = not _FRONT_MATTER_FENCE.match(line)
            continue
        if _CODE_FENCE.match(line):
            in_code = not in_code
            continue
        if in_code or _LAYOUT_DIRECTIVE.match(line):
            continue

        line = _HTML_TAG.sub("", line)
        line = _FOOTNOTE_DEFINITION.sub("", line)
        line = _FOOTNOTE_REFERENCE.sub("", line)
        line = _SUPERSCRIPT_MARKER.sub("", line)
        workbook_stripped = strip_workbook_refs_line(line)
        if workbook_stripped is None:
            continue
        line = resolve_brackets(workbook_stripped)
        line = _TRAILING_ATTRIBUTES.sub("", line)
        line = _BOLD.sub(r"\1", line)
        line = _ITALIC.sub(r"\1", line)
        line = _HEADING_MARKER.sub("", line)
        if _HORIZONTAL_RULE.match(line):
            continue
        line = _BLOCKQUOTE_MARKER.sub("", line)

        out.append(line)

    return "".join(f"{line}\n" for line in out)


def main(argv: list[str]) -> int:
    if not argv:
        print(f"Usage: {sys.argv[0]} <file.qmd> [<file.qmd> ...]", file=sys.stderr)
        print(f"       {sys.argv[0]} --workbook-refs < text", file=sys.stderr)
        return 1

    if argv[0] == "--workbook-refs":
        if len(argv) > 1:
            print("qmd_strip.py: --workbook-refs reads stdin and takes no files", file=sys.stderr)
            return 1
        source = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        sys.stdout.buffer.write(strip_workbook_refs(source).encode("utf-8"))
        return 0

    for path in argv:
        try:
            with open(path, encoding="utf-8") as handle:
                source = handle.read()
        except OSError as error:
            print(f"qmd_strip.py: {error}", file=sys.stderr)
            return 1
        # The blank line after each file is the chapter separator the caller
        # relies on — see the module docstring.
        sys.stdout.buffer.write((strip_qmd(source) + "\n").encode("utf-8"))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
