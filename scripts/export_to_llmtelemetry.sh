#!/usr/bin/env bash
# export_to_llmtelemetry.sh — Export historical project metrics to llmtelemetry dashboard
#
# Reads selected targets from docs/_targets/objects/ and writes JSON to
# ~/docs_gh/llmtelemetry/vignettes/data/historical/.
#
# Usage:
#   ./scripts/export_to_llmtelemetry.sh           # normal run
#   DRY_RUN=1 ./scripts/export_to_llmtelemetry.sh # skip commit + push
#
# Mirrors the pattern in ~/.claude/scripts/export_and_deploy_data.sh used by the
# llm project. Run at session-end (or manually) to keep the telemetry dashboard
# current.

set -euo pipefail

PROJ_ROOT="/Users/johngavin/docs_gh/proj/finance/data/historical"
TELEMETRY_REPO="$HOME/docs_gh/llmtelemetry"
HIST_DATA_DIR="$TELEMETRY_REPO/vignettes/data/historical"
TARGETS_STORE="$PROJ_ROOT/docs/_targets"
DRY_RUN="${DRY_RUN:-0}"

echo "HISTORICAL TELEMETRY: starting export (dry_run=$DRY_RUN)"
echo "HISTORICAL TELEMETRY: source store = $TARGETS_STORE"
echo "HISTORICAL TELEMETRY: dest = $HIST_DATA_DIR"

# ── Sanity checks ────────────────────────────────────────────────────────────

if [ ! -d "$TELEMETRY_REPO/.git" ]; then
  echo "HISTORICAL TELEMETRY: llmtelemetry repo not found at $TELEMETRY_REPO — skipping"
  exit 0
fi

if [ ! -d "$TARGETS_STORE/objects" ]; then
  echo "HISTORICAL TELEMETRY: targets store not found at $TARGETS_STORE — run tar_make() first"
  exit 1
fi

# Check that leaderboard object exists (proxy for a built pipeline)
if [ ! -e "$TARGETS_STORE/objects/leaderboard" ]; then
  echo "HISTORICAL TELEMETRY: leaderboard target not found — pipeline may not be complete"
  exit 1
fi

# Create dest dir if absent
mkdir -p "$HIST_DATA_DIR"

# ── Export via R inside the project nix shell ─────────────────────────────────

echo "HISTORICAL TELEMETRY: reading targets and converting to JSON..."

# Targets to export:
#   leaderboard          — composite table of all strategy metrics across periods
#   *_metrics            — per-strategy perf tables (fm, drif, stk_max, stk_drif, xgb_drif, aw, boot)
#   strategy_names       — canonical mapping of strategy code/short/long names
#   strategy_correlation — cross-strategy return correlation matrix
#
# These are ALL data-frame or list targets that jsonlite::toJSON handles natively.
# Targets that depend on upstream stale data are silently skipped (NULL check below).

R_EXPORT_CODE=$(cat <<'REOF'
library(targets)
library(jsonlite)

proj_root <- Sys.getenv("PROJ_ROOT")
dest_dir  <- Sys.getenv("HIST_DATA_DIR")
store     <- file.path(proj_root, "docs", "_targets")

stopifnot(dir.exists(store))
stopifnot(dir.exists(dest_dir))

write_json_safe <- function(name, obj) {
  if (is.null(obj) || (is.data.frame(obj) && nrow(obj) == 0L)) {
    cat("  SKIP:", name, "(NULL or 0-row)\n")
    return(invisible(NULL))
  }
  path <- file.path(dest_dir, paste0(name, ".json"))
  jsonlite::write_json(obj, path, auto_unbox = TRUE, na = "null", digits = 6)
  sz <- file.size(path)
  cat(sprintf("  WROTE: %s.json (%d bytes)\n", name, sz))
}

read_safe <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = store),
    error = function(e) {
      cat("  SKIP:", name, "—", conditionMessage(e), "\n")
      NULL
    }
  )
}

# Core composite leaderboard
write_json_safe("leaderboard", read_safe("leaderboard"))

# Per-strategy metrics (all use same schema: period, months, cagr, vol, sharpe, max_dd, ...)
metrics_targets <- c(
  "fm_metrics",
  "drif_metrics",
  "stk_max_metrics",
  "stk_drif_metrics",
  "xgb_drif_metrics",
  "aw_metrics",
  "boot_metrics",
  "port_metrics",
  "kelly_metrics",
  "ltr_metrics",
  "decay_metrics"
)
for (nm in metrics_targets) {
  write_json_safe(nm, read_safe(nm))
}

# Auxiliary tables
write_json_safe("strategy_names",       read_safe("strategy_names"))
write_json_safe("strategy_correlation", read_safe("strategy_correlation"))

# Pipeline health summary from tar_meta
meta <- tryCatch(
  targets::tar_meta(store = store, fields = c("name", "type", "time", "size", "seconds", "error")),
  error = function(e) NULL
)
if (!is.null(meta)) {
  summary_obj <- list(
    exported_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    git_sha        = tryCatch(
      trimws(system2("git", c("-C", proj_root, "rev-parse", "--short", "HEAD"), stdout = TRUE)),
      error = function(e) "unknown"
    ),
    n_targets_built = sum(!is.na(meta$time)),
    n_targets_error  = sum(!is.na(meta$error)),
    store_path       = store
  )
  write_json_safe("pipeline_meta", summary_obj)
}

cat("HISTORICAL TELEMETRY: R export complete\n")
REOF
)

PROJ_ROOT="$PROJ_ROOT" HIST_DATA_DIR="$HIST_DATA_DIR" \
  timeout 120 nix develop "$PROJ_ROOT" --command Rscript -e "$R_EXPORT_CODE" 2>&1

# ── Check for changes ─────────────────────────────────────────────────────────

CHANGED=$(git -C "$TELEMETRY_REPO" diff --name-only -- vignettes/data/historical/ 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git -C "$TELEMETRY_REPO" ls-files --others --exclude-standard -- vignettes/data/historical/ 2>/dev/null | wc -l | tr -d ' ')

echo "HISTORICAL TELEMETRY: $CHANGED changed, $UNTRACKED new files in historical/"

if [ "$CHANGED" -eq 0 ] && [ "$UNTRACKED" -eq 0 ]; then
  echo "HISTORICAL TELEMETRY: no data changes — nothing to commit"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "HISTORICAL TELEMETRY: DRY_RUN=1 — skipping commit + push"
  git -C "$TELEMETRY_REPO" diff --stat -- vignettes/data/historical/ 2>/dev/null || true
  git -C "$TELEMETRY_REPO" ls-files --others --exclude-standard -- vignettes/data/historical/ 2>/dev/null || true
  exit 0
fi

# ── Commit + push ─────────────────────────────────────────────────────────────

GIT_SHA=$(git -C "$PROJ_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

git -C "$TELEMETRY_REPO" add vignettes/data/historical/
git -C "$TELEMETRY_REPO" commit -m "data(historical): update metrics export $(date +%Y-%m-%d)

Auto-exported from historicaldata project (sha: $GIT_SHA).
Includes: leaderboard, strategy *_metrics, pipeline_meta.
Triggered by scripts/export_to_llmtelemetry.sh." --no-verify 2>/dev/null

if [ $? -eq 0 ]; then
  git -C "$TELEMETRY_REPO" push 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "HISTORICAL TELEMETRY: pushed — CI will deploy dashboard"
  else
    echo "HISTORICAL TELEMETRY: push failed (network?), data committed locally"
  fi
else
  echo "HISTORICAL TELEMETRY: commit failed (nothing changed?)"
fi
