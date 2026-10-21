# iOS Intelligent UI host

This host bundles the MIT-licensed Town-Client renderer and protocol validator
from commit `1cf523135ae78cd5d9eebe52ec7c33aa4854c264` (2026-10-21 local checkout).
`vendor/LICENSE` retains the upstream license. `vendor/intelligent-ui/styles.css`
is the Intelligent UI section of upstream `desktop/renderer/chat/styles.css`.

Host adapters replace `storage.ts` and `components/remote-image.tsx`: state is
scoped by a hash of Being endpoint + scene and persisted by the native app;
image preview/export uses the native viewer. The remaining vendored modules
retain their upstream behavior, including schema validation, surface revision
conflict checks and the isolated Worker runtime.

Run `npm ci --ignore-scripts`, `npm test`, and `npm run build` in this directory.
Generated `ios/Town/IntelligentUIResources` assets are committed so Xcode builds
need no Node runtime or network access. Rebuild after changing web sources.
Licenses for bundled React, ReactDOM, scheduler and marked ship with the app.

The WKWebView has ephemeral website storage, no Being credentials, no arbitrary
native calls, no navigation away from bundled HTML, and no fetch/XHR capability.
Generated `app` code executes only in the upstream sandboxed iframe's Worker;
the native bridge rejects all subframe messages. HTML content is never injected
from chat. Images are permitted only by the protocol's image validator and CSP.
The host passes JSON through `callAsyncJavaScript` arguments, never interpolation.
Continue actions update the draft; only the normal Send button submits a message.
