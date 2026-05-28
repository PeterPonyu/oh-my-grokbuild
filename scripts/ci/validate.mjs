import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import path from "node:path"
import process from "node:process"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

import { findNamingSlop } from "../lib/naming-slop.mjs"
import { SCRIPT_LINT_DIRS } from "../lib/omgb-paths.mjs"

const root = fileURLToPath(new URL("../..", import.meta.url))

const requiredRoles = [
  "leader",
  "intake-analyst",
  "researcher",
  "codebase-scout",
  "planner",
  "architect",
  "executor",
  "debugger",
  "test-engineer",
  "verifier",
  "code-reviewer",
  "security-reviewer",
  "performance-reviewer",
  "writer",
  "git-steward",
  "ux-reviewer",
]

const readOnlyRoles = new Set([
  "intake-analyst",
  "researcher",
  "codebase-scout",
  "planner",
  "architect",
  "verifier",
  "code-reviewer",
  "security-reviewer",
  "performance-reviewer",
  "ux-reviewer",
])

const mutatingRoles = new Set([
  "leader",
  "executor",
  "debugger",
  "test-engineer",
  "writer",
  "git-steward",
])

const requiredSkillPhrases = [
  "Persistent Run Directory",
  "Role Router",
  "Phase Pipeline",
  "Phase 0: Intake and Resume",
  "Phase 1: Grounding and Research",
  "Phase 2: Planning and Staffing",
  "Phase 2.5: Adversarial Plan Review",
  "Phase 3: Execution",
  "Phase 4: Verification",
  "Phase 5: Review",
  "Phase 6: Fix Loop",
  "Phase 7: Finalization",
  "Execution Discipline",
  "TDD Mandatory",
  "Scenario Contract",
  "Durable Notepad",
  "Reviewer Gate",
  "Smoke and Sanity Contract",
]

const requiredAgentFrontmatterKeys = [
  "name:",
  "description:",
  "prompt_mode:",
  "permission_mode:",
  "agents_md:",
]

const requiredTomlKeys = [
  "description",
  "default_capability_mode",
  "reasoning_effort",
]

const allowedCapabilityModes = new Set(["read-only", "all"])
const allowedReasoningEfforts = new Set(["low", "medium", "high", "xhigh", "max"])

const forbiddenManifestKeys = new Set([
  "hooks",
  "hook",
  "mcp",
  "mcps",
  "mcpServers",
  "commands",
  "command",
  "agents",
  "agent",
])

const forbiddenTopLevelDirs = ["hooks", "mcps", "mcp", "commands"]
function fail(message) {
  console.error(`[OMGB] validation failed: ${message}`)
  process.exitCode = 1
}

function readText(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8")
}

function readJson(relativePath) {
  return JSON.parse(readText(relativePath))
}

function walkFiles(directory) {
  if (!existsSync(directory)) {
    return []
  }

  const entries = readdirSync(directory)
  const files = []

  for (const entry of entries) {
    const fullPath = path.join(directory, entry)
    const stat = statSync(fullPath)
    if (stat.isDirectory()) {
      files.push(...walkFiles(fullPath))
    } else {
      files.push(fullPath)
    }
  }

  return files
}

function assertExists(relativePath) {
  if (!existsSync(path.join(root, relativePath))) {
    fail(`missing ${relativePath}`)
  }
}

function assertManifestIsSkillsOnly(relativePath) {
  const manifest = readJson(relativePath)

  if (manifest.name !== "oh-my-grokbuild") {
    fail(`${relativePath} has unexpected name`)
  }

  if (!Array.isArray(manifest.skills) || manifest.skills.length !== 1) {
    fail(`${relativePath} must declare exactly one skills path`)
  }

  for (const key of Object.keys(manifest)) {
    if (forbiddenManifestKeys.has(key)) {
      fail(`${relativePath} declares forbidden key ${key}`)
    }
  }
}

function parseFrontmatter(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---/)
  return match ? match[1] : null
}

function parseTomlSimple(text) {
  const map = new Map()
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith("#")) continue
    const eq = line.indexOf("=")
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.slice(1, -1)
    }
    map.set(key, value)
  }
  return map
}

