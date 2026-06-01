# Runtime Audit Fixments

This note records the operational issues found during the OMGB runtime audit and
the standing routine that prevents recurrence. It is intentionally evidence-led:
what failed, why it mattered, how it is fixed, and what future maintainers should
check before trusting a run.

## 1. User skill vs enabled plugin listing

- **What:** `grok inspect` showed `omgb` as a `user` skill, while
  `oh-my-grokbuild` did not appear in the enabled plugin list.
- **Why:** Today `/omgb` is made invocable by the managed user-skill mount at
  `~/.grok/skills/omgb`; the copied payload at
  `~/.grok/plugins/local/oh-my-grokbuild` is the portable plugin bundle, but this
  Grok version may not list that local payload as an enabled plugin.
- **How fixed:** Doctor and e2e now say explicitly that the runtime contract is
  the user-skill mount and that the local plugin payload may not appear as an
  enabled plugin.
- **Evidence:** `grok inspect` must list `omgb user`; doctor must report the
  mount points at the current checkout; local payload must match
  `local-payload.txt`.
- **Future design:** Keep `/omgb` as the single user-invocable surface until xAI
  publishes a stable plugin manifest/discovery contract. If Grok later starts
  listing local payloads as enabled plugins, add that as an additional check, not
  as a replacement for the user-skill mount check.
- **Routine:** After install or repo relocation, run
  `scripts/local/install-local.sh --force`, then `scripts/local/doctor.sh`, then
  reload Grok and verify `/skills` or `grok inspect` lists `omgb user`.

## 2. E2E audit wording overstated proof

- **What:** e2e created temporary dry-run probe dirs, then `--audit-all` could
  report `0 runs ok, 2 skipped` while the e2e log still said completed runs
  passed.
- **Why:** The e2e harness sets `OMGB_RUNS_ROOT` to a temporary probe root for
  hermetic launcher checks. That is correct for probes, but misleading for an
  "existing runs" audit.
- **How fixed:** e2e now has `audit_canonical_runs`, which explicitly audits
  `~/.grok/omgb/runs` and logs that skipped incomplete probe dirs are listed in
  the evidence log. The pass wording no longer claims more than the audit proves.
- **Evidence:** The e2e log should contain `canonical run archive audit
  (informational)`, followed by `canonical completed runs pass...` or an
  informational warning with the log path; with `OMGB_E2E_STRICT_AUDIT=1`, audit findings fail e2e for release gating.
- **Future design:** Keep probe-root checks and archive checks separate. Probe
  checks prove launcher structure; archive checks prove historical run evidence.
- **Routine:** Before trusting an OMGB run, prefer explicit
  `node scripts/ci/validate.mjs --audit-run <slug>` over bulk `--audit-all`.

## 3. Incomplete probe dirs and explicit audit behavior

- **What:** Bulk audit skipped dry-run/probe dirs with no `state.json`; explicit
  audit of the same slug correctly blocked.
- **Why:** Bulk audit is a sweep across mixed archives and intentionally skips
  incomplete probe dirs. Explicit audit is a gate for one claimed run and must be
  strict.
- **How fixed:** No semantic change to the auditor: the distinction is correct.
  The fix is clearer e2e wording and routine guidance so skipped probe dirs are
  not mistaken for completed, trusted runs.
- **Evidence:** `--audit-all` may print `audit skip`; `--audit-run <slug>` must
  block if `state.json` is missing.
- **Future design:** If a run directory is meant to be durable evidence, it must
  contain `mission.md`, `state.json`, `tasks.json`, `evidence.md`, `review.md`,
  and any relevant `fanout-trace.json`.
- **Routine:** Treat skipped dirs as non-runs. Clean or ignore them unless they
  are useful dry-run artifacts.

## 4. Team launcher dry-run command drift

- **What:** The actual team launcher used `--permission-mode auto`, but the
  printed dry-run command omitted it.
- **Why:** Users copy the dry-run command. If it differs from `--launch`, the
  manual path can degrade into serial permission prompts and different runtime
  behavior.
- **How fixed:** The printed dry-run command now includes `--permission-mode
  auto` to match the executed command path.
- **Evidence:** `scripts/workflow/launch-omgb-team.sh <slug> "task"` prints a
  copy/paste command containing `--permission-mode auto`.
- **Future design:** Any flag added to the real launch command must be reflected
  in dry-run output or the validator should fail.
- **Routine:** For launch changes, test both dry-run and `--launch` command
  construction; do not let docs become a second source of truth.

## 5. Stale repo-local symlinks to temporary probe roots

- **What:** Doctor/e2e launcher dry-runs created repo-local
  `.grok/omgb/runs/<probe>` symlinks pointing at temporary directories that were
  later deleted.
- **Why:** The launcher links repo-local run paths to canonical run roots so the
  auditor can see the same artifacts. For temporary probe roots, leaving the link
  behind creates confusing broken artifact pointers.
- **How fixed:** Doctor and e2e cleanup traps now remove only symlinks whose
  targets are inside the current probe temp root before deleting that root; stale broken links to prior temp probe roots are cleaned without removing live links owned by another running probe.
- **Evidence:** After running doctor/e2e, repo-local `.grok/omgb/runs` should not
  retain links to the just-deleted `/tmp/omgb-*` probe directory.
- **Future design:** Durable run symlinks may continue to point to
  `~/.grok/omgb/runs/<slug>`; temporary probe symlinks must be cleaned by the
  caller that created the temp root.
- **Routine:** If artifact inspection looks odd, run
  `find .grok/omgb/runs -maxdepth 1 -xtype l -print` to find broken local links.

## 6. Host-level errors in live e2e logs

- **What:** Full headless e2e can pass while Grok logs unrelated host errors such
  as file-watch limits or third-party MCP auth failures.
- **Why:** The headless probe checks Grok reachability and the expected token;
  it does not guarantee every unrelated enabled plugin/MCP in the user's global
  Grok environment is healthy.
- **How fixed:** No OMGB-core behavior changed. The evidence boundary is now
  explicit: these are environment risks, not `/omgb` installation failures.
- **Evidence:** `[OMGB] e2e passed` proves the probe token returned with exit 0;
  separate error lines in the log should be classified by source before being
  assigned to OMGB.
- **Future design:** Keep OMGB e2e focused on OMGB contracts. Add separate
  environment doctor checks only when a host-level issue directly breaks `/omgb`.
- **Routine:** For noisy live logs, separate `grok inspect`, OMGB pass markers,
  and third-party MCP errors before deciding what failed.
