#!/usr/bin/env bash
# Project-local Stop hook: regenerate docs/api-historicaldata.md when
# packages/historicaldata/R/ is touched during the session.
#
# Part of JohnGavin/historical#438 — project-local counterpart of the
# global pkgctx Stop-hook rollout tracked in JohnGavin/llm#532.
# Migrate to the global hook pattern when that lands.
#
# Rules:
#   - Detects touches via git diff HEAD + git status (covers staged,
#     unstaged, and untracked changes under packages/historicaldata/R/).
#   - On no touch: exit 0 silently.
#   - On touch: run scripts/regen_api_context.sh inside timeout 60.
#   - On regen failure/timeout: print ONE warning to stderr; still exit 0.
#     A hook must NEVER block the session (fail-open).
#   - NEVER git add/commit/push anything.
#   - No hardcoded absolute paths — repo root resolved from this file's
#     location so the hook works from any worktree.
#
# SELFTEST=1 mode: prints detection result + would-run command; no pkgctx call.

set -uo pipefail

# Resolve repo root from this script's own location (works in any worktree)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"

if [ -z "$REPO_ROOT" ]; then
  echo "pkgctx-regen-hook: WARNING — could not resolve repo root from $SCRIPT_DIR" >&2
  exit 0
fi

PKG_PATH="packages/historicaldata/R/"
REGEN_CMD="$REPO_ROOT/scripts/regen_api_context.sh"

# ── Detect whether packages/historicaldata/R/ was touched this turn ──────────
# Check both committed diff (HEAD vs working tree) and porcelain (untracked/unmerged)
TOUCHED=$(
  {
    git -C "$REPO_ROOT" diff HEAD --name-only 2>/dev/null
    git -C "$REPO_ROOT" status --porcelain 2>/dev/null | awk '{print $2}'
  } | grep -c "^$PKG_PATH" 2>/dev/null || true
)

if [ "${TOUCHED:-0}" -eq 0 ]; then
  if [ "${SELFTEST:-0}" = "1" ]; then
    echo "pkgctx-regen-hook SELFTEST: no touch to $PKG_PATH detected — would skip"
  fi
  exit 0
fi

# ── Touch detected ────────────────────────────────────────────────────────────
if [ "${SELFTEST:-0}" = "1" ]; then
  echo "pkgctx-regen-hook SELFTEST: $PKG_PATH touched — would run: timeout 60 bash $REGEN_CMD"
  exit 0
fi

# Run the regen; fail-open so a hook error never blocks the session
if ! timeout 60 bash "$REGEN_CMD" 2>&1; then
  echo "pkgctx-regen-hook: WARNING — regen failed or timed out (exit $?); docs/api-historicaldata.md may be stale" >&2
fi

exit 0
