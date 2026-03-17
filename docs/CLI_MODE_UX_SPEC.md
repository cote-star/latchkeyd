# CLI Mode UX Spec

## Purpose

Describe how mode awareness should appear in `latchkeyd` command output and errors.

## Goals

- make the active posture visible
- keep errors structured
- avoid hidden widening of policy behavior

## `status`

`status` should expose:

- version
- manifest path
- support directory
- events path
- supported modes
- brokered protocol version when applicable

## Manifest Commands

`manifest init`, `refresh`, and `verify` should keep structured JSON output.

Mode-aware validation should appear in `manifest verify` items, especially for:

- brokered operation sets
- brokered policy bindings

## `exec`

`exec` inherits child stdout and stderr, but mode should still be visible in audit events and policy configuration.

Expected behavior:

- `handoff`: approved env injection
- `oneshot`: bounded command enforcement
- `brokered`: session setup plus request-time operation handling

## `validate`

`validate` should prove the expected mode-aware workstation behavior.

The current example validation includes:

- handoff demo
- brokered demo
- denial scenario

## Errors

Mode-aware errors should remain structured JSON.

Important codes:

- `USAGE_ERROR`
- `TRUST_DENIED`
- `MANIFEST_INVALID`
- `BACKEND_ERROR`
- `LOGGING_ERROR`
- `OPERATION_NOT_ALLOWED`
- brokered session errors such as auth or expiry failures

## Operator Expectation

The CLI should make it obvious which path failed:

- trust verification
- backend resolution
- logging contract
- brokered session
- brokered operation allowlist
