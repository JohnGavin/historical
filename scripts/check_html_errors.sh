#!/usr/bin/env bash
# scripts/check_html_errors.sh -- trustworthy rendered-HTML error-pattern
# check (#740).
#
# WHY THIS EXISTS: scripts/build.sh Step 4 (--render) and the manual
# Post-Deploy Validation procedure in verification-before-completion.md both
# grep rendered docs/*.qmd -> .html output for reader-visible defects.
# Applied naively -- case-insensitive, against raw markup, matching "NaN" --
# that grep false-positives THREE separate ways (#740, reproduced on the live
# 2026-08-24 site):
#
#   1. Case-insensitive "NaN" matches inside ordinary words: "financial"
#      contains "nan". A case-INsensitive scan of docs/european-overlay.html
#      alone hit this.
#   2. Vendored, minified third-party JS emits "Error:"-shaped tokens that
#      have nothing to do with the page's own R output -- DataTables' own
#      internal `iDrawError:-1` matches the literal pattern "Error:". This
#      lives inside <script> blocks.
#   3. Base64-encoded `data:` URIs (embedded webfonts, images) can contain the
#      literal substring "NaN" BY CHANCE -- 'N', 'a', 'n' are all valid
#      base64-alphabet characters, so a long enough blob eventually produces
#      every 3-character combination somewhere.
#
# On docs/macro-defense-rotation.html specifically, the naive check (grep -i,
# no stripping) reported 38 hits; case-sensitive matching cut it to 18;
# stripping <script>/<style> cut it to 5; every one of those 5 remaining hits
# was inside a base64 font data: URI. True count: zero.
#
# This script is now the ONE place that check lives. scripts/build.sh Step 4
# calls it per rendered page instead of hand-rolling its own grep loop, and
# anyone re-running the manual Post-Deploy Validation procedure by hand should
# call this instead of retyping the pattern list.
#
# DESIGN TRADE-OFF (deliberate): favour a false positive over a false
# negative. Stripping <script>, <style>, and data: URI payloads removes ONLY
# markup that can never be the page's own rendered R output (vendored library
# code, embedded binary blobs) -- it never touches rendered prose, table
# cells, or captions a reader would actually see. A real "Error in ..." or a
# genuine computed NaN sitting in a table cell is untouched by any of the
# three strip rules above and is still caught. NULL and bare "NA" are
# deliberately NOT included in the pattern list below (unlike the fuller
# table in verification-before-completion.md's Post-Deploy Validation
# section) -- both are short, extremely common substrings of ordinary English
# words and identifiers ("NAME", "ANALYSIS", "NATIONAL", "NULLify") with no
# tag/word-boundary rule that reliably separates a real defect from an
# ordinary word, so adding them un-bounded would reintroduce exactly the
# class of false positive this script exists to remove. If a computation ever
# needs to be checked for a literal NULL/NA render defect, that is better done
# with a narrower, page-specific assertion (e.g. `expect_snapshot_value()` on
# the target itself, per snapshot-test-policy) than a repo-wide grep.
#
# Usage:
#   scripts/check_html_errors.sh <html-file> [<html-file> ...]
#   scripts/check_html_errors.sh --all
#     Checks every docs/*.html file that has a same-named docs/*.qmd source.
#     docs/MERMAID_LESSONS.html is DELIBERATELY EXCLUDED by --all: it renders
#     from docs/MERMAID_LESSONS.md (not a .qmd), is not one of the 15
#     dashboard pages scripts/build.sh's Step 3/Step 4 cover, and -- being a
#     lessons-learned page -- legitimately discusses real historical errors
#     as its actual subject matter. A reader passing it explicitly as a named
#     file argument still gets it checked; --all just never adds it on its
#     own.
#
# Exit codes:
#   0  every file checked has zero pattern hits
#   1  at least one file has one or more pattern hits (see the per-file,
#      per-pattern table printed above the summary line)
#   2  usage error, or --all found no docs/*.qmd -> docs/*.html pairs to check

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Patterns per verification-before-completion.md's Post-Deploy Validation
# table, minus NULL/bare NA (see DESIGN TRADE-OFF above), plus #740's NaN
# addition. Matched CASE-SENSITIVELY, after stripping <script>, <style>, and
# data: URI payloads (see strip_html below) -- see file header for why each
# of those three steps is necessary and why together they are still the
# stricter (favours-false-positive) trade-off, not a looser one.
PATTERNS=(
  'not available'
  'not found in targets'
  'MISSING EVIDENCE'
  'Error in'
  'Error:'
  '#&gt;'
  'NaN'
)

