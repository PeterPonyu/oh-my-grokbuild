#!/usr/bin/env bash
# launch-omgb-team.sh
#
# Launch an OMGB run as a real Grok subagent team.
#
# Usage:
#   scripts/local/launch-omgb-team.sh <short-slug> "<task description>" [--launch] [--roles "<csv>"]
#
# Defaults to --dry-run: writes the agents JSON and prints the exact Grok
# command, but does not invoke Grok. Pass --launch to actually start the
# session.
#
# Roles defaults to the full 16-role catalog (from agents/ + roles/ on disk).
# Override with --roles "leader,executor,test-engineer,..." when you want a
# slimmer team for a small task.
#
# What it does:
#   - Validates the source repo via scripts/ci/validate.mjs --smoke (refuses on failure).
#   - Builds a deterministic agents-config.json from agents/<role>.md + roles/<role>.toml.
#   - Verifies the JSON parses.
#   - Writes the JSON into .grok/omgb/runs/<slug>/agents-config.json (idempotent).
#   - Either prints the launch command (dry run) or invokes Grok with -s, --cwd,
#     -p, and --agents.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  cat <<'USAGE' >&2
Usage: scripts/local/launch-omgb-team.sh <short-slug> "<task description>" [--launch] [--roles "csv"]

Examples:
  scripts/local/launch-omgb-team.sh handoff-fix "Improve resume and subagent support"
  scripts/local/launch-omgb-team.sh handoff-fix "Improve resume and subagent support" --launch
  scripts/local/launch-omgb-team.sh perf-audit "Audit hot paths" --roles "leader,codebase-scout,performance-reviewer,test-engineer,verifier" --launch
USAGE
  exit 1
fi

SHORT_SLUG="$1"
TASK="$2"
shift 2

LAUNCH=0
ROLES_CSV=""
while (($#)); do
  case "$1" in
    --launch)  LAUNCH=1; shift ;;
    --roles)   [[ $# -ge 2 ]] || { echo "--roles requires csv" >&2; exit 1; }; ROLES_CSV="$2"; shift 2 ;;
    -h|--help) "$0"; exit 0 ;;
    *) echo "unrecognized arg: $1" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$ROOT/.grok/omgb/runs/$SHORT_SLUG"
CONFIG="$RUN_DIR/agents-config.json"

# All 16 roles, source of truth = disk
ALL_ROLES=(leader intake-analyst researcher codebase-scout planner architect executor debugger test-engineer verifier code-reviewer security-reviewer performance-reviewer writer git-steward ux-reviewer)

# Read-only set; everyone else gets permission_mode=default
declare -A READONLY
for r in intake-analyst researcher codebase-scout planner architect verifier code-reviewer security-reviewer performance-reviewer ux-reviewer; do
  READONLY[$r]=1
done

if [[ -n "$ROLES_CSV" ]]; then
  IFS=',' read -ra SELECTED <<< "$ROLES_CSV"
else
  SELECTED=("${ALL_ROLES[@]}")
fi

# Preflight: validator smoke must pass.
echo "[launch] preflight: validator smoke"
if ! (cd "$ROOT" && node scripts/ci/validate.mjs --smoke >/dev/null); then
  echo "[launch] FAIL: validator smoke failed; refusing to launch" >&2
  exit 1
fi

mkdir -p "$RUN_DIR"

# Build agents JSON
{
  echo "{"
  first=1
  for role in "${SELECTED[@]}"; do
    if [[ ! -f "$ROOT/agents/$role.md" ]]; then
      echo "[launch] FAIL: missing agents/$role.md" >&2
      exit 1
    fi
    if [[ ! -f "$ROOT/roles/$role.toml" ]]; then
      echo "[launch] FAIL: missing roles/$role.toml" >&2
      exit 1
    fi
    mode="default"
    if [[ -n "${READONLY[$role]:-}" ]]; then
      mode="read-only"
    fi
    [[ $first -eq 1 ]] || echo "  ,"
    first=0
    printf '  "%s": {\n' "$role"
    printf '    "name": "%s",\n' "$role"
    printf '    "prompt_file": "agents/%s.md",\n' "$role"
    printf '    "role": "roles/%s.toml",\n' "$role"
    printf '    "permission_mode": "%s"\n' "$mode"
    printf '  }'
  done
  echo
  echo "}"
} > "$CONFIG"

# JSON validity check (no jq dependency)
if ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$CONFIG"; then
  echo "[launch] FAIL: generated $CONFIG is not valid JSON" >&2
  exit 1
fi

ROLE_COUNT="${#SELECTED[@]}"
echo "[launch] wrote $CONFIG ($ROLE_COUNT roles)"

# Grok 0.1.212's --agents wants inline JSON, not an @<file> reference. Load the
# file we just wrote and pass it as a single argument.
AGENTS_INLINE="$(cat "$CONFIG")"

CMD=(grok -s "omgb-$SHORT_SLUG" --cwd "$ROOT" -p "/omgb $TASK" --agents "$AGENTS_INLINE")

if [[ $LAUNCH -eq 1 ]]; then
  echo "[launch] invoking grok with $ROLE_COUNT-role subagent team"
  echo "[launch] session: omgb-$SHORT_SLUG"
  exec "${CMD[@]}"
fi

cat <<NEXT
[launch] dry-run — Grok was not invoked.
[launch] run directory: $RUN_DIR
[launch] agents config: $CONFIG ($ROLE_COUNT roles)

Run this to start the team (passing JSON inline because Grok 0.1.x rejects @<file>):

  grok -s omgb-$SHORT_SLUG --cwd "$ROOT" -p "/omgb $TASK" --agents "\$(cat $CONFIG)"

Or rerun this script with --launch.

Resume later with:
  grok --resume omgb-$SHORT_SLUG

Audit a completed run with:
  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG
NEXT
