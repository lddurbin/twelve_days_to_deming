"""Tests for scripts/lib/scorer-version.sh — the shared `scorer_version` definition.

Issue #737 widened `scorer_version` from a hash of one file to a hash of every
file that can change what a validation run reports. That widening is only worth
anything if three couplings hold, and none of them is visible at a glance:

  1. The writer and the reader use the *same* definition. If either recomputes
     its own hash inline, results can be stamped fresh and read stale.
  2. Every file in the definition exists. A typo in the list would otherwise
     silently drop a file out of coverage.
  3. Every file in the definition is in the staleness workflow's `paths:`
     filter. GitHub never runs a workflow whose paths didn't match, so a file
     that is hashed but not filtered is a check that never fires on the edit it
     was added to catch.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import re
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
LIB = REPO_ROOT / "scripts" / "lib" / "scorer-version.sh"
WRITER = REPO_ROOT / "scripts" / "validate-transcription.sh"
READER = REPO_ROOT / "scripts" / "check-validation-staleness.sh"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "validation-staleness.yml"

# The library is the source of truth for the list; parse it rather than
# restating it here, so this test can't itself become the drifting copy.
SCORER_VERSION_FILES = re.findall(
    r"^\s*(\S+)\s*$",
    re.search(
        r"^SCORER_VERSION_FILES=\((.*?)^\)",
        LIB.read_text(),
        re.MULTILINE | re.DOTALL,
    ).group(1),
    re.MULTILINE,
)


def run_bash(snippet):
    """Source the library in a bash subshell and run `snippet`."""
    return subprocess.run(
        ["bash", "-c", f'set -euo pipefail\n. "{LIB}"\n{snippet}'],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )


class FileListTests(unittest.TestCase):
    def test_list_is_not_empty(self):
        self.assertTrue(
            SCORER_VERSION_FILES,
            "Failed to parse SCORER_VERSION_FILES out of scripts/lib/scorer-version.sh",
        )

    def test_every_listed_file_exists(self):
        for rel in SCORER_VERSION_FILES:
            with self.subTest(file=rel):
                self.assertTrue(
                    (REPO_ROOT / rel).is_file(),
                    f"{rel} is in SCORER_VERSION_FILES but does not exist",
                )

    def test_every_pipeline_module_is_covered(self):
        """The two files #737 exists to cover, plus what later PRs moved out of them.

        qmd_strip.py joined the list in #739, when QMD stripping left the
        shell script, and paragraphs.py in #741, when paragraph assembly did.
        Pinned by name rather than left to the existence check above:
        dropping one would not break anything visibly, it would just stop
        stale results being caught after a change to that stage.
        """
        for rel in (
            "scripts/lib/paragraph_similarity.py",
            "scripts/lib/paragraphs.py",
            "scripts/lib/qmd_strip.py",
            "scripts/validate-transcription.sh",
        ):
            self.assertIn(rel, SCORER_VERSION_FILES)

    def test_library_does_not_list_itself(self):
        """Self-reference would only add false staleness — see the comment in the library.

        Any edit here that can change the computed value already changes it,
        because this is the file that computes it.
        """
        self.assertNotIn("scripts/lib/scorer-version.sh", SCORER_VERSION_FILES)


class ComputationTests(unittest.TestCase):
    def test_computes_a_hash(self):
        result = run_bash('compute_scorer_version "$PWD"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout.strip(), r"^[0-9a-f]{40}$")

    def test_is_deterministic(self):
        first = run_bash('compute_scorer_version "$PWD"').stdout
        second = run_bash('compute_scorer_version "$PWD"').stdout
        self.assertEqual(first, second)

    def test_is_independent_of_list_order(self):
        """Sorting the manifest means reordering the array is not a behaviour change."""
        forward = run_bash('compute_scorer_version "$PWD"').stdout
        reversed_list = " ".join(f'"{f}"' for f in reversed(SCORER_VERSION_FILES))
        backward = run_bash(
            f"SCORER_VERSION_FILES=({reversed_list})\n" 'compute_scorer_version "$PWD"'
        ).stdout
        self.assertEqual(forward, backward)

    def test_differs_from_the_old_single_file_definition(self):
        """Guards the migration: the new value must not collide with the pre-#737 one."""
        combined = run_bash('compute_scorer_version "$PWD"').stdout.strip()
        legacy = subprocess.run(
            ["git", "hash-object", "scripts/lib/paragraph_similarity.py"],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        ).stdout.strip()
        self.assertNotEqual(combined, legacy)

    def test_refuses_an_empty_file_list(self):
        """bash 3.2 and bash 4.4+ disagree about the unguarded empty case.

        On macOS's bash 3.2 the unbound expansion aborts; on the CI runner's
        bash 5 it expands to nothing and hashes the empty string into a
        valid-looking 40-character answer. Guarded, both fail the same way.
        """
        result = run_bash('SCORER_VERSION_FILES=()\ncompute_scorer_version "$PWD"')
        self.assertNotEqual(result.returncode, 0)
        # Assert on the guard's own message, not just a non-zero exit: bash 3.2
        # exits non-zero on the unguarded case too, so exit status alone would
        # make this test pass on macOS whether the guard is there or not.
        self.assertIn("SCORER_VERSION_FILES is empty", result.stderr)
        self.assertNotIn("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", result.stdout)

    def test_refuses_an_incomplete_file_list(self):
        """A typo in the list must fail loudly, not quietly hash fewer files."""
        result = run_bash(
            'SCORER_VERSION_FILES=(scripts/lib/does-not-exist.py)\n'
            'compute_scorer_version "$PWD"'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does-not-exist.py", result.stderr)


class SharedDefinitionTests(unittest.TestCase):
    def test_both_consumers_source_the_library(self):
        for script in (WRITER, READER):
            with self.subTest(script=script.name):
                self.assertIn("lib/scorer-version.sh", script.read_text())

    def test_neither_consumer_hashes_the_pipeline_itself(self):
        """`git hash-object` on a pipeline file outside the library is a second definition."""
        for script in (WRITER, READER):
            with self.subTest(script=script.name):
                for line in script.read_text().splitlines():
                    if "hash-object" in line and not line.lstrip().startswith("#"):
                        self.fail(
                            f"{script.name} computes its own hash ({line.strip()!r}); "
                            "scorer_version must come from compute_scorer_version() alone"
                        )


class WorkflowPathFilterTests(unittest.TestCase):
    """A hashed-but-unfiltered file is a staleness check that never fires."""

    @staticmethod
    def path_filter_blocks(text=None):
        """Collect the entries of every `paths:` sequence in the workflow.

        Comment lines inside a sequence are skipped rather than treated as the
        end of it: a `# why this path is here` note is a plausible future edit,
        and truncating on it would fail these tests for a reason that has
        nothing to do with the coverage they exist to check. Blank lines *do*
        end a block — a blank line is as likely to separate two unrelated keys
        as to sit inside one sequence, and over-reading is the worse error.
        """
        blocks, current = [], None
        for line in (WORKFLOW.read_text() if text is None else text).splitlines():
            if re.match(r"^\s+paths:\s*$", line):
                current = []
                blocks.append(current)
                continue
            if current is None:
                continue
            if re.match(r"^\s+#", line):
                continue
            entry = re.match(r"^\s+- '(.+)'\s*$", line)
            if entry:
                current.append(entry.group(1))
            else:
                current = None
        return blocks

    def test_parser_survives_a_comment_inside_a_block(self):
        blocks = self.path_filter_blocks(
            "  push:\n"
            "    paths:\n"
            "      - 'a/one.py'\n"
            "      # the shell script owns extraction and stripping\n"
            "      - 'b/two.sh'\n"
        )
        self.assertEqual(blocks, [["a/one.py", "b/two.sh"]])

    def test_parser_stops_at_the_end_of_a_block(self):
        blocks = self.path_filter_blocks(
            "  push:\n"
            "    paths:\n"
            "      - 'a/one.py'\n"
            "    branches:\n"
            "      - 'main'\n"
        )
        self.assertEqual(blocks, [["a/one.py"]])

    def test_both_triggers_have_a_path_filter(self):
        self.assertEqual(len(self.path_filter_blocks()), 2)

    def test_every_hashed_file_is_filtered(self):
        for block in self.path_filter_blocks():
            for rel in SCORER_VERSION_FILES:
                with self.subTest(file=rel):
                    self.assertIn(rel, block)

    def test_the_library_itself_is_filtered(self):
        """Not hashed, but editing the list must still trigger the check."""
        for block in self.path_filter_blocks():
            self.assertIn("scripts/lib/scorer-version.sh", block)


if __name__ == "__main__":
    unittest.main()
