# Vendored: @basidekick/baskstream

The baskStream SDK is not published to npm yet, so a compiled copy lives here and is
installed as a `file:` dependency. The game's local bridge (`scripts/baskstream-bridge.mjs`)
uses it for the station login, requests, live subscriptions and reconnects.

- Source: https://github.com/rbhans/bask-stream (`sdk/`)
- Commit: 5e11884856c190d0f3fcd50e6f64760b3e2241a6 (API 1.7, SDK 0.1.0)
- License: Apache-2.0 (see LICENSE and NOTICE.md)

Refresh with `npm run vendor:baskstream` (clones the repo, builds and runs the SDK's
tests, copies `dist/`). When the SDK is published, replace the `file:` dependency with
the npm version and delete this folder.
