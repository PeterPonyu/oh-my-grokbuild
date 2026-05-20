# Running OMGB with Real Parallel Subagents

> **v0.2.0:** real subagent spawning is now mandatory by default. The leader is
> not allowed to synthesize reviewer verdicts in a single context. See the
> "Mandatory Subagent Spawning" section in `skills/omgb/SKILL.md` and the
> Spawning Discipline section in `agents/leader.md`. The auditor at
> `node scripts/validate.mjs --audit-run <slug>` is the enforcement gate.


This document explains how to actually launch an OMGB run where the different roles (leader, codebase-scout, executor, verifier, etc.) run as **real Grok subagents** instead of being simulated in a single context.

This is the execution model the OMGB design was built for.

## Why This Matters

- True parallelism (multiple roles thinking and working at the same time)
- Better isolation and context for each role
- Uses Grok's native `--agent` / `--agents` mechanism + the `agents/*.md` + `roles/*.toml` files you already ship
- Closer to how the plugin is intended to be used in the TUI or in serious headless automation

## Basic Concepts

Grok supports two relevant ways to run multiple agents:

1. `--agent <name-or-file>` — single agent override
2. `--agents '<json>'` — define multiple subagents in one command

OMGB is designed around method 2.

Each role has:
- `agents/<role>.md` — the prompt (with YAML frontmatter: `name`, `description`, `permission_mode`, `agents_md`, etc.)
- `roles/<role>.toml` — capability config (`default_capability_mode`, `reasoning_effort`, etc.)

## Recommended Way: Use a Short Slug + Named Session

```bash
# Good (short, ergonomic)
grok -s "omgb-handoff-fix" --cwd . -p "/omgb fix the handoff exporter and add subagent support" \
  --agents '@.grok/omgb/runs/omgb-resume-subagents/agents-config.json'   # example
```

## Minimal Working --agents JSON Example

Create a file (for example inside your run dir) called `agents-config.json`:

```json
{
  "leader": {
    "name": "leader",
    "prompt_file": "agents/leader.md",
    "role": "roles/leader.toml",
    "permission_mode": "default"
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
  "verifier": {
    "name": "verifier",
    "prompt_file": "agents/verifier.md",
    "role": "roles/verifier.toml",
    "permission_mode": "read-only"
  }
}
```

Then launch with:

```bash
grok -s "omgb-handoff-fix" --cwd /path/to/your/project \
  -p "/omgb improve resume and subagent support. Use short slugs going forward." \
  --agents '@agents-config.json' \
  --no-subagents=false
```

The leader will receive reports from the other roles as they complete their assigned tasks from `tasks.json`.

## Helper Script (Recommended)

Use `scripts/launch-omgb-team.sh`:

```bash
# Dry-run: write the 16-role agents JSON and print the exact grok command
scripts/launch-omgb-team.sh handoff-fix "Improve resume and subagent support"

# Actually launch the team (subagents spawn in parallel under grok)
scripts/launch-omgb-team.sh handoff-fix "Improve resume and subagent support" --launch

# Smaller team for a focused task
scripts/launch-omgb-team.sh perf-audit "Audit hot paths" \
  --roles "leader,codebase-scout,performance-reviewer,test-engineer,verifier" --launch
```

The launcher:

- Validates the source repo via `scripts/validate.mjs --smoke` before doing anything.
- Builds the JSON from disk (all 16 roles by default).
- Verifies the JSON parses before printing or launching.
- Defaults to dry-run; `--launch` invokes Grok with `-s`, `--cwd`, `-p`, `--agents`.

## Auditing a completed run

After a run finishes, run the audit:

```bash
node scripts/validate.mjs --audit-run <slug>
node scripts/validate.mjs --audit-all
```

The audit checks that every `state.json.activeRoles` entry has a real
`## Subagent: <role>` block in `evidence.md`, that reviewers cited in
`review.md` were actually spawned, and that any `spawn_method: unavailable`
block is paired with `OMGB_ALLOW_SYNTHESIS: true` in `mission.md` plus a
`Synthesis Justification:` line. Exit code 1 means the run is blocked from
finalization until the missing evidence is supplied.

## Synthesis opt-in (single-context fallback)

When the host genuinely does not support subagents, add this line to the run's
`mission.md`:

```
OMGB_ALLOW_SYNTHESIS: true
```

The leader will still emit a `## Subagent: <role>` block for every activation
with `spawn_method: unavailable` and a `Synthesis Justification:` line. The
auditor will label the run as `(synthesis opt-in)` rather than passing it as a
real-spawn run. This is honest, non-default, and traceable.

## Important Notes

- Not every host / context supports `--agents` equally well. If your environment has `--no-subagents` forced, OMGB falls back to sequential execution (still fully functional).
- The `agents_md: true` flag on roles means each subagent will also load project `AGENTS.md` / `CLAUDE.md` files — this is usually desired.
- The leader role has `default_capability_mode = "all"` and high reasoning effort — it should be the only one with broad write access.

## Current Status (as of this doc)

The role files and tomls are ready for real subagent use. The missing piece until this run was:
- Good documentation (this file)
- A reliable resume story when using real subagents
- Short, usable session names

This task is closing those gaps.

## Testing Real Subagents

In environments where subagent spawning is available, you can validate the setup with:

```bash
node scripts/validate.mjs --subagents   # (planned addition)
```

Or simply attempt a small launch with 3–4 roles and observe that they receive distinct tasks from `tasks.json` and report back.

---

**This is the execution model that makes "persistent multi-role team" real instead of simulated.**
