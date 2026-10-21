# Embedded Heart Portal

Source: https://github.com/d5z/heart-portal/tree/android-portal
Revision: `5cf3acb005e06d990a4157dd83a18b9ba4857554` (2026-10-21)
Base: `d9a94832d6d9b2dd6e804e90aa2ac7ba7352e929`; version 0.9.2.
Upstream MIT license is in upstream/LICENSE.

The upstream/ directory is a Git submodule of the android-portal branch.
Run `git submodule update --init --recursive` after cloning this mobile repo.
Gradle builds directly inside that submodule, with outputs outside it in build/.
Rust adaptations are committed on the upstream branch; there is no local patch
layer or duplicated source tree. The mobile repository's gitlink pins the exact
revision, even though .gitmodules records the intended branch for updates.

Android adaptations: android_host.rs optionally binds process lifetime to the app and locks
the private runtime directory; connection_status is enabled on Android and
publishes nonce-scoped state. Android shell children get parent-death cleanup,
kill-on-drop and no inherited relay credentials/control nonce. Other code uses the upstream MCP tools,
relay authentication, heartbeat/reconnect, process management and path checks.
The Android web tool uses bounded reqwest streaming (no curl dependency), checks
and pins public DNS addresses on every redirect. Tool calls enforce file/search/
web capability flags; embedded APK OAuth/custom reload calls are rejected.
Standalone Android launchers retain their previous startup/custom tool behavior
when the optional embedding environment variables are absent.
See ../../docs/ANDROID-PORTAL.md for build, capabilities and verification.

Native Android tools are added upstream in android_tools.rs and exposed through
the existing MCP list/call flow. The authenticated loopback bridge calls Kotlin
system APIs; it has no Shell fallback. Bridge credentials are removed from
the environment passed to Shell children. See ../../docs/ANDROID-PORTAL-NATIVE.md
for app scope and upstream/docs/android-embedded-host.md for the bridge contract.

To upgrade: fetch and check out a tested android-portal commit inside upstream/,
run both ABI builds, Android QA and Rust host tests, then stage the updated gitlink.
Do not run an unpinned `git submodule update --remote` as part of normal builds.

Android host design also references https://github.com/HiddenFox/portal-android
at `340397db82e8b99a08fa9d24d1f557930e36b76b`: executable packaging,
foreground service, CA injection, restart budget and battery guidance. Its
application code and prebuilt binary are not copied into this app.
