// scripts/lib/doctor-manifest.mjs
//
// Manifest cross-ref helper for `scripts/local/doctor.sh`.
//
// Ports oh-my-openagent's src/cli/doctor.ts schema-validator pattern.
// Pure .mjs (per the user's TS-preference directive); doctor.sh stays
// bash as the entry point, but the JSON-parsing + cross-ref logic lives
// here so we never hand-roll JSON parsing in bash.
//
// checkManifest():
//   1. Reads plugin.json and .claude-plugin/plugin.json, confirms each
//      parses as JSON and has required fields (name, version,
//      description).
//   2. If a manifest declares a `skills:` array, confirms each entry
//      resolves to a `skills/<name>/SKILL.md` on disk.
//   3. Cross-checks agents/ ↔ roles/ pairing: every `agents/<name>.md`
//      (excluding ROLE-INDEX.md) must have a matching
//      `roles/<name>.toml` and vice versa.
//   4. Returns { ok, findings:[{severity:'WARN'|'FAIL', msg}] }.
//      `ok` is false only when any FAIL-severity finding is present;
//      WARN findings still permit ok:true.
//
// CLI: `node scripts/lib/doctor-manifest.mjs --print` writes findings
// to stdout, one per line, and exits 0 (ok) or 1 (FAIL).

import { readFile, readdir, access } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const REQUIRED_FIELDS = ["name", "version", "description"]

async function exists(p) {
  try {
    await access(p)
    return true
  } catch {
    return false
  }
}

async function readJsonOrNull(p) {
  try {
    return JSON.parse(await readFile(p, "utf8"))
  } catch {
    return null
  }
}

export async function checkManifest() {
  const findings = []
  const manifestPaths = ["plugin.json", path.join(".claude-plugin", "plugin.json")]
  const manifests = []
  for (const rel of manifestPaths) {
    const full = path.join(ROOT, rel)
    if (!(await exists(full))) {
      findings.push({ severity: "FAIL", msg: `manifest missing: ${rel}` })
      continue
    }
    const obj = await readJsonOrNull(full)
    if (!obj) {
      findings.push({ severity: "FAIL", msg: `manifest unparseable: ${rel}` })
      continue
    }
    manifests.push({ rel, obj })
    for (const key of REQUIRED_FIELDS) {
      if (!obj[key]) {
        findings.push({ severity: "FAIL", msg: `${rel} missing required field: ${key}` })
      }
    }
  }

  for (const { rel, obj } of manifests) {
    if (!Array.isArray(obj.skills)) continue
    const manifestDir = path.dirname(path.join(ROOT, rel))
    for (const entry of obj.skills) {
      const skillDir = path.resolve(manifestDir, entry)
      const skillMd = path.join(skillDir, "SKILL.md")
      if (!(await exists(skillMd))) {
        findings.push({
          severity: "FAIL",
          msg: `${rel} skills[] entry "${entry}" has no SKILL.md at ${path.relative(ROOT, skillMd)}`,
        })
      }
    }
  }

  const agentsDir = path.join(ROOT, "agents")
  const rolesDir = path.join(ROOT, "roles")
  if ((await exists(agentsDir)) && (await exists(rolesDir))) {
    const agentNames = (await readdir(agentsDir))
      .filter((f) => f.endsWith(".md") && f !== "ROLE-INDEX.md")
      .map((f) => f.replace(/\.md$/, ""))
    const roleNames = (await readdir(rolesDir))
      .filter((f) => f.endsWith(".toml"))
      .map((f) => f.replace(/\.toml$/, ""))
    const agentSet = new Set(agentNames)
    const roleSet = new Set(roleNames)
    for (const name of agentNames) {
      if (!roleSet.has(name)) {
        findings.push({ severity: "FAIL", msg: `agents/${name}.md has no matching roles/${name}.toml` })
      }
    }
    for (const name of roleNames) {
      if (!agentSet.has(name)) {
        findings.push({ severity: "FAIL", msg: `roles/${name}.toml has no matching agents/${name}.md` })
      }
    }
  } else {
    findings.push({ severity: "WARN", msg: "agents/ or roles/ directory absent — skipping pairing check" })
  }

  const ok = !findings.some((f) => f.severity === "FAIL")
  return { ok, findings }
}

if (process.argv[2] === "--print") {
  const { ok, findings } = await checkManifest()
  for (const f of findings) {
    console.log(`${f.severity}: ${f.msg}`)
  }
  if (ok) console.log("manifest cross-ref: ok")
  process.exit(ok ? 0 : 1)
}
