# Source-feature ports — 2026-05-25

## Purpose

Port three small, recent features from upstream sibling repos
(`oh-my-claudecode`, `oh-my-codex`, `oh-my-openagent`) into
`oh-my-grokbuild` as three independent `.mjs` PRs that each:

- respect grokbuild's "no MCP, no hooks, no daemons" philosophy by
  landing on the existing CI / lib / doctor surfaces only,
- honor the user's directive to prefer TypeScript/`.mjs` for new
  logic (legacy bash launchers stay bash for this batch — a
  bash→TS migration is its own design),
- stay scoped to a single concern under ~50 LOC each,
- pass the existing validators (`scripts/ci/validate.mjs`,
  `scripts/ci/check-subagent-evidence.mjs`,
  `scripts/local/doctor.sh`) before merge.

## Non-goals

- No new hooks (grokbuild ships none and the existing audit-based
  discipline replaces them).
- No new MCP server, no new daemons, no new long-running processes.
- No refactor of the bash launcher fanout (`launch-omgb-fanout.sh`,
  `launch-omgb-pipeline.sh`, `launch-omgb-team.sh`) in this batch.
- No new top-level skills (the single-skill `omgb` design is
  preserved).
- No port of upstream features that require capabilities grokbuild
  does not have (no MCP-tool surface, no pane orchestration, no
  HUD, no in-process subagent registry).

## Source mapping

