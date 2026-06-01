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
scripts/ci/check-subagent-evidence.mjs # run artifact auditor
scripts/lib/                     # shared Node helpers (state + paths)
scripts/local/e2e.sh             # E2E harness; set mode env for pass marker
scripts/local/install-local.sh   # local install into ~/.grok/plugins/local
scripts/workflow/                # fanout/team launchers and handoff export
docs/examples/                   # sanitized committed OMGB run examples
docs/surface-inventory.json      # /omgb-only surface inventory and classifications
docs/LINEAGE.md                  # non-copying lineage and host-boundary notice
docs/release-checklist.md        # release/readiness gates
docs/research/                   # grounded research notes
prd.json                          # task PRD with acceptance criteria
```

## Roles

The 16 roles are: `leader`, `intake-analyst`, `researcher`, `codebase-scout`,
`planner`, `architect`, `executor`, `debugger`, `test-engineer`, `verifier`,
`code-reviewer`, `security-reviewer`, `performance-reviewer`, `writer`,
`git-steward`, `ux-reviewer`. See `agents/ROLE-INDEX.md` for the index.

## Install

### Prerequisites
- Node.js (v20+) — the validator (`scripts/ci/validate.mjs`) is ESM.
- A working `grok` CLI with an authenticated session (`~/.grok/auth.json` for e2e).
- The repo cloned locally (this is the source of truth; the TUI loads via symlinks).

### One-command local install

```bash
scripts/local/install-local.sh --force
```

- Runs `node scripts/ci/validate.mjs --smoke` as a mandatory preflight.
- Copies the minimal runtime payload declared in `local-payload.txt` into `~/.grok/plugins/local/oh-my-grokbuild`.
- Creates (or refreshes) the user-skill mount at `~/.grok/skills/omgb` so that `/omgb` becomes immediately invocable.
- Keeps the copied local payload at `~/.grok/plugins/local/oh-my-grokbuild` as the portable bundle. In current Grok builds, `/omgb` may appear as `omgb user` rather than as an enabled `oh-my-grokbuild` plugin; the user-skill mount is the runtime contract.
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
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh              # live Grok reachability check
OMGB_E2E_HEADLESS=1 OMGB_E2E_REAL_OMGB=1 scripts/local/e2e.sh  # opt-in real /omgb quota check
npm run e2e:real-omgb                              # same real /omgb gate via npm
scripts/local/verify-robust-install.sh   # validates payload, symlinks, and drift detection
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
| `npm run sanity` (`validate.mjs --sanity`) | none | Same as smoke + role frontmatter integrity + capability-mode partition + research docs + `[OMGB]` markers + ROLE-INDEX content + lineage/release checklist presence | Every commit / PR (CI) |
| `scripts/local/doctor.sh` | reads `~/.grok/` | Node version, grok CLI, auth.json, user-skill mount, 16-pair role symmetry, launcher dry-run validity | After install / when `/omgb` misbehaves |
| `OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh` | reads `~/.grok/auth.json` | All of smoke + grok inspect + payload + user-skill mount + grok inspect lists `omgb user` + launcher dry-run JSON validity + informational canonical-run audit, but no live model probe | After install / structural check |
| `OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh` | invokes `grok -p` | Same as structural e2e + a live model reachability probe returning `OMGB_E2E_OK`; this does **not** prove `/omgb` completed | Live reachability gate (consumes a Grok turn) |
| `OMGB_E2E_HEADLESS=1 OMGB_E2E_REAL_OMGB=1 scripts/local/e2e.sh` | invokes `grok -p "/omgb ..."` in an isolated HOME | Same as headless e2e + an actual `/omgb` slash-skill invocation, isolated from global MCP/plugin noise, requiring non-empty stdout and `OMGB_REAL_OMGB_OK` | Opt-in full `/omgb` gate (consumes additional Grok quota) |
| `validate.mjs --audit-run <slug>` | reads `~/.grok/sessions/` | Each `state.json.activeRoles` has a `## Subagent:` block with valid spawn_method, worker markers, phase, cohort; spawn timing **cross-checked against the Grok session transcript** (events.jsonl); review.md verdicts come from real spawns | Inside a Grok run before Finalization; CI on any merged run dir |
| `validate.mjs --audit-all` | reads `~/.grok/sessions/` | Same as audit-run but across every `.grok/omgb/runs/<slug>/`; skips incomplete probe dirs without `state.json` | Periodic CI sweep |

The static checks (smoke + sanity) need only Node, so they belong in CI.
The live checks (doctor, e2e, headless e2e) need a real Grok login and
belong on a developer workstation or a credential-gated CI lane. The
audit straddles both: it works in CI as a pure Node script, and is more
accurate when the user's `~/.grok/sessions/` is available so it can read
the actual `events.jsonl` instead of relying on the leader's claims.
Use `--audit-run <slug>` as the strict gate for a claimed run; bulk
`--audit-all` may skip dry-run/probe directories that were never completed
runs.

