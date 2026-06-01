import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import path from "node:path"
import process from "node:process"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

import { findNamingSlop } from "../lib/naming-slop.mjs"
import { resolveRunsRoot, SCRIPT_LINT_DIRS } from "../lib/omgb-paths.mjs"

const root = fileURLToPath(new URL("../..", import.meta.url))

const validationRunsRoot = resolveRunsRoot({ ...process.env, OMGB_RUNS_ROOT: path.join(root, ".grok", "omgb", "runs") })

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
const surfaceKinds = new Set(["skill", "command", "agent", "role", "hook", "mcp", "manifest", "script", "doc"])
const surfaceClassifications = new Set(["default", "advanced", "internal", "deprecated"])
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

function assertSurfaceInventory() {
  assertExists("docs/surface-inventory.json")

  const inventory = readJson("docs/surface-inventory.json")
  if (inventory.schema_version !== "1.0") {
    fail("docs/surface-inventory.json schema_version must be 1.0")
  }
  if (inventory.repo !== "oh-my-grokbuild") {
    fail("docs/surface-inventory.json repo must be oh-my-grokbuild")
  }
  if (inventory.policy?.default_surface_contract !== "/omgb-only") {
    fail("docs/surface-inventory.json must declare the /omgb-only default surface contract")
  }
  if (inventory.policy?.no_execution_before_inventory_validation !== true) {
    fail("docs/surface-inventory.json must preserve no_execution_before_inventory_validation:true")
  }
  if (!Array.isArray(inventory.surfaces)) {
    fail("docs/surface-inventory.json surfaces must be an array")
    return
  }

  const ids = new Set()
  const defaults = []
  let advanced = 0
  let internal = 0
  let deprecated = 0

  for (const surface of inventory.surfaces) {
    if (!surface.id || ids.has(surface.id)) {
      fail(`docs/surface-inventory.json has missing/duplicate surface id: ${surface.id ?? "<missing>"}`)
    }
    ids.add(surface.id)

    if (!surfaceKinds.has(surface.kind)) {
      fail(`docs/surface-inventory.json surface ${surface.id} has invalid kind: ${surface.kind}`)
    }
    if (!surfaceClassifications.has(surface.classification)) {
      fail(`docs/surface-inventory.json surface ${surface.id} has invalid classification: ${surface.classification}`)
    }
    if (typeof surface.user_invocable !== "boolean") {
      fail(`docs/surface-inventory.json surface ${surface.id} user_invocable must be boolean`)
    }
    if (!surface.path || !surface.rationale || !surface.host_boundary) {
      fail(`docs/surface-inventory.json surface ${surface.id} must include path, rationale, and host_boundary`)
    }

    if (surface.classification === "default" && surface.user_invocable) defaults.push(surface)
    if (surface.classification === "advanced") advanced += 1
    if (surface.classification === "internal") internal += 1
    if (surface.classification === "deprecated") deprecated += 1
  }

  if (defaults.length !== 1 || defaults[0].path !== "skills/omgb/SKILL.md") {
    fail("docs/surface-inventory.json must list exactly one default user-invocable surface: skills/omgb/SKILL.md")
  }
  if (inventory.counts?.default_user_invocable !== defaults.length) {
    fail("docs/surface-inventory.json counts.default_user_invocable is stale")
  }
  if (inventory.counts?.advanced !== advanced) {
    fail("docs/surface-inventory.json counts.advanced is stale")
  }
  if (inventory.counts?.internal !== internal) {
    fail("docs/surface-inventory.json counts.internal is stale")
  }
  if (inventory.counts?.deprecated !== deprecated) {
    fail("docs/surface-inventory.json counts.deprecated is stale")
  }

  const discoveredSkillFiles = walkFiles(path.join(root, "skills"))
    .filter((file) => path.basename(file) === "SKILL.md")
    .map((file) => path.relative(root, file))
  const inventoriedSkillFiles = inventory.surfaces
    .filter((surface) => surface.kind === "skill")
    .map((surface) => surface.path)
    .sort()
  if (
    discoveredSkillFiles.length !== inventoriedSkillFiles.length ||
    discoveredSkillFiles.sort().some((file, index) => file !== inventoriedSkillFiles[index])
  ) {
    fail(
      `docs/surface-inventory.json skill surfaces are stale; discovered ${discoveredSkillFiles.join(", ")} but inventoried ${inventoriedSkillFiles.join(", ")}`,
    )
  }

  // ---------------------------------------------------------------------------
  // Exact-file role/agent inventory coverage.
  //
  // Every discovered roles/*.toml and agents/*.md surface must be covered
  // EXACTLY ONCE in the inventory. We FAIL on:
  //   - missing   : discovered file with no matching inventory entry
  //   - stale      : inventory entry whose file no longer exists on disk
  //   - duplicate  : two inventory entries pointing at the same path
  // agents/ROLE-INDEX.md is INTENTIONALLY EXCLUDED here: it is a thin internal
  // index/doc (not an invocable agent prompt and not consumed via --agents),
  // mirroring the runSmoke() exclusion (entry !== "ROLE-INDEX.md"). This
  // exclusion is explicit and documented so it is not a silent coverage gap.
  // ---------------------------------------------------------------------------
  const discoveredRoleAgentFiles = [
    ...(existsSync(path.join(root, "roles"))
      ? readdirSync(path.join(root, "roles"))
          .filter((entry) => entry.endsWith(".toml"))
          .map((entry) => path.posix.join("roles", entry))
      : []),
    ...(existsSync(path.join(root, "agents"))
      ? readdirSync(path.join(root, "agents"))
          .filter((entry) => entry.endsWith(".md") && entry !== "ROLE-INDEX.md")
          .map((entry) => path.posix.join("agents", entry))
      : []),
  ].sort()

  const roleAgentSurfaces = inventory.surfaces.filter(
    (surface) => surface.kind === "role" || surface.kind === "agent",
  )

  // Detect duplicate inventory paths among role/agent entries.
  const seenRoleAgentPaths = new Set()
  for (const surface of roleAgentSurfaces) {
    if (seenRoleAgentPaths.has(surface.path)) {
      fail(`docs/surface-inventory.json has duplicate role/agent entry for path: ${surface.path}`)
    }
    seenRoleAgentPaths.add(surface.path)
  }

  // Each role/agent entry must be non-default so /omgb stays the only default
  // user-invocable surface: classification advanced|internal, not user_invocable,
  // and explicitly first_run:false.
  for (const surface of roleAgentSurfaces) {
    if (surface.classification === "default") {
      fail(
        `docs/surface-inventory.json role/agent surface ${surface.id} must not be classification:default (/omgb-only contract)`,
      )
    }
    if (surface.user_invocable !== false) {
      fail(
        `docs/surface-inventory.json role/agent surface ${surface.id} must be user_invocable:false (/omgb-only contract)`,
      )
    }
    if (surface.first_run !== false) {
      fail(
        `docs/surface-inventory.json role/agent surface ${surface.id} must declare first_run:false (/omgb-only contract)`,
      )
    }
  }

  const inventoriedRoleAgentFiles = [...seenRoleAgentPaths].sort()

  // Missing: discovered on disk but absent from inventory.
  for (const file of discoveredRoleAgentFiles) {
    if (!seenRoleAgentPaths.has(file)) {
      fail(`docs/surface-inventory.json is MISSING a role/agent surface for discovered file: ${file}`)
    }
  }
  // Stale: in inventory but file no longer exists on disk.
  for (const file of inventoriedRoleAgentFiles) {
    if (!discoveredRoleAgentFiles.includes(file)) {
      fail(`docs/surface-inventory.json has a STALE role/agent surface; file no longer exists: ${file}`)
    }
  }
  if (
    discoveredRoleAgentFiles.length !== inventoriedRoleAgentFiles.length ||
    discoveredRoleAgentFiles.some((file, index) => file !== inventoriedRoleAgentFiles[index])
  ) {
    fail(
      `docs/surface-inventory.json role/agent surfaces are stale; discovered ${discoveredRoleAgentFiles.join(", ")} but inventoried ${inventoriedRoleAgentFiles.join(", ")}`,
    )
  }

  // counts.default_agents_or_roles must equal the number of default-classified
  // role/agent entries (which must be 0 under the /omgb-only contract).
  const defaultRoleAgentCount = roleAgentSurfaces.filter(
    (surface) => surface.classification === "default",
  ).length
  if (typeof inventory.counts?.default_agents_or_roles !== "number") {
    fail("docs/surface-inventory.json counts.default_agents_or_roles must be a number")
  } else if (inventory.counts.default_agents_or_roles !== defaultRoleAgentCount) {
    fail(
      `docs/surface-inventory.json counts.default_agents_or_roles is stale; expected ${defaultRoleAgentCount}, got ${inventory.counts.default_agents_or_roles}`,
    )
  }
  if (defaultRoleAgentCount !== 0) {
    fail("docs/surface-inventory.json must have zero default role/agent surfaces (/omgb-only contract)")
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
  assertExists("docs/LINEAGE.md")
  assertExists("docs/release-checklist.md")

  assertManifestIsSkillsOnly("plugin.json")
  assertManifestIsSkillsOnly(".claude-plugin/plugin.json")
  assertSurfaceInventory()

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
  const lineage = readText("docs/LINEAGE.md")
  const releaseChecklist = readText("docs/release-checklist.md")
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
  if (!readText("README.md").includes("OMGB_REAL_OMGB_GATE_DOCS") || !readText("docs/RUNTIME-AUDIT-FIXMENTS.md").includes("OMGB_REAL_OMGB_GATE_DOCS")) {
    fail("docs must include stable OMGB_REAL_OMGB_GATE_DOCS markers for the opt-in real /omgb quota gate")
  }
  for (const phrase of [
    "/omgb",
    "only default user-invocable",
    "No MCP servers",
    "hooks",
    "source-level reuse",
  ]) {
    if (!lineage.includes(phrase)) {
      fail(`docs/LINEAGE.md missing lineage/host-boundary phrase: ${phrase}`)
    }
  }
  for (const phrase of [
    "docs/surface-inventory.json",
    "scripts/local/doctor.sh",
    "scripts/local/install-local.sh --force",
    "Expansion guard",
  ]) {
    if (!releaseChecklist.includes(phrase)) {
      fail(`docs/release-checklist.md missing release-readiness phrase: ${phrase}`)
    }
  }

  assertNoBrandLeakInScripts()
  assertBash32CompatInShellScripts()
  assertAprRolesAreReadOnly()
  assertPlaceholderMarkerBlocks()
  assertMultiPhaseFanoutSerialStartBlocks()
  assertScenarioCoverageBlocks()
  assertScenarioCoveragePasses()
  assertHeadlessGateRejectsNonZeroExit()
  assertRuntimeReportingContracts()
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
  const runsRoot = validationRunsRoot
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
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], {
      encoding: "utf8",
      env: { ...process.env, OMGB_RUNS_ROOT: runsRoot },
    })
    const output = `${result.stdout || ""}${result.stderr || ""}`

    if (result.status === 0) {
      fail(
        "placeholder-marker audit fixture: expected auditor to exit non-zero (blocked) " +
          "for a run with synthesized placeholder output, but it passed. " +
          "Placeholder findings must have severity=high to trigger the block.",
      )
    }
    if (!output.includes("placeholder marker")) {
      fail(
        "placeholder-marker audit fixture: expected semantic placeholder-marker finding, " +
          `but auditor output was:\n${output}`,
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
  const runsRoot = validationRunsRoot
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
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], {
      encoding: "utf8",
      env: { ...process.env, OMGB_RUNS_ROOT: runsRoot },
    })
    const output = `${result.stdout || ""}${result.stderr || ""}`

    if (result.status === 0) {
      fail(
        "multi-cohort serial fanout fixture: expected auditor to exit non-zero (blocked) " +
          "for a grounding phase where cohorts[].roles starts are 10s apart (>5s = definitely serial), " +
          "but it passed. The auditor must read cohorts[].roles to build fanoutStartsByRole.",
      )
    }
    if (!output.includes("fanout-trace") && !output.includes("transcript-evidence") && !output.includes("started timestamps span")) {
      fail(
        "multi-cohort serial fanout fixture: expected semantic serial-fanout finding, " +
          `but auditor output was:\n${output}`,
      )
    }
  } finally {
    rmSync(fixDir, { recursive: true, force: true })
  }
}

