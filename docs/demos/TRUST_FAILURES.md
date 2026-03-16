# Trust Failure Demos

These demos show the intended failure posture of `latchkeyd`.

The point is not just that the happy path works. The point is that unexpected drift and unsafe execution paths fail closed.

## 1. Wrapper drift

Change the wrapper after trust has been pinned:

```bash
printf '\n# drift\n' >> ./examples/bin/example-wrapper
./.build/debug/latchkeyd manifest verify
```

Expected result:

- `manifest verify` fails with a trusted wrapper hash mismatch
- the operator must choose whether to re-pin with `manifest refresh`

Recovery:

```bash
./.build/debug/latchkeyd manifest refresh
```

## 2. PATH hijack

Create a fake binary earlier in `PATH`:

```bash
mkdir -p /tmp/latchkeyd-hijack
cat >/tmp/latchkeyd-hijack/example-demo-cli <<'EOF'
#!/usr/bin/env bash
echo hijacked
EOF
chmod +x /tmp/latchkeyd-hijack/example-demo-cli
PATH="/tmp/latchkeyd-hijack:$PATH" \
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" \
./examples/bin/example-wrapper demo
```

Expected result:

- `latchkeyd` rejects the run
- the fake binary never receives the secret

## 3. Untrusted caller

Bypass the wrapper:

```bash
./.build/debug/latchkeyd exec \
  --policy example-demo \
  --caller /tmp/not-trusted-wrapper.sh
```

Expected result:

- `TRUST_DENIED`
- caller path mismatch details in the error output

## 4. Backend misconfiguration

Point the file backend at a missing file:

```bash
perl -0pi -e 's#"filePath" : "([^"]+)"#"filePath" : "/tmp/does-not-exist.json"#' \
  ~/Library/Application\ Support/latchkeyd/manifest.json
./.build/debug/latchkeyd validate
```

Expected result:

- backend error
- validation failure
- no secret material released

## Demo narrative

"A name match is not trust. A drifted file is not trust. A direct caller path is not trust. `latchkeyd` makes those failures obvious instead of silently falling back."
