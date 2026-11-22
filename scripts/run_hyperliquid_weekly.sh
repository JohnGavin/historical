#!/bin/bash
# Weekly Hyperliquid candle fetch (#1080). Run by launchd (see scripts/launchd/).
#
# Why weekly: the API keeps the last 5000 bars per interval, so hourly bars reach
# back ~208 days and 15-minute bars ~52 days. A weekly run loses nothing.
#
# Exit status is the fetcher's own: 0 ok | 1 partial | 3 INDETERMINATE.
# 3 is never turned into 0. 2 = this wrapper could not start the fetcher.
#
# The repo path is derived from this script's location, never hard-coded.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/historical"
LOG="$LOG_DIR/hyperliquid_weekly.log"

mkdir -p "$LOG_DIR" || exit 2

{
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) hyperliquid weekly fetch (repo: $REPO) ==="
} >> "$LOG"

# nix is not on launchd's minimal PATH.
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"

cd "$REPO" || exit 2

nix develop "$REPO" --command Rscript scripts/fetch_hyperliquid.R \
  --intervals=1d,1h,15m --resume "$@" >> "$LOG" 2>&1
status=$?

echo "=== exit status $status ===" >> "$LOG"
exit "$status"
