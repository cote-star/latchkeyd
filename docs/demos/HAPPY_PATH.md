# Happy Path Demo

This is the shortest demo that shows what `latchkeyd` does.

## Goal

Show a trusted wrapper calling a trusted binary with one approved secret handoff.

## Commands

```bash
swift build
./.build/debug/latchkeyd manifest init --force
./.build/debug/latchkeyd manifest refresh
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./examples/bin/example-wrapper demo
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" ./.build/debug/latchkeyd validate
```

## Expected flow

1. `manifest init` writes the starter manifest.
2. `manifest refresh` pins the current wrapper and binary hashes.
3. `example-wrapper demo` calls `latchkeyd exec`.
4. `latchkeyd` verifies the wrapper path and hash.
5. `latchkeyd` verifies the downstream binary path and hash.
6. `latchkeyd` injects only `LATCHKEYD_EXAMPLE_TOKEN`.
7. `example-demo-cli` proves the token was present without printing it.
8. `validate` confirms the example path and at least one denial path.

## Example output

```json
{
  "command": "manifest.init",
  "message": "Starter manifest written.",
  "ok": true
}
{
  "command": "manifest.refresh",
  "message": "Manifest hashes refreshed.",
  "ok": true
}
{"ok":true,"tool":"example-demo-cli","tokenPreview":"la***en","tokenLength":19,"args":[]}
{
  "command": "validate",
  "message": "Validation succeeded.",
  "ok": true
}
```

## Demo narrative

"The agent calls the wrapper. The broker verifies the wrapper and the tool. The secret stays local and is handed off only for the approved execution path."
