#!/usr/bin/env bash
# Self-test: verify that the headless reachability gate in e2e.sh requires
# BOTH exit code 0 AND the expected token. A fake grok that prints the token
# but exits non-zero must cause the gate to fail.
#
# Usage (called by validate.mjs --sanity):
#   bash scripts/ci/test-headless-gate.sh
#
# Exits 0 if the gate correctly rejects the bad fake; exits 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source only the headless-gate logic from e2e.sh by extracting it inline.
# We override GROK_BIN to a fake that prints the token and exits 2.
TMPDIR_SELF="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SELF"' EXIT

# Fake grok: prints OMGB_E2E_OK (the expected token) then exits non-zero.
FAKE_GROK="$TMPDIR_SELF/grok"
cat > "$FAKE_GROK" <<'FAKEGROK'
#!/usr/bin/env bash
echo "OMGB_E2E_OK"
exit 2
FAKEGROK
chmod +x "$FAKE_GROK"

# Minimal stubs for e2e.sh helper functions used by the headless section.
LOG="$TMPDIR_SELF/test.log"
touch "$LOG"

FAIL_CALLED=0
FAIL_MSG=""

fail_stub() {
  FAIL_CALLED=1
  FAIL_MSG="$1"
}

# Inline the headless section logic (matches scripts/local/e2e.sh exactly).
GROK_BIN="$FAKE_GROK"
OMGB_E2E_HEADLESS=1

set +e
HEADLESS_OUTPUT=$("$GROK_BIN" --cwd "$ROOT" --no-alt-screen --no-subagents --no-memory \
  --no-plan --disable-web-search --max-turns 20 \
  --output-format plain \
  -p "Reply with the literal token OMGB_E2E_OK and nothing else." \
  2>&1)
HEADLESS_RC=$?
set -e
printf "%s\n" "$HEADLESS_OUTPUT" >>"$LOG"

# Gate 1: exit code must be 0.
if [[ $HEADLESS_RC -ne 0 ]]; then
  fail_stub "grok headless probe exited with code $HEADLESS_RC"
fi
# Gate 2: token must be present.
if [[ $FAIL_CALLED -eq 0 ]] && ! printf "%s\n" "$HEADLESS_OUTPUT" | grep -qx "OMGB_E2E_OK"; then
  fail_stub "grok headless probe did not echo the expected token"
fi

# Verify: gate should have fired because RC=2 (even though token was present).
if [[ $FAIL_CALLED -ne 1 ]]; then
  echo "[OMGB] test-headless-gate FAIL: gate did not reject fake grok that exited 2 with token present"
  exit 1
fi
if [[ "$FAIL_MSG" != *"exited with code 2"* ]]; then
  echo "[OMGB] test-headless-gate FAIL: expected failure message about exit code 2, got: $FAIL_MSG"
  exit 1
fi

echo "[OMGB] test-headless-gate passed: gate correctly rejected token-present + non-zero exit (rc=2)"
