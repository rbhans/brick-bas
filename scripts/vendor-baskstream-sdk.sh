#!/usr/bin/env bash
# Rebuilds vendor/baskstream-sdk from github.com/rbhans/bask-stream (default branch, or $1):
# clones the SDK, builds it and runs its own tests, then copies dist/ and the licence.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/baskstream-sdk"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 --filter=blob:none --sparse ${1:+--branch "$1"} https://github.com/rbhans/bask-stream.git "$WORK/repo"
git -C "$WORK/repo" sparse-checkout set sdk spec
COMMIT="$(git -C "$WORK/repo" rev-parse HEAD)"
(cd "$WORK/repo/sdk" && npm install --no-audit --no-fund && npm test)

rm -rf "$DEST/dist"
cp -R "$WORK/repo/sdk/dist" "$DEST/dist"
cp "$WORK/repo/LICENSE" "$DEST/LICENSE"
cp "$WORK/repo/NOTICE.md" "$DEST/NOTICE.md"
cp "$WORK/repo/sdk/README.md" "$DEST/UPSTREAM-README.md"
sed -i.bak "s/^- Commit: .*/- Commit: $COMMIT/" "$DEST/VENDORED.md" && rm "$DEST/VENDORED.md.bak"
echo "Vendored baskStream SDK at $COMMIT. Update the version in $DEST/package.json if it changed, then npm install."
