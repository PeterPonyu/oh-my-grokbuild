# OMGB Role Catalog

This file is a thin index. Each role lives in its own file so it can be loaded,
inspected, or referenced individually. The orchestration logic lives in the
single skill at `skills/omgb/SKILL.md`.

## Layout

- Per-role Grok-native agent prompts: `agents/<role>.md` (YAML frontmatter + body).
- Per-role Grok-native capability configs: `roles/<role>.toml`.

## Roles

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

## Loading Conventions

When the skill needs to brief a role:

1. Read the YAML frontmatter and body of the matching `agents/<role>.md`.
2. Honor the capability profile from `roles/<role>.toml` (`default_capability_mode`, `reasoning_effort`, `default_fork_context`).
3. Pass the role its assigned task entry from `.grok/omgb/runs/<task-slug>/tasks.json`.

Workers do not spawn further OMGB runs. Workers report to the leader.
