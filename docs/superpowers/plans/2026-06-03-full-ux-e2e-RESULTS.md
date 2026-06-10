# Full User-Experience E2E Test — Results

**Date:** 2026-06-03
**Outcome (safe-local scope):** ✅ **4/4 repos FULL** by the cross-repo conformance gate.
**Plan:** `2026-06-03-full-ux-e2e-test.md` · **Spec:** `../specs/2026-06-03-full-ux-e2e-test-design.md`

## Cross-repo conformance gate (Phase 5)

```
$ node oh-my-grokbuild/scripts/cross-repo/e2e-conformance.mjs \
    oh-my-antigravity oh-my-copilot oh-my-cursor oh-my-grokbuild
PASS  OAG   (oh-my-antigravity)
PASS  OMCP  (oh-my-copilot)
PASS  OMCS  (oh-my-cursor)
PASS  OMGB  (oh-my-grokbuild)

Conformance: 4/4 repos FULL   (exit 0)
```

Each `PASS` ran that repo's credential-free `npm run e2e:structural` and verified the contract: required npm scripts, `e2e-contract.json`, `scripts/local/e2e.sh`, and the tier-tagged pass marker.

## Per-repo summary

| Repo | Brand | Branch | Real tier | Real tier status | CI lane |
|---|---|---|---|---|---|
| oh-my-grokbuild | `OMGB` | `docs/full-ux-e2e-design` | `/omgb` real run (reference) | reference (pre-existing harness, contract-normalized) | `ci.yml` `e2e-real` job (file written, fail-closed) |
| oh-my-antigravity | `OAG` | `test/full-ux-e2e` | `init→loop→approve→verify-goal` | ✅ **deterministic, runs green locally** (no model/secret) | `ci.yml` `e2e-real` job |
| oh-my-copilot | `OMCP` | `test/full-ux-e2e` | `deep-interview→ralplan→autopilot` | ⏳ wired, not yet run (needs quota) | NEW `ci.yml` (fast + gated real) |
| oh-my-cursor | `OMCS` | `test/full-ux-e2e` | `intake→…→review` over cursor-agent + bridge MCP | ⏳ wired, not yet run (needs quota) | `node-ts-ci.yml` `e2e-real` job |

**What "FULL" means here:** every repo has the tiered harness (structural / headless / real), declares the contract, emits `e2e-result.json` + a tier-tagged marker, and is mechanically conformant. The structural tier (and antigravity's full real journey) are **verified green**. The copilot/cursor real-model tiers are **wired and reviewed but not yet executed** — they run for the first time in the outward batch (below).

## Guarantees upheld during safe-local build

- **Zero brand leakage** — each repo uses only its own brand token (`grep` for foreign tokens `OMCOP`/`OMCUR`/`OMAG`/`.omcp`/… came back empty in every repo).
- **No push, no secrets set, no model quota consumed.** All work is on local branches.
- Each repo's pre-existing comprehensive `verify` preserved (renamed to `verify:suite` where the contract required `verify` = `npm test && npm run e2e:structural`).
- Evidence dirs (`.omgb|.oag|.omcp|.omcs/evidence`) are gitignored; no artifacts committed.
- Every phase passed a two-stage review (spec compliance → code quality) before acceptance.

## Outward batch — REMAINING (maintainer-triggered)

These steps consume model quota and/or push to the PeterPonyu remotes. Run per repo.

1. **Validate the wired real tiers locally** (copilot, cursor — first real-model run; antigravity already validated; grokbuild is the reference):
   - `cd oh-my-copilot && RUN_COPILOT_AGENT_SMOKE=1 npm run e2e:real`  → expect `[OMCP] e2e passed (tier=real)`
   - `cd oh-my-cursor && CURSOR_API_KEY=… npm run e2e:real`  → expect `[OMCS] e2e passed (tier=real)`
   - `cd oh-my-grokbuild && npm run e2e:real`  → expect `[OMGB] e2e passed (tier=real)`
   - If a real run reveals the model doesn't traverse all asserted phases (cursor) or emit the provenance chain (copilot), adjust the prompt/assertions in that repo's `scripts/local/e2e.sh` and re-run.
2. **Wire each runner's host-CLI install** — replace the fail-closed `… install step TBD by maintainer; exit 1` guard in each plugin repo's CI with the real install command for `grok` / `copilot` / `cursor-agent`.
3. **Set CI secrets:**
   - `gh secret set GROK_AUTH_JSON --repo PeterPonyu/oh-my-grokbuild < ~/.grok/auth.json`
   - `gh secret set COPILOT_GITHUB_TOKEN --repo PeterPonyu/oh-my-copilot`
   - `gh secret set CURSOR_API_KEY --repo PeterPonyu/oh-my-cursor`
   - antigravity: none (deterministic).
4. **Push branches & open PRs:** `git push -u origin HEAD` in each repo; open a PR from `test/full-ux-e2e` (grokbuild from `docs/full-ux-e2e-design`).
5. **Watch CI:** `gh run watch` — confirm the `e2e-real` lane is green (and `[<BRAND>] e2e passed (tier=real)` appears in the log).

**antigravity can go first** — its real tier is deterministic, needs no secret, and its CI `e2e-real` job will pass on a stock runner.

---

## Evidence status correction — 2026-06-09

> **Note:** This section appends an honest accounting of what the checked-in
> evidence actually proves. The original "4/4 repos FULL" headline is preserved
> for historical accuracy; the qualification below is required for correctness.

### What the conformance gate actually validated at HEAD

The `e2e-conformance.mjs` run above exercised the **structural tier only**.
Each `PASS` entry confirmed:

- `e2e-contract.json` present and schema-valid
- `package.json` declares `e2e:structural`, `e2e:headless`, `e2e:real`, `verify`
- `scripts/local/e2e.sh` present
- `npm run e2e:structural` printed the required `[<BRAND>] structural e2e passed` marker

No `e2e-result.json` with `tier=real` was produced or validated during this
run. The checked-in evidence file (`.omgb/evidence/e2e-result.json`, if
present) is structural-tier only.

### CI real tier status at HEAD

The `e2e-real` job in `ci.yml` is **fail-closed** pending a grok CLI install
step. Line 88 of `.github/workflows/ci.yml` reads:

```
command -v grok || { echo "grok CLI not installed on runner — install step TBD by maintainer"; exit 1; }
```

This guard ensures the job fails loudly rather than silently skipping. As of
commit `b3e670d` (the HEAD at time of this correction) no grok install step
precedes the guard, so the real CI lane has **not yet executed** a live
`/omgb` run in CI.

### Corrected interpretation of "4/4 repos FULL"

| Claim | Accurate? | Notes |
|---|---|---|
| 4/4 repos have tiered harness (structural/headless/real) | ✅ | Harness files present in all repos |
| 4/4 repos pass structural conformance gate | ✅ | Verified by the conformance run above |
| 4/4 repos' real tiers have been executed | ❌ | Only oh-my-antigravity's real tier is deterministic; others need quota/secrets |
| oh-my-grokbuild CI real lane is green | ❌ | Blocked by missing grok installer (ci.yml:88 guard, commit b3e670d) |

"FULL" in the conformance output means structural conformance is complete for
all four repos. It does **not** imply real-tier execution. See the outward
batch checklist above for the remaining steps to achieve real-tier CI green.
