"""Reject mismatched tags, reused version codes and incomplete release notes."""
import os
import pathlib
import re
import subprocess


def properties(text):
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def semver(tag):
    match = re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag)
    if not match:
        raise ValueError(f"Expected a stable vMAJOR.MINOR.PATCH tag: {tag}")
    return tuple(map(int, match.groups()))


tag = os.environ["GITHUB_REF_NAME"]
current = semver(tag)
assert os.environ["GITHUB_REF"] == f"refs/tags/{tag}", "Select a version tag when dispatching"
version = properties(pathlib.Path("android/version.properties").read_text(encoding="utf-8"))
assert tag == f"v{version['versionName']}", "Tag must match versionName"
code = int(version["versionCode"])
assert 0 < code <= 2_100_000_000, "Invalid Android versionCode"
assert pathlib.Path(f"docs/releases/{tag}.md").read_text(encoding="utf-8").strip(), "Release notes are required"

tags = subprocess.check_output(["git", "tag", "--list", "v*"], text=True).splitlines()
for previous in tags:
    if previous == tag or not re.fullmatch(r"v\d+\.\d+\.\d+", previous):
        continue
    assert current > semver(previous), f"Version must exceed existing tag {previous}"
    old = subprocess.check_output(["git", "show", f"{previous}:android/version.properties"], text=True)
    assert code > int(properties(old)["versionCode"]), f"versionCode must exceed {previous}"

print(f"Validated {tag}, Android versionCode {code}")
