# Architecture

## Objective

Provide a reusable local secret broker for agent-mediated tool execution on a single-user machine.

The system should stay small enough to audit, narrow enough to trust, and practical enough to use in real local workflows.

## Implemented alpha shape

The current public alpha ships as a single-shot Swift CLI, not a long-running daemon.

That is an intentional product boundary for now:

- one executable
- one manifest-driven trust model
- one brokered exec path
- one validation path

The internal shape is still broker-oriented so later daemonization does not require changing the trust model.

## High-level components

### 1. Broker core

Responsibilities:

- expose a narrow command surface
- load the trust manifest
- resolve the selected secret backend
- verify trusted wrapper identity
- verify trusted downstream executable identity
- inject only approved secret env vars
- launch the approved command

Current alpha command surface:

- `status`
- `manifest init`
- `manifest refresh`
- `manifest verify`
- `exec`
- `validate`

Important limits:

- no generic secret fetch command
- no provider-specific logic in core
- no browser/session automation logic

### 2. Trust manifest

Responsibilities:

- record trusted wrapper paths and hashes
- record trusted binary paths and hashes
- define the selected secret backend
- define named secret entries
- define exec policies mapping wrapper -> binary -> secrets

Requirements:

- canonical path storage
- cryptographic hash pinning
- fail-closed verification
- human-editable format

Current alpha manifest fields:

```json
{
  "version": 1,
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
  "execPolicies": {
    "example-demo": {
      "wrapper": "example-wrapper",
      "binary": "example-cli",
      "secrets": ["example-token"]
    }
  }
}
```

### 3. Secret backends

The backend interface is intentionally small:

- availability check
- resolve named secret

Current alpha backends:

- `file` for demos, tests, CI, and first-run evaluation
- `keychain` for real macOS local use

The `file` backend is convenience infrastructure, not the preferred long-term workstation posture.

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
- one explicit safe action surface

See [`../examples/wrapper-contract.md`](../examples/wrapper-contract.md).

### 5. Validation and observability

The validation layer exists to prove the expected trust boundary still works.

Current alpha validation checks:

- manifest readability
- trust entry verification
- backend availability
- example wrapper health
- example wrapper demo success
- at least one denied-path scenario

Observability in the alpha is local JSONL event logging with no secret values.

## Control flow

### Trusted exec path

1. An agent or user invokes a wrapper.
2. The wrapper normalizes the request and calls `latchkeyd exec`.
3. `latchkeyd` loads the manifest and selected backend.
4. `latchkeyd` verifies the wrapper path and hash.
5. `latchkeyd` verifies the trusted binary path and hash.
6. If a `lookupName` is configured, `latchkeyd` resolves it in `PATH` and rejects a mismatch.
7. `latchkeyd` resolves only the approved named secret entries.
8. `latchkeyd` injects only the approved env vars and launches the trusted binary.
9. `latchkeyd` emits a local event without logging secret material.

### Failure path

If any trust, manifest, or backend check fails:

- return a structured error
- record a denial or failure event
- do not fall back to weaker behavior
- do not release the secret

## Operator model

The operator loop is intentionally explicit:

1. initialize the manifest
2. refresh trust entries when expected local paths change
3. verify trust state
4. use wrappers for approved operations
5. validate the workstation setup after changes

That loop is part of the product. The project is not trying to hide trust decisions behind automatic repair.

## Distribution shape

The broker core is treated as a Swift command-line tool:

- source consumption via Swift Package Manager
- local builds via `swift build`
- tagged release artifacts via GitHub Releases
- optional Homebrew distribution later

The architecture should not assume package-registry publication for the broker core.

## Portability strategy

V1 is macOS-first because local secret-store integration is a core part of the value.

Possible later backends:

- Linux Secret Service
- Windows Credential Manager

Those are future extensions, not part of the current alpha contract.

## Deliberately out of core

- organization-specific policy
- broad connector catalogs
- UI/browser automation logic
- generic auth discovery
- large policy DSL work
- cloud control-plane assumptions

The repo should expose auditable primitives, reference wrappers, and a clear trust model, not a giant policy platform.
