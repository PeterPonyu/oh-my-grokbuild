# oh-my-grokbuild Agent Notes

Work from this repository root.

## Boundaries

- Preserve the one-skill contract: only `skills/omgb/SKILL.md` may be a skill.
- Do not add MCP servers, hooks, daemons, or custom slash command files.
- Keep `plugin.json` minimal and conservative until xAI publishes a stable
  detailed Grok Build plugin manifest policy.
- Role guidance belongs in `agents/AGENTS.md`, not in additional skills.
- Do not add dependencies unless the user explicitly approves.

## Verification

Before claiming completion, run:

```bash
npm test
```

Expected markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`

## Research Sources

- `docs/research/grok-build-docs.md`
- `docs/research/local-orchestration-survey.md`
