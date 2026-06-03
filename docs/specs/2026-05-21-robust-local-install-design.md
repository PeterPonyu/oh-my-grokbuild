# Design: Robust Local Install for oh-my-grokbuild (Drift Detection + Declarative Payload)

**Date**: 2026-05-21  
**Status**: Approved (user: "approved")  
**Context**: Brainstorming session on why a local oh-my-grokbuild checkout was not appearing in an active Grok session after the source tree was moved.

---

## 1. Problem Statement

Developers working on the oh-my-grokbuild repository commonly reorganize their local clones (moving the directory, nesting it under `tools/`, maintaining multiple checkouts, etc.). 

The current `scripts/local/install-local.sh` creates **absolute symlinks** under `~/.grok/skills/omgb/` that point to whatever path the script considered its `ROOT` at the moment of installation. When the source tree later moves, these symlinks dangle. The Grok Build TUI has no valid `omgb` skill to load, so `/omgb` never appears in the current session even after running `/skills` or restarting the TUI.

A secondary but related maintenance problem: the payload copy logic (`cp -r` statements) and the post-copy verification list in the installer, plus equivalent expectations in `scripts/ci/validate.mjs`, are hardcoded. Every time new assets are added to the distributable plugin (new directories, new top-level files required by future evolution of the local plugin layout), multiple places must be edited in lockstep. This is fragile and violates the "avoid hardcoding" principle requested by the user.

The exact reproduction the user experienced:
- Original clone at `~/Desktop/oh-my-grokbuild`
- `install-local.sh --force` created symlinks pointing there
- Repo later moved (or re-cloned) to `~/Desktop/tools/oh-my-grokbuild`
- Mount remained broken; doctor and the TUI both saw nothing usable

---

## 2. Goals

- The directory containing the `install-local.sh` script being executed is **always** the single source of truth for both the user-skill mount (`~/.grok/skills/omgb`) and the local plugin payload (`~/.grok/plugins/local/oh-my-grokbuild`).
- Re-running the installer from a moved or new checkout automatically detects and heals stale mounts (no manual `rm -rf` of `~/.grok/skills/omgb` required).
- Adding or removing files/directories from the distributable local plugin payload requires editing **only one obvious file**.
- `doctor.sh` gives immediate, high-signal, copy-pastable guidance when the mount is out of sync with the current checkout.
- Behavior remains conservative, zero new runtime dependencies, fully compatible with the existing one-skill + per-role file contract, and respects all current environment variables (`OMGB_SKIP_USER_SKILL_MOUNT`, `--force`, etc.).
- The "live development" experience (edits to `SKILL.md`, `agents/`, `roles/` take effect after a TUI reload because of symlinks) is preserved.

---

## 3. Non-Goals (for this change)

- Relative symlinks (absolute paths + explicit drift healing are more reliable across different TUI sessions and `cd` habits).
- Any form of automatic background repair, file watchers, or post-install hooks.
- Changes to the public `plugin.json`, `.claude-plugin/plugin.json`, or the `omgb` skill surface itself.
- New external dependencies (no `jq`, no additional node packages).
- Support for multiple simultaneous active mounts from different checkouts (last installer run wins — acceptable and simple).

---

## 4. Current Architecture (Key Files)

