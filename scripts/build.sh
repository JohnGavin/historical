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
# STEP 3 (#695): after the store exists, this script also runs
# scripts/check_dashboard_freshness.R --data-staleness, which needs a real
# store to compare each docs/*.qmd page own referenced targets build times
# against that page rendered .html -- the ONE surface of #695's three that
# verify.sh cannot cover (verify.sh runs Check 1 + Check 2 of the same
# script, which need no store -- see that script header comment for the
# full three-check design).
#
# STEP 0.5 / build lock (#730): two overlapping tar_make() runs against ONE
# store interleave writes to docs/_targets/meta/meta -- observed once,
# producing a doubled/malformed meta line that made check_pipeline_errors.R
# (Step 2) silently PASS on a truncated read while tar_make() itself had
# printed "errored pipeline". Before Step 1 can start, this script now
# acquires a best-effort lock (mkdir under the repo's .git dir, PID-stamped,
# released via the trap-based cleanup below) and refuses to start a second
# build while a live one holds it. See the "Step 0.5" block for the exact
# stale-lock recovery behaviour.
#
# STEP 2b / cross-check (#730): Step 1's tar_make() log is now teed to a
# temp file. Immediately after Step 2 (check_pipeline_errors.R) runs, this
# script greps that log for the word "errored" -- if the log mentions it but
# check_pipeline_errors.R reported clean, that disagreement is now a hard
# failure (CROSSCHECK_STATUS) rather than something nothing looks for. This
# is the check that would have caught #730's incident on its own, and it
# also now gates Step 2.5 (metadata snapshot) and Step 4 (--render): a
# snapshot or a publish from a store the cross-check distrusts is worse than
# not producing one.
#
# NOT implemented here: #730's proposal 2 (asserting the tar_meta() row
# count against docs/_targets_meta_snapshot.csv, #695 Check 3's committed
# snapshot). That snapshot is written by THIS SAME script's Step 2.5, from
# the same build it would be asked to validate -- using it as a pre-build
# expectation needs the previous run's snapshot to be read and compared
# before Step 1 overwrites the store, which is a genuine ordering question
# deserving its own design, not a fold-in here. Left for a follow-up.
#
# STEP 2.5 / metadata snapshot (#695 Check 3 CI gap): immediately after a
# clean Step 1 + Step 2, this script also writes
# docs/_targets_meta_snapshot.csv via scripts/write_targets_meta_snapshot.R
# -- a small, deterministic, committable copy of every target's tar_meta()
# build time. .github/workflows/dashboard-freshness.yml reads this file as
# its ONLY source for Check 3 (a CI runner never has a store); see that
# script and scripts/check_dashboard_freshness.R's "Metadata snapshot"
# section header comment for the full design, including why the snapshot's
# own age is itself a hard-failure signal in CI. Deliberately gated on Step
# 1 + Step 2 being clean (NOT on Step 3's DASHBOARD_STATUS, which is
# informational staleness reporting, unrelated to whether the underlying
# build times are trustworthy) -- a snapshot taken from a store with errored
# targets would encode wrong build times for whatever failed. Like --render
# below, this step never commits or pushes what it writes.
#
# STEP 4 / --render (#695): closes the OTHER half of #695. Step 3 above only
# DETECTS stale dashboards -- nothing republishes them. GitHub Pages serves
# whatever .html is committed to main:/docs directly (no render-on-deploy
# workflow), so a page Step 3 flags stays stale until a human remembers to
# `quarto render` it by hand -- the same "forgot the follow-up command"
# failure mode #690/#691 already taught this repo once, just one script
# later; re-rendering the 9 stale pages by hand recently cost ~20 minutes of
# wall clock. `--render` is opt-in (default behaviour is completely
# unchanged): after a clean build it parses Step 3's own stdout for the
# `[STALE]` (Check 2) and `[DATA-STALE]` (Check 3) lines documented in that
# script's header comment, and re-renders ONLY those pages -- ONE PAGE AT A
# TIME via a separate `quarto render` per file, so one unrenderable page
# (e.g. #699) cannot hide a failure on the other 8. Every rendered page is
# then grepped for the same five error patterns
# verification-before-completion.md's Post-Deploy Validation table checks
# against the deployed site, because a page can exit 0 from `quarto render`
# and still emit `NULL`/`MISSING EVIDENCE` where a number belongs. If Step
# 3's stdout does not end with its own completion marker
# (`::VERIFY:DASHBOARD_FRESHNESS_STATUS::`), Step 4 does not trust the
# partial parse and falls back to rendering every docs/*.qmd page instead --
# more expensive, but never silently renders nothing when the truth is
# "don't know". Step 4 renders ONLY: it never `git add`/`git commit`/
# `git push`es anything it produces -- publishing is a decision for a human
# to review and commit, not something a build step should do unattended.
#
# MAIN CHECKOUT ONLY. A worktree has no targets store of its own and must
# not build one that could race the main checkout's docs/_targets store (see
# .claude/CLAUDE.md "Verifying a change" and the worktree-location rule).
# This script refuses to run from a linked worktree -- see the git-dir check
# below.
#
# Usage:
#   scripts/build.sh
#   scripts/build.sh --render
#     After a clean build (tar_make() exit 0 AND check_pipeline_errors.R
#     finds no errored targets -- nothing else gates this; see Step 4 below),
#     re-renders every docs/*.qmd page Step 3 flagged as stale, one at a
#     time. Rendered files are left in the working tree for a human to
#     review and commit -- this flag never runs `git add`/`git commit`/
#     `git push`. An unrecognised flag is rejected immediately, before
#     entering the nix shell, with a usage message and exit 2.
#
# Exit codes:
#   0  tar_make() ran, scripts/check_pipeline_errors.R found no errored
#      targets, and scripts/check_dashboard_freshness.R --data-staleness
#      found no dead target references (and no staleness escalated to a
#      failure -- see that script header for HD_FAIL_ON_STALE_DASHBOARDS).
#      With --render: additionally, every page Step 4 rendered did so
#      cleanly (see exit code 3 below for the alternative).
#   1  the build RAN but reported a problem: one or more targets errored
#      (per check_pipeline_errors.R), tar_make()'s own log disagreed with a
#      clean check_pipeline_errors.R verdict (Step 2b cross-check, #730), the
#      metadata snapshot could not be written (per
#      write_targets_meta_snapshot.R -- #695 Check 3 CI gap; see Step 2.5
#      above), a dead target reference or escalated staleness (per
#      check_dashboard_freshness.R), and/or tar_make() itself exited
#      non-zero (a crashed build still leaves a store worth inspecting, so
#      Steps 2, 2b, 2.5, and 3 always run when Steps 1 + 2 permit -- see
#      below -- but a non-zero tar_make() exit is never silently treated as
#      a pass even when the store it left behind happens to read clean).
#      With --render: also covers the build being too dirty to render at
#      all -- Step 4 is skipped (not attempted) and says so; the render
#      never even starts.
#   2  the build did NOT run at all: wrong location (not the main checkout,
#      or run from a linked worktree), a build lock already held by a live
#      PID (Step 0.5, #730 -- see its block for stale-lock recovery), the
#      nix shell itself could not be entered (pre-flight check below),
#      check_pipeline_errors.R could not read a store at all (no store,
#      tar_meta() failed, or a truncated/malformed meta file -- #730), or
#      check_dashboard_freshness.R --data-staleness could not run its checks
#      at all. Also returned immediately, before anything runs, for an
#      unrecognised command-line flag. This is NOT a pass -- never treat it
#      as one.
#   3  --render ONLY: the build itself was clean (tar_make() exit 0,
#      check_pipeline_errors.R clean) and Step 4 ran, but one or more
#      rendered pages either exited non-zero from `quarto render` or
#      rendered successfully yet still contained one of the five error
#      patterns Step 4 greps for. Deliberately a DIFFERENT code from exit 1:
#      a render failure is not a build failure -- the pipeline and its data
#      are fine, only the republish step for one or more pages is not.
#      Never returned without --render.