usage() {
  echo "Usage: $0 <html-file> [<html-file> ...]" >&2
  echo "       $0 --all" >&2
  exit 2
}

if [[ $# -eq 0 ]]; then
  usage
fi

FILES=()
if [[ "$1" == "--all" ]]; then
  while IFS= read -r qmd; do
    page="$(basename "$qmd" .qmd)"
    html="$REPO_ROOT/docs/${page}.html"
    if [[ -f "$html" ]]; then
      FILES+=("$html")
    fi
  done < <(find "$REPO_ROOT/docs" -maxdepth 1 -name '*.qmd' | sort)
else
  for f in "$@"; do
    FILES+=("$f")
  done
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "!!! No HTML files to check (no docs/*.qmd -> docs/*.html pairs found) !!!" >&2
  exit 2
fi

# strip_html <path> -- prints the file's content to stdout with <script>,
# <style>, and data: URI payloads removed. Case-insensitive, DOTALL (a
# vendored <script> block routinely spans many lines). Uses python3 (present
# on the bare macOS PATH and in CI runners without needing the project's nix
# shell -- this check has nothing to do with R) because portable
# case-insensitive multi-line removal is awkward in pure sed/awk/grep.
strip_html() {
  python3 - "$1" <<'PYEOF'
import re, sys
with open(sys.argv[1], "r", errors="replace") as fh:
    src = fh.read()
clean = re.sub(r'<script\b[^>]*>.*?</script>', '', src, flags=re.S | re.I)
clean = re.sub(r'<style\b[^>]*>.*?</style>', '', clean, flags=re.S | re.I)
# data: URIs are embedded inside an attribute (src="data:...") or a CSS
# url(data:...) -- stop at whichever quote/paren closes the value. Base64's
# alphabet has no '"', "'", or ')' characters, so this bound is exact, never
# eating past the payload into real surrounding markup.
clean = re.sub(r'data:[^"\')]*', '', clean, flags=re.S | re.I)
sys.stdout.write(clean)
PYEOF
}

TOTAL_HITS=0
ANY_FAIL=0

printf "%-30s" "Page"
for p in "${PATTERNS[@]}"; do
  printf " %10s" "$p"
done
printf " %8s\n" "TOTAL"

for html in "${FILES[@]}"; do
  page="$(basename "$html" .html)"
  stripped="$(mktemp)"
  strip_html "$html" > "$stripped"

  row_total=0
  counts=()
  for p in "${PATTERNS[@]}"; do
    hits="$(grep -Fc -- "$p" "$stripped" 2>/dev/null || true)"
    hits="${hits:-0}"
    counts+=("$hits")
    row_total=$((row_total + hits))
  done
  rm -f "$stripped"

  printf "%-30s" "$page"
  for c in "${counts[@]}"; do
    printf " %10d" "$c"
  done
  printf " %8d\n" "$row_total"

  TOTAL_HITS=$((TOTAL_HITS + row_total))
  if [[ "$row_total" -gt 0 ]]; then
    ANY_FAIL=1
  fi
done

echo ""
if [[ "$ANY_FAIL" -ne 0 ]]; then
  echo "RESULT: FAIL -- $TOTAL_HITS error-pattern hit(s) found across ${#FILES[@]} page(s)"
  echo "  (case-sensitive match; <script>/<style>/data: URI stripped -- #740)"
  echo "::VERIFY:HTML_ERRORS_STATUS::FAIL::"
  exit 1
else
  echo "RESULT: PASS -- 0 error-pattern hits across ${#FILES[@]} page(s)"
  echo "  (case-sensitive match; <script>/<style>/data: URI stripped -- #740)"
  echo "::VERIFY:HTML_ERRORS_STATUS::PASS::"
  exit 0
fi