| PR | Source feature | Source file(s) | Grokbuild target |
|----|----------------|----------------|------------------|
| 1  | Naming-slop validator | `oh-my-claudecode` `src/scripts/pre-tool-enforcer.mjs` (merged #3013, 2026-05-15) | new `scripts/lib/naming-slop.mjs` + integration in `scripts/ci/validate.mjs` |
| 2  | Subagent stall warning | `oh-my-openagent` worktree `4218-stall-timeout-separation` | extend `scripts/ci/check-subagent-evidence.mjs` |
| 3  | Doctor manifest cross-ref | `oh-my-openagent` `src/cli/doctor.ts` (schema-validator pattern) | new `scripts/lib/doctor-manifest.mjs` + integration in `scripts/local/doctor.sh` |

PR1 from the original sketch (co-author opt-out for `git-steward`)
is **dropped**: `agents/git-steward.md` already declares "Never
include Co-Authored-By or auto-attribution lines unless requested,"
which is the same policy contract codex's
`commit-lore-guard.ts` enforces. No port needed.

---

## PR 1 — Naming-slop validator

### What changes

A new file `scripts/lib/naming-slop.mjs` (~40 LOC) exports a single
function `findNamingSlop(roots, opts)` that:

1. Walks each `root` (directory) shallowly *and* recursively (up to
   a configurable depth, default `2`), collecting file paths.
2. For each path, checks the basename against a top-of-file
   `const NAMING_SLOP_PATTERNS` array of regexes.
3. Returns `Array<{ path, pattern }>` for all matches.

Patterns:

- `-final.{ext}`
- `-final-v[0-9]+.{ext}`
- `_backup.*`, `_old.*`, `_copy.*`
- `_v[0-9]+.*` where N ≥ 2
- `* (1).*`, `* copy.*`

`scripts/ci/validate.mjs` is extended with a new sub-check that
calls `findNamingSlop(['agents', 'roles', 'scripts', 'skills',
'docs'])` and prints WARN lines if any matches are found. WARN does
not fail the validator (mirrors the existing convention for
advisory checks) — the validator's exit code stays driven by the
hard checks already in place.

### Source mapping

`oh-my-claudecode` `src/scripts/pre-tool-enforcer.mjs` runs the
same pattern set against file paths at hook time. Grokbuild has no
hook surface, so the port lands as an audit-time validator instead.
The pattern list is identical; only the trigger differs.

### Surfaces NOT changed

- No new hook (grokbuild ships none; user constraint preserved).
- No edit to launcher bash scripts.
- No edit to `plugin.json`.

### LOC estimate

~40 LOC in new `scripts/lib/naming-slop.mjs` + ~10 LOC integration
in `scripts/ci/validate.mjs`. **~50 LOC** total.

### Validation

- `node scripts/ci/validate.mjs` exits 0 (and prints WARN lines if
  any pre-existing slop names are found).
- `node scripts/lib/naming-slop.mjs --self-test` (if a self-test
  block is included) exits 0 on a fixture.

---

## PR 2 — Subagent stall warning in evidence audit

### What changes

`scripts/ci/check-subagent-evidence.mjs` is extended with a
post-evidence pass that:

1. After the existing evidence checks pass, scans the per-subagent
   evidence records for `start_ts` and `end_ts` fields (these
   already exist in the audit transcript — confirm during
   implementation; if absent, add as part of the same diff).
2. Computes `duration_ms = end_ts - start_ts` per subagent.
3. Emits WARN lines for any subagent whose `duration_ms` exceeds
   `STALL_THRESHOLD_MS` (default `600_000`, overridable via
   `OMGB_SUBAGENT_STALL_MS` env var).

Stall is *per-subagent*, not per-launcher-run — that's the
"separation" the upstream pattern (`oh-my-openagent` worktree
`4218-stall-timeout-separation`) is named for. The launcher's
overall run time is unconstrained; only the individual subagent
durations are checked.

WARN does not fail the audit (mirrors grokbuild's existing
spawn-evidence WARN convention); a follow-up PR can promote stall
to FAIL once thresholds are tuned to real-world data.

### Why audit-time, not runtime

Grokbuild's "no daemons" constraint forbids a watchdog process.
Audit-time stall detection happens after the launcher returns and
the evidence transcript is complete, which is a natural fit for
post-hoc warning. Users see stalls in the audit summary.

### Surfaces NOT changed

- No new file. Single-file edit to
  `scripts/ci/check-subagent-evidence.mjs`.
- Launcher bash scripts unchanged. They already capture the
  timestamps the audit needs (or will, after this PR confirms the
  format).
- `scripts/lib/state-io.mjs` unchanged.

### LOC estimate

~30 LOC additive in `scripts/ci/check-subagent-evidence.mjs` (one
helper, one loop, threshold-from-env handling, WARN printing).
~5 LOC for env-var documentation in the script header comment.
**~35 LOC**.

### Validation

- `node scripts/ci/check-subagent-evidence.mjs <transcript-fixture>`
  exits 0 on a clean transcript and prints WARN lines on a
  fixture-with-stall.
- Existing audit-passing transcript fixtures still pass.

---

## PR 3 — Doctor manifest cross-ref

### What changes

A new file `scripts/lib/doctor-manifest.mjs` (~40 LOC) exports
`checkManifest()` which:

1. Reads `plugin.json` at the repo root.
2. Reads `.claude-plugin/plugin.json` (the Claude compatibility
   shim) and confirms both parse as JSON.
3. Validates required fields: `name`, `version`, `description`.
4. If either manifest declares a `skills:` array, confirms every
   listed skill has a matching `skills/<name>/SKILL.md` on disk.
5. Cross-checks: for every directory under `agents/`, confirms a
   matching `roles/<name>.toml` exists (and vice versa — every
   `roles/<name>.toml` has `agents/<name>.md`). Grokbuild's per-role
   convention pairs the two; a mismatch is a real bug.
6. Returns a `{ ok: boolean, findings: Array<{ severity, msg }> }`
   shape; the script can also be invoked with `--print` to write
   findings to stdout.

`scripts/local/doctor.sh` gains a new check section near the end:

```bash
echo
info "Manifest cross-ref:"
node scripts/lib/doctor-manifest.mjs --print
```

The shell script does not interpret the .mjs output — it just lets
node print to stdout. Exit code from .mjs follows the same
WARN/FAIL convention as the rest of doctor.sh.

### Why a .mjs helper (not pure bash)

Per the user's directive: prefer TS/.mjs for new logic. Pure-bash
JSON parsing is fragile; node handles it natively. The bash
`doctor.sh` stays the entry point (preserving the user-facing
behavior); only the new logic is `.mjs`.

### Surfaces NOT changed

- `agents/`, `roles/`, `skills/` directories not modified.
- `plugin.json` and `.claude-plugin/plugin.json` not modified.
- The existing `doctor.sh` checks 1-N (node, install paths, plugin
  presence, etc.) are untouched.

### LOC estimate

~40 LOC in new `scripts/lib/doctor-manifest.mjs` + ~5 LOC append
in `scripts/local/doctor.sh`. **~45 LOC** total.

### Validation

- `node scripts/lib/doctor-manifest.mjs --print` exits 0 on the
  current repo state (any pre-existing pairing mismatches show as
  WARN, not FAIL).
- `bash scripts/local/doctor.sh` exits 0 on a clean install.

---

## Per-PR validation checklist

Every PR in this batch, before merge:

1. `node scripts/ci/validate.mjs` exits 0.
2. `node scripts/ci/check-subagent-evidence.mjs` exits 0 on the
   committed fixtures.
3. `bash scripts/local/doctor.sh` exits 0 on a clean install.
4. Diff stays under ~70 LOC. If a PR grows past 70 LOC during
   implementation, split it.
5. PR body cites the upstream source feature with file path and
   (where available) PR number / branch name.
6. New logic lands as `.mjs` (or `.ts` if a build step is
   introduced); existing bash launcher scripts are not refactored
   in this batch.

## Out of scope for this batch

| Considered | Why deferred / rejected |
|------------|-------------------------|
| Co-author opt-out for git-steward (codex) | Already enforced verbatim in `agents/git-steward.md` line: "Never include Co-Authored-By or auto-attribution lines unless requested." |
| MCP runtime config (claudecode) | Grokbuild has no MCP surface; constraint preserved. |
| Live-tail integration (openagent) | 400+ LOC; needs pane orchestration grokbuild does not have. |
| Sparkshell secret redaction (codex) | No equivalent secret-bearing store in grokbuild; spawn transcripts are short and reviewed by the audit. Revisit if transcripts grow. |
| Per-role effort routing (claudecode/codex) | Grokbuild v0.9 already shipped this; no port needed. |
| HUD model metadata | Grokbuild has no HUD. |
| Bash → TS launcher migration | Out of scope for this batch; ~500+ LOC across multiple files. Track as its own design. |

## Implementation order

PR 1 → PR 2 → PR 3, but the three are independent and can land in
any order. PR 1 first because it introduces the smallest helper
file and sets the `.mjs` convention precedent for the batch.

## Success criteria

- Three PRs opened against `oh-my-grokbuild`, each under ~50 LOC.
- All three pass `validate.mjs`, `check-subagent-evidence.mjs`,
  and `doctor.sh` locally.
- Each PR body cites the upstream source it ports from.
- No new hooks, no MCP, no daemons.
- New logic lands as `.mjs`; bash launcher scripts unchanged.
