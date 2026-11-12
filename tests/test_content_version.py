"""Tests for scripts/lib/content-version.sh — which site files a validation
record covers, and `content_version`, the hash of them.

Issue #837: a results/ record said which comparator produced it and which PDF
it read, but not which site content it was compared against, so a PR could
change a day's content and leave its record describing pages that no longer
exist, with every check green. `content_version` closes that, and it is only
worth anything if these couplings hold:

  1. The writer and the reader take the file list and the hash from the *same*
     definition. If either works out its own list, a record can be stamped
     fresh and read stale, or the reverse.
  2. The hash moves when a covered file's bytes change, and when the list
     itself changes (a chapter added to a manifest restales the counts too).
  3. Every file any record covers is matched by the staleness workflow's
     `paths:` filters, as are the manifests and register that decide the list.
     GitHub never runs a workflow whose paths didn't match.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_scorer_version import WorkflowPathFilterTests

REPO_ROOT = Path(__file__).resolve().parents[1]
LIB = REPO_ROOT / "scripts" / "lib" / "content-version.sh"
WRITER = REPO_ROOT / "scripts" / "validate-transcription.sh"
READER = REPO_ROOT / "scripts" / "check-validation-staleness.sh"
RESULTS = REPO_ROOT / "workflow" / "validation" / "results"
RECORDS = sorted(p.stem for p in RESULTS.glob("*.yml"))


def run_lib(snippet, root=REPO_ROOT):
    """Source the library in a bash subshell and run `snippet` with ROOT set."""
    return subprocess.run(
        ["bash", "-c", f'set -euo pipefail\n. "{LIB}"\nROOT="{root}"\n{snippet}'],
        capture_output=True,
        text=True,
        cwd=root,
    )


def lines(result):
    return [line for line in result.stdout.splitlines() if line]


class Fixture(unittest.TestCase):
    """A throwaway git repo shaped like this one, so edits can't touch real content."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("content/days/day-01/02-b.qmd", "Second.\n")
        self.write("content/days/day-01/01-a.qmd", "First.\n")
        self.write("content/extra/one.qmd", "One.\n")
        self.write("content/extra/two.qmd", "Two.\n")
        self.write("content/extra/original.qmd", "Written for the site.\n")
        self.write(
            "workflow/validation/extra-manifest.yml",
            "pdf_file: X.pdf\ncontent_dir: content/extra\nchapters:\n"
            '  - file: "two.qmd"\n  - file: "one.qmd"\n  - file: "original.qmd"\n',
        )
        self.write("front.qmd", "Front matter.\n")
        self.write(
            "workflow/validation/front-manifest.yml",
            'pdf_file: F.pdf\ncontent_dir: "."\nchapters:\n  - file: "front.qmd"\n',
        )
        self.write(
            "workflow/validation/no-source.yml",
            "pages:\n  content/extra/original.qmd: >-\n    Site original.\n",
        )

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def version(self, record):
        result = run_lib(f'compute_content_version "$ROOT" {record}', self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()


class FileListTests(Fixture):
    def test_day_record_is_its_directory_sorted(self):
        result = run_lib('compared_content_files "$ROOT" day-01', self.root)
        self.assertEqual(
            lines(result),
            ["content/days/day-01/01-a.qmd", "content/days/day-01/02-b.qmd"],
        )

    def test_manifest_record_is_its_chapters_minus_no_source(self):
        result = run_lib('partition_content_files "$ROOT" extra', self.root)
        self.assertEqual(
            lines(result),
            [
                "compare content/extra/one.qmd",
                "skip content/extra/original.qmd",
                "compare content/extra/two.qmd",
            ],
        )

    def test_dot_content_dir_means_the_repo_root(self):
        result = run_lib('compared_content_files "$ROOT" front', self.root)
        self.assertEqual(lines(result), ["front.qmd"])

    def test_unknown_record_fails_loudly(self):
        result = run_lib('compared_content_files "$ROOT" nowhere', self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nowhere-manifest.yml", result.stderr)

    def test_refresh_command_names_the_record(self):
        result = run_lib(
            "content_record_command day-03; content_record_command appendix-main"
        )
        self.assertEqual(
            lines(result),
            [
                "./scripts/validate-transcription.sh 3",
                "./scripts/validate-transcription.sh --manifest appendix-main",
            ],
        )


class ComputationTests(Fixture):
    def test_computes_a_hash(self):
        self.assertRegex(self.version("day-01"), r"^[0-9a-f]{40}$")

    def test_is_deterministic(self):
        self.assertEqual(self.version("extra"), self.version("extra"))

    def test_moves_when_a_covered_file_changes(self):
        before = self.version("day-01")
        self.write("content/days/day-01/01-a.qmd", "First, corrected.\n")
        self.assertNotEqual(before, self.version("day-01"))

    def test_moves_when_a_file_joins_a_day(self):
        before = self.version("day-01")
        self.write("content/days/day-01/03-c.qmd", "Third.\n")
        self.assertNotEqual(before, self.version("day-01"))

    def test_moves_when_a_manifest_gains_a_chapter(self):
        before = self.version("extra")
        self.write("content/extra/three.qmd", "Three.\n")
        unchanged = self.version("extra")
        self.assertEqual(before, unchanged, "an unlisted file must not count")
        manifest = self.root / "workflow/validation/extra-manifest.yml"
        manifest.write_text(manifest.read_text() + '  - file: "three.qmd"\n')
        self.assertNotEqual(before, self.version("extra"))

    def test_ignores_a_held_out_page(self):
        """A page in no-source.yml is not compared, so editing it restales nothing."""
        before = self.version("extra")
        self.write("content/extra/original.qmd", "Rewritten for the site.\n")
        self.assertEqual(before, self.version("extra"))

    def test_moves_when_a_page_leaves_no_source(self):
        before = self.version("extra")
        self.write("workflow/validation/no-source.yml", "pages: {}\n")
        self.assertNotEqual(before, self.version("extra"))

    def test_refuses_a_missing_chapter(self):
        """A manifest naming a file that isn't there must fail, not hash fewer files."""
        (self.root / "content/extra/two.qmd").unlink()
        result = run_lib('compute_content_version "$ROOT" extra', self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("content/extra/two.qmd", result.stderr)

    def test_refuses_a_record_that_covers_nothing(self):
        self.write(
            "workflow/validation/empty-manifest.yml",
            "pdf_file: E.pdf\ncontent_dir: content/extra\nchapters: []\n",
        )
        result = run_lib('compute_content_version "$ROOT" empty', self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("covers no files", result.stderr)


class RealRecordTests(unittest.TestCase):
    def test_there_are_records(self):
        self.assertTrue(RECORDS, "no records found in workflow/validation/results")

    def test_every_record_resolves_to_existing_files(self):
        for record in RECORDS:
            with self.subTest(record=record):
                result = run_lib(f'compute_content_version "$ROOT" {record}')
                self.assertEqual(result.returncode, 0, result.stderr)


class SharedDefinitionTests(unittest.TestCase):
    def test_both_consumers_source_the_library(self):
        for script in (WRITER, READER):
            with self.subTest(script=script.name):
                self.assertIn("lib/content-version.sh", script.read_text())

    def test_the_writer_does_not_define_its_own_file_list(self):
        """The helpers that decide the list must exist in the library only."""
        text = WRITER.read_text()
        for helper in ("read_manifest", "read_no_source", "content_candidates"):
            with self.subTest(helper=helper):
                self.assertNotRegex(text, rf"(?m)^\s*{helper}\(\)\s*\{{")

    def test_the_writer_stamps_the_value(self):
        self.assertIn("content_version: $content_version", WRITER.read_text())

    def test_the_reader_recomputes_the_value(self):
        self.assertIn("compute_content_version", READER.read_text())


def matches(pattern, path):
    """GitHub Actions `paths:` glob semantics, as far as this workflow uses them:
    `**` crosses directories, `*` does not."""
    regex = ""
    i = 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            regex += ".*"
            i += 2
        elif pattern[i] == "*":
            regex += "[^/]*"
            i += 1
        else:
            regex += re.escape(pattern[i])
            i += 1
    return re.fullmatch(regex, path) is not None


class WorkflowPathFilterTests(unittest.TestCase):
    """A covered-but-unfiltered file is a staleness check that never fires."""

    blocks = WorkflowPathFilterTests.path_filter_blocks()

    def test_glob_semantics(self):
        self.assertTrue(matches("content/**", "content/days/day-01/a.qmd"))
        self.assertTrue(matches("workflow/validation/*-manifest.yml",
                                "workflow/validation/day-03-manifest.yml"))
        self.assertFalse(matches("workflow/validation/*-manifest.yml",
                                 "workflow/validation/results/x-manifest.yml"))
        self.assertFalse(matches("index.qmd", "content/index.qmd"))

    def test_both_triggers_have_a_path_filter(self):
        self.assertEqual(len(self.blocks), 2)

    def test_every_covered_file_is_filtered(self):
        covered = set()
        for record in RECORDS:
            covered.update(lines(run_lib(f'compared_content_files "$ROOT" {record}')))
        self.assertTrue(covered)
        for block in self.blocks:
            for rel in sorted(covered):
                with self.subTest(file=rel):
                    self.assertTrue(
                        any(matches(p, rel) for p in block),
                        f"{rel} is covered by a validation record but no `paths:` "
                        "entry in validation-staleness.yml matches it",
                    )

    def test_what_decides_the_list_is_filtered(self):
        deciders = ["workflow/validation/no-source.yml", "scripts/lib/content-version.sh"]
        deciders += [
            str(p.relative_to(REPO_ROOT))
            for p in (REPO_ROOT / "workflow" / "validation").glob("*-manifest.yml")
        ]
        for block in self.blocks:
            for rel in deciders:
                with self.subTest(file=rel):
                    self.assertTrue(any(matches(p, rel) for p in block))


if __name__ == "__main__":
    unittest.main()
