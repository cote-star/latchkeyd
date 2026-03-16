#!/usr/bin/env node

import path from "node:path";
import puppeteer from "puppeteer";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const assetsDir = path.join(root, "docs", "assets");
const width = 1200;
const height = 620;

function sceneHtml({ title, subtitle, tab, summary, body, footer, status }) {
  const accent = "#F37021";
  const green = "#2D8A4E";
  const promptColor = status === "success" ? green : accent;
  const bodyColor = status === "success" ? "#D5D1C7" : "#F2B7AF";

  const bodyHtml = body
    .map((line) => {
      const className = line.startsWith("$ ") ? "prompt" : "body";
      const escaped = line
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
      return `<div class="line ${className}">${escaped}</div>`;
    })
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <style>
    :root {
      color-scheme: light;
      --bg: #FDFCF8;
      --panel: #162331;
      --text: #F8F6F0;
      --secondary: #D5D1C7;
      --prompt: ${promptColor};
      --body: ${bodyColor};
      --accent: ${accent};
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      font-family: Inter, "SF Pro Display", Helvetica, Arial, sans-serif;
      color: #1A1A1A;
    }
    .frame {
      width: ${width}px;
      height: ${height}px;
      padding: 40px;
      position: relative;
      overflow: hidden;
      background:
        radial-gradient(circle at 20% 10%, rgba(243, 112, 33, 0.07), transparent 30%),
        radial-gradient(circle at 90% 0%, rgba(243, 112, 33, 0.05), transparent 22%),
        linear-gradient(180deg, rgba(255,255,255,0.25), rgba(255,255,255,0));
    }
    .mark {
      position: absolute;
      left: 40px;
      top: 24px;
      color: var(--accent);
      font-size: 24px;
      font-weight: 700;
      letter-spacing: 0.04em;
    }
    .terminal {
      position: absolute;
      left: 52px;
      right: 52px;
      top: 58px;
      bottom: 42px;
      border-radius: 28px;
      background: var(--panel);
      box-shadow: 0 18px 40px rgba(21, 28, 39, 0.16);
      overflow: hidden;
    }
    .chrome {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 24px 30px 0 30px;
      font-family: "JetBrains Mono", "SF Mono", Menlo, monospace;
      color: #A9B6C5;
      font-size: 18px;
    }
    .dot {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      display: inline-block;
    }
    .dot.red { background: #D94F3B; }
    .dot.amber { background: #F37021; }
    .dot.green { background: #2D8A4E; }
    .content {
      padding: 26px 34px 34px 34px;
      display: flex;
      flex-direction: column;
      height: calc(100% - 44px);
    }
    .eyebrow {
      color: #E6E0D3;
      font-size: 16px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      margin-bottom: 14px;
      opacity: 0.92;
    }
    .headline {
      color: var(--text);
      font-size: 32px;
      line-height: 1.1;
      font-weight: 700;
      margin-bottom: 12px;
      max-width: 900px;
    }
    .sub {
      color: #B6C3D1;
      font-size: 18px;
      line-height: 1.4;
      margin-bottom: 20px;
      max-width: 850px;
    }
    .code {
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 18px;
      padding: 18px 20px;
      font-family: "JetBrains Mono", "SF Mono", Menlo, monospace;
      font-size: 17px;
      line-height: 1.45;
      flex: 1;
      overflow: hidden;
    }
    .line { white-space: pre-wrap; }
    .prompt { color: var(--prompt); margin-bottom: 10px; }
    .body { color: var(--body); margin-bottom: 8px; }
    .footer {
      margin-top: 16px;
      padding-top: 14px;
      border-top: 1px solid rgba(243, 112, 33, 0.35);
      color: var(--text);
      font-size: 24px;
      line-height: 1.2;
      font-weight: 700;
    }
  </style>
</head>
<body>
  <div class="frame">
    <div class="mark">↺</div>
    <div class="terminal">
      <div class="chrome">
        <span class="dot red"></span>
        <span class="dot amber"></span>
        <span class="dot green"></span>
        <span>${tab}</span>
      </div>
      <div class="content">
        <div class="eyebrow">${title}</div>
        <div class="headline">${subtitle}</div>
        <div class="sub">${summary}</div>
        <div class="code">${bodyHtml}</div>
        <div class="footer">${footer}</div>
      </div>
    </div>
  </div>
</body>
</html>`;
}

const scenes = [
  {
    output: path.join(assetsDir, "terminal-happy-path.webp"),
    title: "Trusted Handoff",
    subtitle: "A local agent gets one approved secret handoff, not a broad shell environment.",
    tab: "happy path",
    summary: "build, pin trust, run the wrapper",
    body: [
      "$ swift build",
      "$ latchkeyd manifest init --force",
      '{ "command": "manifest.init", "ok": true }',
      "$ example-wrapper demo",
      '{ "ok": true, "tool": "example-demo-cli", "tokenPreview": "la***en" }'
    ],
    footer: "Trusted wrapper. Trusted binary. Scoped handoff.",
    status: "success"
  },
  {
    output: path.join(assetsDir, "terminal-denial.webp"),
    title: "Denied Handoff",
    subtitle: "A binary name match is not trust. The wrong path gets denied before secrets move.",
    tab: "trust denial",
    summary: "wrong path, no secret handoff",
    body: [
      '$ PATH="/tmp/hijack:$PATH" example-wrapper demo',
      '{ "ok": false, "error": {',
      '  "code": "TRUST_DENIED",',
      '  "message": "PATH hijack detected"',
      "} }"
    ],
    footer: "Drift, hijack, and bypass should fail closed.",
    status: "failure"
  }
];

async function launchBrowser() {
  try {
    return await puppeteer.launch({
      channel: "chrome",
      headless: true
    });
  } catch {
    return puppeteer.launch({
      headless: true
    });
  }
}

const browser = await launchBrowser();

try {
  for (const scene of scenes) {
    const page = await browser.newPage();
    await page.setViewport({ width, height, deviceScaleFactor: 2 });
    await page.setContent(sceneHtml(scene));
    await page.screenshot({ path: scene.output, type: "webp", quality: 92 });
    await page.close();
  }
} finally {
  await browser.close();
}
