# scripts/

Scripts are grouped by audience and authentication needs.

## scripts/ci/ — code-level, no auth required

Pure Node or pure bash on local repo files. Safe to run in any CI runner.
Never touches `~/.grok/` or the Grok CLI.

| Script | Purpose |
| --- | --- |
| `validate.mjs` | Smoke + sanity validator and the `--audit-run` / `--audit-all` wrapper. Run as `npm test`. |
| `check-subagent-evidence.mjs` | Audit kernel that validate.mjs delegates to. Auditable by hand: `node scripts/ci/check-subagent-evidence.mjs <slug>`. |
| `export-omgb-handoff.sh` | Bundles a completed run directory into a portable markdown handoff. Reads only `.grok/omgb/runs/<slug>/`; no auth required. |

## scripts/local/ — needs Grok auth or modifies user state

These either read `~/.grok/auth.json`, write to `~/.grok/plugins/local/`,
or invoke the `grok` CLI. Run them on a developer workstation, not in
unauthenticated CI.

| Script | Purpose |
| --- | --- |
| `install-local.sh` | Bootstrap: copies plugin payload to `~/.grok/plugins/local/oh-my-grokbuild` and symlinks the user-skill mount at `~/.grok/skills/omgb`. |
| `doctor.sh` | Read-only health check of Node, Grok CLI, auth, mount, role-pair symmetry, and launcher dry-run. |
| `e2e.sh` | Asserts an existing Grok login plus payload, launcher JSON validity, and (optional) a live `grok -p` reachability probe. |
| `launch-omgb-team.sh` | Spawn entry point. Writes the 16-role `--agents` JSON and invokes `grok -s … --agents …`. Dry-run by default; pass `--launch` to execute. |

## Lifecycle quick reference

```
# Once per workstation
scripts/local/install-local.sh --force

# Anytime
scripts/local/doctor.sh

# Pre-commit / CI
npm test                                          # = node scripts/ci/validate.mjs --smoke && --sanity
node scripts/ci/validate.mjs --audit-all          # catches synthesis in committed runs

# Before any release
scripts/local/e2e.sh                              # needs ~/.grok/auth.json
OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh          # adds a live `grok -p` probe

# Starting a real OMGB run
scripts/local/launch-omgb-team.sh <slug> "<task>" --launch

# After a run completes
scripts/ci/export-omgb-handoff.sh <slug>          # share to Claude / Codex / Cursor
node scripts/ci/validate.mjs --audit-run <slug>   # finalization gate
```

## Why the split

- **Reviewability.** `scripts/ci/` is safe to drop into a generic GitHub Actions runner without provisioning a Grok login or `~/.grok/` mounts.
- **Blast radius.** Nothing in `scripts/ci/` can mutate the user's Grok state. `scripts/local/` is the only place that does, so audits and code review can focus there.
- **Author intent.** The leader subagent inside a Grok run only ever calls `scripts/ci/validate.mjs --audit-run <slug>` for finalization. It does not need the local-only scripts to do its job.
