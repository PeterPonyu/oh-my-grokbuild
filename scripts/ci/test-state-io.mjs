// scripts/ci/test-state-io.mjs
//
// Unit tests for scripts/lib/state-io.mjs operations.
// Uses node:test + node:assert. Creates tmp run dirs under os.tmpdir()
// and calls state-io.mjs via spawnSync so each test exercises the real CLI.
//
// Run directly:
//   node scripts/ci/test-state-io.mjs
//
// Wired into npm test via package.json.

import { test } from "node:test"
import assert from "node:assert/strict"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import path from "node:path"
import os from "node:os"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../..", import.meta.url))
const stateIo = path.join(root, "scripts", "lib", "state-io.mjs")

// Point state-io at a per-process temp root so tests never touch real ~/.grok state.
const RUNS_ROOT = mkdtempSync(path.join(os.tmpdir(), "omgb-state-io-runs-"))
process.env.OMGB_RUNS_ROOT = RUNS_ROOT
process.on("exit", () => {
  rmSync(RUNS_ROOT, { recursive: true, force: true })
})

function runDir(slug) {
  return path.join(RUNS_ROOT, slug)
}

function readJson(p) {
  return JSON.parse(readFileSync(p, "utf8"))
}

function stateIoRun(args, options = {}) {
  return spawnSync(process.execPath, [stateIo, ...args], {
    encoding: "utf8",
    env: { ...process.env, OMGB_RUNS_ROOT: RUNS_ROOT },
    ...options,
  })
}

function cleanup(slug) {
  const dir = runDir(slug)
  if (existsSync(dir)) rmSync(dir, { recursive: true, force: true })
}

// Unique slug per test to prevent cross-test interference.
let testCounter = 0
function slug() {
  return `test-state-io-${process.pid}-${++testCounter}`
}

