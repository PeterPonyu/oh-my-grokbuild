# Full User-Experience E2E Test — Cross-Repo Design

**Date:** 2026-06-03
**Status:** Approved design (pre-implementation)
**Scope:** 4 maintained PeterPonyu "ohmy" repos — `oh-my-antigravity`, `oh-my-copilot`, `oh-my-cursor`, `oh-my-grokbuild`
**Out of scope:** `oh-my-codex-work` (not a maintained repo), the Yeachan-Heo upstreams (`oh-my-claudecode`, `oh-my-codex`)
**Reference implementation:** `oh-my-grokbuild/scripts/local/e2e.sh` (already FULL)

---

## 1. Goal & the "FULL" bar

Bring all four maintained repos to a uniform, CI-enforced standard of **full end-to-end coverage of the overall user experience**, modeled on grokbuild's tiered `e2e.sh`.

A repo is **FULL** only if all of the following hold:

1. **Real invocation** of the product the way a user runs it, in an **isolated HOME + temp workspace**.
2. The invocation drives the **documented core user journey end-to-end** — the whole lifecycle, not a single command.
3. Success is asserted from **transcript / artifact evidence** that the skill/workflow actually loaded *and* completed — never just exit code 0.
4. It is **wired into CI and gated on every PR**, real model-backed (quota cost accepted).
5. A **credential-free structural tier** still runs everywhere as the fast pre-gate.

"FULL" is **mechanically verified** by a conformance check (§5), not a judgment call.

---

## 2. Two host classes (key architectural fact)

The four repos are not the same kind of product, and the real tier differs accordingly:

| Class | Repos | What "the product" is | Real-tier invocation | Needs model + secrets? |
|---|---|---|---|---|
| **Host-CLI plugin** | copilot, cursor, grokbuild | a plugin/skill loaded into a host agent CLI | invoke host CLI headlessly with a real model, assert transcript evidence | **Yes** |
| **Standalone CLI tool** | antigravity | its own CLI binary (per its README, it does not integrate with the Antigravity IDE/CLI as a plugin) | invoke its own binary end-to-end | **No** — deterministic |

This split is load-bearing: antigravity's real tier is deterministic and secret-free; the other three need per-host auth + model quota in CI.

---

## 3. Architecture — Hybrid (shared contract, per-repo harness)

### 3.1 Shared contract (`E2E-CONTRACT.md`)

Canonical spec lives at **`oh-my-grokbuild/docs/E2E-CONTRACT.md`** (grokbuild is the reference). Each repo **copy-adapts** its harness — no shared runtime dependency — but every harness MUST conform.

**Three-tier model (uniform names + env vars across all repos):**

| Tier | Name | Runs | Needs | Asserts |
|---|---|---|---|---|
| 1 | `structural` | always (local + CI) | nothing (stub/fake host, synthetic envelopes) | plugin installs into isolated root; skills/agents discoverable; hooks fire on synthetic input |
| 2 | `headless` | local + CI | host CLI present (real or stub) | host reachable; plugin context loads; no model assertion |
| 3 | `real` | **CI gated on every PR** + local opt-in | host CLI + auth (plugin repos); none (antigravity) | full user journey runs; transcript/artifact evidence of skill load **and** completion marker |

**Uniform conventions (this is the "contract"):**

