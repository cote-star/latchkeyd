# Architecture

## Objective

Provide a reusable local secret broker for agent-mediated tool execution on a single-user machine.

The architecture should be simple enough to audit and narrow enough to trust.

## High-Level Components

### 1. Broker

Responsibilities:

- receive a narrow set of subcommands
- resolve secret identifiers to OS-backed secret storage
- verify trusted caller identity
- verify trusted downstream executable identity
- exec the approved command with minimal credential exposure

Desirable implementation traits:

- compiled implementation for the broker core
- Swift-first implementation is a good fit for the broker core
- explicit subcommands instead of dynamic behavior
- no generic “get any secret” API

### 2. Trust Manifest

Responsibilities:

- record approved caller paths
- record approved executable paths
- record expected hashes
- support refresh and status verification

Requirements:

- canonical paths only
- cryptographic hash pinning
- human-readable format
- fail-closed verification

### 3. Wrappers

Responsibilities:

- normalize task input
- enforce context and policy before broker access
- keep command surfaces small and discoverable
- make approved behavior easier than improvised behavior

Wrapper contract:

- `--health`
- `--whoami`
- `--version`
- `--discover`
- structured success and error JSON

### 4. Validation Layer

Responsibilities:

- verify trusted binaries and scripts are present
- verify boundary enforcement works
- verify path hijacks are rejected
- verify logs and docs still match the actual behavior

### 5. Observability

Responsibilities:

- emit local structured events
- support operational queries
- help detect blocked, denied, or drifted states

## Control Flow

### Trusted exec path

1. Agent invokes a wrapper.
2. Wrapper validates context and request shape.
3. Wrapper resolves the intended tool and calls the broker.
4. Broker verifies:
   - broker integrity
   - trusted caller path and hash
   - trusted downstream executable path and hash
   - allowed subcommand shape
5. Broker injects only the needed credential material.
6. Broker `exec`s the approved command.

### Failure path

If any trust or policy check fails:

- return a structured error
- do not fall back to a weaker access path
- do not release the secret

## Reference V1 Interfaces

### Broker commands

- `status`
- `provider-exec`
- `http-get`

V1 should stay intentionally small.

## Build And Distribution Shape

The broker core should be treated as a Swift command-line tool with a release flow that matches Swift ecosystems:

- source consumption through Swift Package Manager
- local builds via `swift build`
- installable release artifacts produced from tagged builds
- optional Homebrew distribution later for ergonomic install/update

That means the architecture should not assume language-package-registry publication for the broker itself. Registry publishing may still be appropriate for companion tooling or demo integrations, but the broker core should optimize for SwiftPM and release binaries.

### Example manifest shape

```json
{
  "version": 1,
  "wrappers": {
    "example-wrapper": {
      "path": "/abs/path/to/example-wrapper",
      "sha256": "..."
    }
  },
  "binaries": {
    "example-cli": {
      "path": "/abs/path/to/example-cli",
      "sha256": "..."
    }
  }
}
```

## Portability Strategy

V1 can be macOS-first because OS key store integration is a major part of the value.

Cross-platform can come later with pluggable secret backends:

- macOS Keychain first
- Linux Secret Service later
- Windows Credential Manager later

## What To Keep Out Of Core

- organization-specific policy
- repo-specific context models
- UI/browser automation logic
- broad connector catalogs
- generic auth discovery
- registry-publishing assumptions that do not match the broker language/runtime

The project should expose primitives, reference wrappers, and policy examples, not ship someone else's workstation worldview.
