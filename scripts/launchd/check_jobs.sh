#!/bin/bash
# Read-only status check for the Hyperliquid launchd jobs (#1080).
# Loads, unloads and changes nothing: only `launchctl print` and file mtimes.
#
# Per job: loaded / not loaded, and the age of the log's last write (the
# wrappers write a line at the start and end of every run).
# STALE: poller log older than 15 minutes, weekly log older than 8 days.
#
# Exit status: 0 everything fine | 1 a finding (not loaded, or STALE)
#              | 3 cannot tell (a log file is missing or launchctl unusable).

UIDN="$(id -u)"
LOG_DIR="$HOME/Library/Logs/historical"
NOW="$(date +%s)"
finding=0
unknown=0

# label | log file | max age in seconds
check_job() {
  label="$1"; log="$2"; max="$3"
  out="$(launchctl print "gui/$UIDN/$label" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$label: loaded"
  elif echo "$out" | grep -qi "could not find service"; then
    echo "$label: NOT LOADED"
    finding=1
  else
    echo "$label: cannot tell (launchctl print failed: $out)"
    unknown=1
  fi
  if [ ! -f "$log" ]; then
    echo "  log $log: missing, cannot tell its age"
    unknown=1
    return
  fi
  mtime="$(stat -f %m "$log")"
  age=$((NOW - mtime))
  if [ "$age" -gt "$max" ]; then
    echo "  log age: ${age}s (limit ${max}s): STALE"
    finding=1
  else
    echo "  log age: ${age}s (limit ${max}s): ok"
  fi
}

check_job io.github.johngavin.historical.hyperliquid-ctx-poll \
  "$LOG_DIR/hyperliquid_ctx_poll.log" 900
check_job io.github.johngavin.historical.hyperliquid-weekly \
  "$LOG_DIR/hyperliquid_weekly.log" 691200

# A finding outranks "cannot tell": a known problem is reported as 1.
if [ "$finding" -eq 1 ]; then exit 1; fi
if [ "$unknown" -eq 1 ]; then exit 3; fi
exit 0
