# Working with Other Agents (Claude Code, Codex, Cursor, etc.)

`oh-my-grokbuild` (OMGB) is a **Grok Build** plugin. The orchestration itself only runs inside Grok.

However, the **output** of an OMGB run is extremely valuable to teams that use Claude Code, Anthropic's Claude, OpenAI Codex, Cursor, or any other agent that can read markdown files.

This document explains the hybrid workflow and exactly how a non-Grok agent should consume OMGB artifacts.

## The Core Idea

A Grok user runs a complex, multi-phase task with OMGB.  
The Grok agent produces a structured, auditable record under:

```
.grok/omgb/runs/<task-slug>/
  mission.md
  state.json
  tasks.json
  evidence.md
  review.md
  omgb-handoff-<slug>.md     ← the portable summary
  omgb-handoff.md            ← stable short name (preferred when sharing the folder)
```

A teammate using Claude Code (or similar) can take that folder (or the six files) and continue or review the work with full context, without ever running Grok.

## How to Share a Run with a Claude / Codex / Cursor Teammate

### Option 1 – Best (recommended)
The Grok user runs:

```bash
scripts/ci/export-omgb-handoff.sh <task-slug>
```

Then zips or tars the entire run directory:

```bash
cd .grok/omgb/runs
tar -czf ~/omgb-<task-slug>.tar.gz <task-slug>/
```

The receiving agent gets the tarball, extracts it, and starts their prompt with:

> "I received an OMGB run from a Grok teammate. Read all files in this directory, especially the five artifacts and the handoff. Continue / review / verify as the next leader."

### Option 2 – Lightweight
Just send the six files:
- `mission.md`
- `state.json`
- `tasks.json`
- `evidence.md`
- `review.md`
- `omgb-handoff.md` (or the long-named one)

Claude-style agents are excellent at `@` referencing multiple files when they are in the workspace.

## The Handoff File (omgb-handoff.md)

The handoff is a *summary*, not the source of truth.

It always contains a prominent table:

| File            | Purpose |
|-----------------|---------|
| `mission.md`    | Goal, scope, constraints, acceptance criteria |
| `state.json`    | Phase, counts, status |
| `tasks.json`    | Backlog with owners and verification commands |
| `evidence.md`   | Full decision log + command outputs |
| `review.md`     | All review verdicts |

The receiving agent is explicitly told to treat the five files as the authoritative record.

## Recommended Folder Layout When Receiving a Handoff

```
my-project/
  .grok/omgb/runs/previous-task/
    mission.md
    ...
    omgb-handoff.md
  CLAUDE.md                 ← add a line here
```

In your `CLAUDE.md` or `AGENTS.md` you can write:

```markdown
## OMGB Handoffs from Grok Teammates

When a `.grok/omgb/runs/<slug>/` directory appears, treat `omgb-handoff.md` + the five sibling files as the complete context for that task.

Start any follow-up work by reading:
@.grok/omgb/runs/<slug>/omgb-handoff.md
@.grok/omgb/runs/<slug>/evidence.md
@.grok/omgb/runs/<slug>/tasks.json
```

## What Value Does a Claude User Get?

- A **structured, phase-gated** execution history instead of a messy chat transcript.
- Explicit acceptance criteria and verification commands already recorded.
- Multiple rounds of review (code, UX, security, verifier) already performed and documented.
- A single accountable "leader" mindset that the handoff continues.
- The ability to continue a large task that a Grok teammate started, or to audit/review it.

## The `.claude-plugin/` Directory (advanced)

The plugin ships a `.claude-plugin/plugin.json` shim so that the same payload can be installed into Claude-style plugin directories if a future host ever supports it.

Today this is mostly for symmetry and future-proofing. The practical value for Claude users is the **run artifacts + handoff**, not running the orchestration themselves.

## Summary for Mixed Teams

1. Grok user does the heavy orchestration with `/omgb`.
2. At any milestone (or at the end), they run `export-omgb-handoff.sh`.
3. They share the run directory (or the six files).
4. Claude / Codex teammate drops the files in their workspace and continues with full context and discipline.

This pattern gives you the best of both worlds: Grok's persistent role-team orchestration + Claude's strengths, with an auditable handoff contract between them.

---

**Maintained as part of the oh-my-grokbuild plugin.**  
See also the main README "Sharing & Handoff" section and `scripts/local/doctor.sh` output for quick commands.
