#!/usr/bin/env bash
# Run devtools::check() inside the project's nix develop shell
# Usage: bash scripts/check_in_nix.sh [pkg_path]
#
# This solves the ABI mismatch problem: compiled R packages (glmnet, duckdb)
# segfault when loaded from a different nix shell than they were built in.
# Running check inside nix develop ensures the correct R binary and libs.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_PATH="${1:-packages/historicaldata}"

echo "=== R CMD check inside nix develop ==="
echo "Project: $PROJECT_ROOT"
echo "Package: $PKG_PATH"
echo ""

nix develop "$PROJECT_ROOT" --command bash -c "
  cd '$PROJECT_ROOT'
  Rscript -e '
    cat(\"R:\", R.version.string, \"\n\")
    cat(\"glmnet:\", as.character(packageVersion(\"glmnet\")), \"\n\")
    res <- devtools::check(pkg = \"$PKG_PATH\", error_on = \"never\")
    cat(\"\n=== RESULT ===\", res\$status, \"\n\")
    if (res\$status != 0) quit(status = 1)
  '
"
