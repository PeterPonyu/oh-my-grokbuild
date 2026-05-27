# Repo Relocation Test (Manual Regression Scenario)

This document captures the exact scenario that originally broke the local oh-my-grokbuild experience and is now protected by the drift-aware install + doctor.

## Purpose

Prove that after moving (or re-cloning) the oh-my-grokbuild source tree, running the installer from the *new* location automatically heals the `~/.grok/skills/omgb` mount so that `/omgb` works again.

## Prerequisites

- A working `grok` CLI with an authenticated session (`~/.grok/auth.json` recommended but not strictly required for the mount-healing part).
- Node.js (for the validator).

## Step-by-step Test

1. **Create two safe temporary checkouts**
   ```bash
   ORIGINAL_ROOT="$PWD"
   TMPDIR="$(mktemp -d)"
   trap 'cd "$ORIGINAL_ROOT" && ./scripts/local/install-local.sh --force >/dev/null 2>&1 || true; rm -rf "$TMPDIR"' EXIT

   cp -a "$ORIGINAL_ROOT" "$TMPDIR/omgb-A"
   cp -a "$TMPDIR/omgb-A" "$TMPDIR/omgb-B"
   ```

2. **Install from location A**
   ```bash
   cd "$TMPDIR/omgb-A"
   ./scripts/local/install-local.sh --force
   ./scripts/local/doctor.sh
   node scripts/ci/validate.mjs --smoke
   ```

   Expected:
   - Doctor reports the mount points to `$TMPDIR/omgb-A`
   - `node -e 'console.log(require("fs").realpathSync(process.argv[1]))' ~/.grok/skills/omgb/SKILL.md` resolves inside `$TMPDIR/omgb-A`

3. **Run the installer from location B**
   ```bash
   cd "$TMPDIR/omgb-B"
   ./scripts/local/install-local.sh --force | tee "$TMPDIR/install-B.log"
   ./scripts/local/doctor.sh
   npm test
   ```

   Expected:
   - In the install log (`.omgb/evidence/install-*.log`) you should see lines like:
     ```
     [OMGB] Drift detected
     Previous user-skill mount pointed at: /old/path/.../skills/omgb/SKILL.md
     Current script location (new source of truth): /new/path/oh-my-grokbuild
     Replacing mount with links to the current tree.
     ```
   - Doctor should now report clean green: "User skill mount healthy and points to *this* checkout"
   - `node -e 'console.log(require("fs").realpathSync(process.argv[1]))' ~/.grok/skills/omgb/SKILL.md` resolves inside the new location (`$TMPDIR/omgb-B`)
   - The captured `$TMPDIR/install-B.log` contains the drift messages above.

4. **Verify the skill is actually usable**
   - Start (or reload) the Grok Build TUI
   - Run `/skills` or `/plugins`
   - Confirm `omgb` appears as a user skill
   - Try a minimal invocation: `/omgb "quick smoke test of the mount after relocation"`

5. **Negative test (optional but recommended)**
   - Manually point the mount back at the old (now deleted) location.
   - Run doctor from the B checkout → it must show the yellow drift warning + the exact `install --force` command.

## Success Criteria

- After step 3, the mount is healthy for the *current* `$ROOT`.
- `node scripts/ci/validate.mjs --smoke` passes from the B checkout.
- `npm test` passes.
- No stale absolute paths from previous clones remain in `~/.grok/skills/omgb`.

## Automated Helper (recommended)

After the code changes, you can run:

```bash
./scripts/local/verify-robust-install.sh
```

This runs smoke + sanity, `npm test`, an install from the current checkout, the doctor drift check, and duplicate-payload-list checks. It does not replace the full relocation scenario above or authenticated `e2e.sh`.

## Cleanup

```bash
cd "$ORIGINAL_ROOT"
./scripts/local/install-local.sh --force
rm -rf "$TMPDIR"
```

The `trap` in step 1 performs the same cleanup if a command fails midway. This scenario (plus the helper above) must continue to pass after any future change to the install/doctor logic.

---

**Last verified**: 2026-05-22 (full relocation scenario, install, doctor, and e2e)