function loadLocalPayloadManifest() {
  const txt = readText("local-payload.txt")
  const entries = []

  for (const [index, rawLine] of txt.split(/\r?\n/).entries()) {
    const line = rawLine.trim()
    if (!line || line.startsWith("#")) continue

    if (line !== rawLine) {
      fail(`local-payload.txt:${index + 1} entries must not have leading/trailing whitespace`)
      continue
    }

    const clean = line.endsWith("/") ? line.slice(0, -1) : line
    const parts = clean.split("/")
    if (
      path.isAbsolute(clean) ||
      clean.includes("\\") ||
      parts.some((part) => part === "" || part === ".." || part === ".")
    ) {
      fail(`local-payload.txt:${index + 1} has unsafe entry: ${line}`)
      continue
    }

    entries.push({ raw: line, path: clean })
  }

  return entries
}

function assertNoSymlinks(relativePath) {
  const fullPath = path.join(root, relativePath)
  const stat = lstatSync(fullPath)
  if (stat.isSymbolicLink()) {
    fail(`local-payload.txt entry must not be a symlink: ${relativePath}`)
    return
  }

  if (stat.isDirectory()) {
    for (const entry of readdirSync(fullPath)) {
      assertNoSymlinks(path.join(relativePath, entry))
    }
  }
}

function runSmoke() {
  assertExists("package.json")
  assertExists("local-payload.txt")
  assertExists("plugin.json")
  assertExists(".claude-plugin/plugin.json")
  assertExists("skills/omgb/SKILL.md")
  assertExists("agents/ROLE-INDEX.md")
  assertExists("scripts/ci/validate.mjs")
  assertExists("scripts/local/e2e.sh")
  assertExists("scripts/local/install-local.sh")

  assertManifestIsSkillsOnly("plugin.json")
  assertManifestIsSkillsOnly(".claude-plugin/plugin.json")

  const payloadItems = loadLocalPayloadManifest()
  for (const item of payloadItems) {
    assertExists(item.path)
    if (existsSync(path.join(root, item.path))) {
      assertNoSymlinks(item.path)
    }
  }

  const skillFiles = walkFiles(path.join(root, "skills"))
    .filter((file) => path.basename(file) === "SKILL.md")
    .map((file) => path.relative(root, file))

  if (skillFiles.length !== 1 || skillFiles[0] !== path.join("skills", "omgb", "SKILL.md")) {
    fail(`expected exactly one skill at skills/omgb/SKILL.md, found ${skillFiles.join(", ")}`)
  }

  const skill = readText("skills/omgb/SKILL.md")
  const skillFrontmatter = parseFrontmatter(skill)
  if (!skillFrontmatter || !/^name:\s*omgb\s*$/m.test(skillFrontmatter)) {
    fail("skills/omgb/SKILL.md frontmatter must name omgb")
  }

  for (const forbiddenDir of forbiddenTopLevelDirs) {
    if (existsSync(path.join(root, forbiddenDir))) {
      fail(`forbidden extension directory exists: ${forbiddenDir}`)
    }
  }

  const agentFiles = readdirSync(path.join(root, "agents"))
    .filter((entry) => entry.endsWith(".md") && entry !== "ROLE-INDEX.md")
    .sort()
  const expectedAgents = [...requiredRoles].sort().map((role) => `${role}.md`)
  if (agentFiles.length !== expectedAgents.length || agentFiles.some((f, i) => f !== expectedAgents[i])) {
    fail(`agents/ must contain exactly these per-role files: ${expectedAgents.join(", ")}; found: ${agentFiles.join(", ")}`)
  }

  const roleFiles = readdirSync(path.join(root, "roles"))
    .filter((entry) => entry.endsWith(".toml"))
    .sort()
  const expectedRoles = [...requiredRoles].sort().map((role) => `${role}.toml`)
  if (roleFiles.length !== expectedRoles.length || roleFiles.some((f, i) => f !== expectedRoles[i])) {
    fail(`roles/ must contain exactly these per-role files: ${expectedRoles.join(", ")}; found: ${roleFiles.join(", ")}`)
  }

  if (process.exitCode) {
    return
  }

  console.log("[OMGB] smoke passed")
}

