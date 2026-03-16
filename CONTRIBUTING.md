# Contributing

`latchkeyd` is still pre-alpha and design-first.

That means the most useful contributions right now are:

- threat-model review
- architecture feedback
- interface simplification
- demo and validation ideas
- careful implementation proposals for the first Swift milestone

## Before Opening A PR

Please keep changes aligned with the current project shape:

- narrow command surface
- fail-closed behavior
- no generic secret vending
- clear trust boundaries
- honest documentation about tradeoffs and non-goals

## Early Contribution Priorities

Good first implementation areas:

- Swift package layout
- trust manifest parsing and verification
- canonical path handling
- digest verification
- fixture-based tests for denial cases
- example wrapper integration

Please avoid broadening scope too early with:

- lots of connectors
- editor-specific integrations
- a large policy DSL
- claims that exceed the current threat model

## Development Notes

The intended first implementation path is:

1. a small Swift command-line broker
2. a tiny manifest format
3. one end-to-end example exec flow
4. validation and observability

If you want to propose a larger direction change, open an issue or discussion first so the core stays coherent.
