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
local-payload.txt                 # local install payload manifest
skills/omgb/SKILL.md              # the single entry-point skill
agents/ROLE-INDEX.md              # thin index (deliberately not AGENTS.md)
agents/<role>.md                  # 16 detailed Grok-native agent prompts
roles/<role>.toml                 # 16 Grok-native capability configs
scripts/ci/validate.mjs              # smoke + sanity validator
scripts/local/e2e.sh                    # E2E harness; set mode env for pass marker
scripts/local/install-local.sh          # local install into ~/.grok/plugins/local
docs/research/                    # grounded research notes
prd.json                          # task PRD with acceptance criteria
```

## Roles

The 16 roles are: `leader`, `intake-analyst`, `researcher`, `codebase-scout`,
`planner`, `architect`, `executor`, `debugger`, `test-engineer`, `verifier`,
`code-reviewer`, `security-reviewer`, `performance-reviewer`, `writer`,
`git-steward`, `ux-reviewer`. See `agents/ROLE-INDEX.md` for the index.

## Install

### Prerequisites
- Node.js (v18+) — the validator (`scripts/ci/validate.mjs`) is ESM.
- A working `grok` CLI with an authenticated session (`~/.grok/auth.json` for e2e).
- The repo cloned locally (this is the source of truth; the TUI loads via symlinks).

### One-command local install

```bash
scripts/local/install-local.sh --force
```

- Runs `node scripts/ci/validate.mjs --smoke` as a mandatory preflight.
- Copies the minimal runtime payload declared in `local-payload.txt` into `~/.grok/plugins/local/oh-my-grokbuild`.
- Creates (or refreshes) the user-skill mount at `~/.grok/skills/omgb` so that `/omgb` becomes immediately invocable.
- Logs everything under `.omgb/evidence/install-*.log`.

**No sudo, no network, no `npm install` on the target machine.**

### Post-install step (required)
Reload or restart the Grok Build TUI (or run `/plugins` + `/skills` inside it) so the extensions scanner picks up the new symlinks under `~/.grok/skills/omgb`.

**Strongly recommended after any install or repo move:** run `./scripts/local/doctor.sh` from the current checkout. It will tell you immediately if the mount is healthy for *this* tree.

### Troubleshooting
- `/omgb` not appearing or pointing at the wrong tree? Run `./scripts/local/doctor.sh`. It now detects mount drift (when the symlinks point to a different checkout than the one you're currently in) and tells you the exact command to heal it.
- The recommended first step when anything feels off: `./scripts/local/install-local.sh --force` (from the checkout you want to use) followed by `./scripts/local/doctor.sh`.
- The payload contents are now declared in `local-payload.txt` at the repo root. Editing this file is the only thing needed when adding/removing distributable assets.
- Want to develop without re-copying the payload every time? The user-skill mount is a symlink, so edits to `SKILL.md`, role files, and `ROLE-INDEX.md` take effect immediately after a TUI reload.
- To skip the user-skill mount (advanced): `OMGB_SKIP_USER_SKILL_MOUNT=1 scripts/local/install-local.sh --force`.

### Verification after install
```bash
node scripts/ci/validate.mjs --smoke
node scripts/ci/validate.mjs --sanity
npm test
OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh  # structural check
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh              # full live check
```

For the relocation / "I moved my clone" scenario, see `docs/REPO-RELOCATION-TEST.md`.

See the "Verification" section below for expected success markers.

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
npm test                                       # runs smoke and sanity
OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh  # structural: login + payload + launcher dry-run
node scripts/ci/validate.mjs --audit-run <slug>   # gate before finalization of a run
node scripts/ci/validate.mjs --audit-all          # bulk-audit every .grok/omgb/runs/<slug>
```

### Smoke vs Sanity vs E2E vs Audit — what runs when

