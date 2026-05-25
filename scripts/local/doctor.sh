#!/usr/bin/env bash
# OMGB Doctor — quick health check for the installed omgb plugin and Grok environment.
#
# Run this after `scripts/local/install-local.sh --force` or when `/omgb` is not behaving.
# It is intentionally dependency-light (only uses what the install script already assumes).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

pass() { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
fail() { printf "${RED}✗ %s${RESET}\n" "$*"; }
warn() { printf "${YELLOW}! %s${RESET}\n" "$*"; }
info() { printf "  %s\n" "$*"; }

resolve_path() {
  node -e 'const fs = require("fs"); try { process.stdout.write(fs.realpathSync(process.argv[1])) } catch { process.exit(1) }' "$1"
}

payload_entry_is_safe() {
  case "$1" in
    ""|/*|*\\*|../*|*/../*|*"/.."|".."|./*|*/./*|*"/."|"."|*[[:space:]]*)
      return 1
      ;;
  esac
}

echo "OMGB Doctor — checking your Grok + omgb setup"
echo "Source: $ROOT"
echo

# 1. Node
if command -v node >/dev/null 2>&1; then
  NODEV="$(node --version)"
  if node --version | grep -qE 'v(1[8-9]|[2-9][0-9])'; then
    pass "Node.js present: $NODEV"
  else
    warn "Node.js present but old ($NODEV). v18+ recommended for validate.mjs"
  fi
else
  fail "Node.js not found in PATH (required for validate / doctor)"
fi

# 2. Grok CLI
if command -v grok >/dev/null 2>&1; then
  GROKPATH="$(command -v grok)"
  GROKVER="$("$GROKPATH" --version 2>/dev/null | head -1 || echo 'unknown')"
  pass "Grok CLI: $GROKPATH ($GROKVER)"
else
  fail "grok command not found in PATH"
fi

# 3. Auth (for e2e / headless)
AUTH="$HOME/.grok/auth.json"
if [[ -f "$AUTH" ]]; then
  pass "Grok auth present: $AUTH"
else
  warn "No $AUTH — e2e.sh and some headless flows will skip live probes (run 'grok login' if needed)"
fi

# 4. User skill mount (what makes /omgb appear) — now drift-aware vs current checkout
USER_SKILL="$HOME/.grok/skills/omgb"
EXPECTED_SKILL_TARGET="$(resolve_path "$ROOT/skills/omgb/SKILL.md")"
EXPECTED_AGENTS_TARGET="$(resolve_path "$ROOT/agents")"
EXPECTED_ROLES_TARGET="$(resolve_path "$ROOT/roles")"
MOUNT_POINTS_TO_CURRENT=0

if [[ -L "$USER_SKILL" ]]; then
  warn "User skill mount directory is itself a symlink; re-run install-local.sh --force to replace it with the managed directory"
elif [[ -L "$USER_SKILL/SKILL.md" ]]; then
  TARGET="$(resolve_path "$USER_SKILL/SKILL.md" 2>/dev/null || true)"
  if [[ -f "$TARGET" ]]; then
    AGENTS_TARGET="$(resolve_path "$USER_SKILL/agents" 2>/dev/null || true)"
    ROLES_TARGET="$(resolve_path "$USER_SKILL/roles" 2>/dev/null || true)"
    if [[ "$TARGET" == "$EXPECTED_SKILL_TARGET" && "$AGENTS_TARGET" == "$EXPECTED_AGENTS_TARGET" && "$ROLES_TARGET" == "$EXPECTED_ROLES_TARGET" ]]; then
      pass "User skill mount healthy and points to *this* checkout: $USER_SKILL → $TARGET"
      MOUNT_POINTS_TO_CURRENT=1
    else
      warn "User skill mount exists but points to a *different* source tree (drift)"
      info "  Current doctor source (truth): $ROOT"
      info "  SKILL.md currently resolves to: $TARGET"
      info "  agents currently resolves to:   $AGENTS_TARGET"
      info "  roles currently resolves to:    $ROLES_TARGET"
      info "  → To adopt the current tree as the active mount, run:"
      info "     ./scripts/local/install-local.sh --force"
    fi
  else
    fail "User skill symlink exists but target is broken (missing file): $TARGET"
  fi
elif [[ -e "$USER_SKILL" ]]; then
  warn "Something exists at $USER_SKILL but it is not the expected symlink from install-local.sh"
else
  fail "No user skill mount at $USER_SKILL — run scripts/local/install-local.sh --force"
fi

# 5. ROLE-INDEX.md (the critical file after the rename)
if [[ -f "$USER_SKILL/agents/ROLE-INDEX.md" ]]; then
  pass "ROLE-INDEX.md present in mounted agents/ (no more AGENTS.md collision)"
elif [[ -f "$USER_SKILL/agents/AGENTS.md" ]]; then
  fail "Old agents/AGENTS.md still present — you have a stale mount. Re-run install-local.sh --force"
else
  fail "agents/ROLE-INDEX.md missing under the skill mount"
fi

# 5b. 16-role subagent symmetry — every agent file has a matching role toml.
ALL_ROLES=(leader intake-analyst researcher codebase-scout planner architect executor debugger test-engineer verifier code-reviewer security-reviewer performance-reviewer writer git-steward ux-reviewer)
SYMMETRY_OK=1
for role in "${ALL_ROLES[@]}"; do
  if [[ ! -f "$ROOT/agents/$role.md" || ! -f "$ROOT/roles/$role.toml" ]]; then
    fail "subagent pair missing: agents/$role.md or roles/$role.toml"
    SYMMETRY_OK=0
  fi
done
if [[ $SYMMETRY_OK -eq 1 ]]; then
  pass "All 16 agent/role pairs present and launchable as subagents"
fi

# 5c. Launcher dry-run — write and validate a 16-role agents JSON.
LAUNCH_DRY_DIR="$ROOT/.grok/omgb/runs/doctor-probe"
if bash "$ROOT/scripts/workflow/launch-omgb-team.sh" doctor-probe "doctor dry-run probe" >/dev/null 2>&1; then
  if node -e "const c=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); if(Object.keys(c).length!==16){process.exit(2)}" "$LAUNCH_DRY_DIR/agents-config.json" 2>/dev/null; then
    pass "launch-omgb-team.sh dry-run produced a valid 16-role agents JSON"
  else
    fail "launch-omgb-team.sh produced JSON but it does not contain exactly 16 roles"
  fi
else
  fail "launch-omgb-team.sh dry-run failed (try running it directly to see the error)"
fi

# 6. Local plugin payload (optional but nice)
LOCAL_PAYLOAD="$HOME/.grok/plugins/local/oh-my-grokbuild"
if [[ -d "$LOCAL_PAYLOAD" ]]; then
  PAYLOAD_OK=1
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
    if ! payload_entry_is_safe "$item"; then
      warn "Unsafe local-payload.txt entry: $item"
      PAYLOAD_OK=0
      continue
    fi
    item_path="${item%/}"
    if [[ ! -e "$LOCAL_PAYLOAD/$item_path" ]]; then
      warn "Local plugin payload missing $item_path (listed in local-payload.txt). Re-run install-local.sh --force"
      PAYLOAD_OK=0
    fi
  done < "$ROOT/local-payload.txt"

  if [[ $PAYLOAD_OK -eq 1 ]]; then
    pass "Local plugin payload present and matches local-payload.txt"
  else
    warn "Local plugin payload exists but is stale. Re-run install-local.sh --force"
  fi
else
  info "No local plugin payload at $LOCAL_PAYLOAD (normal if you only use the user-skill mount)"
fi

# 7. Recent install log (useful for support)
LATEST_LOG="$(ls -t "$ROOT/.omgb/evidence"/install-*.log 2>/dev/null | head -1 || true)"
if [[ -n "$LATEST_LOG" ]]; then
  info "Most recent install log: $LATEST_LOG"
else
  info "No install logs yet (run install-local.sh at least once)"
fi

echo
info "Manifest cross-ref:"
if node scripts/lib/doctor-manifest.mjs --print; then
  pass "Manifest cross-ref complete"
else
  warn "Manifest cross-ref found issues (see above)"
fi

echo
echo "Doctor summary:"
if [[ $MOUNT_POINTS_TO_CURRENT -eq 1 && -f "$USER_SKILL/agents/ROLE-INDEX.md" ]]; then
  echo -e "${GREEN}Looks good. The mount points to *this* checkout. Reload the Grok TUI (or run /plugins + /skills), then try /omgb inside the TUI.${RESET}"
  echo
  echo "Next commands you probably want:"
  echo "  node scripts/ci/validate.mjs --smoke"
  echo "  npm test"
  echo "  OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh"
  echo "  OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh   # full live probe"
  echo "  scripts/workflow/export-omgb-handoff.sh <your-task-slug>   # share run with Claude/Codex/Cursor"
  echo "  cat docs/WORKING-WITH-OTHER-AGENTS.md           # hybrid team guide"
else
  echo -e "${RED}Problems detected above (including possible mount drift). Re-run 'scripts/local/install-local.sh --force' from the correct checkout and then re-run this doctor.${RESET}"
fi
