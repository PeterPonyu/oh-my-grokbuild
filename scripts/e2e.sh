#!/usr/bin/env bash
# OMGB end-to-end smoke against an existing Grok login.
#
# Requires:
#   - grok CLI present on PATH (looks for `grok` or ~/.grok/bin/grok).
#   - An existing Grok login at ~/.grok/auth.json. This script refuses to invoke
#     `grok login`; the user must already be logged in.
#
# Checks:
#   1. ~/.grok/auth.json exists and is non-empty.
#   2. `grok --version` works.
#   3. `grok inspect` exits cleanly (with code 0 or the documented diagnostic code).
#   4. The plugin payload at the local install path contains a discoverable
#      omgb skill.
#   5. Optional headless reachability probe with `grok -p` is only run when
#      OMGB_E2E_HEADLESS=1 is exported; otherwise the script reports SKIP.
#
# On success, prints "[OMGB] e2e passed" and writes a trace to
# .omc/evidence/e2e-<timestamp>.log.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT/.omc/evidence"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$EVIDENCE_DIR/e2e-$TIMESTAMP.log"
LOCAL_INSTALL="${OMGB_LOCAL_INSTALL:-$HOME/.grok/plugins/local/oh-my-grokbuild}"
AUTH_FILE="$HOME/.grok/auth.json"

mkdir -p "$EVIDENCE_DIR"

log() {
  printf "%s %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"
}

fail() {
  log "FAIL: $*"
  log "[OMGB] e2e failed"
  exit 1
}

ok() {
  log "OK:   $*"
}

step() {
  log "STEP: $*"
}

resolve_grok() {
  if command -v grok >/dev/null 2>&1; then
    command -v grok
    return
  fi
  if [[ -x "$HOME/.grok/bin/grok" ]]; then
    echo "$HOME/.grok/bin/grok"
    return
  fi
  echo ""
}

main() {
  step "auth check"
  if [[ ! -s "$AUTH_FILE" ]]; then
    fail "missing or empty $AUTH_FILE. Log in to Grok first via 'grok login'."
  fi
  ok "auth file present"

  step "grok cli resolution"
  GROK_BIN="$(resolve_grok)"
  if [[ -z "$GROK_BIN" ]]; then
    fail "grok CLI not found on PATH or at ~/.grok/bin/grok"
  fi
  ok "grok cli: $GROK_BIN"

  step "grok --version"
  if ! "$GROK_BIN" --version >>"$LOG" 2>&1; then
    fail "grok --version failed"
  fi
  ok "version probe ok"

  step "grok inspect"
  # `grok inspect` exits non-zero on this client for diagnostic reasons but
  # still prints the inventory we care about. We accept exit codes 0 and 2.
  set +e
  "$GROK_BIN" inspect >>"$LOG" 2>&1
  INSPECT_RC=$?
  set -e
  if [[ $INSPECT_RC -ne 0 && $INSPECT_RC -ne 2 ]]; then
    fail "grok inspect failed with code $INSPECT_RC"
  fi
  ok "inspect probe ok (rc=$INSPECT_RC)"

  step "local install payload"
  if [[ ! -d "$LOCAL_INSTALL" ]]; then
    fail "installed payload missing at $LOCAL_INSTALL; run scripts/install-local.sh first"
  fi
  for required in \
    "plugin.json" \
    ".claude-plugin/plugin.json" \
    "skills/omgb/SKILL.md" \
    "agents/AGENTS.md" \
    "roles/leader.toml"
  do
    if [[ ! -e "$LOCAL_INSTALL/$required" ]]; then
      fail "installed payload missing $required"
    fi
  done
  ok "installed payload looks healthy"

  step "grok user-skill mount"
  USER_SKILL="$HOME/.grok/skills/omgb"
  if [[ "${OMGB_E2E_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
    log "SKIP: user-skill mount check (OMGB_E2E_SKIP_USER_SKILL_MOUNT=1)"
  else
    for required in "SKILL.md" "agents" "roles"; do
      if [[ ! -e "$USER_SKILL/$required" ]]; then
        fail "grok user-skill mount missing $required at $USER_SKILL; re-run scripts/install-local.sh"
      fi
    done
    ok "grok user-skill mount looks healthy at $USER_SKILL"

    step "grok inspect discovers omgb"
    set +e
    "$GROK_BIN" inspect 2>&1 | grep -E "^\s+└\s+omgb\s+user\s*$" >>"$LOG"
    GREP_RC=$?
    set -e
    if [[ $GREP_RC -ne 0 ]]; then
      fail "grok inspect did not list omgb as a user skill; reload Grok or rerun install"
    fi
    ok "grok inspect lists omgb as a user skill"
  fi

  step "headless reachability"
  if [[ "${OMGB_E2E_HEADLESS:-0}" = "1" ]]; then
    # Grok defaults to spawning subagents and may attempt background MCP
    # connections, which inflates the turn count for trivially small prompts.
    # Pin --no-subagents and --no-memory, disable web search and plan mode,
    # and allow a generous turn budget so noisy MCP retries do not starve
    # the actual reply.
    set +e
    "$GROK_BIN" --cwd "$ROOT" --no-alt-screen --no-subagents --no-memory \
      --no-plan --disable-web-search --max-turns 20 \
      --output-format plain \
      -p "Reply with the literal token OMGB_E2E_OK and nothing else." \
      >>"$LOG" 2>&1
    HEADLESS_RC=$?
    set -e
    if ! grep -q "OMGB_E2E_OK" "$LOG"; then
      fail "grok headless probe did not echo the expected token (exit $HEADLESS_RC)"
    fi
    ok "headless probe returned OMGB_E2E_OK (exit $HEADLESS_RC)"
  else
    log "SKIP: headless reachability (set OMGB_E2E_HEADLESS=1 to run a live model probe)"
  fi

  log "[OMGB] e2e passed"
}

main "$@"
