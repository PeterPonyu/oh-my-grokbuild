#!/usr/bin/env bash
# launch-omgb-pipeline.sh
#
# Chain multiple launch-omgb-fanout.sh invocations into a single OMGB run
# spanning several phases. The pipeline is the multi-phase form of fan-out:
# each phase forks its own role cohort in parallel, then control returns
# to the pipeline driver to start the next phase.
#
# Default pipeline (when --phases not given):
#   1. grounding   — codebase-scout + researcher (parallel)
#   2. review      — code-reviewer + security-reviewer + performance-reviewer + ux-reviewer (parallel)
#
# Why this exists: Grok 0.1.x's in-session leader cannot reliably emit
# multiple spawn_subagent calls in one assistant turn (every test produces
# ~80s gaps). The launcher-fanout mode replaces that by orchestrating role
# subprocesses from outside Grok. This pipeline wrapper does the same for a
# multi-phase run, producing a single run dir with one mission.md, one
# state.json (phases array spans every cohort), one evidence.md (Subagent
# blocks for every spawned role), and one fanout-trace.json (cohorts
# array). The audit treats it as a single OMGB run.
#
# Usage:
#   scripts/local/launch-omgb-pipeline.sh <short-slug> "<task description>" \
#     [--phases "grounding,review"] \
#     [--max-turns 30] \
#     [--launch]

set -euo pipefail

if [[ $# -lt 2 ]]; then
  cat <<'USAGE' >&2
Usage: scripts/local/launch-omgb-pipeline.sh <short-slug> "<task description>" [--phases "csv"] [--max-turns N] [--launch]

Examples:
  scripts/local/launch-omgb-pipeline.sh pipeline-demo "Audit OMGB plugin"
  scripts/local/launch-omgb-pipeline.sh pipeline-demo "Audit OMGB plugin" --launch
  scripts/local/launch-omgb-pipeline.sh pipeline-demo "Audit OMGB plugin" --phases "grounding,planning,review" --launch
USAGE
  exit 1
fi

SHORT_SLUG="$1"
TASK="$2"
shift 2

PHASES_CSV="grounding,review"
MAX_TURNS=30
LAUNCH=0

while (($#)); do
  case "$1" in
    --phases)     [[ $# -ge 2 ]] || { echo "--phases requires csv" >&2; exit 1; }; PHASES_CSV="$2"; shift 2 ;;
    --max-turns)  [[ $# -ge 2 ]] || { echo "--max-turns requires N" >&2; exit 1; }; MAX_TURNS="$2"; shift 2 ;;
    --launch)     LAUNCH=1; shift ;;
    -h|--help)    "$0"; exit 0 ;;
    *)            echo "unrecognized arg: $1" >&2; exit 1 ;;
  esac
done

IFS=',' read -ra PHASES <<< "$PHASES_CSV"
if [[ "${#PHASES[@]}" -lt 1 ]]; then
  echo "Pipeline needs at least one phase." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FANOUT="$ROOT/scripts/local/launch-omgb-fanout.sh"

if [[ ! -x "$FANOUT" ]]; then
  echo "[pipeline] FAIL: $FANOUT missing or not executable" >&2
  exit 1
fi

echo "[pipeline] slug:       $SHORT_SLUG"
echo "[pipeline] task:       $TASK"
echo "[pipeline] phases:     ${PHASES[*]}"
echo "[pipeline] max-turns:  $MAX_TURNS (per role)"

if [[ $LAUNCH -eq 0 ]]; then
  cat <<DRY
[pipeline] dry-run — no grok subprocesses spawned.
Each phase will invoke:
  $FANOUT $SHORT_SLUG "$TASK" --phase <phase> --max-turns $MAX_TURNS --launch [--append]
The first phase runs in normal mode (creates mission.md/state.json/etc.).
Subsequent phases run with --append (preserve prior artifacts, push new cohort onto state.json.phases + fanout-trace.json.cohorts + evidence.md).

Rerun with --launch to actually fork.
DRY
  exit 0
fi

# Run each phase sequentially; phases themselves contain parallel cohorts.
# The first phase initializes the run dir; subsequent phases use --append.
i=0
for phase in "${PHASES[@]}"; do
  echo
  echo "============================================================"
  echo "[pipeline] phase ${i}/${#PHASES[@]}: $phase"
  echo "============================================================"
  if [[ $i -eq 0 ]]; then
    "$FANOUT" "$SHORT_SLUG" "$TASK" --phase "$phase" --max-turns "$MAX_TURNS" --launch
  else
    "$FANOUT" "$SHORT_SLUG" "$TASK" --phase "$phase" --max-turns "$MAX_TURNS" --launch --append
  fi
  i=$((i+1))
done

# Pipeline finalizer: flip state.json to complete (fanout left it active
# on every --append call so successive phases don't trip the audit's
# "state=complete needs review.md Verdict" guard mid-pipeline).
RUN_DIR="$HOME/.grok/omgb/runs/$SHORT_SLUG"
PIPELINE_COMPLETED_ISO="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
node - <<EOF
const fs = require('fs')
const p = "$RUN_DIR/state.json"
const s = JSON.parse(fs.readFileSync(p, 'utf8'))
s.active = false
s.phase = "complete"
s.updatedAt = "$PIPELINE_COMPLETED_ISO"
fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n")
EOF
echo
echo "[pipeline] run complete. state.json marked phase=complete."
echo
echo "Audit:"
echo "  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG"
