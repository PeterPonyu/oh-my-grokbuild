# Changelog

## 0.3.0 — 2026-05-20

Scripts regrouped by audience + tightened `.gitignore` + git author corrected.

### Script reorg (breaking change for direct path users)

Scripts moved out of the flat `scripts/` directory into two folders that
match their audience and authentication requirements:

```
scripts/
├── README.md
├── ci/                                # code-level, no auth needed
│   ├── validate.mjs
│   ├── check-subagent-evidence.mjs
│   └── export-omgb-handoff.sh
└── local/                             # needs Grok auth or touches ~/.grok
    ├── install-local.sh
    ├── doctor.sh
    ├── e2e.sh
    └── launch-omgb-team.sh
```

- `scripts/ci/` runs in any CI runner without provisioning a Grok login or
  `~/.grok/` mounts. It's the surface a generic GitHub Actions workflow can
  rely on.
- `scripts/local/` is the only place that mutates user state or invokes
  the Grok CLI. Code review and audits can focus there.
- All cross-references (README, SKILL.md, CHANGELOG, prd.json, every
  agent .md, every script-to-script call, package.json scripts, doc
  examples) are updated.
- ROOT path computation in each moved script is bumped from `../` to
  `../../` so they continue to resolve the repo root.

### `.gitignore`

Expanded to keep workspace noise out of source:

- Editor and OS junk: `.vscode/`, `.idea/`, `*.swp`, `*.swo`, `Thumbs.db`, `desktop.ini`, `*~`.
- All of `.grok/` (not just `.grok/omgb/runs/`) so runtime mounts and
  caches never leak in.
- Python scratch (`__pycache__/`, `*.pyc`, `.venv/`, `venv/`) for
  drive-by virtualenvs.
- Local scratch: `scratch/`, `tmp/`, `.tmp/`, `*.tmp`, `*.bak`.

### Author identity

Local repo's `user.name` and `user.email` corrected to
`PeterPonyu` / `fuzeyu09@gmail.com`. Earlier commits' authorship is left
intact (no history rewrite); only new commits use the corrected identity.

### Verified locally post-reorg

```
npm test                                      -> smoke + sanity green
node scripts/ci/validate.mjs --audit-all      -> correctly blocks 5 legacy runs
                                                 (exit 1), skips 4 stubs
scripts/local/e2e.sh                          -> [OMGB] e2e passed
scripts/local/doctor.sh                       -> "Looks good", all checks green
scripts/local/launch-omgb-team.sh dry-test    -> 16-role JSON validated
```

## 0.2.1 — 2026-05-20

Bug fix: `scripts/local/launch-omgb-team.sh --launch` was invoking grok with
`--agents "@<config>"`, which Grok 0.1.212 rejects:

```
Error: --agents: invalid JSON: expected value at line 1 column 1
```

The `@<file>` shorthand is documentation cargo-culted from other tools and is
not supported by the current Grok CLI. The launcher now reads the file and
passes the JSON inline. The dry-run output also prints the inline form so
copy-paste works.

Verified by a real live run on this machine:

```
scripts/local/launch-omgb-team.sh v020-smoke "<task>"        # dry-run
grok -s omgb-v020-smoke --cwd "$PWD" --agents "$(cat ...agents-config.json)" \
  --no-memory --no-plan --disable-web-search --max-turns 40 \
  -p "/omgb <task>"
```

The leader subagent loaded `/omgb`, read `skills/omgb/SKILL.md`, and produced
the requested deliverable (`.grok/omgb/runs/v020-smoke/status.md`) listing
all eight OMGB phase names verbatim.

## 0.2.0 — 2026-05-20

Mandatory real subagent spawning. Synthesis is now opt-in, not the default.

Earlier OMGB runs (v0.1.0 / v0.1.1) repeatedly degraded into a single-context
"leader synthesizes every reviewer" pattern. That violated the persistent-team
contract. This release makes the contract enforceable.

- `skills/omgb/SKILL.md` now has a "Mandatory Subagent Spawning (no synthesis)"
  section. The "If the host disables subagents, run each role section
  sequentially while preserving the same task ownership and artifacts."
  escape clause is removed. Each role activation MUST be a real subagent
  spawn and record a `## Subagent: <role>` evidence block.
- `agents/leader.md` gains a "Spawning Discipline" section that forbids the
  leader from signing reviewer verdicts and requires the audit gate before
  finalization.
- All 16 `agents/<role>.md` files now require a uniform "Worker Output
  Marker" block (`### WORKER START <role>` / `### WORKER END <role>`) so
  the leader records subagent output verbatim instead of paraphrasing.
