# OMGB — Future Plan (v0.8.0 → v0.13.0)

ROI-ranked roadmap derived from comparing OMC v4.13.5 and OMO v4.2.3 against
OMGB v0.7.0's surface. Each item lists why it applies, what changes, and
roughly how big the work is. Mark `done` next to the heading as items ship.

> **Constraint check.** OMGB's manifest is `skills/` only — no MCP servers,
> no hooks, no custom commands. Any port that would add MCP/hooks is
> rejected up front. The plan only lists items that respect that charter.

## Grok-model reality check (2026-05-21)

`grok models` on this machine returns exactly:

```
Default model: grok-build
Available models:
  * grok-build (default)
```

So "per-role MODEL routing" is **not** applicable today — there is no other
model to route to. What IS available on the same binary is reasoning-budget
routing via `--effort <low|medium|high|xhigh|max>`. That's the v0.9.0 plan
below.

If xAI adds more models later, the same `roles/<role>.toml` field surface
adds `model: <id>` trivially. No schema break.

---

## v0.7.1 — Script reorganization + bash 3.2 macOS compatibility  · cleanup  · ~30 min

**Why.** The original `scripts/ci/` mixed CI gates (Node validators) with a
workflow script (`export-omgb-handoff.sh`). And `scripts/local/` mixed
install/diagnostic tools with run-driving launchers. Three-bucket model is
cleaner:

| Folder | Audience | Touches `~/.grok/`? |
| --- | --- | --- |
| `scripts/ci/` | CI runner | no — pure Node, no Grok |
| `scripts/local/` | User setting up their machine | yes (mount/auth/probe) |
| `scripts/workflow/` | User driving an OMGB run | yes (writes run artifacts, invokes grok) |

Bash compatibility: target **bash 3.2 (macOS default) and newer**. Audit
caught 2 idioms used:

- `${PIDS[-1]}` (negative array index, bash 4.3+) in fanout.sh
- `declare -A READONLY` (associative array, bash 4+) in team.sh

Both rewritten without dependencies. Repo-wide grep regression check
documented in `scripts/README.md`.

**Changes (all shipped together as part of v0.7.1).**

- `git mv scripts/local/launch-omgb-*.sh` → `scripts/workflow/`
- `git mv scripts/ci/export-omgb-handoff.sh` → `scripts/workflow/`
- Rewrite 23 reference sites (markdown + scripts).
- Replace `${PIDS[-1]}` with `${PIDS[$((${#PIDS[@]}-1))]}`.
- Replace `declare -A READONLY` with space-padded string + substring test.
- Update `scripts/README.md` with new layout, bash-compat policy, and the
  "when to use Node vs Bash" matrix.

## v0.8.0 — Auto-retry on placeholder output  · HIGH ROI · ~4 hours

**Why.** Today when a fan-out subprocess returns without emitting the
`### WORKER START/END <role>` markers, `launch-omgb-fanout.sh` synthesizes
a placeholder (`(missing markers — raw output below)`). The audit catches
that via `has_placeholder_marker` and emits a `[medium]` finding, but the
run is allowed to complete with a degraded result. OMO's `delegate-task-retry`
pattern says: don't surrender, re-spawn the stuck role with a sharper
prompt.

**This is real launcher/shell logic, NOT just a markdown tweak.** The
v0.7.0 work that tightened the STRICT OUTPUT PROTOCOL inside the prompt
templates was the PREVENTIVE half. v0.9.0 is the CORRECTIVE half: detect
the placeholder, fork again. Two distinct layers, both needed.

**Changes.**

