# scripts/

Three buckets, separated by **who runs the script and whether it touches the
user's Grok installation**.

## scripts/ci/ — code-level CI gates, no auth required

Pure Node, no Grok, no `~/.grok/` access. Safe to run in any CI runner.

| Script | Purpose |
| --- | --- |
| `validate.mjs` | Smoke + sanity validator and the `--audit-run` / `--audit-all` wrapper. Run as `npm test`. |
| `check-subagent-evidence.mjs` | Audit kernel that validate.mjs delegates to. Direct: `node scripts/ci/check-subagent-evidence.mjs <slug>`. |

## scripts/local/ — install & diagnose your machine

Touch `~/.grok/`. Don't drive an OMGB run, but set up or diagnose the
environment that runs one. Need Grok auth for the e2e probe.

| Script | Purpose |
| --- | --- |
| `install-local.sh` | Bootstrap: copies the `local-payload.txt` manifest payload to `~/.grok/plugins/local/oh-my-grokbuild` and heals/symlinks the user-skill mount at `~/.grok/skills/omgb`. |
| `doctor.sh` | Read-only health check of Node, Grok CLI, auth, mount drift, role-pair symmetry, launcher dry-run. |
| `e2e.sh` | Asserts an existing Grok login plus manifest payload, launcher JSON validity, and (optional) a live `grok -p` reachability probe. |
| `verify-robust-install.sh` | Local helper for robust install changes: smoke, sanity, install, doctor, and duplicate-payload-list checks. |

## scripts/workflow/ — drive an actual OMGB run

These call `grok` to fork role subprocesses, produce evidence artifacts, and
optionally share them with other agents. Need Grok auth.

| Script | Purpose |
| --- | --- |
| `launch-omgb-team.sh` | In-session leader mode. Writes a 16-role `--agents` JSON and invokes `grok -s … --agents …`. Expects the leader to spawn subagents inside one session (Grok 0.1.x currently serializes these — use fanout instead). |
| `launch-omgb-fanout.sh` | Launcher-fanout single-phase. Forks N parallel `grok --agent <role>` subprocesses for one phase cohort. The recommended path under current Grok. |
| `launch-omgb-pipeline.sh` | Multi-phase fanout. Chains `--phase grounding`, `--phase review`, etc. into one run with a single mission, state.json (phases array), and fanout-trace.json (cohorts array). |
| `export-omgb-handoff.sh` | After a run completes, packages the run dir into a portable markdown handoff for Claude / Codex / Cursor. |

## Lifecycle quick reference

```
# Once per workstation
scripts/local/install-local.sh --force

# Anytime
scripts/local/doctor.sh

# Pre-commit / CI (no Grok auth needed)
npm test                                          # = validate.mjs --smoke && --sanity
node scripts/ci/validate.mjs --audit-all          # bulk audit any completed runs

# Before any release (needs ~/.grok/auth.json)
OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh  # structural check
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh              # + live grok -p probe

# Drive an OMGB run
scripts/workflow/launch-omgb-fanout.sh   <slug> "<task>" --launch
scripts/workflow/launch-omgb-pipeline.sh <slug> "<task>" --launch

# After a run completes
scripts/workflow/export-omgb-handoff.sh <slug>    # share to Claude/Codex/Cursor
node scripts/ci/validate.mjs --audit-run <slug>   # finalization gate
```

## Bash compatibility policy

All `.sh` scripts target **bash 3.2 (macOS default) and newer**. Apple stopped
shipping bash 4+ for licensing reasons, so default-shell macOS users have
3.2.x. Bash 4+ idioms are explicitly avoided:

| Avoid | Use instead |
| --- | --- |
| `declare -A` (associative arrays) | Space-padded string + substring test (`[[ "$SET" == *" $key "* ]]`) |
| `${arr[-1]}` (negative index) | `${arr[$((${#arr[@]}-1))]}` |
| `mapfile` / `readarray` | `while read -r line; do ...` |
| `${var,,}` / `${var^^}` (case) | `tr '[:upper:]' '[:lower:]'` |
| `coproc` | Backgrounded subshell + named pipes |

A repo-wide grep catches regressions:

```bash
grep -rnE 'declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}' scripts/
```

## When to use Node (.mjs) instead of Bash (.sh)

| Reach for Node when... | Stay in Bash when... |
| --- | --- |
| Parsing / writing / mutating JSON or TOML | Forking processes (`grok &`, `wait`) |
| Cross-platform behavior must be identical | Calling external CLIs (`grok`, `node`, `npm`) |
| Logic exceeds ~150 lines or branches deeply | Simple file ops (`cp`, `ln`, `mkdir`, `rm`) |
| Doing string manipulation with non-trivial regex | Quick text munging (`grep`, `sed`, `awk`) |
| Building objects, lists, maps | Glue between tools |
| You'd otherwise use `jq` (not always installed) | Wiring stdin/stdout pipes |

The current split follows this rule:

- `validate.mjs` and `check-subagent-evidence.mjs` are Node because they
  parse evidence.md, state.json, fanout-trace.json, and Grok's events.jsonl.
- Everything in `scripts/local/` and `scripts/workflow/` is shell because
  it's mostly process orchestration. The two places that DO touch JSON
  (`launch-omgb-fanout.sh` writing fanout-trace.json, finalizing state.json)
  shell out to small inline `node -e` snippets so the JSON path stays
  type-safe.

## Why the split

- **Reviewability.** `scripts/ci/` is safe to drop into a generic CI runner without provisioning a Grok login or `~/.grok/` mounts.
- **Blast radius.** Nothing in `scripts/ci/` can mutate user state. `scripts/local/` modifies `~/.grok/` (install/diagnose). `scripts/workflow/` writes run artifacts and invokes `grok` — the only bucket that performs real OMGB execution.
- **Audience clarity.** Each folder has a single audience: CI runner, the user setting up their machine, the user driving an actual run. Mixed-purpose scripts (e.g. `export-omgb-handoff.sh` writes user-visible artifacts and lives next to other workflow tools) belong with their primary audience.
- **Author intent.** The leader subagent inside a Grok run only ever calls `scripts/ci/validate.mjs --audit-run <slug>` for finalization. It does not need anything in `scripts/local/` or `scripts/workflow/` to do its job.
