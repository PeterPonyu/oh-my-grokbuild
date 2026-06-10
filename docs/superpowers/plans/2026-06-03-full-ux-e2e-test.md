# Full User-Experience E2E Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring all four maintained ohmy repos (antigravity, copilot, cursor, grokbuild) to a uniform, CI-enforced standard of full end-to-end coverage of the overall user experience, with a real model-backed tier gated on every PR.

**Architecture:** A shared, copy-adapted contract (3 tiers: structural / headless / real). Each repo owns its `scripts/local/e2e.sh` harness and declares its brand/host specifics in a per-repo `e2e-contract.json`. A single `e2e-conformance.mjs` (checked in at the `~/Desktop/tools` root) mechanically verifies every repo meets the contract. grokbuild is the reference; the other three port its pattern.

**Tech Stack:** bash (harness), Node ≥20 (conformance + checks, `node:test`), GitHub Actions (CI), per-host agent CLIs (grok, Copilot CLI, cursor-agent), python3 (transcript evidence parsing, already used by grokbuild).

**Companion spec:** `oh-my-grokbuild/docs/superpowers/specs/2026-06-03-full-ux-e2e-test-design.md`

---

## Scope & Decomposition

This plan spans **four independent git repos**. It is organized into **six phases**; Phase 0–1 are the foundation (must complete first), Phases 2–4 are per-repo and **parallelizable** after Phase 1, and Phase 5 is the final cross-repo gate.

Because the per-repo host-CLI invocation details (exact headless flags, auth materialization, transcript layout) are external unknowns, **each plugin-repo phase begins with a feasibility spike task whose output supplies the exact commands** used by the remaining tasks in that phase. This is deliberate sequencing, not a placeholder.

**Repo → brand token → host class** (CONFIRMED by the 2.0/3.0/4.0 spikes; tokens derived from each repo's OWN existing brand convention to avoid brand leakage):

| Repo | Brand token | Evidence dir | Host class | Real tier auth (CI secret) |
|---|---|---|---|---|
| oh-my-grokbuild | `OMGB` | `.omgb/evidence` | host-plugin (grok) | `GROK_AUTH_JSON` → `~/.grok/auth.json` |
| oh-my-antigravity | `OAG` | `.oag/evidence` | standalone CLI | **none** (deterministic; isolation via `OH_MY_ANTIGRAV_HOME`, success field `complete:true`) |
| oh-my-copilot | `OMCP` | `.omcp/evidence` | host-plugin (Copilot CLI) | `COPILOT_GITHUB_TOKEN` (also accepts `GH_TOKEN`/`GITHUB_TOKEN`); model `gpt-5-mini`; **no root `package.json` — must create one** |
| oh-my-cursor | `OMCS` | `.omcs/evidence` | host-plugin (cursor-agent) | `CURSOR_API_KEY` (+ optional bridge `OH_MY_CURSOR_MCP_TOKEN`, off by default); state at `.cursor/state/workflow-state.json` |

> Spike-confirmed corrections vs the original draft: antigravity brand is `OAG` (not `OMAG`) and uses `OH_MY_ANTIGRAV_HOME`; copilot plugin namespace is `omcp` (skills invoked as `copilot --agent omcp:<skill>`), auth is `COPILOT_GITHUB_TOKEN` (not `COPILOT_TOKEN`), and it has **no root package.json**; cursor brand is `OMCS`, auth `CURSOR_API_KEY`, real state file is `.cursor/state/workflow-state.json`. These derived tokens were approved by the maintainer.

---

## File Structure

**Cross-repo (tools root, `/home/zeyufu/Desktop/tools/`):**
- Create: `e2e-conformance.mjs` — reads each repo's `e2e-contract.json` + `package.json`, runs `e2e:structural`, asserts contract. One responsibility: prove conformance.
- Create: `e2e-conformance.test.mjs` — `node:test` unit tests for the conformance checker (uses temp fixture dirs).

**Per repo (each of the four):**
- Create: `e2e-contract.json` — declares `{brand, host, hostClass, evidenceDir, journey, markerPrefix, requiresSecret, npmScripts}`.
- Create/Modify: `scripts/local/e2e.sh` — tiered harness (grokbuild already has it; others create it).
- Modify: `package.json` — add/normalize `e2e:structural`, `e2e:headless`, `e2e:real`, `verify` scripts.
- Create/Modify: `.github/workflows/ci.yml` (copilot: create; others: add real lane).

**grokbuild canonical contract doc:**
- Create: `oh-my-grokbuild/docs/E2E-CONTRACT.md` — the human-readable contract every repo conforms to.

---

## Phase 0 — Shared contract + conformance checker

Foundation. Produces the contract doc, the per-repo contract schema, and a working conformance checker with tests. No repo behavior changes yet.

### Task 0.1: Write the canonical contract doc

**Files:**
- Create: `oh-my-grokbuild/docs/E2E-CONTRACT.md`

- [ ] **Step 1: Write the contract doc**

Create `oh-my-grokbuild/docs/E2E-CONTRACT.md` with exactly this content:

```markdown
# ohmy E2E Contract (v1)

Every maintained ohmy repo MUST conform to this contract. Conformance is
verified mechanically by `e2e-conformance.mjs` at the tools root.

## Tiers
- **structural** — credential-free. Stubbed/fake host. Asserts install + skill discovery + hook fire.
- **headless** — host CLI present (real or stub). Asserts host reachable + plugin context loads.
- **real** — full documented user journey, real model (plugin repos) or real own-binary (standalone).
  Asserts transcript/artifact evidence of skill load AND a completion marker. Gated in CI on every PR.

## Required npm scripts
- `e2e:structural`, `e2e:headless`, `e2e:real`
- `verify` = `npm test && npm run e2e:structural`

## Required env flags (brand-specific flags MAY alias these)
- `OMX_E2E_STRUCTURAL=1`, `OMX_E2E_HEADLESS=1`, `OMX_E2E_REAL=1`

## Required artifacts (real tier)
- A log at `<evidenceDir>/e2e-<UTC>.log`
- A machine-readable `<evidenceDir>/e2e-result.json`:
  `{ "tier", "host", "journey", "passed", "evidence_paths": [], "marker" }`
- A grep-able pass marker line: `[<BRAND>] e2e passed (tier=<tier>)`

## Required repo declaration
- `e2e-contract.json` at repo root declaring brand/host/journey (schema in e2e-conformance.mjs).

## Isolation (real tier)
- mktemp HOME + workspace copy; read-only host tools where supported; clean up created run dirs.
```

- [ ] **Step 2: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add docs/E2E-CONTRACT.md
git commit -m "docs: add canonical ohmy E2E contract v1"
```

### Task 0.2: Define the per-repo contract schema + write the conformance checker test (failing)

**Files:**
- Create: `/home/zeyufu/Desktop/tools/e2e-conformance.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `/home/zeyufu/Desktop/tools/e2e-conformance.test.mjs`:

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkRepoConformance } from './e2e-conformance.mjs';

