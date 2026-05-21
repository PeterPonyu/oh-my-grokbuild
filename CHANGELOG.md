# Changelog

## 0.4.0 — 2026-05-21

Fix the two failure modes the `omgb-smoke` run exposed:

1. **The leader serialized everything.** Phase steps in the skill were
   written as numbered ("1. Spawn X. 2. Spawn Y."), which Grok read as a
   serial recipe. Independent roles like codebase-scout + researcher ran
   2–3 minutes apart, one after another.
2. **The leader stopped between every step to ask the user "should I
   continue?".** A subagent finishing was being treated as a checkpoint,
   not a step.

### Changes

- `skills/omgb/SKILL.md` grows two new mandatory sections before the
  Phase Pipeline:
  - **Parallel Spawning** — defines the mandatory-parallel cohorts
    (Grounding: scout + researcher; Review: every active reviewer;
    Execution: executor + writer when on disjoint files), shows the
    "one assistant turn with N tool calls" pattern explicitly, and
    extends the Subagent evidence schema with optional `phase:` and
    `cohort:` fields.
  - **No-Stop-Between-Phases** — enumerates the exact five cases when
    the leader is allowed to stop and ask, and the four common
    rationalizations that are NOT valid pauses (finished a role,
    crossed a phase boundary, pending tasks, audit pending).
- Phase 1 (Grounding) and Phase 5 (Review) in the pipeline are rewritten
  to require a single-cohort parallel spawn rather than numbered serial
  steps.
- `agents/leader.md` gains "Continuation Discipline (do not pause
  between phases)" and "Parallel Spawning Pattern" sections that mirror
  the skill rules with concrete tool-call shape examples.
- `scripts/local/launch-omgb-team.sh` now passes `--permission-mode auto`
  to grok, so individual ordinary tool calls don't pop confirmation
  prompts (which was forcing stop-and-ask between every step).
- `scripts/ci/check-subagent-evidence.mjs` parses the new `phase:` and
  `cohort:` fields and runs a concurrency check on mandatory-parallel
  phases:
  - Roles in the same phase must share a cohort id, OR have
    `cohort: serial-by-design` plus a `serial_reason:` line.
  - The `started` timestamps within a shared cohort must be within 60s
    of each other (otherwise emit a medium-severity finding for
    "cohort id shared but timestamps imply serial spawn").
  - Violations are high-severity and block finalization, the same as
    other audit failures.

### Verified locally

- `npm test` (smoke + sanity) green after the SKILL.md / leader.md /
  launcher / audit changes.
- Synthetic fixture in `/tmp/concurrency-smoke.mjs`:
  - Serial fixture (scout + researcher with different cohort ids,
    timestamps 4 minutes apart) → audit blocks with
    `phase=grounding ran serially: codebase-scout@g-scout-only,
    researcher@g-researcher-only`.
  - Parallel fixture (same evidence, both blocks share `cohort: g1`,
    timestamps within 30s) → no concurrency finding.
- Audit run on the real `omgb-smoke` artifacts continues to block, but
  on the legitimate pre-existing reasons (unknown spawn_method='spawn'
  for the planner block; executor and test-engineer activated but not
  spawned). No regression in the prior audit logic.

### Why this is v0.4.0 and not v0.3.1

This changes the contract that an OMGB run must follow to pass
`--audit-run`. Previously-passing runs (none exist among the legacy
runs) that did not record `phase:` / `cohort:` would still pass; runs
that DO record `phase:` for grounding or review now must share a
cohort id. That's a soft-breaking contract evolution, hence the minor
bump.

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
