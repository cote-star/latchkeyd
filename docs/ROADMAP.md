# Roadmap

## Current Direction

The repo has moved from “one explicit handoff model” toward “explicit, user-chosen trust posture per task.”

That shift defines the next roadmap.

## V1.4: Trust Modes

Goal:

- make mode a first-class part of the product story and the local manifest

Deliverables:

- explicit `mode` in policies
- mode visibility in CLI output and event logs
- tracked trust-mode docs
- README and demo updates around mode choice

Success criteria:

- users can see which posture a task is using
- docs no longer imply one universal execution model

## V1.5: Oneshot Hardening

Goal:

- move `oneshot` from a narrow heuristic slice toward a stronger bounded-run contract

Deliverables:

- stronger long-lived process detection
- clearer policy and validation rules for bounded execution
- more explicit denial cases for backgrounding or daemon-like behavior

Success criteria:

- `oneshot` feels intentionally bounded, not just lightly filtered

## V2.0: Brokered Expansion

Goal:

- expand the current brokered first slice into a more complete request-time control model

Deliverables:

- richer brokered session handling
- additional brokered operations beyond `secret.resolve`
- stronger session binding and denial reporting
- wrapper/client helper guidance

Success criteria:

- `brokered` is useful for repeated bounded operations, not just a demo path

## V2.x: Ephemeral Backends

Goal:

- support provider flows where a child can receive a short-lived scoped credential instead of a longer-lived secret

Deliverables:

- credential-flow schema
- provider-specific backend planning
- lifetime-aware audit semantics

Success criteria:

- the repo can support short-lived credential paths without pretending every backend works the same way

## V3.0: Proxy / Secretless Capability Paths

Goal:

- support the highest-trust posture for workflows that should not expose raw secret material to the child at all

Deliverables:

- capability-oriented request model
- secretless or delegated operation path
- wrapper guidance for proxy mode

Success criteria:

- the strongest mode has a clear, bounded operator story

## Supporting Tracks

### Distribution

- SwiftPM remains the primary source distribution path
- GitHub Releases remain the artifact path
- Homebrew can come later if it does not distort the core shape

### Community Hardening

- contribution guide
- wider test matrix
- release automation hardening
- more reference wrappers

## What Not To Do Too Early

- build a giant policy DSL
- ship dozens of connectors
- overfit to one editor or one agent
- overpromise security guarantees
- force a Swift-native broker into registry-first release workflows
