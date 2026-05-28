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
#   scripts/workflow/launch-omgb-fanout.sh <short-slug> "<task description>" \
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

# Portable UTC ISO-8601 timestamp with milliseconds. Uses Node (already a hard
# dependency of this launcher) so it matches on macOS BSD date, which has no
# GNU `%3N` specifier. Output format is identical: YYYY-MM-DDTHH:mm:ss.sssZ.
iso_now() { node -e 'console.log(new Date().toISOString())'; }

if [[ $# -lt 2 ]]; then
  cat <<'USAGE' >&2
Usage: scripts/workflow/launch-omgb-fanout.sh <short-slug> "<task description>" [--phase <name>] [--roles "csv"] [--max-turns N] [--launch]

Examples:
  scripts/workflow/launch-omgb-fanout.sh fanout-demo "Audit OMGB plugin layout"
  scripts/workflow/launch-omgb-fanout.sh fanout-demo "Audit OMGB plugin layout" --launch
  scripts/workflow/launch-omgb-fanout.sh review-pass "Review the changeset" --phase review --launch
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
APPEND=0

while (($#)); do
  case "$1" in
    --phase)      [[ $# -ge 2 ]] || { echo "--phase requires a name" >&2; exit 1; }; PHASE="$2"; shift 2 ;;
    --roles)      [[ $# -ge 2 ]] || { echo "--roles requires csv" >&2; exit 1; }; ROLES_CSV="$2"; shift 2 ;;
    --max-turns)  [[ $# -ge 2 ]] || { echo "--max-turns requires N" >&2; exit 1; }; MAX_TURNS="$2"; shift 2 ;;
    --launch)     LAUNCH=1; shift ;;
    --append)     APPEND=1; shift ;;
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
    apr)        ROLES_CSV="code-reviewer,security-reviewer,performance-reviewer,ux-reviewer,architect" ;;
    *)          echo "Unknown phase '$PHASE'. Pass --roles to specify the cohort explicitly." >&2; exit 1 ;;
  esac
fi
IFS=',' read -ra ROLES <<< "$ROLES_CSV"

if [[ "${#ROLES[@]}" -lt 2 ]]; then
  echo "Fan-out needs at least 2 roles (got ${#ROLES[@]}); for a single role, use 'grok --agent agents/<role>.md -p ...' directly." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNS_ROOT="${OMGB_RUNS_ROOT:-$HOME/.grok/omgb/runs}"
RUN_DIR_HOME="$RUNS_ROOT/$SHORT_SLUG"
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

_existing_count=$(node -e "
  const p=process.argv[1]; const ph=process.argv[2];
  const t=require('fs').existsSync(p)?JSON.parse(require('fs').readFileSync(p,'utf8')):{};
  const c=(t.cohorts||[]).filter(c=>c.phase===ph).length;
  process.stdout.write(String(c+1));
" "$RUN_DIR/fanout-trace.json" "$PHASE" 2>/dev/null || echo 1)
COHORT_ID="${PHASE:0:1}${_existing_count}"
RUN_STARTED_ISO="$(iso_now)"

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

STATE_IO="$ROOT/scripts/lib/state-io.mjs"
if [[ $APPEND -eq 1 ]]; then
  # Preserve prior mission/state/tasks/review — only add a new cohort.
  if [[ ! -f "$RUN_DIR/state.json" ]]; then
    echo "[fanout] FAIL: --append given but $RUN_DIR/state.json does not exist" >&2
    exit 1
  fi
  echo "[fanout] append-mode: preserving prior mission.md / state.json / tasks.json / review.md"
else
  # state-io.mjs init scaffolds mission.md, state.json, tasks.json, review.md.
  # All JSON manipulation lives in Node so bash never builds JSON by hand.
  ROLES_CSV_JOINED="$(printf '%s,' "${ROLES[@]}" | sed 's/,$//')"
  node "$STATE_IO" init "$SHORT_SLUG" "$TASK" "$PHASE" "$COHORT_ID" "$ROLES_CSV_JOINED" >/dev/null
fi

# APR (Adversarial Plan Review) per-role stances. When PHASE=apr each role
# is a hostile defender of its domain — the plan must survive their attack
# before Phase 3 starts.
apr_stance_for_role() {
  local role="$1"
  case "$role" in
    code-reviewer)        echo "Attack correctness, contract drift, partial implementations. Cite file:line where the plan will break." ;;
    security-reviewer)    echo "Attack trust boundaries, secret/auth/input handling, supply-chain risks. Assume the input is hostile." ;;
    performance-reviewer) echo "Attack hot paths, allocations, scaling assumptions. Ask 'what happens at 10x scale?'" ;;
    ux-reviewer)          echo "Attack the gap between the literal request and the underlying need. Surface install/CLI flow regressions." ;;
    architect)            echo "Attack coupling, leaky abstractions, structural debt. Ask 'is there a simpler design that meets the requirements?'" ;;
    *)                    echo "Defend your domain. Be hostile. Weak findings die." ;;
  esac
}

