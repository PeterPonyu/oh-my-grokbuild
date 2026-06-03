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