- `scripts/ci/check-subagent-evidence.mjs` (new) audits a run for
  `## Subagent: <role>` blocks against `state.json.activeRoles` and the
  reviewers cited in `review.md`. Exits non-zero on missing or unjustified
  spawn evidence.
- `scripts/ci/validate.mjs` gains `--audit-run <slug>` and `--audit-all`
  modes that delegate to the auditor and propagate its exit code.
- `scripts/local/launch-omgb-team.sh` rewritten:
  - Builds the agents JSON from all 16 roles on disk (no hardcoded subset).
  - Dry-run by default; `--launch` invokes Grok via `grok -s … --agents @…`.
  - Optional `--roles "csv"` to pick a slimmer team for small tasks.
  - Validates the JSON before exit.
- `scripts/local/e2e.sh` adds a "subagent team launcher (dry-run)" step that
  generates a 16-role agents JSON and validates it, plus an informational
  audit-all step.
- `scripts/local/doctor.sh` adds 16-agent/role symmetry and launcher dry-run
  checks.
- Synthesis opt-in: a run can put `OMGB_ALLOW_SYNTHESIS: true` in its
  `mission.md` to explicitly allow single-context mode. The auditor still
  requires a `Synthesis Justification:` line per role and labels the run
  as `(synthesis opt-in)` rather than `passed`.
- Patched the missing `review.md` for the `omgb-resume-subagents` run with
  an independent, evidence-grounded review (Round 1 code-reviewer, Round 2
  ux-reviewer, Round 3 verifier).

Verified locally on this machine:
  npm test                          -> smoke + sanity green
  scripts/local/e2e.sh                    -> [OMGB] e2e passed (incl. launcher
                                       probe + informational audit-all)
  scripts/local/doctor.sh                 -> "Looks good", all checks green
  scripts/local/launch-omgb-team.sh ...   -> 16-role JSON written and validated
  scripts/ci/validate.mjs --audit-all  -> correctly blocks 5 legacy runs;
                                       skips one with no state.json

## 0.1.1 — 2026-05-20

- `scripts/local/install-local.sh` now also mounts the omgb skill at
  `~/.grok/skills/omgb/` via symlinks (`SKILL.md`, `agents/`, `roles/`).
  This is what makes `/omgb` discoverable in `grok inspect` and invocable
  from a fresh Grok session. The plugin payload at
  `~/.grok/plugins/local/oh-my-grokbuild/` is still written for a future
  marketplace flow. Set `OMGB_SKIP_USER_SKILL_MOUNT=1` to opt out.
- `scripts/local/e2e.sh` now verifies the user-skill mount is healthy and that
  `grok inspect` lists `omgb` as a user skill. Set
  `OMGB_E2E_SKIP_USER_SKILL_MOUNT=1` to opt out.
- Live invocation confirmed against this machine's existing Grok login:
  `grok -p "/omgb …"` loads `skills/omgb/SKILL.md`, lists the eight phase
  names, and respects the prompt's no-run constraint.

## 0.1.0 — 2026-05-20

Initial release.

- One-skill entry point at `skills/omgb/SKILL.md` that runs the OMGB phase
  pipeline (intake, grounding, planning, execution, verification, review, fix
  loop, finalization).
- Sixteen detailed roles, each in its own pair of files:
  - `agents/<role>.md` — Grok-native YAML-frontmatter agent prompt with
    purpose, scope, responsibilities, inputs, outputs, constraints, execution
    process, failure handling, records, CI / testing / E2E expectations.
  - `roles/<role>.toml` — Grok-native role config with `description`,
    `default_capability_mode`, `reasoning_effort`, `default_fork_context`.
- Skills-only manifests (`plugin.json`, `.claude-plugin/plugin.json`). No MCP
  servers, hooks, commands, or registered agent plugin surfaces.
- Validator (`scripts/ci/validate.mjs`) enforces the new layout, role inventory,
  read-only / mutating partition, frontmatter integrity, and `[OMGB]` pass
  markers.
- E2E script (`scripts/local/e2e.sh`) that reuses an existing Grok login at
  `~/.grok/auth.json` and never invokes `grok login` itself. Optional
  `OMGB_E2E_HEADLESS=1` adds a live `grok -p` reachability probe.
- Local installer (`scripts/local/install-local.sh`) writes a minimal payload to
  `~/.grok/plugins/local/oh-my-grokbuild`.
- Grounded research notes under `docs/research/` covering official xAI docs,
  the local Grok client (`0.1.212`) capabilities, the native
  `agents/<name>.md` and `roles/<name>.toml` formats, and patterns sampled
  from `oh-my-openagent`, `oh-my-codex`, `oh-my-claudecode`, and
  `oh-my-cursor`.
