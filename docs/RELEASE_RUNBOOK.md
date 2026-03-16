# Release Runbook

This document is the operator checklist for cutting a public `latchkeyd` release.

## Preconditions

- `main` is green in GitHub Actions
- the README and docs match the current shipped behavior
- demo assets are present and reviewable
- the release notes and changelog are current

## Versioning

Suggested alpha tag shape:

- `v0.1.0-alpha.1`
- `v0.1.0-alpha.2`

## Local verification before tag

```bash
swift build
swift test
./.build/debug/latchkeyd manifest init --force
./.build/debug/latchkeyd manifest verify
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./examples/bin/example-wrapper demo
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./.build/debug/latchkeyd validate
```

## Tagging

```bash
git checkout main
git pull --ff-only
git tag v0.1.0-alpha.1
git push origin v0.1.0-alpha.1
```

## Expected GitHub release flow

The tag should trigger the `release` workflow, which:

1. builds the release binary
2. runs tests
3. runs manifest init and verify
4. runs `validate`
5. packages `dist/latchkeyd`
6. publishes `dist/latchkeyd.sha256`

## Post-release checks

- confirm the GitHub Release exists
- confirm the binary downloads correctly
- verify the published checksum
- verify the README renders images and demo links correctly on GitHub
- confirm the changelog entry and release notes match

## If the release workflow fails

Do not move the tag forward silently.

Instead:

1. inspect the failed run
2. fix the workflow or the code
3. cut a new tag for the corrected release

## Announcement gating

Before public announcement, confirm:

- release artifact exists
- checksum exists
- docs and visuals render correctly
- the demo package reflects the current build
