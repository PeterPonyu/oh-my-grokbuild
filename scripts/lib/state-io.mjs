// scripts/lib/state-io.mjs
//
// State-management primitives for OMGB runs. JSON in / JSON out. The
// workflow shell scripts call this for every state.json / fanout-trace.json
// mutation so that:
//
//   - bash never builds JSON via string concatenation (brittle, no type
//     safety, easy to corrupt mid-write);
//   - every state transition has a single Node implementation we can test
//     and reuse from any caller (workflow launchers, CI audit, future
//     auto-retry logic, future resume logic);
//   - read-paths in scripts/ci/check-subagent-evidence.mjs can import the
//     same parsers if needed (today they read directly, but the schemas
//     are now defined here).
//
// Operations (CLI):
//
//   state-io.mjs init <slug> <task> <phase> <cohort> <roles-csv>
//       Initialize a run dir. Idempotent on mission.md/tasks.json/review.md;
//       always overwrites state.json with a fresh active=true scaffold.
//
//   state-io.mjs append-cohort <slug> <phase> <cohort> <started-iso> <completed-iso> <trace-tmp-dir>
//       Read per-role files (<role>.start, <role>.end, <role>.rc,
//       <role>.pid) from <trace-tmp-dir>, compose a cohort entry, push it
//       onto fanout-trace.json.cohorts, push a matching phase entry onto
//       state.json.phases, and update activeRoles + updatedAt.
//
//   state-io.mjs finalize <slug> [--keep-active]
//       Mark state.json complete. With --keep-active the run stays active
//       (used by pipeline.sh between phases).
//
// Every op prints a single JSON object to stdout describing what it did.

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs"
import path from "node:path"
import os from "node:os"

const RUNS_ROOT = path.join(os.homedir(), ".grok", "omgb", "runs")

function runDir(slug) {
  return path.join(RUNS_ROOT, slug)
}

function readJson(p, fallback = null) {
  if (!existsSync(p)) return fallback
  try {
    return JSON.parse(readFileSync(p, "utf8"))
  } catch {
    return fallback
  }
}

function writeJson(p, obj) {
  writeFileSync(p, JSON.stringify(obj, null, 2) + "\n")
}

function readTrim(p, fallback = "") {
  if (!existsSync(p)) return fallback
  return readFileSync(p, "utf8").trim()
}

function init(slug, task, phase, cohort, rolesCsv) {
  const dir = runDir(slug)
  mkdirSync(dir, { recursive: true })
  const startedAt = new Date().toISOString()
  const roles = String(rolesCsv || "")
    .split(",")
    .map((r) => r.trim())
    .filter(Boolean)

  const missionPath = path.join(dir, "mission.md")
  if (!existsSync(missionPath)) {
    writeFileSync(
      missionPath,
      [
        "# Mission",
        "",
        "## Goal",
        task,
        "",
        "## Scope",
        `- Phase: ${phase}`,
        `- Cohort: ${cohort}`,
        `- Roles: ${roles.join(", ")}`,
        "- Orchestration: launcher-fanout (each role spawned as a parallel grok subprocess)",
        "",
        "## Constraints",
        "- Roles run with --no-memory --no-plan --disable-web-search --no-subagents.",
        "- Each role replies between literal markers `### WORKER START <role>` / `### WORKER END <role>`.",
        "",
        "## Ambiguity",
        "score: low",
        "",
      ].join("\n"),
    )
  }

  writeJson(path.join(dir, "state.json"), {
    mode: "omgb",
    active: true,
    phase,
    startedAt,
    updatedAt: startedAt,
    taskSlug: slug,
    activeRoles: roles,
    qaCycles: 0,
    reviewRounds: 0,
    blockers: [],
    phases: [],
  })

  if (!existsSync(path.join(dir, "tasks.json"))) {
    writeJson(path.join(dir, "tasks.json"), { tasks: [] })
  }
  if (!existsSync(path.join(dir, "review.md"))) {
    writeFileSync(path.join(dir, "review.md"), "# Review log — fan-out cohort only\n")
  }

  console.log(JSON.stringify({ op: "init", slug, dir, startedAt, roles }))
}

