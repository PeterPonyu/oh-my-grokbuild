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

1. **`grok --agents <JSON>` at session start** — the canonical path. The team launcher (`scripts/launch-omgb-team.sh`) emits the JSON for all 16 roles from disk. Grok then routes each `Task`-style instruction to the named subagent.
2. **`grok --agent <role-file>` per-task** — for headless single-role probes from within an active session.
3. **The Task tool inside the TUI** — when the host exposes it, the leader emits `Task(agent="<role>", prompt="…")` to spawn a worker. Record the Task call id in evidence.

### Required evidence per role activation

For every role the leader activates in this run, append to `evidence.md`:

```
## Subagent: <role> (task=<task-id>)

- spawn_method: agents-json | agent-flag | task-tool | unavailable
- invocation: <exact command, Task call id, or session id>
- started: <ISO-8601>
- completed: <ISO-8601>
- worker_output_excerpt: |
    ### WORKER START <role>
    <verbatim 5–30 lines from the subagent's reply>
    ### WORKER END <role>
- verdict_or_result: <one-line summary>
```

The worker output excerpt MUST come back inside the `### WORKER START <role>` /
`### WORKER END <role>` markers that every worker file requires. The leader
copies that block verbatim — no paraphrase.

### What to do when subagents are unavailable

If the host disables subagents (`--no-subagents`, missing `--agents` support,
no Task tool), the leader does **not** silently synthesize. Instead:

1. Add a blocker to `state.json.blockers`: `"subagent-spawn-unavailable"`.
2. Stop and ask the user to either:
   - Re-launch via `scripts/launch-omgb-team.sh <slug> "<task>" --launch` in an environment that supports `--agents`, or
   - Add `OMGB_ALLOW_SYNTHESIS: true` to `mission.md` to explicitly opt into single-context mode for this run. The synthesis opt-in is recorded for every activated role with `spawn_method: unavailable` plus a `Synthesis Justification:` line so the audit tool can flag it.
3. Do not mark `state.active=false` until the user resolves the choice.

### Audit gate

Before Finalization (Phase 7), the leader MUST run the audit:

```bash
node scripts/validate.mjs --audit-run <task-slug>
```

The audit fails if any `activeRole` lacks a `## Subagent: <role>` block, or if
the block claims `spawn_method: unavailable` without a matching opt-in in
`mission.md`. The leader records the audit's exit code and output snippet in
`evidence.md` before advancing to Phase 7.

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
  "blockers": []
}
```

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

1. Spawn `codebase-scout` to map local files, commands, package manager, tests, and likely edit surfaces.
2. Spawn `researcher` for current official docs, plugin policy, SDK/API behavior, package versions, or external facts.
3. Each subagent's verbatim output goes into `evidence.md` inside its `## Subagent: <role>` block.
4. Mark unsupported or inferred behavior explicitly.

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

1. Spawn `code-reviewer` to review quality, correctness, maintainability, and architecture.
2. Spawn `security-reviewer` when changes touch auth, secrets, untrusted input, shell execution, dependency manifests, network calls, or file paths.
3. Spawn `performance-reviewer` for performance claims or hot-path changes.
4. Spawn `ux-reviewer` for changes to CLI prompts, install flows, or final report shape.
5. Each reviewer's verbatim verdict goes into `review.md`.
6. Increment `reviewRounds` in `state.json`.

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
4. Run `node scripts/validate.mjs --audit-run <task-slug>` and record the result. If it fails, do not finalize.
5. Set `state.active` false and `phase: "complete"` only when verified.
6. Report changed files, commands run, review verdicts, residual risks, and next optional actions.

## Headless and Resume Hints

When invoking Grok from a shell for an OMGB run, prefer a named session with
the full team JSON:

```bash
scripts/launch-omgb-team.sh <short-slug> "<task>" --launch
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
node scripts/validate.mjs --smoke
node scripts/validate.mjs --sanity
node scripts/validate.mjs --audit-run <task-slug>
npm test
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] audit passed` (or `[OMGB] audit blocked` with actionable diagnostics)

For end-to-end validation against the user's existing Grok login:

```bash
scripts/e2e.sh
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
