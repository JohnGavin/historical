#!/usr/bin/env bash
# Upload data/raw/kraken_ohlcvt.parquet to the HF dataset (#436 Phase B).
#
# Companion to scripts/fetch_kraken_ohlcvt.R: fetch builds the parquet
# locally from the Kraken quarterly archive; this script publishes it to
# hf://datasets/JohnGavin/finance-data/kraken_ohlcvt.parquet, where
# historicaldata::hd_kraken_ohlcvt() (and hd_datasets()) read it.
#
# Auth: uses the `hf` CLI's own credential cache (hf auth login).
# No tokens are read from or written to this repo.
#
# Usage:
#   bash scripts/upload_kraken_hf.sh            # upload
#   DRYRUN=1 bash scripts/upload_kraken_hf.sh   # print command only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARQUET="$ROOT/data/raw/kraken_ohlcvt.parquet"
HF_REPO="${HD_HF_REPO:-JohnGavin/finance-data}"

if ! command -v hf >/dev/null 2>&1; then
  echo "upload_kraken_hf.sh: 'hf' CLI not found on PATH — skipping upload." >&2
  echo "  Install: https://huggingface.co/docs/huggingface_hub/guides/cli" >&2
  exit 0
fi

if [ ! -f "$PARQUET" ]; then
  echo "upload_kraken_hf.sh: $PARQUET not found." >&2
  echo "  Build it first: KRAKEN_ZIP_PATH=... Rscript scripts/fetch_kraken_ohlcvt.R" >&2
  exit 1
fi

SIZE=$(du -h "$PARQUET" | cut -f1)
echo "Uploading $PARQUET ($SIZE) -> hf://datasets/$HF_REPO/kraken_ohlcvt.parquet"

CMD=(hf upload "$HF_REPO" "$PARQUET" kraken_ohlcvt.parquet
     --repo-type dataset
     --commit-message "data: kraken_ohlcvt refresh ($(date -u +%Y-%m-%d)) — #436")

if [ -n "${DRYRUN:-}" ]; then
  echo "DRYRUN: ${CMD[*]}"
  exit 0
fi

"${CMD[@]}"
echo "Done. Verify with: Rscript -e 'historicaldata::hd_kraken_ohlcvt(\"SOL\", interval_min = 1440L) |> nrow()'"
