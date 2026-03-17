# Architecture

## Objective

Provide a reusable local trust broker for agent-mediated tool execution on a single-user machine.

The system should stay:

- small enough to audit
- narrow enough to trust
- practical enough to use in real local workflows

## Implemented Shape

The current repo ships as a single-shot Swift CLI, not a long-running daemon.

That boundary is still intentional:

- one executable
- one manifest-driven trust root
- one validation path
- multiple policy modes

The internal shape is still broker-oriented so later daemonization does not require changing the trust model.

## High-Level Components

### 1. Broker core

Responsibilities:

- expose a narrow command surface
- load the trust manifest
- resolve the selected secret backend
- verify trusted wrapper identity
- verify trusted downstream executable identity
- enforce the selected execution mode
- emit structured errors and audit events

Current command surface:

- `status`
- `manifest init`
- `manifest refresh`
- `manifest verify`
- `exec`
- `validate`

### 2. Trust manifest

Responsibilities:

- record trusted wrapper paths and hashes
- record trusted binary paths and hashes
- define the selected secret backend
- define named secret entries
- define reusable brokered operation sets
- define exec policies with explicit mode

Requirements:

- canonical path storage
- cryptographic hash pinning
- fail-closed verification
- human-editable format

Current repo shape:

```json
{
  "version": 2,
  "backend": {
    "type": "file",
    "filePath": "/abs/path/to/demo-secrets.json"
  },
  "wrappers": {
    "example-wrapper": {
      "path": "/abs/path/to/example-wrapper",
      "sha256": "..."
    }
  },
  "binaries": {
    "example-cli": {
      "path": "/abs/path/to/example-cli",
      "sha256": "...",
      "lookupName": "example-demo-cli"
    }
  },
  "secrets": {
    "example-token": {
      "envVar": "LATCHKEYD_EXAMPLE_TOKEN",
      "backendKey": "example-token"
    }
  },
  "operationSets": {
    "example-brokered-ops": {
      "operations": [
        {
          "name": "secret.resolve",
          "allowedSecrets": ["example-token"],
          "allowedResponseFields": ["secretName", "value", "lifetimeSeconds"]
        }
      ]
    }
  },
  "execPolicies": {
    "example-demo": {
      "mode": "handoff",
      "wrapper": "example-wrapper",
      "binary": "example-cli",
      "secrets": ["example-token"]
    },
    "example-brokered": {
      "mode": "brokered",
      "wrapper": "example-wrapper",
      "binary": "example-cli",
      "secrets": ["example-token"],
      "operationSet": "example-brokered-ops"
    }
  }
}
```

### 3. Secret backends

The backend interface stays intentionally small:

- availability check
- resolve named secret

Current backends:

- `file` for demos, tests, CI, and first-run evaluation
- `keychain` for real macOS local use

### 4. Wrappers

Responsibilities:

- normalize user or agent input
- keep the allowed command surface small and discoverable
- fail closed on unknown operations
- call `latchkeyd exec` instead of resolving secrets themselves

Reference wrapper contract:

- `--health`
- `--whoami`
- `--version`
- `--discover`
- explicit safe action surfaces such as `demo` and `brokered-demo`

See [`../examples/wrapper-contract.md`](../examples/wrapper-contract.md).

### 5. Validation and observability

The validation layer exists to prove the expected trust boundary still works.

Current validation checks:

- manifest readability
- trust entry verification
- mode-aware manifest validation
- backend availability
- example wrapper health
- example wrapper handoff demo success
- example wrapper brokered demo success
- at least one denied-path scenario

Observability is local JSONL event logging with no secret values.

## Execution Modes

The repo now treats execution mode as a first-class architectural boundary.

### `handoff`

What enters the child:

- approved secret env vars at launch

What the broker still controls:

- pre-launch wrapper verification
- pre-launch binary verification
- policy scope
- audit event emission

What the broker stops controlling:

- what the child does with the secret after launch

### `oneshot`

What enters the child:

- approved secret env vars at launch

What the broker still controls:

- everything from `handoff`
- a narrow first slice of long-lived argument rejection

What the broker stops controlling:

- post-handoff retention inside the child

### `brokered`

What enters the child:

- session metadata only at launch

What the broker still controls:

- wrapper verification
- binary verification
- operation-set validation
- live session checks
- request-time allowlist enforcement
- per-request audit events

What the broker stops controlling:

- same-user compromise outside its own trust boundary
- universal tool semantics

### `ephemeral`

Planned mode.

Intent:

- hand the child a scoped short-lived credential instead of a longer-lived root secret

### `proxy`

Planned mode.

Intent:

- avoid direct raw secret visibility in the child for high-risk workflows

## Control Flow

### Handoff path

1. A wrapper calls `latchkeyd exec`.
2. `latchkeyd` loads the manifest and selected backend.
3. `latchkeyd` verifies the wrapper path and hash.
4. `latchkeyd` verifies the trusted binary path and hash.
5. `latchkeyd` resolves only the approved named secret entries.
6. `latchkeyd` injects only the approved env vars.
7. `latchkeyd` launches the trusted binary.
8. `latchkeyd` emits an audit event.

### Brokered path

1. A wrapper calls `latchkeyd exec` for a brokered policy.
2. `latchkeyd` loads the manifest and verifies wrapper, binary, mode, and operation set.
3. `latchkeyd` creates a local brokered session and Unix socket.
4. `latchkeyd` launches the trusted child without raw secret env vars.
5. The child receives only session metadata.
6. The child requests an approved operation such as `secret.resolve`.
7. The broker verifies session identity, operation allowlist, and secret binding.
8. The broker returns the approved result and records audit events.

## Failure Path

If any trust, manifest, backend, mode, or brokered-session check fails:

- return a structured error
- record a denial or failure event
- do not fall back to weaker behavior
- do not release the secret

## Operator Model

The operator loop is intentionally explicit:

1. initialize the manifest
2. refresh trust entries when expected local paths change
3. verify trust state
4. choose the right mode for the task
5. use wrappers for approved operations
6. validate the workstation setup after changes

The project is not trying to hide trust decisions behind automatic repair.

## Distribution Shape

The broker core is a Swift command-line tool:

- source consumption via Swift Package Manager
- local builds via `swift build`
- tagged release artifacts via GitHub Releases
- optional Homebrew distribution later

## Portability Strategy

V1 remains macOS-first because local secret-store integration is part of the value.

Possible later backends:

- Linux Secret Service
- Windows Credential Manager

Those are future extensions, not part of the current contract.

## Deliberately Out Of Core

- organization-specific policy
- broad connector catalogs
- UI or browser automation logic
- generic auth discovery
- giant policy DSL work
- cloud control-plane assumptions

The repo should expose auditable primitives, reference wrappers, and clear trust boundaries, not a large policy platform.