function runSanity() {
  const skill = readText("skills/omgb/SKILL.md")
  const indexFile = readText("agents/ROLE-INDEX.md")
  const grokDocs = readText("docs/research/grok-build-docs.md")
  const localSurvey = readText("docs/research/local-orchestration-survey.md")
  const prd = readJson("prd.json")

  for (const phrase of requiredSkillPhrases) {
    if (!skill.includes(phrase)) {
      fail(`skill is missing required phrase: ${phrase}`)
    }
  }

  if (!skill.includes("agents/<role>.md") || !skill.includes("roles/<role>.toml")) {
    fail("skill must reference per-role files at agents/<role>.md and roles/<role>.toml")
  }

  for (const role of requiredRoles) {
    if (!skill.includes(role)) {
      fail(`skill does not route role: ${role}`)
    }
    const agentPath = `agents/${role}.md`
    const rolePath = `roles/${role}.toml`
    if (!indexFile.includes(`\`${agentPath}\``)) {
      fail(`ROLE-INDEX.md missing agent file reference: ${agentPath}`)
    }
    if (!indexFile.includes(`\`${rolePath}\``)) {
      fail(`ROLE-INDEX.md missing role file reference: ${rolePath}`)
    }
    if (!skill.includes(`\`${agentPath}\``)) {
      fail(`skill does not reference role file: ${agentPath}`)
    }
    if (!skill.includes(`\`${rolePath}\``)) {
      fail(`skill does not reference role file: ${rolePath}`)
    }

    const agentText = readText(agentPath)
    const fm = parseFrontmatter(agentText)
    if (!fm) {
      fail(`${agentPath} missing YAML frontmatter`)
      continue
    }
    for (const key of requiredAgentFrontmatterKeys) {
      if (!fm.includes(key)) {
        fail(`${agentPath} frontmatter missing key ${key}`)
      }
    }
    if (!new RegExp(`^name:\\s*${role}\\s*$`, "m").test(fm)) {
      fail(`${agentPath} frontmatter name must equal ${role}`)
    }
    const body = agentText.slice(agentText.indexOf("---", 4) + 3)
    for (const section of [
      "## Purpose",
      "## Scope",
      "## Responsibilities",
      "## Constraints",
      "## Execution Process",
      "## Failure Handling",
      "## Records You Keep",
    ]) {
      if (!body.includes(section)) {
        fail(`${agentPath} body missing section ${section}`)
      }
    }

    const tomlText = readText(rolePath)
    const tomlMap = parseTomlSimple(tomlText)
    for (const key of requiredTomlKeys) {
      if (!tomlMap.has(key)) {
        fail(`${rolePath} missing key ${key}`)
      }
    }
    const capability = tomlMap.get("default_capability_mode")
    if (!allowedCapabilityModes.has(capability)) {
      fail(`${rolePath} default_capability_mode must be read-only or all, got ${capability}`)
    }
    if (readOnlyRoles.has(role) && capability !== "read-only") {
      fail(`${rolePath} must be read-only`)
    }
    if (mutatingRoles.has(role) && capability !== "all") {
      fail(`${rolePath} must be all (mutating role)`)
    }
    const reasoning = tomlMap.get("reasoning_effort")
    if (!allowedReasoningEfforts.has(reasoning)) {
      fail(`${rolePath} reasoning_effort must be low|medium|high|xhigh|max, got ${reasoning}`)
    }
  }

  if (indexFile.split(/\r?\n/).length > 80) {
    fail("agents/ROLE-INDEX.md must stay under 80 lines (it should be thin)")
  }

  // Subagent launch compatibility check (for --agents JSON usage)
  for (const role of requiredRoles) {
    const agentPath = `agents/${role}.md`
    const rolePath = `roles/${role}.toml`

    const agentText = readText(agentPath)
    const fmRaw = parseFrontmatter(agentText)
    if (!fmRaw || !/^name:\s*\S/m.test(fmRaw)) {
      fail(`${agentPath} is missing required YAML frontmatter 'name:' for --agents usage`)
    }

    if (!existsSync(path.join(root, rolePath))) {
      fail(`Missing ${rolePath} required for subagent capability config`)
    }
  }

  for (const source of [
    "https://docs.x.ai/build/modes-and-commands",
    "https://docs.x.ai/build/cli/headless-scripting",
  ]) {
    if (!grokDocs.includes(source)) {
      fail(`Grok docs research missing source ${source}`)
    }
  }

  for (const phrase of [
    "agents/<name>.md",
    "roles/<name>.toml",
    "--agent",
    "--agents",
    "--check",
    "0.1.212",
  ]) {
    if (!grokDocs.includes(phrase)) {
      fail(`Grok docs research missing phrase: ${phrase}`)
    }
  }

  for (const name of [
    "oh-my-claudecode",
    "oh-my-codex",
    "oh-my-openagent",
    "oh-my-cursor",
  ]) {
    if (!localSurvey.includes(name)) {
      fail(`local orchestration survey missing project ${name}`)
    }
  }

  if (!Array.isArray(prd.stories) || prd.stories.length < 8) {
    fail("prd.json must contain at least eight stories")
  }

  for (const story of prd.stories ?? []) {
    if (!story.id || !Array.isArray(story.acceptanceCriteria) || typeof story.passes !== "boolean") {
      fail(`invalid PRD story shape for ${story.id ?? "<missing id>"}`)
    }
  }

  if (!skill.includes("[OMGB] smoke passed") || !skill.includes("[OMGB] sanity passed")) {
    fail("skill must document [OMGB] pass markers")
  }
  if (!skill.includes("[OMGB] e2e passed")) {
    fail("skill must document [OMGB] e2e passed marker")
  }
  if (!skill.includes("[OMGB] structural e2e passed")) {
    fail("skill must document [OMGB] structural e2e passed marker")
  }

  assertNoBrandLeakInScripts()
  assertBash32CompatInShellScripts()
  assertAprRolesAreReadOnly()
  assertPlaceholderMarkerBlocks()
  assertMultiPhaseFanoutSerialStartBlocks()
  assertHeadlessGateRejectsNonZeroExit()
  assertValidateRejectsUnknownFlag()

  if (process.exitCode) {
    return
  }

  console.log("[OMGB] sanity passed")
}

