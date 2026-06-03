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
