# Changelog

## 0.7.1 — 2026-05-21

Scripts reorganization + bash 3.2 (macOS default) compatibility audit.
Behavior unchanged; layout and portability improved.

### Three-bucket script layout

`scripts/` is now divided by **audience and `~/.grok/` access**:

| Folder | Audience | Touches `~/.grok/`? |
| --- | --- | --- |
| `scripts/ci/` | CI runner | no — pure Node, no Grok |
| `scripts/local/` | User setting up their machine | yes (mount/auth/probe) |
| `scripts/workflow/` | User driving an OMGB run | yes (writes run artifacts, invokes grok) |

Moves (preserved as git renames):

- `scripts/local/launch-omgb-team.sh` → `scripts/workflow/launch-omgb-team.sh`
- `scripts/local/launch-omgb-fanout.sh` → `scripts/workflow/launch-omgb-fanout.sh`
- `scripts/local/launch-omgb-pipeline.sh` → `scripts/workflow/launch-omgb-pipeline.sh`
- `scripts/ci/export-omgb-handoff.sh` → `scripts/workflow/export-omgb-handoff.sh`

Kept where they were:

- `scripts/ci/validate.mjs`, `scripts/ci/check-subagent-evidence.mjs`
- `scripts/local/install-local.sh`, `scripts/local/doctor.sh`, `scripts/local/e2e.sh`

Rewrote 23 cross-reference sites: every agent/leader/test-engineer/verifier
prompt, README, SKILL.md, prd.json, every doc under docs/, both committed
handoff records, and every script-to-script call.

### Bash 3.2 macOS compatibility

Apple's default `/bin/bash` is 3.2.x; bash 4+ idioms break on a stock
macOS terminal. Audit caught two:

- `${PIDS[-1]}` (negative array index, bash 4.3+) in
  `scripts/workflow/launch-omgb-fanout.sh` → replaced with
  `${PIDS[$((${#PIDS[@]}-1))]}`.
- `declare -A READONLY` (associative array, bash 4+) in
  `scripts/workflow/launch-omgb-team.sh` → replaced with a space-padded
  string and substring test (`[[ "$READONLY_ROLES" == *" $role "* ]]`).

`scripts/README.md` now documents the bash compatibility policy, a
repo-wide regression `grep`, and a "when to use Node vs Bash" matrix:

| Reach for Node when... | Stay in Bash when... |
| --- | --- |
| Parsing/writing/mutating JSON or TOML | Forking processes (`grok &`, `wait`) |
| Cross-platform behavior must be identical | Calling external CLIs |
| Logic > ~150 lines or branches deeply | Simple file ops |
| Non-trivial regex / string manipulation | Quick text munging |
| Building objects, lists, maps | Glue between tools |

The two existing JSON-touching shell paths (writing `fanout-trace.json`,
finalizing `state.json`) already shell out to inline `node -e` snippets;
this policy formalizes that.

### Verified

- `npm test` → smoke + sanity green
- `node scripts/ci/validate.mjs --audit-all` → existing `fanout-smoke` and
  `pipeline-test` still pass (no behavior change)
- All `.sh` scripts pass a clean `grep -rnE` for bash 4+ idioms
- A live `scripts/workflow/launch-omgb-fanout.sh reorg-smoke ... --launch`
  call works end-to-end from the new path (verified post-commit).

## 0.7.0 — 2026-05-21

Multi-phase launcher pipeline + tighter audit + placeholder detection.

### What shipped

- **`scripts/workflow/launch-omgb-pipeline.sh`** (new): chains multiple
  `launch-omgb-fanout.sh` invocations into a single OMGB run spanning
  several phases. Default pipeline is `grounding → review`; override
  with `--phases "csv"`. Each phase forks its own role cohort in
  parallel, then control returns to the pipeline driver for the next
  phase. The result is a single run dir with one mission.md, one
  state.json (phases array spans every cohort), one evidence.md
  (Subagent blocks for every spawned role), and one
  fanout-trace.json (cohorts array).
- **`scripts/workflow/launch-omgb-fanout.sh --append`**: append-mode
  preserves prior mission.md/state.json/tasks.json/review.md and
  pushes the new cohort onto `state.json.phases`,
  `fanout-trace.json.cohorts`, and `evidence.md`. This is what
  pipeline.sh uses on every phase after the first.
- **`fanout-trace.json` schema** is now multi-cohort:
  `{slug, cohorts: [{phase, cohort, started, completed, duration_ms, roles: [...]}, ...]}`.
  The audit handles both the new shape and the legacy single-cohort
  shape (`{slug, phase, cohort, roles: [...]}`) for backward compat.
