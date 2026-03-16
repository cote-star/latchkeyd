# Wrapper Contract

Reference wrappers should provide:

- `--health`
- `--whoami`
- `--version`
- `--discover`

Reference wrappers should:

- validate input before broker access
- normalize identifiers from URLs or user-facing references
- keep remote access bounded and discoverable
- return structured success and error JSON
- fail closed on unknown operations

Reference wrappers should not:

- expose generic secret lookup
- fall back to browser-first auth paths silently
- scrape config or env state as a first-line access strategy
- auto-expand into write behavior
