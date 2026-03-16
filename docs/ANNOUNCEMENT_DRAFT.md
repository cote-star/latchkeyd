# Announcement Draft

`latchkeyd` is now public.

It is a local trust gate and secret broker for agent-driven developer workflows.

The project exists for a simple reason: local coding agents are useful, but most setups still force a bad choice between "too little access to help" and "too much access to trust."

`latchkeyd` takes a local-first approach:

- secrets stay local
- wrappers and binaries are trust-pinned
- secret release is explicit
- drift and hijack cases fail closed

What it is not:

- not a sandbox
- not full endpoint security
- not "secure agents solved"

What it is:

- a narrower, more auditable way to let local agents use real tools with real credentials

Current alpha scope:

- Swift CLI broker
- manifest-driven trust model
- file and keychain backends
- example wrapper and demo CLI
- validation tooling
- local JSONL event logs

Suggested short post:

> Open-sourced `latchkeyd`: a local trust gate for agent workflows. It keeps secrets local, pins trust to wrappers and binaries, and fails closed on drift or hijack instead of turning your shell into a credential vending machine.

Suggested close:

If you use local agents with real credentials and want a more explicit secret handoff model, this repo is for you.