// Shared helper: write an otherwise-passing run (one executor with real
// worker markers) so the only audit lever under test is tasks.json scenario
// coverage. Returns the fixture dir.
function writeScenarioFixtureBase(fixDir) {
  mkdirSync(fixDir, { recursive: true })
  writeFileSync(
    path.join(fixDir, "state.json"),
    JSON.stringify({
      phase: "complete",
      activeRoles: ["executor"],
      phases: [{ name: "execution", started: "2026-01-01T00:00:00Z", completed: "2026-01-01T00:01:00Z" }],
    }),
  )
  writeFileSync(
    path.join(fixDir, "evidence.md"),
    [
      "## Subagent: executor",
      "- spawn_method: launcher-fanout",
      "- phase: execution",
      "- cohort: e1",
      "- started: 2026-01-01T00:00:00Z",
      "### WORKER START executor",
      "real output here",
      "### WORKER END executor",
    ].join("\n"),
  )
  // No '**Reviewer:**' citation: the only audit lever under test is scenario
  // coverage, so we avoid the reviewer-without-block finding. A Verdict line is
  // still required because state.phase=complete.
  writeFileSync(path.join(fixDir, "review.md"), "Verdict: APPROVE\n")
}

// GROK-1 fixture: a tasks.json whose task omits the `regression` scenario class
// must be blocked by the auditor (Scenario Contract: >=3 scenarios covering
// happy + edge + regression). This asserts the missing-class finding is high.
function assertScenarioCoverageBlocks() {
  const fixSlug = "fixture-scenario-coverage-must-block"
  const runsRoot = validationRunsRoot
  const fixDir = path.join(runsRoot, fixSlug)
  writeScenarioFixtureBase(fixDir)
  try {
    // Three scenarios but only happy + edge (no regression) -> must block.
    writeFileSync(
      path.join(fixDir, "tasks.json"),
      JSON.stringify({
        tasks: [
          {
            id: "T-001",
            ownerRole: "executor",
            status: "completed",
            scenarios: [
              { id: "S1", class: "happy", pass_condition: "exit 0", surface_artifact: "stdout", test_file_and_id: "a.test#1" },
              { id: "S2", class: "edge", pass_condition: "empty input handled", surface_artifact: "stdout", test_file_and_id: "a.test#2" },
              { id: "S3", class: "happy", pass_condition: "second happy", surface_artifact: "stdout", test_file_and_id: "a.test#3" },
            ],
          },
        ],
      }),
    )

    const auditorPath = path.join(root, "scripts", "ci", "check-subagent-evidence.mjs")
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], {
      encoding: "utf8",
      env: { ...process.env, OMGB_RUNS_ROOT: runsRoot },
    })
    const output = `${result.stdout || ""}${result.stderr || ""}`

    if (result.status === 0) {
      fail(
        "scenario-coverage audit fixture: expected auditor to exit non-zero (blocked) " +
          "for a task missing the regression scenario class, but it passed. " +
          "Missing-class findings must have severity=high to trigger the block.",
      )
    }
    if (!output.includes("missing class") && !output.includes("regression")) {
      fail(
        "scenario-coverage audit fixture: expected a missing-class finding naming regression, " +
          `but auditor output was:\n${output}`,
      )
    }
  } finally {
    rmSync(fixDir, { recursive: true, force: true })
  }
}

