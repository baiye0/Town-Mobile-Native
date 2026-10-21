#!/usr/bin/env bash
set -euo pipefail

tag=${GITHUB_REF_NAME:?}
repo=${GITHUB_REPOSITORY:?}
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
cd dist/android
sha256sum --check ./*.apk.sha256
python3 - <<'PY'
import json, os, pathlib
files = list(pathlib.Path('.').glob('*.json'))
assert len(files) == 1, 'Expected exactly one APK metadata file'
data = json.loads(files[0].read_text())
assert data['commit'] == os.environ['GITHUB_SHA'], 'Artifact belongs to another commit'
assert 'v' + data['version_name'] == os.environ['GITHUB_REF_NAME'], 'Artifact version mismatch'
assert data['build_type'] == 'release', 'Only Release APKs may be published'
assert len(list(pathlib.Path('.').glob('*.apk'))) == 1, 'Expected exactly one APK'
with open('RELEASE-NOTES.md', 'a', encoding='utf-8') as notes:
    notes.write(f"\n\n构建提交：`{data['commit']}`\n\nPortal 提交：`{data['portal_commit']}`\n\nAPK SHA-256：`{data['sha256']}`\n\n[CI 验证记录]({data['run_url']})\n")
PY

# API/auth failures must stop publishing, not be mistaken for a missing release.
draft=$(gh api --paginate --slurp "repos/$repo/releases" | jq -r --arg tag "$tag" '.[][] | select(.tag_name == $tag) | .draft')
if [[ "$draft" == false ]]; then
  echo "Release $tag is already published; its assets will not be overwritten." >&2
  exit 1
elif [[ -z "$draft" ]]; then
  gh release create "$tag" --repo "$repo" --verify-tag --draft --title "Being Android $tag" --notes-file RELEASE-NOTES.md
elif [[ "$draft" != true ]]; then
  echo 'Unexpected release state' >&2
  exit 1
fi
# A failed upload leaves a draft; a rerun can safely complete that draft.
gh release upload "$tag" --repo "$repo" --clobber ./*.apk ./*.apk.sha256 ./*.json signature.txt package.txt
gh release edit "$tag" --repo "$repo" --notes-file RELEASE-NOTES.md --draft=false
printf '\n[Download Being %s](https://github.com/%s/releases/tag/%s)\n' "$tag" "$repo" "$tag" >> "$GITHUB_STEP_SUMMARY"