set -euo pipefail

# ---------------------------------------------------------------------------
# Flag parsing (#695). Deliberately the very first thing this script does,
# before REPO_ROOT/nix-shell/anything else -- an unrecognised flag should
# fail immediately and cheaply, not after a 10+ minute cold nix build.
# ---------------------------------------------------------------------------
RENDER=false
for arg in "$@"; do
  case "$arg" in
    --render)
      RENDER=true
      ;;
    *)
      echo "!!! Unknown argument: $arg" >&2
      echo "!!! Usage: scripts/build.sh [--render]" >&2
      echo "!!!   --render  after a clean build, re-render docs/*.qmd pages Step 3" >&2
      echo "!!!             flagged as stale (see this script's header comment)." >&2
      echo "!!! BUILD DID NOT RUN. This is NOT a pass.                              !!!" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# #730: single unified cleanup trap for every temp resource this script
# creates (build lock dir, tar_make() log, dashboard-freshness log). All
# three variables are pre-declared empty here and populated later, at the
# point each resource is actually created, so the trap (registered once,
# below) is safe to fire at ANY point in the script -- including an early
# exit before some of these vars are ever assigned -- without tripping
# `set -u`. Declaring one trap here (instead of one per resource) also means
# the build lock is guaranteed to be released on every exit path, not only
# the one Step it happens to be textually near.
# ---------------------------------------------------------------------------
LOCKDIR=""
TARMAKE_LOG=""
DASHBOARD_LOG=""
_cleanup() {
  [[ -n "${LOCKDIR:-}" ]] && rm -rf "$LOCKDIR"
  [[ -n "${TARMAKE_LOG:-}" ]] && rm -f "$TARMAKE_LOG"
  [[ -n "${DASHBOARD_LOG:-}" ]] && rm -f "$DASHBOARD_LOG"
  return 0
}
trap _cleanup EXIT

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