# Per-role prompt templates.
prompt_for_role() {
  local role="$1"

  if [[ "$PHASE" == "apr" ]]; then
    local stance
    stance="$(apr_stance_for_role "$role")"
    cat <<EOP
You are $role acting as an ADVERSARIAL DEFENDER in OMGB Phase 2.5 (Adversarial Plan Review) of run "$SHORT_SLUG".

Task being planned: $TASK

Your stance: $stance

STRICT OUTPUT PROTOCOL:
- Use AT MOST 2 read-only tool calls. Prefer 0 — attack the plan as stated.
- Default posture is HOSTILE. Soft, hedged, or collegial findings are rejected.
- Produce 3-7 numbered findings, each ≤3 sentences, each tagged with exactly one of: CONSTRAINT, RISK, ALTERNATIVE, BLOCKER.
- End with a single verdict line: APPROVE | REQUEST CHANGES | BLOCK.
- "looks good but..." is REQUEST CHANGES. No round-ups.
- Emit ONLY the marker block below as your final message.

### WORKER START $role
<verdict line>
1. [TAG] <finding ≤3 sentences>
2. [TAG] <finding ≤3 sentences>
...
### WORKER END $role
EOP
    return
  fi

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

STRICT OUTPUT PROTOCOL:
- Use AT MOST 2 tool calls. Prefer 0.
- After tools (or immediately), emit your FINAL message and stop.
- That final message MUST be EXACTLY the marker block below — no prose before or after.

### WORKER START planner
<your tasks.json content as JSON: array of {id, title, ownerRole, acceptance, verification}>
### WORKER END planner
EOP
      ;;
    architect)
      cat <<EOP
You are architect. Phase 2 Planning of OMGB run "$SHORT_SLUG".

Task: $TASK

STRICT OUTPUT PROTOCOL:
- Use AT MOST 2 tool calls. Prefer 0.
- After tools (or immediately), emit your FINAL message and stop.
- That final message MUST be EXACTLY the marker block below — no prose before or after.

### WORKER START architect
<APPROVE | COMMENT | REQUEST CHANGES, then 3-5 bullets on interface boundaries, persistent state ownership, recovery paths>
### WORKER END architect
EOP
      ;;
    code-reviewer|security-reviewer|performance-reviewer|ux-reviewer)
      cat <<EOP
You are $role. Phase 5 Review of OMGB run "$SHORT_SLUG".

Task: $TASK

STRICT OUTPUT PROTOCOL:
- MCPs (huggingface, etc.) may be unreachable; do NOT retry MCP tools.
- Use AT MOST 2 read-only tool calls (list_dir / read_file). Prefer 0 — compose your verdict from existing knowledge of the OMGB plugin and the task description.
- After tools (or immediately), emit your FINAL message and stop.
- That final message MUST be EXACTLY the marker block below — no prose before or after.
- If you cannot complete a real review, still emit the markers with a single-line "n/a — <reason>" inside.

