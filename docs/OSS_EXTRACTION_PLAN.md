# OSS Extraction Plan

## Objective

Extract the generic, reusable parts of the local trust-broker system without leaking any personal or employer-specific setup.

## Keep

- secret broker core
- trust manifest model
- executable verification
- caller verification
- provider-style exec pattern
- compact validation concepts
- wrapper contract and examples
- Swift-native CLI packaging and release assumptions for the broker core

## Replace

- personal paths
- workstation-specific repo layout
- work/play naming
- employer connector names
- organization hostnames
- personal environment file conventions

## Remove

- company endpoints
- company policies
- company identities
- private repo assumptions
- personal operational docs that only make sense in one machine setup

## Generalize

- “context” into a generic policy concept
- “provider exec” into a reusable approved-tool execution primitive
- “connector wrappers” into reference wrapper examples
- “workstation validation” into a generic integrity check tool
- workstation-specific release scripts into a generic Swift release story

## Suggested Extraction Sequence

1. Copy broker core into a fresh repo.
2. Set up a clean SwiftPM package layout for the broker core.
3. Replace all hard-coded paths and names with generic config.
4. Extract trust-manifest tooling.
5. Add a single example wrapper and example manifest.
6. Add docs before adding feature breadth.
7. Add tests for drift, hash mismatch, and PATH hijack.
8. Define GitHub Release and checksum distribution before widening feature scope.
9. Publish the design repo before overbuilding.

## Red Flags Before Publishing

- repo still contains organization names
- docs imply stronger security than the code provides
- example wrappers secretly rely on local personal config
- broker surface is too broad to explain in one page
- docs imply npm/crates/PyPI are the main release path for a Swift-native broker

## Showcase Angle

This repo should showcase:

- practical security engineering judgment
- agent-systems ergonomics
- ability to turn a personal workflow into a clean reusable tool
- honesty about tradeoffs

That combination is more impressive than a flashy but vague “AI infra” repo.