| Check | Auth needed? | What it asserts | Lifecycle position |
| --- | --- | --- | --- |
| `npm run smoke` (`validate.mjs --smoke`) | none | Plugin layout: SKILL.md count, plugin manifests, agents/ and roles/ counts, no forbidden top-level dirs | Every commit / PR (CI) |
| `npm run sanity` (`validate.mjs --sanity`) | none | Same as smoke + role frontmatter integrity + capability-mode partition + research docs + `[OMGB]` markers + ROLE-INDEX content | Every commit / PR (CI) |
| `scripts/local/doctor.sh` | reads `~/.grok/` | Node version, grok CLI, auth.json, user-skill mount, 16-pair role symmetry, launcher dry-run validity | After install / when `/omgb` misbehaves |
| `OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh` | reads `~/.grok/auth.json` | All of smoke + grok inspect + payload + user-skill mount + grok inspect lists `omgb` + launcher dry-run JSON validity + informational audit-all, but no live model probe | After install / structural check |
| `OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh` | invokes `grok -p` | Same as structural e2e + a live model probe returning `OMGB_E2E_OK` | Full release gate (consumes a Grok turn) |
| `validate.mjs --audit-run <slug>` | reads `~/.grok/sessions/` | Each `state.json.activeRoles` has a `## Subagent:` block with valid spawn_method, worker markers, phase, cohort; spawn timing **cross-checked against the Grok session transcript** (events.jsonl); review.md verdicts come from real spawns | Inside a Grok run before Finalization; CI on any merged run dir |
| `validate.mjs --audit-all` | reads `~/.grok/sessions/` | Same as audit-run but across every `.grok/omgb/runs/<slug>/` | Periodic CI sweep |

The static checks (smoke + sanity) need only Node, so they belong in CI.
The live checks (doctor, e2e, headless e2e) need a real Grok login and
belong on a developer workstation or a credential-gated CI lane. The
audit straddles both: it works in CI as a pure Node script, and is more
accurate when the user's `~/.grok/sessions/` is available so it can read
the actual `events.jsonl` instead of relying on the leader's claims.

Optional live headless probe (consumes a real Grok turn):

```bash
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] structural e2e passed` for structural mode
- `[OMGB] e2e passed` for full headless mode
- `[OMGB] audit passed` (per run, or `[OMGB] audit passed (synthesis opt-in)` when `OMGB_ALLOW_SYNTHESIS: true` is set in `mission.md`)

## Mandatory Subagent Spawning (v0.2.0+)

OMGB does not allow the leader to "act as" reviewers. Every role activation
must be a real Grok subagent invocation with a verbatim worker-output block in
`evidence.md`. The leader runs `node scripts/ci/validate.mjs --audit-run <slug>`
before finalizing; the auditor blocks the run if any active role lacks a
`## Subagent: <role>` block, if a reviewer cited in `review.md` was not
actually spawned, or if `spawn_method: unavailable` is claimed without an
explicit synthesis opt-in.

Launch a real team:

```bash
scripts/workflow/launch-omgb-team.sh handoff-fix "Improve resume + subagent support"            # dry-run
scripts/workflow/launch-omgb-team.sh handoff-fix "Improve resume + subagent support" --launch    # actually invokes grok
scripts/workflow/launch-omgb-team.sh perf-audit "Audit hot paths" \
  --roles "leader,codebase-scout,performance-reviewer,test-engineer,verifier" --launch  # slim team
```

See `docs/RUNNING-WITH-SUBAGENTS.md` for the full subagent guide, including the
opt-in synthesis fallback for hosts that genuinely cannot spawn subagents.

## Doctor & Troubleshooting

After installing (or when `/omgb` feels off), run:

```bash
scripts/local/doctor.sh
```

It checks your Node version, Grok CLI + auth, the user-skill mount, the critical `ROLE-INDEX.md` (post-rename), and recent install logs, then prints clear next steps.

## Sharing & Handoff (to Claude Code, Cursor, Codex, etc.)

Any completed OMGB run can be exported as a single, self-contained markdown file that another agent (Claude Code, oh-my-claudecode, Cursor, Codex, etc.) can consume directly.

```bash
scripts/workflow/export-omgb-handoff.sh <task-slug>
```

For full hybrid-team instructions, recommended folder layouts, and prompt templates for the receiving agent, see:

**`docs/WORKING-WITH-OTHER-AGENTS.md`**

Example:

```bash
scripts/workflow/export-omgb-handoff.sh omgb-self-audit-agents-md-install-guide
```

This produces:

- `.grok/omgb/runs/<slug>/OMGB-RUN-<slug>-HANDOFF.md`
- A copy at the repo root for convenience

The handoff file:
- Contains the mission, final OMGB RESULT, condensed evidence, review verdicts, and continuation advice.
- Is written in second person ("You are now the leader...") so the receiving agent can pick up seamlessly.
- Can be dropped into any Claude workspace or referenced from the user's `CLAUDE.md` / `AGENTS.md`:

  > "This task was orchestrated by OMGB in Grok. Also read `OMGB-RUN-omgb-self-audit-agents-md-install-guide-HANDOFF.md` + the sibling `evidence.md` and `tasks.json` for full context and decisions."

The handoff + the five canonical run files give the other agent the same "leader's notebook" the original Grok run used.

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
