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
#   - Writes evidence to .omgb/evidence/install-<timestamp>.log.
#   - Does not require sudo, network access, or package installs.
#   - Does not reload Grok. Reload the Grok TUI manually after install.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_NAME="oh-my-grokbuild"
DEFAULT_TARGET_ROOT="$HOME/.grok/plugins/local"
TARGET_ROOT="$DEFAULT_TARGET_ROOT"
MODE="copy"
FORCE=0
EVIDENCE_DIR="$ROOT/.omgb/evidence"
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

resolve_path() {
  node -e 'const fs = require("fs"); try { process.stdout.write(fs.realpathSync(process.argv[1])) } catch { process.exit(1) }' "$1"
}

resolve_logical_path() {
  node -e 'const path = require("path"); process.stdout.write(path.resolve(process.argv[1]))' "$1"
}

validate_payload_item() {
  case "$1" in
    ""|/*|*\\*|../*|*/../*|*"/.."|".."|./*|*/./*|*"/."|".")
      fail "unsafe local-payload.txt entry: $1"
      ;;
    *[[:space:]]*)
      fail "local-payload.txt entries must not contain whitespace: $1"
      ;;
  esac
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
Usage: scripts/local/install-local.sh [--target-root PATH] [--name NAME] [--copy|--symlink] [--force]
USAGE
      exit 0
      ;;
    *)
      fail "unrecognized arg: $1"
      ;;
  esac
done

case "$PLUGIN_NAME" in
  ""|.|..|.*|-*|*/*|*\\*|*[!A-Za-z0-9._-]*)
    fail "--name must be a safe plugin directory name"
    ;;
esac

TARGET_ROOT="$(resolve_logical_path "$TARGET_ROOT")"
DEFAULT_TARGET_ROOT="$(resolve_logical_path "$DEFAULT_TARGET_ROOT")"
HOME_REAL="$(resolve_logical_path "$HOME")"
TARGET="$(resolve_logical_path "$TARGET_ROOT/$PLUGIN_NAME")"

case "$TARGET_ROOT" in
  "$DEFAULT_TARGET_ROOT"|"$DEFAULT_TARGET_ROOT"/*) ;;
  *) fail "--target-root must stay under $DEFAULT_TARGET_ROOT" ;;
esac

case "$TARGET" in
  "$TARGET_ROOT"/*) ;;
  *) fail "refusing to operate outside target root: $TARGET" ;;
esac

if [[ "$TARGET" = "/" || "$TARGET" = "$HOME_REAL" ]]; then
  fail "refusing dangerous install target: $TARGET"
fi

log "source: $ROOT"
log "target: $TARGET"
log "mode:   $MODE"

# Pre-flight validation: validator must pass before we touch the user's grok directory.
log "running validator smoke check"
if ! (cd "$ROOT" && node scripts/ci/validate.mjs --smoke >>"$LOG" 2>&1); then
  fail "validator smoke failed; refusing to install"
fi

mkdir -p "$TARGET_ROOT"

if [[ -e "$TARGET" ]]; then
  if [[ $FORCE -eq 1 ]]; then
    log "removing existing target (force)"
    rm -rf -- "$TARGET"
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
    # Copy driven by local-payload.txt — the single source of truth.
    # When assets change, edit only local-payload.txt (top-level entries only).
    while IFS= read -r item || [[ -n "$item" ]]; do
      [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
      validate_payload_item "$item"
      if [[ "$item" == */ ]]; then
        # directory — copy recursively
        mkdir -p "$(dirname "$TARGET/${item%/}")"
        cp -r "$ROOT/${item%/}" "$TARGET/${item%/}"
      else
        mkdir -p "$(dirname "$TARGET/$item")"
        cp "$ROOT/$item" "$TARGET/$item"
      fi
    done < "$ROOT/local-payload.txt"
    log "copied minimal runtime payload (from local-payload.txt)"
    ;;
  *)
    fail "unknown mode $MODE"
    ;;
esac

