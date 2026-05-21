---
name: omgb
description: Persistent Grok Build team-role orchestration for broad CLI tasks. Use when the user says omgb, asks for a thorough persistent run, or wants a team of roles to carry a task through intake, planning, execution, verification, review, fixes, and finalization. Loads roles by reading per-role files; spawns each role as a real Grok subagent rather than synthesizing them in a single context.
---

# OMGB - Oh My Grok Build Orchestrator

OMGB is the single entry point for persistent role-team orchestration in Grok
Build. It is one markdown skill. It does not require MCP servers, hooks,
custom commands, daemons, or additional skills.

The orchestration here stays simple by design. Role differentiation lives in
per-role files at `agents/<role>.md` (Grok-native agent prompt) and
`roles/<role>.toml` (Grok-native capability config). When you need role detail,
read that role's two files; do not duplicate role bodies inside this skill.

## Ground Rules

- Activate when the user invokes `/omgb`, says `OMGB`, asks for persistent team execution, or requests a thorough role-based run.
- Do not create or invoke additional custom skills as part of OMGB.
- Do not require MCP servers, hooks, background daemons, or hidden extension state.
- Use Grok's documented strengths: plan mode, headless `grok -p`, named sessions `-s`, `--resume`, `--check`, `--agent`, `--agents` JSON, and ordinary subagent spawning.
- Ask before destructive, irreversible, credential-gated, external-production, or materially scope-changing actions.
- Never auto-commit, push, deploy, publish, or delete user work unless explicitly requested.
- Keep one leader responsible for integration and final evidence.

## Official Grok Assumptions

The official docs checked for this plugin document:

- `/skills` and `/plugins` open the extensions modal inside Grok Build's TUI.
- User-invocable skills can appear as slash commands.
- Plan mode blocks write tools except the session plan file.
- Headless mode supports `grok -p`, `--cwd`, `-s`, `--resume`, `--continue`, `--output-format`, and `--check`.
- `--agent`, `--agents` JSON, and `--no-subagents` configure subagent spawning.
- Always-approve mode exists but should only run with explicit user consent.

The Grok client also bundles its own `roles/<name>.toml`, `agents/<name>.md`,
and `skills/<name>/SKILL.md` under `~/.grok/bundled/`. OMGB's role files match
that native layout so Grok can discover them through ordinary plugin payloads.

## Launcher Fan-Out (recommended path under Grok 0.1.x)

Grok 0.1.x's in-session leader does not reliably emit multiple
`spawn_subagent` calls in a single assistant turn — every test we've run
produced ~80s gaps between consecutive spawn calls. The v0.5.0
transcript-based audit correctly blocks such runs. To produce a passing
OMGB run today, use the **launcher-fanout** orchestration mode:

```bash
# Single phase cohort (e.g. grounding: scout + researcher in parallel)
scripts/workflow/launch-omgb-fanout.sh <slug> "<task>" --launch

# Multi-phase pipeline (e.g. grounding then review)
scripts/workflow/launch-omgb-pipeline.sh <slug> "<task>" --launch
```

The launcher itself acts as the orchestrator and forks N parallel
`grok --agent <role>` subprocesses, one per role. Each subprocess is a
single-role headless grok session. Their wall-clock start timestamps are
recorded in `<rundir>/fanout-trace.json` and the audit reads that as
ground truth (same role as Grok's session `events.jsonl` for in-session
spawns). Subprocesses spawned by the launcher start within milliseconds
of each other — true wall-clock parallelism, not assistant-turn
parallelism.

The in-session leader path (`/omgb` skill loaded into one grok session)
remains the primary contract. When Grok's leader gains real single-turn
multi-tool-use, that path will work too. Fan-out is the bridge that lets
OMGB deliver on the parallel promise under current Grok.

## Mandatory Subagent Spawning (no synthesis)

**This section is load-bearing. Read it before activating any role.**

OMGB's "persistent role team" claim is only honest if each role actually runs
as its own Grok subagent. Earlier OMGB runs degraded into single-context
"synthesis" — the leader speaking for code-reviewer, security-reviewer, etc.
That is now a contract violation, not a fallback.

### The discipline

- Every role activation in any phase below (Grounding, Planning, Execution, Verification, Review, Fix Loop) MUST be a real Grok subagent invocation.
- The leader MUST NOT paraphrase, narrate, or "channel" another role.
- The leader MUST refuse to advance to Finalization while any role has been activated without a recorded subagent invocation, unless an explicit synthesis opt-in token is present in `mission.md`.

### How to spawn

Use one of these mechanisms, in order of preference:

