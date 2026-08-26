#!/usr/bin/env python3
"""Build a Wave 2 adjudication review page from its recorded findings.

A Wave 2 pass of epic #734 ends with a human decision on every flag the
comparator raised for one day or appendix. That decision is Lee's to make
(AGENTS.md: "User will always verify transcription accuracy"), so the pass has
to *present* the evidence rather than act on it — source text, site text, the
proposed replacement, and why the verdict goes the way it does.

This script turns the recorded findings in
`workflow/validation/adjudications/<pass>.json` into that page, using
`workflow/validation/adjudication/template.html` as the shell. The record is
the source of truth and lives in git; the HTML is derived and is not committed.

Two substitutions, deliberately: the page title, and one JSON blob the page's
own script reads. Everything else about the page — palette, decision controls,
filters, export — is pass-independent and lives in the template, so a later
pass changes data and never markup. See issue #765.

Usage:
    python3 scripts/build-adjudication-page.py workflow/validation/adjudications/day-05.json
    python3 scripts/build-adjudication-page.py <record.json> -o /tmp/preview.html
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = REPO_ROOT / "workflow" / "validation" / "adjudication" / "template.html"
DEFAULT_OUT_DIR = REPO_ROOT / "workflow" / "validation" / "adjudication"

VALID_DECISIONS = {"accept", "reject", "discuss", None}

# Keys every record must carry. `page` and `sections` are checked in more
# detail below; the rest are copied into the page verbatim.
REQUIRED_TOP = ("pass", "epic", "source_pdf", "scorer_version", "content_dir",
                "export_filename", "page", "sections")
REQUIRED_ITEM = ("id", "chip", "page", "flag", "source_html", "site_html", "evidence_html")


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def validate(record):
    """Reject a record that would build a page with holes in it.

    Everything here is a mistake that produces a *plausible-looking* page
    rather than a crash — a missing evidence line reads as an oversight, and a
    duplicated id silently makes two findings share one decision.
    """
    for key in REQUIRED_TOP:
        if key not in record:
            fail(f"record is missing required key: {key}")

    page = record["page"]
    for key in ("eyebrow", "title", "standfirst_html", "provenance"):
        if key not in page:
            fail(f"record['page'] is missing required key: {key}")

    if not record["sections"]:
        fail("record has no sections")

    seen = {}
    for section in record["sections"]:
        for key in ("key", "kind", "title", "count", "note_html", "labels", "items"):
            if key not in section:
                fail(f"section is missing required key: {key}")
        for verdict in ("accept", "reject", "discuss"):
            if verdict not in section["labels"]:
                fail(f"section '{section['key']}' has no label for '{verdict}'")

        for item in section["items"]:
            for key in REQUIRED_ITEM:
                if key not in item:
                    fail(f"item {item.get('id', '?')} is missing required key: {key}")
            if item["id"] in seen:
                fail(f"duplicate finding id {item['id']} "
                     f"(in sections '{seen[item['id']]}' and '{section['key']}')")
            seen[item["id"]] = section["key"]
            if item.get("decision") not in VALID_DECISIONS:
                fail(f"item {item['id']} has an unrecognised decision: {item['decision']!r}")
            # A finding that names a file must name a line in it, or the
            # location line renders as `file:None`.
            if item.get("file") and not item.get("line"):
                fail(f"item {item['id']} names a file but no line")

    return len(seen)


def build(record_path, out_path):
    record = json.loads(record_path.read_text(encoding="utf-8"))
    count = validate(record)

    template = TEMPLATE.read_text(encoding="utf-8")
    for marker in ("__TITLE__", "__PASS_JSON__"):
        if marker not in template:
            fail(f"template has no {marker} marker: {TEMPLATE}")

    title = record["page"].get("artifact_title") or record["page"]["title"]
    html = template.replace("__TITLE__", title)
    # json.dumps escapes nothing that can close the surrounding <script>, with
    # one exception worth being explicit about: a literal "</script>" inside a
    # findings string would end the block early.
    blob = json.dumps(record, ensure_ascii=False).replace("</", "<\\/")
    html = html.replace("__PASS_JSON__", blob)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")

    decided = sum(1 for s in record["sections"] for i in s["items"] if i.get("decision"))
    print(f"{record['pass']}: {count} findings ({decided} already decided) -> {out_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("record", type=Path,
                        help="path to workflow/validation/adjudications/<pass>.json")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="where to write the page (default: alongside the template)")
    args = parser.parse_args()

    if not args.record.exists():
        fail(f"no such record: {args.record}")
    if not TEMPLATE.exists():
        fail(f"no such template: {TEMPLATE}")

    out = args.output or DEFAULT_OUT_DIR / (args.record.stem + ".html")
    build(args.record, out)


if __name__ == "__main__":
    main()