- **Env flags:** `OMX_E2E_STRUCTURAL=1`, `OMX_E2E_HEADLESS=1`, `OMX_E2E_REAL=1`. Existing brand-specific flags (e.g. grokbuild's `OMGB_E2E_*`) remain as **aliases** for backward compatibility.
- **npm scripts:** `e2e:structural`, `e2e:headless`, `e2e:real`; `verify` = `test && e2e:structural`.
- **Evidence:** every real run writes `.<brand>/evidence/e2e-<UTC-timestamp>.log` plus a machine-readable `e2e-result.json`:
  ```json
  { "tier": "real", "host": "copilot", "journey": "deep-interview->ralplan->autopilot",
    "passed": true, "evidence_paths": ["..."], "marker": "[OMCOP] e2e passed (tier=real)" }
  ```
- **Pass marker:** a single grep-able line `[<BRAND>] e2e passed (tier=<tier>)`, printed **only** when evidence checks pass.
- **Isolation:** real tier always uses a `mktemp` HOME + workspace copy, read-only host tools where supported, and cleans up symlinked run dirs (grokbuild's cleanup pattern is the reference).

### 3.2 Per-repo harness + the journey each must exercise (the "owned" half)

Each repo owns `scripts/local/e2e.sh` (copy-adapted from grokbuild) plus a thin **host adapter** documenting how to invoke its host.

| Repo | Host | Real-tier invocation | Core journey to exercise E2E | Status today → work |
|---|---|---|---|---|
| **grokbuild** *(reference)* | grok CLI | `grok -s … --agents …` (exists) | `/omgb` skill load → 16-role agents config → run → transcript envelope + completion marker | FULL → formalize against contract, add `e2e-result.json`, env aliases |
| **copilot** | Copilot CLI | headless agent prompt (`RUN_COPILOT_AGENT_SMOKE` path; `COPILOT_SMOKE_MODEL`, pin cheap) | `deep-interview → ralplan → autopilot` pipeline; assert each stage artifact + final autopilot output | MINIMAL → build real `e2e.sh`; **promote `examples/e2e-pipeline-run` from manual README to automated harness**; add brand-new `ci.yml` |
| **cursor** | cursor-agent CLI + cursor-state-bridge MCP | `cursor-agent` headless with bridge MCP live | `intake → research → plan → execute → verify → review` via `@auto-execute`/`@phase-controller`; assert workflow-state transitions through the bridge + final review artifact | MINIMAL → upgrade synthetic structural fixture into a real journey |
| **antigravity** | standalone (no model) | own binary via `spawnSync` (already in `test/cli.test.ts`) | `init → loop --run (clarity gate) → approve → verify-goal` lifecycle in temp HOME; assert ledger + goal-completion | PARTIAL → consolidate existing pipeline tests into one gated `e2e.sh` journey (deterministic, no secrets) |

---

## 4. CI integration — real on every PR

Per-repo CI job matrix:

- **Fast lane (every PR, no secrets):** tier-1 `structural` + tier-2 `headless` against a stubbed host. Blocks merge, ~seconds, zero cost.
- **Real lane (every PR, gated, real model-backed):** tier-3 `real` with host auth from repo secrets:
  - copilot → `COPILOT_TOKEN` / GH Copilot auth; `COPILOT_SMOKE_MODEL` pinned cheap (`gpt-5-mini`).
  - cursor → `CURSOR_API_KEY` / token for cursor-agent.
  - grokbuild → `GROK_AUTH_JSON` secret materialized to `~/.grok/auth.json`.
  - antigravity → **no secret** (deterministic).
- **Cost controls (quota accepted, but bounded):** pin cheapest capable model per host; single journey per PR (no journey matrix on PRs); concurrency-cancel superseded runs; `paths-ignore` for docs-only PRs; hard per-run timeout; reserve any extended/multi-journey runs for a separate nightly schedule.
- **copilot needs a brand-new `ci.yml`** with these lanes (it currently has only `docs-check.yml` + `deploy-pages.yml`, and its structural-e2e script is not wired into CI at all).

---

## 5. Conformance & rollout

### 5.1 Conformance check

A small `e2e-conformance.mjs` (one checked-in script at the `~/Desktop/tools` root, or copied per repo) asserts each repo exposes the contract's npm scripts, env flags, evidence file, and pass marker. This is what mechanically proves *"all four now have full E2E."*

### 5.2 Rollout sequence (dependency-ordered; steps 3–5 parallelizable after step 1)

1. **Ratify the contract** — finalize `E2E-CONTRACT.md` + evidence schema from grokbuild.
2. **grokbuild conformance** — env aliases, emit `e2e-result.json`, confirm reference still passes.
3. **antigravity** — consolidate existing CLI tests into a single gated `e2e.sh`; deterministic, no secrets (early quick win).
4. **copilot** — biggest lift: build `e2e.sh` real journey + **new `ci.yml`** + secrets. First task = host-headless + auth feasibility spike.
5. **cursor** — build real journey over cursor-agent + bridge MCP; upgrade structural fixture. First task = host-headless + auth feasibility spike.
6. **Cross-repo conformance gate** — run `e2e-conformance` across all four; produce the final "FULL ✓" report.

### 5.3 Risk hotspots

- Per-host headless invocation flags + CI auth are the main unknowns → each plugin repo's first task is a short feasibility spike before building the journey.
- Real-model flakiness on PRs → assert on **evidence of skill load + completion marker**, tolerant of model wording; retry-once on transport errors only (never on assertion failure).
- Brand leakage when copy-adapting grokbuild's harness → conformance check + per-repo brand tokens guard against `omgb`/`grok` strings leaking into other repos.
