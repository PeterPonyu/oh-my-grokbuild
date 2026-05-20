# Local Orchestration Survey

Date: 2026-05-20

This survey informs the OMGB design by sampling four local oh-my-* projects
that ship persistent multi-role orchestration patterns. OMGB intentionally
does not import code from these projects; it borrows orchestration shape
only and writes fresh artifacts for Grok Build's native layout.

## Local Packages Sampled

- `oh-my-openagent` — local package `oh-my-opencode`, version `4.0.0` (sampled 2026-05-20).
- `oh-my-codex-main` — local package `oh-my-codex`, version `0.14.1` (sampled 2026-05-20).
- `oh-my-claudecode-main` — local package `oh-my-claude-sisyphus`, version `4.13.5` (sampled 2026-05-20).
- `oh-my-cursor` — local repo `PeterPonyu/oh-my-cursor`, ships plugin `v0.5.0` (sampled 2026-05-20 after fast-forward from `origin/main`).

## Patterns Borrowed

### oh-my-openagent

- Uses a gated team mode rather than exposing team tools unconditionally.
- Separates team lifecycle, mailbox, task list, worktree, and status concepts.
- Documents team behavior through a skill, while runtime tools remain separately gated.
- Enforces team boundaries: eligible roles only, no nested teams, lead-owned shutdown.

### oh-my-codex

- Treats `team` as durable tmux-backed coordination and `ralph` as persistent single-owner completion.
- Requires pre-context intake before launching long-running orchestration.
- Keeps a leader responsible for integration, verification, and stopping conditions.
- Uses explicit phase transitions: plan, PRD, execute, verify, fix loop, terminal state.

### oh-my-claudecode

- Uses an AGENTS-style operating contract with role catalog, routing rules, and verification rules.
- Keeps workflow state explicit under a project-local state directory.
- Separates worker responsibilities from leader responsibilities.
- Requires review and security review for meaningful changes.
- Persistent loops (ralph, ultrawork) tie completion to PRD acceptance criteria, not vibes.

### oh-my-cursor

- Ships repo-owned rules, hooks, agents, and a workflow-state contract under `.cursor/`.
- Splits each agent into its own file under `.cursor/agents/<role>.md` rather than centralizing them.
- Uses an explicit claim/proof discipline so docs do not over-promise.
- Validates the plugin payload via local scripts before installing into `~/.cursor/plugins/local/`.

## OMGB Design Takeaways

- Make one skill the only user-invocable entry point.
- Keep role routing in the skill and an `agents/AGENTS.md` index, but put each role body in its own file at `agents/<role>.md` and pair it with `roles/<role>.toml`. This mirrors Grok's native bundle layout.
- Persist run state in ordinary project files so a later Grok session can resume without hooks.
- Prefer phase gates over unstructured "keep going" loops.
- Make verification and review first-class phases with bounded fix loops.
- Avoid MCP, hooks, and extra commands until Grok publishes a stable plugin policy for them.
- Validate the plugin payload locally before installing into `~/.grok/plugins/local/`.
