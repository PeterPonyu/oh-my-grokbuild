#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omgb-launcher-modes.XXXXXX")"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/grok" <<'GROK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "grok fake"
  exit 0
fi
echo "fake grok should not be launched by launcher-mode tests" >&2
exit 99
GROK
chmod +x "$FAKE_BIN/grok"
export PATH="$FAKE_BIN:$PATH"
cleanup() {
  rm -rf "$TMP_ROOT"
  rm -f "$ROOT/.grok/omgb/runs/launcher-mode-team" "$ROOT/.grok/omgb/runs/launcher-mode-fanout"
}
trap cleanup EXIT

run_expect_ok() {
  local name="$1"; shift
  local log="$TMP_ROOT/$name.log"
  OMGB_RUNS_ROOT="$TMP_ROOT/runs" "$@" >"$log" 2>&1
  grep -q "dry-run" "$log"
}

run_expect_mixed_reject() {
  local name="$1"; shift
  local log="$TMP_ROOT/$name.log"
  set +e
  OMGB_RUNS_ROOT="$TMP_ROOT/runs" "$@" >"$log" 2>&1
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "$name unexpectedly succeeded" >&2
    cat "$log" >&2
    exit 1
  fi
  grep -q -- "--launch and --dry-run are mutually exclusive" "$log"
}

run_expect_ok team-dry-run "$ROOT/scripts/workflow/launch-omgb-team.sh" launcher-mode-team "test explicit dry run" --dry-run
run_expect_ok fanout-dry-run "$ROOT/scripts/workflow/launch-omgb-fanout.sh" launcher-mode-fanout "test explicit dry run" --roles codebase-scout,researcher --dry-run
run_expect_mixed_reject team-launch-then-dry "$ROOT/scripts/workflow/launch-omgb-team.sh" launcher-mode-team "test mixed" --launch --dry-run
run_expect_mixed_reject team-dry-then-launch "$ROOT/scripts/workflow/launch-omgb-team.sh" launcher-mode-team "test mixed" --dry-run --launch
run_expect_mixed_reject fanout-launch-then-dry "$ROOT/scripts/workflow/launch-omgb-fanout.sh" launcher-mode-fanout "test mixed" --roles codebase-scout,researcher --launch --dry-run
run_expect_mixed_reject fanout-dry-then-launch "$ROOT/scripts/workflow/launch-omgb-fanout.sh" launcher-mode-fanout "test mixed" --roles codebase-scout,researcher --dry-run --launch

echo "[OMGB] launcher-modes passed"
