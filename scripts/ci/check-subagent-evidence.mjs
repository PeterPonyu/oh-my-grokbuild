// scripts/ci/check-subagent-evidence.mjs
//
// Audit a completed OMGB run for real subagent spawn evidence.
//
// Usage:
//   node scripts/ci/check-subagent-evidence.mjs <task-slug>
//   node scripts/ci/check-subagent-evidence.mjs --all
//
// Exits non-zero with `[OMGB] audit blocked` if any active role lacks a
// `## Subagent: <role>` block in evidence.md, or if a block claims
// spawn_method=unavailable without an OMGB_ALLOW_SYNTHESIS opt-in in
// mission.md plus a Synthesis Justification line.
//
// Exits 0 with `[OMGB] audit passed` when:
//   - Every activeRole in state.json has at least one Subagent block, and
//   - Every reviewer verdict in review.md has a matching Subagent block, and
//   - Any spawn_method:unavailable block is paired with a synthesis opt-in.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../..", import.meta.url))
const runsRoot = path.join(root, ".grok", "omgb", "runs")

const ALLOWED_SPAWN_METHODS = new Set([
  "agents-json",
  "agent-flag",
  "task-tool",
  "unavailable",
])

const REVIEWER_ROLES = new Set([
  "code-reviewer",
  "security-reviewer",
  "performance-reviewer",
  "ux-reviewer",
  "verifier",
])

function readText(p) {
  return readFileSync(p, "utf8")
}

function readJsonSafe(p) {
  try {
    return JSON.parse(readText(p))
  } catch {
    return null
  }
}

