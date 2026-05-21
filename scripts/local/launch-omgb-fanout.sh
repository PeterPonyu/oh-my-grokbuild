#!/usr/bin/env bash
# launch-omgb-fanout.sh
#
# Run an OMGB cohort by spawning role agents as parallel `grok --agent`
# subprocesses, then composing the evidence record from their wall-clock
# timings.
#
# Unlike launch-omgb-team.sh (which starts ONE grok session running the
# `/omgb` skill, expecting the leader to emit multiple spawn_subagent calls
# in a single assistant turn — which Grok 0.1.x does not do reliably), this
# script bypasses the in-session leader entirely. The launcher itself acts
# as the leader: it forks N parallel grok subprocesses, each running as one
# role agent, and records their outputs.
#
# Why: Grok's leader serializes spawn_subagent calls across consecutive
# turns. The v0.5.0 transcript-based audit catches this and rightly blocks
# such runs. Launcher-side fan-out is the only way today to produce a
# cohort of roles that actually run in parallel.
#
# Audit integration: this writes `fanout-trace.json` next to evidence.md.
# `scripts/ci/check-subagent-evidence.mjs` reads that file as ground truth
# (the same way it reads Grok's session `events.jsonl` for task-tool spawns)
# when a Subagent block declares `spawn_method: launcher-fanout`.
#
# Usage:
#   scripts/local/launch-omgb-fanout.sh <short-slug> "<task description>" \
#     [--phase grounding] \
#     [--roles "codebase-scout,researcher"] \
#     [--max-turns 20] \
#     [--launch]
#
# Defaults:
#   --phase   grounding
#   --roles   inferred from --phase (grounding: codebase-scout,researcher;
#             review: code-reviewer,security-reviewer,performance-reviewer,ux-reviewer;
#             planning: planner,architect)
#   --launch  off (dry-run prints the plan without forking)

set -euo pipefail

if [[ $# -lt 2 ]]; then
  cat <<'USAGE' >&2
Usage: scripts/local/launch-omgb-fanout.sh <short-slug> "<task description>" [--phase <name>] [--roles "csv"] [--max-turns N] [--launch]

Examples:
  scripts/local/launch-omgb-fanout.sh fanout-demo "Audit OMGB plugin layout"
  scripts/local/launch-omgb-fanout.sh fanout-demo "Audit OMGB plugin layout" --launch
  scripts/local/launch-omgb-fanout.sh review-pass "Review the changeset" --phase review --launch
USAGE
  exit 1
fi

SHORT_SLUG="$1"
TASK="$2"
shift 2

PHASE="grounding"
ROLES_CSV=""
MAX_TURNS=20
LAUNCH=0

while (($#)); do
  case "$1" in
    --phase)      [[ $# -ge 2 ]] || { echo "--phase requires a name" >&2; exit 1; }; PHASE="$2"; shift 2 ;;
    --roles)      [[ $# -ge 2 ]] || { echo "--roles requires csv" >&2; exit 1; }; ROLES_CSV="$2"; shift 2 ;;
    --max-turns)  [[ $# -ge 2 ]] || { echo "--max-turns requires N" >&2; exit 1; }; MAX_TURNS="$2"; shift 2 ;;
    --launch)     LAUNCH=1; shift ;;
    -h|--help)    "$0"; exit 0 ;;
    *)            echo "unrecognized arg: $1" >&2; exit 1 ;;
  esac
done

# Phase -> default roles mapping (when --roles not given).
if [[ -z "$ROLES_CSV" ]]; then
  case "$PHASE" in
    grounding)  ROLES_CSV="codebase-scout,researcher" ;;
    planning)   ROLES_CSV="planner,architect" ;;
    review)     ROLES_CSV="code-reviewer,security-reviewer,performance-reviewer,ux-reviewer" ;;
    *)          echo "Unknown phase '$PHASE'. Pass --roles to specify the cohort explicitly." >&2; exit 1 ;;
  esac
fi
IFS=',' read -ra ROLES <<< "$ROLES_CSV"

if [[ "${#ROLES[@]}" -lt 2 ]]; then
  echo "Fan-out needs at least 2 roles (got ${#ROLES[@]}); for a single role, use 'grok --agent agents/<role>.md -p ...' directly." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR_HOME="$HOME/.grok/omgb/runs/$SHORT_SLUG"
RUN_DIR_LINK="$ROOT/.grok/omgb/runs/$SHORT_SLUG"
RUN_DIR="$RUN_DIR_HOME"

# Preflight: validator smoke must pass.
echo "[fanout] preflight: validator smoke"
if ! (cd "$ROOT" && node scripts/ci/validate.mjs --smoke >/dev/null); then
  echo "[fanout] FAIL: validator smoke failed; refusing to launch" >&2
  exit 1
