# Known Issue: grok CLI installer pinning in CI

**Status:** mitigated in CI — the shell lane downloads a fixed Grok CLI artifact and verifies SHA-256.
**Tracking:** opened as security review follow-up issue #64.
**Affected file:** `.github/workflows/ci.yml`, `shell-lanes` job, "Install pinned grok CLI" step

## What the workflow does now

The `shell-lanes` CI job no longer executes the mutable installer script from
`https://x.ai/cli/install.sh`. Instead, it downloads the pinned Linux x86_64
artifact directly and verifies the expected SHA-256 before adding `grok` to
`PATH`.

Current CI pin:

```yaml
GROK_CLI_VERSION: "0.2.51"
GROK_CLI_SHA256: "52916267aa2f7868c23a6dd7847dfe066e39a52b8ffd216380186397ea7d0075"
```

This keeps the credential-free shell lane reproducible and removes live
`curl | bash` execution from PR/push workflows.

## Remaining supply-chain considerations

| Risk | Current control |
|---|---|
| Silent upstream upgrades | The workflow pins `GROK_CLI_VERSION`; CI keeps using that artifact until the pin changes. |
| Artifact tampering or CDN drift | `sha256sum -c -` verifies the downloaded binary before execution. |
| Mutable installer script execution | CI does not execute `https://x.ai/cli/install.sh`; it downloads the versioned artifact directly. |
| Intentional upgrades | Maintainers must update both the version and checksum in one PR, then rerun shell-lanes. |

## How to update the pin

1. Check the intended stable version, for example `curl -fsSL https://x.ai/cli/stable`.
2. Download `https://x.ai/cli/grok-<version>-linux-x86_64` and compute `sha256sum`.
3. Update `GROK_CLI_VERSION` and `GROK_CLI_SHA256` together in `.github/workflows/ci.yml`.
4. Run `npm test` and the credential-free shell lane or `npm run e2e:structural`.

Do not reintroduce `curl -fsSL https://x.ai/cli/install.sh | bash` in CI; doing
so would restore mutable remote-code execution on every workflow run.