# Sanity check driven by the same local-payload.txt manifest.
# We only do lightweight existence checks here; the authoritative validation
# lives in node scripts/ci/validate.mjs --smoke (which also reads the manifest).
while IFS= read -r item || [[ -n "$item" ]]; do
  [[ "$item" =~ ^#.*$ || -z "$item" ]] && continue
  validate_payload_item "$item"
  item_path="${item%/}"   # strip trailing / for existence check
  if [[ ! -e "$TARGET/$item_path" ]]; then
    fail "installed payload missing $item_path (listed in local-payload.txt)"
  fi
done < "$ROOT/local-payload.txt"

# Grok auto-discovers user skills at ~/.grok/skills/<name>/. The plugin payload
# above lives at ~/.grok/plugins/local/<name>/ for a future marketplace flow,
# but the user-skill mount is what makes /omgb invocable today. Symlink-only
# so updates to the source repo or the plugin payload propagate immediately.

USER_SKILL_DIR="$HOME/.grok/skills/omgb"
EXPECTED_SKILL_TARGET="$(resolve_path "$ROOT/skills/omgb/SKILL.md")"
EXPECTED_AGENTS_TARGET="$(resolve_path "$ROOT/agents")"
EXPECTED_ROLES_TARGET="$(resolve_path "$ROOT/roles")"

# Drift detection + healing: if an existing mount is stale, broken, or not the
# symlink layout this installer manages, remove it before adopting this checkout.
if [[ "${OMGB_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
  if [[ -L "$USER_SKILL_DIR/SKILL.md" ]]; then
    EXISTING="$(resolve_path "$USER_SKILL_DIR/SKILL.md" 2>/dev/null || true)"
    if [[ -n "$EXISTING" ]]; then
      EXISTING_DIR="$(dirname "$EXISTING")"
      if [[ "$EXISTING_DIR" != "$(dirname "$EXPECTED_SKILL_TARGET")" ]]; then
        log "NOTE: drift healing would have replaced mount from $EXISTING_DIR to $ROOT (skipped by OMGB_SKIP_USER_SKILL_MOUNT=1)"
      fi
    fi
  fi
else
  NEEDS_HEAL=0
  EXISTING=""

  if [[ -L "$USER_SKILL_DIR" ]]; then
    NEEDS_HEAL=1
  elif [[ -L "$USER_SKILL_DIR/SKILL.md" ]]; then
    EXISTING="$(resolve_path "$USER_SKILL_DIR/SKILL.md" 2>/dev/null || true)"
    if [[ -n "$EXISTING" ]]; then
      EXISTING_DIR="$(dirname "$EXISTING")"
      if [[ "$EXISTING" != "$EXPECTED_SKILL_TARGET" || "$EXISTING_DIR" != "$(dirname "$EXPECTED_SKILL_TARGET")" ]]; then
        NEEDS_HEAL=1
      fi
    else
      NEEDS_HEAL=1
    fi
  elif [[ -e "$USER_SKILL_DIR/SKILL.md" ]]; then
    NEEDS_HEAL=1
  fi

  if [[ -L "$USER_SKILL_DIR/agents" ]]; then
    AGENTS_TARGET="$(resolve_path "$USER_SKILL_DIR/agents" 2>/dev/null || true)"
    if [[ "$AGENTS_TARGET" != "$EXPECTED_AGENTS_TARGET" ]]; then
      NEEDS_HEAL=1
    fi
  fi

  if [[ -L "$USER_SKILL_DIR/roles" ]]; then
    ROLES_TARGET="$(resolve_path "$USER_SKILL_DIR/roles" 2>/dev/null || true)"
    if [[ "$ROLES_TARGET" != "$EXPECTED_ROLES_TARGET" ]]; then
      NEEDS_HEAL=1
    fi
  fi

  for mount_entry in agents roles; do
    if [[ -e "$USER_SKILL_DIR/$mount_entry" && ! -L "$USER_SKILL_DIR/$mount_entry" ]]; then
      NEEDS_HEAL=1
    fi
  done

  if [[ -e "$USER_SKILL_DIR" && ! -d "$USER_SKILL_DIR" ]]; then
    NEEDS_HEAL=1
  fi

  if [[ $NEEDS_HEAL -eq 1 ]]; then
    if [[ -n "$EXISTING" ]]; then
      log "[OMGB] Drift detected"
      log "Previous user-skill mount pointed at: $EXISTING"
    else
      log "[OMGB] No healthy user-skill mount for current tree"
    fi
    log "Current script location (new source of truth): $ROOT"
    log "Replacing mount with links to the current tree."
    rm -rf -- "$USER_SKILL_DIR"
  fi
fi

if [[ "${OMGB_SKIP_USER_SKILL_MOUNT:-0}" = "1" ]]; then
  log "skipping user-skill mount at $USER_SKILL_DIR (OMGB_SKIP_USER_SKILL_MOUNT=1)"
else
  mkdir -p "$(dirname "$USER_SKILL_DIR")"
  mkdir -p "$USER_SKILL_DIR"
  if [[ -L "$USER_SKILL_DIR" ]]; then
    fail "refusing symlinked mount directory: $USER_SKILL_DIR"
  fi
  ln -sfn -- "$EXPECTED_SKILL_TARGET" "$USER_SKILL_DIR/SKILL.md"
  ln -sfn -- "$EXPECTED_AGENTS_TARGET" "$USER_SKILL_DIR/agents"
  ln -sfn -- "$EXPECTED_ROLES_TARGET" "$USER_SKILL_DIR/roles"
  log "mounted user skill at $USER_SKILL_DIR"
fi

log "[OMGB] install ok at $TARGET"
log "next steps:"
log "  1. Reload Grok TUI (or /plugins + /skills) so the new mount is discovered"
log "  2. Run: ./scripts/local/doctor.sh          (quick health check)"
log "  3. Run: npm test && OMGB_E2E_ALLOW_HEADLESS_SKIP=1 scripts/local/e2e.sh   (structural verification)"
log "  4. For full verification: OMGB_E2E_HEADLESS=1 scripts/local/e2e.sh"
log "  5. Inside Grok: /omgb <your task>"
log "  6. After a run: ./scripts/workflow/export-omgb-handoff.sh <slug>  (share to Claude/Codex/etc.)"
log "  7. See docs/WORKING-WITH-OTHER-AGENTS.md for hybrid team instructions"
