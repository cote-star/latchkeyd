# Repo Metadata

This file is the source of truth for the repo-side discoverability layer.

It exists because some public-facing metadata lives outside tracked files:

- GitHub repo description
- homepage URL
- GitHub topics
- social/share metadata on any future site or launch page

Use this file when updating those surfaces so the public message stays aligned with the repo.

## GitHub About

### Description

Primary:

- `macOS local trust broker for agent-mediated tool execution with explicit trust modes, trust-pinned wrappers, and fail-closed credential handoff.`

Short fallback:

- `macOS local trust broker with explicit trust modes for local agent tooling.`

### Homepage

Preferred order:

1. release landing page if one exists
2. repo URL
3. maintainer landing page only if you intentionally want that as the canonical public homepage

### Topics

Recommended GitHub topics:

- `macos`
- `swift`
- `swift-package-manager`
- `cli`
- `security`
- `developer-tools`
- `agent-tooling`
- `secrets-management`
- `local-first`
- `devsecops`
- `trust-boundary`
- `prompt-injection`
- `keychain`
- `wrapper`
- `broker`

## Search Language

These phrase families should appear naturally in README, docs, release notes, and launch posts:

- local trust broker
- trust-pinned wrapper
- trust-pinned binary
- explicit handoff
- trust modes
- handoff mode
- oneshot mode
- brokered mode
- fail closed
- local-first secret broker
- safer local agent tooling
- prompt-injection fallout

Avoid keyword stuffing. Use these terms where they are actually true.

## Social / Share Metadata

If a docs site or landing page exists later, use:

### Title

- `Choose the trust posture before a local tool gets credential-backed access`

### Description

- `latchkeyd is a macOS local trust broker for agent workflows with explicit trust modes, trust-pinned wrappers, and fail-closed execution.`

### Suggested Open Graph fields

- `og:title`: same as title above
- `og:description`: same as description above
- `og:image`: share card image
- `og:image:alt`: `Share card for latchkeyd, a macOS local trust broker with explicit trust modes.`

### Suggested Twitter/X fields

- `twitter:title`: same as title above
- `twitter:description`: same as description above
- `twitter:image`: share card image
- `twitter:image:alt`: same as the Open Graph image alt text

## Structured Data For A Future Site

If a landing page or docs mirror exists later, use `SoftwareSourceCode` with:

- `name`: `latchkeyd`
- `codeRepository`: repo URL
- `programmingLanguage`: `Swift`
- `runtimePlatform`: `macOS`
- `license`: `MIT`
- `description`: the primary repo description above
- `keywords`: the search language terms above

## Release Metadata

Recommended release title pattern:

- `vX.Y.Z-alpha.N: trust modes`

Recommended proof bullets:

- hosted CI passed
- hosted release passed
- binary and checksum attached
- offline smoke and validation green

## Asset Metadata

Each promoted asset should have:

- filename
- title
- short description
- alt text
- primary keyword
- support keywords

Examples:

### Hero asset

- primary keyword: `local trust broker`
- support keywords:
  - `trust modes`
  - `explicit handoff`
  - `agent tooling`

### Architecture diagram

- primary keyword: `trust-pinned execution flow`
- support keywords:
  - `wrapper`
  - `binary verification`
  - `brokered mode`

## Maintainer Promotion

The repo includes a light maintainer-promotion layer.

Rules:

- product proof comes first
- creator promotion stays secondary
- QR usage belongs on images or animations only, not in the core markdown flow

Confirmed QR rule:

- bottom-right corner only
- no overlap with the primary visual
- keep the QR small
- make the maintainer name more visually prominent than the QR itself

## Geo Metadata

Do not invent geo facts in tracked files.

Only add:

- city
- region
- country
- timezone

after confirming the values you want public.
