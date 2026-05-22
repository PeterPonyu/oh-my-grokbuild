#!/usr/bin/env bash
# verify-robust-install.sh
#
# Optional verification helper for the robust local install changes
# (drift detection, manifest-driven payload, doctor improvements).
#
# This is a convenience wrapper, not a replacement for the required e2e and
# relocation checks documented in docs/REPO-RELOCATION-TEST.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

pass() { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
fail() { printf "${RED}✗ %s${RESET}\n" "$*"; exit 1; }
info() { printf "  %s\n" "$*"; }

echo "=== OMGB Robust Install Verification ==="
echo "Source: $ROOT"
echo

# 1. Smoke + Sanity (the authoritative static checks)
echo "→ Running smoke + sanity..."
if node "$ROOT/scripts/ci/validate.mjs" --smoke; then
  pass "validate --smoke passed"
else
  fail "validate --smoke failed"
fi

if node "$ROOT/scripts/ci/validate.mjs" --sanity; then
  pass "validate --sanity passed"
else
  fail "validate --sanity failed"
fi

# 2. npm test (as required by AGENTS.md)
echo
echo "→ Running npm test..."
if npm test; then
  pass "npm test passed (smoke + sanity markers present)"
else
  fail "npm test failed"
fi

# 3. Doctor check from current tree (drift awareness)
echo
echo "→ Installing current checkout with --force..."
if "$ROOT/scripts/local/install-local.sh" --force; then
  pass "install-local.sh --force completed for current checkout"
else
  fail "install-local.sh --force failed"
fi

echo
echo "→ Running doctor.sh (should be clean for current checkout)..."
DOCTOR_OUTPUT="$("$ROOT/scripts/local/doctor.sh")"
case "$DOCTOR_OUTPUT" in
  *"User skill mount healthy and points to *this* checkout"*)
    pass "doctor.sh reports healthy mount for current tree"
    ;;
  *)
    echo "Doctor output:"
    printf "%s\n" "$DOCTOR_OUTPUT"
    fail "doctor.sh did not report clean current-tree mount (possible drift or setup issue)"
    ;;
esac

# 4. Manifest is the single source of truth
echo
echo "→ Verifying local-payload.txt is the only payload definition..."
if grep -r --include="*.sh" --include="*.mjs" "plugin.json.*cp\|for required in.*plugin.json" "$ROOT/scripts/local" "$ROOT/scripts/ci" | grep -v "local-payload.txt" | grep -v "verify-robust-install.sh" >/dev/null; then
  fail "Found hardcoded payload lists outside of local-payload.txt"
else
  pass "No duplicate hardcoded payload lists found"
fi

echo
echo "=== Verification Summary ==="
pass "All static and doctor checks passed for current tree"
info "Next manual step (when ready): run the full relocation scenario in docs/REPO-RELOCATION-TEST.md"
info "When that passes + e2e.sh passes, the robust install verification is complete."

echo
echo "To run the full e2e (requires auth):"
echo "  scripts/local/e2e.sh"
echo
echo "To run the relocation test:"
echo "  See docs/REPO-RELOCATION-TEST.md"