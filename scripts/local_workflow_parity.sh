#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

debug_manifest="${tmp_dir}/debug-manifest.json"
release_manifest="${tmp_dir}/release-manifest.json"
release_dist="${tmp_dir}/dist"

echo "== debug build =="
swift build

echo "== test =="
swift test

echo "== debug manifest init/verify =="
.build/debug/latchkeyd manifest init --manifest "${debug_manifest}" --force
.build/debug/latchkeyd manifest refresh --manifest "${debug_manifest}"
.build/debug/latchkeyd manifest verify --manifest "${debug_manifest}"

echo "== debug wrapper demo =="
LATCHKEYD_BIN="${repo_root}/.build/debug/latchkeyd" \
  ./examples/bin/example-wrapper demo --manifest "${debug_manifest}" -- parity smoke

echo "== debug validate =="
LATCHKEYD_BIN="${repo_root}/.build/debug/latchkeyd" \
  .build/debug/latchkeyd validate --manifest "${debug_manifest}"

echo "== release build =="
swift build -c release

echo "== release test =="
swift test -c release

echo "== release manifest init/verify =="
.build/release/latchkeyd manifest init --manifest "${release_manifest}" --force
.build/release/latchkeyd manifest refresh --manifest "${release_manifest}"
.build/release/latchkeyd manifest verify --manifest "${release_manifest}"

echo "== release validate =="
LATCHKEYD_BIN="${repo_root}/.build/release/latchkeyd" \
  .build/release/latchkeyd validate --manifest "${release_manifest}"

echo "== release package =="
mkdir -p "${release_dist}"
cp .build/release/latchkeyd "${release_dist}/latchkeyd"
chmod +x "${release_dist}/latchkeyd"
shasum -a 256 "${release_dist}/latchkeyd" > "${release_dist}/latchkeyd.sha256"

echo "local workflow parity succeeded"
echo "artifacts: ${release_dist}"
