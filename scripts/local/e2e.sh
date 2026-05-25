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
#   5. Headless reachability probe with `grok -p` must pass for a full E2E.
#      Set OMGB_E2E_ALLOW_HEADLESS_SKIP=1 only for an explicit structural check;
#      that mode never prints the full E2E pass marker.
#
# On success, prints "[OMGB] e2e passed" and writes a trace to
# .omgb/evidence/e2e-<timestamp>.log.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="$ROOT/.omgb/evidence"
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

resolve_path() {
  node -e 'const fs = require("fs"); try { process.stdout.write(fs.realpathSync(process.argv[1])) } catch { process.exit(1) }' "$1"
}

validate_payload_item() {
  case "$1" in
    ""|/*|*\\*|../*|*/../*|*"/.."|".."|./*|*/./*|*"/."|"."|*[[:space:]]*)
      fail "unsafe local-payload.txt entry: $1"
      ;;
  esac
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

  step "local install payload (driven by local-payload.txt)"
  if [[ ! -d "$LOCAL_INSTALL" ]]; then
    fail "installed payload missing at $LOCAL_INSTALL; run scripts/local/install-local.sh first"
  fi
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
    validate_payload_item "$item"
    item_path="${item%/}"
    if [[ ! -e "$LOCAL_INSTALL/$item_path" ]]; then
      fail "installed payload missing $item_path (listed in local-payload.txt)"
    fi
  done < "$ROOT/local-payload.txt"
  ok "installed payload looks healthy (matches local-payload.txt)"

  step "subagent team launcher (dry-run)"
  set +e
  bash "$ROOT/scripts/workflow/launch-omgb-team.sh" e2e-team-probe "e2e team JSON probe" >>"$LOG" 2>&1
  LAUNCH_RC=$?
  set -e
  if [[ $LAUNCH_RC -ne 0 ]]; then
    fail "launch-omgb-team.sh dry-run failed with code $LAUNCH_RC"
  fi
  PROBE_CFG="$ROOT/.grok/omgb/runs/e2e-team-probe/agents-config.json"
  if ! node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); if(Object.keys(c).length!==16){process.exit(2)}" "$PROBE_CFG" >>"$LOG" 2>&1; then
    fail "launcher produced JSON but it does not contain exactly 16 roles"
  fi
  ok "launcher emitted a valid 16-role agents JSON ($PROBE_CFG)"

  step "audit existing runs (informational)"
  set +e
  node "$ROOT/scripts/ci/validate.mjs" --audit-all >>"$LOG" 2>&1
  AUDIT_RC=$?
  set -e
  if [[ $AUDIT_RC -eq 0 ]]; then
    ok "all completed runs pass the subagent-evidence audit"
  else
    log "INFO: existing runs do not yet have subagent-spawn evidence (legacy synthesis); see audit findings in $LOG"
  fi

  step "grok user-skill mount"
  USER_SKILL="$HOME/.grok/skills/omgb"
  if [[ "${OMGB_E2E_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
    log "SKIP: user-skill mount check (OMGB_E2E_SKIP_USER_SKILL_MOUNT=1)"
  else
    EXPECTED_SKILL_TARGET="$(resolve_path "$ROOT/skills/omgb/SKILL.md")"
    EXPECTED_AGENTS_TARGET="$(resolve_path "$ROOT/agents")"
    EXPECTED_ROLES_TARGET="$(resolve_path "$ROOT/roles")"

    for required in "SKILL.md" "agents" "roles"; do
      if [[ ! -e "$USER_SKILL/$required" ]]; then
        fail "grok user-skill mount missing $required at $USER_SKILL; re-run scripts/local/install-local.sh"
      fi
    done

    SKILL_TARGET="$(resolve_path "$USER_SKILL/SKILL.md" 2>/dev/null || true)"
    AGENTS_TARGET="$(resolve_path "$USER_SKILL/agents" 2>/dev/null || true)"
    ROLES_TARGET="$(resolve_path "$USER_SKILL/roles" 2>/dev/null || true)"
    if [[ "$SKILL_TARGET" != "$EXPECTED_SKILL_TARGET" ]]; then
      fail "grok user-skill mount SKILL.md points outside current checkout: $SKILL_TARGET"
    fi
    if [[ "$AGENTS_TARGET" != "$EXPECTED_AGENTS_TARGET" ]]; then
      fail "grok user-skill mount agents points outside current checkout: $AGENTS_TARGET"
    fi
    if [[ "$ROLES_TARGET" != "$EXPECTED_ROLES_TARGET" ]]; then
      fail "grok user-skill mount roles points outside current checkout: $ROLES_TARGET"
    fi
    ok "grok user-skill mount points to current checkout at $USER_SKILL"

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
    HEADLESS_OUTPUT=$("$GROK_BIN" --cwd "$ROOT" --no-alt-screen --no-subagents --no-memory \
      --no-plan --disable-web-search --max-turns 20 \
      --output-format plain \
      -p "Reply with the literal token OMGB_E2E_OK and nothing else." \
      2>&1)
    HEADLESS_RC=$?
    set -e
    printf "%s\n" "$HEADLESS_OUTPUT" >>"$LOG"
    if [[ $HEADLESS_RC -ne 0 ]]; then
      fail "grok headless probe exited with code $HEADLESS_RC"
    fi
    if ! printf "%s\n" "$HEADLESS_OUTPUT" | grep -qx "OMGB_E2E_OK"; then
      fail "grok headless probe did not echo the expected token"
    fi
    ok "headless probe returned OMGB_E2E_OK (exit $HEADLESS_RC)"
  elif [[ "${OMGB_E2E_ALLOW_HEADLESS_SKIP:-0}" = "1" ]]; then
    log "SKIP: headless reachability (explicit structural mode via OMGB_E2E_ALLOW_HEADLESS_SKIP=1)"
    log "[OMGB] structural e2e passed (headless skipped)"
    return 0
  else
    fail "headless reachability was not run; set OMGB_E2E_HEADLESS=1 for full E2E or OMGB_E2E_ALLOW_HEADLESS_SKIP=1 for structural-only validation"
  fi

  log "[OMGB] e2e passed"
}

main "$@"
