# Announcement Draft

## Short Post

Open-sourced `latchkeyd`: a macOS local trust broker for agent workflows.

If you use local coding agents with real credentials, `latchkeyd` lets you choose the trust posture before a local tool gets access:

- secrets stay local
- wrappers and binaries are trust-pinned
- drift, hijack, and bypass fail closed
- mode choice is explicit

Repo:

`https://github.com/cote-star/latchkeyd`

## Medium Post

Local coding agents are useful right up until credential handoff becomes broad, ambient, and hard to reason about.

`latchkeyd` is a local trust broker for that problem:

- secrets stay local
- wrappers and binaries are trust-pinned
- the trust posture is explicit
- drift, hijack, and bypass fail closed

The current direction is no longer just “explicit handoff before execution.”

It is:

- explicit, user-chosen trust posture per task

The repo now has a trust-mode family:

- `handoff`
- `oneshot`
- `brokered`
- future `ephemeral`
- future `proxy`

This release narrows credential handoff. It does not claim full confinement after handoff.

It is not:

- a sandbox
- full endpoint security
- same-user compromise protection
- universal prompt-injection prevention

It is a narrower, more auditable way to let local agents use real tools with real credentials on a developer workstation.

Current repo scope includes:

- Swift CLI broker
- manifest-driven trust model
- explicit policy modes
- file and keychain backends
- reference wrapper and demo CLI
- validation tooling
- local JSONL event logs
- offline and release-parity proof scripts

## Launch Thread Skeleton

1. Problem:
   local agents usually get either too little access to help or too much access to trust.
2. Mechanism:
   wrapper -> local trust broker -> trusted tool, with explicit mode choice.
3. Proof:
   hero asset, trust modes diagram, brokered request demo, denied brokered request demo.
4. Limits:
   not a sandbox, not same-user compromise protection, not universal prompt-injection prevention.
5. Close:
   if you use local agents with real credentials and want a more explicit trust boundary, this repo is for you.
