#!/usr/bin/env bash
# launch-omgb-team.sh
#
# Convenience wrapper to start an OMGB run using real parallel subagents.
#
# Usage:
#   scripts/launch-omgb-team.sh <short-slug> "<your task description>"
#
# Example:
#   scripts/launch-omgb-team.sh handoff-fix "fix resume UX and document real subagent usage"
#
# It will:
#   - Use the short slug for both the session name (omgb-<slug>) and run directory
#   - Build a --agents JSON from the available role files
#   - Start grok with a named session

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <short-slug> \"<task description>\""
  echo "Example: $0 handoff-fix \"Improve resume and subagent support\""
  exit 1
fi

SHORT_SLUG="$1"
shift
TASK="$*"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/.grok/omgb/runs/$SHORT_SLUG"

mkdir -p "$RUN_DIR"

# Build a minimal but useful agents JSON (leader + core roles)
# You can edit this or make it more complete later.
AGENTS_JSON=$(cat <<'JSON'
{
  "leader": {
    "name": "leader",
    "prompt_file": "agents/leader.md",
    "role": "roles/leader.toml",
    "permission_mode": "default"
  },
  "intake-analyst": {
    "name": "intake-analyst",
    "prompt_file": "agents/intake-analyst.md",
    "role": "roles/intake-analyst.toml",
    "permission_mode": "read-only"
  },
  "codebase-scout": {
    "name": "codebase-scout",
    "prompt_file": "agents/codebase-scout.md",
    "role": "roles/codebase-scout.toml",
    "permission_mode": "read-only"
  },
  "planner": {
    "name": "planner",
    "prompt_file": "agents/planner.md",
    "role": "roles/planner.toml",
    "permission_mode": "read-only"
  },
  "executor": {
    "name": "executor",
    "prompt_file": "agents/executor.md",
    "role": "roles/executor.toml",
    "permission_mode": "default"
  },
  "test-engineer": {
    "name": "test-engineer",
    "prompt_file": "agents/test-engineer.md",
    "role": "roles/test-engineer.toml",
    "permission_mode": "default"
  },
  "verifier": {
    "name": "verifier",
    "prompt_file": "agents/verifier.md",
    "role": "roles/verifier.toml",
    "permission_mode": "read-only"
  },
  "code-reviewer": {
    "name": "code-reviewer",
    "prompt_file": "agents/code-reviewer.md",
    "role": "roles/code-reviewer.toml",
    "permission_mode": "read-only"
  }
}
JSON
)

# Write the config into the run dir for reproducibility
echo "$AGENTS_JSON" > "$RUN_DIR/agents-config.json"

echo "Launching OMGB team with short slug: $SHORT_SLUG"
echo "Session name will be: omgb-$SHORT_SLUG"
echo "Task: $TASK"
echo
echo "Run directory: $RUN_DIR"
echo "Using agents config: $RUN_DIR/agents-config.json"
echo

# The actual launch command the user can copy or we execute
CMD=(grok -s "omgb-$SHORT_SLUG" --cwd "$PWD" -p "/omgb $TASK" --agents "@$RUN_DIR/agents-config.json")

echo "Recommended command (copy and run in a full Grok environment that supports --agents):"
echo
echo "${CMD[*]}"
echo
echo "Files created for this short-slug run:"
echo "  $RUN_DIR/agents-config.json"
echo "  $RUN_DIR/  (ready for .grok/omgb/runs/$SHORT_SLUG/)"
echo
echo "You can now do:"
echo "  grok --resume omgb-$SHORT_SLUG"
echo "  # or start a fresh short-slug run with the command above"
echo
echo "Note: Real parallel subagent execution requires a Grok host that supports --agents."
echo "In restricted environments the team will fall back to sequential simulation."
