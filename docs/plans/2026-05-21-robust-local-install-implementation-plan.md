# Implementation Plan: Drift-Aware Authoritative Local Install + Declarative Payload Manifest

**Related spec**: `docs/specs/2026-05-21-robust-local-install-design.md` (Approved)
**Date of plan**: 2026-05-21
**Status**: Ready for executor handoff
**Target deliverable**: Single, safe, reviewable PR that fully implements the design while keeping the repository green after every commit.
**Primary author of plan**: writing-plans skill (per superpowers guidelines)
**Constraints respected**: AGENTS.md (one-skill contract, no new MCPs/hooks/daemons/dependencies, verification via `npm test && scripts/local/e2e.sh`), conservative changes only, bash 3.2+ compatibility.

---

## 1. Goal & Success Criteria (verbatim from approved spec + repo rules)

The installed `omgb` user-skill mount (`~/.grok/skills/omgb`) and the local plugin payload (`~/.grok/plugins/local/oh-my-grokbuild`) are always derived from the **current** location of the `install-local.sh` being executed. Re-running the installer after a repo move automatically heals stale absolute symlinks. Payload contents are declared in exactly one place (`local-payload.txt`). `doctor.sh` gives high-signal guidance on mount drift. All existing behavior for non-relocated clones is unchanged.

**Mandatory final verification (must pass before PR is considered complete)**:
- `npm test` (i.e. `npm run smoke && npm run sanity`) passes with `[OMGB] smoke passed` and `[OMGB] sanity passed`.
- `bash scripts/local/e2e.sh` passes with `[OMGB] e2e passed`.
- `node scripts/ci/validate.mjs --smoke --sanity` passes explicitly.
- The exact relocation scenario from the spec works end-to-end (detailed in the new test artifact):
  1. Fresh clone at location A → install → `/omgb` visible.
  2. Move (or second checkout) to location B.
  3. From B: `./scripts/local/install-local.sh --force`.
  4. `readlink -f ~/.grok/skills/omgb/SKILL.md` now resolves inside B.
  5. `doctor.sh` (run from B) reports clean green pass for the current tree.
  6. After TUI reload or `/skills`, `omgb` is listed and `/omgb` is invocable.
- Drift decision messages appear in `.omc/evidence/install-*.log` and are human-readable.
- `local-payload.txt` is the **only** place listing the distributable payload contents (no remaining duplication in `install-local.sh`, `e2e.sh`, or `validate.mjs`).
- Documentation is updated and the "why did my local skill stop showing after a move?" question is answered by running `doctor.sh`.
- No violations of AGENTS.md boundaries (only `skills/omgb/SKILL.md` is a skill; `plugin.json` / `.claude-plugin/plugin.json` untouched; no new runtime deps).

---

## 2. Scope & Non-Goals

**In scope (this PR only)**:
- New root file `local-payload.txt`.
- Enhancements to `scripts/local/install-local.sh`, `scripts/local/doctor.sh`, `scripts/local/e2e.sh`, `scripts/ci/validate.mjs`.
- Documentation in `README.md`, `docs/AGENT-INSTALL.md`, `CHANGELOG.md`, `scripts/README.md` (light), and a new focused test artifact `docs/REPO-RELOCATION-TEST.md`.
- Inline comments, logging, and doctor messaging.
- The 6-phase ordered implementation that guarantees the tree is always runnable and `npm test` / e2e pass after each logical commit.

**Out of scope (future or separate PRs)**:
- Relative symlinks, watchers, background repair, multiple simultaneous mounts.
- Changes to `plugin.json`, `.claude-plugin/plugin.json`, `skills/omgb/SKILL.md`, any `agents/*.md`, `roles/*.toml`, or `agents/ROLE-INDEX.md`.
- New external commands (`jq`, etc.).
- CI workflow changes or new GitHub Actions jobs.
- Automatic update of `local-payload.txt` (manual one-line edit remains the contract).

