# Installing oh-my-grokbuild — an agent-facing recipe

This file is a deterministic, copy-pasteable install + verify recipe for an
AI agent (Claude Code, Codex, Cursor, another OMGB run, etc.) to set up the
plugin on a fresh machine. No interactive prompts.

## Preconditions

The host must have:

- `node` >= v18 (the validator is ESM).
- `grok` CLI on `PATH` or installed at `~/.grok/bin/grok` (Grok Build).
- An authenticated Grok session — a non-empty `~/.grok/auth.json`. The
  installer **does not** invoke `grok login` and refuses to proceed without
  this file.
- Write access to `~/.grok/` and the repo root.

## Step 1: clone

```bash
git clone https://github.com/PeterPonyu/oh-my-grokbuild.git
cd oh-my-grokbuild
```

## Step 2: install

```bash
./scripts/local/install-local.sh --force
```

Side effects:

- Runs `node scripts/ci/validate.mjs --smoke` as a mandatory preflight.
- Copies the minimal payload to `~/.grok/plugins/local/oh-my-grokbuild/`.
- Symlinks `~/.grok/skills/omgb/{SKILL.md, agents, roles}` into the repo so
  Grok auto-discovers the `omgb` skill from a normal `grok inspect`.
- Writes a timestamped log to `.omc/evidence/install-<ts>.log`.

Expected success markers in the install output:

- `[OMGB] install ok at ~/.grok/plugins/local/oh-my-grokbuild`
- `mounted user skill at ~/.grok/skills/omgb`

## Step 3: verify (non-interactive)

```bash
./scripts/local/doctor.sh                  # quick health check
npm test                                   # smoke + sanity
./scripts/local/e2e.sh                     # asserts existing Grok login + mount + launcher JSON
```

Expected success markers:

- `Looks good. Reload the Grok TUI ...` (from doctor)
- `[OMGB] smoke passed`
- `[OMGB] sanity passed`
- `[OMGB] e2e passed`

If `~/.grok/auth.json` is missing, the e2e script will exit non-zero with
`FAIL: missing or empty …`. That is the only auth-related failure case the
installer surfaces.

## Step 4: reload Grok

Inside the Grok TUI, run `/plugins` or close+reopen the TUI so the
extensions scanner picks up `~/.grok/skills/omgb`. `grok inspect` from the
plugin root should now list `omgb` as a user skill:

```
Skills (N)
└ omgb                            user
```

## Step 5: start an OMGB run

```bash
./scripts/workflow/launch-omgb-team.sh <short-slug> "<task description>"
./scripts/workflow/launch-omgb-team.sh <short-slug> "<task description>" --launch
```

The first form is a dry-run that writes the 16-role agents JSON and prints
the exact `grok -s … --agents …` command. The second form actually invokes
Grok with `--permission-mode auto` so the leader does not stop between
phases.

## Step 6: audit a completed run

```bash
node scripts/ci/validate.mjs --audit-run <slug>
node scripts/ci/validate.mjs --audit-all
```

The audit reads `~/.grok/sessions/<urlencoded-cwd>/<session-uuid>/events.jsonl`
to verify that the leader's claimed parallel cohorts actually emitted their
`spawn_subagent` calls in a single assistant turn. Hand-crafted `started:`
timestamps cannot fool this check.

## Uninstall

```bash
rm -rf ~/.grok/plugins/local/oh-my-grokbuild
rm -rf ~/.grok/skills/omgb
```

Nothing else under `~/.grok/` is touched. The plugin never writes to
project state outside `.grok/omgb/runs/` (gitignored) and `.omc/evidence/`
(gitignored).

## Machine-readable contract

For agents that prefer JSON:

```json
{
  "preconditions": {
    "node": ">=18",
    "grok": "any version >=0.1.x",
    "auth_file": "~/.grok/auth.json"
  },
  "install_command": "scripts/local/install-local.sh --force",
  "success_markers": [
    "[OMGB] install ok at ~/.grok/plugins/local/oh-my-grokbuild",
    "mounted user skill at ~/.grok/skills/omgb",
    "[OMGB] smoke passed",
    "[OMGB] sanity passed",
    "[OMGB] e2e passed"
  ],
  "verify_commands": [
    "scripts/local/doctor.sh",
    "npm test",
    "scripts/local/e2e.sh"
  ],
  "launch_command": "scripts/workflow/launch-omgb-team.sh <slug> \"<task>\" --launch",
  "audit_command": "node scripts/ci/validate.mjs --audit-run <slug>",
  "uninstall_commands": [
    "rm -rf ~/.grok/plugins/local/oh-my-grokbuild",
    "rm -rf ~/.grok/skills/omgb"
  ]
}
```
