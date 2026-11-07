#!/usr/bin/env python3
"""Fail when .well-known/security.txt is close to expiring (#919).

RFC 9116 makes `Expires:` required, and a researcher's tooling treats a file
past its `Expires` as stale, so an expired security.txt is worse than none: it
tells the reader the contact details may no longer be trusted. Nothing about
the site's normal life touches the file, so without this check it would expire
silently. release-cadence.yml runs it weekly.

It fails when:
  - the file lacks a `Contact:` line, or has anything but exactly one
    `Expires:` line (both are required by RFC 9116 §2.5);
  - `Expires` is within WARN_DAYS of now, or already past;
  - `Expires` is more than a year away. RFC 9116 §2.5.5 recommends less than a
    year, and capping it is what keeps a refresh from being "set it to 2099".

To refresh: set `Expires` to a date under a year from today, in the
`YYYY-MM-DDThh:mm:ss.000Z` form already in the file, and merge it.

Usage:
  python3 scripts/check-security-txt.py [--file PATH] [--now ISO-DATETIME]

`--now` exists so the check can be shown to fail without waiting a year.
"""
from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FILE = REPO_ROOT / ".well-known" / "security.txt"
WARN_DAYS = 30
MAX_DAYS = 366


def parse_fields(text: str) -> dict[str, list[str]]:
    """Field name (lower-cased, as RFC 9116 names are case-insensitive) to values."""
    fields: dict[str, list[str]] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        name, value = line.split(":", 1)
        fields.setdefault(name.strip().lower(), []).append(value.strip())
    return fields


def parse_datetime(value: str) -> datetime:
    """An RFC 3339 timestamp, as RFC 9116 requires for `Expires`."""
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError(f"{value!r} has no timezone")
    return parsed


def check(text: str, now: datetime) -> list[str]:
    """Every problem with the file, or an empty list when it's fine."""
    fields = parse_fields(text)
    problems = []

    if not fields.get("contact"):
        problems.append("no Contact: line")

    expires_values = fields.get("expires", [])
    if len(expires_values) != 1:
        problems.append(f"expected exactly one Expires: line, found {len(expires_values)}")
        return problems

    try:
        expires = parse_datetime(expires_values[0])
    except ValueError as err:
        problems.append(f"Expires is not an RFC 3339 timestamp: {err}")
        return problems

    remaining = expires - now
    if remaining <= timedelta(0):
        problems.append(f"Expires ({expires_values[0]}) has passed")
    elif remaining < timedelta(days=WARN_DAYS):
        problems.append(
            f"Expires ({expires_values[0]}) is {remaining.days} day(s) away, "
            f"inside the {WARN_DAYS}-day refresh window"
        )
    elif remaining > timedelta(days=MAX_DAYS):
        problems.append(
            f"Expires ({expires_values[0]}) is more than a year away; "
            "RFC 9116 recommends less than a year"
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", type=Path, default=DEFAULT_FILE)
    parser.add_argument("--now", type=parse_datetime, default=None)
    args = parser.parse_args(argv)

    now = args.now or datetime.now(timezone.utc)
    problems = check(args.file.read_text(encoding="utf-8"), now)
    if problems:
        print(f"FAIL: {args.file}")
        for problem in problems:
            print(f"  - {problem}")
        print("Refresh Expires to a date under a year away (see this script's docstring).")
        return 1
    print(f"OK: {args.file} is valid and not near expiry.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