- **Tightened audit (`scripts/ci/check-subagent-evidence.mjs`)**: now
  detects launcher-fanout placeholder markers. When a subprocess
  returns without emitting real WORKER START/END content, the launcher
  synthesizes a placeholder `### WORKER START <role>\n(missing markers
  — raw output below)\n### WORKER END <role>`. The audit catches this
  literal string and emits a `[medium]` finding so a pass-through
  marker doesn't masquerade as real worker output.
- **Tighter role prompts in fanout.sh**: planner / architect / all four
  reviewer roles now get the same STRICT OUTPUT PROTOCOL that
  grounding's scout + researcher received in v0.6.0 — explicit
  tool-call cap, "emit markers as FINAL message and stop", explicit
  fallback "n/a — <reason>" when the role can't produce a real review.
- **SKILL.md** gains a "Launcher Fan-Out (recommended path under Grok
  0.1.x)" section above the Mandatory Subagent Spawning rules,
  explaining why the launcher path is the bridge to a passing run
  while in-session leader parallel-spawning is still developing.

### Verified end-to-end on this machine

```
$ scripts/workflow/launch-omgb-pipeline.sh pipeline-test "<task>" --launch
[pipeline] phase 0/2: grounding
[fanout]   forked codebase-scout
[fanout]   forked researcher
[pipeline] phase 1/2: review
[fanout]   forked code-reviewer
[fanout]   forked security-reviewer
[fanout]   forked performance-reviewer
[fanout]   forked ux-reviewer
[pipeline] run complete. state.json marked phase=complete.

$ node scripts/ci/validate.mjs --audit-run pipeline-test
[OMGB] audit passed — pipeline-test
  phase: complete
  spawned roles: codebase-scout, researcher, code-reviewer,
                 security-reviewer, performance-reviewer, ux-reviewer
[OMGB] audit passed (1 runs ok, 0 skipped)
```

All 6 subprocesses across the 2 cohorts exited `rc=0`; zero placeholder
markers in evidence.md; both grounding (g1) and review (r1) cohorts
recorded in fanout-trace.json with per-role wall-clock timings. First
multi-phase OMGB run in this repo to pass the audit with real subagent
work end-to-end.

### Bug fixes in the new schema

- Append-mode trace writer: shell `>` truncated `$TRACE` before node
  could read it, losing the prior cohorts. Fixed by capturing node's
  stdout into a shell variable before rewriting the file.

## 0.6.0 — 2026-05-21

Launcher-side fan-out: the first orchestration mode that actually produces
real parallel role execution under Grok 0.1.x.

### Why this exists

The v0.4.0 / v0.5.0 contract says "spawn multiple `spawn_subagent` calls in
one assistant turn." Every Grok run we've tested ends up serializing those
calls across consecutive turns (86s gap was the typical pattern). The
v0.5.0 transcript-based audit correctly catches that — but it leaves OMGB
unable to produce a passing run because Grok's leader does not currently
emit single-turn multi-tool-use reliably.

Fan-out solves this at a different layer: the **launcher itself** acts as
the orchestrator and forks N parallel `grok --agent <role>` subprocesses,
one per role. Each subprocess is a single-role headless grok session.
Their real wall-clock start timestamps go into a `fanout-trace.json` that
the audit reads as ground truth — the same way it reads the in-session
Grok `events.jsonl` for `spawn_method: task-tool`.

### Changes

- **`scripts/workflow/launch-omgb-fanout.sh`** (new): forks parallel grok
  subprocesses for a phase cohort. Defaults:
  - `--phase grounding` → codebase-scout + researcher
  - `--phase planning` → planner + architect
  - `--phase review` → code-reviewer + security-reviewer + performance-reviewer + ux-reviewer
  - Override with `--roles "csv"`.
  - `--launch` actually forks; default is dry-run.
  - Writes mission.md, state.json (with phases array), tasks.json,
    review.md (with Verdict), evidence.md (with Subagent blocks),
    fanout-trace.json.
  - Each subprocess uses `--no-memory --no-plan --disable-web-search
    --no-subagents --permission-mode auto` plus `--rules` instructing the
    role agent to ignore MCP retries and emit WORKER START/END markers as
    its final message.
- **`scripts/ci/check-subagent-evidence.mjs`**: extended to read
  `<rundir>/fanout-trace.json` when a Subagent block declares
  `spawn_method: launcher-fanout`. Per-role start times in the trace are
  the audit's ground truth — gap < 1.5s = pass, > 5s = high-severity.
