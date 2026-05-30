# Release Readiness Checklist

Use this checklist before tagging or sharing an `oh-my-grokbuild` release candidate. It preserves the `/omgb`-only default surface while making install and drift evidence repeatable.

## Static gates

- [ ] `node scripts/ci/validate.mjs --smoke` prints `[OMGB] smoke passed`.
- [ ] `node scripts/ci/validate.mjs --sanity` prints `[OMGB] sanity passed`.
- [ ] `npm test` passes.
- [ ] `docs/surface-inventory.json` still lists `/omgb` as the only `default` + `user_invocable` surface.
- [ ] `docs/LINEAGE.md` still states non-copying lineage and Grok Build host boundaries.

## Install and drift gates

- [ ] `scripts/local/install-local.sh --force` records a fresh `.omgb/evidence/install-*.log`.
- [ ] `scripts/local/doctor.sh` reports the user-skill mount points at this checkout.
- [ ] If the checkout moved, `docs/REPO-RELOCATION-TEST.md` has been followed or explicitly deemed not applicable.
- [ ] `scripts/local/verify-robust-install.sh` validates payload, symlinks, and drift detection where the local Grok environment is available.

## Runtime gates

- [ ] `OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh` passes for structural verification.
- [ ] `OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh` passes before a full release when a credentialed Grok session is available.
- [ ] At least one representative completed run passes `node scripts/ci/validate.mjs --audit-run <slug>`.

## Expansion guard

Do not add a new default invocable skill, command, hook, MCP server, daemon, or dependency without a decision record explaining the failing evidence that requires expansion and the validation change that keeps it bounded.
