#!/usr/bin/env bash
set -euo pipefail

short_sha=$(git rev-parse --short=7 HEAD)
build_type=${1:-debug}
case "$build_type" in debug|release) ;; *) echo 'Expected debug or release' >&2; exit 1 ;; esac
tools="$ANDROID_HOME/build-tools/35.0.0"
version=$(sed -n 's/^versionName=//p' android/version.properties | tr -d '\r')
apk="dist/android/Being-portal-${short_sha}-debug.apk"
if [[ "$build_type" == release ]]; then
  test "${GITHUB_REF_NAME:?}" = "v$version"
  apk="dist/android/Being-${version}-android.apk"
fi
mkdir -p dist/android
cp "android/app/build/outputs/apk/$build_type/app-$build_type.apk" "$apk"

"$tools/apksigner" verify --verbose --print-certs "$apk" > dist/android/signature.txt
actual_signer=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' dist/android/signature.txt)
test -n "$actual_signer"
"$tools/zipalign" -c -P 16 4 "$apk"
"$tools/aapt" dump badging "$apk" > dist/android/package.txt
grep -q "^package: name='town.beings.nativeapp' " dist/android/package.txt
if [[ "$build_type" == release ]]; then
  expected_signer=$(tr -d '\r\n' < android/release-certificate.sha256)
  test "$actual_signer" = "$expected_signer"
  if grep -q '^application-debuggable' dist/android/package.txt; then
    echo 'Release APK must not be debuggable' >&2
    exit 1
  fi
fi

export PACKAGED_APK="$apk"
export APK_SIGNER_SHA256="$actual_signer"
export APK_BUILD_TYPE="$build_type"
python3 - <<'PY'
import hashlib, json, os, pathlib, re, struct, subprocess, zipfile
p = pathlib.Path(os.environ['PACKAGED_APK'])
version = dict(line.split('=', 1) for line in pathlib.Path('android/version.properties').read_text().splitlines() if '=' in line)
badging = pathlib.Path('dist/android/package.txt').read_text()
assert re.search(r"^package: .*versionCode='" + re.escape(version['versionCode']) + r"' .*versionName='" + re.escape(version['versionName']) + "'", badging), 'APK version differs from version.properties'
runtime = {}
with zipfile.ZipFile(p) as archive:
    for abi in ['arm64-v8a', 'x86_64']:
        binary = archive.read(f'lib/{abi}/libheart_portal.so')
        assert binary[:6] == b'\x7fELF\x02\x01', f'{abi}: expected 64-bit little-endian ELF'
        offset = struct.unpack_from('<Q', binary, 32)[0]
        size, count = struct.unpack_from('<HH', binary, 54)
        loads = [struct.unpack_from('<IIQQQQQQ', binary, offset + i * size) for i in range(count)]
        loads = [h for h in loads if h[0] == 1]
        assert loads and all(h[7] >= 16384 and h[2] % 16384 == h[3] % 16384 for h in loads), f'{abi}: invalid 16 KB load alignment'
        runtime[abi] = hashlib.sha256(binary).hexdigest()
digest = hashlib.sha256(p.read_bytes()).hexdigest()
p.with_suffix('.apk.sha256').write_text(f'{digest}  {p.name}\n')
metadata = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'portal_commit': subprocess.check_output(['git', '-C', 'android/portal-runtime/upstream', 'rev-parse', 'HEAD'], text=True).strip(),
    'package': 'town.beings.nativeapp', 'build_type': os.environ['APK_BUILD_TYPE'], 'bytes': p.stat().st_size,
    'version_name': version['versionName'], 'version_code': int(version['versionCode']),
    'apk': p.name, 'sha256': digest, 'signer_sha256': os.environ['APK_SIGNER_SHA256'],
    'portal_elf_sha256': runtime,
    'run_url': f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
}
p.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
    summary.write(f"## Being Android APK\n\n- Package: `town.beings.nativeapp`\n- Build: {metadata['build_type']}\n- Version: {metadata['version_name']} ({metadata['version_code']})\n- Signer SHA-256: `{metadata['signer_sha256']}`\n- Commit: `{metadata['commit']}`\n- Portal: `{metadata['portal_commit']}`\n- Portal ABIs: ARM64 / x86_64; 16 KB alignment verified\n- SHA-256: `{digest}`\n\nUnit tests and lint ran in this job; device instrumentation is not run in this workflow.\n")
PY
printf 'short_sha=%s\n' "$short_sha" >> "$GITHUB_OUTPUT"