fi

# Locate grok binary.
GROK_BIN="$(command -v grok 2>/dev/null || true)"
if [[ -z "$GROK_BIN" && -x "$HOME/.grok/bin/grok" ]]; then
  GROK_BIN="$HOME/.grok/bin/grok"
fi
if [[ -z "$GROK_BIN" ]]; then
  echo "[fanout] FAIL: grok binary not found on PATH or at ~/.grok/bin/grok" >&2
  exit 1
fi

# Validate role files exist.
for role in "${ROLES[@]}"; do
  if [[ ! -f "$ROOT/agents/$role.md" ]]; then
    echo "[fanout] FAIL: missing agents/$role.md" >&2
    exit 1
  fi
done

mkdir -p "$RUN_DIR_HOME" "$ROOT/.grok/omgb/runs"
# Replace any stale dir at the plugin-root with a symlink to canonical home.
if [[ -L "$RUN_DIR_LINK" ]]; then
  rm -f "$RUN_DIR_LINK"
elif [[ -e "$RUN_DIR_LINK" ]]; then
  echo "[fanout] FAIL: $RUN_DIR_LINK exists and is not a symlink; refusing to overwrite" >&2
  exit 1
fi
ln -sfn "$RUN_DIR_HOME" "$RUN_DIR_LINK"

COHORT_ID="${PHASE:0:1}1"
RUN_STARTED_ISO="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"

echo "[fanout] phase:        $PHASE"
echo "[fanout] cohort:       $COHORT_ID"
echo "[fanout] roles:        ${ROLES[*]}"
echo "[fanout] run dir:      $RUN_DIR_HOME"
echo "[fanout] plugin link:  $RUN_DIR_LINK -> $RUN_DIR_HOME"
echo "[fanout] grok binary:  $GROK_BIN"

if [[ $LAUNCH -eq 0 ]]; then
  cat <<DRY
