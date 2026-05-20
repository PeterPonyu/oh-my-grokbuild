# Spec: OMGB Grok Build Orchestrator

## Goal

Create a Grok Build plugin that exposes exactly one skill, `omgb`, as the entry point for thorough, persistent, team-role orchestration across general CLI tasks.

## Success Criteria

- The plugin contains exactly one `SKILL.md`.
- The skill defines a leader-owned orchestration protocol with role routing, phase separation, persistence, verification, review, and bounded fix loops.
- The plugin has no MCP server, hook, daemon, or multi-skill dependency.
- Role behavior is available through a role catalog that the `omgb` skill references.
- Research notes cite the official Grok Build docs that were checked and clearly mark policy gaps.
- Smoke and sanity checks prove the package shape and [OMGB] invariants.

## Non-Goals

- Implementing a runtime daemon.
- Adding MCP servers, hooks, or external service integrations.
- Assuming undocumented Grok plugin APIs beyond skills-as-commands and extension discovery.
- Auto-committing, pushing, deploying, or publishing.

## Compatibility Assumptions

- Grok Build supports user-invocable skills surfaced as slash commands.
- Grok Build exposes `/skills` and `/plugins` for extension management.
- Grok Build supports plan mode and headless session continuation, which the skill can instruct users or agents to use.
- Detailed plugin policy is not public in the official docs checked, so the manifest remains minimal.

## Persistent Run Artifacts

When `/omgb` is invoked for a task, the skill instructs the leader to create:

- `.grok/omgb/runs/<slug>/mission.md`
- `.grok/omgb/runs/<slug>/state.json`
- `.grok/omgb/runs/<slug>/tasks.json`
- `.grok/omgb/runs/<slug>/evidence.md`
- `.grok/omgb/runs/<slug>/review.md`

These files are ordinary project artifacts owned by the active run. They are not hooks, MCP state, or a daemon.

## Role Set

The default role roster is:

- leader
- intake-analyst
- researcher
- codebase-scout
- planner
- architect
- executor
- debugger
- test-engineer
- verifier
- code-reviewer
- security-reviewer
- performance-reviewer
- writer
- git-steward
- ux-reviewer

The leader may activate only the roles needed for the task.

## Phase Model

1. Intake and resume detection.
2. Grounding and research.
3. Planning and role staffing.
4. Execution.
5. Verification.
6. Review.
7. Fix loop.
8. Finalization and state closure.

## Safety Rules

- Ask before destructive, irreversible, credential-gated, external-production, or materially scope-changing actions.
- Do not add extra skills.
- Do not introduce MCP or hooks.
- Do not let workers spawn nested teams.
- Do not claim success without fresh evidence.