---

## 3. Key Technical Context (Grounded in Current Code)

- `ROOT` is already correctly computed in both installer and doctor as `$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)`.
- Current duplication of payload knowledge:
  - `install-local.sh:106-113` (explicit `cp` + `mkdir -p .claude-plugin`).
  - `install-local.sh:122-132` (post-copy `for required in ...` sanity).
  - `e2e.sh:98-108` (identical `for required in ...` list against `LOCAL_INSTALL`).
  - `validate.mjs:177-183` (source-tree `assertExists` for a superset; smoke walks `skills`/`agents` for deeper integrity).
- Mount health in doctor (`doctor.sh:54-66`) only checks "contains omgb" via string match; never compares against the *current* script's `$ROOT`.
- Mount creation (`install-local.sh:142-146`) uses unconditional `mkdir -p` + `ln -sfn` (no prior inspection of existing target).
- Evidence logging already exists via `log()` helper writing to `.omc/evidence/install-*.log`.
- All scripts target bash 3.2+ (no associative arrays, `mapfile`, etc.).

The plan re-uses the dynamic `ROOT`, `--force`, and `OMGB_SKIP_USER_SKILL_MOUNT` contract exactly.

---

## 4. Safe Incremental Order (Phases → Commits)

Changes are ordered so that **after every commit**:
- `npm test` passes.
- `scripts/local/e2e.sh` (when auth present) passes.
- `./scripts/local/install-local.sh --force` succeeds and produces a working mount for the *current* checkout.
- `doctor.sh` remains useful (never regresses).
- The one-skill contract and plugin manifests are untouched.
- No syntax or runtime breakage for users on the current tree.

Recommended commit sequence (executor may squash minor polish within a phase):
1. `feat(install): add local-payload.txt declarative manifest + smoke assertion`
2. `feat(doctor): drift-aware user-skill mount diagnosis (read-only)`
3. `feat(install): drift detection + healing before user-skill mount creation`
4. `refactor(install): drive payload copy from local-payload.txt; eliminate duplication in installer + e2e + validator`
5. `docs: update README, AGENT-INSTALL, CHANGELOG, scripts/README + add relocation test artifact`
6. `chore(verify): final cross-checks, evidence log inspection, and relocation scenario run`

Each phase below lists the exact files, the concrete edits (with context), Definition of Done, and verification commands the executor must run before considering the phase complete / before committing.

---

## 5. Detailed Phases

### Phase 1: Introduce the single source of truth — `local-payload.txt`

**Objective**: Land the declarative manifest with zero behavior change. Future edits to payload will be one-line changes here.

**Files to change**:
- `local-payload.txt` (new file at repository root)
- `scripts/ci/validate.mjs` (tiny additive change only)

**Exact changes**:

1. Create `local-payload.txt` (exact content):

```text
# local-payload.txt
# Single source of truth for the minimal runtime payload that
# install-local.sh copies into ~/.grok/plugins/local/oh-my-grokbuild
# and that e2e.sh / doctor expectations are derived from.
#
# Format:
#   - One relative path per line.
#   - Directories that must be copied recursively end with "/".
#   - Comments (#) and blank lines are ignored.
#   - This file itself is NOT part of the shipped payload (it is a dev/install tool).
#
# When you add or remove distributable top-level items (new docs, a future
# roles/ subdir, etc.), edit ONLY this file.

plugin.json
.claude-plugin/plugin.json
skills/
agents/
roles/
README.md
```

2. In `scripts/ci/validate.mjs`:
   - Add a loader function (place it near other pure helpers, e.g. after `parseFrontmatter` or before `runSmoke`).
   - Call the loader inside `runSmoke()` and assert that every listed item exists in the source tree (this makes the manifest drive payload-related assertions).
   - Also add an explicit `assertExists("local-payload.txt")`.

Suggested addition (implementer may refine names/style while preserving semantics):