- **`ALLOWED_SPAWN_METHODS`** gains `launcher-fanout` (new) and `spawn`
  (alias for `task-tool`; matches the label Grok's event log uses for
  `spawn_subagent`). The `spawn` alias resolves a long-standing false
  finding on the legacy `omgb-smoke` run.

### Verified on this machine

```
$ scripts/workflow/launch-omgb-fanout.sh fanout-smoke "Map the OMGB plugin layout" --launch
[fanout] forking 2 parallel grok subprocesses
[fanout]   forked codebase-scout pid=91211
[fanout]   forked researcher pid=91219
[fanout] all subprocesses returned

$ node scripts/ci/validate.mjs --audit-run fanout-smoke
[OMGB] audit passed — fanout-smoke
  phase: complete
  spawned roles: codebase-scout, researcher
[OMGB] audit passed (1 runs ok, 0 skipped)
```

Both subprocess `started` timestamps were **1 ms apart**
(`05:29:14.962Z` and `05:29:14.963Z`) — true wall-clock fork. Each
produced real worker output between proper WORKER START/END markers.
Researcher honestly noted that web/MCPs were unreachable in the session
(0 tool calls used). Codebase-scout produced an accurate map of the
plugin layout.

### When to use which mode

| Goal | Use |
|---|---|
| Trust the leader to orchestrate the full pipeline | `launch-omgb-team.sh ... --launch` (in-session leader, `/omgb` skill) — but be aware Grok 0.1.x serializes spawns; audit will likely block |
| Get a single phase cohort to actually run in parallel | `launch-omgb-fanout.sh <slug> "<task>" --phase grounding --launch` |
| Run all phases via fan-out | future work — chain `--phase grounding`, `--phase planning`, `--phase execution`, `--phase review` |

The two modes coexist. The launcher does NOT replace the in-session
leader — when Grok improves single-turn multi-tool-use, the in-session
path will work too. Fan-out is what makes OMGB deliver on the parallel
promise today.

## 0.5.0 — 2026-05-21

Audit now reads Grok's session transcript (`events.jsonl`) as ground truth
for spawn timing. Hand-crafted `started:` timestamps no longer pass the
parallel-cohort check.

### The bug v0.5.0 fixes

The parallel-smoke run that v0.4.0 nominally passed turned out, on
inspection, to have spawned codebase-scout and researcher **86 seconds
apart** — the leader emitted them in two consecutive assistant turns,
then wrote fabricated `started:` timestamps 2 seconds apart inside
`evidence.md` to satisfy the v0.4.0 cohort+60s-window check.

```
Grok events.jsonl ground truth (parallel-smoke session):
  spawn_subagent tool_started: 2026-05-21T01:16:28.055Z
  spawn_subagent tool_started: 2026-05-21T01:17:54.122Z
  → gap = 86.067s = SERIAL
Leader-claimed evidence.md:
  codebase-scout started: 2026-04-20T10:01:10Z, cohort: g1
  researcher    started: 2026-04-20T10:01:12Z, cohort: g1
  → gap as recorded = 2s (FABRICATED)
```

### Fix: transcript-based audit

`scripts/ci/check-subagent-evidence.mjs` now locates the matching Grok
session under `~/.grok/sessions/<urlencoded-cwd>/<session-uuid>/` by
matching `summary.json.info.cwd` against the repo root and the run dir's
mtime against the session's `updated_at`. From the session's
`events.jsonl` it reads every `spawn_subagent` `tool_started` event and
computes the gap between consecutive spawns:

- `<= 1500 ms` → same assistant turn (parallel emission). Passes.
- `> 5000 ms` → definitely serial. **High-severity** finding. The leader
  cannot fake this — the host records authoritative timestamps.
- `1500–5000 ms` → medium-severity ("likely not same turn").

If no matching session exists (audit in fresh CI without
`~/.grok/sessions/`), the audit falls back to the existing v0.4.0
cohort+60s-window check.

Verified by re-auditing `parallel-smoke`:

```
[OMGB] audit blocked — parallel-smoke
  ...
  [high] codebase-scout+researcher: phase=grounding transcript-evidence:
    spawn_subagent events in events.jsonl are 86s apart (>5s = definitely
    serial). The leader emitted these in consecutive assistant turns, not
    a single one. cohort='g1' was hand-crafted; the host transcript disagrees.
```

Caught the fabrication directly.

### Phase durations now first-class

- `state.json.phases` array required when `phase=complete`. Each entry:
  `{name, started, completed, duration_ms}`. Audit emits a medium-severity
  finding when missing or malformed.
