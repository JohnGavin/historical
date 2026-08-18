#!/usr/bin/env bash
# scripts/build.sh — single entry point to BUILD the real pipeline and prove
# it built (#693).
#
# scripts/verify.sh proves docs/_targets.R is STRUCTURALLY sound -- it never
# runs a single target body (see its header comment). This script is the
# complement: it runs the real build (`tar_make()` against docs/_targets.R,
# docs/_targets) and then, UNCONDITIONALLY, runs scripts/check_pipeline_errors.R
# against the resulting store, because docs/_targets.R sets
# `error = "continue"` project-wide -- tar_make() itself exits 0 even when
# targets errored, and a routine tar_read() afterwards silently serves the
# last good value for anything that broke (#680). Neither script is a
# substitute for the other: verify.sh runs no target body; build.sh runs no
# test. Both belong in the "Verifying a change" table in .claude/CLAUDE.md.
#
# WHY THIS EXISTS: PR #690 added check_pipeline_errors.R to close the
# `error = "continue"` blind spot, but nothing invoked it -- the check ran
# only when a human remembered to type a second command after a 40+ minute
# build finished, which is the moment attention is furthest from it. #691 is
# the demonstration: six registry writers errored on every build for four
# commits, surfaced only on the first occasion anyone ran the check by hand.
#
# MAIN CHECKOUT ONLY. A worktree has no targets store of its own and must
# not build one that could race the main checkout's docs/_targets store (see
# .claude/CLAUDE.md "Verifying a change" and the worktree-location rule).
# This script refuses to run from a linked worktree -- see the git-dir check
# below.
#
# Usage:
#   scripts/build.sh
#
# Exit codes:
#   0  tar_make() ran and scripts/check_pipeline_errors.R found no errored
#      targets.
#   1  the build RAN but reported a problem: one or more targets errored
#      (per check_pipeline_errors.R), and/or tar_make() itself exited
#      non-zero (a crashed build still leaves a store worth inspecting, so
#      check_pipeline_errors.R always runs -- see Step 2 below -- but a
#      non-zero tar_make() exit is never silently treated as a pass even
#      when the store it left behind happens to read clean).
#   2  the build did NOT run at all: wrong location (not the main checkout,
#      or run from a linked worktree), the nix shell itself could not be
#      entered (pre-flight check below), or check_pipeline_errors.R could
#      not read a store at all (no store / tar_meta() failed). This is NOT
#      a pass -- never treat it as one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# CRITICAL: cd into the repo this script belongs to -- see scripts/verify.sh's
# header comment (#575) for why. `nix develop "$REPO_ROOT"` only selects
# which flake provides the shell -- the command it runs INHERITS THE
# CALLER'S CWD, so without this `cd`, running this script from elsewhere
# would silently build the wrong tree.
cd "$REPO_ROOT"

if [[ ! -f "$REPO_ROOT/_targets.R" ]]; then
  echo "!!! $REPO_ROOT does not contain _targets.R -- not a valid checkout !!!"
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                         !!!"
  exit 2
fi

# Refuse to run from a linked worktree. A worktree's git-dir lives under
# <main-repo>/.git/worktrees/<name>/ -- the main checkout's own git-dir has
# no such path component. `--absolute-git-dir` (as opposed to plain
# `--git-dir`, which can return a relative path from the main checkout)
# makes this comparison reliable regardless of where the script is invoked
# from.
GIT_DIR_ABS="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
if [[ -z "$GIT_DIR_ABS" ]]; then
  echo "!!! $REPO_ROOT is not a git checkout -- cannot confirm this is the main checkout !!!"
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                       !!!"
  exit 2
fi
if [[ "$GIT_DIR_ABS" == *"/.git/worktrees/"* ]]; then
  echo "!!! Refusing to build from a linked worktree: $REPO_ROOT"
  echo "!!! git-dir: $GIT_DIR_ABS"
  echo "!!! A worktree has no targets store of its own and must not build one that"
  echo "!!! could race the main checkout's docs/_targets store. Run scripts/build.sh"
  echo "!!! from the main checkout instead."
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                    !!!"
  exit 2
fi