// APR (Adversarial Plan Review) contract: the 5 hostile defenders must all
// be read-only by capability. They attack the plan; they never mutate it.
function assertAprRolesAreReadOnly() {
  const aprRoles = [
    "code-reviewer",
    "security-reviewer",
    "performance-reviewer",
    "ux-reviewer",
    "architect",
  ]
  for (const role of aprRoles) {
    const toml = parseTomlSimple(readText(`roles/${role}.toml`))
    if (toml.get("default_capability_mode") !== "read-only") {
      fail(`APR role ${role} must be default_capability_mode = read-only; APR defenders never mutate state`)
    }
  }
  const fanoutScript = readText("scripts/workflow/launch-omgb-fanout.sh")
  if (!/apr\)\s*ROLES_CSV="code-reviewer,security-reviewer,performance-reviewer,ux-reviewer,architect"/.test(fanoutScript)) {
    fail("launch-omgb-fanout.sh must declare the apr phase with exactly the 5 APR roles")
  }
}

// Placeholder-marker audit fixture: a run where the launcher synthesized a
// placeholder block (missing real WORKER START/END output) must be blocked
// by the auditor — not just warned. This asserts the severity is "high".
function assertPlaceholderMarkerBlocks() {
  const fixSlug = "fixture-placeholder-must-block"
  const runsRoot = path.join(root, ".grok", "omgb", "runs")
  const fixDir = path.join(runsRoot, fixSlug)
  mkdirSync(fixDir, { recursive: true })
  try {
    // state.json: one active role, phase=complete
    writeFileSync(
      path.join(fixDir, "state.json"),
      JSON.stringify({
        phase: "complete",
        activeRoles: ["executor"],
        phases: [{ name: "execution", started: "2026-01-01T00:00:00Z", completed: "2026-01-01T00:01:00Z" }],
      }),
    )
    // evidence.md: executor block that has the placeholder text (no real worker output)
    writeFileSync(
      path.join(fixDir, "evidence.md"),
      [
        "## Subagent: executor",
        "- spawn_method: launcher-fanout",
        "- phase: execution",
        "- cohort: e1",
        "- started: 2026-01-01T00:00:00Z",
        "### WORKER START executor",
        "(missing markers — raw output below)",
        "some raw output here",
        "### WORKER END executor",
      ].join("\n"),
    )
    // review.md: minimal verdict
    writeFileSync(path.join(fixDir, "review.md"), "**Reviewer:** verifier\nVerdict: APPROVE\n")

    const auditorPath = path.join(root, "scripts", "ci", "check-subagent-evidence.mjs")
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], { encoding: "utf8" })

    if (result.status === 0) {
      fail(
        "placeholder-marker audit fixture: expected auditor to exit non-zero (blocked) " +
          "for a run with synthesized placeholder output, but it passed. " +
          "Placeholder findings must have severity=high to trigger the block.",
      )
    }
  } finally {
    rmSync(fixDir, { recursive: true, force: true })
  }
}

