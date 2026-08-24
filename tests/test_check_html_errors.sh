#!/usr/bin/env bash
# tests/test_check_html_errors.sh -- regression tests for
# scripts/check_html_errors.sh (#740).
#
# #740 documented three independent ways a naive grep for error patterns
# false-positives against real rendered dashboard HTML:
#   1. case-insensitive "NaN" matches inside ordinary words ("financial")
#   2. vendored minified JS emits "Error:"-shaped tokens inside <script>
#      blocks (DataTables' own iDrawError:-1)
#   3. base64 data: URIs can contain the literal substring "NaN" by chance
#
# These tests build small HTML fixtures reproducing each source in
# isolation, plus a fixture with a genuine defect that must still be caught
# (the false-positive fixes must not become false negatives -- #740's stated
# design trade-off is to favour a false positive over a false negative).
#
# Usage: bash tests/test_check_html_errors.sh
# Exit code: 0 if all tests pass, 1 if any test fails.

set -uo pipefail  # deliberately NOT -e: test bodies check exit codes by hand

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check_html_errors.sh"

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

echo "=== tests/test_check_html_errors.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: case-insensitive "NaN" inside an ordinary word ("financial") must
# NOT be flagged -- source 1 from #740.
# ---------------------------------------------------------------------------
echo "--- Test 1: 'financial' does not trigger a NaN false positive ---"
f1="$(mktemp /tmp/check_html_errors_test1.XXXXXX.html)"
printf '<html><body><p>The financial results are strong.</p></body></html>' > "$f1"
"$CHECKER" "$f1" > /dev/null 2>&1
assert_eq "$?" 0 "'financial' (lowercase nan) alone: clean exit"
rm -f "$f1"
echo ""

# ---------------------------------------------------------------------------
# Test 2: an "Error:"-shaped token inside a <script> block (vendored JS) must
# NOT be flagged -- source 2 from #740.
# ---------------------------------------------------------------------------
echo "--- Test 2: vendored <script> 'Error:' token does not trigger a false positive ---"
f2="$(mktemp /tmp/check_html_errors_test2.XXXXXX.html)"
printf '<html><head><script>function f(){ iDrawError:-1; }</script></head><body><p>OK</p></body></html>' > "$f2"
"$CHECKER" "$f2" > /dev/null 2>&1
assert_eq "$?" 0 "vendored <script> 'Error:' token alone: clean exit"
rm -f "$f2"
echo ""

# ---------------------------------------------------------------------------
# Test 3: a base64 data: URI containing the literal substring "NaN" by
# chance must NOT be flagged -- source 3 from #740. 'N', 'a', 'n' are all
# valid base64-alphabet characters, so a long enough blob can contain "NaN"
# with no meaning at all; the fixture string "AAAANaNBBBB==" is deliberately
# constructed to contain the literal 3-character substring "NaN" (asserted
# below) purely as base64-alphabet noise.
# ---------------------------------------------------------------------------
echo "--- Test 3: base64 data: URI containing literal 'NaN' does not trigger a false positive ---"
f3="$(mktemp /tmp/check_html_errors_test3.XXXXXX.html)"
printf '<html><body><img src="data:font/woff;base64,AAAANaNBBBB=="></body></html>' > "$f3"
if ! grep -q "NaN" "$f3"; then
  fail "Test 3 fixture setup: does not contain literal 'NaN' -- test is invalid"
else
  "$CHECKER" "$f3" > /dev/null 2>&1
  assert_eq "$?" 0 "base64 data: URI containing 'NaN': clean exit"
fi
rm -f "$f3"
echo ""

# ---------------------------------------------------------------------------
# Test 4 (regression guard): a genuine defect in rendered TEXT -- not inside
# <script>/<style>/data: -- MUST still be caught. The false-positive fixes
# above must not become false negatives.
# ---------------------------------------------------------------------------
echo "--- Test 4: a genuine 'Error in' + NaN defect in body text is still caught ---"
f4="$(mktemp /tmp/check_html_errors_test4.XXXXXX.html)"
printf '<html><body><p>Genuine defect: Error in compute_thing(): argument is NaN</p></body></html>' > "$f4"
out4="$("$CHECKER" "$f4" 2>&1)"
status4=$?
assert_eq "$status4" 1 "genuine defect: FAIL exit code"
assert_contains "$out4" "RESULT: FAIL" "genuine defect: FAIL result line printed"
rm -f "$f4"
echo ""

# ---------------------------------------------------------------------------
# Test 5: all three false-positive sources combined in one fixture, plus one
# genuine defect -- exercises stripping order does not interfere across
# sources, and the genuine defect is still the only thing counted.
# ---------------------------------------------------------------------------
echo "--- Test 5: combined fixture -- 3 false-positive sources suppressed, 1 genuine defect caught ---"
f5="$(mktemp /tmp/check_html_errors_test5.XXXXXX.html)"
{
  echo '<html><head>'
  echo '<style>.foo{background:#fff}</style>'
  echo '<script>function f(){ iDrawError:-1; }</script>'
  echo '</head><body>'
  echo '<p>The financial results are strong.</p>'
  echo '<img src="data:font/woff;base64,AAAANaNBBBB==">'
  echo '<p>Genuine defect: Error in compute_thing(): argument is NaN</p>'
  echo '</body></html>'
} > "$f5"
out5="$("$CHECKER" "$f5" 2>&1)"
status5=$?
assert_eq "$status5" 1 "combined fixture: FAIL exit code (genuine defect present)"
# Exactly 2 hits expected: one "Error in", one "NaN" -- both from the
# genuine-defect line. Everything else in the fixture must be suppressed.
assert_contains "$out5" "FAIL -- 2 error-pattern hit(s)" "combined fixture: exactly 2 hits (not 3+ from false positives)"
rm -f "$f5"
echo ""

# ---------------------------------------------------------------------------
# Test 6: usage errors.
# ---------------------------------------------------------------------------
echo "--- Test 6: usage errors ---"
"$CHECKER" > /dev/null 2>&1
assert_eq "$?" 2 "no arguments: exit 2"
"$CHECKER" --all --this-is-not-a-thing > /dev/null 2>&1
# --all with extra args is still treated as --all (ignores trailing args) --
# this just confirms it does not crash; the real --all path is exercised
# against the repo's own docs/ tree in Test 7.
echo ""

# ---------------------------------------------------------------------------
# Test 7: --all finds the repo's docs/*.qmd -> docs/*.html pairs and
# excludes MERMAID_LESSONS.html (no corresponding .qmd).
# ---------------------------------------------------------------------------
echo "--- Test 7: --all enumerates docs/*.qmd -> docs/*.html pairs ---"
out7="$("$CHECKER" --all 2>&1)"
if echo "$out7" | grep -q "No HTML files to check"; then
  echo "  SKIP: no docs/*.html files present in this checkout (worktree may not have rendered output)"
elif echo "$out7" | grep -qi "MERMAID_LESSONS"; then
  fail "--all must not include MERMAID_LESSONS.html (no corresponding .qmd)"
else
  pass "--all correctly excludes MERMAID_LESSONS.html"
fi
echo ""

echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
