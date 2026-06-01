#!/usr/bin/env bash
# Self-test: the real /omgb transcript evidence gate must not accept a marker
# that appears only in the real user prompt. It must require skill evidence in
# non-user or synthetic context.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_SELF="$(mktemp -d)"
trap 'rm -rf "$TMP_SELF"' EXIT

OMGB_E2E_LIB_ONLY=1 . "$ROOT/scripts/local/e2e.sh"

mkdir -p "$TMP_SELF/negative" "$TMP_SELF/assistant" "$TMP_SELF/tool" "$TMP_SELF/positive" "$TMP_SELF/skill-envelope"
cat >"$TMP_SELF/negative/chat_history.jsonl" <<'JSONL'
{"type":"user","content":"/omgb fake prompt mentioning # OMGB - Oh My Grok Build Orchestrator only in user text"}
JSONL

if real_omgb_transcript_has_skill_evidence "$TMP_SELF/negative"; then
  echo "[OMGB] test-real-omgb-evidence FAIL: accepted marker present only in real user prompt"
  exit 1
fi

cat >"$TMP_SELF/assistant/chat_history.jsonl" <<'JSONL'
{"type":"assistant","content":"# OMGB - Oh My Grok Build Orchestrator\nAssistant echoed inspected skill body"}
JSONL

if real_omgb_transcript_has_skill_evidence "$TMP_SELF/assistant"; then
  echo "[OMGB] test-real-omgb-evidence FAIL: accepted marker present only in assistant output"
  exit 1
fi

cat >"$TMP_SELF/tool/chat_history.jsonl" <<'JSONL'
{"type":"tool_result","content":"# OMGB - Oh My Grok Build Orchestrator\nTool returned inspected skill body"}
JSONL

if real_omgb_transcript_has_skill_evidence "$TMP_SELF/tool"; then
  echo "[OMGB] test-real-omgb-evidence FAIL: accepted marker present only in tool output"
  exit 1
fi

cat >"$TMP_SELF/positive/chat_history.jsonl" <<'JSONL'
{"type":"user","content":"/omgb fake prompt without skill body"}
{"type":"user","synthetic_reason":"skills","content":"# OMGB - Oh My Grok Build Orchestrator\nSynthetic skill payload context"}
JSONL

if ! real_omgb_transcript_has_skill_evidence "$TMP_SELF/positive"; then
  echo "[OMGB] test-real-omgb-evidence FAIL: rejected synthetic skill payload context"
  exit 1
fi

echo "[OMGB] test-real-omgb-evidence passed"