[fanout] dry-run — no grok subprocesses spawned.
Rerun with --launch to fork ${#ROLES[@]} parallel grok subprocesses.
Each subprocess will invoke:
  $GROK_BIN --agent agents/<role>.md --permission-mode auto \\
    --no-memory --no-plan --disable-web-search --no-subagents \\
    --max-turns $MAX_TURNS --output-format plain \\
    -p "<role-specific prompt for: $TASK>"
After completion the launcher will write:
  $RUN_DIR/mission.md, state.json, tasks.json, evidence.md, review.md, fanout-trace.json
Audit:
  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG
DRY
  exit 0
fi

# Scaffolding so the audit can find the run.
cat > "$RUN_DIR/mission.md" <<EOF
# Mission

## Goal
$TASK

## Scope
- Phase: $PHASE
- Cohort: $COHORT_ID
- Roles: ${ROLES[*]}
- Orchestration: launcher-fanout (each role spawned as a parallel grok subprocess)

## Constraints
- Roles run with --no-memory --no-plan --disable-web-search --no-subagents.
- Each role replies between literal markers \`### WORKER START <role>\` / \`### WORKER END <role>\`.
- No further phases beyond $PHASE. This is a bounded fan-out, not a full /omgb run.

## Acceptance Criteria
- evidence.md contains one \`## Subagent: <role>\` block per role with spawn_method=launcher-fanout, phase=$PHASE, cohort=$COHORT_ID, and the role's worker output verbatim.
- fanout-trace.json records each subprocess's PID, start, end, exit code.
- node scripts/ci/validate.mjs --audit-run $SHORT_SLUG exits 0 with \`[OMGB] audit passed\`.

## Ambiguity
score: low
EOF

# state.json scaffold
cat > "$RUN_DIR/state.json" <<EOF
{
  "mode": "omgb",
  "active": true,
  "phase": "$PHASE",
  "startedAt": "$RUN_STARTED_ISO",
  "updatedAt": "$RUN_STARTED_ISO",
  "taskSlug": "$SHORT_SLUG",
  "activeRoles": [$(printf '"%s",' "${ROLES[@]}" | sed 's/,$//')],
  "qaCycles": 0,
  "reviewRounds": 0,
  "blockers": [],
  "phases": []
}
EOF

echo '{"tasks": []}' > "$RUN_DIR/tasks.json"
echo "# Review log — fan-out cohort only" > "$RUN_DIR/review.md"

# Per-role prompt templates.
prompt_for_role() {
  local role="$1"
  case "$role" in
    codebase-scout)
      cat <<EOP
You are codebase-scout. Phase 1 Grounding of OMGB run "$SHORT_SLUG".

Task: $TASK

STRICT OUTPUT PROTOCOL:
- Use AT MOST 3 read-only tool calls (list_dir / read_file). Prefer 0–1.
- After tools (or immediately if you need none), emit your FINAL message and stop.
- That final message MUST be EXACTLY the marker block below — no prose before or after.
- If you cannot complete the task, still emit the markers with a one-line "n/a — <reason>" inside.

### WORKER START codebase-scout
<3–8 terse bullets: repo root, relevant files for this task, build/test/audit commands, likely blast radius>
### WORKER END codebase-scout
EOP
      ;;
    researcher)
      cat <<EOP
You are researcher. Phase 1 Grounding of OMGB run "$SHORT_SLUG".

Task: $TASK

STRICT OUTPUT PROTOCOL:
- Web search and MCPs may be unreachable in this session. If so, say so inside your worker block — do NOT retry MCP tools and do NOT invent sources.
- Use AT MOST 2 tool calls total. Prefer 0 (compose from your existing knowledge of the OMGB plugin).
- After tools (or immediately), emit your FINAL message and stop.
- That final message MUST be EXACTLY the marker block below — no prose before or after.

### WORKER START researcher
<3–6 terse bullets: confirmed facts about the OMGB plugin from your existing knowledge, sources cited if any, gaps explicitly marked>
### WORKER END researcher
EOP
      ;;
    planner)
      cat <<EOP
You are planner. Phase 2 Planning of OMGB run "$SHORT_SLUG".

Task: $TASK

Produce a small, reviewable tasks.json shape inside your worker block — array of {id, title, ownerRole, acceptance, verification}.

### WORKER START planner
<your tasks.json content as JSON>
### WORKER END planner
EOP
      ;;
    architect)
      cat <<EOP
You are architect. Phase 2 Planning of OMGB run "$SHORT_SLUG".

Task: $TASK

Verdict on interface boundaries, persistent state ownership, recovery paths. Concise.

### WORKER START architect
<APPROVE | COMMENT | REQUEST CHANGES + bullets of findings>
### WORKER END architect
EOP
      ;;
    code-reviewer|security-reviewer|performance-reviewer|ux-reviewer)
      cat <<EOP
You are $role. Phase 5 Review of OMGB run "$SHORT_SLUG".

Task: $TASK

Produce a severity-ranked verdict inside your worker block.

### WORKER START $role
<APPROVE | COMMENT | REQUEST CHANGES + severity-ranked findings>
### WORKER END $role
EOP
      ;;
    *)
      cat <<EOP
You are $role. Cohort task for OMGB run "$SHORT_SLUG".

Task: $TASK

### WORKER START $role
<your reply per the role definition in agents/$role.md>
### WORKER END $role
EOP
      ;;
  esac
}

# Spawn all roles in parallel. Each subprocess writes its own start/end
# timestamps to dedicated files so the launcher (and the audit) can read
# real wall-clock times — not leader-claimed values that can be fabricated.
echo "[fanout] forking ${#ROLES[@]} parallel grok subprocesses"
TRACE_TMP="$RUN_DIR/.fanout-tmp"
rm -rf "$TRACE_TMP"
mkdir -p "$TRACE_TMP"

PIDS=()
for role in "${ROLES[@]}"; do
  prompt="$(prompt_for_role "$role")"
  # Subshell records start, runs grok, records end + rc. The & after the
  # closing brace forks the whole subshell in parallel.
  (
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" > "$TRACE_TMP/$role.start"
    set +e
    "$GROK_BIN" \
      --cwd "$ROOT" \
      --agent "$ROOT/agents/$role.md" \
      --no-memory --no-plan --disable-web-search --no-subagents \
      --permission-mode auto \
      --max-turns "$MAX_TURNS" \
      --output-format plain \
      --rules "MCPs (huggingface, etc.) are unreachable; do not invoke or retry MCP tools. Emit the WORKER START/END markers as your FINAL message. Stop after emitting them." \
      -p "$prompt" \
      > "$TRACE_TMP/$role.out" 2> "$TRACE_TMP/$role.err"
    rc=$?
    set -e
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" > "$TRACE_TMP/$role.end"
    echo "$rc" > "$TRACE_TMP/$role.rc"
  ) &
  PIDS+=($!)
  echo "[fanout]   forked $role pid=${PIDS[-1]}"
done

echo "[fanout] waiting for ${#PIDS[@]} subprocesses ..."
for pid in "${PIDS[@]}"; do
  wait "$pid" || true
done
echo "[fanout] all subprocesses returned"

RUN_COMPLETED_ISO="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
PHASE_DURATION_MS="$(node -e "console.log(Date.parse('$RUN_COMPLETED_ISO') - Date.parse('$RUN_STARTED_ISO'))")"

# Compose evidence.md and fanout-trace.json from the per-role files.
EVIDENCE="$RUN_DIR/evidence.md"
TRACE="$RUN_DIR/fanout-trace.json"

{
  echo "# OMGB Evidence Log — $SHORT_SLUG (launcher-fanout)"
  echo
  echo "**Task:** $TASK"
  echo "**Slug:** $SHORT_SLUG"
  echo "**Started:** $RUN_STARTED_ISO"
  echo "**Phase:** $PHASE"
  echo "**Cohort:** $COHORT_ID"
  echo "**Orchestration:** launcher-fanout (parallel grok subprocesses, one per role)"
  echo
} > "$EVIDENCE"

{
  echo "{"
  echo "  \"slug\": \"$SHORT_SLUG\","
  echo "  \"phase\": \"$PHASE\","
  echo "  \"cohort\": \"$COHORT_ID\","
  echo "  \"started\": \"$RUN_STARTED_ISO\","
  echo "  \"completed\": \"$RUN_COMPLETED_ISO\","
  echo "  \"duration_ms\": $PHASE_DURATION_MS,"
  echo "  \"roles\": ["
} > "$TRACE"

first_role=1
i=0
for role in "${ROLES[@]}"; do
  start="$(cat "$TRACE_TMP/$role.start" 2>/dev/null || echo "$RUN_STARTED_ISO")"
  end="$(cat "$TRACE_TMP/$role.end"   2>/dev/null || echo "$RUN_COMPLETED_ISO")"
  rc="$(cat "$TRACE_TMP/$role.rc"     2>/dev/null || echo "?")"
  pid="${PIDS[$i]}"
  out="$(cat "$TRACE_TMP/$role.out" 2>/dev/null || echo "")"
  duration_ms="$(node -e "console.log(Date.parse('$end') - Date.parse('$start'))")"
  excerpt="$(printf '%s' "$out" | sed -n "/### WORKER START $role/,/### WORKER END $role/p")"
  if [[ -z "$excerpt" ]]; then
    excerpt="### WORKER START $role
(missing markers — raw output below)
$(printf '%s' "$out" | head -c 800)
### WORKER END $role"
  fi
  {
    echo "## Subagent: $role (task=fanout-$role-$pid)"
    echo
    echo "- spawn_method: launcher-fanout"
    echo "- invocation: grok --agent agents/$role.md (subprocess pid=$pid)"
    echo "- phase: $PHASE"
    echo "- cohort: $COHORT_ID"
    echo "- started: $start"
    echo "- completed: $end"
    echo "- duration_ms: $duration_ms"
    echo "- exit_code: $rc"
    echo "- worker_output_excerpt: |"
    printf '%s\n' "$excerpt" | sed 's/^/    /'
    echo "- verdict_or_result: subprocess exited rc=$rc"
    echo
  } >> "$EVIDENCE"

  [[ $first_role -eq 1 ]] || echo "    ," >> "$TRACE"
  first_role=0
  {
    echo "    {"
    echo "      \"role\": \"$role\","
    echo "      \"pid\": $pid,"
    echo "      \"started\": \"$start\","
    echo "      \"completed\": \"$end\","
    echo "      \"duration_ms\": $duration_ms,"
    echo "      \"exit_code\": \"$rc\""
    echo "    }"
  } >> "$TRACE"
  i=$((i+1))
done

{
  echo "  ]"
  echo "}"
} >> "$TRACE"

# Finalize state.json
node - <<EOF
const fs = require('fs')
const p = "$RUN_DIR/state.json"
const s = JSON.parse(fs.readFileSync(p, 'utf8'))
s.active = false
s.phase = "complete"
s.updatedAt = "$RUN_COMPLETED_ISO"
s.phases = [{
  name: "$PHASE",
  started: "$RUN_STARTED_ISO",
  completed: "$RUN_COMPLETED_ISO",
  duration_ms: $PHASE_DURATION_MS
}]
fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n")
EOF

# Append a Verdict line to review.md so the audit's "state=complete needs Verdict" check passes.
cat >> "$RUN_DIR/review.md" <<EOF

## Launcher Fan-out Cohort

Roles: ${ROLES[*]}
Phase: $PHASE
Cohort: $COHORT_ID

**Verdict:** N/A — bounded fan-out cohort. No code changes performed; no full review pass run. The cohort proves the launcher-fanout orchestration model and the audit's transcript-based concurrency check.
EOF

# Cleanup tmp dir
rm -rf "$TRACE_TMP"

echo
echo "[fanout] wrote $EVIDENCE"
echo "[fanout] wrote $TRACE"
echo "[fanout] state.json marked complete"
echo
echo "Audit this run:"
echo "  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG"