1. **`grok --agents <JSON>` at session start** — the canonical path. The team launcher (`scripts/workflow/launch-omgb-team.sh`) emits the JSON for all 16 roles from disk. Grok then routes each `Task`-style instruction to the named subagent.
2. **`grok --agent <role-file>` per-task** — for headless single-role probes from within an active session.
3. **The Task tool inside the TUI** — when the host exposes it, the leader emits `Task(agent="<role>", prompt="…")` to spawn a worker. Record the Task call id in evidence.

### Required evidence per role activation

For every role the leader activates in this run, append to `evidence.md`:

```
## Subagent: <role> (task=<task-id>)

- spawn_method: agents-json | agent-flag | task-tool | unavailable
- invocation: <exact command, Task call id, or session id>
- phase: intake | grounding | planning | execution | verification | review | fix-loop | finalization
- cohort: <id, e.g. "g1"> | serial-by-design  (with `- serial_reason: ...` on the next line if serial-by-design)
- started: <ISO-8601>
- completed: <ISO-8601>
- duration_ms: <completed - started, integer milliseconds>
- worker_output_excerpt: |
    ### WORKER START <role>
    <verbatim 5–30 lines from the subagent's reply>
    ### WORKER END <role>
- verdict_or_result: <one-line summary>
```

The worker output excerpt MUST come back inside the `### WORKER START <role>` /
`### WORKER END <role>` markers that every worker file requires. The leader
copies that block verbatim — no paraphrase.

**The audit reads Grok's events.jsonl as ground truth for spawn timing.**
The leader-recorded `started:` / `completed:` / `duration_ms:` fields are
descriptive. The audit pass/fail on parallel cohorts is decided by the
host transcript at `~/.grok/sessions/<urlencoded-cwd>/<session-uuid>/events.jsonl`,
not by these claims. A hand-crafted "cohort: g1 + started 2s apart" will
be flagged as a high-severity contract violation if the transcript shows
the underlying spawns were 86s apart.

### What to do when subagents are unavailable

If the host disables subagents (`--no-subagents`, missing `--agents` support,
no Task tool), the leader does **not** silently synthesize. Instead:

1. Add a blocker to `state.json.blockers`: `"subagent-spawn-unavailable"`.
2. Stop and ask the user to either:
   - Re-launch via `scripts/workflow/launch-omgb-team.sh <slug> "<task>" --launch` in an environment that supports `--agents`, or
   - Add `OMGB_ALLOW_SYNTHESIS: true` to `mission.md` to explicitly opt into single-context mode for this run. The synthesis opt-in is recorded for every activated role with `spawn_method: unavailable` plus a `Synthesis Justification:` line so the audit tool can flag it.
3. Do not mark `state.active=false` until the user resolves the choice.

### Audit gate

Before Finalization (Phase 7), the leader MUST run the audit:

```bash
node scripts/ci/validate.mjs --audit-run <task-slug>
```

The audit fails if any `activeRole` lacks a `## Subagent: <role>` block, or if
the block claims `spawn_method: unavailable` without a matching opt-in in
`mission.md`. The leader records the audit's exit code and output snippet in
`evidence.md` before advancing to Phase 7.

## Parallel Spawning (mandatory for independent lanes)

OMGB's "team" claim is only honest if independent roles actually run in
parallel. Serial spawning across an entire pipeline is a contract regression
that earlier runs (`omgb-smoke`, others) exhibited.

### The rule

When a phase activates two or more roles that do not depend on each other,
the leader MUST spawn them concurrently. Concrete mechanism: emit all
`spawn_subagent` (or `Task`) tool calls in a single assistant turn.

```
PARALLEL (correct)
  Turn N: <leader emits TWO tool calls in the same message>
    spawn_subagent(name="codebase-scout", prompt=...)
    spawn_subagent(name="researcher",    prompt=...)
  Turn N+1: <both worker replies arrive together; leader records both
            Subagent blocks under the same cohort id>

SERIAL (forbidden for independent roles)
  Turn N:   spawn_subagent(name="codebase-scout", ...)
  Turn N+1: <scout reply arrives>
  Turn N+2: spawn_subagent(name="researcher", ...)
  Turn N+3: <researcher reply arrives>
  → contract violation: scout and researcher were independent, leader serialized them.
```

### Mandatory-parallel cohorts

| Phase | Roles that MUST share one cohort | Why |
| --- | --- | --- |
| Grounding | `codebase-scout` + `researcher` (when both activated) | They read independent sources (local repo vs official docs). No data dependency. |
| Review | every active reviewer (`code-reviewer`, `security-reviewer`, `performance-reviewer`, `ux-reviewer`) | Reviewers operate on the same changeset independently. |
| Execution | `executor` + `writer` (when docs follow code) when on disjoint files | Independent file sets. Use serial only when the writer needs the executor's output. |