function makeRepo({ contract, scripts, hasHarness = true }) {
  const dir = mkdtempSync(join(tmpdir(), 'e2e-conf-'));
  if (contract) writeFileSync(join(dir, 'e2e-contract.json'), JSON.stringify(contract));
  writeFileSync(join(dir, 'package.json'), JSON.stringify({ name: 'x', scripts }));
  if (hasHarness) {
    mkdirSync(join(dir, 'scripts', 'local'), { recursive: true });
    writeFileSync(join(dir, 'scripts', 'local', 'e2e.sh'), '#!/usr/bin/env bash\n');
  }
  return dir;
}

const VALID_CONTRACT = {
  brand: 'OMGB', host: 'grok', hostClass: 'host-plugin',
  evidenceDir: '.omgb/evidence', journey: '/omgb full run',
  markerPrefix: 'OMGB', requiresSecret: true,
  npmScripts: ['e2e:structural', 'e2e:headless', 'e2e:real', 'verify'],
};
const VALID_SCRIPTS = {
  'e2e:structural': 'x', 'e2e:headless': 'x', 'e2e:real': 'x',
  verify: 'npm test && npm run e2e:structural', test: 'x',
};

test('passes a fully conformant repo', () => {
  const dir = makeRepo({ contract: VALID_CONTRACT, scripts: VALID_SCRIPTS });
  const r = checkRepoConformance(dir, { runStructural: false });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, true, JSON.stringify(r.failures));
});

test('fails when a required npm script is missing', () => {
  const { ['e2e:real']: _omit, ...partial } = VALID_SCRIPTS;
  const dir = makeRepo({ contract: VALID_CONTRACT, scripts: partial });
  const r = checkRepoConformance(dir, { runStructural: false });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, false);
  assert.ok(r.failures.some((f) => f.includes('e2e:real')));
});

test('fails when e2e-contract.json is absent', () => {
  const dir = makeRepo({ contract: null, scripts: VALID_SCRIPTS });
  const r = checkRepoConformance(dir, { runStructural: false });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, false);
  assert.ok(r.failures.some((f) => f.includes('e2e-contract.json')));
});

