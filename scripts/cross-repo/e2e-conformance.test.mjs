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

test('passes when runStructural is true and the structural run prints the marker', () => {
  const scripts = {
    ...VALID_SCRIPTS,
    'e2e:structural': "node -e \"console.log('[OMGB] structural e2e passed')\"",
  };
  const dir = makeRepo({ contract: VALID_CONTRACT, scripts });
  const r = checkRepoConformance(dir, { runStructural: true });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, true, JSON.stringify(r.failures));
});

test('fails when runStructural is true and the structural run exits non-zero', () => {
  const scripts = {
    ...VALID_SCRIPTS,
    'e2e:structural': 'node -e "process.exit(1)"',
  };
  const dir = makeRepo({ contract: VALID_CONTRACT, scripts });
  const r = checkRepoConformance(dir, { runStructural: true });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, false);
  assert.ok(r.failures.some((f) => f.includes('e2e:structural failed')));
});

test('fails when e2e-contract.json is not valid JSON', () => {
  const dir = mkdtempSync(join(tmpdir(), 'e2e-conf-'));
  writeFileSync(join(dir, 'e2e-contract.json'), '{bad json');
  writeFileSync(join(dir, 'package.json'), JSON.stringify({ name: 'x', scripts: VALID_SCRIPTS }));
  mkdirSync(join(dir, 'scripts', 'local'), { recursive: true });
  writeFileSync(join(dir, 'scripts', 'local', 'e2e.sh'), '#!/usr/bin/env bash\n');
  const r = checkRepoConformance(dir, { runStructural: false });
  rmSync(dir, { recursive: true, force: true });
  assert.equal(r.passed, false);
  assert.ok(r.failures.some((f) => f.includes('e2e-contract.json is not valid JSON')));
});
