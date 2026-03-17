# Demo Asset Generation

`latchkeyd` keeps its promoted visual assets as tracked image files so the README, docs, and share surfaces stay consistent.

Current terminal stills:

- `terminal-brokered-demo.png`
- `terminal-brokered-denial.png`

Current supporting assets:

- `hero-before-after-trust-modes.png`
- `diagram-execution-modes.png`
- `attack-surface-anim.webp`
- `architecture-flow.png`
- `share-card-trust-modes.png`
- `share-card-creator-qr.png`
- `qr-code.png`

## Regenerate

Install the renderer dependency once:

```bash
npm install
```

Then run:

```bash
npm run render:demo-assets
```

The renderer prefers a locally installed Google Chrome browser through Puppeteer and falls back to Puppeteer's managed browser when needed.

## Why this exists

- keeps the demos visually consistent
- makes CLI stills easier to refresh when output changes
- matches the repo's warm-paper visual system without hand-editing SVG text

## QR Branding Rule

When the repo adds QR-based branding later:

- QR marks only go on animations or images
- place them in the bottom-right corner
- do not let the QR overlap the primary visual content
- keep the QR small
- keep the maintainer name visually more prominent than the QR itself
- do not place QR branding on every asset

This promotion layer should stay secondary to product proof.

## Alt Text Guidance

Use descriptive alt text for promoted assets.

Recommended starting points:

- `hero-before-after-trust-modes.png`: `Before-and-after visual showing broad local credential exposure replaced by explicit trust-mode selection and trust-mediated execution.`
- `diagram-execution-modes.png`: `Diagram showing handoff, oneshot, brokered, ephemeral, and proxy execution modes with what the child receives and what the broker still controls.`
- `attack-surface-anim.webp`: `Animation showing how a local trust broker narrows prompt-injection fallout by verifying wrapper and binary before credential-backed access.`
- `architecture-flow.png`: `Architecture diagram showing wrapper, local trust broker, trusted binary, and local secret backend flow.`
- `terminal-brokered-demo.png`: `Terminal still showing a successful brokered request through latchkeyd.`
- `terminal-brokered-denial.png`: `Terminal still showing a denied brokered operation before secret access is returned.`
- `share-card-trust-modes.png`: `Share card for latchkeyd, a macOS local trust broker with explicit trust modes.`
- `share-card-creator-qr.png`: `Creator card for latchkeyd with maintainer attribution and a small bottom-right QR code.`