function appendCohort(slug, phase, cohort, startedIso, completedIso, traceTmpDir) {
  const dir = runDir(slug)
  if (!existsSync(dir)) {
    throw new Error(`append-cohort: run dir does not exist: ${dir} (call init first)`)
  }
  const tracePath = path.join(dir, "fanout-trace.json")
  const existing = readJson(tracePath, { slug, cohorts: [] })

  // Backward-compat: legacy single-cohort shape (v0.6.0 fanout-trace) had
  // `{slug, phase, cohort, roles: [...]}` at the top level. Wrap it.
  let cohorts = Array.isArray(existing.cohorts) ? existing.cohorts : []
  if (cohorts.length === 0 && Array.isArray(existing.roles)) {
    cohorts = [{
      phase: existing.phase,
      cohort: existing.cohort,
      started: existing.started,
      completed: existing.completed,
      duration_ms: existing.duration_ms,
      roles: existing.roles,
    }]
  }

  const durationMs = Date.parse(completedIso) - Date.parse(startedIso)
  const roles = []
  for (const entry of readdirSync(traceTmpDir).sort()) {
    if (!entry.endsWith(".start")) continue
    const role = entry.replace(/\.start$/, "")
    const start = readTrim(path.join(traceTmpDir, `${role}.start`))
    const end = readTrim(path.join(traceTmpDir, `${role}.end`))
    const rc = readTrim(path.join(traceTmpDir, `${role}.rc`), "?")
    const pidStr = readTrim(path.join(traceTmpDir, `${role}.pid`), "0")
    roles.push({
      role,
      pid: Number(pidStr) || 0,
      started: start,
      completed: end,
      duration_ms: Date.parse(end) - Date.parse(start),
      exit_code: rc,
    })
  }
  cohorts.push({
    phase,
    cohort,
    started: startedIso,
    completed: completedIso,
    duration_ms: durationMs,
    roles,
  })
  writeJson(tracePath, { slug, cohorts })

  const statePath = path.join(dir, "state.json")
  const state = readJson(statePath, {})
  state.phases = Array.isArray(state.phases) ? state.phases : []
  state.phases.push({
    name: phase,
    started: startedIso,
    completed: completedIso,
    duration_ms: durationMs,
  })
  const activeSet = new Set(Array.isArray(state.activeRoles) ? state.activeRoles : [])
  for (const r of roles) activeSet.add(r.role)
  state.activeRoles = [...activeSet]
  state.updatedAt = completedIso
  writeJson(statePath, state)

  console.log(
    JSON.stringify({
      op: "append-cohort",
      slug,
      phase,
      cohort,
      role_count: roles.length,
      duration_ms: durationMs,
      trace_cohorts: cohorts.length,
    }),
  )
}

function buildAgentsConfig(slug, rolesCsv, readonlyRolesCsv) {
  const dir = runDir(slug)
  mkdirSync(dir, { recursive: true })
  const roles = String(rolesCsv || "")
    .split(",")
    .map((r) => r.trim())
    .filter(Boolean)
  const readonlySet = new Set(
    String(readonlyRolesCsv || "")
      .split(",")
      .map((r) => r.trim())
      .filter(Boolean),
  )
  const config = {}
  for (const role of roles) {
    config[role] = {
      name: role,
      prompt_file: `agents/${role}.md`,
      role: `roles/${role}.toml`,
      permission_mode: readonlySet.has(role) ? "read-only" : "default",
    }
  }
  const configPath = path.join(dir, "agents-config.json")
  writeJson(configPath, config)
  console.log(JSON.stringify({ op: "build-agents-config", slug, configPath, role_count: roles.length }))
}

function finalize(slug, keepActive) {
  const dir = runDir(slug)
  const statePath = path.join(dir, "state.json")
  const state = readJson(statePath, {})
  state.updatedAt = new Date().toISOString()
  if (!keepActive) {
    state.active = false
    state.phase = "complete"
  }
  writeJson(statePath, state)
  console.log(
    JSON.stringify({
      op: "finalize",
      slug,
      active: state.active,
      phase: state.phase,
      phases_recorded: Array.isArray(state.phases) ? state.phases.length : 0,
    }),
  )
}

function usage(code = 1) {
  console.error("Usage:")
  console.error("  state-io.mjs init <slug> <task> <phase> <cohort> <roles-csv>")
  console.error("  state-io.mjs append-cohort <slug> <phase> <cohort> <started-iso> <completed-iso> <trace-tmp-dir>")
  console.error("  state-io.mjs finalize <slug> [--keep-active]")
  console.error("  state-io.mjs build-agents-config <slug> <roles-csv> <readonly-roles-csv>")
  process.exit(code)
}

const args = process.argv.slice(2)
const op = args[0]

try {
  switch (op) {
    case "init":
      if (args.length < 6) usage()
      init(args[1], args[2], args[3], args[4], args[5])
      break
    case "append-cohort":
      if (args.length < 7) usage()
      appendCohort(args[1], args[2], args[3], args[4], args[5], args[6])
      break
    case "finalize":
      if (args.length < 2) usage()
      finalize(args[1], args.includes("--keep-active"))
      break
    case "build-agents-config":
      if (args.length < 4) usage()
      buildAgentsConfig(args[1], args[2], args[3])
      break
    case "--help":
    case "-h":
      usage(0)
      break
    default:
      console.error(`unknown op: ${op || "(missing)"}`)
      usage()
  }
} catch (err) {
  console.error(`state-io error: ${err?.message || err}`)
  process.exit(2)
}