// GROK-1 fixture: a tasks.json whose task declares >=3 scenarios covering all
// three classes must pass the auditor (no scenario-coverage finding). This
// guards against over-blocking on valid coverage.
function assertScenarioCoveragePasses() {
  const fixSlug = "fixture-scenario-coverage-must-pass"
  const runsRoot = validationRunsRoot
  const fixDir = path.join(runsRoot, fixSlug)
  writeScenarioFixtureBase(fixDir)
  try {
    writeFileSync(
      path.join(fixDir, "tasks.json"),
      JSON.stringify({
        tasks: [
          {
            id: "T-001",
            ownerRole: "executor",
            status: "completed",
            scenarios: [
              { id: "S1", class: "happy", pass_condition: "exit 0", surface_artifact: "stdout", test_file_and_id: "a.test#1" },
              { id: "S2", class: "edge", pass_condition: "empty input handled", surface_artifact: "stdout", test_file_and_id: "a.test#2" },
              { id: "S3", class: "regression", pass_condition: "adjacent surface ok", surface_artifact: "stdout", test_file_and_id: "a.test#3" },
            ],
          },
        ],
      }),
    )

    const auditorPath = path.join(root, "scripts", "ci", "check-subagent-evidence.mjs")
    const result = spawnSync(process.execPath, [auditorPath, fixSlug], {
      encoding: "utf8",
      env: { ...process.env, OMGB_RUNS_ROOT: runsRoot },
    })
    const output = `${result.stdout || ""}${result.stderr || ""}`

    if (result.status !== 0) {
      fail(
        "scenario-coverage pass fixture: expected auditor to exit 0 for a task with full " +
          `happy/edge/regression coverage, but it blocked. Auditor output:\n${output}`,
      )
    }
  } finally {
    rmSync(fixDir, { recursive: true, force: true })
  }
}