### Evidence schema additions

Every `## Subagent: <role>` block grows two optional fields:

```
- phase:   intake | grounding | planning | execution | verification | review | fix-loop | finalization
- cohort:  <short id, e.g. "g1", "review-r1"> — roles spawned in the SAME assistant turn share an id
```

The audit (`node scripts/ci/validate.mjs --audit-run <slug>`) reads these.
For each mandatory-parallel cohort (Grounding, Review) the audit verifies
that all participating roles share a single cohort id and that their
`started` timestamps are within 60 seconds of each other. Otherwise it
emits a high-severity finding: `concurrency-violation: <phase> ran serially`.

When two roles legitimately depend on each other (e.g., architect reads
planner output before producing its verdict), the leader records `cohort:
serial-by-design` plus a one-line `serial_reason:` field. The audit accepts
that.

## No-Stop-Between-Phases (mandatory)

The leader does NOT pause between phases or between role activations to
ask the user "should I continue?". The OMGB contract is end-to-end
autonomous up to Finalization.

### Stop only when

The leader stops and asks the user in exactly these cases:

1. A destructive, irreversible, credentialed, or external-production action is required (commit/push, deploy, rm -rf, history rewrite).
2. The user gave conflicting or missing requirements that the intake-analyst could not resolve (intake's blocking question).
3. `state.json.blockers` contains a real blocker that needs a human decision (e.g., missing credentials, contradictory acceptance criteria, subagent-spawn-unavailable without synthesis opt-in).
4. Three review rounds REQUEST CHANGES on the same item.
5. The same verification command fails three times.

### Never stop because

- A subagent finished its turn and "I should confirm the next step." Spawn the next role immediately.
- A phase boundary was crossed. Phase transitions are internal bookkeeping, not user checkpoints.
- The task list still has pending items. Pending items are work to do, not reasons to halt.
- The audit is about to run. The audit is the gate the leader uses; it is not a user prompt.

### Permission discipline

The launcher passes `--permission-mode auto` so individual read-only and
scoped-write tool calls do not pop confirmation prompts. The leader still
honors the "destructive action" rule above; it does not bypass user
consent for the truly risky operations. `auto` mode means "approve the
ordinary tool calls, escalate the risky ones."

## Persistent Run Directory

At the start of a non-trivial run, create or resume:

```text
.grok/omgb/runs/<task-slug>/
  mission.md
  state.json
  tasks.json
  evidence.md
  review.md
```

Use lowercase kebab-case for `<task-slug>`. Prefer short, ergonomic slugs
(`auth-audit`, `handoff-fix`, `perf-2026`) over long descriptive ones.
If an active run exists for the same slug, resume it instead of starting over.

`state.json` should contain:

```json
{
  "mode": "omgb",
  "active": true,
  "phase": "intake",
  "startedAt": "ISO-8601 timestamp",
  "updatedAt": "ISO-8601 timestamp",
  "taskSlug": "example-task",
  "activeRoles": [],
  "qaCycles": 0,
  "reviewRounds": 0,
  "blockers": [],
  "phases": [
    {"name": "intake",       "started": "ISO-8601", "completed": "ISO-8601", "duration_ms": 1234},
    {"name": "grounding",    "started": "ISO-8601", "completed": "ISO-8601", "duration_ms": 5678}
  ]
}
```

Append one entry to `state.json.phases` every time you transition out of a
phase. `duration_ms = Date.parse(completed) - Date.parse(started)`. The audit
sanity-checks the array exists when `phase` is `complete`.

`tasks.json` should contain role-owned tasks:

```json
{
  "tasks": [
    {
      "id": "T-001",
      "title": "Map repository commands",
      "ownerRole": "codebase-scout",
      "status": "pending",
      "acceptance": ["Exact verification commands are recorded in evidence.md"]
    }
  ]
}
```

## Role Catalog

When role detail is needed, load `agents/ROLE-INDEX.md` for the index, then
spawn the specific role as a subagent and read its files at:

| Role | Agent file | Capability config |
| --- | --- | --- |
| leader | `agents/leader.md` | `roles/leader.toml` |
| intake-analyst | `agents/intake-analyst.md` | `roles/intake-analyst.toml` |
| researcher | `agents/researcher.md` | `roles/researcher.toml` |
| codebase-scout | `agents/codebase-scout.md` | `roles/codebase-scout.toml` |
| planner | `agents/planner.md` | `roles/planner.toml` |
| architect | `agents/architect.md` | `roles/architect.toml` |
| executor | `agents/executor.md` | `roles/executor.toml` |
| debugger | `agents/debugger.md` | `roles/debugger.toml` |
| test-engineer | `agents/test-engineer.md` | `roles/test-engineer.toml` |
| verifier | `agents/verifier.md` | `roles/verifier.toml` |
| code-reviewer | `agents/code-reviewer.md` | `roles/code-reviewer.toml` |
| security-reviewer | `agents/security-reviewer.md` | `roles/security-reviewer.toml` |
| performance-reviewer | `agents/performance-reviewer.md` | `roles/performance-reviewer.toml` |
| writer | `agents/writer.md` | `roles/writer.toml` |
| git-steward | `agents/git-steward.md` | `roles/git-steward.toml` |
| ux-reviewer | `agents/ux-reviewer.md` | `roles/ux-reviewer.toml` |

Only activate the roles a task actually needs. Workers do not recursively
orchestrate. Workers report to the leader.

## Role Router

Route by task shape:

| Task Shape | First Roles | Required Before Final |
| --- | --- | --- |
| Vague or broad request | intake-analyst, codebase-scout | planner, verifier |
| New feature | codebase-scout, planner, architect | executor, test-engineer, code-reviewer, verifier |
| Bug or failing test | codebase-scout, debugger | executor, test-engineer, verifier |
| Refactor or cleanup | codebase-scout, planner, architect | executor, test-engineer, code-reviewer, verifier |
| External API, package, or policy | researcher, codebase-scout, architect | executor, test-engineer, security-reviewer, verifier |
| Documentation | researcher, codebase-scout, writer | verifier |
| UI or UX | ux-reviewer, codebase-scout | executor, test-engineer, verifier |
| Merge, conflict, release, commit, PR | git-steward, codebase-scout | test-engineer, verifier |
| Security-sensitive work | security-reviewer, architect | test-engineer, verifier, code-reviewer |
| Performance work | performance-reviewer, codebase-scout | test-engineer, verifier |

When the task spans independent lanes, run available subagents in parallel via
Grok's native subagent spawning (`--agents` JSON or the Task tool). Each
spawn is logged per the Mandatory Subagent Spawning section above.

## Phase Pipeline

Every phase below that activates roles requires a real subagent spawn per role
plus its evidence block. The leader checks the audit gate before advancing.

### Phase 0: Intake and Resume

1. Identify the task slug and run directory.
2. Resume existing `state.json` when present and active.
3. Spawn the `intake-analyst` subagent to extract user goal, constraints, non-goals, and acceptance criteria into `mission.md`.
4. If ambiguity is high, ask exactly one blocking question. Otherwise proceed.

Advance when:

- `mission.md` has a goal, scope, non-goals, constraints, and acceptance criteria.
- A `## Subagent: intake-analyst` evidence block exists.
- `state.json.phase` is `grounding`.

### Phase 1: Grounding and Research

**Parallel cohort required.** When both `codebase-scout` and `researcher`
are activated, the leader spawns them in the SAME assistant turn (one
`cohort` id, two `spawn_subagent` calls in one message).

1. Spawn `codebase-scout` (maps local files, commands, package manager, tests, likely edit surfaces) and `researcher` (current official docs, plugin policy, SDK/API behavior, package versions) **in one parallel cohort**.
2. Each subagent's verbatim output goes into `evidence.md` inside its `## Subagent: <role>` block with `phase: grounding` and the shared `cohort:` id.
3. Mark unsupported or inferred behavior explicitly.

Advance when:

- The leader can name likely files to change.
- External policy or API assumptions are sourced or marked as unknown.
- Subagent evidence blocks exist for every role activated in this phase.

### Phase 2: Planning and Staffing

1. Spawn `planner` to create tasks in `tasks.json`.
2. Spawn `architect` when design risk is real.
3. Assign owners from the role catalog.
4. Define verification commands before editing.
5. If the user asked only for a plan, stop after this phase and mark `state.active` false.

Advance when:

- Every task has an owner role, status, and acceptance criteria.
- The plan names verification commands.
- Subagent evidence blocks exist for every role activated in this phase.

### Phase 3: Execution

1. Spawn `executor` to implement scoped tasks.
2. Spawn `debugger` for failures and failing tests.
3. Spawn `writer` when docs need updates.
4. The leader updates `tasks.json` after each completed task.
5. No worker may reduce scope to make tests pass.

Advance when:

- All planned implementation tasks are complete or explicitly cancelled by the user.
- Changed files and rationale are recorded in `evidence.md`.
- Subagent evidence blocks exist for every role activated in this phase.

### Phase 4: Verification

1. Spawn `test-engineer` to run focused checks first.
2. Run the project-level verification suite available for the changed surface: build, lint, typecheck, tests, smoke, and sanity.
3. Record exact commands and important output snippets in `evidence.md` inside the test-engineer's subagent block.
4. Increment `qaCycles` in `state.json`.

If verification fails, enter Phase 6. Stop and surface a blocker if the same
failure recurs three times.

Advance when:

- Every acceptance criterion has fresh evidence.
- No relevant verification command is failing.
- A `## Subagent: test-engineer` block exists for this cycle.

### Phase 5: Review

**Parallel cohort required.** All active reviewers run in one cohort,
spawned in a single assistant turn. Reviewers operate on the same
changeset independently and never block each other.

1. In one assistant turn, spawn every applicable reviewer concurrently:
   - `code-reviewer` (always)
   - `security-reviewer` (when changes touch auth, secrets, untrusted input, shell execution, dependency manifests, network calls, or file paths)
   - `performance-reviewer` (for performance claims or hot-path changes)
   - `ux-reviewer` (for CLI prompts, install flows, or final report shape)
2. Each reviewer's verbatim verdict goes into `review.md`, and the corresponding `## Subagent: <reviewer>` block in `evidence.md` carries `phase: review` plus the shared `cohort:` id.
3. Increment `reviewRounds` in `state.json` after the cohort returns.

Verdicts:

- `APPROVE`: no blocking findings.
- `COMMENT`: non-blocking risks remain.
- `REQUEST CHANGES`: fix required before finalization.

If any review requests changes, enter Phase 6. Stop and surface a blocker
after three review rounds on the same issue. **The leader is not allowed to
sign reviewer verdicts. Every verdict in `review.md` MUST come from a real
spawn whose evidence block is in `evidence.md`.**

### Phase 6: Fix Loop

1. Convert each failing verification or review finding into a task in `tasks.json`.
2. Route to `debugger`, `executor`, `test-engineer`, or the relevant reviewer.
3. Return to Phase 3 or Phase 4 depending on whether code changed.
4. Do not skip re-verification after fixes.

### Phase 7: Finalization

1. Ensure every task is `completed`, `cancelled`, or `blocked` with explanation.
2. Ensure `evidence.md` contains fresh verification output.
3. Ensure `review.md` has final verdicts from real reviewer spawns.
4. Run `node scripts/ci/validate.mjs --audit-run <task-slug>` and record the result. If it fails, do not finalize.
5. Set `state.active` false and `phase: "complete"` only when verified.
6. Report changed files, commands run, review verdicts, residual risks, and next optional actions.

## Headless and Resume Hints

When invoking Grok from a shell for an OMGB run, prefer a named session with
the full team JSON:

```bash
scripts/workflow/launch-omgb-team.sh <short-slug> "<task>" --launch
```

That command writes the agents JSON, runs the validator, and invokes:

```bash
grok -s "omgb-<short-slug>" --cwd "$PWD" -p "/omgb <task>" \
  --agents "@.grok/omgb/runs/<short-slug>/agents-config.json"
```

For continuation:

```bash
grok --resume "omgb-<short-slug>"
```

Use `--output-format json` or `--output-format streaming-json` only when an
automation caller needs machine-readable progress. Use `--always-approve`
only when the user explicitly accepts permission risk. Use `--check` to
append a self-verification loop in headless mode.

## Smoke and Sanity Contract

For plugin development, the leader must run:

```bash
node scripts/ci/validate.mjs --smoke
node scripts/ci/validate.mjs --sanity
node scripts/ci/validate.mjs --audit-run <task-slug>
npm test
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] audit passed` (or `[OMGB] audit blocked` with actionable diagnostics)

For end-to-end validation against the user's existing Grok login:

```bash
scripts/local/e2e.sh
```

Expected success marker:

- `[OMGB] e2e passed`

The E2E script reuses `~/.grok/auth.json`; it must not invoke `grok login`.

## Final Report Format

Use this concise report shape:

```text
OMGB RESULT
Task: <goal>
Run: .grok/omgb/runs/<slug>
Phase: complete | blocked | cancelled
Spawned roles: <comma-separated, each with a Subagent block in evidence.md>
Changed files: <paths>
Verification: <commands and pass/fail>
Audit: [OMGB] audit passed | [OMGB] audit blocked
Review: <APPROVE|COMMENT|REQUEST CHANGES>
Risks: <remaining risks or none>
```
