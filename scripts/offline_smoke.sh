#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

debug_manifest="${tmp_dir}/offline-manifest.json"

proxy_env=(
  "http_proxy=http://127.0.0.1:1"
  "https_proxy=http://127.0.0.1:1"
  "HTTP_PROXY=http://127.0.0.1:1"
  "HTTPS_PROXY=http://127.0.0.1:1"
  "ALL_PROXY=socks5://127.0.0.1:1"
  "no_proxy=localhost,127.0.0.1"
  "NO_PROXY=localhost,127.0.0.1"
)

echo "== offline preflight =="
swift --version

echo "== build under offline proxies =="
env "${proxy_env[@]}" swift build

echo "== test under offline proxies =="
env "${proxy_env[@]}" swift test

echo "== manifest lifecycle =="
env "${proxy_env[@]}" .build/debug/latchkeyd manifest init --manifest "${debug_manifest}" --force
env "${proxy_env[@]}" .build/debug/latchkeyd manifest refresh --manifest "${debug_manifest}"
env "${proxy_env[@]}" .build/debug/latchkeyd manifest verify --manifest "${debug_manifest}"

echo "== wrapper demo =="
env "${proxy_env[@]}" \
  LATCHKEYD_BIN="${repo_root}/.build/debug/latchkeyd" \
  ./examples/bin/example-wrapper demo --manifest "${debug_manifest}" -- offline-smoke

echo "== raw exec =="
env "${proxy_env[@]}" \
  PATH="${repo_root}/examples/bin:$PATH" \
  .build/debug/latchkeyd exec --manifest "${debug_manifest}" --policy example-demo --caller "${repo_root}/examples/bin/example-wrapper" -- raw offline

echo "== validate =="
env "${proxy_env[@]}" \
  LATCHKEYD_BIN="${repo_root}/.build/debug/latchkeyd" \
  .build/debug/latchkeyd validate --manifest "${debug_manifest}"

echo "offline smoke succeeded"
