#!/usr/bin/env bash
# Self-test: verify that the real e2e.sh headless gate requires BOTH exit code
# 0 and the expected token. A fake grok that prints the token but exits non-zero
# must cause the sourced gate function to fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR_SELF="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SELF"' EXIT

FAKE_GROK="$TMPDIR_SELF/grok"
cat > "$FAKE_GROK" <<'FAKEGROK'
#!/usr/bin/env bash
echo "OMGB_E2E_OK"
exit 2
FAKEGROK
chmod +x "$FAKE_GROK"

# Source the actual e2e helpers without running the full e2e main flow.
OMGB_E2E_LIB_ONLY=1 . "$ROOT/scripts/local/e2e.sh"

LOG="$TMPDIR_SELF/test.log"
touch "$LOG"
GROK_BIN="$FAKE_GROK"
FAIL_CALLED=0
FAIL_MSG=""

fail() {
  FAIL_CALLED=1
  FAIL_MSG="$1"
}

ok() { :; }

run_headless_probe

if [[ $FAIL_CALLED -ne 1 ]]; then
  echo "[OMGB] test-headless-gate FAIL: gate did not reject fake grok that exited 2 with token present"
  exit 1
fi
if [[ "$FAIL_MSG" != *"exited with code 2"* ]]; then
  echo "[OMGB] test-headless-gate FAIL: expected failure message about exit code 2, got: $FAIL_MSG"
  exit 1
fi

echo "[OMGB] test-headless-gate passed: real e2e gate rejected token-present + non-zero exit (rc=2)"
