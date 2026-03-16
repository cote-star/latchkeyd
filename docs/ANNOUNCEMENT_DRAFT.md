# Announcement Draft

## Short Post

Open-sourced `latchkeyd`: a local trust gate for agent workflows.

If you use local coding agents with real credentials, `latchkeyd` gives you a narrower handoff:

- secrets stay local
- wrappers and binaries are trust-pinned
- drift, hijack, and bypass fail closed

Repo:

`https://github.com/cote-star/latchkeyd`

## Medium Post

Local coding agents are useful right up until they get broad access to real credentials.

`latchkeyd` is a local trust gate and secret broker for that problem:

- secrets stay local
- wrappers and binaries are trust-pinned
- secret release is explicit
- drift, hijack, and bypass fail closed

It is not a sandbox, not full endpoint security, and not "secure agents solved."

It is a narrower, more auditable way to let local agents use real tools with real credentials on a developer workstation.

Current alpha includes:

- Swift CLI broker
- manifest-driven trust model
- file and keychain backends
- example wrapper and demo CLI
- validation tooling
- local JSONL event logs

## Launch Thread Skeleton

1. Problem:
   local agents usually get either too little access to help or too much access to trust.
2. Mechanism:
   wrapper -> `latchkeyd` -> trusted tool, with explicit secret handoff.
3. Proof:
   before/after hero plus denial demos.
4. Limits:
   not a sandbox, not same-user compromise protection, not universal prompt-injection prevention.
5. Close:
   if you use local agents with real credentials and want a more explicit trust boundary, this repo is for you.