test('fails when the harness script is absent', () => {
  const dir = makeRepo({ contract: VALID_CONTRACT, scripts: VALID_SCRIPTS, hasHarness: false });
  const r = checkRepoConformance(dir, { runStructural: false });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, false);
  assert.ok(r.failures.some((f) => f.includes('scripts/local/e2e.sh')));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/zeyufu/Desktop/tools && node --test e2e-conformance.test.mjs`
Expected: FAIL — `Cannot find module './e2e-conformance.mjs'`.

### Task 0.3: Implement the conformance checker

**Files:**
- Create: `/home/zeyufu/Desktop/tools/e2e-conformance.mjs`

- [ ] **Step 1: Write the implementation**

Create `/home/zeyufu/Desktop/tools/e2e-conformance.mjs`:

```javascript
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const REQUIRED_SCRIPTS = ['e2e:structural', 'e2e:headless', 'e2e:real', 'verify'];
const REQUIRED_CONTRACT_KEYS = [
  'brand', 'host', 'hostClass', 'evidenceDir', 'journey', 'markerPrefix',
  'requiresSecret', 'npmScripts',
];

export function checkRepoConformance(repoDir, opts = {}) {
  const { runStructural = true } = opts;
  const failures = [];

  const contractPath = join(repoDir, 'e2e-contract.json');
  let contract = null;
  if (!existsSync(contractPath)) {
    failures.push('missing e2e-contract.json at repo root');
  } else {
    try {
      contract = JSON.parse(readFileSync(contractPath, 'utf8'));
      for (const k of REQUIRED_CONTRACT_KEYS) {
        if (!(k in contract)) failures.push(`e2e-contract.json missing key: ${k}`);
      }
    } catch (e) {
      failures.push(`e2e-contract.json is not valid JSON: ${e.message}`);
    }
  }

  const pkgPath = join(repoDir, 'package.json');
  if (!existsSync(pkgPath)) {
    failures.push('missing package.json');
  } else {
    const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
    const scripts = pkg.scripts || {};
    for (const s of REQUIRED_SCRIPTS) {
      if (!scripts[s]) failures.push(`package.json missing required script: ${s}`);
    }
    if (scripts.verify && !/npm (run )?test/.test(scripts.verify)) {
      failures.push('verify script must run the test suite (npm test)');
    }
  }

  if (!existsSync(join(repoDir, 'scripts', 'local', 'e2e.sh'))) {
    failures.push('missing harness at scripts/local/e2e.sh');
  }

  if (runStructural && failures.length === 0 && contract) {
    try {
      const out = execFileSync('npm', ['run', 'e2e:structural'], {
        cwd: repoDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 180000,
      });
      const marker = `[${contract.markerPrefix}] structural e2e passed`;
      if (!out.includes(marker)) {
        failures.push(`structural run did not print marker: ${marker}`);
      }
    } catch (e) {
      failures.push(`e2e:structural failed: ${(e.stderr || e.message || '').toString().slice(0, 400)}`);
    }
  }

  return { repoDir, brand: contract?.brand ?? null, passed: failures.length === 0, failures };
}

function main(argv) {
  const repos = argv.length ? argv : ['.'];
  let allPassed = true;
  const results = [];
  for (const repo of repos) {
    const r = checkRepoConformance(repo, { runStructural: true });
    results.push(r);
    if (!r.passed) allPassed = false;
    const status = r.passed ? 'PASS' : 'FAIL';
    console.log(`${status}  ${r.brand ?? repo}  (${repo})`);
    for (const f of r.failures) console.log(`        - ${f}`);
  }
  console.log(`\nConformance: ${results.filter((r) => r.passed).length}/${results.length} repos FULL`);
  process.exit(allPassed ? 0 : 1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2));
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd /home/zeyufu/Desktop/tools && node --test e2e-conformance.test.mjs`
Expected: PASS — 4/4 tests pass.

- [ ] **Step 3: Commit**

```bash
cd /home/zeyufu/Desktop/tools
git init -q 2>/dev/null || true   # tools root is not a git repo; init only if you want to version it. Otherwise skip.
# If you do NOT want a git repo at the tools root, skip the commit and track these
# two files inside grokbuild instead (see Task 0.4).
```

### Task 0.4: Decide conformance-script home (tools-root vs grokbuild)

**Files:**
- Modify: location of `e2e-conformance.mjs` / `e2e-conformance.test.mjs`

- [ ] **Step 1: Place the checker in grokbuild (recommended — avoids a new git repo at the tools root)**

```bash
mkdir -p /home/zeyufu/Desktop/tools/oh-my-grokbuild/scripts/cross-repo
git -C /home/zeyufu/Desktop/tools/oh-my-grokbuild mv 2>/dev/null || true
cp /home/zeyufu/Desktop/tools/e2e-conformance.mjs /home/zeyufu/Desktop/tools/oh-my-grokbuild/scripts/cross-repo/
cp /home/zeyufu/Desktop/tools/e2e-conformance.test.mjs /home/zeyufu/Desktop/tools/oh-my-grokbuild/scripts/cross-repo/
```

Invoke it cross-repo with explicit paths, e.g.:
`node oh-my-grokbuild/scripts/cross-repo/e2e-conformance.mjs ../oh-my-antigravity ../oh-my-copilot ../oh-my-cursor .`

- [ ] **Step 2: Commit in grokbuild**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add scripts/cross-repo/e2e-conformance.mjs scripts/cross-repo/e2e-conformance.test.mjs
git commit -m "test: add cross-repo E2E conformance checker"
```

---

## Phase 1 — grokbuild conformance (reference repo)

grokbuild already has the tiered harness. Work: (a) add `e2e-contract.json`, (b) normalize npm script names + `OMX_E2E_*` aliases, (c) emit `e2e-result.json` + the `(tier=...)` marker suffix, (d) add the **real-in-CI lane** (new — grokbuild only runs structural in CI today).

### Task 1.1: Add grokbuild's contract declaration

**Files:**
- Create: `oh-my-grokbuild/e2e-contract.json`

- [ ] **Step 1: Write the file**

```json
{
  "brand": "OMGB",
  "host": "grok",
  "hostClass": "host-plugin",
  "evidenceDir": ".omgb/evidence",
  "journey": "/omgb skill load -> 16-role agents JSON -> real run -> transcript+marker",
  "markerPrefix": "OMGB",
  "requiresSecret": true,
  "npmScripts": ["e2e:structural", "e2e:headless", "e2e:real", "verify"]
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add e2e-contract.json
git commit -m "test: declare grokbuild e2e-contract.json"
```

### Task 1.2: Normalize npm scripts + add OMX_E2E_* aliases

**Files:**
- Modify: `oh-my-grokbuild/package.json:11-14`
- Modify: `oh-my-grokbuild/scripts/local/e2e.sh:386-391,517-529`

- [ ] **Step 1: Add `e2e:real` alias script and keep the legacy one**

In `oh-my-grokbuild/package.json`, replace the scripts block lines 11-14 with:

```json
    "e2e:structural": "OMGB_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh",
    "e2e:headless": "OMGB_E2E_HEADLESS=1 bash scripts/local/e2e.sh",
    "e2e:real-omgb": "OMGB_E2E_HEADLESS=1 OMGB_E2E_REAL_OMGB=1 bash scripts/local/e2e.sh",
    "e2e:real": "OMGB_E2E_HEADLESS=1 OMGB_E2E_REAL_OMGB=1 bash scripts/local/e2e.sh",
    "verify": "npm test && npm run e2e:structural"
```

- [ ] **Step 2: Add OMX_E2E_* aliases at the top of `main()` in e2e.sh**

In `oh-my-grokbuild/scripts/local/e2e.sh`, immediately after `set -euo pipefail` (line 26), insert:

```bash
# Contract aliases: OMX_E2E_* are the cross-repo canonical flags; the OMGB_*
# flags remain the brand-native names.
: "${OMGB_E2E_STRUCTURAL:=${OMX_E2E_STRUCTURAL:-0}}"
: "${OMGB_E2E_HEADLESS:=${OMX_E2E_HEADLESS:-0}}"
: "${OMGB_E2E_REAL_OMGB:=${OMX_E2E_REAL:-0}}"
```

- [ ] **Step 3: Verify structural still passes**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-grokbuild && OMX_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh`
Expected: ends with `[OMGB] structural e2e passed`.

- [ ] **Step 4: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add package.json scripts/local/e2e.sh
git commit -m "test: add OMX_E2E_* contract aliases and e2e:real script"
```

### Task 1.3: Emit `e2e-result.json` and the `(tier=...)` marker suffix

**Files:**
- Modify: `oh-my-grokbuild/scripts/local/e2e.sh` (the `log "[OMGB] ... passed"` lines: 383, 521, 531; add a writer fn near `log()` at line 74)

- [ ] **Step 1: Add a result-writer function after `step()` (after line 90)**

```bash
write_result() {
  # args: tier journey passed
  local tier="$1" journey="$2" passed="$3"
  local result_file="$EVIDENCE_DIR/e2e-result.json"
  node -e '
    const [tier, journey, passed, log, marker] = process.argv.slice(1);
    const fs = require("fs");
    fs.writeFileSync(process.env.RESULT_FILE, JSON.stringify({
      tier, host: "grok", journey, passed: passed === "true",
      evidence_paths: [log], marker
    }, null, 2));
  ' "$tier" "$journey" "$passed" "$LOG" "[OMGB] e2e passed (tier=$tier)" \
    RESULT_FILE="$result_file" 2>/dev/null || RESULT_FILE="$result_file" node -e '
    const [tier, journey, passed, log] = process.argv.slice(1);
    require("fs").writeFileSync(process.env.RESULT_FILE, JSON.stringify({
      tier, host:"grok", journey, passed: passed==="true",
      evidence_paths:[log], marker:`[OMGB] e2e passed (tier=${tier})`}, null, 2));
  ' "$tier" "$journey" "$passed" "$LOG"
}
```

- [ ] **Step 2: Update the three terminal markers to include the tier and write the result**

Replace line 383 `  log "[OMGB] structural e2e passed"` with:

```bash
  write_result "structural" "structural payload + fake headless" "true"
  log "[OMGB] structural e2e passed (tier=structural)"
```

Replace line 521 `    log "[OMGB] structural e2e passed (headless skipped)"` with:

```bash
    write_result "structural" "structural payload (headless skipped)" "true"
    log "[OMGB] structural e2e passed (tier=structural)"
```

Replace line 531 `  log "[OMGB] e2e passed"` with:

```bash
  local tier="headless"
  [[ "${OMGB_E2E_REAL_OMGB:-0}" = "1" ]] && tier="real"
  write_result "$tier" "/omgb full run" "true"
  log "[OMGB] e2e passed (tier=$tier)"
```

- [ ] **Step 3: Verify structural emits the result file**

Run:
```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
OMX_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh
cat .omgb/evidence/e2e-result.json
```
Expected: JSON with `"tier": "structural"`, `"passed": true`, and marker `[OMGB] e2e passed (tier=structural)`; console shows `[OMGB] structural e2e passed (tier=structural)`.

- [ ] **Step 4: Update the conformance checker marker expectation**

The structural marker is now `[OMGB] structural e2e passed (tier=structural)`. In `e2e-conformance.mjs` the check uses `includes(\`[${markerPrefix}] structural e2e passed\`)`, which is still a substring — no change needed. Confirm by running the conformance test: `cd /home/zeyufu/Desktop/tools/oh-my-grokbuild && node --test scripts/cross-repo/e2e-conformance.test.mjs` → PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add scripts/local/e2e.sh
git commit -m "test: emit e2e-result.json and tier-tagged pass marker"
```

### Task 1.4: Add the real-in-CI lane (grok auth from secret)

**Files:**
- Modify: `oh-my-grokbuild/.github/workflows/ci.yml` (append a job after `shell-lanes`, line 62)

- [ ] **Step 1: Append the real-tier job**

Append to `oh-my-grokbuild/.github/workflows/ci.yml`:

```yaml
  e2e-real:
    name: real /omgb e2e (gated, consumes Grok quota)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Materialize Grok auth from secret
        env:
          GROK_AUTH_JSON: ${{ secrets.GROK_AUTH_JSON }}
        run: |
          test -n "$GROK_AUTH_JSON" || { echo "GROK_AUTH_JSON secret not set"; exit 1; }
          mkdir -p "$HOME/.grok/bin"
          printf '%s' "$GROK_AUTH_JSON" > "$HOME/.grok/auth.json"
      - name: Install grok CLI
        run: |
          # From the spike output (Task 1.4 step 0): the exact install command for grok.
          # Placeholder for the verified command, e.g. npm i -g @x-ai/grok-cli
          echo "TODO replaced by spike"; exit 1
      - name: Install local payload
        run: scripts/local/install-local.sh --force
      - name: Run real e2e
        timeout-minutes: 10
        run: npm run e2e:real
```

- [ ] **Step 0 (do FIRST — spike): determine the grok CLI install command for CI**

Run locally: `command -v grok; grok --version; cat ~/.grok/bin/grok 2>/dev/null | head; npm ls -g 2>/dev/null | grep -i grok`
Record the exact global install command and replace the `echo "TODO replaced by spike"; exit 1` line in Step 1 with it.

- [ ] **Step 2: Add the secret**

```bash
gh secret set GROK_AUTH_JSON --repo PeterPonyu/oh-my-grokbuild < ~/.grok/auth.json
```
Expected: `✓ Set secret GROK_AUTH_JSON`.

- [ ] **Step 3: Push branch and confirm the lane runs green**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-grokbuild
git add .github/workflows/ci.yml
git commit -m "ci: gate real /omgb e2e on every PR"
git push -u origin HEAD
gh run watch
```
Expected: `e2e-real` job passes; log contains `[OMGB] e2e passed (tier=real)`.

---

## Phase 2 — oh-my-antigravity (standalone CLI; deterministic, no secret)

antigravity's UX is its own binary. Real tier == its own `init → loop → approve → verify-goal` journey, deterministic. Work: consolidate existing partial CLI tests into one gated `scripts/local/e2e.sh`, declare the contract, add the CI real lane (no secret).

### Task 2.0 (spike): Confirm antigravity's CLI entrypoint, brand token, and journey commands

**Files:** read-only

- [ ] **Step 1: Discover the binary name, brand dir, and the exact journey commands**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-antigravity
node -e "const p=require('./package.json'); console.log('bin:', JSON.stringify(p.bin), 'scripts:', JSON.stringify(p.scripts))"
sed -n '1,80p' test/cli.test.ts          # extract the real spawn invocations used today
grep -rEo '\.om[a-z]+/' --include='*.ts' src 2>/dev/null | sort -u   # confirm brand dir (.omag?)
```
Record: the CLI command (e.g. `node dist/cli.js loop --run --json`), the brand token + evidence dir, and the assertions used (ledger path, goal-completion marker). These feed Tasks 2.2–2.3.

### Task 2.1: Declare antigravity's contract

**Files:**
- Create: `oh-my-antigravity/e2e-contract.json`

- [ ] **Step 1: Write the file** (substitute brand/evidenceDir from Task 2.0 if different)

```json
{
  "brand": "OMAG",
  "host": "self",
  "hostClass": "standalone",
  "evidenceDir": ".omag/evidence",
  "journey": "init -> loop --run (clarity gate) -> approve -> verify-goal",
  "markerPrefix": "OMAG",
  "requiresSecret": false,
  "npmScripts": ["e2e:structural", "e2e:headless", "e2e:real", "verify"]
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-antigravity
git checkout -b test/full-ux-e2e
git add e2e-contract.json
git commit -m "test: declare antigravity e2e-contract.json"
```

### Task 2.2: Write the failing journey test (the harness's real-tier assertions)

**Files:**
- Create: `oh-my-antigravity/test/e2e-journey.test.ts`

- [ ] **Step 1: Write the failing test** (fill spawn args + assertions from Task 2.0)

```typescript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// CLI_CMD + JOURNEY come from Task 2.0 spike output.
const CLI = ['node', 'dist/cli.js']; // <- replace with verified entrypoint

function run(home: string, args: string[]) {
  return spawnSync(CLI[0], [...CLI.slice(1), ...args], {
    env: { ...process.env, HOME: home }, cwd: process.cwd(), encoding: 'utf8',
  });
}

test('full user journey: init -> loop -> approve -> verify-goal', () => {
  const home = mkdtempSync(join(tmpdir(), 'omag-e2e-'));
  assert.equal(run(home, ['init']).status, 0, 'init failed');
  const loop = run(home, ['loop', '--run', '--json']);
  assert.equal(loop.status, 0, loop.stderr);
  assert.equal(run(home, ['approve']).status, 0, 'approve failed');
  const verify = run(home, ['verify-goal', '--json']);
  assert.equal(verify.status, 0, verify.stderr);
  // Evidence of completion (from Task 2.0): a ledger file + goal marker.
  const ledger = join(home, '.omag', 'ledger.json'); // <- confirm path in 2.0
  assert.ok(existsSync(ledger), 'ledger not written');
  assert.match(verify.stdout, /"goal_complete"\s*:\s*true/);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-antigravity && node --test test/e2e-journey.test.ts`
Expected: FAIL (entrypoint/paths not yet confirmed, or assertion mismatch). Adjust `CLI`/paths from Task 2.0 until the failure is a *real* assertion, not a wiring error.

### Task 2.3: Create the tiered harness `scripts/local/e2e.sh`

**Files:**
- Create: `oh-my-antigravity/scripts/local/e2e.sh`

- [ ] **Step 1: Write the harness**

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${OMAG_E2E_STRUCTURAL:=${OMX_E2E_STRUCTURAL:-0}}"
: "${OMAG_E2E_REAL:=${OMX_E2E_REAL:-0}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${OMAG_EVIDENCE_DIR:-$ROOT/.omag/evidence}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$EVIDENCE_DIR/e2e-$TS.log"
mkdir -p "$EVIDENCE_DIR"
log() { printf "%s %s\n" "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
fail() { log "FAIL: $*"; log "[OMAG] e2e failed"; exit 1; }

write_result() { # tier journey passed
  node -e 'const[t,j,p,l]=process.argv.slice(1);require("fs").writeFileSync(process.env.RF,JSON.stringify({tier:t,host:"self",journey:j,passed:p==="true",evidence_paths:[l],marker:`[OMAG] e2e passed (tier=${t})`},null,2))' \
    "$1" "$2" "$3" "$LOG" RF="$EVIDENCE_DIR/e2e-result.json"
}

# Structural: build + skill/surface inventory only, no journey.
log "STEP: structural (build + inventory)"
npm run --silent build >>"$LOG" 2>&1 || fail "build failed"
node scripts/validate-surface-inventory.mjs >>"$LOG" 2>&1 || fail "surface inventory failed"
if [[ "$OMAG_E2E_STRUCTURAL" = "1" ]]; then
  write_result "structural" "build+inventory" "true"
  log "[OMAG] structural e2e passed (tier=structural)"
  exit 0
fi

# Real: deterministic full journey via the node:test journey test.
log "STEP: real journey (init->loop->approve->verify-goal)"
node --test test/e2e-journey.test.ts >>"$LOG" 2>&1 || fail "journey test failed"
write_result "real" "init->loop->approve->verify-goal" "true"
log "[OMAG] e2e passed (tier=real)"
```

- [ ] **Step 2: Add npm scripts**

In `oh-my-antigravity/package.json` scripts, add:

```json
    "e2e:structural": "OMAG_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh",
    "e2e:headless": "OMAG_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh",
    "e2e:real": "OMAG_E2E_REAL=1 bash scripts/local/e2e.sh",
    "verify": "npm test && npm run e2e:structural"
```

(For a standalone tool, `headless` == structural: there is no external host to reach.)

- [ ] **Step 3: Run structural then real**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-antigravity
chmod +x scripts/local/e2e.sh
npm run e2e:structural   # expect: [OMAG] structural e2e passed (tier=structural)
npm run e2e:real         # expect: [OMAG] e2e passed (tier=real)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/local/e2e.sh package.json test/e2e-journey.test.ts
git commit -m "test: full deterministic user-journey e2e harness"
```

### Task 2.4: Wire the real lane into CI (no secret)

**Files:**
- Modify: `oh-my-antigravity/.github/workflows/ci.yml`

- [ ] **Step 1: Append the real-tier job**

```yaml
  e2e-real:
    name: full user-journey e2e
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run e2e:real
        timeout-minutes: 10
```

- [ ] **Step 2: Push and confirm green**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-antigravity
git add .github/workflows/ci.yml
git commit -m "ci: gate full user-journey e2e on every PR"
git push -u origin HEAD
gh run watch
```
Expected: `e2e-real` passes; log contains `[OMAG] e2e passed (tier=real)`.

---

## Phase 3 — oh-my-copilot (host-plugin; real model; **new ci.yml**)

Biggest lift. copilot has no test/e2e CI lane and its `examples/e2e-pipeline-run` is a manual README. Work: build `scripts/local/e2e.sh` (structural + headless + real), promote the manual pipeline into the real tier, declare the contract, and create a brand-new `ci.yml` with the fast + real lanes.

### Task 3.0 (spike): Confirm Copilot CLI headless invocation, auth, and transcript layout

**Files:** read-only; uses existing `scripts/smoke-copilot-cli.sh`

- [ ] **Step 1: Capture the verified real invocation**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-copilot
sed -n '1,200p' scripts/smoke-copilot-cli.sh        # the model-backed prompt invocation pattern
copilot --help 2>&1 | sed -n '1,60p'                # headless/prompt/output flags
RUN_COPILOT_AGENT_SMOKE=1 COPILOT_SMOKE_MODEL=gpt-5-mini bash scripts/smoke-copilot-cli.sh --run-agent-prompts 2>&1 | tail -40
ls -la examples/e2e-pipeline-run                     # what the manual runbook expects
```
Record: (a) exact headless prompt flags (the `copilot ... -p`-equivalent), (b) how auth is provided (env token name), (c) where the session transcript is written (path + format) so the harness can assert skill-load evidence, (d) the cheap model id. These feed Tasks 3.2–3.3.

### Task 3.1: Declare copilot's contract

**Files:**
- Create: `oh-my-copilot/e2e-contract.json`

- [ ] **Step 1: Write the file** (substitute brand/host token from Task 3.0)

```json
{
  "brand": "OMCOP",
  "host": "copilot",
  "hostClass": "host-plugin",
  "evidenceDir": ".omcop/evidence",
  "journey": "deep-interview -> ralplan -> autopilot (real model)",
  "markerPrefix": "OMCOP",
  "requiresSecret": true,
  "npmScripts": ["e2e:structural", "e2e:headless", "e2e:real", "verify"]
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-copilot
git checkout -b test/full-ux-e2e
git add e2e-contract.json
git commit -m "test: declare copilot e2e-contract.json"
```

### Task 3.2: Build the tiered harness (structural + headless reuse existing scripts)

**Files:**
- Create: `oh-my-copilot/scripts/local/e2e.sh`

- [ ] **Step 1: Write the harness skeleton wrapping existing scripts**

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${OMCOP_E2E_STRUCTURAL:=${OMX_E2E_STRUCTURAL:-0}}"
: "${OMCOP_E2E_HEADLESS:=${OMX_E2E_HEADLESS:-0}}"
: "${OMCOP_E2E_REAL:=${OMX_E2E_REAL:-0}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${OMCOP_EVIDENCE_DIR:-$ROOT/.omcop/evidence}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$EVIDENCE_DIR/e2e-$TS.log"
mkdir -p "$EVIDENCE_DIR"
log() { printf "%s %s\n" "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
fail() { log "FAIL: $*"; log "[OMCOP] e2e failed"; exit 1; }
write_result() { node -e 'const[t,j,p,l]=process.argv.slice(1);require("fs").writeFileSync(process.env.RF,JSON.stringify({tier:t,host:"copilot",journey:j,passed:p==="true",evidence_paths:[l],marker:`[OMCOP] e2e passed (tier=${t})`},null,2))' "$1" "$2" "$3" "$LOG" RF="$EVIDENCE_DIR/e2e-result.json"; }

# Tier 1 structural: the existing credential-free fixture.
log "STEP: structural"
bash "$ROOT/scripts/validate-structural-e2e.sh" >>"$LOG" 2>&1 || fail "structural fixture failed"
if [[ "$OMCOP_E2E_STRUCTURAL" = "1" ]]; then
  write_result "structural" "structural fixture" "true"
  log "[OMCOP] structural e2e passed (tier=structural)"; exit 0
fi

# Tier 2 headless: CLI presence + command surface (no model).
log "STEP: headless"
bash "$ROOT/scripts/smoke-copilot-cli.sh" >>"$LOG" 2>&1 || fail "copilot CLI smoke failed"
if [[ "$OMCOP_E2E_HEADLESS" = "1" && "$OMCOP_E2E_REAL" != "1" ]]; then
  write_result "headless" "cli smoke" "true"
  log "[OMCOP] e2e passed (tier=headless)"; exit 0
fi

# Tier 3 real: implemented in Task 3.3 (run_real_pipeline).
log "STEP: real pipeline"
run_real_pipeline
write_result "real" "deep-interview->ralplan->autopilot" "true"
log "[OMCOP] e2e passed (tier=real)"
```

- [ ] **Step 2: Add npm scripts**

In `oh-my-copilot/package.json` scripts (create the block if absent):

```json
    "e2e:structural": "OMCOP_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh",
    "e2e:headless": "OMCOP_E2E_HEADLESS=1 bash scripts/local/e2e.sh",
    "e2e:real": "OMCOP_E2E_HEADLESS=1 OMCOP_E2E_REAL=1 bash scripts/local/e2e.sh",
    "verify": "npm test && npm run e2e:structural"
```

- [ ] **Step 3: Verify structural passes (credential-free)**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-copilot && chmod +x scripts/local/e2e.sh && npm run e2e:structural`
Expected: `[OMCOP] structural e2e passed (tier=structural)`.

- [ ] **Step 4: Commit**

```bash
git add scripts/local/e2e.sh package.json
git commit -m "test: tiered e2e harness (structural+headless) for copilot"
```

### Task 3.3: Implement the real pipeline (promote the manual runbook)

**Files:**
- Modify: `oh-my-copilot/scripts/local/e2e.sh` (add `run_real_pipeline` before `main` invocation)

- [ ] **Step 1: Add `run_real_pipeline` using the verified invocation from Task 3.0**

Insert this function near the top of `scripts/local/e2e.sh` (after `write_result`). Replace the `COPILOT_PROMPT_CMD` placeholder with the exact flags captured in Task 3.0:

```bash
run_real_pipeline() {
  local model="${COPILOT_SMOKE_MODEL:-gpt-5-mini}"
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/omcop-real.XXXXXX")"
  local home="$tmp/home" ws="$tmp/ws" sessions="$tmp/home/.copilot/sessions"
  mkdir -p "$home" "$ws"
  (cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$ws"
  # Single combined pipeline prompt; the three skills are exercised in sequence.
  # COPILOT_PROMPT_CMD = verified headless invocation from Task 3.0, e.g.:
  #   copilot --no-color --model "$model" --add-dir "$ws" -p "<prompt>"
  local prompt='/deep-interview then /ralplan then /autopilot for: add a /healthz endpoint. Do not edit files; only confirm each skill loaded. End with the exact marker OMCOP_REAL_OK.'
  local out
  set +e
  out="$(HOME="$home" timeout "${OMCOP_REAL_TIMEOUT:-300}" COPILOT_PROMPT_CMD 2>>"$LOG")"
  local rc=$?
  set -e
  printf '%s\n' "$out" >>"$LOG"
  [[ $rc -eq 0 ]] || { cp -R "$sessions" "$EVIDENCE_DIR/real-sessions-$TS" 2>/dev/null||true; fail "copilot real invocation rc=$rc"; }
  printf '%s\n' "$out" | tail -n1 | grep -qx 'OMCOP_REAL_OK' || fail "missing final marker OMCOP_REAL_OK"
  # Skill-load evidence (path/format from Task 3.0): each skill name must appear in the transcript.
  for skill in deep-interview ralplan autopilot; do
    grep -R -q "$skill" "$sessions" 2>/dev/null || { cp -R "$sessions" "$EVIDENCE_DIR/real-sessions-$TS" 2>/dev/null||true; fail "transcript lacks $skill skill evidence"; }
  done
  rm -rf "$tmp"
  log "OK: real pipeline produced OMCOP_REAL_OK with deep-interview/ralplan/autopilot transcript evidence"
}
```

- [ ] **Step 2: Run the real tier locally (consumes quota)**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-copilot && RUN_COPILOT_AGENT_SMOKE=1 npm run e2e:real`
Expected: `[OMCOP] e2e passed (tier=real)` and `.omcop/evidence/e2e-result.json` with `"tier":"real"`.

- [ ] **Step 3: Commit**

```bash
git add scripts/local/e2e.sh
git commit -m "test: real deep-interview->ralplan->autopilot pipeline e2e"
```

### Task 3.4: Create copilot's CI (`ci.yml`) with fast + real lanes

**Files:**
- Create: `oh-my-copilot/.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow** (use the auth env name verified in Task 3.0)

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  fast:
    name: structural + headless (no secrets)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run e2e:structural
  e2e-real:
    name: real pipeline e2e (consumes model quota)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - name: Install + auth Copilot CLI
        env:
          COPILOT_TOKEN: ${{ secrets.COPILOT_TOKEN }}
        run: |
          test -n "$COPILOT_TOKEN" || { echo "COPILOT_TOKEN not set"; exit 1; }
          # Install + auth command from Task 3.0 spike output.
          echo "TODO replaced by spike"; exit 1
      - name: Run real e2e
        timeout-minutes: 12
        env:
          RUN_COPILOT_AGENT_SMOKE: '1'
          COPILOT_SMOKE_MODEL: gpt-5-mini
        run: npm run e2e:real
```

- [ ] **Step 2: Add the secret**

```bash
gh secret set COPILOT_TOKEN --repo PeterPonyu/oh-my-copilot
```

- [ ] **Step 3: Replace the install/auth TODO with the spike command, push, confirm green**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-copilot
git add .github/workflows/ci.yml
git commit -m "ci: add CI with structural fast lane and gated real pipeline e2e"
git push -u origin HEAD
gh run watch
```
Expected: both jobs pass; real job log contains `[OMCOP] e2e passed (tier=real)`.

---

## Phase 4 — oh-my-cursor (host-plugin; cursor-agent + bridge MCP)

Work: upgrade the synthetic structural fixture into a real journey over `cursor-agent` with the cursor-state-bridge MCP live, declare the contract, add the real CI lane. cursor already has `node-ts-ci.yml` and `npm run verify:e2e`.

### Task 4.0 (spike): Confirm cursor-agent headless invocation, auth, bridge MCP, and workflow-state evidence

**Files:** read-only; uses `scripts/test-plugin-on-cursor-cli.ts`, `scripts/validate-structural-e2e.sh`

- [ ] **Step 1: Capture the verified real invocation**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-cursor
sed -n '1,200p' scripts/test-plugin-on-cursor-cli.ts   # the cursor-agent invocation it already uses
cursor-agent --help 2>&1 | sed -n '1,60p'              # headless/print/output + MCP flags
grep -rEn 'workflow-state|state\.json|phase' mcp/cursor-state-bridge 2>/dev/null | head
```
Record: (a) headless invocation flags for cursor-agent, (b) auth env token name, (c) how the bridge MCP is started + the workflow-state file path the harness asserts transitions on, (d) cheap model id. These feed Tasks 4.2–4.3.

### Task 4.1: Declare cursor's contract

**Files:**
- Create: `oh-my-cursor/e2e-contract.json`

- [ ] **Step 1: Write the file**

```json
{
  "brand": "OMCUR",
  "host": "cursor-agent",
  "hostClass": "host-plugin",
  "evidenceDir": ".omcur/evidence",
  "journey": "intake -> research -> plan -> execute -> verify -> review (real model)",
  "markerPrefix": "OMCUR",
  "requiresSecret": true,
  "npmScripts": ["e2e:structural", "e2e:headless", "e2e:real", "verify"]
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/zeyufu/Desktop/tools/oh-my-cursor
git checkout -b test/full-ux-e2e
git add e2e-contract.json
git commit -m "test: declare cursor e2e-contract.json"
```

### Task 4.2: Build the tiered harness (structural reuses existing fixture)

**Files:**
- Create: `oh-my-cursor/scripts/local/e2e.sh`

- [ ] **Step 1: Write the harness skeleton**

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${OMCUR_E2E_STRUCTURAL:=${OMX_E2E_STRUCTURAL:-0}}"
: "${OMCUR_E2E_HEADLESS:=${OMX_E2E_HEADLESS:-0}}"
: "${OMCUR_E2E_REAL:=${OMX_E2E_REAL:-0}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${OMCUR_EVIDENCE_DIR:-$ROOT/.omcur/evidence}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$EVIDENCE_DIR/e2e-$TS.log"
mkdir -p "$EVIDENCE_DIR"
log() { printf "%s %s\n" "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
fail() { log "FAIL: $*"; log "[OMCUR] e2e failed"; exit 1; }
write_result() { node -e 'const[t,j,p,l]=process.argv.slice(1);require("fs").writeFileSync(process.env.RF,JSON.stringify({tier:t,host:"cursor-agent",journey:j,passed:p==="true",evidence_paths:[l],marker:`[OMCUR] e2e passed (tier=${t})`},null,2))' "$1" "$2" "$3" "$LOG" RF="$EVIDENCE_DIR/e2e-result.json"; }

log "STEP: structural"
bash "$ROOT/scripts/validate-structural-e2e.sh" >>"$LOG" 2>&1 || fail "structural fixture failed"
if [[ "$OMCUR_E2E_STRUCTURAL" = "1" ]]; then
  write_result "structural" "structural fixture" "true"
  log "[OMCUR] structural e2e passed (tier=structural)"; exit 0
fi

log "STEP: headless"
node --experimental-strip-types scripts/test-plugin-on-cursor-cli.ts >>"$LOG" 2>&1 || fail "cursor-agent compat failed"
if [[ "$OMCUR_E2E_HEADLESS" = "1" && "$OMCUR_E2E_REAL" != "1" ]]; then
  write_result "headless" "cursor-agent compat" "true"
  log "[OMCUR] e2e passed (tier=headless)"; exit 0
fi

log "STEP: real journey"
run_real_journey
write_result "real" "intake->research->plan->execute->verify->review" "true"
log "[OMCUR] e2e passed (tier=real)"
```

- [ ] **Step 2: Add npm scripts**

In `oh-my-cursor/package.json` scripts, add/normalize:

```json
    "e2e:structural": "OMCUR_E2E_STRUCTURAL=1 bash scripts/local/e2e.sh",
    "e2e:headless": "OMCUR_E2E_HEADLESS=1 bash scripts/local/e2e.sh",
    "e2e:real": "OMCUR_E2E_HEADLESS=1 OMCUR_E2E_REAL=1 bash scripts/local/e2e.sh",
    "verify": "npm test && npm run e2e:structural"
```

- [ ] **Step 3: Verify structural passes**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-cursor && chmod +x scripts/local/e2e.sh && npm run e2e:structural`
Expected: `[OMCUR] structural e2e passed (tier=structural)`.

- [ ] **Step 4: Commit**

```bash
git add scripts/local/e2e.sh package.json
git commit -m "test: tiered e2e harness (structural+headless) for cursor"
```

### Task 4.3: Implement the real journey over cursor-agent + bridge MCP

**Files:**
- Modify: `oh-my-cursor/scripts/local/e2e.sh` (add `run_real_journey`)

- [ ] **Step 1: Add `run_real_journey` using Task 4.0 outputs**

Insert near the top of `scripts/local/e2e.sh` (after `write_result`). Replace `CURSOR_AGENT_CMD` and `STATE_FILE` with the spike-verified values:

```bash
run_real_journey() {
  local model="${CURSOR_E2E_MODEL:-auto}"
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/omcur-real.XXXXXX")"
  local home="$tmp/home" ws="$tmp/ws"
  mkdir -p "$home" "$ws"
  (cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$ws"
  # STATE_FILE = the workflow-state path the bridge MCP writes (from Task 4.0).
  local STATE_FILE="$ws/.cursor/workflow-state.json"
  local prompt='@auto-execute drive intake->research->plan->execute->verify->review for: add a /healthz endpoint. Do not edit files; confirm each phase transition. End with the exact marker OMCUR_REAL_OK.'
  local out
  set +e
  # CURSOR_AGENT_CMD = verified headless invocation with bridge MCP enabled (Task 4.0).
  out="$(HOME="$home" timeout "${OMCUR_REAL_TIMEOUT:-300}" CURSOR_AGENT_CMD 2>>"$LOG")"
  local rc=$?
  set -e
  printf '%s\n' "$out" >>"$LOG"
  [[ $rc -eq 0 ]] || fail "cursor-agent real invocation rc=$rc"
  printf '%s\n' "$out" | tail -n1 | grep -qx 'OMCUR_REAL_OK' || fail "missing final marker OMCUR_REAL_OK"
  # Evidence: the bridge recorded phase transitions through the full lifecycle.
  test -f "$STATE_FILE" || fail "workflow-state file not written by bridge MCP"
  for phase in intake research plan execute verify review; do
    grep -q "$phase" "$STATE_FILE" || fail "workflow-state missing phase: $phase"
  done
  rm -rf "$tmp"
  log "OK: real journey reached review with all phase transitions recorded"
}
```

- [ ] **Step 2: Run the real tier locally (consumes quota)**

Run: `cd /home/zeyufu/Desktop/tools/oh-my-cursor && npm run e2e:real`
Expected: `[OMCUR] e2e passed (tier=real)`.

- [ ] **Step 3: Commit**

```bash
git add scripts/local/e2e.sh
git commit -m "test: real intake->...->review journey e2e over cursor-agent"
```

### Task 4.4: Add the real lane to cursor CI

**Files:**
- Modify: `oh-my-cursor/.github/workflows/node-ts-ci.yml`

- [ ] **Step 1: Append the real-tier job** (auth env from Task 4.0)

```yaml
  e2e-real:
    name: real journey e2e (consumes model quota)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - name: Install + auth cursor-agent
        env:
          CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
        run: |
          test -n "$CURSOR_API_KEY" || { echo "CURSOR_API_KEY not set"; exit 1; }
          echo "TODO replaced by spike"; exit 1
      - name: Run real e2e
        timeout-minutes: 12
        run: npm run e2e:real
```

- [ ] **Step 2: Add secret, replace TODO with spike command, push, confirm green**

```bash
gh secret set CURSOR_API_KEY --repo PeterPonyu/oh-my-cursor
cd /home/zeyufu/Desktop/tools/oh-my-cursor
git add .github/workflows/node-ts-ci.yml
git commit -m "ci: gate real journey e2e on every PR"
git push -u origin HEAD
gh run watch
```
Expected: `e2e-real` passes; log contains `[OMCUR] e2e passed (tier=real)`.

---

## Phase 5 — Cross-repo conformance gate

Prove all four repos are FULL.

### Task 5.1: Run the conformance checker across all four repos

**Files:** none (verification)

- [ ] **Step 1: Run structural conformance for all four**

```bash
cd /home/zeyufu/Desktop/tools
node oh-my-grokbuild/scripts/cross-repo/e2e-conformance.mjs \
  oh-my-antigravity oh-my-copilot oh-my-cursor oh-my-grokbuild
```
Expected output ends with: `Conformance: 4/4 repos FULL` and exit code 0.

- [ ] **Step 2: Confirm every repo's CI real lane is green on its PR**

```bash
for r in oh-my-antigravity oh-my-copilot oh-my-cursor oh-my-grokbuild; do
  echo "== $r =="; gh run list --repo PeterPonyu/$r --branch test/full-ux-e2e --limit 1 2>/dev/null \
    || gh run list --repo PeterPonyu/$r --branch docs/full-ux-e2e-design --limit 1
done
```
Expected: latest run per repo is `completed / success` with the `e2e-real` job present.

- [ ] **Step 3: Write the final FULL report**

Create `oh-my-grokbuild/docs/superpowers/plans/2026-06-03-full-ux-e2e-RESULTS.md` summarizing per-repo: tier markers observed, CI run URLs, and the `4/4 FULL` conformance line. Commit it.

---

## Self-Review

**Spec coverage:** §1 FULL bar → conformance checker (0.2–0.3) + per-repo real tiers. §2 two host classes → antigravity standalone (Phase 2, no secret) vs plugin repos (Phases 1/3/4, secrets). §3.1 contract (tiers, env flags, npm scripts, evidence, marker, isolation) → Task 0.1 doc + enforced by 0.3 + implemented per repo. §3.2 per-repo journeys → Tasks 2.2/3.3/4.3 with the exact journeys from the table. §4 real-in-CI every PR + cost controls → CI jobs (1.4/2.4/3.4/4.4) with `concurrency.cancel-in-progress`, pinned cheap models, single journey, timeouts. §5 conformance + rollout order → Phases 0→1→(2,3,4)→5. §5.3 risks → spike-first tasks (2.0/3.0/4.0/1.4-step0) and evidence-based (not exit-code) assertions.

**Placeholder scan:** The only deferred values are host CLI install/invocation commands, which are explicitly produced by the named spike task in each phase before the dependent step runs, and `echo "TODO replaced by spike"; exit 1` lines that *fail closed* until replaced (not silent). No "add error handling"/"write tests for the above"/"similar to Task N" placeholders.

**Type consistency:** `checkRepoConformance(repoDir, opts)` signature, `e2e-contract.json` keys (`brand/host/hostClass/evidenceDir/journey/markerPrefix/requiresSecret/npmScripts`), the result schema (`{tier,host,journey,passed,evidence_paths,marker}`), and marker grammar `[<BRAND>] e2e passed (tier=<tier>)` / `[<BRAND>] structural e2e passed (tier=structural)` are used identically across the checker, the contract doc, and all four harnesses.
