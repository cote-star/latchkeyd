# Threat Model

## Goal

Reduce accidental overexposure of local credentials in agent-assisted development workflows.

`latchkeyd` is meant to narrow the trust boundary around approved local tool execution. It is not meant to claim total workstation security.

## What the project is trying to reduce

### 1. Prompt-driven tool misuse

An agent takes a risky path such as:

- direct token use
- raw API calls
- ad-hoc CLI auth probing
- browser-first access where a safer wrapper exists

`latchkeyd` reduces this by making approved wrapper paths easy and secret release conditional.

### 2. PATH hijack of downstream tools

A malicious or accidental binary earlier in `PATH` captures a secret intended for a trusted CLI.

`latchkeyd` reduces this with:

- canonical path resolution
- trusted binary hash pinning
- optional `lookupName` resolution checks

### 3. Wrapper drift or tampering

A trusted wrapper changes in ways that broaden access or change request shape.

`latchkeyd` reduces this with trusted wrapper verification against canonical path and hash.

### 4. Silent fallback to weaker auth behavior

A wrapper or workflow falls back to:

- config scraping
- environment probing
- browser interaction
- looser auth paths

The intended `latchkeyd` posture is fail closed instead.

### 5. Prompt-injection fallout

Remote content may influence an agent to attempt sensitive local actions.

`latchkeyd` does not prevent the model from producing a bad idea. What it does is reduce the chance that a bad idea automatically turns into broad credential exposure:

- wrappers stay narrow
- secret release is explicit
- both wrapper and binary are verified
- broad inherited env state is avoided

## What the project does not solve

### 1. Same-user compromise

If a malicious process already has broad same-user access, this project does not provide full protection.

### 2. Full endpoint policy enforcement

The broker does not understand the business meaning of every API path or CLI action.

Bounded-read logic and endpoint allowlists belong in wrappers or connector libraries.

### 3. Browser or session compromise

If a browser-backed CLI or session store is compromised, `latchkeyd` cannot secure it after the fact.

### 4. OS isolation

This project is not a VM, container runtime, sandbox, or MAC framework.

### 5. Safe autonomous agents as a general claim

The project should never be presented as "secure agents solved."

## Deployment assumption

The default audience is a single-user developer workstation where:

- the operator wants safer local agent workflows
- the operator accepts local trust-pinning and fail-closed behavior
- stronger isolation, when needed, is handled outside the project

## Security principles

- no generic secret fetch
- narrow command surface
- explicit trust roots
- no silent auth fallback
- secret release only after caller and callee verification
- local operator control over trust refresh

## Safe framing for open source

The project should be framed as:

- safer local agent tooling
- explicit trust mediation for approved workflows
- practical defense in depth for single-user workstations
- a local-first response to credential sprawl in agent workflows

The project should not be framed as:

- full endpoint security
- enterprise policy platform completeness
- universal prompt-injection prevention
- same-user compromise protection
