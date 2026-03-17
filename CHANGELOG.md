# Changelog

All notable release-facing changes to `latchkeyd` should be documented in this file.

The format is intentionally simple while the project is in alpha.

## Unreleased (target: v0.1.0-alpha.2)

### Added

- public-alpha broker core in Swift
- manifest init, refresh, verify, exec, and validate commands
- file and keychain secret backends
- reference wrapper and harmless demo CLI
- isolated temporary-keychain integration coverage
- CI and release workflows
- public demo walkthroughs and visual assets
- `scripts/offline_smoke.sh` for offline proof
- `scripts/local_workflow_parity.sh` for local release-parity commands

### Changed

- broker denial logging now records trust and backend failures earlier and audit logging is enforced with explicit `LOGGING_ERROR` failures when the event log path is unavailable or append fails mid-run
- CI and release workflows now refresh the manifest before verify, and CI runs the dedicated offline smoke proof on macOS
- release candidates still require a green hosted CI run and a green hosted release run after the local parity and offline scripts pass

## v0.1.0-alpha.1

Initial public alpha target.