```js
function loadLocalPayloadManifest() {
  const txt = readText("local-payload.txt")
  return txt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => (line.endsWith("/") ? line.slice(0, -1) : line))
}

function runSmoke() {
  assertExists("package.json")
  assertExists("local-payload.txt")          // NEW
  // ... existing asserts ...

  // NEW: drive payload-item existence from the manifest (single source)
  const payloadItems = loadLocalPayloadManifest()
  for (const item of payloadItems) {
    assertExists(item)
  }

  // ... rest of runSmoke unchanged ...
}
```

**Definition of Done for Phase 1**:
- `local-payload.txt` exists at root with the exact header + 6 entries above.
- `node scripts/ci/validate.mjs --smoke` succeeds and the new manifest-driven asserts run without failure.
- `npm test` reports both smoke and sanity passed.
- `git diff --stat` shows exactly the new file + the two small hunks in validate.mjs.
- No other files modified.

**Verification commands** (run in order):
```bash
npm test
node scripts/ci/validate.mjs --smoke
ls -l local-payload.txt
head -20 local-payload.txt
```
Commit only after green.

---

### Phase 2: Make `doctor.sh` drift-aware (read-only diagnosis)

**Objective**: The doctor now compares any existing mount against the *current* checkout's `$ROOT` and gives actionable yellow/red guidance. This is the primary user-facing answer to "why is my local omgb not showing after I moved the tree?"

**Files to change**:
- `scripts/local/doctor.sh` (only the "User skill mount" section + summary)

**Exact changes** (insert as the very first logic inside the User skill mount block, replacing/augmenting lines 54-66):

- Keep the existing color helpers.
- After `USER_SKILL=...` compute the current tree's expectation.
- For the symlink case: resolve `SKILL.md`, derive the implied old repo root (three `dirname` steps), compare to `$ROOT`.
- Emit:
  - Green: healthy **and** matches current tree.
  - Yellow: healthy symlink but different tree (include the exact one-line command using the *current* `./scripts/...`).
  - Red / fail for broken/missing or non-symlink.
- Update the final "Doctor summary" block (lines ~123-135) to mention the new "mount source vs current tree" check and adjust the success condition slightly if needed (still requires ROLE-INDEX for full green).

Suggested structure (executor writes clean bash):

```bash
# 4. User skill mount (drift-aware — first check in this section)
USER_SKILL="$HOME/.grok/skills/omgb"
if [[ -L "$USER_SKILL/SKILL.md" ]]; then
  TARGET="$(readlink -f "$USER_SKILL/SKILL.md" 2>/dev/null || true)"
  if [[ -n "$TARGET" && -f "$TARGET" ]]; then
    # Derive the repo root that the symlink currently points at
    local d="$TARGET"
    d="$(dirname "$d")"   # .../omgb
    d="$(dirname "$d")"   # .../skills
    d="$(dirname "$d")"   # repo root
    local mounted_root="$d"
    if [[ "$mounted_root" == "$ROOT" ]]; then
      pass "User skill mount healthy and points to *this* checkout: $USER_SKILL → $mounted_root"
    else
      warn "User skill mount is healthy but points to a *different* tree:"
      info "  Mounted from: $mounted_root"
      info "  Current tree: $ROOT"
      info "  To make *this* checkout active, run:"
      info "    ./scripts/local/install-local.sh --force"
    fi
  else
    fail "User skill symlink exists but target is broken or missing: $TARGET"
  fi
elif [[ -e "$USER_SKILL" ]]; then
  warn "Something exists at $USER_SKILL but it is not the expected symlink created by install-local.sh"
else
  fail "No user skill mount at $USER_SKILL — run scripts/local/install-local.sh --force from the checkout you want to use"
fi
```

Also update the final summary paragraph to reference the new check explicitly.

