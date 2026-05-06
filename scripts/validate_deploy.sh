#!/bin/bash
# Post-deploy validation: check published HTML for common defects
#
# Usage: ./scripts/validate_deploy.sh [URL_BASE]
# Default URL: https://johngavin.github.io/historical
#
# Also works on local files:
#   LOCAL=1 ./scripts/validate_deploy.sh
#
# Exit codes: 0 = all clean, 1 = issues found

set -euo pipefail

URL_BASE="${1:-https://johngavin.github.io/historical}"
LOCAL="${LOCAL:-0}"

# Pages to check
PAGES=(falsification leaderboard quiz negative-results)

echo "=== Post-Deploy Validation ==="
echo "Base: $URL_BASE"
echo ""

TOTAL_ISSUES=0

printf "%-20s %7s %7s %7s %7s %7s %7s %7s %7s\n" \
  "Page" "Leaked" "TarRead" "NotAvl" "Error" "NULL" "RawTbl" "Syntax" "BrkImg"
printf "%-20s %7s %7s %7s %7s %7s %7s %7s %7s\n" \
  "----" "------" "-------" "------" "-----" "----" "------" "------" "------"

for page in "${PAGES[@]}"; do
  if [ "$LOCAL" = "1" ]; then
    content=$(cat "docs/${page}.html" 2>/dev/null || echo "")
  else
    content=$(curl -s "${URL_BASE}/${page}.html" 2>/dev/null || echo "")
  fi

  if [ -z "$content" ]; then
    printf "%-20s %7s\n" "$page" "MISSING"
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
    continue
  fi

  leaked=$(echo "$content" | grep -c '#| label\|#| echo\|#| results' || true)
  tar_read=$(echo "$content" | grep -c 'safe_tar_read\|tar_read(' || true)
  not_avail=$(echo "$content" | grep -ci 'not yet built\|not available\|MISSING EVIDENCE' || true)
  errors=$(echo "$content" | grep -c 'Error in \|Error:' || true)
  nulls=$(echo "$content" | grep -c '>NULL<\|> NULL<' || true)
  raw_tbl=$(echo "$content" | grep -c 'class="dataframe"' || true)
  syntax_err=$(echo "$content" | grep -ci 'Syntax error\|Parse error\|mermaid version' || true)
  broken_img=$(echo "$content" | grep -ci 'broken-image\|img-error\|onerror' || true)

  issues=$((leaked + tar_read + not_avail + errors + nulls + raw_tbl + syntax_err + broken_img))
  TOTAL_ISSUES=$((TOTAL_ISSUES + issues))

  status="OK"
  [ "$issues" -gt 0 ] && status="FAIL"

  printf "%-20s %7d %7d %7d %7d %7d %7d %7d %7d  %s\n" \
    "$page" "$leaked" "$tar_read" "$not_avail" "$errors" "$nulls" "$raw_tbl" "$syntax_err" "$broken_img" "$status"
done

echo ""
echo "Total issues: $TOTAL_ISSUES"

if [ "$TOTAL_ISSUES" -gt 0 ]; then
  echo "RESULT: FAIL — fix issues before deployment is considered clean"
  exit 1
else
  echo "RESULT: PASS — all pages clean"
  exit 0
fi
