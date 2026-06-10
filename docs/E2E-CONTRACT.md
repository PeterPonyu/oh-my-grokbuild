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

## Required env flags
Each repo uses its own brand-prefixed canonical flags. Cross-repo `OMX_E2E_*`
names are **aliases** only — they are accepted as fallbacks when the brand flag
is unset, not as the primary names.

| Canonical (brand-native) | Cross-repo alias |
|---|---|
| `OMGB_E2E_STRUCTURAL=1` | `OMX_E2E_STRUCTURAL=1` |
| `OMGB_E2E_HEADLESS=1` | `OMX_E2E_HEADLESS=1` |
| `OMGB_E2E_REAL_OMGB=1` | `OMX_E2E_REAL=1` |

In `scripts/local/e2e.sh` the resolution order is (bash parameter expansion):
```
: "${OMGB_E2E_STRUCTURAL:=${OMX_E2E_STRUCTURAL:-0}}"
```
i.e. `OMGB_*` wins if set, `OMX_*` is the fallback. Set the brand-native flag
in scripts and documentation; the `OMX_*` aliases exist for the cross-repo
conformance harness only.

## Required artifacts (real tier)
- A log at `<evidenceDir>/e2e-<UTC>.log`
- A machine-readable `<evidenceDir>/e2e-result.json`:
  `{ "tier", "host", "journey", "passed", "evidence_paths": [], "marker" }`
- A grep-able pass marker line: `[<BRAND>] e2e passed (tier=<tier>)`

## Required repo declaration
- `e2e-contract.json` at repo root declaring brand/host/journey (schema in e2e-conformance.mjs).

## Isolation (real tier)
- mktemp HOME + workspace copy; read-only host tools where supported; clean up created run dirs.
