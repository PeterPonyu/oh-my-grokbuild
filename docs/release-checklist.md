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
- [ ] `scripts/local/doctor.sh` reports the user-skill mount points at this checkout and explains user-skill vs local-plugin-payload discovery clearly.
- [ ] If the checkout moved, `docs/REPO-RELOCATION-TEST.md` has been followed or explicitly deemed not applicable.
- [ ] `scripts/local/verify-robust-install.sh` validates payload, symlinks, and drift detection where the local Grok environment is available.

## Runtime gates

- [ ] `OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh` passes for structural verification.
- [ ] `OMGB_E2E_HEADLESS=1 OMGB_E2E_STRICT_AUDIT=1 scripts/local/e2e.sh` passes before a full release when a credentialed Grok session is available.
- [ ] At least one representative completed run passes `node scripts/ci/validate.mjs --audit-run <slug>`; do not count `--audit-all` skipped probe dirs as completed evidence.

## Expansion guard

Do not add a new default invocable skill, command, hook, MCP server, daemon, or dependency without a decision record explaining the failing evidence that requires expansion and the validation change that keeps it bounded.

## Runtime audit routine

- [ ] `scripts/workflow/launch-omgb-team.sh <slug> "task"` dry-run prints the same safety-critical flags as `--launch`, including `--permission-mode auto`.
- [ ] Running doctor/e2e does not leave repo-local `.grok/omgb/runs/*` symlinks pointing at deleted `/tmp/omgb-*` probe roots.
- [ ] Review `docs/RUNTIME-AUDIT-FIXMENTS.md` before changing install, doctor, e2e, launcher, or audit behavior.