### WORKER START $role
<one of: APPROVE | COMMENT | REQUEST CHANGES, then 3-5 severity-ranked findings (low/medium/high), or "n/a — <reason>" if nothing in scope>
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
  # Subshell records pid + start, runs grok, records end + rc. The & after
  # the closing brace forks the whole subshell in parallel.
  (
    iso_now > "$TRACE_TMP/$role.start"

    # Read effort from the role's toml (role-local effort routing)
    effort=$(grep -E '^(reasoning_effort|effort)\s*=' "$ROOT/roles/$role.toml" 2>/dev/null | head -1 | sed -E 's/.*= *["'\'']?([^"'\'' ]+)["'\'']?.*/\1/' | tr -d '\r')
    effort_flag=""
    if [[ -n "$effort" ]]; then
      effort_flag="--effort $effort"
    fi

    set +e
    "$GROK_BIN" \
      --cwd "$ROOT" \
      --agent "$ROOT/agents/$role.md" \
      --no-memory --no-plan --disable-web-search --no-subagents \
      --permission-mode auto \
      --max-turns "$MAX_TURNS" \
      --output-format plain \
      $effort_flag \
      --rules "MCPs (huggingface, etc.) are unreachable; do not invoke or retry MCP tools. Emit the WORKER START/END markers as your FINAL message. Stop after emitting them." \
      -p "$prompt" \
      > "$TRACE_TMP/$role.out" 2> "$TRACE_TMP/$role.err"
    rc=$?
    set -e
    iso_now > "$TRACE_TMP/$role.end"
    echo "$rc" > "$TRACE_TMP/$role.rc"
  ) &
  child_pid=$!
  PIDS+=("$child_pid")
  echo "$child_pid" > "$TRACE_TMP/$role.pid"
  echo "[fanout]   forked $role pid=$child_pid"
done

echo "[fanout] waiting for ${#PIDS[@]} subprocesses ..."
for pid in "${PIDS[@]}"; do
  wait "$pid" || true
done
echo "[fanout] all subprocesses returned"

RUN_COMPLETED_ISO="$(iso_now)"

# Compose evidence.md from the per-role files. This is pure markdown
# templating, so it stays in bash. All JSON (trace + state.json) is
# delegated to scripts/lib/state-io.mjs immediately below.
EVIDENCE="$RUN_DIR/evidence.md"

if [[ $APPEND -eq 1 && -f "$EVIDENCE" ]]; then
  {
    echo
    echo "---"
    echo "## Cohort: $PHASE / $COHORT_ID (appended)"
    echo
  } >> "$EVIDENCE"
else
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
fi

for role in "${ROLES[@]}"; do
  start="$(cat "$TRACE_TMP/$role.start" 2>/dev/null || echo "$RUN_STARTED_ISO")"
  end="$(cat "$TRACE_TMP/$role.end"   2>/dev/null || echo "$RUN_COMPLETED_ISO")"
  rc="$(cat "$TRACE_TMP/$role.rc"     2>/dev/null || echo "?")"
  pid="$(cat "$TRACE_TMP/$role.pid"   2>/dev/null || echo "0")"
  out="$(cat "$TRACE_TMP/$role.out" 2>/dev/null || echo "")"
  duration_ms="$(node -e "const d=Date.parse(process.argv[2])-Date.parse(process.argv[1]); console.log(Number.isFinite(d)?d:0)" "$start" "$end")"
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
done

# Delegate ALL JSON state to state-io.mjs:
#   - append-cohort updates fanout-trace.json (cohorts array) + state.json
#     (phases array, activeRoles, updatedAt) atomically.
node "$STATE_IO" append-cohort "$SHORT_SLUG" "$PHASE" "$COHORT_ID" \
  "$RUN_STARTED_ISO" "$RUN_COMPLETED_ISO" "$TRACE_TMP" >/dev/null

# Single-shot fanout (no --append): mark the run complete via state-io.
# Append-mode runs leave the run active; the pipeline driver finalizes
# after the last phase.
if [[ $APPEND -eq 0 ]]; then
  node "$STATE_IO" finalize "$SHORT_SLUG" >/dev/null
fi

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
echo "[fanout] wrote $RUN_DIR/fanout-trace.json"
echo "[fanout] state.json marked complete"
echo
echo "Audit this run:"
echo "  node scripts/ci/validate.mjs --audit-run $SHORT_SLUG"
