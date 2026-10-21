import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


VALIDATOR = pathlib.Path(__file__).with_name("validate-release.py").resolve()


class ReleaseValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "android").mkdir()
        (self.root / "docs/releases").mkdir(parents=True)
        self.git("init", "-q")
        self.git("config", "user.name", "Release validation")
        self.git("config", "user.email", "ci@example.invalid")
        self.version("0.1.0", 2)

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def version(self, name, code):
        (self.root / "android/version.properties").write_text(
            f"versionName={name}\nversionCode={code}\n", encoding="utf-8")
        (self.root / f"docs/releases/v{name}.md").write_text("发布说明", encoding="utf-8")

    def validate(self, tag="v0.1.0", ref=None):
        return subprocess.run([sys.executable, str(VALIDATOR)], cwd=self.root,
                              env=dict(os.environ, GITHUB_REF_NAME=tag, GITHUB_REF=ref or f"refs/tags/{tag}"),
                              capture_output=True).returncode

    def previous_release(self):
        self.git("add", ".")
        self.git("commit", "-qm", "Previous release")
        self.git("tag", "v0.1.0")

    def test_first_release(self):
        self.assertEqual(self.validate(), 0)

    def test_version_mismatch(self):
        self.assertNotEqual(self.validate("v0.2.0"), 0)

    def test_nonstable_tag(self):
        self.assertNotEqual(self.validate("v0.1.0-rc1"), 0)

    def test_branch_dispatch(self):
        self.assertNotEqual(self.validate(ref="refs/heads/v0.1.0"), 0)

    def test_missing_notes(self):
        (self.root / "docs/releases/v0.1.0.md").unlink()
        self.assertNotEqual(self.validate(), 0)

    def test_version_code_must_increase(self):
        self.previous_release()
        self.version("0.1.1", 2)
        self.assertNotEqual(self.validate("v0.1.1"), 0)
        self.version("0.1.1", 3)
        self.assertEqual(self.validate("v0.1.1"), 0)

    def test_version_name_must_increase(self):
        self.previous_release()
        self.version("0.0.9", 3)
        self.assertNotEqual(self.validate("v0.0.9"), 0)


if __name__ == "__main__":
    unittest.main()
