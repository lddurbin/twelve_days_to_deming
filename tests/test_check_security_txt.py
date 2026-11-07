"""Tests for scripts/check-security-txt.py — security.txt's expiry check (#919).

An expired security.txt is worse than none, and nothing about the site's normal
life touches the file, so these pin the check that catches it in time, the
committed file's shape, and the wiring: a check the weekly run never calls, or
a file Quarto never copies into _book/, would be the same gap with extra steps.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "check-security-txt.py"
SECURITY_TXT = REPO_ROOT / ".well-known" / "security.txt"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release-cadence.yml"
QUARTO = REPO_ROOT / "_quarto.yml"

spec = importlib.util.spec_from_file_location("check_security_txt", SCRIPT)
st = importlib.util.module_from_spec(spec)
spec.loader.exec_module(st)

NOW = datetime(2026, 11, 8, tzinfo=timezone.utc)


def body(expires="2027-06-01T00:00:00.000Z", contact="https://example.org/report"):
    lines = ["# comment: ignored"]
    if contact is not None:
        lines.append(f"Contact: {contact}")
    if expires is not None:
        lines.append(f"Expires: {expires}")
    return "\n".join(lines) + "\n"


class CheckTest(unittest.TestCase):
    def test_a_valid_file_passes(self):
        self.assertEqual(st.check(body(), NOW), [])

    def test_inside_the_refresh_window_fails(self):
        problems = st.check(body(expires="2026-11-30T00:00:00Z"), NOW)
        self.assertEqual(len(problems), 1)
        self.assertIn("refresh window", problems[0])

    def test_already_expired_fails(self):
        problems = st.check(body(expires="2026-11-01T00:00:00Z"), NOW)
        self.assertIn("has passed", problems[0])

    def test_more_than_a_year_away_fails(self):
        problems = st.check(body(expires="2099-01-01T00:00:00Z"), NOW)
        self.assertIn("more than a year", problems[0])

    def test_missing_contact_fails(self):
        self.assertIn("no Contact: line", st.check(body(contact=None), NOW))

    def test_missing_or_repeated_expires_fails(self):
        self.assertIn("found 0", st.check(body(expires=None), NOW)[0])
        doubled = body() + "Expires: 2027-06-01T00:00:00Z\n"
        self.assertIn("found 2", st.check(doubled, NOW)[0])

    def test_field_names_are_case_insensitive(self):
        text = "contact: https://example.org\nEXPIRES: 2027-06-01T00:00:00Z\n"
        self.assertEqual(st.check(text, NOW), [])

    def test_a_timestamp_without_a_timezone_fails(self):
        problems = st.check(body(expires="2027-06-01T00:00:00"), NOW)
        self.assertIn("not an RFC 3339 timestamp", problems[0])


class CommittedFileTest(unittest.TestCase):
    def test_committed_file_fails_once_past_expires(self):
        # The issue's own verification: run against a date past Expires.
        out = io.StringIO()
        with redirect_stdout(out):
            code = st.main(["--now", "2099-01-01T00:00:00Z"])
        self.assertEqual(code, 1)
        self.assertIn("has passed", out.getvalue())

    def test_committed_file_has_the_required_fields(self):
        fields = st.parse_fields(SECURITY_TXT.read_text(encoding="utf-8"))
        self.assertEqual(
            fields["contact"],
            ["https://github.com/lddurbin/twelve_days_to_deming/security/advisories/new"],
        )
        self.assertEqual(len(fields["expires"]), 1)
        self.assertEqual(
            fields["canonical"], ["https://learndeming.org/.well-known/security.txt"]
        )


class WiringTest(unittest.TestCase):
    def test_weekly_workflow_runs_the_check(self):
        self.assertIn("scripts/check-security-txt.py", WORKFLOW.read_text(encoding="utf-8"))

    def test_quarto_copies_the_file_into_the_book(self):
        # Quarto skips dot-directories, so without this resources: entry the
        # file never reaches _book/ and the site serves a 404.
        self.assertIn('".well-known/security.txt"', QUARTO.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