echo "=== scripts/build.sh ==="
echo "Repo root: $REPO_ROOT"
echo ""

# ---------------------------------------------------------------------------
# Pre-flight: confirm the nix shell itself can be entered before attempting
# the real build. Without this, a broken flake (nix build failure, not a
# targets problem) would make Step 1 and Step 2 below both exit non-zero for
# reasons that have nothing to do with the pipeline -- and without a way to
# tell that apart from "targets errored", it would be wrongly reported as
# exit 1 instead of exit 2 ("did not run at all").
# ---------------------------------------------------------------------------
echo "--- Pre-flight: confirming nix develop shell is usable (warm: ~13s, cold: 10+ min) ---"
if ! nix develop "$REPO_ROOT" --command true; then
  echo "!!! nix develop failed to provide a shell for $REPO_ROOT !!!"
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                 !!!"
  exit 2
fi
echo "PASS: nix develop shell is usable"
echo ""

# ---------------------------------------------------------------------------
# Step 1: tar_make() against the REAL pipeline. script= and store= are always
# explicit (#680) -- _targets.yaml is gitignored, so relying on it silently
# builds whichever pipeline happens to be ambient in the caller's shell.
#
# docs/_targets.R sets `error = "continue"` project-wide, so tar_make() can
# exit 0 even when targets errored -- that is exactly why Step 2 below is
# unconditional, not gated on this step's exit code.
# ---------------------------------------------------------------------------
echo "--- Step 1: tar_make() (docs/_targets.R -> docs/_targets store) ---"
set +e
nix develop "$REPO_ROOT" --command Rscript -e \
  'targets::tar_make(script = file.path("docs", "_targets.R"), store = file.path("docs", "_targets"))'
TAR_MAKE_STATUS=$?
set -e
echo "--- tar_make() exited $TAR_MAKE_STATUS ---"
echo ""

# ---------------------------------------------------------------------------
# Step 2: check_pipeline_errors.R -- runs UNCONDITIONALLY, even when Step 1
# above exited non-zero (#693). A crashed build still leaves errored targets
# worth naming; skipping this step on a tar_make() failure would throw away
# the most actionable information a failed build produces.
# ---------------------------------------------------------------------------
echo "--- Step 2: scripts/check_pipeline_errors.R (reads tar_meta() directly) ---"
set +e
nix develop "$REPO_ROOT" --command Rscript scripts/check_pipeline_errors.R
CHECK_STATUS=$?
set -e
echo "--- check_pipeline_errors.R exited $CHECK_STATUS ---"
echo ""

# ---------------------------------------------------------------------------
# Final verdict -- printed LAST and kept short, so it is the final thing on
# screen rather than buried 900+ lines up in the tar_make() build log
# (#693). The errored-target list itself was already printed by Step 2,
# directly above this block.
# ---------------------------------------------------------------------------
echo "=== scripts/build.sh: summary ==="
echo "tar_make() exit code:               $TAR_MAKE_STATUS"
echo "check_pipeline_errors.R exit code:  $CHECK_STATUS"
echo ""

if [[ "$CHECK_STATUS" -eq 2 ]]; then
  echo "!!! check_pipeline_errors.R could not run the check at all (no store, or"
  echo "!!! tar_meta() failed) -- see its output above."
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                   !!!"
  exit 2
fi

if [[ "$TAR_MAKE_STATUS" -ne 0 ]] || [[ "$CHECK_STATUS" -ne 0 ]]; then
  echo "=== scripts/build.sh: FAIL ==="
  if [[ "$CHECK_STATUS" -ne 0 ]]; then
    echo "One or more targets errored -- see the [ERROR] list above."
  fi
  if [[ "$TAR_MAKE_STATUS" -ne 0 ]]; then
    echo "tar_make() itself also exited non-zero ($TAR_MAKE_STATUS) -- see the build"
    echo "log above. Even if check_pipeline_errors.R reported no errored targets,"
    echo "a crashed tar_make() means the store may not reflect a complete build --"
    echo "do not treat a clean check_pipeline_errors.R result as a pass on its own."
  fi
  exit 1
fi

echo "=== scripts/build.sh: PASS (tar_make() clean, no errored targets) ==="
exit 0
