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

# 4. User skill mount (what makes /omgb appear)
USER_SKILL="$HOME/.grok/skills/omgb"
if [[ -L "$USER_SKILL/SKILL.md" ]]; then
  TARGET="$(readlink -f "$USER_SKILL/SKILL.md")"
  if [[ -f "$TARGET" && "$TARGET" == *omgb* ]]; then
    pass "User skill mount healthy: $USER_SKILL → $TARGET"
  else
    fail "User skill symlink exists but target looks wrong: $TARGET"
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
  if [[ -f "$LOCAL_PAYLOAD/agents/ROLE-INDEX.md" ]]; then
    pass "Local plugin payload present and up-to-date"
  else
    warn "Local plugin payload exists but is stale (missing ROLE-INDEX.md). Re-run install-local.sh --force"
  fi
else
  info "No local plugin payload at $LOCAL_PAYLOAD (normal if you only use the user-skill mount)"
fi

# 7. Recent install log (useful for support)
LATEST_LOG="$(ls -t "$ROOT/.omc/evidence"/install-*.log 2>/dev/null | head -1 || true)"
if [[ -n "$LATEST_LOG" ]]; then
  info "Most recent install log: $LATEST_LOG"
else
  info "No install logs yet (run install-local.sh at least once)"
fi

echo
echo "Doctor summary:"
if [[ -L "$USER_SKILL/SKILL.md" && -f "$USER_SKILL/agents/ROLE-INDEX.md" ]]; then
  echo -e "${GREEN}Looks good. Reload the Grok TUI (or run /plugins + /skills), then try /omgb inside the TUI.${RESET}"
  echo
  echo "Next commands you probably want:"
  echo "  node scripts/ci/validate.mjs --smoke"
  echo "  npm test"
  echo "  scripts/local/e2e.sh"
  echo "  scripts/workflow/export-omgb-handoff.sh <your-task-slug>   # share run with Claude/Codex/Cursor"
  echo "  cat docs/WORKING-WITH-OTHER-AGENTS.md           # hybrid team guide"
else
  echo -e "${RED}Problems detected above. Re-run 'scripts/local/install-local.sh --force' and then re-run this doctor.${RESET}"
fi
