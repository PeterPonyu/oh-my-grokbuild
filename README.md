# oh-my-grokbuild

`oh-my-grokbuild` is a Grok Build plugin with a single user entry point:
`/omgb`. It is a one-skill + many-roles design.

- **One skill, one entry point.** `skills/omgb/SKILL.md` is the only invocable
  surface. It owns the orchestration logic and the role router.
- **Many roles, one file each.** Each of the 16 roles ships its own Grok-native
  `agents/<role>.md` (YAML-frontmatter prompt) and `roles/<role>.toml`
  (capability config). The orchestration layer stays thin; the differentiation
  lives in per-role files.
- **Skills-only manifest.** No MCP servers, no hooks, no custom commands, no
  registered agent plugin surfaces, no runtime daemon, no dependencies.

## Why This Shape

The official Grok Build docs checked for this work describe `/plugins`,
`/skills`, plan mode, headless sessions, `--agent`, `--agents`, `--check`,
named sessions, and resume. No public official page was found that fully
specifies a Grok Build plugin policy or manifest schema. Because of that, the
plugin avoids unstable surfaces and keeps its behavior in one markdown skill
plus per-role files that match Grok's own bundled extension layout
(`~/.grok/bundled/skills/`, `~/.grok/bundled/agents/`, `~/.grok/bundled/roles/`).

## Layout

```
plugin.json                       # root skills-only manifest
.claude-plugin/plugin.json        # compatibility shim for Claude-style hosts
skills/omgb/SKILL.md              # the single entry-point skill
agents/AGENTS.md                  # thin index, one line per role
agents/<role>.md                  # 16 detailed Grok-native agent prompts
roles/<role>.toml                 # 16 Grok-native capability configs
scripts/validate.mjs              # smoke + sanity validator
scripts/e2e.sh                    # end-to-end probe against existing login
scripts/install-local.sh          # local install into ~/.grok/plugins/local
docs/research/                    # grounded research notes
prd.json                          # task PRD with acceptance criteria
```

## Roles

The 16 roles are: `leader`, `intake-analyst`, `researcher`, `codebase-scout`,
`planner`, `architect`, `executor`, `debugger`, `test-engineer`, `verifier`,
`code-reviewer`, `security-reviewer`, `performance-reviewer`, `writer`,
`git-steward`, `ux-reviewer`. See `agents/AGENTS.md` for the index.

## Install

Local install into Grok's plugin directory:

```bash
scripts/install-local.sh --force
```

This copies the runtime payload to `~/.grok/plugins/local/oh-my-grokbuild`. It
runs the validator first; it does not require sudo, network access, or any
package install.

## Invocation

Inside Grok Build:

```text
/omgb <task>
```

Headless:

```bash
grok -s "omgb-<task-slug>" --cwd "$PWD" -p "/omgb <task>"
```

Resume:

```bash
grok --resume "omgb-<task-slug>"
```

## Verification

```bash
npm test          # runs smoke and sanity
scripts/e2e.sh    # asserts existing Grok login, validates installed payload
```

Optional live headless probe (consumes a real Grok turn):

```bash
OMGB_E2E_HEADLESS=1 scripts/e2e.sh
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] e2e passed`

## Persistence

The skill instructs the leader to keep ordinary project files under:

```
.grok/omgb/runs/<task-slug>/
  mission.md
  state.json
  tasks.json
  evidence.md
  review.md
```

There are no hooks, MCP servers, or background daemons involved.

## License

MIT.
