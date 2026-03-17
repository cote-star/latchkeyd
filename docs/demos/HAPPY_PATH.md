# Happy Path Demos

This file now covers both shipped example paths:

- `handoff`
- `brokered`

## Handoff Mode Demo

### Goal

Show a trusted wrapper calling a trusted binary with one approved secret handoff.

### Commands

```bash
swift build
./.build/debug/latchkeyd manifest init --force
./.build/debug/latchkeyd manifest refresh
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./examples/bin/example-wrapper demo
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./.build/debug/latchkeyd validate
```

### Expected flow

1. `manifest init` writes the starter manifest.
2. `manifest refresh` pins the current wrapper and binary hashes.
3. `example-wrapper demo` calls `latchkeyd exec`.
4. `latchkeyd` verifies the wrapper path and hash.
5. `latchkeyd` verifies the downstream binary path and hash.
6. `latchkeyd` injects only `LATCHKEYD_EXAMPLE_TOKEN`.
7. `example-demo-cli` proves the token was present without printing it.
8. `validate` confirms the example path and at least one denial path.

### Example output

```json
{
  "ok": true,
  "tool": "example-demo-cli",
  "transport": "handoff",
  "tokenPreview": "la***en",
  "tokenLength": 19,
  "args": []
}
```

### Narrative

This demo uses the current `handoff` model. The broker decides whether the tool may start with the approved env var, but post-handoff behavior still belongs to the trusted child.

## Brokered Mode Demo

### Goal

Show a trusted wrapper calling a trusted binary without raw secret env injection at launch.

### Commands

```bash
swift build
./.build/debug/latchkeyd manifest init --force
./.build/debug/latchkeyd manifest refresh
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./examples/bin/example-wrapper brokered-demo
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./.build/debug/latchkeyd validate
```

### Expected flow

1. `example-wrapper brokered-demo` calls `latchkeyd exec` with the brokered policy.
2. `latchkeyd` verifies the wrapper, binary, policy, and operation set.
3. `latchkeyd` starts a local session socket and launches the child without raw secret env vars.
4. `example-demo-cli` requests `secret.resolve`.
5. The broker checks the live session and allowlist.
6. The broker returns the approved result and records brokered audit events.

### Example output

```json
{
  "ok": true,
  "tool": "example-demo-cli",
  "transport": "brokered",
  "args": [],
  "brokeredOperation": {
    "operation": "secret.resolve",
    "secretName": "example-token",
    "valuePreview": "la***en",
    "valueLength": 19,
    "policyName": "example-brokered",
    "policyMode": "brokered"
  }
}
```

### Narrative

This demo uses the first shipped `brokered` slice. The child starts with session metadata only, then requests one approved brokered operation. It is a narrower request boundary than `handoff`, not a universal secretless proxy.
