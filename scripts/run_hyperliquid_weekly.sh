#!/bin/bash
# Weekly Hyperliquid candle fetch (#1080). Run by launchd (see scripts/launchd/).
#
# Why weekly: the API keeps the last 5000 bars per interval, so hourly bars reach
# back ~208 days and 15-minute bars ~52 days. A weekly run loses nothing.
#
# Exit status: the fetcher's own (0 ok | 1 partial | 3 INDETERMINATE), with the
# market reference step (#1084, fetch_hl_market_reference.R: 0 ok | 3 INDETERMINATE)
# folded in: 3 from either step is 3. 3 is never turned into 0. 2 = this wrapper
# could not start a step.
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

# Market reference table (#1084): long names / definitions from the exchange's
# published page, one request to the API and one to the page. It runs even when
# the fetch above was partial or INDETERMINATE (it needs nothing from it). Its
# own status is folded in so that 3 is never turned into a lower number:
# 3 beats 1 beats 0 (and 2 = could not start is kept as is).
nix develop "$REPO" --command Rscript scripts/fetch_hl_market_reference.R >> "$LOG" 2>&1
ref_status=$?
echo "=== market reference exit status $ref_status ===" >> "$LOG"
if [ "$ref_status" -eq 3 ] || [ "$status" -eq 3 ]; then
  status=3
elif [ "$status" -eq 0 ]; then
  status=$ref_status
fi

echo "=== exit status $status ===" >> "$LOG"
exit "$status"
