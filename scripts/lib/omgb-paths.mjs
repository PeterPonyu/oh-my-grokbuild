// Shared filesystem path resolvers for OMGB runtime artifacts.
// Keep this module dependency-free so both CI and workflow helpers can import it.

import os from "node:os"
import path from "node:path"

function resolveEnvPath(value) {
  if (!value) return null
  const raw = String(value)
  if (raw === "~") return os.homedir()
  if (raw.startsWith("~/")) return path.join(os.homedir(), raw.slice(2))
  return path.resolve(raw)
}

export function resolveRunsRoot(env = process.env) {
  return resolveEnvPath(env.OMGB_RUNS_ROOT) || path.join(os.homedir(), ".grok", "omgb", "runs")
}

export function resolveSessionsRoot(env = process.env) {
  return resolveEnvPath(env.OMGB_SESSIONS_ROOT) || path.join(os.homedir(), ".grok", "sessions")
}

export const SCRIPT_LINT_DIRS = ["scripts/local", "scripts/workflow", "scripts/ci", "scripts/lib"]
