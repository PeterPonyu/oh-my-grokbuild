// scripts/lib/naming-slop.mjs
//
// Naming-slop validator — flags file names that look like the user
// dragged in a "_backup" / "-final-v2" / " (1).ext" copy and forgot
// to clean up before committing.
//
// Ports oh-my-claudecode's src/scripts/pre-tool-enforcer.mjs (merged
// PR #3013, 2026-05-15). Upstream runs this at hook time on every
// Write/Edit. Grokbuild has no hook surface, so the same pattern set
// lands as an audit-time directory walker invoked by validate.mjs.
//
// Exports:
//   NAMING_SLOP_PATTERNS — array of { name, re } pattern descriptors.
//   matchNamingSlop(basename) — returns the first matching pattern
//     name (string) or '' when nothing matches.
//   findNamingSlop(roots, { maxDepth = 2 } = {}) — walks each root
//     (recursively, capped by maxDepth) and returns
//     Array<{ path, pattern }> for every match.
//
// WARN-level only; no caller should treat a match as a hard failure
// without explicit confirmation from the human reviewer.

import { readdir } from "node:fs/promises"
import path from "node:path"

export const NAMING_SLOP_PATTERNS = [
  { name: "slop-final", re: /-final(\.[^./]+)?$/ },
  { name: "slop-final-vN", re: /-final-v\d+(\.[^./]+)?$/ },
  { name: "slop-backup", re: /_backup\b/ },
  { name: "slop-old", re: /_old\b/ },
  { name: "slop-copy", re: /_copy\b/ },
  { name: "slop-vN", re: /_v\d+(\.[^./]+)?$/ },
  { name: "slop-paren", re: / \(\d+\)(\.[^./]+)?$/ },
  { name: "slop-space-copy", re: / copy(\.[^./]+)?$/ },
]

export function matchNamingSlop(basename) {
  for (const { name, re } of NAMING_SLOP_PATTERNS) {
    if (re.test(basename)) return name
  }
  return ""
}

export async function findNamingSlop(roots, { maxDepth = 2 } = {}) {
  const findings = []
  async function walk(dir, depth) {
    if (depth > maxDepth) return
    let entries
    try {
      entries = await readdir(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        await walk(full, depth + 1)
      } else if (entry.isFile()) {
        const pattern = matchNamingSlop(entry.name)
        if (pattern) findings.push({ path: full, pattern })
      }
    }
  }
  for (const root of roots) {
    await walk(root, 0)
  }
  return findings
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const roots = ["agents", "roles", "scripts", "skills", "docs"]
  const findings = await findNamingSlop(roots)
  if (findings.length === 0) {
    console.log("[naming-slop] no matches in " + roots.join(", "))
  } else {
    for (const f of findings) {
      console.log(`[naming-slop] ${f.pattern}  ${f.path}`)
    }
  }
}
