#!/usr/bin/env bash
# Install oh-my-grokbuild into the user's local Grok plugin directory.
#
# Defaults:
#   - target: ~/.grok/plugins/local/oh-my-grokbuild
#   - mode:   copy
#
# Flags:
#   --target-root PATH    Override the plugins root (default ~/.grok/plugins/local).
#   --name NAME           Override the installed plugin directory name.
#   --copy | --symlink    Install mode (default copy).
#   --force               Overwrite an existing payload.
#
# Side effects:
#   - Writes evidence to .omc/evidence/install-<timestamp>.log.
#   - Does not require sudo, network access, or package installs.
#   - Does not reload Grok. Reload the Grok TUI manually after install.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="oh-my-grokbuild"
TARGET_ROOT="$HOME/.grok/plugins/local"
MODE="copy"
FORCE=0
EVIDENCE_DIR="$ROOT/.omc/evidence"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$EVIDENCE_DIR"
LOG="$EVIDENCE_DIR/install-$TIMESTAMP.log"

log() {
  printf "%s %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"
}

fail() {
  log "FAIL: $*"
  exit 1
}

while (($#)); do
  case "$1" in
    --target-root)
      [[ $# -ge 2 ]] || fail "--target-root requires a path"
      TARGET_ROOT="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || fail "--name requires a value"
      PLUGIN_NAME="$2"
      shift 2
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --symlink)
      MODE="symlink"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: scripts/install-local.sh [--target-root PATH] [--name NAME] [--copy|--symlink] [--force]
USAGE
      exit 0
      ;;
    *)
      fail "unrecognized arg: $1"
      ;;
  esac
done

TARGET="$TARGET_ROOT/$PLUGIN_NAME"

log "source: $ROOT"
log "target: $TARGET"
log "mode:   $MODE"

# Pre-flight validation: validator must pass before we touch the user's grok directory.
log "running validator smoke check"
if ! (cd "$ROOT" && node scripts/validate.mjs --smoke >>"$LOG" 2>&1); then
  fail "validator smoke failed; refusing to install"
fi

mkdir -p "$TARGET_ROOT"

if [[ -e "$TARGET" ]]; then
  if [[ $FORCE -eq 1 ]]; then
    log "removing existing target (force)"
    rm -rf "$TARGET"
  else
    fail "target exists: $TARGET (rerun with --force to overwrite)"
  fi
fi

case "$MODE" in
  symlink)
    ln -s "$ROOT" "$TARGET"
    log "symlinked $ROOT -> $TARGET"
    ;;
  copy)
    mkdir -p "$TARGET"
    mkdir -p "$TARGET/.claude-plugin"
    cp "$ROOT/plugin.json" "$TARGET/plugin.json"
    cp "$ROOT/.claude-plugin/plugin.json" "$TARGET/.claude-plugin/plugin.json"
    cp -r "$ROOT/skills" "$TARGET/skills"
    cp -r "$ROOT/agents" "$TARGET/agents"
    cp -r "$ROOT/roles" "$TARGET/roles"
    cp "$ROOT/README.md" "$TARGET/README.md"
    log "copied minimal runtime payload"
    ;;
  *)
    fail "unknown mode $MODE"
    ;;
esac

# Sanity check that the installed payload contains everything the e2e script needs.
for required in \
  "plugin.json" \
  ".claude-plugin/plugin.json" \
  "skills/omgb/SKILL.md" \
  "agents/ROLE-INDEX.md" \
  "roles/leader.toml"
do
  if [[ ! -e "$TARGET/$required" ]]; then
    fail "installed payload missing $required"
  fi
done

# Grok auto-discovers user skills at ~/.grok/skills/<name>/. The plugin payload
# above lives at ~/.grok/plugins/local/<name>/ for a future marketplace flow,
# but the user-skill mount is what makes /omgb invocable today. Symlink-only
# so updates to the source repo or the plugin payload propagate immediately.
USER_SKILL_DIR="$HOME/.grok/skills/omgb"
if [[ "${OMGB_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
  log "skipping user-skill mount at $USER_SKILL_DIR (OMGB_SKIP_USER_SKILL_MOUNT=1)"
else
  mkdir -p "$USER_SKILL_DIR"
  ln -sfn "$ROOT/skills/omgb/SKILL.md" "$USER_SKILL_DIR/SKILL.md"
  ln -sfn "$ROOT/agents"              "$USER_SKILL_DIR/agents"
  ln -sfn "$ROOT/roles"               "$USER_SKILL_DIR/roles"
  log "mounted user skill at $USER_SKILL_DIR"
fi

log "[OMGB] install ok at $TARGET"
log "next steps:"
log "  1. Reload Grok TUI (or /plugins + /skills) so the new mount is discovered"
log "  2. Run: ./scripts/doctor.sh          (quick health check)"
log "  3. Run: npm test && scripts/e2e.sh   (full verification)"
log "  4. Inside Grok: /omgb <your task>"
log "  5. After a run: ./scripts/export-omgb-handoff.sh <slug>  (share to Claude/Codex/etc.)"
log "  6. See docs/WORKING-WITH-OTHER-AGENTS.md for hybrid team instructions"
