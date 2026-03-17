# Demo Asset Generation

`latchkeyd` keeps its terminal demo stills as generated browser-rendered assets instead of manually maintained screenshots.

Current generated assets:

- `terminal-happy-path.webp`
- `terminal-denial.webp`

Current supporting assets:

- `before-after-anim.webp`
- `attack-surface-anim.webp`
- `architecture-flow.png`
- `share-card.svg`

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

- `before-after-anim.webp`: `Animated before-and-after showing broad local credential exposure replaced by explicit trust-mode selection and trust-mediated execution.`
- `attack-surface-anim.webp`: `Animation showing how a local trust broker narrows prompt-injection fallout by verifying wrapper and binary before credential-backed access.`
- `architecture-flow.png`: `Architecture diagram showing wrapper, local trust broker, trusted binary, and local secret backend flow.`
- `terminal-happy-path.webp`: `Terminal still showing a successful trusted handoff through latchkeyd.`
- `terminal-denial.webp`: `Terminal still showing a trust denial before the secret is released.`
- `share-card.svg`: `Share card for latchkeyd, a macOS local trust broker with explicit trust modes.`