function findSubagentBlocks(evidenceText) {
  const blocks = []
  const re = /^## Subagent:\s*([a-z-]+)(?:\s*\(task=([^)]+)\))?\s*$/gm
  let match
  while ((match = re.exec(evidenceText)) !== null) {
    const role = match[1]
    const task = match[2] || null
    const start = match.index
    re.lastIndex = match.index + match[0].length
    const nextSection = evidenceText.slice(re.lastIndex).search(/^## /m)
    const end = nextSection === -1 ? evidenceText.length : re.lastIndex + nextSection
    const body = evidenceText.slice(start, end)

    const methodMatch = body.match(/^- *spawn_method:\s*([a-z-]+)/m)
    const justifMatch = body.match(/^- *Synthesis Justification:\s*(.+)$/m)
    const phaseMatch = body.match(/^- *phase:\s*([a-z-]+)/m)
    const cohortMatch = body.match(/^- *cohort:\s*([A-Za-z0-9_-]+)/m)
    const serialReasonMatch = body.match(/^- *serial_reason:\s*(.+)$/m)
    const startedMatch = body.match(/^- *started:\s*(\S+)/m)
    const workerMarker = body.includes(`### WORKER START ${role}`) && body.includes(`### WORKER END ${role}`)

    blocks.push({
      role,
      task,
      spawn_method: methodMatch ? methodMatch[1] : null,
      phase: phaseMatch ? phaseMatch[1] : null,
      cohort: cohortMatch ? cohortMatch[1] : null,
      serial_reason: serialReasonMatch ? serialReasonMatch[1].trim() : null,
      started: startedMatch ? startedMatch[1] : null,
      has_worker_marker: workerMarker,
      has_synthesis_justification: !!justifMatch,
    })
  }
  return blocks
}

const MANDATORY_PARALLEL_PHASES = {
  grounding: new Set(["codebase-scout", "researcher"]),
  review: new Set(["code-reviewer", "security-reviewer", "performance-reviewer", "ux-reviewer"]),
}

function parseIsoMs(s) {
  if (!s) return null
  const t = Date.parse(s)
  return Number.isNaN(t) ? null : t
}

function checkConcurrencyFindings(blocks) {
  const findings = []
  for (const [phase, expectedSet] of Object.entries(MANDATORY_PARALLEL_PHASES)) {
    const phaseBlocks = blocks.filter((b) => b.phase === phase && expectedSet.has(b.role))
    if (phaseBlocks.length < 2) continue

    const cohorts = new Map()
    for (const b of phaseBlocks) {
      if (!b.cohort) {
        findings.push({
          severity: "high",
          role: b.role,
          message: `phase=${phase} requires a 'cohort:' id on '${b.role}' (mandatory-parallel phase)`,
        })
        continue
      }
      if (!cohorts.has(b.cohort)) cohorts.set(b.cohort, [])
      cohorts.get(b.cohort).push(b)
    }

    const sharedCohorts = [...cohorts.values()].filter((arr) => arr.length >= 2)
    if (sharedCohorts.length === 0) {
      const allSerialByDesign = phaseBlocks.every(
        (b) => b.cohort === "serial-by-design" && b.serial_reason,
      )
      if (allSerialByDesign) continue
      findings.push({
        severity: "high",
        role: phaseBlocks.map((b) => b.role).join("+"),
        message: `phase=${phase} ran serially: ${phaseBlocks
          .map((b) => `${b.role}@${b.cohort || "no-cohort"}`)
          .join(", ")} (mandatory-parallel phase; emit all spawn_subagent calls in one assistant turn and share a cohort id, or set cohort=serial-by-design with a serial_reason)`,
      })
      continue
    }

    for (const cohortBlocks of sharedCohorts) {
      const starts = cohortBlocks.map((b) => parseIsoMs(b.started)).filter((t) => t !== null)
      if (starts.length < 2) continue
      const spread = Math.max(...starts) - Math.min(...starts)
      if (spread > 60_000) {
        findings.push({
          severity: "medium",
          role: cohortBlocks.map((b) => b.role).join("+"),
          message: `phase=${phase} cohort '${cohortBlocks[0].cohort}' started timestamps span ${Math.round(spread / 1000)}s (>60s suggests serial spawn even though cohort id was shared)`,
        })
      }
    }
  }
  return findings
}

function auditRun(slug) {
  const runDir = path.join(runsRoot, slug)
  if (!existsSync(runDir) || !statSync(runDir).isDirectory()) {
    return { slug, status: "skip", reason: "run directory missing" }
  }

  const statePath = path.join(runDir, "state.json")
  const evidencePath = path.join(runDir, "evidence.md")
  const reviewPath = path.join(runDir, "review.md")
  const missionPath = path.join(runDir, "mission.md")

  if (!existsSync(statePath)) {
    return { slug, status: "skip", reason: "state.json missing" }
  }

  const state = readJsonSafe(statePath) || {}
  const evidence = existsSync(evidencePath) ? readText(evidencePath) : ""
  const review = existsSync(reviewPath) ? readText(reviewPath) : ""
  const mission = existsSync(missionPath) ? readText(missionPath) : ""

  const activeRoles = Array.isArray(state.activeRoles) ? state.activeRoles : []
  const synthesisOptIn = /OMGB_ALLOW_SYNTHESIS:\s*true/i.test(mission)

  const blocks = findSubagentBlocks(evidence)
  const blocksByRole = new Map()
  for (const b of blocks) {
    if (!blocksByRole.has(b.role)) {
      blocksByRole.set(b.role, [])
    }
    blocksByRole.get(b.role).push(b)
  }

  const findings = []
  findings.push(...checkConcurrencyFindings(blocks))

  for (const role of activeRoles) {
    const roleBlocks = blocksByRole.get(role) || []
    if (roleBlocks.length === 0) {
      findings.push({
        severity: "high",
        role,
        message: `activeRole '${role}' has no '## Subagent: ${role}' block in evidence.md`,
      })
      continue
    }
    for (const b of roleBlocks) {
      if (!b.spawn_method) {
        findings.push({
          severity: "high",
          role,
          message: `Subagent block for '${role}' is missing 'spawn_method:'`,
        })
        continue
      }
      if (!ALLOWED_SPAWN_METHODS.has(b.spawn_method)) {
        findings.push({
          severity: "high",
          role,
          message: `Subagent block for '${role}' has unknown spawn_method='${b.spawn_method}'`,
        })
      }
      if (b.spawn_method === "unavailable") {
        if (!synthesisOptIn) {
          findings.push({
            severity: "high",
            role,
            message: `Subagent block for '${role}' is spawn_method=unavailable but mission.md does not opt in (OMGB_ALLOW_SYNTHESIS: true)`,
          })
        }
        if (!b.has_synthesis_justification) {
          findings.push({
            severity: "high",
            role,
            message: `Subagent block for '${role}' is spawn_method=unavailable but no 'Synthesis Justification:' line is present`,
          })
        }
      } else if (!b.has_worker_marker) {
        findings.push({
          severity: "medium",
          role,
          message: `Subagent block for '${role}' (spawn_method=${b.spawn_method}) is missing '### WORKER START/END ${role}' markers`,
        })
      }
    }
  }

  if (review) {
    const reviewedRoles = new Set()
    const reviewerLineRe = /^\*\*Reviewer:\*\*\s*([a-z-]+)/gim
    let m
    while ((m = reviewerLineRe.exec(review)) !== null) {
      reviewedRoles.add(m[1])
    }
    for (const role of reviewedRoles) {
      if (!REVIEWER_ROLES.has(role)) continue
      if (!blocksByRole.has(role)) {
        findings.push({
          severity: "high",
          role,
          message: `review.md cites reviewer '${role}' but evidence.md has no '## Subagent: ${role}' block`,
        })
      }
    }
  }

  if (state.phase === "complete" && (review === "" || !review.includes("Verdict"))) {
    findings.push({
      severity: "high",
      role: "leader",
      message: `state.json says phase=complete but review.md is missing or lacks a Verdict line`,
    })
  }

  const blocking = findings.filter((f) => f.severity === "high")
  const status = blocking.length === 0 ? (synthesisOptIn ? "synthesis-opt-in" : "passed") : "blocked"

  return {
    slug,
    status,
    state_phase: state.phase || "unknown",
    active_roles: activeRoles,
    spawned_roles: Array.from(blocksByRole.keys()),
    synthesis_opt_in: synthesisOptIn,
    findings,
  }
}

function printReport(report) {
  if (report.status === "skip") {
    console.log(`[OMGB] audit skip — ${report.slug} (${report.reason || "no state.json"})`)
    return
  }
  const header = report.synthesis_opt_in
    ? `[OMGB] audit ${report.status} (synthesis opt-in) — ${report.slug}`
    : `[OMGB] audit ${report.status} — ${report.slug}`
  console.log(header)
  console.log(`  phase: ${report.state_phase}`)
  console.log(`  active roles:  ${(report.active_roles || []).join(", ") || "(none)"}`)
  console.log(`  spawned roles: ${(report.spawned_roles || []).join(", ") || "(none)"}`)
  if (report.findings && report.findings.length > 0) {
    console.log("  findings:")
    for (const f of report.findings) {
      console.log(`    [${f.severity}] ${f.role}: ${f.message}`)
    }
  }
}

const args = process.argv.slice(2)

if (args.length === 0 || args.includes("--help")) {
  console.log("Usage: node scripts/ci/check-subagent-evidence.mjs <slug> | --all")
  process.exit(args.length === 0 ? 1 : 0)
}

let slugs
if (args.includes("--all")) {
  if (!existsSync(runsRoot)) {
    console.log("[OMGB] audit passed (no runs)")
    process.exit(0)
  }
  slugs = readdirSync(runsRoot).filter((name) => statSync(path.join(runsRoot, name)).isDirectory())
} else {
  slugs = [args[0]]
}

let blockedCount = 0
let skippedCount = 0
const reports = []
for (const slug of slugs) {
  const report = auditRun(slug)
  reports.push(report)
  printReport(report)
  if (report.status === "blocked") blockedCount += 1
  if (report.status === "skip") skippedCount += 1
}

if (blockedCount > 0) {
  console.log(`[OMGB] audit blocked (${blockedCount} of ${reports.length} runs failed)`)
  process.exit(1)
}
console.log(`[OMGB] audit passed (${reports.length - skippedCount} runs ok, ${skippedCount} skipped)`)
