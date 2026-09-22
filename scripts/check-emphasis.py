#!/usr/bin/env python3
"""check-emphasis.py — report emphasis the source PDFs carry and the site lost.

    ./scripts/check-emphasis.py 5                 one day
    ./scripts/check-emphasis.py appendix-main     one named manifest
    ./scripts/check-emphasis.py --all             every record
    ./scripts/check-emphasis.py 5 --json out.json the findings, machine-readable
    ./scripts/check-emphasis.py 5 --quiet         counts only, no per-run lines
    ./scripts/check-emphasis.py --all --no-record don't write to emphasis/

The paragraph comparator in scripts/validate-transcription.sh works on
stripped text and cannot see emphasis at all, which is why Wave 2 passes kept
finding lost italics by eye — 29 on Day 9 alone. This closes that gap
mechanically. See scripts/lib/emphasis.py, docs/emphasis-detection-spike.md
and issues #825 and #846.

Every run writes a record to workflow/validation/emphasis/<record>.yml, so the
counts CI reads are written by the tool rather than transcribed by hand. The
records are what makes drift visible: scripts/check-validation-staleness.sh
compares each one's `emphasis_version` against the checker as it exists now,
without needing the PDFs (which are gitignored and local-only — see #734).

Requires: pdftohtml (poppler), quarto, ruby, git. Python stdlib only.
"""
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

import emphasis  # noqa: E402

REPO_ROOT = emphasis.REPO_ROOT
RECORD_DIR = os.path.join(REPO_ROOT, "workflow", "validation", "emphasis")
VERSION_LIB = os.path.join(REPO_ROOT, "scripts", "lib", "emphasis-version.sh")

KINDS = ("lost", "added", "swapped")


def emphasis_version():
    """The checker's content hash, from the one shell definition that the
    staleness check also reads. Shelling out rather than reimplementing the
    hash in Python is the point: two implementations is how #737's drift
    happened in the first place."""
    proc = subprocess.run(
        ["bash", "-c",
         f'set -euo pipefail\n. "{VERSION_LIB}"\ncompute_emphasis_version "{REPO_ROOT}"'],
        capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "could not compute emphasis_version")
    return proc.stdout.strip()


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_record(record, stats, version):
    os.makedirs(RECORD_DIR, exist_ok=True)
    path = os.path.join(RECORD_DIR, f"{record.name}.yml")
    with open(path, "w", encoding="utf-8") as out:
        out.write(f"""\
# Emphasis check for {record.name}. Written by scripts/check-emphasis.py —
# see workflow/validation/emphasis/README.md and issue #846.
record: {record.name}
checked_at: {datetime.date.today().isoformat()}
source_pdf: {os.path.basename(record.pdf_path)}
source_sha256: {sha256_of(record.pdf_path)}
emphasis_version: {version}
files:
  compared: {len(record.chapters)}
words:
  pdf: {stats['pdf_words']}
  qmd: {stats['qmd_words']}
  aligned: {stats['aligned']}
runs:
  total: {stats['runs_total']}
  explained: {stats['runs_explained']}
counts:
  lost: {stats['lost']}
  lost_words: {stats['lost_words']}
  added: {stats['added']}
  added_words: {stats['added_words']}
  swapped: {stats['swapped']}
  swapped_words: {stats['swapped_words']}
""")
    return path


def print_report(name, stats, findings, quiet):
    aligned_pct = (100 * stats["aligned"] / stats["pdf_words"]
                   if stats["pdf_words"] else 0)
    print(f"\n=== {name} ===")
    print(f"  {stats['pdf_words']} PDF words, {stats['qmd_words']} site words, "
          f"{stats['aligned']} aligned ({aligned_pct:.0f}%)")
    print(f"  {stats['runs_total']} disagreeing runs, "
          f"{stats['runs_explained']} explained by site convention")
    for kind in KINDS:
        print(f"  {kind:<8} {stats[kind]:>4} runs  "
              f"({stats[kind + '_words']} words)")
    if quiet:
        return
    for kind in KINDS:
        open_runs = [f for f in findings
                     if f["kind"] == kind and not f["explained"]]
        if not open_runs:
            continue
        print(f"\n  -- {kind} --")
        for finding in open_runs:
            notes = ",".join(finding["notes"])
            print(f"  p{finding['page']:>3} {finding['file'][:26]:26} "
                  f"pdf={finding['pdf_style']:<3} qmd={finding['qmd_style']:<3} "
                  f"{notes[:16]:16} | {finding['snippet'][:120]}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Report emphasis present in the source PDFs and lost on the site.")
    parser.add_argument("record", nargs="?",
                        help="a day number (5) or manifest name (appendix-main)")
    parser.add_argument("--all", action="store_true",
                        help="run every day and every named manifest")
    parser.add_argument("--json", metavar="PATH",
                        help="write the full findings, explained ones included")
    parser.add_argument("--quiet", action="store_true",
                        help="counts only, without the per-run lines")
    parser.add_argument("--no-record", action="store_true",
                        help="skip writing workflow/validation/emphasis/")
    args = parser.parse_args(argv)

    if bool(args.record) == bool(args.all):
        parser.error("give exactly one record, or --all")

    names = emphasis.all_records() if args.all else [args.record]
    version = emphasis_version()
    everything, totals = {}, dict.fromkeys(
        ["pdf_words", "qmd_words", "aligned", "runs_total", "runs_explained"]
        + [k for kind in KINDS for k in (kind, kind + "_words")], 0)

    for name in names:
        try:
            record = emphasis.resolve(name)
        except emphasis.RecordError as error:
            print(f"Error: {error}", file=sys.stderr)
            return 1
        stats, findings = emphasis.compare(record)
        print_report(record.name, stats, findings, args.quiet)
        for key in totals:
            totals[key] += stats[key]
        everything[record.name] = dict(stats=stats, findings=findings)
        if not args.no_record:
            written = write_record(record, stats, version)
            print(f"  recorded: {os.path.relpath(written, REPO_ROOT)}")

    if len(names) > 1:
        print(f"\n=== all {len(names)} records ===")
        for kind in KINDS:
            print(f"  {kind:<8} {totals[kind]:>4} runs  "
                  f"({totals[kind + '_words']} words)")
        print(f"  {totals['runs_explained']} of {totals['runs_total']} runs "
              "explained by site convention")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as out:
            json.dump(dict(emphasis_version=version, records=everything),
                      out, indent=1)
        print(f"\nFindings written to {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
