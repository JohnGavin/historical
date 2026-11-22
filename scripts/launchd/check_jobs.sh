#!/bin/bash
# Read-only status check for the Hyperliquid launchd jobs (#1080).
# Loads, unloads and changes nothing: only `launchctl print`, file reads and
# file mtimes.
#
# Per job:
#   - loaded / NOT LOADED (launchctl print)
#   - FAIL "loaded from <path>, will not survive reboot" when launchd's `path =`
#     is not under ~/Library/LaunchAgents (a plist bootstrapped from the repo
#     is gone after logout or reboot)
#   - FAIL "stale install" when the installed plist differs from the repo
#     template rendered with this checkout's path (scripts/launchd/install_jobs.sh
#     fixes both)
#   - age of the log's last write; STALE if the poller log is older than 15
#     minutes or the weekly log older than 8 days
#
# Exit status: 0 everything fine | 1 a finding (FAIL or STALE)
#              | 3 cannot tell (not loaded, a log or plist missing, launchctl
#                unusable). A finding outranks 3.
#
# Test hooks (never needed in normal use): HL_LAUNCH_AGENTS_DIR, HL_LOG_DIR.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
UIDN="$(id -u)"
AGENTS_DIR="${HL_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
LOG_DIR="${HL_LOG_DIR:-$HOME/Library/Logs/historical}"
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
    path="$(echo "$out" | sed -n 's/^[[:space:]]*path = //p' | head -n 1)"
    if [ -z "$path" ]; then
      echo "  cannot tell where it was loaded from (no path line in launchctl print)"
      unknown=1
    else
      case "$path" in
        "$AGENTS_DIR"/*)
          template="$HERE/$label.plist"
          if [ ! -f "$path" ] || [ ! -f "$template" ]; then
            echo "  cannot compare the installed copy: missing $path or $template"
            unknown=1
          else
            want="$(sed "s|__REPO__|$REPO|g" "$template" | shasum | cut -c1-40)"
            have="$(shasum < "$path" | cut -c1-40)"
            if [ "$want" != "$have" ]; then
              echo "  FAIL: stale install ($path differs from the rendered repo copy)"
              finding=1
            else
              echo "  installed copy: $path (matches the repo template)"
            fi
          fi
          ;;
        *)
          echo "  FAIL: loaded from $path, will not survive reboot"
          finding=1
          ;;
      esac
    fi
  elif echo "$out" | grep -qi "could not find service"; then
    echo "$label: NOT LOADED"
    unknown=1
  else
    echo "$label: cannot tell (launchctl print failed: $out)"
    unknown=1
  fi
  if [ ! -f "$log" ]; then
    echo "  log $log: missing, cannot tell its age"
    unknown=1
    return
  fi
  mtime="$(/usr/bin/stat -f %m "$log")"   # BSD stat: a nix shell puts GNU stat first
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

if [ "$finding" -eq 1 ]; then exit 1; fi
if [ "$unknown" -eq 1 ]; then exit 3; fi
exit 0