# ---------------------------------------------------------------------------
# Step 0.5 (#730): concurrency guard. Nothing about `targets` itself locks
# the store -- a second `tar_make()` starting against a store one is already
# building will interleave writes to docs/_targets/meta/meta, which is
# exactly the incident behind #730: two overlapping runs produced one
# doubled, malformed meta line, and the checker built to catch an errored
# pipeline instead reported PASS on a truncated read of that file. This is
# a best-effort guard, not a distributed lock -- it protects against the
# common case (a human, or a second script invocation, starting a second
# scripts/build.sh while one is already running) via `mkdir`, which is
# atomic w.r.t. EEXIST on a local filesystem, so at most one concurrent
# invocation can create $LOCKDIR. The lock lives under $GIT_DIR_ABS (always
# ".../.git" for the main checkout, confirmed not-a-worktree just above),
# not under docs/_targets, because docs/_targets may not exist yet on a
# first-ever build.
# ---------------------------------------------------------------------------
LOCKDIR="$GIT_DIR_ABS/build.lock.d"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  LOCK_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
  if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "!!! Refusing to start: another scripts/build.sh (PID $LOCK_PID) appears to be" >&2
    echo "!!! running against this store already -- lock: $LOCKDIR" >&2
    echo "!!! Two overlapping tar_make() runs against ONE store is exactly the incident" >&2
    echo "!!! that corrupted docs/_targets/meta/meta and produced issue #730 (a checker" >&2
    echo "!!! fail-open that then silently reported PASS on the truncated result)." >&2
    echo "!!! If PID $LOCK_PID is definitely not running scripts/build.sh (e.g. a stale" >&2
    echo "!!! lock left behind by a killed session), remove $LOCKDIR by hand and re-run." >&2
    echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                   !!!" >&2
    exit 2
  fi
  echo "--- Step 0.5: stale build lock found (PID $LOCK_PID not running) -- removing and retrying ---"
  rm -rf "$LOCKDIR"
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "!!! Could not acquire build lock even after removing a stale one: $LOCKDIR !!!" >&2
    echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                   !!!" >&2
    exit 2
  fi
fi
# Written immediately after mkdir succeeds, before anything else, to
# minimise (not eliminate) the window in which a second, near-simultaneous
# invocation could read an empty pid file and mistake this lock for stale.
echo "$$" > "$LOCKDIR/pid"
echo "--- Step 0.5: build lock acquired (PID $$, $LOCKDIR) ---"
echo ""

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
# Tee to a temp file as well as stdout -- Step 2b (#730) greps this log for
# tar_make()'s OWN verdict ("errored pipeline" / individual "... errored"
# lines) as an independent cross-check against check_pipeline_errors.R's
# tar_meta()-based verdict in Step 2. PIPESTATUS[0] (not plain $?) captures
# the Rscript's own exit code, not tee's -- same pattern already used for
# Step 3's DASHBOARD_LOG below.
TARMAKE_LOG="$(mktemp)"
set +e
nix develop "$REPO_ROOT" --command Rscript -e \
  'targets::tar_make(script = file.path("docs", "_targets.R"), store = file.path("docs", "_targets"))' \
  2>&1 | tee "$TARMAKE_LOG"
