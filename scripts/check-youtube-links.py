#!/usr/bin/env python3
"""check-youtube-links.py — find dead YouTube links, which lychee cannot.

    ./scripts/check-youtube-links.py                       check, print report
    ./scripts/check-youtube-links.py --output report.md    also write it to a file

YouTube answers HTTP 200 for a video or playlist that does not exist: it
renders a "This video isn't available" page instead of a 404. So the weekly
lychee run in .github/workflows/link-check.yml, which reads status codes, sees
a dead YouTube link as healthy and always has (#805). Two mistranscribed IDs
on the References appendix went unreported that way, both confusable glyphs:
#420's capital I read as an 8, and #804's 3 read as a 0, beneath Neave's own
warning on that page that 0/O and 1/I are easily confused.

YouTube's oEmbed endpoint does tell them apart: 200 with the title for a live
video or playlist, 404 for one that does not exist, 400 for an ID that is not
even well formed. This script sends every YouTube URL in the corpus through it.

Scope matches lychee's: content/**/*.qmd plus the root-level *.qmd pages.

Exit status: 0 when every link resolves, 1 when any is dead. A link oEmbed
could not settle (rate-limited, private, network error) is listed as
unverified but does not fail the run, the same way link-check.yml accepts
lychee's 403 and 429.

Python stdlib only.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

OEMBED = "https://www.youtube.com/oembed?format=json&url="
USER_AGENT = "twelve-days-to-deming link check"

# A whole URL token. Markdown ends it at ")" and autolinks at ">"; trailing
# sentence punctuation is stripped afterwards.
URL_RE = re.compile(
    r"""https?://(?:www\.|m\.)?(?:youtube\.com|youtu\.be)/[^\s)\]>"'<`]+"""
)

DEAD_STATUSES = {400, 404}


def corpus_files(root=REPO_ROOT):
    """The .qmd files lychee scans: content/ recursively, plus the root."""
    return sorted(root.glob("content/**/*.qmd")) + sorted(root.glob("*.qmd"))


def canonical(url):
    """The URL oEmbed should be asked about, or None if it isn't checkable.

    Only the three forms that name one video or playlist are checkable: a
    youtube.com watch?v= or playlist?list= URL, and a youtu.be/ short link.
    Extra parameters (a start time, a playlist alongside a video) are dropped,
    because what can be dead is the ID itself.
    """
    parts = urllib.parse.urlsplit(url)
    host = parts.netloc.lower()
    query = urllib.parse.parse_qs(parts.query)
    if host == "youtu.be":
        video = parts.path.strip("/")
        if video:
            return f"https://www.youtube.com/watch?v={video}"
        return None
    if parts.path == "/watch" and query.get("v"):
        return f"https://www.youtube.com/watch?v={query['v'][0]}"
    if parts.path == "/playlist" and query.get("list"):
        return f"https://www.youtube.com/playlist?list={query['list'][0]}"
    return None


def find_links(files, root=REPO_ROOT):
    """{canonical URL: [(written URL, "path:line"), ...]} across the corpus."""
    found = {}
    for path in files:
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for match in URL_RE.finditer(line):
                written = match.group(0).rstrip(".,;:!?")
                target = canonical(written)
                if target is not None:
                    found.setdefault(target, []).append((written, f"{rel}:{lineno}"))
    return found


def fetch_oembed(url, timeout=20):
    """(HTTP status, parsed JSON or None). Status None means no response."""
    request = urllib.request.Request(
        OEMBED + urllib.parse.quote(url, safe=""),
        headers={"User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as err:
        return err.code, None
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None, None


def classify(status, body):
    """'live', 'dead' or 'unverified', and a note for the report."""
    if status == 200 and body:
        return "live", body.get("title", "(no title)")
    if status in DEAD_STATUSES:
        return "dead", f"oEmbed {status}: no such video or playlist"
    if status is None:
        return "unverified", "no response from oEmbed"
    return "unverified", f"oEmbed {status}"


def check(links, fetch=None):
    """One result row per canonical URL, in a stable order."""
    fetch = fetch or fetch_oembed
    rows = []
    for target in sorted(links):
        verdict, note = classify(*fetch(target))
        rows.append({"url": target, "verdict": verdict, "note": note, "sites": links[target]})
    return rows


def report(rows):
    """Markdown, dead links first, then unverified, then live with titles."""
    order = {"dead": 0, "unverified": 1, "live": 2}
    counts = {v: sum(r["verdict"] == v for r in rows) for v in order}
    lines = [
        "## YouTube links (oEmbed)",
        "",
        f"{len(rows)} checked: {counts['dead']} dead, "
        f"{counts['unverified']} unverified, {counts['live']} live.",
        "",
        "| Status | URL | Title or reason | Linked from |",
        "|---|---|---|---|",
    ]
    for row in sorted(rows, key=lambda r: (order[r["verdict"]], r["url"])):
        sites = "<br>".join(site for _, site in row["sites"])
        note = row["note"].replace("|", "\\|")
        lines.append(f"| {row['verdict']} | {row['url']} | {note} | {sites} |")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--output", help="also write the Markdown report here")
    args = parser.parse_args(argv)

    rows = check(find_links(corpus_files()))
    text = report(rows)
    sys.stdout.write(text)
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    return 1 if any(r["verdict"] == "dead" for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