- `scripts/local/install-local.sh:21` — `ROOT` is already computed dynamically from the script location.
- `scripts/local/install-local.sh:138-147` — user-skill mount creation (`ln -sfn` to `$ROOT/...`) with no inspection of any pre-existing mount.
- `scripts/local/install-local.sh:105-115` — hardcoded `cp` block for the local payload.
- `scripts/local/install-local.sh:122-131` — separate hardcoded `for required in ...` list used for sanity after copy.
- `scripts/local/doctor.sh:54-66` — existing mount health check (only checks that something is symlinked and contains "omgb"; does not compare against the *current* script's `ROOT`).
- `scripts/ci/validate.mjs` — contains its own list of expected payload contents for smoke/sanity.

The design re-uses the existing dynamic `ROOT` and `--force` semantics while adding the missing drift layer and a single source of truth for the payload.

---

## 5. Proposed Design

### 5.1 User-Skill Mount Drift Detection & Healing

In `install-local.sh`, immediately before the existing user-skill mount block, insert a small drift-detection routine:

1. If `OMGB_SKIP_USER_SKILL_MOUNT=1`, skip all logic (current behavior) but still emit a one-line note in the log that drift would have been healed.
2. Otherwise:
   - Compute `CURRENT_MOUNT_TARGET` via `readlink -f "$USER_SKILL_DIR/SKILL.md" 2>/dev/null || true`
   - If the resolved directory portion differs from `$ROOT`, or the link is broken/missing:
     - Log (both terminal and evidence log):
       ```
       [OMGB] Drift detected
       Previous user-skill mount pointed at: $OLD_TARGET
       Current script location (new source of truth): $ROOT
       Replacing mount with links to the current tree.
       ```
     - `rm -rf "$USER_SKILL_DIR"` (clean slate — the directory only ever contains our three managed entries)
   - Proceed with the existing `mkdir -p + ln -sfn` sequence (now guaranteed to point at the live `$ROOT`).

The same read-and-compare logic (read-only) is added to `doctor.sh` as the very first check in the "User skill mount" section, producing one of three outcomes:

- **Green pass**: symlink exists, resolves, and the directory matches the doctor's own `$ROOT`.
- **Yellow warning**: healthy symlink but points to a different tree → "To make *this* checkout the active one, run: ./scripts/local/install-local.sh --force from here."
- **Red fail**: broken or missing → "Run ./scripts/local/install-local.sh --force from the checkout you want to use."

This directly answers the original user question ("why is the local version not showing in the current session?") with actionable output.

### 5.2 Declarative Local Payload Manifest

Introduce a new file at the repository root:

**`local-payload.txt`** (plain text, deliberately minimal)

Format:
```text
# local-payload.txt
# One relative path per line. Directories must end with / for recursive copy.
# Comments start with #. Blank lines are ignored.
# This file is the single source of truth for what install-local.sh copies
# into ~/.grok/plugins/local/oh-my-grokbuild and what validate.mjs asserts.

plugin.json
.claude-plugin/plugin.json
skills/
agents/
roles/
README.md
```

In `install-local.sh`:
- Replace the explicit `cp` block with a small pure-bash loop over the manifest (example):
  ```bash
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
    if [[ "$item" == */ ]]; then
      cp -r "$ROOT/${item%/}" "$TARGET/${item%/}"
    else
      cp "$ROOT/$item" "$TARGET/$item"
    fi
  done < "$ROOT/local-payload.txt"
  ```
- The post-copy "required files" sanity loop will be removed; the manifest itself (plus the smoke/sanity tests that will also read it) becomes the single source of truth.

In `scripts/ci/validate.mjs`:
- Add a tiny loader that reads `local-payload.txt` (Node `fs.readFileSync` + split/filter) and uses it for the "installed payload must contain" assertions. This keeps the two tools in sync forever.

Future asset additions (new role files, new top-level documentation the local plugin should carry, etc.) become a one-line edit in `local-payload.txt`.

### 5.3 Evidence, Logging & Messaging

- All drift decisions are appended to the existing `.omgb/evidence/install-<timestamp>.log`.
- Terminal output from the installer is clear, non-alarmist, and ends with the familiar next-steps list (reload TUI, run doctor, etc.).
- Doctor success/failure summary text is updated to mention the new "mount source vs current tree" check.

### 5.4 Documentation Updates (required for completeness)

- `README.md` — Troubleshooting section and "One-command local install" post-install step.
- `docs/AGENT-INSTALL.md` — the deterministic agent-facing recipe (Step 2 and verification).
- Inline help text inside `doctor.sh` success/failure blocks.
- Brief entry in `CHANGELOG.md` (under "Unreleased" or next version).

---

## 6. Implementation Outline (for the subsequent plan)

1. Create `local-payload.txt` with current contents + comments.
2. Edit `install-local.sh`:
   - Add drift detection + healing block for the user-skill mount.
   - Replace hardcoded copy with manifest-driven loop.
   - Update logging around the decisions.
3. Edit `doctor.sh`:
   - Add the cross-check against the script's own `ROOT`.
   - Improve messaging for the three outcomes.
4. Edit `scripts/ci/validate.mjs` to consume the manifest (small addition).
5. Update the four documentation locations listed above.
6. Add a regression test scenario (documented in the plan) that simulates a repo move.

All changes are small and localized. No behavior change for users who never move their clone.

---

## 7. Risks, Trade-offs & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Accidental removal of user-managed files under `~/.grok/skills/omgb/` | Low | The directory we manage only ever contains the three symlinks we create. We `rm -rf` only that directory. |
| Manifest skew between bash installer and node validator | Low | Both read the identical text file; the validator addition is trivial. |
| Users with very old or hand-crafted mounts | Medium | New doctor output and drift messages will guide them on the first re-install. |
| Overly aggressive healing on every run | Low | We only replace when a real mismatch is detected. Normal re-runs on the same tree are cheap `ln -sfn` operations. |

The design favors **explicitness and safety** over cleverness: the user sees exactly what changed and why, and the corrective action is always "run the installer from the tree you want."

---

## 8. Success Criteria (Verification Before Completion)

Before the implementation PR is considered complete:

- `npm test`, `OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh`, and `node scripts/ci/validate.mjs --smoke --sanity` all pass with no regressions.
- The exact user scenario works end-to-end:
  1. Fresh clone at location A → install → `/omgb` visible.
  2. Move (or second clone) to location B.
  3. From location B run `install-local.sh --force`.
  4. `readlink -f ~/.grok/skills/omgb/SKILL.md` now resolves inside location B.
  5. `doctor.sh` reports clean green pass from location B.
  6. After TUI reload or `/skills`, the `omgb` skill is listed and `/omgb` is invocable.
- Drift messages appear in the evidence log and are human-readable.
- `local-payload.txt` is the only place that lists payload contents (no duplication).
- Documentation reads clearly and the "why did my local plugin stop showing?" question is answered by running `doctor.sh`.

---

## 9. Open Questions

None at time of approval. All major points were discussed and resolved during the brainstorming session.

---

*This design was produced via the brainstorming skill and approved by the user before the spec was written. It will be committed and then reviewed by the user before any implementation plan or code changes are created.*
