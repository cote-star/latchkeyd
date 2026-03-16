# Wrapper Contract

Reference wrappers should provide:

- `--health`
- `--whoami`
- `--version`
- `--discover`
- one explicit safe action surface, not a generic shell pass-through

Reference wrappers should:

- validate input before broker access
- normalize identifiers from URLs or user-facing references
- keep remote access bounded and discoverable
- return structured success and error JSON
- fail closed on unknown operations
- call `latchkeyd exec` for approved command launch instead of resolving secrets themselves
- pass their own trusted wrapper path as the caller identity input to the broker

Reference wrappers should not:

- expose generic secret lookup
- fall back to browser-first auth paths silently
- scrape config or env state as a first-line access strategy
- auto-expand into write behavior
- print secret values or derived values that are effectively reversible

The alpha example wrapper lives at [`examples/bin/example-wrapper`](bin/example-wrapper) and demonstrates the intended contract.
