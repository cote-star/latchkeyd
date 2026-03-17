# Trust Failure Demos

These demos show the intended failure posture of `latchkeyd`.

They are trust failures before handoff or during an approved brokered session. They are not claims about post-handoff confinement after a trusted child already has access.

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

Use a temporary manifest and point the file backend at a missing file:

```bash
tmpdir="$(mktemp -d)"
./.build/debug/latchkeyd manifest init --manifest "$tmpdir/manifest.json" --force
./.build/debug/latchkeyd manifest refresh --manifest "$tmpdir/manifest.json"
perl -0pi -e 's#"filePath" : "([^"]+)"#"filePath" : "/tmp/does-not-exist.json"#' "$tmpdir/manifest.json"
./.build/debug/latchkeyd validate --manifest "$tmpdir/manifest.json"
```

Expected result:

- backend error
- validation failure
- no secret material released

## 5. Audit log unavailable

Make the event-log path unusable before a brokered run:

```bash
mkdir -p /tmp/latchkeyd-events-blocked
./.build/debug/latchkeyd exec \
  --manifest ~/Library/Application\ Support/latchkeyd/manifest.json \
  --policy example-demo \
  --caller "$PWD/examples/bin/example-wrapper"
```

Expected result:

- `LOGGING_ERROR`
- the run does not proceed as an unaudited success

## 6. Unsupported brokered operation

Ask the brokered example CLI for an operation that is not allowed:

```bash
LATCHKEYD_BIN="$PWD/.build/debug/latchkeyd" \
./examples/bin/example-wrapper brokered-demo -- --brokered-operation secret.invalid
```

Expected result:

- `OPERATION_NOT_ALLOWED`
- the request is denied inside the brokered session
- no secret value is returned

## What The Operator Does Next

1. inspect the failing wrapper, binary, backend path, or brokered operation
2. decide whether the change is expected
3. if it is expected, re-pin with `manifest refresh`
4. if it is not expected, stop and investigate instead of weakening the policy

## Demo Narrative

“A name match is not trust. A drifted file is not trust. A direct caller path is not trust. An unsupported brokered request is not trust. `latchkeyd` makes those failures explicit instead of silently falling back.”
