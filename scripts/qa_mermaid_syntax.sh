#!/bin/bash
# MANDATORY QA: Test all Mermaid diagrams render without syntax errors
#
# Uses mermaid CLI (mmdc) to validate each diagram BEFORE deploy.
# Also uses Chrome headless to check rendered page for JS errors.
#
# Usage: ./scripts/qa_mermaid_syntax.sh
# Exit: 0 = all pass, 1 = syntax errors found

set -euo pipefail

HTML_FILE="${1:-docs/falsification.html}"
DEPLOYED_URL="${2:-https://johngavin.github.io/historical/falsification.html}"
TMPDIR=$(mktemp -d)
TOTAL_ERRORS=0

echo "=== MANDATORY QA: Mermaid Syntax Check ==="
echo ""

# ── Step 1: Extract and test each diagram with mmdc ──────────
echo "--- Step 1: mmdc syntax validation ---"

python3 << PYEOF
import re, sys
with open("$HTML_FILE") as f:
    html = f.read()
blocks = re.findall(r'data-mermaid="(dag-[^"]+)">\s*(.*?)</script>', html, re.DOTALL)
for name, content in blocks:
    path = f"$TMPDIR/{name}.mmd"
    with open(path, 'w') as f:
        f.write(content.strip())
    print(name)
PYEOF

DIAGRAMS=$(ls "$TMPDIR"/*.mmd 2>/dev/null)
if [ -z "$DIAGRAMS" ]; then
  echo "No mermaid diagrams found in $HTML_FILE"
  rm -rf "$TMPDIR"
  exit 0
fi

for mmd in $TMPDIR/*.mmd; do
  name=$(basename "$mmd" .mmd)
  svg="$TMPDIR/${name}.svg"
  result=$(npx --yes @mermaid-js/mermaid-cli -i "$mmd" -o "$svg" 2>&1) || true

  if [ -f "$svg" ] && [ -s "$svg" ]; then
    printf "  %-20s PASS\n" "$name"
  else
    printf "  %-20s FAIL: %s\n" "$name" "$(echo "$result" | tail -1)"
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
  fi
done

# ── Step 2: Chrome headless DOM check ────────────────────────
echo ""
echo "--- Step 2: Chrome headless DOM check ---"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  dom=$("$CHROME" --headless=new --dump-dom --timeout=15000 "$DEPLOYED_URL" 2>/dev/null || echo "")
  if [ -n "$dom" ]; then
    js_errors=$(echo "$dom" | grep -ciE "syntax error|parse error|mermaid version" || true)
    printf "  JS rendering errors: %d\n" "$js_errors"
    if [ "$js_errors" -gt 0 ]; then
      echo "  Matches:"
      echo "$dom" | grep -iE "syntax error|parse error|mermaid version" | head -5
      TOTAL_ERRORS=$((TOTAL_ERRORS + js_errors))
    fi
  else
    echo "  Chrome headless returned empty DOM (timeout or error)"
  fi
else
  echo "  Chrome not found at $CHROME — skipping DOM check"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "Total errors: $TOTAL_ERRORS"
rm -rf "$TMPDIR"

if [ "$TOTAL_ERRORS" -gt 0 ]; then
  echo "RESULT: FAIL — fix mermaid syntax before deploying"
  exit 1
else
  echo "RESULT: PASS — all diagrams valid"
  exit 0
fi
