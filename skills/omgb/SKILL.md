---
name: omgb
description: Persistent Grok Build team-role orchestration for broad CLI tasks. Use when the user says omgb, asks for a thorough persistent run, or wants a team of roles to carry a task through intake, planning, execution, verification, review, fixes, and finalization. Loads roles by reading per-role files; does not inline role bodies.
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

Use lowercase kebab-case for `<task-slug>`. If an active run exists for the
same slug, resume it instead of starting over.

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

When role detail is needed, load `agents/AGENTS.md` for the index, then read
the specific role files:

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
Grok's native subagent spawning. If the host disables subagents, run each role
section sequentially while preserving the same task ownership and artifacts.

## Phase Pipeline

### Phase 0: Intake and Resume

1. Identify the task slug and run directory.
2. Resume existing `state.json` when present and active.
3. Extract user goal, constraints, non-goals, and acceptance criteria into `mission.md` via the `intake-analyst` role.
4. If ambiguity is high, ask exactly one blocking question. Otherwise proceed.

Advance when:

- `mission.md` has a goal, scope, non-goals, constraints, and acceptance criteria.
- `state.json.phase` is `grounding`.

### Phase 1: Grounding and Research

1. Use `codebase-scout` to map local files, commands, package manager, tests, and likely edit surfaces.
2. Use `researcher` for current official docs, plugin policy, SDK/API behavior, package versions, or external facts.
3. Record evidence in `evidence.md` with paths, URLs, and command outputs.
4. Mark unsupported or inferred behavior explicitly.

Advance when:

- The leader can name likely files to change.
- External policy or API assumptions are sourced or marked as unknown.

### Phase 2: Planning and Staffing

1. Use `planner` to create tasks in `tasks.json`.
2. Use `architect` for design boundaries, state ownership, and risk review when design risk is real.
3. Assign owners from the role catalog.
4. Define verification commands before editing.
5. If the user asked only for a plan, stop after this phase and mark `state.active` false.

Advance when:

- Every task has an owner role, status, and acceptance criteria.
- The plan names verification commands.

### Phase 3: Execution

1. `executor` implements scoped tasks.
2. `debugger` handles failures and failing tests.
3. `writer` updates docs when behavior changes.
4. The leader updates `tasks.json` after each completed task.
5. No worker may reduce scope to make tests pass.

Advance when:

- All planned implementation tasks are complete or explicitly cancelled by the user.
- Changed files and rationale are recorded in `evidence.md`.

### Phase 4: Verification

1. `test-engineer` runs focused checks first.
2. Run the project-level verification suite available for the changed surface: build, lint, typecheck, tests, smoke, and sanity.
3. Record exact commands and important output snippets in `evidence.md`.
4. Increment `qaCycles` in `state.json`.

If verification fails, enter Phase 6. Stop and surface a blocker if the same
failure recurs three times.

Advance when:

- Every acceptance criterion has fresh evidence.
- No relevant verification command is failing.

### Phase 5: Review

1. `code-reviewer` reviews quality, correctness, maintainability, and architecture.
2. `security-reviewer` is mandatory when changes touch auth, secrets, untrusted input, shell execution, dependency manifests, network calls, or file paths.
3. `performance-reviewer` is mandatory for performance claims or hot-path changes.
4. `ux-reviewer` is mandatory for changes to CLI prompts, install flows, or final report shape.
5. Record findings and verdicts in `review.md`.
6. Increment `reviewRounds` in `state.json`.

Verdicts:

- `APPROVE`: no blocking findings.
- `COMMENT`: non-blocking risks remain.
- `REQUEST CHANGES`: fix required before finalization.

If any review requests changes, enter Phase 6. Stop and surface a blocker
after three review rounds on the same issue.

### Phase 6: Fix Loop

1. Convert each failing verification or review finding into a task in `tasks.json`.
2. Route to `debugger`, `executor`, `test-engineer`, or the relevant reviewer.
3. Return to Phase 3 or Phase 4 depending on whether code changed.
4. Do not skip re-verification after fixes.

### Phase 7: Finalization

1. Ensure every task is `completed`, `cancelled`, or `blocked` with explanation.
2. Ensure `evidence.md` contains fresh verification output.
3. Ensure `review.md` has final verdicts.
4. Set `state.active` false and `phase: "complete"` only when verified.
5. Report changed files, commands run, review verdicts, residual risks, and next optional actions.

## Headless and Resume Hints

When invoking Grok from a shell for an OMGB run, prefer a named session:

```bash
grok -s "omgb-<task-slug>" --cwd "$PWD" -p "/omgb <task>"
```

For continuation:

```bash
grok --resume "omgb-<task-slug>"
```

Use `--output-format json` or `--output-format streaming-json` only when an
automation caller needs machine-readable progress. Use `--always-approve` only
when the user explicitly accepts permission risk. Use `--check` to append a
self-verification loop in headless mode.

## Subagent Spawning

Grok supports `--agent <name>` and `--agents <JSON>` for subagent definitions.
OMGB uses ordinary Grok subagents to run workers in parallel when the host
exposes them. The role file at `agents/<role>.md` is the agent prompt. The
capability config at `roles/<role>.toml` is the matching role profile.

If `--no-subagents` is in effect, run roles sequentially without changing the
artifact contract.

## Smoke and Sanity Contract

For plugin development, the leader must run:

```bash
node scripts/validate.mjs --smoke
node scripts/validate.mjs --sanity
npm test
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`

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
Changed files: <paths>
Verification: <commands and pass/fail>
Review: <APPROVE|COMMENT|REQUEST CHANGES>
Risks: <remaining risks or none>
```
