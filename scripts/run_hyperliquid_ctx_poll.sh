#!/bin/bash
# 5-minute Hyperliquid metaAndAssetCtxs poll (#1080). Run by launchd
# (see scripts/launchd/). One request per run; the data has no history, so a run
# that does not happen is a gap that is never filled.
#
# Exit status is the poller's own: 0 ok | 2 usage | 3 INDETERMINATE.
# 3 is never turned into 0. A wrapper that cannot start also exits 2.
#
# The repo path is derived from this script's location, never hard-coded.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/historical"
LOG="$LOG_DIR/hyperliquid_ctx_poll.log"

mkdir -p "$LOG_DIR" || exit 2

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) hyperliquid ctx poll (repo: $REPO) ===" >> "$LOG"

# nix is not on launchd's minimal PATH.
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"

cd "$REPO" || exit 2

nix develop "$REPO" --command Rscript scripts/poll_hyperliquid_ctx.R "$@" >> "$LOG" 2>&1
status=$?

echo "=== exit status $status ===" >> "$LOG"
exit "$status"