- `scripts/workflow/launch-omgb-fanout.sh`:
  - After `wait $pid` per role, scan `$TRACE_TMP/$role.out` for the literal
    `(missing markers — raw output below)`. (Same string the audit looks for.)
  - If found AND `$role.attempt < $MAX_RETRIES`: re-fork the subprocess
    with a noisier prompt prefix and a stricter `--rules` directive
    ("you MUST emit the markers in your next message, with no preamble").
    Default `MAX_RETRIES=1`. Tunable via `--max-retries N`.
  - Record both attempts in the trace:
    ```json
    {
      "role": "code-reviewer",
      "attempts": [
        {"pid": 105466, "started": "...", "completed": "...", "exit_code": "1", "placeholder": true},
        {"pid": 105520, "started": "...", "completed": "...", "exit_code": "0", "placeholder": false}
      ]
    }
    ```
  - Evidence block carries the latest successful attempt; older attempts
    are kept in the trace for diagnostics.

- `scripts/ci/check-subagent-evidence.mjs`:
  - When `attempts: [...]` shape is present, treat the last attempt as
    the authoritative one for `has_placeholder_marker`.
  - Emit a `[low]` advisory finding when a successful attempt followed a
    placeholder attempt ("role X retried once and succeeded — consider
    tuning the initial prompt").

**Confidence.** OMO's delegate-task-retry already proves this pattern.
Detection is trivial (string match the placeholder line); re-fork is just
a second pass through the same loop.

## v0.9.0 — Per-role effort routing  · HIGH ROI · ~1 day

**Why.** Today every `grok --agent <role>` subprocess inherits the default
effort level. Reviewer-style roles (architect, security-reviewer) benefit
from `high` or `xhigh`; mapping-style roles (codebase-scout, writer) need
`low` or `medium`. Cheaper reasoning + faster wall clock for ~half the
roles in a typical pipeline.

**Changes.**

- `roles/<role>.toml` already has `reasoning_effort` but the launcher
  ignores it. Honor it:
  - Plain effort: `effort: low|medium|high|xhigh|max` → passed via `--effort`.
  - Reasoning effort: `reasoning_effort: low|medium|high` → passed via
    `--reasoning-effort` if Grok exposes a reasoning model.
- `scripts/workflow/launch-omgb-fanout.sh`: read the toml per role; pass the
  flag(s).
- `scripts/ci/validate.mjs --sanity`: validate every role toml's
  effort/reasoning_effort against the allowed sets.
- Document the role → effort matrix in SKILL.md and AGENT-INSTALL.md.
- Suggested defaults:
  - `low`: codebase-scout, writer, git-steward
  - `medium`: intake-analyst, planner, researcher, executor, test-engineer, ux-reviewer
  - `high`: architect, debugger, verifier, code-reviewer, security-reviewer, performance-reviewer
  - `xhigh`/`max`: only on explicit user override

## v0.10.0 — Pipeline resume  · MEDIUM-HIGH ROI · ~1 day

**Why.** A multi-phase `launch-omgb-pipeline.sh` run that fails mid-flight
(network drop, host OOM, transient Grok error) currently loses the work
of every phase that already completed. State is fully captured in
`state.json.phases` and `fanout-trace.json.cohorts`; resume should be
mechanical.

**Changes.**

- `scripts/workflow/launch-omgb-pipeline.sh --resume`: at start, read
  `$RUN_DIR/state.json`. Compute `done_phases = state.phases.map(p => p.name)`.
  Iterate the requested `--phases` and skip any that are already in
  `done_phases`. For the first not-done phase, call fanout with `--append`
  (state already exists). For subsequent ones, normal `--append` flow.
- If no `state.json` exists yet, `--resume` falls back to a normal first run.
- Audit unaffected — same state.json, same trace, same evidence shape.

## v0.11.0 — Pre-flight Socratic intake  · MEDIUM ROI · ~1 day

**Why.** Mapped from OMC's `/deep-interview`. Many user `<task description>`
inputs to the pipeline are vague — "audit the plugin," "improve UX," etc.
The downstream cohorts produce better work against a structured mission
than against a one-line prompt. A solo `intake-analyst` subprocess BEFORE
the pipeline forks can crystallize ambiguity in a single Grok call.

**Changes.**

- `scripts/workflow/launch-omgb-pipeline.sh`: new `--intake` flag (default on,
  opt out with `--no-intake`).
  - Runs one `grok --agent agents/intake-analyst.md` subprocess with a
    template that demands the Mission shape (goal / scope / non-goals /
    constraints / acceptance criteria / ambiguity score).
  - Writes the result to `$RUN_DIR/mission.md` BEFORE the first cohort
    runs. The cohort prompts get the refined mission text injected.
- `state.json` gets an `intake` phase entry with timing.
- Skip behavior: if `mission.md` already exists with `Ambiguity score: low`,
  intake is a no-op.

## v0.12.0 — Hashline-style edit safety for executor  · LOW-MED ROI · ~2 days

**Why.** Once executor enters fan-out, file edits become a real risk
surface. OMO ships `hashline-edit` to guarantee a model's edit lands on
the right lines (each line is content-hashed and the model must verify
the hash before editing). OMGB can't ship its own edit tool (Grok owns
that), but it CAN inject a prompt-template discipline that requires the
executor to:
1. Read the target file first.
2. Restate the exact lines it will change with their line numbers.
3. Re-read after the edit and confirm only those lines changed.

