# oh-my-grokbuild Agent Notes

Work from this repository root.

## Boundaries

- Preserve the one-skill contract: only `skills/omgb/SKILL.md` may be a skill.
- Do not add MCP servers, hooks, daemons, or custom slash command files.
- Keep `plugin.json` and `.claude-plugin/plugin.json` minimal and conservative until xAI publishes a stable detailed Grok Build plugin manifest policy.
- Role bodies live in `agents/<role>.md`. Role capability configs live in `roles/<role>.toml`. `agents/ROLE-INDEX.md` is the thin catalog index (intentionally not named AGENTS.md to avoid host auto-injection).
- Do not add dependencies unless the user explicitly approves.

## Verification

Before claiming completion, run:

```bash
npm test          # smoke + sanity
OMGB_E2E_HEADLESS=1 bash scripts/local/e2e.sh   # full E2E; refuses to grok login
```

Expected markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] e2e passed` for full headless E2E

## Research Sources

- `docs/research/grok-build-docs.md`
- `docs/research/local-orchestration-survey.md`
