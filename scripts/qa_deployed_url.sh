#!/bin/bash
# MANDATORY QA: grep deployed GH Pages URL for 'error' and other defects
#
# Run AFTER every deploy. Must pass before claiming success.
# Usage: ./scripts/qa_deployed_url.sh [URL_BASE]
# Local: LOCAL=1 ./scripts/qa_deployed_url.sh

set -euo pipefail

URL_BASE="${1:-https://johngavin.github.io/historical}"
LOCAL="${LOCAL:-0}"
PAGES=(falsification leaderboard quiz negative-results)

echo "=== MANDATORY QA: Deployed URL Check ==="
echo "Base: $URL_BASE"
echo ""

TOTAL=0

printf "%-20s %6s %6s %6s %6s %6s %6s %6s %6s %6s\n" \
  "Page" "error" "Error" "Syntax" "NULL" "Leaked" "TarRd" "NotAvl" "RawTbl" "BrkImg"
printf "%-20s %6s %6s %6s %6s %6s %6s %6s %6s %6s\n" \
  "----" "-----" "-----" "------" "----" "------" "-----" "------" "------" "------"

for page in "${PAGES[@]}"; do
  if [ "$LOCAL" = "1" ]; then
    c=$(cat "docs/${page}.html" 2>/dev/null || echo "")
  else
    c=$(curl -s --compressed "${URL_BASE}/${page}.html" 2>/dev/null || echo "")
  fi

  if [ -z "$c" ]; then
    printf "%-20s %6s\n" "$page" "MISSING"
    TOTAL=$((TOTAL + 1))
    continue
  fi

  # 'error' (case-insensitive) excluding known safe patterns
  tmpf=$(mktemp)
  echo "$c" > "$tmpf"
  err_lower=$(grep -i "error" "$tmpf" | grep -civE "error-continue|errorbar|stderr|Type I|inflates|error_patterns|error =|tar_option|cue.*error|jog.lua" || true)
  rm -f "$tmpf"
  err_upper=$(echo "$c" | grep -c "Error in \|Error:" || true)
  syntax=$(echo "$c" | grep -ci "Syntax error\|Parse error\|mermaid version" || true)
  nulls=$(echo "$c" | grep -c ">NULL<\|> NULL<" || true)
  leaked=$(echo "$c" | grep -c "#| label\|#| echo\|#| results" || true)
  tar_rd=$(echo "$c" | grep -c "safe_tar_read\|tar_read(" || true)
  not_avl=$(echo "$c" | grep -ci "not yet built\|not available\|MISSING EVIDENCE" || true)
  raw_tbl=$(echo "$c" | grep -c 'class="dataframe"' || true)
  brk_img=$(echo "$c" | grep -ci "broken-image\|img-error" || true)

  issues=$((err_lower + err_upper + syntax + nulls + leaked + tar_rd + not_avl + raw_tbl + brk_img))
  TOTAL=$((TOTAL + issues))

  s="OK"
  [ "$issues" -gt 0 ] && s="FAIL"

  printf "%-20s %6d %6d %6d %6d %6d %6d %6d %6d %6d  %s\n" \
    "$page" "$err_lower" "$err_upper" "$syntax" "$nulls" "$leaked" "$tar_rd" "$not_avl" "$raw_tbl" "$brk_img" "$s"
done

echo ""
echo "Total issues: $TOTAL"

if [ "$TOTAL" -gt 0 ]; then
  echo "RESULT: FAIL — DO NOT claim deploy is working"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