TAR_MAKE_STATUS=${PIPESTATUS[0]}
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
# Step 2b (#730): cross-check tar_make()'s OWN verdict (Step 1's log)
# against check_pipeline_errors.R's tar_meta()-based verdict (Step 2). This
# is the check that would have caught #730 on its own: tar_make() printed
# "errored pipeline" while check_pipeline_errors.R -- reading a truncated
# view of a meta file corrupted by two overlapping runs -- printed
# "PASS: no errored targets". Two independent sources of truth disagreeing
# is the strongest signal available; nothing looked for it before.
#
# Deliberately matched on the word "errored" alone, not on tar_make()'s
# exact bullet symbol (cli renders "✖"/"x" for cli::symbol$cross
# depending on the calling terminal's UTF-8 capability, which nix develop
# --command's non-interactive pipe here may or may not report as UTF-8-
# capable) or on the specific phrase "errored pipeline" alone (which misses
# the case where an individual target errors without the whole pipeline
# verdict line surviving truncation). A clean tar_make() run's log does not
# contain the substring "errored" under any known reporter output -- so
# this is symbol/locale-agnostic and, per this script's stated design
# constraint (a false PASS here is worse than a false FAIL), deliberately
# the NOISIER of the two possible false-positive/false-negative trade-offs:
# it will flag on any log line merely mentioning "errored" (e.g. a target's
# own printed message quoting that word), not only the pipeline verdict.
# ---------------------------------------------------------------------------
CROSSCHECK_STATUS=0
if [[ "$CHECK_STATUS" -eq 0 ]] && grep -qi 'errored' "$TARMAKE_LOG" 2>/dev/null; then
  CROSSCHECK_STATUS=1
  echo "--- Step 2b: CROSS-CHECK MISMATCH ---"
  echo "!!! tar_make()'s own log (Step 1) mentions \"errored\", but"
  echo "!!! check_pipeline_errors.R (Step 2) reported no errored targets. These two"
  echo "!!! sources disagree -- treating this as a FAILURE rather than trusting"
  echo "!!! check_pipeline_errors.R's clean verdict on its own (#730)."
  echo "!!! Matching line(s) from the tar_make() log:"
  grep -in 'errored' "$TARMAKE_LOG" 2>/dev/null | sed 's/^/!!!   /'
  echo ""
else
  echo "--- Step 2b: cross-check clean (tar_make() log and check_pipeline_errors.R agree) ---"
  echo ""
fi

# ---------------------------------------------------------------------------
# Step 2.5: scripts/write_targets_meta_snapshot.R (#695 Check 3 CI gap). See
# the header comment above for why this is gated on Step 1 + Step 2 only,
# and why it never commits/pushes. Also gated on Step 2b (#730): a snapshot
# taken while the cross-check disagrees would encode build times read from
# the same meta file the cross-check just found reason to distrust.
# ---------------------------------------------------------------------------
SNAPSHOT_STATUS=0
if [[ "$TAR_MAKE_STATUS" -eq 0 ]] && [[ "$CHECK_STATUS" -eq 0 ]] && [[ "$CROSSCHECK_STATUS" -eq 0 ]]; then
  echo "--- Step 2.5: scripts/write_targets_meta_snapshot.R (#695 Check 3 CI gap) ---"
  set +e
  nix develop "$REPO_ROOT" --command Rscript scripts/write_targets_meta_snapshot.R
  SNAPSHOT_STATUS=$?
  set -e
  echo "--- write_targets_meta_snapshot.R exited $SNAPSHOT_STATUS ---"
  echo ""