**Definition of Done**:
- Running `scripts/local/doctor.sh` from the current checkout produces either a clean green "points to *this* checkout" or the exact yellow guidance string from the spec.
- When a stale mount from another path exists, doctor prints the yellow warning + copy-pastable command.
- All later doctor checks (ROLE-INDEX, 16-role symmetry, launcher dry-run, payload, logs) continue to run.
- `npm test` and e2e still pass (doctor is not part of the automated gates but must not regress).

**Verification commands**:
```bash
./scripts/local/doctor.sh
# Manually create a fake stale mount (in a temp dir) and re-run doctor to see yellow path (optional but recommended)
```

Commit after green doctor output on the real tree.

---

### Phase 3: Add drift detection + healing logic to `install-local.sh`

**Objective**: The installer now self-heals on ` --force` (or normal run) when it detects the current mount does not point at the executing `$ROOT`. This is the core fix for the original bug report.

**Files to change**:
- `scripts/local/install-local.sh` (insert new block immediately before the existing `USER_SKILL_DIR=...` block, i.e. before line 138)

**Exact changes**:

Insert a self-contained drift block (pure bash, re-uses existing `log` and `ROOT`):

```bash
# --- Drift detection & healing for user-skill mount (authoritative install) ---
USER_SKILL_DIR="$HOME/.grok/skills/omgb"
if [[ "${OMGB_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
  log "skipping user-skill mount at $USER_SKILL_DIR (OMGB_SKIP_USER_SKILL_MOUNT=1)"
  # Still note that drift healing would have occurred
  if [[ -L "$USER_SKILL_DIR/SKILL.md" ]]; then
    local cur
    cur=$(readlink -f "$USER_SKILL_DIR/SKILL.md" 2>/dev/null || true)
    if [[ -n "$cur" ]]; then
      local d="$cur"; d="$(dirname "$d")"; d="$(dirname "$d")"; d="$(dirname "$d")"
      if [[ "$d" != "$ROOT" ]]; then
        log "NOTE: drift healing would have replaced mount from $d to $ROOT (skipped by OMGB_SKIP...)"
      fi
    fi
  fi
else
  # Detect drift
  local needs_heal=0
  local old_target=""
  if [[ -L "$USER_SKILL_DIR/SKILL.md" ]]; then
    old_target=$(readlink -f "$USER_SKILL_DIR/SKILL.md" 2>/dev/null || true)
    if [[ -z "$old_target" ]]; then
      needs_heal=1
    else
      local d="$old_target"; d="$(dirname "$d")"; d="$(dirname "$d")"; d="$(dirname "$d")"
      if [[ "$d" != "$ROOT" ]]; then
        needs_heal=1
      fi
    fi
  else
    needs_heal=1   # missing or not a symlink we control
  fi

  if [[ $needs_heal -eq 1 ]]; then
    if [[ -n "$old_target" ]]; then
      log "[OMGB] Drift detected"
      log "  Previous user-skill mount pointed at: $old_target"
      log "  Current script location (new source of truth): $ROOT"
      log "  Replacing mount with links to the current tree."
    else
      log "[OMGB] No healthy user-skill mount for current tree; creating fresh mount at $USER_SKILL_DIR"
    fi
    rm -rf "$USER_SKILL_DIR"
  fi

  mkdir -p "$USER_SKILL_DIR"
  ln -sfn "$ROOT/skills/omgb/SKILL.md" "$USER_SKILL_DIR/SKILL.md"
  ln -sfn "$ROOT/agents"              "$USER_SKILL_DIR/agents"
  ln -sfn "$ROOT/roles"               "$USER_SKILL_DIR/roles"
  log "mounted user skill at $USER_SKILL_DIR"
fi
# --- end drift block ---
```

**Important**: The old mount creation block (lines 138-147) is completely replaced by the above. The three `ln -sfn` lines move inside the `else`.

The variable `USER_SKILL_DIR` is now defined at the top of the block.

