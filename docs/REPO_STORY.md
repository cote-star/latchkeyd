# Repo Story

## One-Sentence Pitch

`latchkeyd` is a local trust broker that lets coding agents use real tools without giving them uncontrolled access to your credential surface.

## Why People Will Care

The local agent workflow problem is common:

- people want agents to do useful work
- useful work touches real systems
- real systems need credentials
- most local setups solve this with trust and vibes

This repo offers a sharper answer:

- approved wrappers
- verified callers
- pinned executables
- fail-closed secret release

## Why This Can Be A Standout Repo

It demonstrates a rare combination:

- strong systems taste
- realistic local security posture
- clean threat-model writing
- practical agent workflow design

It is the kind of repo that makes other engineers say, “yes, this person has actually thought through how local agents should work.”

## Good Public Narrative

“I built a local secret broker for agentic development because I wanted real automation without turning my machine into an unbounded credential playground.”

That story is concrete, relevant, and credible.

## Distribution Narrative

The public release story should also be clear:

- the broker core is a Swift-native CLI
- source distribution should work through Swift Package Manager
- installable binaries should come from GitHub Releases
- Homebrew can come later if the project earns that convenience layer

That framing keeps the repo honest. It signals that the project is designed around the language and runtime it actually uses, instead of forcing a generic package-registry story where it does not belong.
