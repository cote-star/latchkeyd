# Trust Modes Spec

## Purpose

Define the named execution modes that `latchkeyd` uses so operators can choose the trust posture that fits the task.

## Principles

- mode is explicit
- users pick named postures, not loose security knobs
- guarantees are mode-specific
- mode changes should be visible in manifests, CLI output, validation, and logs

## Modes

### `handoff`

Summary:

- trusted child gets approved env vars at launch

Best for:

- compatibility with existing tools

Guarantee:

- wrapper and binary are verified before handoff

Limit:

- the child can retain or re-export the secret after launch

### `oneshot`

Summary:

- like `handoff`, but intended for one bounded command

Best for:

- publish, release, and other short-lived commands

Guarantee:

- the broker can reject obvious long-lived argument patterns

Limit:

- the child still sees the raw secret while it runs

### `brokered`

Summary:

- the child starts with session metadata only and requests approved operations later

Best for:

- repeated bounded actions where request-time control matters

Guarantee:

- the broker checks the session and operation allowlist before returning an approved result

Limit:

- the first shipped slice is intentionally narrow

### `ephemeral`

Summary:

- planned mode for provider-backed short-lived credentials

### `proxy`

Summary:

- planned mode for secretless or delegated operation paths

## Current Repo State

Shipped in the repo:

- `handoff`
- `oneshot` first slice
- `brokered` first slice

Planned:

- `ephemeral`
- `proxy`

## Operator Rule

Choose the mode per task. Do not assume every workflow needs the same trust posture.