**Definition of Done**:
- Installer still succeeds on a fresh or same-tree run (no spurious healing).
- When a stale mount exists, running `--force` from the new location produces the exact three-line drift log block (with `[OMGB] Drift detected`).
- The resulting `readlink -f .../SKILL.md` resolves inside the current `$ROOT`.
- Evidence log (`.omc/evidence/install-*.log`) contains the drift messages.
- `npm test` + e2e still pass.
- `--force` on a clean tree remains a cheap `ln -sfn` (no unnecessary rm).

**Verification**:
```bash
./scripts/local/install-local.sh --force
./scripts/local/doctor.sh          # must be green for current tree
cat .omc/evidence/install-*.log | tail -30
```

Commit after the above + a successful `npm test`.

---

### Phase 4: Drive payload copy from the manifest; remove all duplication

**Objective**: Make `local-payload.txt` the single source of truth for both copy and verification. Remove the last hardcoded lists from installer, e2e, and validator.

**Files to change**:
- `scripts/local/install-local.sh`
- `scripts/local/e2e.sh`
- `scripts/ci/validate.mjs`

**Exact changes** (in dependency order inside the phase):

**A. `install-local.sh`** (replace the entire `copy)` case and the post-sanity loop):

In the `case "$MODE" in ... copy)` branch, replace the `mkdir -p ...` + six `cp` lines with:

```bash
copy)
  mkdir -p "$TARGET"
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
    if [[ "$item" == */ ]]; then
      mkdir -p "$(dirname "$TARGET/${item%/}")" 2>/dev/null || true
      cp -r "$ROOT/${item%/}" "$TARGET/${item%/}"
    else
      mkdir -p "$(dirname "$TARGET/$item")" 2>/dev/null || true
      cp "$ROOT/$item" "$TARGET/$item"
    fi
  done < "$ROOT/local-payload.txt"
  log "copied minimal runtime payload (from local-payload.txt)"
  ;;
```

Then **delete entirely** the post-copy sanity block (the `for required in ...` loop that used to live at 122-132). The preflight smoke + manifest-driven copy is now authoritative.

**B. `e2e.sh`** (replace the payload check at ~98-108):

```bash
step "local install payload (driven by local-payload.txt)"
if [[ ! -d "$LOCAL_INSTALL" ]]; then
  fail "installed payload missing at $LOCAL_INSTALL; run scripts/local/install-local.sh first"
fi
while IFS= read -r item || [[ -n "$item" ]]; do
  [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
  local clean="${item%/}"
  if [[ ! -e "$LOCAL_INSTALL/$clean" ]]; then
    fail "installed payload missing $clean (per local-payload.txt)"
  fi
done < "$ROOT/local-payload.txt"
ok "installed payload looks healthy (matches local-payload.txt)"
```

**C. `validate.mjs`**:
- Keep / enhance the `loadLocalPayloadManifest()` from Phase 1.
- The existing `assertExists` calls for payload items may stay (they are now also covered by the manifest loop you added in Phase 1). Optionally, you may remove the now-redundant individual `assertExists("plugin.json")` etc. if you prefer, but it is not required — additive is safer.
- Ensure `local-payload.txt` itself is asserted (already done in Phase 1).

**Definition of Done**:
- `grep -n "plugin.json\|skills/\|agents/\|roles/\|README.md" scripts/local/install-local.sh scripts/local/e2e.sh | grep -v local-payload` returns nothing (no more hardcoded payload lists).
- `npm test` passes (validator uses the manifest).
- Running the installer produces an identical payload tree to before (diff the two trees if paranoid).
- `e2e.sh` payload step now prints "matches local-payload.txt".
- No behavior change for normal users.

**Verification**:
```bash
npm test
./scripts/local/install-local.sh --force
./scripts/local/e2e.sh
diff -rq ~/.grok/plugins/local/oh-my-grokbuild .  # (manual spot-check of key files)
```

Commit only when all green. This is the largest single refactor commit — review carefully.

---

### Phase 5: Documentation & test artifact

**Objective**: Make the improvement discoverable and the relocation regression test permanently documented and repeatable.

