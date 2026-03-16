# Demo Asset Generation

`latchkeyd` keeps its terminal demo stills as generated browser-rendered assets instead of manually maintained screenshots.

Current generated assets:

- `terminal-happy-path.webp`
- `terminal-denial.webp`

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
