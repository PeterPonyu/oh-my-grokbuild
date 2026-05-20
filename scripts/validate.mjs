import { existsSync, readdirSync, readFileSync, statSync } from "node:fs"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("..", import.meta.url))

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
  "Phase 3: Execution",
  "Phase 4: Verification",
  "Phase 5: Review",
  "Phase 6: Fix Loop",
  "Phase 7: Finalization",
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
const allowedReasoningEfforts = new Set(["low", "medium", "high"])

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

function runSmoke() {
  assertExists("package.json")
  assertExists("plugin.json")
  assertExists(".claude-plugin/plugin.json")
  assertExists("skills/omgb/SKILL.md")
  assertExists("agents/ROLE-INDEX.md")
  assertExists("scripts/validate.mjs")
  assertExists("scripts/e2e.sh")
  assertExists("scripts/install-local.sh")

  assertManifestIsSkillsOnly("plugin.json")
  assertManifestIsSkillsOnly(".claude-plugin/plugin.json")

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
      fail(`${rolePath} reasoning_effort must be low|medium|high, got ${reasoning}`)
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

  if (process.exitCode) {
    return
  }

  console.log("[OMGB] sanity passed")
}

const args = new Set(process.argv.slice(2))

if (args.size === 0 || args.has("--help")) {
  console.log("Usage: node scripts/validate.mjs --smoke | --sanity")
  process.exit(args.has("--help") ? 0 : 1)
}

if (args.has("--smoke")) {
  runSmoke()
}

if (args.has("--sanity")) {
  runSanity()
}