// Multi-phase fanout serial-start fixture: a multi-cohort fanout-trace.json
// where a mandatory-parallel phase (grounding) has subprocess starts >5s
// apart must be blocked. This verifies the auditor reads cohorts[].roles
// (not just the legacy top-level roles array) when building fanoutStartsByRole.
function assertMultiPhaseFanoutSerialStartBlocks() {
  const fixSlug = "fixture-multi-cohort-serial-must-block"
  const runsRoot = path.join(root, ".grok", "omgb", "runs")
  const fixDir = path.join(runsRoot, fixSlug)
  mkdirSync(fixDir, { recursive: true })
  try {
    // Multi-cohort fanout-trace: grounding phase roles start 10s apart (>5s = definitely serial).
    writeFileSync(
      path.join(fixDir, "fanout-trace.json"),
      JSON.stringify({
        slug: fixSlug,
        cohorts: [
          {
            phase: "grounding",
            cohort: "g1",
            started: "2026-01-01T00:00:00Z",
            completed: "2026-01-01T00:01:00Z",
            roles: [
              { role: "codebase-scout", started: "2026-01-01T00:00:00Z", completed: "2026-01-01T00:00:30Z", exit_code: "0" },
              { role: "researcher",     started: "2026-01-01T00:00:10Z", completed: "2026-01-01T00:01:00Z", exit_code: "0" },
            ],
          },
        ],
        // Intentionally no top-level 'roles' array — only cohorts[].roles.
      }),
    )
    // state.json: both grounding roles active, phase=complete
    writeFileSync(
      path.join(fixDir, "state.json"),
      JSON.stringify({
        phase: "complete",
        activeRoles: ["codebase-scout", "researcher"],
        phases: [{ name: "grounding", started: "2026-01-01T00:00:00Z", completed: "2026-01-01T00:01:00Z" }],
      }),
    )
    // evidence.md: both roles have proper blocks with launcher-fanout and shared cohort
    writeFileSync(
      path.join(fixDir, "evidence.md"),
      [
        "## Subagent: codebase-scout",
        "- spawn_method: launcher-fanout",
        "- phase: grounding",
        "- cohort: g1",
        "- started: 2026-01-01T00:00:00Z",
        "### WORKER START codebase-scout",
        "real output",
        "### WORKER END codebase-scout",
        "",
        "## Subagent: researcher",
        "- spawn_method: launcher-fanout",
        "- phase: grounding",
        "- cohort: g1",
        "- started: 2026-01-01T00:00:10Z",
        "### WORKER START researcher",
        "real output",
        "### WORKER END researcher",
      ].join("\n"),
    )
    writeFileSync(path.join(fixDir, "review.md"), "**Reviewer:** verifier\nVerdict: APPROVE\n")

    const auditorPath = path.join(root, "scripts", "ci", "check-subagent-evidence.mjs")
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], { encoding: "utf8" })

    if (result.status === 0) {
      fail(
        "multi-cohort serial fanout fixture: expected auditor to exit non-zero (blocked) " +
          "for a grounding phase where cohorts[].roles starts are 10s apart (>5s = definitely serial), " +
          "but it passed. The auditor must read cohorts[].roles to build fanoutStartsByRole.",
      )
    }
  } finally {
    rmSync(fixDir, { recursive: true, force: true })
  }
}

// Headless gate self-test: verifies that the e2e.sh headless check requires
// BOTH exit code 0 AND the expected token. A fake grok that prints the token
// but exits non-zero must be rejected by the gate.
function assertHeadlessGateRejectsNonZeroExit() {
  const testScript = path.join(root, "scripts", "ci", "test-headless-gate.sh")
  if (!existsSync(testScript)) {
    fail("scripts/ci/test-headless-gate.sh is missing")
    return
  }
  const result = spawnSync("bash", [testScript], { encoding: "utf8" })
  if (result.status !== 0) {
    fail(
      `headless gate self-test failed:\n${result.stdout || ""}${result.stderr || ""}`,
    )
  }
}

function assertBash32CompatInShellScripts() {
  const forbidden = /declare -A|mapfile|readarray|\$BASHPID|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}/
  for (const dir of SCRIPT_LINT_DIRS) {
    const fullDir = path.join(root, dir)
    if (!existsSync(fullDir)) continue
    for (const entry of readdirSync(fullDir)) {
      const rel = path.join(dir, entry)
      const full = path.join(root, rel)
      if (!statSync(full).isFile() || !entry.endsWith(".sh")) continue
      const text = readText(rel)
      const match = text.match(forbidden)
      if (match) {
        fail(`bash 3.2 compatibility: ${rel} contains forbidden idiom ${match[0]}`)
      }
    }
  }
}

