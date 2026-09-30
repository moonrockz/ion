"""Exercise the workflow's actual release-note command against a local repo."""

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("git-cliff"), "git-cliff is installed by mise in CI")
class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        # Resolve mise's project tool before moving into the temporary repository,
        # where the project configuration is no longer available to its shims.
        executable = shutil.which("git-cliff")
        if shutil.which("mise"):
            executable = subprocess.run(
                ["mise", "which", "git-cliff"],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        self.tool_path = str(Path(executable).parent)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Release test")
        self.git("config", "user.email", "release-test@example.invalid")
        shutil.copyfile(ROOT / "cliff.toml", self.root / "cliff.toml")
        self.git("add", "cliff.toml")
        self.git("commit", "-m", "feat: previous release feature")
        self.git("tag", "v0.1.0")
        self.git("commit", "--allow-empty", "-m", "fix: current release fix")
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Generate release notes\n", 1)[1]
        self.command = textwrap.dedent(
            step.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0]
        )

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def notes(self, tag_exists):
        output = self.root / "github-output"
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", self.command],
            cwd=self.root,
            check=False,
            capture_output=True,
            text=True,
            env=dict(
                os.environ,
                PATH=self.tool_path + os.pathsep + os.environ["PATH"],
                VERSION="0.2.0",
                TAG_EXISTS=tag_exists,
                GITHUB_OUTPUT=str(output),
            ),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return output.read_text()

    def test_manual_release_uses_unreleased_commits_under_new_version(self):
        notes = self.notes("false")
        self.assertIn("[0.2.0]", notes)
        self.assertIn("Current release fix", notes)
        self.assertNotIn("Previous release feature", notes)
        self.assertNotIn("[0.1.0]", notes)

    def test_existing_tag_uses_its_release_notes(self):
        self.git("tag", "v0.2.0")
        notes = self.notes("true")
        self.assertIn("[0.2.0]", notes)
        self.assertIn("Current release fix", notes)
        self.assertNotIn("Previous release feature", notes)


if __name__ == "__main__":
    unittest.main()
