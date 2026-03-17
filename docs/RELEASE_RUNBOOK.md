# Release Runbook

This is the operator checklist for cutting a public `latchkeyd` macOS alpha.

## Release Target

- current target: `v0.1.0-alpha.3`
- positioning: macOS-only public alpha
- accepted alpha limitations:
  - no daemon mode
  - no cross-platform backend story
  - no same-user compromise claim
  - no signing or notarization yet

## Preconditions

- `README.md`, `CHANGELOG.md`, and demo docs match the current shipped behavior
- `wip/feature_test_report`, `wip/claims_test_report`, and `wip/release_readiness_report` have been regenerated for the candidate commit
- local uncommitted review notes are not the only source of release truth
- the release candidate commit is on the branch you intend to push

## Local Gates Before Any Tag

Run these from the repo root:

```bash
swift build
swift test
scripts/offline_smoke.sh
scripts/local_workflow_parity.sh
```

Expected outcome:

- build and tests pass
- offline smoke succeeds with invalid proxy endpoints
- local parity succeeds for debug and release flows, including packaging and checksum generation

## Audit Contract Check

Before tagging, confirm the release candidate still matches the enforced audit contract:

- `exec` and `validate` preflight the event log path
- manifest lifecycle commands return `LOGGING_ERROR` if the audit log cannot be created or appended
- append failures after child execution surface as `LOGGING_ERROR` with incomplete audit details

Do not announce or tag a build that can silently skip audit logging.

## Hosted Gates Required Before Public Release

Local parity is necessary but not sufficient. A release is not public-ready until hosted runs are green.

1. Push the release candidate branch/commit.
2. Confirm the `ci` workflow passes on GitHub Actions.
3. Create the release tag:

```bash
git checkout main
git pull --ff-only
git tag v0.1.0-alpha.3
git push origin main
git push origin v0.1.0-alpha.3
```

4. Confirm the hosted `release` workflow passes for the tag.
5. Confirm the workflow publishes:
   - `dist/latchkeyd`
   - `dist/latchkeyd.sha256`

If either hosted workflow is red, the candidate is not release-ready.

## Expected Hosted Workflow Coverage

The hosted workflows should cover:

- `swift build`
- `swift test`
- manifest `init`
- manifest `refresh`
- manifest `verify`
- wrapper demo or validation path
- `validate`
- offline smoke proof in CI
- release packaging and checksum creation on tagged builds

## Post-Release Checks

- GitHub Release exists for the tag
- binary downloads correctly
- checksum matches the published artifact
- README images and demo links render on GitHub
- release notes and changelog match the shipped behavior

## If A Gate Fails

Do not move the tag forward silently.

1. inspect the failing local or hosted gate
2. fix the code, workflow, or docs
3. regenerate the `wip/` reports
4. cut a new candidate instead of force-moving the existing tag
