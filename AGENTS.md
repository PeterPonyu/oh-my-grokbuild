# oh-my-grokbuild Agent Notes

Work from this repository root.

## Boundaries

- Preserve the one-skill contract: only `skills/omgb/SKILL.md` may be a skill.
- Do not add MCP servers, hooks, daemons, or custom slash command files.
- Keep `plugin.json` and `.claude-plugin/plugin.json` minimal and conservative until xAI publishes a stable detailed Grok Build plugin manifest policy.
- Role bodies live in `agents/<role>.md`. Role capability configs live in `roles/<role>.toml`. `agents/AGENTS.md` is only a thin index over those files.
- Do not add dependencies unless the user explicitly approves.

## Verification

Before claiming completion, run:

```bash
npm test          # smoke + sanity
bash scripts/e2e.sh   # asserts ~/.grok/auth.json; refuses to grok login
```

Expected markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] e2e passed`

## Research Sources

- `docs/research/grok-build-docs.md`
- `docs/research/local-orchestration-survey.md`