Optional live headless probe (consumes a real Grok turn and proves Grok reachability):

```bash
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh
```

<!-- OMGB_REAL_OMGB_GATE_DOCS -->

Optional real `/omgb` probe (consumes additional real Grok quota and proves the slash skill returns a final answer):

```bash
OMGB_E2E_HEADLESS=1 OMGB_E2E_REAL_OMGB=1 scripts/local/e2e.sh
# or
npm run e2e:real-omgb
```

Expected success markers:

- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] structural e2e passed` for structural mode
- `[OMGB] e2e passed` for full headless mode
- `OMGB_REAL_OMGB_OK` inside the e2e log when `OMGB_E2E_REAL_OMGB=1` is set
- `[OMGB] audit passed` (per run, or `[OMGB] audit passed (synthesis opt-in)` when `OMGB_ALLOW_SYNTHESIS: true` is set in `mission.md`)

The committed `docs/surface-inventory.json` is the release-time inventory for
the compact surface contract. It must keep `skills/omgb/SKILL.md` as the only
`default` + `user_invocable` surface; launchers, validators, manifests, agents,
and roles are advanced/internal support surfaces unless a future decision record
explicitly changes that contract.

### Environment variables

| Env var | Default | Effect |
| --- | --- | --- |
| `OMGB_E2E_HEADLESS` | unset | Set to `1` to enable the live model reachability probe in `scripts/local/e2e.sh` (consumes a real Grok turn; does not invoke `/omgb` by itself). |
| `OMGB_E2E_REAL_OMGB` | unset | Set to `1` together with `OMGB_E2E_HEADLESS=1` to run an isolated real `/omgb` headless probe that must emit `OMGB_REAL_OMGB_OK` (consumes additional Grok quota). |
| `OMGB_E2E_REAL_OMGB_TIMEOUT` | `180` | Timeout in seconds for the opt-in real `/omgb` probe. |
| `OMGB_E2E_STRICT_AUDIT` | unset | Set to `1` to make `scripts/local/e2e.sh` fail when the canonical `~/.grok/omgb/runs` audit has findings; useful for release gating. |
| `OMGB_E2E_ALLOW_HEADLESS_SKIP` | unset | Set to `1` to allow `e2e.sh` to pass without a live Grok login (structural check only). |
| `OMGB_ALLOW_SYNTHESIS` | unset | Set `OMGB_ALLOW_SYNTHESIS: true` in a run's `mission.md` to allow single-context synthesis as a fallback when subagents are unavailable. |
| `OMGB_SUBAGENT_STALL_MS` | `600000` | Per-subagent duration threshold (ms) for stall warnings in `--audit-run` / `--audit-all`. Subagents whose recorded duration exceeds this value print a `WARN` line in the audit report. WARN-only; does not change exit code. |
| `OMGB_RUNS_ROOT` | `~/.grok/omgb/runs` | Overrides where state-io, launchers, exporter, and auditor read/write OMGB run directories. Useful for hermetic tests and CI probes. |
| `OMGB_SESSIONS_ROOT` | `~/.grok/sessions` | Overrides where the auditor looks for Grok session transcripts (`summary.json` / `events.jsonl`). |


### What can still block a pleasant real-user run?

The local gates prove install/discovery, Grok reachability, and a real `/omgb`
slash-skill invocation on this machine. They do not eliminate every external
source of friction. Remaining blockers are operational rather than hidden local
test gaps:

- **Credential or quota state:** `~/.grok/auth.json` can expire, rate-limit, or
  lack quota. Re-run `scripts/local/doctor.sh` and the live e2e when in doubt.
- **Host Grok behavior changes:** future Grok builds may change skill injection,
  `--agents`, session transcript shape, or allowed tool names. The real `/omgb`
  gate is designed to fail loudly if that happens.
- **Full team execution is task-dependent:** the real `/omgb` probe proves the
  slash skill loads and answers under real quota; complex multi-role work still
  needs a completed run plus `validate.mjs --audit-run <slug>`.
- **Remote readiness is separate:** local commits are not proof that GitHub CI,
  a pushed branch, or another machine has the same auth/Grok version. Run the
  release checklist before tagging or sharing.

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

For the runtime audit issue log and standing maintenance routine, see
`docs/RUNTIME-AUDIT-FIXMENTS.md`.

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

A sanitized committed example lives at `docs/examples/sample-completed-run/` so
new contributors and receiving agents can inspect valid artifact shapes without
starting an authenticated Grok session.

This produces:

- `.grok/omgb/runs/<slug>/omgb-handoff-<slug>.md`
- `.grok/omgb/runs/<slug>/omgb-handoff.md`
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