else
  echo "--- Step 2.5: skipping metadata snapshot write -- build not clean (tar_make() exit $TAR_MAKE_STATUS, check_pipeline_errors.R exit $CHECK_STATUS, cross-check status $CROSSCHECK_STATUS) ---"
  echo "!!! A snapshot from a store with errored targets -- or a store the cross-check found reason to distrust -- would encode wrong build times -- not writing one. !!!"
  echo ""
fi

# ---------------------------------------------------------------------------
# Step 3: scripts/check_dashboard_freshness.R --data-staleness (#695). Runs
# UNCONDITIONALLY, same reasoning as Step 2: a crashed or partially-errored
# tar_make() (docs/_targets.R sets error = "continue" project-wide) still
# leaves a store with real build times for whatever DID succeed, worth
# checking. This re-runs Check 1 (dead target references) and Check 2
# (source-vs-render staleness) as well as Check 3 (data staleness) -- see
# that script header comment for the full three-check design and why Check
# 3 specifically needs a real store (hence living here, not in
# scripts/verify.sh). Staleness (Check 2/Check 3) is informational-only by
# default (HD_FAIL_ON_STALE_DASHBOARDS=1 escalates it) -- dead references
# (Check 1) are always a hard failure. See that script header for the full
# exit-code contract; the same 0/1/2 meaning is reused here.
# ---------------------------------------------------------------------------
echo "--- Step 3: scripts/check_dashboard_freshness.R --data-staleness (#695) ---"
# Tee to a temp file as well as stdout -- Step 4 (--render) needs to parse
# this output for [STALE]/[DATA-STALE] page names without re-running the
# check a second time. PIPESTATUS[0] (not plain $?) below captures the
# Rscript's own exit code, not tee's. Cleanup is handled by the unified
# _cleanup EXIT trap declared near the top of this script (#730) -- no
# separate trap needed here.
DASHBOARD_LOG="$(mktemp)"
set +e
nix develop "$REPO_ROOT" --command Rscript scripts/check_dashboard_freshness.R --data-staleness 2>&1 | tee "$DASHBOARD_LOG"
DASHBOARD_STATUS=${PIPESTATUS[0]}
set -e
echo "--- check_dashboard_freshness.R --data-staleness exited $DASHBOARD_STATUS ---"
echo ""

# ---------------------------------------------------------------------------
# Final verdict -- printed LAST and kept short, so it is the final thing on
# screen rather than buried 900+ lines up in the tar_make() build log
# (#693). The errored-target/dead-reference/staleness lists were already
# printed by Step 2 and Step 3, directly above this block.
# ---------------------------------------------------------------------------
echo "=== scripts/build.sh: summary ==="
echo "tar_make() exit code:                              $TAR_MAKE_STATUS"
echo "check_pipeline_errors.R exit code:                 $CHECK_STATUS"
echo "cross-check status (tar_make() log vs Step 2, #730): $CROSSCHECK_STATUS"
echo "write_targets_meta_snapshot.R exit code:           $SNAPSHOT_STATUS"
echo "check_dashboard_freshness.R --data-staleness exit: $DASHBOARD_STATUS"
echo ""

if [[ "$CHECK_STATUS" -eq 2 ]]; then
  echo "!!! check_pipeline_errors.R could not run the check at all (no store, or"
  echo "!!! tar_meta() failed) -- see its output above."
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                   !!!"
  exit 2
fi

