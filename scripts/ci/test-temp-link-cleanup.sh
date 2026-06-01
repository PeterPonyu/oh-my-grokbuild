#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINK_ROOT="$ROOT/.grok/omgb/runs"
mkdir -p "$LINK_ROOT"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omgb-temp-link-cleanup.XXXXXX")"
LIVE_TARGET="$TMP_ROOT/live/run"
BROKEN_TARGET="$TMP_ROOT/broken/run"
LIVE_LINK="$LINK_ROOT/temp-cleanup-live"
BROKEN_LINK="$LINK_ROOT/temp-cleanup-broken"
mkdir -p "$LIVE_TARGET" "$BROKEN_TARGET"
rm -f "$LIVE_LINK" "$BROKEN_LINK"
ln -s "$LIVE_TARGET" "$LIVE_LINK"
ln -s "$BROKEN_TARGET" "$BROKEN_LINK"
rm -rf "$BROKEN_TARGET"

cleanup() {
  rm -f "$LIVE_LINK" "$BROKEN_LINK"
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

OMGB_E2E_STRUCTURAL=1 bash "$ROOT/scripts/local/e2e.sh" >/tmp/omgb-temp-link-cleanup-e2e.log 2>&1

if [[ ! -L "$LIVE_LINK" ]]; then
  echo "live temp link was removed unexpectedly" >&2
  cat /tmp/omgb-temp-link-cleanup-e2e.log >&2
  exit 1
fi
if [[ -e "$BROKEN_LINK" || -L "$BROKEN_LINK" ]]; then
  echo "broken temp link was not removed" >&2
  cat /tmp/omgb-temp-link-cleanup-e2e.log >&2
  exit 1
fi

echo "[OMGB] temp-link-cleanup passed"