**Files to change / create**:
- `README.md`
- `docs/AGENT-INSTALL.md`
- `CHANGELOG.md`
- `scripts/README.md` (light touch)
- `docs/REPO-RELOCATION-TEST.md` (new — the required regression test artifact)

**Exact changes** (high-level; executor writes natural prose):

**README.md**:
- In "One-command local install": mention that re-running from any checkout is now safe and self-healing.
- In "Troubleshooting": expand the first bullet to explain drift, point to `doctor.sh`, and link to the new relocation test doc.
- In "Layout" code block: add `local-payload.txt` with a one-line comment.
- In "Verification" or "Doctor & Troubleshooting" section: note the new doctor output.

**docs/AGENT-INSTALL.md**:
- Step 2 (install): add a sentence "Re-running from a relocated or new checkout automatically heals any stale mounts."
- Step 3 (verify): note that `doctor.sh` now reports whether the mount matches the current source tree.
- Update expected markers if any wording changed.

**CHANGELOG.md**:
- Insert at the very top (after `# Changelog`):

```markdown
## Unreleased

### Robust local installer with drift healing and declarative payload
- `local-payload.txt` is now the single source of truth for everything copied to `~/.grok/plugins/local/oh-my-grokbuild`.
- `install-local.sh` detects when the user-skill mount (`~/.grok/skills/omgb`) points at an old checkout and automatically heals it on re-run (no manual `rm -rf` required).
- `doctor.sh` now distinguishes "healthy but stale tree" (yellow) from "healthy and current" (green) and prints the exact corrective command.
- `e2e.sh` and the validator consume the same manifest; all prior hardcoded payload lists removed.
- Addresses the "repo moved, skill disappeared" failure mode reported in the field.
```

**scripts/README.md**:
- In the table row for `install-local.sh`, add a parenthetical: "(now drift-aware and driven by `local-payload.txt`)".

**New file `docs/REPO-RELOCATION-TEST.md`** (the regression test artifact):

Provide a self-contained, copy-pasteable manual test script + expected outputs that reproduces the exact 6 success criteria steps. Include:
- How to create a "moved" tree safely (`mktemp -d` + `cp -a`).
- Exact commands to run from the new location.
- How to capture `readlink`, doctor output, evidence log snippets.
- Cleanup + "heal back" instructions (re-run installer from the real checkout, then `rm -rf` the temp tree).
- A note: "This scenario must be executed successfully before the PR is merged."

**Definition of Done**:
- All four documentation files updated with clear, non-alarmist language.
- New `docs/REPO-RELOCATION-TEST.md` exists and is referenced from README Troubleshooting.
- `git grep -l "local-payload.txt"` shows the manifest is mentioned in docs where a user or future developer would look.
- No code changes in this phase (pure docs).

**Verification**:
```bash
git diff --stat
head -30 docs/REPO-RELOCATION-TEST.md
```

---

### Phase 6: Final verification, evidence inspection, and PR readiness

**Objective**: Execute the complete Success Criteria (including the manual relocation scenario) and produce the artifacts an executor or reviewer would need.

**Actions (no new "code" changes, only verification + possible tiny polish)**:
1. Run the full automated gate from a clean tree:
   ```bash
   npm test
   bash scripts/local/e2e.sh
   node scripts/ci/validate.mjs --smoke --sanity
   ```
2. Execute the full relocation scenario exactly as documented in `docs/REPO-RELOCATION-TEST.md`. Capture terminal output + relevant log excerpts into a temporary file (e.g. `/tmp/omgb-relocation-evidence.txt`) and attach or reference it in the PR description.
3. Grep the entire repo for any remaining hardcoded payload strings that should have been removed.
4. Inspect the latest install evidence log for a drift-healing entry (from the test in step 2).
5. Confirm `doctor.sh` green on the final healed tree.
6. Confirm `readlink -f ~/.grok/skills/omgb/SKILL.md` points inside the real checkout.
7. Run the repo-wide bash-compat grep from `scripts/README.md` to ensure no new forbidden constructs were introduced.
8. (Optional but recommended) `git log --oneline -6` shows the six logical commits.

