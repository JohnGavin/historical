#!/bin/bash
# Is there a Time Machine snapshot at least as new as the newest data file?
# (RECOVERY.md; run at the end of scripts/run_hyperliquid_weekly.sh.)
#
# Read-only. It reads the Time Machine preferences with `defaults read` (the
# snapshot dates the machine has recorded for its destinations) and the modification
# times under data/dist. It never calls tmutil and never needs a drive mounted: the
# dates are the ones the preferences recorded at the last backup, so a drive that is
# not plugged in right now does not make this check unknown.
#
# PASS when   newest snapshot >= newest data file mtime - tolerance
# FAIL when   the newest snapshot is older than that (both times and the gap printed)
#
# Exit status (exit-code-conventions):
#   0 PASS | 1 FAIL | 2 usage | 3 INDETERMINATE (the reason is printed)
#
# INDETERMINATE (3) is never reported as PASS: preferences unreadable, preferences
# with no snapshot dates, a data folder that is missing or holds no file, or a date
# that does not parse. A data folder that does not exist is also 3, not 1: the
# question "is the data backed up" has no answer when there is no data to look at.
#
# Output carries times and counts only: no volume name, destination ID or path of a
# backup drive (the repository is public and these logs get pasted into issues).
#
# Usage: scripts/check_backup.sh [--tolerance-hours=N]
# Test hooks (so tests never read the real machine):
#   HL_BACKUP_PREFS_FILE   a file holding `defaults read` output, used instead of
#                          the real preferences
#   HL_BACKUP_DATA_DIR     the folder to scan instead of <repo>/data/dist

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFS_DOMAIN="/Library/Preferences/com.apple.TimeMachine"
tolerance_hours=24

for arg in "$@"; do
  case "$arg" in
    --tolerance-hours=*) tolerance_hours="${arg#--tolerance-hours=}" ;;
    -h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: check_backup.sh [--tolerance-hours=N]  (unknown argument: $arg)" >&2; exit 2 ;;
  esac
done
case "$tolerance_hours" in
  ''|*[!0-9]*) echo "usage: --tolerance-hours needs a whole number of hours, got '$tolerance_hours'" >&2; exit 2 ;;
esac

data_dir="${HL_BACKUP_DATA_DIR:-$REPO/data/dist}"

# date and stat are called by absolute path: inside `nix develop` (and in the weekly
# wrapper, which puts the nix profile first on PATH) a GNU date/stat can shadow the
# BSD ones, and `date -j` / `stat -f` do not exist there.
indeterminate() { echo "BACKUP INDETERMINATE: $1"; exit 3; }

# --- snapshot dates --------------------------------------------------------
if [ -n "${HL_BACKUP_PREFS_FILE:-}" ]; then
  [ -r "$HL_BACKUP_PREFS_FILE" ] || indeterminate "the preferences fixture is not readable"
  prefs="$(cat "$HL_BACKUP_PREFS_FILE")"
else
  prefs_err="$(mktemp)" || indeterminate "cannot create a temporary file"
  prefs="$(defaults read "$PREFS_DOMAIN" 2>"$prefs_err")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    reason="$(head -c 200 "$prefs_err" | tr '\n' ' ')"
    rm -f "$prefs_err"
    indeterminate "the Time Machine preferences could not be read (defaults exit $rc: $reason)"
  fi
  rm -f "$prefs_err"
fi

# Only the SnapshotDates lists count: AttemptDates are attempts, not backups.
dates="$(printf '%s\n' "$prefs" | awk '
  /SnapshotDates[ ]*=/ { inlist = 1; next }
  inlist && /\)/       { inlist = 0; next }
  inlist               { gsub(/[",]/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") print }
')"
if [ -z "$dates" ]; then
  indeterminate "the Time Machine preferences hold no snapshot dates (no backup recorded, or an unexpected format)"
fi

newest_snap=0
n_snap=0
while IFS= read -r d; do
  # "2026-11-21 07:28:54 +0000" -> epoch seconds
  e="$(/bin/date -j -f "%Y-%m-%d %H:%M:%S %z" "$d" +%s 2>/dev/null)" || \
    indeterminate "a snapshot date did not parse (the preferences format may have changed)"
  n_snap=$((n_snap + 1))
  [ "$e" -gt "$newest_snap" ] && newest_snap="$e"
done <<EOF
$dates
EOF

# --- newest data file ------------------------------------------------------
[ -d "$data_dir" ] || indeterminate "the data folder does not exist (run this from the checkout that holds the data)"
newest_data="$(find "$data_dir" -type f -exec /usr/bin/stat -f %m {} + 2>/dev/null | sort -n | tail -n 1)"
[ -n "$newest_data" ] || indeterminate "the data folder holds no file to compare against"

# --- verdict ---------------------------------------------------------------
tol=$((tolerance_hours * 3600))
fmt() { /bin/date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
echo "newest data file:     $(fmt "$newest_data")"
echo "newest snapshot:      $(fmt "$newest_snap") (of $n_snap recorded)"
echo "tolerance:            ${tolerance_hours} h"

if [ "$newest_snap" -ge $((newest_data - tol)) ]; then
  echo "BACKUP PASS: the newest snapshot is within ${tolerance_hours} h of the newest data file (or newer)"
  exit 0
fi

gap=$((newest_data - newest_snap))
echo "BACKUP FAIL: the newest snapshot is $((gap / 3600)) h older than the newest data file (allowed ${tolerance_hours} h)"
echo "  Data written after the snapshot exists only on this machine. Connect a backup drive and let Time Machine finish."
exit 1
