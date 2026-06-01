#!/usr/bin/env bash
# launch-omgb-team.sh
#
# Launch an OMGB run as a real Grok subagent team.
#
# Usage:
#   scripts/workflow/launch-omgb-team.sh <short-slug> "<task description>" [--launch] [--roles "<csv>"]
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
Usage: scripts/workflow/launch-omgb-team.sh <short-slug> "<task description>" [--launch] [--roles "csv"]

Examples:
  scripts/workflow/launch-omgb-team.sh handoff-fix "Improve resume and subagent support"
  scripts/workflow/launch-omgb-team.sh handoff-fix "Improve resume and subagent support" --launch
  scripts/workflow/launch-omgb-team.sh perf-audit "Audit hot paths" --roles "leader,codebase-scout,performance-reviewer,test-engineer,verifier" --launch
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
# Grok writes session artifacts under ~/.grok/omgb/runs/<slug>/. The audit
# (validate.mjs --audit-run) reads <plugin>/.grok/omgb/runs/<slug>/. We make
# the home location canonical and the plugin-root path a symlink so both
# sides see the same files.
RUNS_ROOT="${OMGB_RUNS_ROOT:-$HOME/.grok/omgb/runs}"
RUN_DIR_HOME="$RUNS_ROOT/$SHORT_SLUG"
RUN_DIR_LINK="$ROOT/.grok/omgb/runs/$SHORT_SLUG"
RUN_DIR="$RUN_DIR_HOME"
CONFIG="$RUN_DIR/agents-config.json"

# All 16 roles, source of truth = disk
ALL_ROLES=(leader intake-analyst researcher codebase-scout planner architect executor debugger test-engineer verifier code-reviewer security-reviewer performance-reviewer writer git-steward ux-reviewer)

# Read-only set (bash 3.2-compatible: space-padded string, substring test
# below). everyone else gets permission_mode=default.
READONLY_ROLES=" intake-analyst researcher codebase-scout planner architect verifier code-reviewer security-reviewer performance-reviewer ux-reviewer "

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

mkdir -p "$RUN_DIR_HOME" "$ROOT/.grok/omgb/runs"
# Replace any stale dir/file at the plugin-root location with a symlink to
# the canonical home location. This is what makes the audit
# (validate.mjs --audit-run) able to find the run on completion.
if [[ -L "$RUN_DIR_LINK" ]]; then
  # Already a symlink — refresh it in case it points elsewhere.
  rm -f "$RUN_DIR_LINK"
elif [[ -e "$RUN_DIR_LINK" ]]; then
  echo "[launch] FAIL: $RUN_DIR_LINK exists and is not a symlink; refusing to overwrite" >&2
  exit 1
fi
ln -sfn "$RUN_DIR_HOME" "$RUN_DIR_LINK"
echo "[launch] canonical run dir: $RUN_DIR_HOME"
echo "[launch] plugin-root link:  $RUN_DIR_LINK -> $RUN_DIR_HOME"

# Validate role files exist before delegating to state-io.
for role in "${SELECTED[@]}"; do
  if [[ ! -f "$ROOT/agents/$role.md" ]]; then
    echo "[launch] FAIL: missing agents/$role.md" >&2
    exit 1
  fi
  if [[ ! -f "$ROOT/roles/$role.toml" ]]; then
    echo "[launch] FAIL: missing roles/$role.toml" >&2
    exit 1
  fi
done

# Build agents JSON via state-io.mjs (Node-for-JSON policy: bash never
# constructs JSON by string concatenation).
STATE_IO="$ROOT/scripts/lib/state-io.mjs"
ROLES_CSV_JOINED="$(printf '%s,' "${SELECTED[@]}" | sed 's/,$//')"
# Build readonly CSV: roles that appear in READONLY_ROLES string.
READONLY_CSV=""
for role in "${SELECTED[@]}"; do
  if [[ "$READONLY_ROLES" == *" $role "* ]]; then
    READONLY_CSV="${READONLY_CSV}${role},"
  fi
done
READONLY_CSV="${READONLY_CSV%,}"

node "$STATE_IO" build-agents-config "$SHORT_SLUG" "$ROLES_CSV_JOINED" "$READONLY_CSV" >/dev/null

ROLE_COUNT="${#SELECTED[@]}"
echo "[launch] wrote $CONFIG ($ROLE_COUNT roles)"

# Grok 0.1.212's --agents wants inline JSON, not an @<file> reference. Load the
# file we just wrote and pass it as a single argument.
AGENTS_INLINE="$(cat "$CONFIG")"

# Permission-mode auto: approve ordinary tool calls; the leader still pauses
# for genuinely destructive/credentialed actions per its own Continuation
# Discipline. Without this, Grok pops a confirmation between every step and
# the leader degrades into stop-and-ask serial mode.
CMD=(grok -s "omgb-$SHORT_SLUG" --cwd "$ROOT" --permission-mode auto -p "/omgb $TASK" --agents "$AGENTS_INLINE")

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

  grok -s omgb-$SHORT_SLUG --cwd "$ROOT" --permission-mode auto -p "/omgb $TASK" --agents "\$(cat $CONFIG)"

Or rerun this script with --launch.

Resume later with:
  grok --resume omgb-$SHORT_SLUG

Audit a completed run with:
  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG
NEXT
