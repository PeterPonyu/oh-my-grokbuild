# Grok Build Docs Research

Date: 2026-05-20

## Official xAI Docs Checked

- `https://docs.x.ai/build/modes-and-commands`
- `https://docs.x.ai/build/cli/headless-scripting`

## Local Grok Client

This research was performed against the Grok Build CLI installed on this
machine at `~/.grok/bin/grok`. Reported version: `0.1.212`.

`grok --help` documents the following relevant flags:

- `--agent <NAME>` — agent name or definition file path.
- `--agents <JSON>` — inline subagent definitions as JSON.
- `--no-subagents` — disable subagent spawning.
- `--allow <RULE>` / `--deny <RULE>` — permission rules.
- `--always-approve` — auto-approve all tool executions (only with explicit user consent).
- `--best-of-n <N>` — run a task N ways in parallel and pick the best (headless only).
- `--check` — append a self-verification loop to the prompt (headless only).
- `--continue` (`-c`) — resume most recent session for the current cwd.
- `--cwd <CWD>` — working directory.
- `--effort <LEVEL>` — `low | medium | high | xhigh | max`.
- `--experimental-memory` / `--no-memory` — cross-session memory toggles.
- `--no-plan` — disable plan mode.
- `--output-format <plain|json|streaming-json>` — headless output shape.
- `--permission-mode <default|acceptEdits|auto|dontAsk|bypassPermissions|plan>`.
- `-p <PROMPT>` / `--prompt-file` / `--prompt-json` — headless prompts.
- `-r [SESSION_ID]` / `--resume` — resume a session.
- `-s` — start or attach a named session.
- `--rules` / `--system-prompt-override` — system prompt control.
- `--sandbox <PROFILE>` — filesystem and network sandbox.
- `--tools` / `--disallowed-tools` — built-in tool whitelisting.
- `-w [WORKTREE]` / `--worktree` — start the session in a new git worktree.

Subcommands include `agent`, `import`, `leader`, `login`, `mcp`, `memory`,
`models`, `sessions`, `setup`, `share`, `ssh`, `trace`, `update`, `version`,
and `worktree`. `/plugins` and `/skills` are slash commands inside the TUI,
not CLI subcommands.

## Grounded Findings

- Grok Build exposes `/plugins`, `/skills`, `/hooks`, and `/mcps` as tabs in one extensions modal inside the TUI.
- User-invocable skills can appear as slash commands. If names collide, the documented qualified form is similar to `/local:commit`.
- Plan mode blocks write tools except for the session plan file and is intended for approach approval before edits.
- Always-approve mode can be toggled in the TUI with `/always-approve` or started with `grok --always-approve`.
- Headless mode supports `grok -p`, named sessions via `-s`, resuming via `--resume`, continuing with `--continue`, `--cwd`, and `--output-format plain|json|streaming-json`.
- ACP mode is available through `grok agent stdio` for tool or IDE integration.

## Native Extension Layout (from `~/.grok/bundled/`)

The Grok client ships its own extensions under `~/.grok/bundled/`. The layout
the OMGB plugin matches:

- `skills/<name>/SKILL.md` — Claude-style YAML-frontmatter markdown skill.
- `agents/<name>.md` — agent prompt with YAML frontmatter (keys observed: `name`, `description`, `prompt_mode`, `model`, `permission_mode`, `agents_md`).
- `roles/<name>.toml` — role capability config with keys: `description`, `default_capability_mode` (`read-only` or `all`), `reasoning_effort` (`low|medium|high`), optional `default_fork_context`.
- `personas/<name>.toml` — separate persona files (not used by OMGB).

Bundled examples cross-checked include `agents/explore.md`,
`agents/plan.md`, `agents/general-purpose.md`, and `roles/explore.toml`,
`roles/implementer.toml`, `roles/plan.toml`, `roles/reviewer.toml`,
`roles/security-auditor.toml`.

## Plugin Discovery

Local plugins live under `~/.grok/plugins/local/<plugin-name>/`. Grok also
maintains `~/.grok/marketplace-cache/<hash>/` for marketplace-fetched plugins.

Per the official xAI docs
(<https://docs.x.ai/build/features/skills-plugins-marketplaces>), Grok discovers
plugins from `./.grok/plugins/`, `~/.grok/plugins/`, marketplace installs under
`~/.grok/plugins/marketplaces/`, and extra `[plugins] paths` in
`~/.grok/config.toml`; marketplace sources are configured via
`[[marketplace.sources]]` in `~/.grok/config.toml` and
`~/.grok/plugins/known_marketplaces.json`.

> Observed locally on grok `0.1.212` (not in the official docs): an
> `installed_plugins.json` index appears sibling to the Claude marketplace cache
> at `~/.claude/plugins/installed_plugins.json`, consistent with Grok also
> reading the Claude Code plugin discovery surface via its Claude-compatibility
> layer. Treat this specific sibling-index path as a local observation, not a
> documented contract; the official config locations above are authoritative.

OMGB ships:

- a root `plugin.json` (skills-only manifest), and
- a `.claude-plugin/plugin.json` compatibility shim,

so the same payload installs into both Grok and Claude-style hosts without
duplicating skill definitions.

## Policy Gap

No public xAI page found that fully specifies a Grok Build plugin policy,
manifest schema, or enforcement contract beyond the extensions modal and skill
command behavior above. Because of that, this plugin uses the most
conservative surface:

- one markdown skill only,
- no MCP servers,
- no hooks,
- no custom commands,
- no declared agent plugin components in the manifest,
- no dependencies or background daemons.

The role catalog uses Grok's native per-file `agents/<name>.md` and
`roles/<name>.toml` layout. The orchestration logic stays inside the single
`skills/omgb/SKILL.md`.