if [[ "$DASHBOARD_STATUS" -eq 2 ]]; then
  echo "!!! check_dashboard_freshness.R --data-staleness could not run the check at all"
  echo "!!! (no store, tar_manifest()/tar_meta() failed, or a broken extractor) -- see"
  echo "!!! its output above."
  echo "!!! BUILD DID NOT RUN. This is NOT a pass.                                   !!!"
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 4: --render (#695). Only reached once Step 3 is confirmed to have run
# to completion (the two exit-2 checks above already returned for anything
# less). Gated ONLY on tar_make()/check_pipeline_errors.R being clean, per
# this script's header comment -- DASHBOARD_STATUS is deliberately NOT part
# of that gate: Step 3's own [STALE]/[DATA-STALE] output is what tells this
# step WHICH pages to render, so requiring it to already read clean would be
# circular (and staleness is informational-only by default -- see Step 3's
# comment above).
# ---------------------------------------------------------------------------
RENDER_STATUS=0
RENDER_RAN=false
if [[ "$RENDER" == "true" ]]; then
  echo "--- Step 4: --render (#695) ---"
  if [[ "$TAR_MAKE_STATUS" -ne 0 ]] || [[ "$CHECK_STATUS" -ne 0 ]] || [[ "$CROSSCHECK_STATUS" -ne 0 ]]; then
    echo "!!! Skipping --render: build was not clean (tar_make() exit $TAR_MAKE_STATUS,"
    echo "!!! check_pipeline_errors.R exit $CHECK_STATUS, cross-check status"
    echo "!!! $CROSSCHECK_STATUS (#730)). Rendering from a store with errored targets --"
    echo "!!! or one the cross-check found reason to distrust -- would publish wrong"
    echo "!!! numbers into HTML that looks fine -- strictly worse than not rendering at"
    echo "!!! all. Fix the build, then re-run with --render."
    echo ""
  else
    RENDER_RAN=true
    if grep -q '::VERIFY:DASHBOARD_FRESHNESS_STATUS::' "$DASHBOARD_LOG" 2>/dev/null; then
      # Parse Step 3's own stdout for the page names it flagged -- both
      # "  [STALE] <page>.qmd -- ..." (Check 2) and
      # "  [DATA-STALE] <page>.qmd -- ..." (Check 3) lines, per that
      # script's documented output format (see its header comment).
      STALE_PAGES="$(grep -oE '^[[:space:]]+\[(STALE|DATA-STALE)\][[:space:]]+[^[:space:]]+\.qmd' "$DASHBOARD_LOG" | awk '{print $2}' | sort -u)"
    else
      echo "!!! check_dashboard_freshness.R output did not end with its own completion"
      echo "!!! marker (::VERIFY:DASHBOARD_FRESHNESS_STATUS::) -- cannot trust a partial"
      echo "!!! [STALE]/[DATA-STALE] parse. Falling back to rendering ALL docs/*.qmd"
      echo "!!! pages instead of only the stale ones -- more expensive, but never"
      echo "!!! silently renders nothing when the true stale set is unknown."
      STALE_PAGES="$(find "$REPO_ROOT/docs" -maxdepth 1 -name '*.qmd' -exec basename {} \; | sort -u)"
    fi

    if [[ -z "$STALE_PAGES" ]]; then
      echo "No stale dashboards found by Step 3 -- nothing to render."
      echo ""
    else
      N_STALE=$(echo "$STALE_PAGES" | wc -l | tr -d ' ')
      echo "$N_STALE page(s) to render:"
      echo "$STALE_PAGES" | sed 's/^/  - /'
      echo ""
      N_RENDER_OK=0
      N_RENDER_FAILED=0
      while IFS= read -r page; do
        [[ -z "$page" ]] && continue
        qmd_path="docs/$page"
        html_path="docs/${page%.qmd}.html"
        if [[ ! -f "$REPO_ROOT/$qmd_path" ]]; then
          echo "  [SKIP] $page -- $qmd_path not found; cannot render"
          RENDER_STATUS=1
          N_RENDER_FAILED=$((N_RENDER_FAILED + 1))
          continue
        fi
        echo "  --- quarto render $qmd_path ---"
        set +e
        nix develop "$REPO_ROOT" --command quarto render "$qmd_path"
        PAGE_STATUS=$?
        set -e
        if [[ "$PAGE_STATUS" -ne 0 ]]; then
          echo "  [RENDER-FAIL] $page -- quarto render exited $PAGE_STATUS"
          RENDER_STATUS=1
          N_RENDER_FAILED=$((N_RENDER_FAILED + 1))
          continue
        fi
        # Same five patterns verification-before-completion.md's Post-Deploy
        # Validation table checks against the deployed site -- a page can
        # exit 0 from quarto render and still emit NULL/MISSING EVIDENCE
        # where a number belongs.
        N_HITS=0
        for pattern in 'not available' 'not found in targets' 'MISSING EVIDENCE' 'Error in' '#&gt;'; do
          HITS="$(grep -Fc "$pattern" "$REPO_ROOT/$html_path" 2>/dev/null || true)"
          HITS="${HITS:-0}"
          N_HITS=$((N_HITS + HITS))
        done
        if [[ "$N_HITS" -gt 0 ]]; then
          echo "  [RENDER-FAIL] $page -- rendered, but $N_HITS error-pattern hit(s) found in $html_path"
          RENDER_STATUS=1
          N_RENDER_FAILED=$((N_RENDER_FAILED + 1))
        else
          echo "  [OK] $page -- rendered clean (0 error-pattern hits)"
          N_RENDER_OK=$((N_RENDER_OK + 1))
        fi
      done <<< "$STALE_PAGES"
      echo ""
      echo "--- Step 4 summary: $N_RENDER_OK page(s) rendered clean, $N_RENDER_FAILED page(s) failed ---"
      echo "$N_STALE page(s) re-rendered; nothing was committed or pushed -- review the"
      echo "file(s) under docs/ and commit them yourself if they look right."
      echo ""
    fi
  fi
fi

if [[ "$TAR_MAKE_STATUS" -ne 0 ]] || [[ "$CHECK_STATUS" -ne 0 ]] || [[ "$CROSSCHECK_STATUS" -ne 0 ]] || [[ "$SNAPSHOT_STATUS" -ne 0 ]] || [[ "$DASHBOARD_STATUS" -ne 0 ]]; then
  echo "=== scripts/build.sh: FAIL ==="
  if [[ "$CHECK_STATUS" -ne 0 ]]; then
    echo "One or more targets errored -- see the [ERROR] list above."
  fi
  if [[ "$CROSSCHECK_STATUS" -ne 0 ]]; then
    echo "Step 2b cross-check (#730): tar_make()'s own log mentioned \"errored\" while"
    echo "check_pipeline_errors.R reported no errored targets -- see the [Step 2b:"
    echo "CROSS-CHECK MISMATCH] block above. Treat check_pipeline_errors.R's PASS as"
    echo "untrustworthy here; investigate the meta file directly (tar_meta() /"
    echo "docs/_targets/meta/meta) before relying on this build."
  fi
  if [[ "$SNAPSHOT_STATUS" -ne 0 ]]; then
    echo "write_targets_meta_snapshot.R failed to write docs/_targets_meta_snapshot.csv"
    echo "-- see its output above (#695 Check 3 CI gap). CI's Check 3 relies entirely on"
    echo "this committed file; a build that can't produce it leaves that gap open again."
  fi
  if [[ "$DASHBOARD_STATUS" -ne 0 ]]; then
    echo "Dashboard freshness found a problem -- see the [DEAD-REF]/[STALE]/[DATA-STALE]"
    echo "lines above (staleness only fails when HD_FAIL_ON_STALE_DASHBOARDS is set --"
    echo "see scripts/check_dashboard_freshness.R header comment)."
  fi
  if [[ "$TAR_MAKE_STATUS" -ne 0 ]]; then
    echo "tar_make() itself also exited non-zero ($TAR_MAKE_STATUS) -- see the build"
    echo "log above. Even if check_pipeline_errors.R reported no errored targets,"
    echo "a crashed tar_make() means the store may not reflect a complete build --"
    echo "do not treat a clean check_pipeline_errors.R result as a pass on its own."
  fi
  if [[ "$RENDER" == "true" ]] && [[ "$RENDER_RAN" == "false" ]]; then
    echo "--render was requested but skipped -- see Step 4 above."
  fi
  exit 1
fi

if [[ "$RENDER" == "true" ]] && [[ "$RENDER_STATUS" -ne 0 ]]; then
  echo "=== scripts/build.sh: BUILD PASS, RENDER FAIL ==="
  echo "tar_make() and check_pipeline_errors.R are clean, but one or more --render"
  echo "pages failed -- see the [RENDER-FAIL]/[SKIP] line(s) above. This is exit code"
  echo "3, distinct from exit 1 (a build failure): the pipeline and its data are"
  echo "fine, only the republish step for one or more pages is not."
  exit 3
fi

if [[ "$RENDER" == "true" ]]; then
  echo "=== scripts/build.sh: PASS (tar_make() clean, no errored targets, dashboard freshness clean, --render clean) ==="
else
  echo "=== scripts/build.sh: PASS (tar_make() clean, no errored targets, dashboard freshness clean) ==="
fi
exit 0
