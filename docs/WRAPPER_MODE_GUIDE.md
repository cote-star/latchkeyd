# Wrapper Mode Guide

## Purpose

Help wrapper authors understand what changes when a wrapper targets different trust modes.

## Shared Rules

All wrappers should:

- keep the command surface small and explicit
- validate input before broker access
- fail closed on unknown operations
- call `latchkeyd exec` instead of resolving secrets themselves
- pass their own trusted wrapper path as caller identity

## `handoff`

Wrapper shape:

- normalize input
- call `latchkeyd exec`
- let the trusted child start with approved env vars

Good for:

- existing tools that already expect env-based auth

## `oneshot`

Wrapper shape:

- same as `handoff`, but designed for clearly bounded commands

Good for:

- publish
- release
- one-shot admin tasks

Wrapper advice:

- avoid exposing actions that naturally want to linger or watch

## `brokered`

Wrapper shape:

- call `latchkeyd exec` for a brokered policy
- launch a child that knows how to talk to the local broker session
- keep request names explicit and narrow

Good for:

- repeated bounded operations
- workflows that benefit from request-time control

Current example:

- `example-wrapper brokered-demo`

## `ephemeral`

Planned wrapper implication:

- wrappers may need to understand short-lived credential lifetime or refresh boundaries

## `proxy`

Planned wrapper implication:

- wrappers may become capability-oriented rather than secret-oriented

## Current Example Surface

The example wrapper demonstrates:

- `demo` for `handoff`
- `brokered-demo` for `brokered`

That split is intentional. Different trust postures should be visible in the wrapper surface, not hidden behind a vague one-command interface.