**Definition of Done**:
- Every item in the "Mandatory final verification" list at the top of this plan is checked and passes.
- The PR branch is ready for review / squash-merge.
- Any polish commits from this phase are minimal and justified.

**Verification commands** (the final ones the executor must run and record):
```bash
npm test && bash scripts/local/e2e.sh
# Then the full manual relocation steps from docs/REPO-RELOCATION-TEST.md
./scripts/local/doctor.sh | cat
readlink -f ~/.grok/skills/omgb/SKILL.md
ls -l .omc/evidence/install-*.log | tail -1
```

---

## 6. New Test Artifact Summary

- `docs/REPO-RELOCATION-TEST.md` — permanent, executable-by-hand regression test that captures the exact user scenario from the spec. This is the only new non-code artifact required. It lives alongside the design spec and other long-term guidance.

---

## 7. Documentation Update Summary (precise locations)

- **README.md**
  - Layout diagram (add `local-payload.txt` entry)
  - One-command local install paragraph
  - Troubleshooting section (drift explanation + doctor guidance)
  - Doctor & Troubleshooting section (cross-reference)
- **docs/AGENT-INSTALL.md**
  - Step 2 install description
  - Step 3 verify description + markers
- **CHANGELOG.md** — new Unreleased section at top
- **scripts/README.md** — table description for install-local.sh (one sentence)
- **docs/REPO-RELOCATION-TEST.md** (new)

---

## 8. Risks, Mitigations & Judgment Allowed

| Risk | Mitigation in plan |
|------|--------------------|
| Path math for "implied root" is off-by-one | Explicit three-`dirname` example + comment; executor can test with `readlink` on a known tree. |
| `cp` of nested file (`.claude-plugin/...`) fails because parent dir missing | `mkdir -p "$(dirname ...)"` before every non-dir `cp` (shown in Phase 4). |
| Removing the post-copy sanity loop in install hides copy failures | Preflight smoke already guarantees the source files exist; manifest loop itself would fail on `cp` error because of `set -e`. |
| Doctor output changes surprise long-time users | Yellow path still tells them exactly what to run; green path is clearer than before. |
| Executor wants slightly different helper names or logging | Allowed — the plan gives the required behavior and log strings from the spec; style may vary. |

Judgment left to executor: exact helper function names, whether to factor the three-`dirname` into a tiny bash function (duplication is acceptable for two scripts), wording of log lines as long as the required phrases from the spec appear, and minor formatting.

---

## 9. Handoff to Executor / Implementer

You now have everything needed:
- The approved design spec.
- This concrete, ordered, verifiable plan.
- All source files already read in context.

**Next actions**:
1. Create a feature branch from current `main` / `master`.
2. Execute the phases **in order**, running the verification commands after each phase's edits.
3. Commit after each phase (or logical sub-group) using the suggested commit messages.
4. When Phase 6 is green, open the PR with a description that includes:
   - Link to the design spec.
   - Link to this plan.
   - Output of the final relocation test run (redacted paths if needed).
   - Confirmation that `npm test && scripts/local/e2e.sh` is clean.
5. Request review from the usual roles (code-reviewer, verifier, etc.).

If any verification step fails or the manual scenario exposes an edge case not covered, stop, document the finding, and either fix within the plan's spirit or escalate.

The plan is intentionally detailed enough to remove almost all "what do I edit next?" decisions while still leaving room for tasteful bash/Node hygiene.

---

*End of Implementation Plan. Ready for execution.*

**Remember the repo rule**: Before claiming "done", the last human-visible command the executor runs must be:

```bash
npm test && bash scripts/local/e2e.sh
```

and the manual relocation scenario must have succeeded with evidence.