# Mode Selection

Use this file when deciding which trust posture fits a task.

## Quick Matrix

| Task shape | Recommended mode | Why |
| :--- | :--- | :--- |
| existing CLI that expects env auth | `handoff` | maximum compatibility |
| short publish or release command | `oneshot` | bounded execution intent |
| repeated bounded operations through a wrapper-aware tool | `brokered` | request-time control |
| provider that supports short-lived scoped credentials | `ephemeral` | reduces long-lived credential exposure |
| highest-risk workflows where the child should not see raw secrets | `proxy` | strongest future posture |

## What To Ask Before Choosing

1. Does the tool already expect normal env-based auth?
2. Does the task need a long-lived session?
3. Is the wrapper able to make request-time broker calls?
4. Does the backend support short-lived credentials?
5. Is raw secret visibility acceptable for this workflow?

## Short Guidance

### `handoff`

Use when compatibility matters more than post-launch control.

### `oneshot`

Use when the task is clearly one command and should not become a long-lived session.

### `brokered`

Use when the wrapper or tool can make explicit broker requests and the workflow benefits from request-time checks.

### `ephemeral`

Use when provider support exists and you want a short-lived credential instead of a longer-lived secret.

### `proxy`

Use when the workflow is sensitive enough that the child should not receive raw secret material at all.

## Current Repo State

Shipped in the repo:

- `handoff`
- `oneshot` first slice
- `brokered` first slice

Planned:

- `ephemeral`
- `proxy`
