#!/usr/bin/env bash
# tests/test_build_lock.sh -- regression tests for scripts/build.sh's Step 0.5
# concurrency lock (#730, and the two bugs fixed on top of it).
#
# Bug A (the headline bug): the trap-visible $LOCKDIR used to be assigned to
# the lock's path BEFORE `mkdir` was attempted, so a REFUSED invocation (one
# that detects a live build already holds the lock and exits 2) still had
# $LOCKDIR populated -- and the EXIT trap unconditionally rm -rf's a non-empty
# $LOCKDIR. A refused invocation therefore deleted the lock the live build
# still held, silently defeating the guard: retrying after the refusal would
# then race the live build for real, which is exactly the corruption #730's
# lock exists to prevent.
#
# Bug B: the liveness check (`kill -0 "$LOCK_PID" 2>/dev/null`) cannot
# distinguish EPERM ("process exists, not ours to signal") from ESRCH ("no
# such process") -- both give a non-zero exit, both used to read as "not
# running". A live-but-unsignallable PID (e.g. PID 1 / launchd, or any lock
# left by another user) was therefore treated as dead and its lock silently
# reclaimed.
#
# These tests exercise the REAL scripts/build.sh, copied verbatim into a
# throwaway scratch git repo (never the real repo, never the real
# docs/_targets store -- see .claude/CLAUDE.md "Verifying a change" and the
# `destructive-ops-guard` rule). The scratch repo has no flake.nix, so
# `nix develop` fails immediately at the pre-flight check that runs right
# after Step 0.5 -- deterministic and near-instant, unlike a real build,
# which is exactly what lets these tests run in well under a second each
# instead of a 10+ minute cold nix build. What is stubbed: everything from
# the nix pre-flight onward (Steps 1-4: tar_make(), check_pipeline_errors.R,
# the metadata snapshot, --render). Nothing about Step 0.5 itself -- lock
# path resolution, mkdir, the liveness check, the EXIT trap -- is stubbed;
# it is the actual code in scripts/build.sh, unmodified, run as a subprocess.
#
# Usage: bash tests/test_build_lock.sh
# Exit code: 0 if all tests pass, 1 if any test fails.

set -uo pipefail  # deliberately NOT -e: test bodies check exit codes by hand

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg (got $actual)"
  else
    fail "$msg (expected $expected, got $actual)"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$msg"
  else
    fail "$msg (did not find: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$msg"
  else
    fail "$msg (unexpectedly found: $needle)"
  fi
}

# Sets up a throwaway git repo with a minimal `_targets.R` (so build.sh's
# "is this a valid checkout" check passes) and its own copy of the real
# scripts/build.sh (so REPO_ROOT inside that subprocess resolves to the
# scratch repo, never to $REPO_ROOT). No flake.nix is created on purpose --
# see file header. Prints the scratch dir path on stdout.
setup_scratch_repo() {
  local dir
  dir="$(mktemp -d)"
  git init -q "$dir"
  touch "$dir/_targets.R"
  mkdir -p "$dir/scripts"
  cp "$BUILD_SH" "$dir/scripts/build.sh"
  chmod +x "$dir/scripts/build.sh"
  echo "$dir"
}

echo "=== tests/test_build_lock.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1 (regression test for Bug A): a refused invocation must NOT delete
# the lock the live build still holds. This is the test that must FAIL
# against the pre-fix code and PASS against the fix -- see the manual
# before/after run in the PR description for the demonstration.
# ---------------------------------------------------------------------------
echo "--- Test 1: lock survives a refusal ---"
scratch="$(setup_scratch_repo)"
lockdir="$scratch/.git/build.lock.d"
mkdir -p "$lockdir"

# A genuinely live, same-user, long-running process to act as the lock owner.
sleep 300 &
live_pid=$!
echo "$live_pid" > "$lockdir/pid"

out="$("$scratch/scripts/build.sh" 2>&1)"
status=$?

kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null

assert_eq "$status" 2 "refused invocation exits 2"
assert_contains "$out" "Refusing to start" "refusal message printed"
if [[ -d "$lockdir" ]]; then
  pass "lock directory still exists after the refused invocation exited"
else
  fail "lock directory was deleted by the refused invocation -- THE BUG"
fi
rm -rf "$scratch"
echo ""

# ---------------------------------------------------------------------------
# Test 2: a genuinely stale lock (dead PID) is still reclaimed and the build
# proceeds -- must not regress while fixing Test 1.
# ---------------------------------------------------------------------------
echo "--- Test 2: stale lock is reclaimed ---"
scratch="$(setup_scratch_repo)"
lockdir="$scratch/.git/build.lock.d"
mkdir -p "$lockdir"

# A PID guaranteed to be dead: spawn a no-op subshell and wait for it to
# exit and be reaped, so `kill -0` on it reports ESRCH.
( : ) &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
echo "$dead_pid" > "$lockdir/pid"

out="$("$scratch/scripts/build.sh" 2>&1)"
status=$?

assert_contains "$out" "stale build lock found" "stale-lock message printed"
assert_not_contains "$out" "Refusing to start" "did not refuse on a dead PID"
assert_contains "$out" "Step 0.5: build lock acquired" "lock re-acquired after reclaim"
# The scratch repo has no flake.nix, so the run fails at the nix pre-flight
# step that immediately follows Step 0.5 -- see file header. Exit 2 here
# reflects that stub, not a Step 0.5 refusal (already asserted above).
assert_eq "$status" 2 "run proceeds past Step 0.5, then fails at the (stubbed) nix pre-flight"
rm -rf "$scratch"
echo ""

# ---------------------------------------------------------------------------
# Test 3: a run that acquires its own lock releases it on exit (the EXIT
# trap still works correctly after the Bug A fix -- LOCKDIR IS populated
# once ownership is actually claimed).
# ---------------------------------------------------------------------------
echo "--- Test 3: own lock is released on exit ---"
scratch="$(setup_scratch_repo)"
lockdir="$scratch/.git/build.lock.d"

out="$("$scratch/scripts/build.sh" 2>&1)"
status=$?

assert_contains "$out" "Step 0.5: build lock acquired" "lock acquired (no pre-existing lock)"
if [[ -d "$lockdir" ]]; then
  fail "lock directory was NOT released after the run exited"
else
  pass "lock directory released after the run exited"
fi
rm -rf "$scratch"
echo ""

# ---------------------------------------------------------------------------
# Test 4 (regression test for Bug B): a PID that exists but cannot be
# signalled (EPERM) must be treated as ALIVE, not reclaimed. PID 1 (launchd
# on macOS, init on Linux) is always running and never signallable by an
# unprivileged user.
# ---------------------------------------------------------------------------
echo "--- Test 4: EPERM (PID 1) is treated as alive, not reclaimed ---"
scratch="$(setup_scratch_repo)"
lockdir="$scratch/.git/build.lock.d"
mkdir -p "$lockdir"
echo "1" > "$lockdir/pid"

out="$("$scratch/scripts/build.sh" 2>&1)"
status=$?

assert_eq "$status" 2 "refused invocation exits 2"
assert_contains "$out" "Refusing to start" "refusal message printed for PID 1"
assert_not_contains "$out" "stale build lock found" "PID 1 not treated as stale"
if [[ -d "$lockdir" ]]; then
  pass "lock directory (owned by PID 1) still exists"
else
  fail "lock directory was deleted -- PID 1 was wrongly treated as dead"
fi
rm -rf "$scratch"
echo ""

echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