// Runtime reporting guard: keep the operational evidence honest. These checks
// lock in the fixes for observed runtime drift points: e2e must audit the durable
// run archive rather than only temp probes, probe cleanup must remove temp
// repo-local symlinks, and team dry-run copy/paste commands must match the real
// launch permission mode.
function assertRuntimeReportingContracts() {
  const e2eScript = readText("scripts/local/e2e.sh")
  const doctorScript = readText("scripts/local/doctor.sh")
  const teamLauncher = readText("scripts/workflow/launch-omgb-team.sh")
  const fanoutLauncher = readText("scripts/workflow/launch-omgb-fanout.sh")

  if (!e2eScript.includes('audit_canonical_runs()')) {
    fail("scripts/local/e2e.sh must keep canonical run archive audit in a named helper")
  }
  if (!e2eScript.includes('OMGB_RUNS_ROOT="$HOME/.grok/omgb/runs" node "$ROOT/scripts/ci/validate.mjs" --audit-all')) {
    fail("scripts/local/e2e.sh must audit ~/.grok/omgb/runs explicitly, not only temporary probe roots")
  }
  if (e2eScript.includes('ok "all completed runs pass the subagent-evidence audit"')) {
    fail("scripts/local/e2e.sh must not claim all completed runs pass after auditing only temp dry-run probes")
  }
  if (!e2eScript.includes('rm -f -- "$link"') || !e2eScript.includes('readlink "$link"')) {
    fail("scripts/local/e2e.sh must clean repo-local symlinks that point at temporary probe roots")
  }
  if (!/! -e ['\"]?\$target['\"]?/.test(e2eScript) || !e2eScript.includes('PROBE_TMP_PARENT') || !e2eScript.includes('/tmp/omgb-*/*')) {
    fail("scripts/local/e2e.sh must preserve live temp probe links from other concurrent runs while cleaning stale ones")
  }
  if (!e2eScript.includes('OMGB_E2E_STRICT_AUDIT')) {
    fail("scripts/local/e2e.sh must support strict canonical audit gating for releases")
  }
  if (!e2eScript.includes('OMGB_E2E_REAL_OMGB') || !e2eScript.includes('OMGB_REAL_OMGB_OK')) {
    fail("scripts/local/e2e.sh must provide an opt-in real /omgb quota gate, not only a generic headless token probe")
  }
  if (!e2eScript.includes('--cwd "$real_workspace"') || !e2eScript.includes('--tools read_file,list_dir,grep') || !e2eScript.includes('mktemp -d "${TMPDIR:-/tmp}/omgb-real-omgb.XXXXXX"') || !e2eScript.includes('env -i "HOME=$real_home"') || !e2eScript.includes('HTTP_PROXY HTTPS_PROXY NO_PROXY')) {
    fail("real /omgb e2e must run in a scrubbed isolated HOME and temporary workspace with read-only tools")
  }
  if (!e2eScript.includes('git ls-files -z | tar --null -T - -cf -') || !e2eScript.includes('--dry-run') || !e2eScript.includes('timeout "${OMGB_E2E_REAL_OMGB_TIMEOUT:-180}"') || !e2eScript.includes('final_line=') || !e2eScript.includes('real_omgb_transcript_has_skill_evidence') || !e2eScript.includes('synthetic_reason') || !e2eScript.includes('<skill_information>')) {
    fail("real /omgb e2e must copy the workspace, explicitly dry-run JSON generation, require a final marker, and verify non-user /omgb transcript evidence")
  }
  if (e2eScript.includes('^\\s+└\\s+omgb\\s+user\\s*$')) {
    fail("scripts/local/e2e.sh must not depend on exact grok inspect tree-glyph formatting")
  }
  if (!doctorScript.includes('readlink "$link"') || !doctorScript.includes('rm -f -- "$link"')) {
    fail("scripts/local/doctor.sh must clean repo-local symlinks created by its dry-run probe")
  }
  if (!/! -e ['\"]?\$target['\"]?/.test(doctorScript) || !doctorScript.includes('PROBE_TMP_PARENT') || !doctorScript.includes('/tmp/omgb-*/*')) {
    fail("scripts/local/doctor.sh must preserve live temp probe links from other concurrent runs while cleaning stale ones")
  }
  if (!teamLauncher.includes('--permission-mode auto -p "/omgb $TASK"')) {
    fail("launch-omgb-team.sh dry-run command must include --permission-mode auto to match the real launch command")
  }
  if (!/--dry-run\)\s+LAUNCH=0/.test(teamLauncher) || !/--dry-run\)\s+LAUNCH=0/.test(fanoutLauncher)) {
    fail("launchers must accept explicit --dry-run as a no-op alias for the default dry-run mode")
  }
  if (!teamLauncher.includes('--launch and --dry-run are mutually exclusive') || !fanoutLauncher.includes('--launch and --dry-run are mutually exclusive')) {
    fail("launchers must reject mixed --launch and --dry-run flags instead of using order-dependent precedence")
  }
  if (!readText("package.json").includes("scripts/ci/test-launcher-modes.sh")) {
    fail("npm test must include behavioral launcher mode checks for explicit --dry-run and mixed launch flags")
  }
  if (!readText("package.json").includes("scripts/ci/test-real-omgb-evidence.sh") || !existsSync(path.join(root, "scripts", "ci", "test-real-omgb-evidence.sh"))) {
    fail("npm test must include a negative transcript-evidence regression test for the real /omgb gate")
  }
  if (!e2eScript.includes('local plugin payload may not appear as an enabled plugin')) {
    fail("scripts/local/e2e.sh must clarify user-skill mount vs enabled-plugin listing semantics")
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
  const forbidden = /declare -A|mapfile|readarray|\$BASHPID|date[^\n]*%[0-9]*N|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}/
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
