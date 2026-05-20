# Plan: One-Skill Grok Build Orchestrator

## Goal

Build a conservative Grok Build plugin package that provides one `/omgb` skill for persistent role-team orchestration.

## Scope

- In: `plugin.json`, `.claude-plugin/plugin.json`, `skills/omgb/SKILL.md`, `agents/AGENTS.md`, docs under `docs/`, validation under `scripts/`, and `prd.json`.
- Out: MCP servers, hooks, runtime daemons, multiple skills, package publishing, and external deployment.

## Acceptance Criteria

- [ ] `node scripts/ci/validate.mjs --smoke` reports `[OMGB] smoke passed`.
- [ ] `node scripts/ci/validate.mjs --sanity` reports `[OMGB] sanity passed`.
- [ ] `npm test` passes without installing dependencies.
- [ ] The validator confirms exactly one skill exists.
- [ ] The manifests do not declare hooks, MCP servers, commands, or agent plugin surfaces.
- [ ] The skill contains phase routing, role routing, persistence, verification, review, and safety sections.
- [ ] Research docs record official Grok docs checked and local oh-my-* versions.

## Implementation Steps

1. Create the plugin manifests with a skills-only surface.
2. Write `skills/omgb/SKILL.md` as the sole orchestration entry point.
3. Write `agents/AGENTS.md` as the role catalog loaded by the skill.
4. Add research docs from official Grok docs and local oh-my-* inspection.
5. Add `prd.json` for iterate-loop traceability.
6. Add `scripts/ci/validate.mjs` for smoke and sanity gates.
7. Run smoke, sanity, and `npm test`; fix until green.
8. Perform code and security review over the resulting package.

## Risks

- Grok Build plugin manifest details are underdocumented publicly. Mitigation: keep the manifest minimal and include a Claude-style compatibility manifest.
- A single skill can become too large. Mitigation: keep role detail in `agents/AGENTS.md` while preserving one user-invocable skill.
- Persistence files may be mistaken for runtime hooks. Mitigation: document them as ordinary run artifacts created by the leader during `/omgb`.

## Verification

- `node scripts/ci/validate.mjs --smoke`
- `node scripts/ci/validate.mjs --sanity`
- `npm test`