**Changes.**

- `roles/executor.toml` gets optional `edit_safety: hashline-discipline`.
- When launcher spawns executor with that flag, append the discipline
  block to the prompt via `--rules`.
- Audit: when executor is in a cohort, check the evidence block for a
  `Read-Confirm-Write-Reread` shape inside the worker output. Soft
  finding, not blocking.

Defer until executor fan-out templates exist in the launcher.

## v0.13.0 — AI-slop filter on worker output  · LOW ROI · ~0.5 day

**Why.** OMO's `comment-checker` hook strips filler from AI-generated text.
Could apply to the recorded `worker_output_excerpt` blocks (drop
"Certainly!" preambles, repeated apologies, trailing "Hope this helps!"
lines, etc.). Marginal improvement compared to v0.8/v0.9/v0.10/v0.11.
Stretch goal.

**Changes.**

- `scripts/workflow/launch-omgb-fanout.sh`: after extracting the marker block,
  pass it through a small `node` filter that strips a small allow-list of
  slop phrases. Original output stays on disk as `$role.out.raw` for
  inspection.

---

## Items explicitly NOT planned

| Item | Why rejected |
|---|---|
| Skill-embedded MCP servers (OMO) | Violates `skills/`-only manifest charter. OMGB by design has zero MCPs. |
| OAuth 2.1 RFC compliance (OMO) | No MCPs to authenticate. |
| Persistent-mode Stop hook (OMC) | OMGB has no hooks; Grok provides session resume natively for the use cases this hook covers in Claude Code. |
| Bash/Node hybrid hook runtime (OMC) | No hooks. |
| 19 specialist sub-agents catalog (OMC) | OMGB already has 16 roles in `agents/<role>.md`; the per-file layout matches OMC's approach. |

## Suggested execution order

| Week | Items |
|---|---|
| 1 | v0.8.0 (effort routing) + v0.9.0 (auto-retry) |
| 2 | v0.10.0 (resume) + v0.11.0 (Socratic intake) |
| Later | v0.12.0 (hashline discipline) when executor fan-out lands; v0.13.0 (slop filter) opportunistically |

## Open questions to confirm before starting

- For v0.8.0: should the role → effort matrix be hard-coded in toml or
  configurable per-run via `launch-omgb-fanout.sh --effort-override`?
  (Current proposal: toml default + per-run override.)
- For v0.9.0: should the retry be allowed only for FANOUT subprocesses or
  also for in-session leader-spawned roles? (Current proposal: fanout only;
  leader-mode is being deprioritized.)
- For v0.11.0: if intake's ambiguity score is `high`, should the pipeline
  ASK the user to clarify or proceed with documented assumptions?
  (Current proposal: proceed with documented assumptions; surface them in
  the final report.)
