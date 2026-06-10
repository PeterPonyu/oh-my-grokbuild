# Known Issue: Unpinned grok CLI installer in CI

**Status:** Open  
**Tracking:** Committed as a follow-up in `b3e670d`; no issue filed yet.  
**Affected file:** `.github/workflows/ci.yml`, `shell-lanes` job, "Install grok CLI" step  

## Problem

The `shell-lanes` CI job installs the grok CLI via:

```yaml
- name: Install grok CLI
  run: |
    # UNPINNED — see this file for details
    curl -fsSL https://x.ai/cli/install.sh | bash
```

This pattern has two supply-chain risks:

1. **No version pin.** The install script always fetches the latest release.
   A breaking upstream change will silently change the version under test,
   potentially causing false-green or false-red CI results.

2. **No checksum verification.** The install script is piped directly into
   `bash` over HTTPS without verifying a SHA-256 or GPG signature. A
   compromised CDN or DNS spoofing could execute arbitrary code on the runner.

## Why it is not fixed yet

The xAI grok CLI installer (`https://x.ai/cli/install.sh`) does not currently
expose a versioned download URL or a published checksum file. Pinning is not
possible without one of:

- A versioned artifact URL (e.g. `https://x.ai/cli/releases/v1.2.3/grok-linux-amd64`)
- A checksum manifest signed by xAI
- A package registry entry (e.g. `npm install -g @xai/grok@1.2.3`)

Until xAI provides one of the above, the piped-install pattern is the only
supported mechanism.

## Mitigation in place

- The `shell-lanes` job runs with `persist-credentials: false` and
  `permissions: contents: read` (least-privilege), limiting blast radius.
- The job uses a temporary `$RUNNER_TEMP/omgb-home` to avoid polluting the
  default `$HOME`.
- The `e2e-real` job is **fail-closed**: it requires `GROK_AUTH_JSON` and
  does not install grok via the unpinned script (it expects grok to already
  be on PATH or fails with an explicit message).

## Remediation plan

When xAI publishes a stable versioned artifact or checksum:

1. Replace the `curl | bash` with a pinned download + verification step.
2. Update this document to reflect the pinned version.
3. Add a `# PINNED:` comment at the CI step and close this issue.

## References

- CI workflow: `.github/workflows/ci.yml` (shell-lanes job, "Install grok CLI" step)
- Commit that acknowledged this gap: `b3e670d` ("grok installer not arg-pinnable; pin tracked as a follow-up issue")
