#!/usr/bin/env bash
# Publish a local parquet to the HuggingFace dataset (#619).
#
# Generalises scripts/upload_kraken_hf.sh, which was the only uploader in the
# repo and is why kraken_ohlcvt was the only HF-backed dataset still being
# refreshed. That script is left in place; it can be migrated to call this one.
#
# Usage:
#   bash scripts/upload_hf.sh <local-path> <remote-name> [commit-message]
#   DRYRUN=1 bash scripts/upload_hf.sh ...        # print the command, upload nothing
#
# Auth, in order of preference:
#   1. HF_TOKEN in the environment (CI)
#   2. the `hf` CLI's own credential cache (`hf auth login`, local use)
# No token is ever read from or written to this repo.
#
# ── Publishing is gated, deliberately ──────────────────────────────────────
#
# This writes to a PUBLIC dataset. It is a cross-boundary action, so it does
# not happen as a side effect of a build:
#
#   * absent `hf` CLI      -> exit 0 with a message (fail-soft; a poll that
#                             cannot publish should still not fail red)
#   * absent credentials   -> exit 0 with a message (same reasoning)
#   * DRYRUN=1             -> print the exact command and stop
#
# In CI the gate is the SECRET: with no HF_TOKEN configured the workflow skips
# this step entirely. Adding that secret is the deliberate act of authorising
# publication — not merging this script.
set -euo pipefail

LOCAL_PATH="${1:-}"
REMOTE_NAME="${2:-}"
COMMIT_MSG="${3:-}"
HF_REPO="${HD_HF_REPO:-JohnGavin/finance-data}"

if [ -z "$LOCAL_PATH" ] || [ -z "$REMOTE_NAME" ]; then
  echo "usage: bash scripts/upload_hf.sh <local-path> <remote-name> [commit-message]" >&2
  echo "  e.g. bash scripts/upload_hf.sh data/raw/macro_daily.parquet macro_daily.parquet" >&2
  exit 2
fi

if [ ! -f "$LOCAL_PATH" ]; then
  echo "upload_hf.sh: $LOCAL_PATH not found." >&2
  echo "  Build it first — for macro_daily: Rscript scripts/build_macro_daily.R" >&2
  exit 1
fi

# Gate 1 — tooling. The huggingface-upload rule mandates the `hf` CLI over
# git+lfs, which cannot authenticate non-interactively against HF's LFS
# endpoint.
if ! command -v hf >/dev/null 2>&1; then
  echo "upload_hf.sh: 'hf' CLI not found on PATH — skipping upload." >&2
  echo "  Install: pip install --upgrade huggingface_hub" >&2
  exit 0
fi

# Gate 2 — credentials. Either an env token or a cached login.
if [ -z "${HF_TOKEN:-}" ] && ! hf auth whoami >/dev/null 2>&1; then
  echo "upload_hf.sh: no HF_TOKEN and no cached login — skipping upload." >&2
  echo "  CI:    add HF_TOKEN to repository secrets" >&2
  echo "  local: hf auth login" >&2
  exit 0
fi

if [ -z "$COMMIT_MSG" ]; then
  COMMIT_MSG="data: ${REMOTE_NAME%.parquet} refresh ($(date -u +%Y-%m-%d))"
fi

SIZE=$(du -h "$LOCAL_PATH" | cut -f1)
echo "Uploading $LOCAL_PATH ($SIZE) -> hf://datasets/$HF_REPO/$REMOTE_NAME"

CMD=(hf upload "$HF_REPO" "$LOCAL_PATH" "$REMOTE_NAME"
     --repo-type dataset
     --commit-message "$COMMIT_MSG")

# Gate 3 — explicit dry run.
if [ -n "${DRYRUN:-}" ]; then
  echo "DRYRUN: ${CMD[*]}"
  exit 0
fi

"${CMD[@]}"
echo "Done. Verify the served copy actually moved:"
echo "  Rscript -e 'x <- historicaldata::hd_macro(\"VIXCLS\"); cat(format(max(as.Date(x\$date))))'"
