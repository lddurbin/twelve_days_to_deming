"""Tests for scripts/build-adjudication-page.py — the Wave 2 review page builder.

The builder turns a `workflow/validation/adjudications/<pass>.json` record into
the page Lee adjudicates a day's transcription flags on (issue #765). Almost
every way it can go wrong produces a *plausible-looking* page rather than a
crash, which is exactly what the validation in `validate()` exists to stop:

  - A duplicated finding id makes two findings share one decision control, so
    one of them silently inherits the other's verdict.
  - A missing `evidence_html` renders as a finding with no stated reason, which
    reads as an oversight rather than as a bug in the record.
  - A `file` with no `line` renders a location of `file.qmd:None`.
  - An unrecognised `decision` matches no button, so a decided finding reopens
    as undecided.

The last test here guards the one injection path that matters: findings text is
Neave's prose and my commentary, embedded in a `<script>` block, and a literal
`</script>` inside it would end the block early and blank the page.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import contextlib
import copy
import importlib.util
import io
import json
import re
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BUILDER = REPO_ROOT / "scripts" / "build-adjudication-page.py"
TEMPLATE = REPO_ROOT / "workflow" / "validation" / "adjudication" / "template.html"
RECORDS = REPO_ROOT / "workflow" / "validation" / "adjudications"


def load_builder():
    """Import the builder despite its hyphenated, non-importable filename."""
    spec = importlib.util.spec_from_file_location("build_adjudication_page", BUILDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_builder()


MINIMAL = {
    "pass": "day-99",
    "epic": 734,
    "source_pdf": "X.Day.99.pdf",
    "scorer_version": "abc123",
    "content_dir": "content/days/day-99",
    "export_filename": "day-99-decisions.json",
    "page": {
        "eyebrow": "Epic #734 · Wave 2",
        "title": "Day 99 against Neave's manual",
        "standfirst_html": "A test record.",
        "provenance": [{"label": "Source", "value": "X.Day.99.pdf"}],
    },
    "sections": [
        {
            "key": "fix",
            "kind": "k-fix",
            "title": "Fix proposed",
            "count": "1 finding",
            "note_html": "note",
            "labels": {"accept": "Apply fix", "reject": "Leave as-is", "discuss": "Discuss"},
            "items": [
                {
                    "id": "D99-01",
                    "chip": "Word substitution",
                    "chip_class": "crit",
                    "file": "01-intro.qmd",
                    "line": 12,
                    "page": "PDF p5 · printed p1",
                    "flag": "Altered 1 · 96%",
                    "source_html": "the <mark class='src'>source</mark> text",
                    "site_html": "the <mark class='gone'>site</mark> text",
                    "proposal": "the source text",
                    "evidence_html": "because.",
                    "decision": None,
                    "decision_note": None,
                }
            ],
        }
    ],
}


class BuilderTestCase(unittest.TestCase):
    def build(self, record):
        """Build `record` to a temp file and return the page, or raise SystemExit."""
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "rec.json"
            out = Path(tmp) / "out.html"
            src.write_text(json.dumps(record), encoding="utf-8")
            # The builder prints a one-line summary; keep it out of test output.
            with contextlib.redirect_stdout(io.StringIO()):
                builder.build(src, out)
            return out.read_text(encoding="utf-8")

    def embedded(self, html):
        """Pull the record back out of the built page's script block."""
        match = re.search(r"const PASS = (\{.*?\});\n", html, re.S)
        self.assertIsNotNone(match, "built page has no PASS assignment")
        return json.loads(match.group(1).replace("<\\/", "</"))


class TestValidRecord(BuilderTestCase):
    def test_builds_and_substitutes_both_markers(self):
        html = self.build(MINIMAL)
        self.assertNotIn("__TITLE__", html)
        self.assertNotIn("__PASS_JSON__", html)
        self.assertIn("<title>Day 99 against Neave's manual</title>", html)

    def test_artifact_title_overrides_the_heading(self):
        record = copy.deepcopy(MINIMAL)
        record["page"]["artifact_title"] = "Day 99 Adjudication"
        self.assertIn("<title>Day 99 Adjudication</title>", self.build(record))

    def test_record_survives_the_round_trip_intact(self):
        embedded = self.embedded(self.build(MINIMAL))
        self.assertEqual(embedded, MINIMAL)


class TestRejections(BuilderTestCase):
    def assertRejects(self, record):
        with self.assertRaises(SystemExit) as caught:
            self.build(record)
        self.assertEqual(caught.exception.code, 1)

    def test_duplicate_finding_id(self):
        record = copy.deepcopy(MINIMAL)
        twin = copy.deepcopy(record["sections"][0]["items"][0])
        record["sections"][0]["items"].append(twin)
        self.assertRejects(record)

    def test_duplicate_id_across_sections(self):
        record = copy.deepcopy(MINIMAL)
        other = copy.deepcopy(record["sections"][0])
        other["key"] = "clear"
        record["sections"].append(other)
        self.assertRejects(record)

    def test_missing_evidence(self):
        record = copy.deepcopy(MINIMAL)
        del record["sections"][0]["items"][0]["evidence_html"]
        self.assertRejects(record)

    def test_file_without_line(self):
        record = copy.deepcopy(MINIMAL)
        record["sections"][0]["items"][0]["line"] = None
        self.assertRejects(record)

    def test_unrecognised_decision(self):
        record = copy.deepcopy(MINIMAL)
        record["sections"][0]["items"][0]["decision"] = "maybe"
        self.assertRejects(record)

    def test_missing_top_level_key(self):
        record = copy.deepcopy(MINIMAL)
        del record["scorer_version"]
        self.assertRejects(record)

    def test_section_missing_a_decision_label(self):
        record = copy.deepcopy(MINIMAL)
        del record["sections"][0]["labels"]["discuss"]
        self.assertRejects(record)

    def test_no_sections(self):
        record = copy.deepcopy(MINIMAL)
        record["sections"] = []
        self.assertRejects(record)


class TestScriptEscaping(BuilderTestCase):
    def test_closing_script_tag_in_findings_cannot_end_the_block(self):
        record = copy.deepcopy(MINIMAL)
        record["sections"][0]["items"][0]["evidence_html"] = "a literal </script> in the prose"
        html = self.build(record)
        # One opening tag for the page's own script, one closing tag at the end.
        self.assertEqual(html.count("</script>"), 1)
        self.assertEqual(
            self.embedded(html)["sections"][0]["items"][0]["evidence_html"],
            "a literal </script> in the prose",
        )


class TestCommittedRecords(BuilderTestCase):
    """Every record in the repo must still build — they are the real inputs."""

    def test_all_records_build(self):
        records = sorted(RECORDS.glob("*.json"))
        self.assertTrue(records, "no adjudication records found")
        for record in records:
            with self.subTest(record=record.name):
                html = self.build(json.loads(record.read_text(encoding="utf-8")))
                self.assertIn("const PASS = {", html)

    def test_template_keeps_both_markers(self):
        template = TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("__TITLE__", template)
        self.assertIn("__PASS_JSON__", template)


if __name__ == "__main__":
    unittest.main()
