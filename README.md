# latchkeyd

`latchkeyd` is a local secret broker and trust gate for agent-driven developer workflows.

It lets agents use real tools without turning your shell into a generic credential vending machine.

## Current Status

`latchkeyd` is pre-alpha.

This repository is intentionally being published design-first:

- the concept and threat model are documented
- the V1 architecture and scope are defined
- the broker implementation is not shipped yet
- the repo will evolve in public as the first working build lands

## Why this exists

Local agentic development is useful right up until the model starts improvising with:

- raw API calls
- browser-first auth flows
- direct token usage
- ad-hoc CLI discovery
- credential probing through config and env state

Most local setups have the same gap: either the agent gets too little access to be useful, or too much access to be safe.

`latchkeyd` is aimed at the middle:

- secrets stay in the OS key store
- trusted callers are verified before secret release
- tool execution is mediated through explicit policy
- read-only and bounded operations are easy to support
- local workflows stay fast and scriptable

## Project Positioning

`latchkeyd` is not:

- a sandbox
- a container runtime
- malware protection
- a replacement for OS isolation
- a universal policy engine

`latchkeyd` is:

- a local broker for secret-scoped tool execution
- a trust-pinning layer for agent wrappers and approved CLIs
- a practical guardrail for single-user agentic development workstations

## Who It Is For

- engineers using local coding agents with real company or personal credentials
- advanced individual developers who want safer local automation
- teams building internal agent tooling on top of existing CLIs and API wrappers

## Core Idea

An agent should not get direct access to long-lived credentials just because it can run shell commands.

Instead:

1. The agent calls a wrapper.
2. The wrapper proves context and intent.
3. `latchkeyd` verifies the calling path and the target executable.
4. `latchkeyd` releases only the secret needed for that exact approved action.
5. The tool runs and returns output without exposing the general credential surface.

## Product Shape

Planned capabilities:

- local secret broker with small, explicit command surface
- trust manifest for approved wrappers and executables
- path and hash pinning for downstream CLIs
- provider-style `exec` mode for running approved tools with injected credentials
- policy-friendly integration for read-only wrappers and bounded API access
- local audit logging hooks
- compact validation command for workstation integrity checks

## Distribution Model

`latchkeyd` should be treated as a Swift-native project, not a registry package project.

Planned public distribution paths:

- source distribution via GitHub and Swift Package Manager
- signed release binaries attached to GitHub Releases
- Homebrew formula or tap later for install convenience

Planned non-goals for the broker itself:

- publishing the core broker to npm
- publishing the core broker to crates.io
- publishing the core broker to PyPI

Those registries may still matter for example wrappers, demos, or companion tooling in other languages, but they are not the primary release path for the broker core.

## Design Principles

- Boring over magical
- Fail closed
- Keep trust boundaries obvious
- Prefer small contracts over flexible abstractions
- Make the secure path the shortest path
- Support real developer workflows without pretending to be a full sandbox

## Non-Goals

- fully preventing a malicious same-user process
- replacing macOS Keychain, 1Password, or enterprise secret managers
- securing arbitrary browser sessions
- allowing unrestricted generic shell access with secrets in scope
- solving multi-user workstation isolation

## Differentiators

- built for local agent workflows, not generic app secret injection
- trust-pins both wrappers and underlying CLIs
- optimized for workstation ergonomics, not only enterprise platforms
- designed to pair with wrapper-first tooling rather than replace it

## Initial Open Source Scope

Ship first:

- broker core
- trust manifest tooling
- example wrapper integration
- validation tooling
- reference docs and threat model
- SwiftPM package definition and local build story
- GitHub Release distribution plan for signed binaries

Do not ship first:

- personal workstation conventions
- employer-specific connectors
- organization-specific policies
- personal work/play routing assumptions
- package-registry publishing paths that do not match the Swift broker core

## How To Read This Repo

Start here:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the system shape
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) for the security framing
- [`docs/ROADMAP.md`](docs/ROADMAP.md) for the implementation sequence
- [`docs/OSS_EXTRACTION_PLAN.md`](docs/OSS_EXTRACTION_PLAN.md) for what is generic versus workstation-specific
- [`examples/wrapper-contract.md`](examples/wrapper-contract.md) for the wrapper-facing contract

If you are evaluating whether the repo is worth following, the key question is simple:

can a small local broker make agent workflows safer without becoming a giant policy platform?

That is the problem this project is trying to answer.

## Near-Term Plan

The first implementation milestone is intentionally narrow:

1. ship a minimal Swift broker with a tiny command surface
2. verify trusted callers and trusted downstream binaries
3. demonstrate one approved exec flow end to end
4. deny path hijacks, caller drift, and hash drift cleanly
5. add validation and observability before feature breadth

## Proposed Repo Layout

```text
latchkeyd/
  README.md
  docs/
    ARCHITECTURE.md
    THREAT_MODEL.md
    ROADMAP.md
    OSS_EXTRACTION_PLAN.md
    REPO_STORY.md
  examples/
    example-manifest.json
    wrapper-contract.md
  src/
  tests/
```

## Name Rationale

`latchkeyd` suggests a local key-holder that opens only the right door for the right caller.

It is distinctive, short, and naturally maps to a small broker daemon or broker-style utility without sounding like another generic "agent bridge" package.

## V1 Demo Story

A strong first public demo should show:

1. A local agent tries to use a trusted wrapper.
2. The wrapper invokes `latchkeyd`.
3. The broker verifies trust and launches the approved CLI with the minimum secret scope.
4. A path-hijack or untrusted caller attempt fails closed.
5. Validation proves the workstation is still in a good state.

That demo would communicate both engineering quality and agent-systems judgment.

## Contributing

Discussion and design feedback are welcome early.

Implementation contributions will be most useful once the first Swift package layout and broker skeleton are in place.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).

## License

MIT. See [`LICENSE`](LICENSE).
