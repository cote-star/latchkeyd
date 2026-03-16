# Security Policy

## Project Maturity

`latchkeyd` is pre-alpha.

Until the broker implementation exists and has real tests, this repository should be treated as a public design and early implementation effort, not as a production-ready security control.

## Reporting

If you find a security issue in the implementation once code lands, please report it privately before opening a public issue.

For now, the most valuable security feedback is:

- flaws in the trust model
- overclaims in the documentation
- design choices that could encourage unsafe deployment assumptions

## Scope

The intended security properties are documented in [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md).

In particular, this project is not intended to solve:

- same-user full compromise
- OS isolation
- browser session compromise
- unrestricted endpoint policy reasoning inside the broker core

If you believe the docs imply stronger guarantees than the design actually provides, that is a security issue worth raising.
