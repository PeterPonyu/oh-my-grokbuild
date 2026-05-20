# OMGB Handoff — Portable Run Record

**For Claude Code, Codex, Cursor, and other markdown-first agents**

This file was produced by the `oh-my-grokbuild` (OMGB) plugin inside Grok Build.
It is a concise summary. The *complete* authoritative record of the run lives in
the five files listed below in the same directory.

You are now acting as the **leader / verifier / next agent** for any remaining work.

---

## Run Artifacts — The Source of Truth

Keep this directory (or at least these five files + this handoff) together when sharing
with another agent. They represent the full OMGB lifecycle and are far more valuable
than this summary alone.

| File            | Purpose |
|-----------------|---------|
| `mission.md`    | Original goal, scope, non-goals, constraints, and acceptance criteria for the entire run |
| `state.json`    | Current phase, timestamps, QA cycles, review rounds, active roles, blockers |
| `tasks.json`    | Every task with id, title, ownerRole, status, acceptance criteria, dependencies, and verification commands |
| `evidence.md`   | Full chronological log: research, commands executed, outputs, decisions, rationale, and intermediate results |
| `review.md`     | All code, UX, security, performance, and verifier reviews with explicit verdicts (APPROVE / COMMENT / REQUEST CHANGES) |

**Recommended usage in Claude Code / Codex / Cursor:**
- Drag the whole run directory into your workspace, or
- Reference the files explicitly: `@mission.md @evidence.md @tasks.json`
- Start your prompt with: "Continue this OMGB run. Read the five artifacts above plus this handoff first."

---

## Mission

# OMGB Mission

**Task Slug:** omgb-self-audit-agents-md-install-guide

**Goal:** Audit the oh-my-grokbuild plugin file structure for correctness and minimalism as a skills-only Grok Build plugin. Assess whether the installation guide (in README.md and scripts/local/install-local.sh) is suitable, complete, and user-friendly. Fix the AGENTS.md hardcoding issue: the role catalog index at `agents/AGENTS.md` is being consumed by the local Grok agent's AGENTS.md loader (triggered by `agents_md: true` in all role frontmatter), causing the index content to be unintentionally hardcoded into worker role contexts. Rename and update references so the index no longer shadows or gets auto-injected as project instructions.

**Scope:**
- Inventory and validate current file tree against declared layout in README and plugin manifests.
- Review install flow, preflight checks, payload selection, user-skill mounting, and post-install instructions.
- Identify any gaps in installation documentation or script robustness.
- Execute the rename of the role index file, update all call sites (SKILL.md, README, validate.mjs, install script, e2e script, root AGENTS.md, prd.json, historical docs if critical).
- Verify no other magic filenames are causing similar issues.
- Run full verification: smoke, sanity, npm test, e2e.
- Staff appropriate roles (codebase-scout, researcher, planner, executor, test-engineer, verifier, code-reviewer, ux-reviewer for install docs).
- Record all evidence, decisions, and commands.

**Non-goals:**
- No changes to role behaviors or addition of new roles.
- No marketplace publishing or version bump unless explicitly required for the fix.
- Do not refactor the entire duplication between SKILL.md table and index file (note only; fix name only).
- Do not touch .git history or force pushes.

**Constraints:**
- All edits must preserve the one-skill contract.
- Validation and e2e must pass after changes (may require local re-install for e2e payload check).
- Ask user before any destructive action on installed payloads.
- Leader owns final integration and report.
- Use only documented Grok surfaces.

**Acceptance Criteria:**
- `mission.md`, `state.json`, `tasks.json`, `evidence.md`, `review.md` exist and are complete in the run dir.
- File structure audit complete with no unexpected files or missing declared artifacts.
- Installation guide gaps identified and either fixed in docs/scripts or explicitly accepted with rationale.
- `agents/AGENTS.md` successfully renamed to `agents/ROLE-INDEX.md` (chosen name).
- Zero references to the old index path remain in runtime-critical files (scripts, SKILL.md, README).
- `node scripts/ci/validate.mjs --smoke` and `--sanity` both report `[OMGB] ... passed`.
- `npm test` passes.
- `scripts/local/e2e.sh` passes (or documented why skipped).
- Code review (at minimum code-reviewer + verifier) returns APPROVE or COMMENT with no blockers.
- Final report follows the OMGB RESULT format.
- No blockers remain; run marked complete.

**Started:** 2026-05-20 (current session)
**Owner:** leader (self-orchestrated for this meta-task)

---

## Final State

- **Phase:** `complete`
- **QA cycles completed:** 1
- **Review rounds completed:** 1
- **Still active:** false

---

## How to Continue (receiving agent instructions)

1. Read the five artifacts listed in the table above (especially `evidence.md` for decisions and `tasks.json` for open work).
2. Treat the last non-completed tasks in `tasks.json` as your backlog.
3. Follow a disciplined process (intake → grounding → plan → execute → verify → review).
4. When you finish work, run the verification commands recorded in the evidence and produce your own handoff or summary.

The original Grok OMGB run used strict phase gates and a single accountable leader.
You now own the next segment of that same contract.

---

**Original run (Grok workspace):** `.grok/omgb/runs/omgb-self-audit-agents-md-install-guide/`

**Handoff generated by:** `scripts/ci/export-omgb-handoff.sh`
**Generated at:** 2026-05-20T15:27:19Z

For hybrid team workflows, recommended prompts, and how to set up your CLAUDE.md / AGENTS.md to automatically pick up OMGB handoffs, see the guide that travels with the plugin:

`docs/WORKING-WITH-OTHER-AGENTS.md`

This handoff + the five sibling files give you the same working memory the original leader had.
