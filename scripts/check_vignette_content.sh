#!/usr/bin/env bash
# Post-render content validation for vignettes
# Detects fallback/placeholder content that shouldn't appear in production
#
# Source: JohnGavin/historical#99
# Related: quarto-vignette-validation rule

set -euo pipefail

# Default to docs/ directory unless specified
DOCS_DIR="${1:-docs}"

if [ ! -d "$DOCS_DIR" ]; then
  echo "No $DOCS_DIR directory found, skipping vignette content validation"
  exit 0
fi

echo "=== Vignette Content Validation ==="
echo "Checking $DOCS_DIR for fallback/placeholder content..."

# Fallback patterns that indicate missing data or failed targets
FALLBACK_PATTERNS=(
  "Data not available"
  "Run tar_make"
  "target not found"
  "Error in tar_read"
  "could not find function"
  "object .* not found"
)

# Build grep pattern
PATTERN=$(IFS='|'; echo "${FALLBACK_PATTERNS[*]}")

# Find HTML files with fallback content
PROBLEM_FILES=()
while IFS= read -r file; do
  if grep -qE "$PATTERN" "$file" 2>/dev/null; then
    PROBLEM_FILES+=("$file")
  fi
done < <(find "$DOCS_DIR" -name "*.html" -type f)

# Report results
if [ ${#PROBLEM_FILES[@]} -eq 0 ]; then
  echo "✓ No fallback content detected in ${DOCS_DIR}"
  exit 0
fi

echo "✗ ERROR: ${#PROBLEM_FILES[@]} file(s) contain fallback/placeholder content:"
echo ""

for file in "${PROBLEM_FILES[@]}"; do
  echo "  - $(basename "$file")"
  # Show the specific fallback messages found
  grep -nE "$PATTERN" "$file" | head -3 | sed 's/^/    /'
  echo ""
done

echo "Fallback content indicates:"
echo "  - Missing targets (run tar_make() to build)"
echo "  - Failed data loads (check target dependencies)"
echo "  - Defensive fallback messages that shouldn't appear in production"
echo ""
echo "Fix by ensuring all required targets are built before quarto render."

exit 1
