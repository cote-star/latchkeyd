# Threat Model

## Goal

Reduce accidental overexposure of local credentials in agent-assisted development workflows.

## Primary Threats Addressed

### 1. Prompt-driven tool misuse

An agent chooses a risky path such as:

- raw API calls
- direct token use
- ad-hoc CLI auth probing
- browser-first access where a safer wrapper exists

`latchkeyd` reduces this by making approved wrapper paths easy and secret release conditional.

### 2. PATH hijack of downstream tools

A malicious or accidental binary earlier in `PATH` captures secrets intended for a trusted CLI.

`latchkeyd` addresses this with canonical path resolution and hash pinning.

### 3. Script drift or wrapper tampering

A trusted wrapper changes in ways that broaden access or alter request shape.

`latchkeyd` addresses this with trusted caller verification against a manifest.

### 4. Silent fallback to weaker behavior

The wrapper or workflow falls back to:

- environment probing
- config scraping
- browser interaction
- looser auth paths

`latchkeyd` should fail closed instead.

## Threats Explicitly Not Solved

### 1. Same-user compromise

If a malicious process already has unrestricted same-user access, this project does not provide full protection.

### 2. Full endpoint policy enforcement

The broker alone does not know the business meaning of every API path.

Endpoint allowlists and bounded-read logic belong in wrappers or connector libraries.

### 3. Browser session compromise

If a browser-backed CLI or session store is compromised, `latchkeyd` cannot magically secure it.

### 4. OS isolation

This project is not a VM, container, sandbox, or MAC framework.

## Deployment Assumption

The default audience is a single-user developer workstation where:

- the operator wants safer agent workflows
- the operator accepts local trust-pinning and fail-closed behavior
- stronger isolation, when needed, is handled outside the project

## Security Principles

- no generic secret fetch
- narrow command surface
- explicit trust roots
- no silent auth fallback
- policy at the wrapper edge
- secret release only after caller and callee verification

## Safe Framing For OSS

The project should never be marketed as “secure agents solved.”

It should be framed as:

- safer local agentic tooling
- trust mediation for approved workflows
- practical defense in depth for single-user workstations
