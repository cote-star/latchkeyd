# Changelog

All notable release-facing changes to `latchkeyd` should be documented in this file.

The format is intentionally simple while the project is in alpha.

## Unreleased

### Added

- public-alpha broker core in Swift
- manifest init, refresh, verify, exec, and validate commands
- file and keychain secret backends
- reference wrapper and harmless demo CLI
- JSONL event logging
- CI and release workflows
- public demo walkthroughs and visual assets

### Changed

- broker denial logging now records trust and backend failures earlier
- release workflow now runs a release-mode smoke validation before packaging artifacts

## v0.1.0-alpha.1

Initial public alpha target.
