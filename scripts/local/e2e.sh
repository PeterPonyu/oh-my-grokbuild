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
EVIDENCE_DIR="${OMGB_EVIDENCE_DIR:-$ROOT/.omgb/evidence}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$EVIDENCE_DIR/e2e-$TIMESTAMP.log"
LOCAL_INSTALL="${OMGB_LOCAL_INSTALL:-$HOME/.grok/plugins/local/oh-my-grokbuild}"
AUTH_FILE="$HOME/.grok/auth.json"

mkdir -p "$EVIDENCE_DIR"
PROBE_TMP_PARENT="$(cd "${TMPDIR:-/tmp}" && pwd)"
PROBE_RUNS_ROOT="$(mktemp -d "$PROBE_TMP_PARENT/omgb-e2e-runs.XXXXXX")"
STRUCT_TMP=""
cleanup_probe_runs() {
  # launch-omgb-{team,fanout}.sh creates repo-local .grok/omgb/runs/<slug>
  # symlinks to OMGB_RUNS_ROOT. Probe roots are temporary, so remove only the
  # links this e2e invocation created before deleting the temp directory.
  local links_root="$ROOT/.grok/omgb/runs"
  if [[ -d "$links_root" ]]; then
    while IFS= read -r link; do
      local target
      target="$(readlink "$link" 2>/dev/null || true)"
      case "$target" in
        "$PROBE_RUNS_ROOT"/*|"${STRUCT_TMP:-__omgb_no_struct_tmp__}"/*)
          rm -f -- "$link"
          ;;
        /tmp/omgb-e2e-runs.*/*|/tmp/omgb-doctor-runs.*/*|/tmp/omgb-structural.*/*|"$PROBE_TMP_PARENT"/omgb-e2e-runs.*/*|"$PROBE_TMP_PARENT"/omgb-doctor-runs.*/*|"$PROBE_TMP_PARENT"/omgb-structural.*/*)
          # Clean stale probe links from prior runs, but do not remove another
          # currently-running probe's live link.
          if [[ ! -e "$target" ]]; then
            rm -f -- "$link"
          fi
          ;;
      esac
    done < <(find "$links_root" -maxdepth 1 -type l -print 2>/dev/null)
  fi
  rm -rf "$PROBE_RUNS_ROOT"
  if [[ -n "${STRUCT_TMP:-}" ]]; then
    rm -rf "$STRUCT_TMP"
  fi
}
trap cleanup_probe_runs EXIT
export OMGB_RUNS_ROOT="$PROBE_RUNS_ROOT"

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

run_headless_probe() {
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
}


audit_canonical_runs() {
  step "canonical run archive audit (informational)"
  # The launch probes above use a temporary OMGB_RUNS_ROOT by design. Audit the
  # durable ~/.grok/omgb/runs archive explicitly so the e2e log does not imply
  # that skipped temporary dry-run probes prove historical runs are healthy.
  set +e
  OMGB_RUNS_ROOT="$HOME/.grok/omgb/runs" node "$ROOT/scripts/ci/validate.mjs" --audit-all >>"$LOG" 2>&1
  AUDIT_RC=$?
  set -e
  if [[ $AUDIT_RC -eq 0 ]]; then
    ok "canonical completed runs pass the subagent-evidence audit; skipped incomplete probe dirs, if any, are listed in the log"
  elif [[ "${OMGB_E2E_STRICT_AUDIT:-0}" = "1" ]]; then
    fail "canonical run archive has audit findings; see $LOG"
  else
    log "INFO: canonical run archive has audit findings; see $LOG (e2e continues because this pass is informational; set OMGB_E2E_STRICT_AUDIT=1 for release gating)"
  fi
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


run_structural_probe() {
  step "structural mode setup (no credentials)"
  STRUCT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/omgb-structural.XXXXXX")"

  FAKE_BIN_DIR="$STRUCT_TMP/bin"
  mkdir -p "$FAKE_BIN_DIR"
  cat >"$FAKE_BIN_DIR/grok" <<'FAKEGROK'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "grok fake structural 0.0.0"
    exit 0
    ;;
  inspect)
    echo "skills"
    echo "  └ omgb user"
    exit 0
    ;;
  *)
    echo "OMGB_E2E_OK"
    exit 0
    ;;
esac
FAKEGROK
  chmod +x "$FAKE_BIN_DIR/grok"
  export PATH="$FAKE_BIN_DIR:$PATH"
  GROK_BIN="$FAKE_BIN_DIR/grok"
  ok "using fake grok binary for credential-free structural checks: $GROK_BIN"

  step "local payload structure (repository checkout)"
  LOCAL_INSTALL="${OMGB_LOCAL_INSTALL:-$ROOT}"
  if [[ ! -d "$LOCAL_INSTALL" ]]; then
    fail "structural payload root missing at $LOCAL_INSTALL"
  fi
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
    validate_payload_item "$item"
    item_path="${item%/}"
    if [[ ! -e "$LOCAL_INSTALL/$item_path" ]]; then
      fail "structural payload missing $item_path (listed in local-payload.txt)"
    fi
  done < "$ROOT/local-payload.txt"
  ok "repository payload matches local-payload.txt"

  step "subagent team launcher (dry-run, fake/no credential path)"
  set +e
  bash "$ROOT/scripts/workflow/launch-omgb-team.sh" structural-team-probe "structural team JSON probe" >>"$LOG" 2>&1
  LAUNCH_RC=$?
  set -e
  if [[ $LAUNCH_RC -ne 0 ]]; then
    fail "launch-omgb-team.sh structural dry-run failed with code $LAUNCH_RC"
  fi
  PROBE_CFG="$OMGB_RUNS_ROOT/structural-team-probe/agents-config.json"
  if ! node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); if(Object.keys(c).length!==16){process.exit(2)}" "$PROBE_CFG" >>"$LOG" 2>&1; then
    fail "structural launcher produced JSON but it does not contain exactly 16 roles"
  fi
  ok "launcher emitted a valid 16-role agents JSON ($PROBE_CFG)"

  step "APR fan-out launcher (dry-run, fake/no credential path)"
  set +e
  APR_OUT=$(bash "$ROOT/scripts/workflow/launch-omgb-fanout.sh" structural-apr-probe "structural APR cohort probe" --phase apr 2>&1)
  APR_RC=$?
  set -e
  printf "%s\n" "$APR_OUT" >>"$LOG"
  if [[ $APR_RC -ne 0 ]]; then
    fail "launch-omgb-fanout.sh structural dry-run failed with code $APR_RC"
  fi
  for role in code-reviewer security-reviewer performance-reviewer ux-reviewer architect; do
    if ! printf "%s\n" "$APR_OUT" | grep -q "$role"; then
      fail "structural APR cohort missing required role $role"
    fi
  done
  if ! printf "%s\n" "$APR_OUT" | grep -q "Rerun with --launch to fork 5 parallel grok subprocesses"; then
    fail "structural APR cohort did not declare exactly 5 parallel subprocesses"
  fi
  ok "APR fan-out plans the 5-role adversarial cohort"

  audit_canonical_runs

  step "fake headless reachability"
  run_headless_probe

  log "[OMGB] structural e2e passed"
}

main() {
  if [[ "${OMGB_E2E_STRUCTURAL:-0}" = "1" ]]; then
    run_structural_probe
    return 0
  fi

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
  PROBE_CFG="$OMGB_RUNS_ROOT/e2e-team-probe/agents-config.json"
  if ! node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); if(Object.keys(c).length!==16){process.exit(2)}" "$PROBE_CFG" >>"$LOG" 2>&1; then
    fail "launcher produced JSON but it does not contain exactly 16 roles"
  fi
  ok "launcher emitted a valid 16-role agents JSON ($PROBE_CFG)"

  step "APR fan-out launcher (dry-run)"
  set +e
  APR_OUT=$(bash "$ROOT/scripts/workflow/launch-omgb-fanout.sh" e2e-apr-probe "e2e APR cohort probe" --phase apr 2>&1)
  APR_RC=$?
  set -e
  printf "%s\n" "$APR_OUT" >>"$LOG"
  if [[ $APR_RC -ne 0 ]]; then
    fail "launch-omgb-fanout.sh --phase apr dry-run failed with code $APR_RC"
  fi
  for role in code-reviewer security-reviewer performance-reviewer ux-reviewer architect; do
    if ! printf "%s\n" "$APR_OUT" | grep -q "$role"; then
      fail "APR cohort missing required role $role"
    fi
  done
  if ! printf "%s\n" "$APR_OUT" | grep -q "Rerun with --launch to fork 5 parallel grok subprocesses"; then
    fail "APR cohort did not declare exactly 5 parallel subprocesses"
  fi
  ok "APR fan-out plans the 5-role adversarial cohort"

  audit_canonical_runs

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
    INSPECT_OUTPUT="$($GROK_BIN inspect 2>&1)"
    GREP_RC=1
    if printf "%s\n" "$INSPECT_OUTPUT" | grep -Eq '(^|[^[:alnum:]_-])omgb[[:space:]]+user([^[:alnum:]_-]|$)'; then
      GREP_RC=0
    fi
    printf "%s\n" "$INSPECT_OUTPUT" >>"$LOG"
    set -e
    if [[ $GREP_RC -ne 0 ]]; then
      fail "grok inspect did not list omgb as a user skill; reload Grok or rerun install"
    fi
    ok "grok inspect lists omgb as a user skill (/omgb is mounted via ~/.grok/skills/omgb; the local plugin payload may not appear as an enabled plugin in this Grok version)"
  fi

  step "headless reachability"
  if [[ "${OMGB_E2E_HEADLESS:-0}" = "1" ]]; then
    run_headless_probe
  elif [[ "${OMGB_E2E_ALLOW_HEADLESS_SKIP:-0}" = "1" ]]; then
    log "SKIP: headless reachability (explicit structural mode via OMGB_E2E_ALLOW_HEADLESS_SKIP=1)"
    log "[OMGB] structural e2e passed (headless skipped)"
    return 0
  else
    fail "headless reachability was not run; set OMGB_E2E_HEADLESS=1 for full E2E or OMGB_E2E_ALLOW_HEADLESS_SKIP=1 for structural-only validation"
  fi

  log "[OMGB] e2e passed"
}

if [[ "${OMGB_E2E_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
