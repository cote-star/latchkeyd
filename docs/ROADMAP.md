# Roadmap

## V0: Public Design Repo

Goal:

- publish the concept, architecture, threat model, and examples

Deliverables:

- polished README
- architecture doc
- threat model
- extraction plan
- example manifest
- wrapper contract

Success criteria:

- the repo communicates the idea clearly
- the scope is credible
- the threat model is honest

## V1: Minimal Working Broker

Goal:

- ship a usable macOS-first broker with trust verification and one example exec path

Deliverables:

- broker binary
- SwiftPM package layout
- trust manifest refresh/status tool
- example wrapper
- example validation checks

Success criteria:

- verified trusted wrapper can launch a trusted CLI with injected secret
- untrusted caller is denied
- hash mismatch is denied
- path hijack is denied

## V1.1: Swift Release Shape

Goal:

- make the broker easy to build, consume, and install as a Swift-native project

Deliverables:

- `Package.swift`
- reproducible local build instructions
- tagged GitHub Release plan
- artifact and checksum plan

Success criteria:

- a user can build the broker with standard Swift tooling
- a tagged release can produce installable binaries
- the project clearly communicates SwiftPM as the primary source distribution path

## V1.2: Reference Wrapper Kit

Goal:

- make it easier for others to build safe wrappers around their own tooling

Deliverables:

- shell helper library
- wrapper templates
- discoverability conventions
- error contract examples

## V1.3: Local Observability

Goal:

- show why something was denied and help users debug trust drift

Deliverables:

- JSONL event sink
- compact local query helper
- drift-focused validation output

## V2: Portable Secret Backends

Goal:

- expand beyond macOS-first installations

Deliverables:

- backend abstraction
- Linux and Windows backend plans
- compatibility matrix

## V3: Community Hardening

Goal:

- turn the project from a personal extraction into a durable open-source tool

Deliverables:

- contribution guide
- test matrix
- GitHub Release automation
- optional Homebrew packaging
- reference integrations

## What Not To Do Too Early

- build a giant policy DSL
- ship dozens of connectors
- overfit to one editor or one agent
- overpromise security guarantees
- force a Swift-native broker into npm/crates/PyPI release workflows