function assertValidateRejectsUnknownFlag() {
  const result = spawnSync(process.execPath, [path.join(root, "scripts", "ci", "validate.mjs"), "--smoek"], { encoding: "utf8" })
  if (result.status === 0) {
    fail("validate.mjs must reject unknown flags instead of exiting 0")
  }
  if (!String(result.stderr || result.stdout).includes("Unknown option")) {
    fail("validate.mjs unknown-flag rejection should print an Unknown option message")
  }
}

// Brand-leak guard: first-party runtime scripts must not write to peer-project paths.
// The legacy Claude namespace belongs to oh-my-claudecode; oh-my-grokbuild writes its
// own evidence under .omgb/. Peer-project mentions in research/changelog/prd
// remain allowed because they document the broader ecosystem.
function assertNoBrandLeakInScripts() {
  const brandNamespace = ".om" + "c/"
  const brandLeakRe = new RegExp("\\.om" + "c/")
  for (const dir of SCRIPT_LINT_DIRS) {
    const fullDir = path.join(root, dir)
    if (!existsSync(fullDir)) continue
    for (const entry of readdirSync(fullDir)) {
      const rel = path.join(dir, entry)
      const full = path.join(root, rel)
      if (!statSync(full).isFile()) continue
      if (!/\.(sh|mjs|js|cjs)$/.test(entry)) continue
      const text = readText(rel)
      if (brandLeakRe.test(text)) {
        fail(`brand leak: ${rel} references ${brandNamespace} — first-party scripts must use .omgb/`)
      }
    }
  }
}

async function runNamingSlopWarn() {
  // Advisory: ports oh-my-claudecode pre-tool-enforcer pattern set
  // (no hook surface in grokbuild, so this runs at audit time).
  // WARN-only; does not change exit code.
  const roots = ["agents", "roles", "scripts", "skills", "docs"].map((r) =>
    path.join(root, r),
  )
  const findings = await findNamingSlop(roots)
  for (const { path: p, pattern } of findings) {
    console.log(`WARN: naming-slop ${pattern} matched ${path.relative(root, p)}`)
  }
}

const rawArgs = process.argv.slice(2)
const args = new Set(rawArgs)
const knownFlags = new Set(["--smoke", "--sanity", "--audit-run", "--audit-all", "--help"])

function usage() {
  console.log(
    [
      "Usage:",
      "  node scripts/ci/validate.mjs --smoke",
      "  node scripts/ci/validate.mjs --sanity",
      "  node scripts/ci/validate.mjs --audit-run <slug>",
      "  node scripts/ci/validate.mjs --audit-all",
    ].join("\n"),
  )
}

if (rawArgs.length === 0 || args.has("--help")) {
  usage()
  process.exit(args.has("--help") ? 0 : 1)
}

const unknownArgs = rawArgs.filter((arg, index) => {
  if (index > 0 && rawArgs[index - 1] === "--audit-run") return false
  return arg.startsWith("-") && !knownFlags.has(arg)
})
if (unknownArgs.length > 0) {
  console.error(`Unknown option(s): ${unknownArgs.join(", ")}`)
  usage()
  process.exit(1)
}

if (!["--smoke", "--sanity", "--audit-run", "--audit-all"].some((flag) => args.has(flag))) {
  console.error(`No validation mode selected for args: ${rawArgs.join(" ")}`)
  usage()
  process.exit(1)
}

if (args.has("--smoke")) {
  runSmoke()
}

if (args.has("--sanity")) {
  runSanity()
}

if (args.has("--smoke") || args.has("--sanity")) {
  await runNamingSlopWarn()
}

async function runAudit(auditArgs) {
  const { spawn } = await import("node:child_process")
  return new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      [path.join(root, "scripts", "ci", "check-subagent-evidence.mjs"), ...auditArgs],
      { stdio: "inherit" },
    )
    child.on("exit", (code) => resolve(code ?? 1))
  })
}

if (args.has("--audit-run")) {
  const idx = rawArgs.indexOf("--audit-run")
  const slug = rawArgs[idx + 1]
  if (!slug) {
    console.error("--audit-run requires a slug")
    process.exit(1)
  }
  const code = await runAudit([slug])
  if (code !== 0) process.exitCode = code
}

if (args.has("--audit-all")) {
  const code = await runAudit(["--all"])
  if (code !== 0) process.exitCode = code
}
