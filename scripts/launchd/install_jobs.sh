#!/bin/bash
# Install the Hyperliquid launchd jobs so they survive logout and reboot (#1080).
# FOR THE OWNER TO RUN. Nothing else in the repo runs it.
#
# Usage: scripts/launchd/install_jobs.sh [--dry-run | --apply]
#   --dry-run (the default) prints what would be done and changes nothing.
#   --apply   does it.
#
# For each template in this directory:
#   1. render it: __REPO__ -> the absolute path of this checkout
#   2. plutil -lint the rendered file
#   3. copy it (a copy, not a symlink) to ~/Library/LaunchAgents/<label>.plist
#   4. if the job is already loaded: launchctl bootout it first
#   5. launchctl bootstrap gui/<uid> ~/Library/LaunchAgents/<label>.plist
# The bootstrap step refuses any source path outside ~/Library/LaunchAgents: a
# job bootstrapped from the repo path is gone after the next reboot.
#
# RunAtLoad is true for both jobs, so installing starts a first poll at once and
# a weekly fetch (long: it can take over an hour) at once.
#
# Exit status: 0 ok | 1 a step failed | 2 usage | 3 could not tell.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
UIDN="$(id -u)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
mode="dry-run"

for a in "$@"; do
  case "$a" in
    --apply) mode="apply" ;;
    --dry-run) mode="dry-run" ;;
    *) echo "usage: install_jobs.sh [--dry-run | --apply]" >&2; exit 2 ;;
  esac
done

# Test hook, honoured in dry-run only: apply always uses the real directory.
if [ "$mode" = "dry-run" ] && [ -n "$HL_LAUNCH_AGENTS_DIR" ]; then
  AGENTS_DIR="$HL_LAUNCH_AGENTS_DIR"
fi

echo "mode: $mode (repo: $REPO, target: $AGENTS_DIR)"
fail=0

for template in "$HERE"/io.github.johngavin.historical.*.plist; do
  [ -f "$template" ] || { echo "no templates found in $HERE" >&2; exit 3; }
  label="$(basename "$template" .plist)"
  dest="$AGENTS_DIR/$label.plist"

  tmp="$(mktemp -t "$label")" || exit 3
  sed "s|__REPO__|$REPO|g" "$template" > "$tmp"
  if ! plutil -lint "$tmp" > /dev/null; then
    echo "$label: rendered plist does not lint; skipping" >&2
    fail=1
    continue
  fi
  if grep -q "__REPO__" "$tmp"; then
    echo "$label: placeholder left after rendering; skipping" >&2
    fail=1
    continue
  fi

  # The guard: bootstrap only from under ~/Library/LaunchAgents.
  case "$dest" in
    "$HOME/Library/LaunchAgents"/*) ;;
    *)
      if [ "$mode" = "apply" ]; then
        echo "$label: refusing to bootstrap from $dest (outside ~/Library/LaunchAgents)" >&2
        fail=1
        continue
      fi
      echo "$label: (dry-run only) $dest is outside ~/Library/LaunchAgents; --apply would refuse"
      ;;
  esac

  loaded=0
  if launchctl print "gui/$UIDN/$label" > /dev/null 2>&1; then loaded=1; fi

  echo "$label:"
  echo "  copy      rendered template -> $dest"
  if [ "$loaded" -eq 1 ]; then
    echo "  bootout   gui/$UIDN/$label (currently loaded)"
  else
    echo "  (not currently loaded)"
  fi
  echo "  bootstrap gui/$UIDN $dest"

  if [ "$mode" = "apply" ]; then
    mkdir -p "$AGENTS_DIR" || { fail=1; continue; }
    if [ "$loaded" -eq 1 ]; then
      launchctl bootout "gui/$UIDN/$label" || { echo "  bootout failed" >&2; fail=1; continue; }
    fi
    cp "$tmp" "$dest" || { fail=1; continue; }
    launchctl bootstrap "gui/$UIDN" "$dest" || { echo "  bootstrap failed" >&2; fail=1; continue; }
    echo "  done"
  fi
  rm -f "$tmp"
done

if [ "$mode" = "dry-run" ]; then
  echo "dry-run: nothing changed. Re-run with --apply to install."
fi
if [ "$fail" -eq 1 ]; then exit 1; fi
exit 0
