# Lineage and Non-Copying Notice

`oh-my-grokbuild` follows the local oh-my suite doctrine: use observed product trends as design input, but do not copy another project's source, assets, package identity, or branding.

## Inspiration

The current modernization lane was informed by a suite-level review of compact default surfaces, inventory-first validation, and release-readiness evidence. Those are product-shape patterns, not copied implementation.

## Boundaries

- `/omgb` is the only default user-invocable Grok Build surface in this repo.
- The 16 role files are internal/advanced orchestration inputs consumed by the `/omgb` skill and launchers; they are not additional default slash commands.
- No MCP servers, hooks, custom commands, daemon, telemetry, or network dependency is added by default.
- Any future source-level reuse from another project requires explicit provenance/legal review before implementation.

## Host Capability Notes

This plugin documents only Grok Build capabilities that are either implemented locally or grounded in the checked research notes. It must not claim unsupported host behavior such as Codex/Claude-specific tmux runtimes, hooks, MCP servers, or publish automation.