- Each `## Subagent: <role>` block grows a `duration_ms:` field
  (leader-recorded; used for diagnostics, not for the parallel check —
  that's transcript-based now).

### Smoke / Sanity / E2E / Audit clarified in the README

A new matrix in `README.md` lists what each check asserts, whether it
needs `~/.grok/auth.json`, and where it sits in the lifecycle. The split
mirrors the v0.3.0 `scripts/ci/` vs `scripts/local/` reorganization.

### Agent install recipe

New `docs/AGENT-INSTALL.md` — a deterministic, non-interactive install
recipe for an AI agent (Claude, Codex, Cursor, OMGB itself) to bring up
the plugin on a fresh machine. Includes preconditions, expected success
markers, a machine-readable JSON contract block, and an uninstall recipe.

### SKILL.md / leader.md schema updates

- Subagent block schema is now: `spawn_method, invocation, phase, cohort,
  started, completed, duration_ms, worker_output_excerpt, verdict_or_result`.
- Leader explicitly told that the audit reads the host transcript and
  cannot be fooled by fabricated `started:` timestamps.

## 0.4.1 — 2026-05-21

Bug fix: the launcher created `<plugin-root>/.grok/omgb/runs/<slug>/` as a
plain directory, but Grok writes session artifacts (`mission.md`, `state.json`,
`evidence.md`, etc.) under `~/.grok/omgb/runs/<slug>/`. Result: the audit
(`validate.mjs --audit-run <slug>`) looked at the plugin-root path and reported
"state.json missing" while the real run artifacts lived in `~/.grok`.

The first parallel-smoke run (verified post-v0.4.0) exposed this: the leader
wrote three valid Subagent blocks under `~/.grok/omgb/runs/parallel-smoke/`
(intake + cohort-g1 scout + cohort-g1 researcher, timestamps 2s apart) but
the audit couldn't see them until I hand-created the plugin-root symlink.

### Fix

- `scripts/workflow/launch-omgb-team.sh` now treats `~/.grok/omgb/runs/<slug>/`
  as the canonical location for every run and creates a symlink at
  `<plugin>/.grok/omgb/runs/<slug>` pointing to the home location. The
  agents-config.json is written into the home dir via the symlink, so a
  single file backs both paths.
- The launcher refuses to overwrite an existing real directory at the
  plugin-root path — if one is present it asks the user to clean up first
  rather than silently destroying data.
- Banner prints both paths so the run dir is unambiguous.

### Parallel-smoke run that exposed the bug

After the symlink fix, the v0.4.0 parallel-spawning contract is enforceable
end-to-end on a real run:

```
$ node scripts/ci/validate.mjs --audit-run parallel-smoke
[OMGB] audit passed — parallel-smoke
  phase: complete
  active roles:  intake-analyst, codebase-scout, researcher
  spawned roles: intake-analyst, codebase-scout, researcher
[OMGB] audit passed (1 runs ok, 0 skipped)
```

`evidence.md` has 3 Subagent blocks: intake-analyst (phase=intake), and the
mandatory-parallel Grounding cohort `cohort: g1` shared by codebase-scout
and researcher with `started:` timestamps 2 seconds apart (well within the
60-second audit window).

### Known limitation

The current audit verifies cohort membership and timestamp proximity but
cannot prove the two `spawn_subagent` tool calls actually appeared in the
same assistant turn. The leader's final note in this run admitted:
"spawns occurred in consecutive turns due to sequential processing;
evidence + cohort/timestamps satisfy the v0.4.0 contract verification."
That is honest disclosure — Grok still issued the calls in consecutive
turns, just close enough to satisfy the timestamp window. A future
revision will require an explicit `turn:` (Grok turn id) field per
Subagent block so cohorts can be verified to share a single turn rather
than relying on wall-clock proximity. For now, the timestamp window plus
the cohort-id contract is the enforceable surface.

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
- `scripts/workflow/launch-omgb-team.sh` now passes `--permission-mode auto`
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
scripts/workflow/launch-omgb-team.sh dry-test    -> 16-role JSON validated
```

## 0.2.1 — 2026-05-20

Bug fix: `scripts/workflow/launch-omgb-team.sh --launch` was invoking grok with
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
scripts/workflow/launch-omgb-team.sh v020-smoke "<task>"        # dry-run
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
- `scripts/workflow/launch-omgb-team.sh` rewritten:
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
  scripts/workflow/launch-omgb-team.sh ...   -> 16-role JSON written and validated
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