// ---------------------------------------------------------------------------
// 1. init — scaffolds state.json with correct shape
// ---------------------------------------------------------------------------
test("init: creates state.json with expected shape", () => {
  const s = slug()
  try {
    const result = stateIoRun(["init", s, "test task", "grounding", "g1", "codebase-scout,researcher"])
    assert.equal(result.status, 0, `state-io init failed: ${result.stderr}`)

    const state = readJson(path.join(runDir(s), "state.json"))
    assert.equal(state.mode, "omgb")
    assert.equal(state.active, true)
    assert.equal(state.phase, "grounding")
    assert.equal(state.taskSlug, s)
    assert.deepEqual(state.activeRoles, ["codebase-scout", "researcher"])
    assert.ok(Array.isArray(state.phases))
    assert.equal(state.phases.length, 0)
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 2. init — mission.md is created
// ---------------------------------------------------------------------------
test("init: creates mission.md containing the task", () => {
  const s = slug()
  try {
    stateIoRun(["init", s, "my mission task", "grounding", "g1", "codebase-scout"])
    const mission = readFileSync(path.join(runDir(s), "mission.md"), "utf8")
    assert.ok(mission.includes("my mission task"), "mission.md should contain the task description")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 3. init — idempotent: re-run does not overwrite mission.md
// ---------------------------------------------------------------------------
test("init: mission.md is idempotent on re-run", () => {
  const s = slug()
  try {
    stateIoRun(["init", s, "original task", "grounding", "g1", "codebase-scout"])
    const before = readFileSync(path.join(runDir(s), "mission.md"), "utf8")

    // Re-run with different task — mission.md must NOT be overwritten.
    stateIoRun(["init", s, "new task", "grounding", "g1", "codebase-scout"])
    const after = readFileSync(path.join(runDir(s), "mission.md"), "utf8")

    assert.equal(before, after, "mission.md must not be overwritten on second init")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 4. append-cohort — pushes new entry without clobbering prior cohorts
//    (regression test for v0.7.0 truncation bug)
// ---------------------------------------------------------------------------
test("append-cohort: pushes new cohort without clobbering prior ones", () => {
  const s = slug()
  const dir = runDir(s)
  try {
    stateIoRun(["init", s, "multi-cohort task", "grounding", "g1", "codebase-scout,researcher"])

    // Create a tmp trace dir with role timing files.
    function makeTmp(roles, started, completed) {
      const tmp = path.join(os.tmpdir(), `omgb-test-${process.pid}-${Date.now()}`)
      mkdirSync(tmp, { recursive: true })
      for (const role of roles) {
        writeFileSync(path.join(tmp, `${role}.start`), started)
        writeFileSync(path.join(tmp, `${role}.end`), completed)
        writeFileSync(path.join(tmp, `${role}.rc`), "0")
        writeFileSync(path.join(tmp, `${role}.pid`), "12345")
      }
      return tmp
    }

    const tmp1 = makeTmp(["codebase-scout", "researcher"], "2026-01-01T00:00:00.000Z", "2026-01-01T00:01:00.000Z")
    stateIoRun(["append-cohort", s, "grounding", "g1", "2026-01-01T00:00:00.000Z", "2026-01-01T00:01:00.000Z", tmp1])
    rmSync(tmp1, { recursive: true, force: true })

    const tmp2 = makeTmp(["planner", "architect"], "2026-01-01T00:02:00.000Z", "2026-01-01T00:03:00.000Z")
    stateIoRun(["append-cohort", s, "planning", "p1", "2026-01-01T00:02:00.000Z", "2026-01-01T00:03:00.000Z", tmp2])
    rmSync(tmp2, { recursive: true, force: true })

    const trace = readJson(path.join(dir, "fanout-trace.json"))
    assert.equal(trace.cohorts.length, 2, "both cohorts must be present after two appends")
    assert.equal(trace.cohorts[0].cohort, "g1")
    assert.equal(trace.cohorts[1].cohort, "p1")

    const state = readJson(path.join(dir, "state.json"))
    assert.equal(state.phases.length, 2, "state.json must record both phases")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 5. finalize — sets active=false, phase=complete
// ---------------------------------------------------------------------------
test("finalize: sets active=false and phase=complete", () => {
  const s = slug()
  try {
    stateIoRun(["init", s, "finalize task", "grounding", "g1", "codebase-scout"])
    stateIoRun(["finalize", s])

    const state = readJson(path.join(runDir(s), "state.json"))
    assert.equal(state.active, false)
    assert.equal(state.phase, "complete")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 6. finalize --keep-active — leaves active=true
// ---------------------------------------------------------------------------
test("finalize --keep-active: leaves active=true", () => {
  const s = slug()
  try {
    stateIoRun(["init", s, "pipeline task", "grounding", "g1", "codebase-scout"])
    stateIoRun(["finalize", s, "--keep-active"])

    const state = readJson(path.join(runDir(s), "state.json"))
    assert.equal(state.active, true, "--keep-active must leave active=true")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 7. backward-compat: legacy single-cohort trace is wrapped on append-cohort
// ---------------------------------------------------------------------------
test("append-cohort: wraps legacy single-cohort trace (backward-compat)", () => {
  const s = slug()
  const dir = runDir(s)
  try {
    mkdirSync(dir, { recursive: true })

    // Write a legacy v0.6.0 fanout-trace (flat, no cohorts array).
    const legacyTrace = {
      slug: s,
      phase: "grounding",
      cohort: "g1",
      started: "2026-01-01T00:00:00.000Z",
      completed: "2026-01-01T00:01:00.000Z",
      duration_ms: 60000,
      roles: [
        { role: "codebase-scout", started: "2026-01-01T00:00:00.000Z", completed: "2026-01-01T00:01:00.000Z", exit_code: "0" },
      ],
    }
    writeFileSync(path.join(dir, "fanout-trace.json"), JSON.stringify(legacyTrace))
    writeFileSync(path.join(dir, "state.json"), JSON.stringify({ phases: [], activeRoles: [] }))

    // Append a new cohort — legacy entry must be preserved as cohorts[0].
    const tmp = path.join(os.tmpdir(), `omgb-test-bc-${process.pid}`)
    mkdirSync(tmp, { recursive: true })
    writeFileSync(path.join(tmp, "researcher.start"), "2026-01-01T00:02:00.000Z")
    writeFileSync(path.join(tmp, "researcher.end"), "2026-01-01T00:03:00.000Z")
    writeFileSync(path.join(tmp, "researcher.rc"), "0")
    writeFileSync(path.join(tmp, "researcher.pid"), "0")

    const result = stateIoRun(["append-cohort", s, "grounding", "g2", "2026-01-01T00:02:00.000Z", "2026-01-01T00:03:00.000Z", tmp])
    rmSync(tmp, { recursive: true, force: true })

    assert.equal(result.status, 0, `append-cohort failed: ${result.stderr}`)

    const trace = readJson(path.join(dir, "fanout-trace.json"))
    assert.equal(trace.cohorts.length, 2, "legacy cohort + new cohort = 2 entries")
    assert.equal(trace.cohorts[0].cohort, "g1", "legacy cohort must be cohorts[0]")
    assert.equal(trace.cohorts[1].cohort, "g2", "new cohort must be cohorts[1]")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 8. build-agents-config — writes valid agents-config.json
// ---------------------------------------------------------------------------
test("build-agents-config: writes agents-config.json with correct shape", () => {
  const s = slug()
  const dir = runDir(s)
  try {
    const result = stateIoRun(["build-agents-config", s, "leader,executor,codebase-scout", "codebase-scout"])
    assert.equal(result.status, 0, `build-agents-config failed: ${result.stderr}`)

    const config = readJson(path.join(dir, "agents-config.json"))
    assert.ok(config.leader, "leader must be present")
    assert.equal(config.leader.permission_mode, "default")
    assert.equal(config.executor.permission_mode, "default")
    assert.equal(config["codebase-scout"].permission_mode, "read-only")
    assert.equal(config.leader.name, "leader")
    assert.equal(config.leader.prompt_file, "agents/leader.md")
    assert.equal(config.leader.role, "roles/leader.toml")
  } finally {
    cleanup(s)
  }
})

// ---------------------------------------------------------------------------
// 9. error branches — append/finalize/usage/unknown op fail predictably
// ---------------------------------------------------------------------------
test("append-cohort: missing run dir exits non-zero", () => {
  const tmp = path.join(os.tmpdir(), `omgb-test-missing-${process.pid}`)
  mkdirSync(tmp, { recursive: true })
  try {
    const result = stateIoRun(["append-cohort", "missing-run", "grounding", "g1", "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:01.000Z", tmp])
    assert.equal(result.status, 2)
    assert.match(result.stderr, /run dir does not exist/)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
})

test("finalize: missing state.json exits non-zero", () => {
  const s = slug()
  mkdirSync(runDir(s), { recursive: true })
  try {
    const result = stateIoRun(["finalize", s])
    assert.equal(result.status, 2)
    assert.match(result.stderr, /state\.json does not exist/)
  } finally {
    cleanup(s)
  }
})

test("usage and unknown op exit non-zero", () => {
  const usageResult = stateIoRun(["init", "too-few"])
  assert.equal(usageResult.status, 1)
  assert.match(usageResult.stderr, /Usage:/)

  const unknownResult = stateIoRun(["bogus-op"])
  assert.equal(unknownResult.status, 1)
  assert.match(unknownResult.stderr, /unknown op/)
})

test("readJson fallback: invalid legacy trace is replaced", () => {
  const s = slug()
  const dir = runDir(s)
  const tmp = path.join(os.tmpdir(), `omgb-test-invalid-json-${process.pid}`)
  try {
    stateIoRun(["init", s, "invalid trace task", "grounding", "g1", "researcher"])
    writeFileSync(path.join(dir, "fanout-trace.json"), "{not json")
    mkdirSync(tmp, { recursive: true })
    writeFileSync(path.join(tmp, "researcher.start"), "2026-01-01T00:00:00.000Z")
    writeFileSync(path.join(tmp, "researcher.end"), "2026-01-01T00:00:01.000Z")
    writeFileSync(path.join(tmp, "researcher.rc"), "0")
    writeFileSync(path.join(tmp, "researcher.pid"), "123")
    const result = stateIoRun(["append-cohort", s, "grounding", "g2", "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:01.000Z", tmp])
    assert.equal(result.status, 0, result.stderr)
    const trace = readJson(path.join(dir, "fanout-trace.json"))
    assert.equal(trace.cohorts.length, 1)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
    cleanup(s)
  }
})

console.log("[OMGB] state-io tests passed")
