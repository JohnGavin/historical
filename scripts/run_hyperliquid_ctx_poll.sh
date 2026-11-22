#!/bin/bash
# 5-minute Hyperliquid metaAndAssetCtxs poll (#1080, #1084). Run by launchd
# (see scripts/launchd/). One request per exchange per run (all exchanges by
# default: the poller's own `--dexes=all`, so the installed plist, which passes no
# arguments, needs no change); the data has no history, so a run that does not
# happen is a gap that is never filled.
#
# Exit status: 0 ok | 2 usage / could not start | 3 INDETERMINATE (the poller's
# own 3, which includes a partial run where some exchanges failed; DNS never
# resolved; or the run hit its deadline). 3 is never turned into 0.
#
# What this wrapper adds around the poller:
#  - waits (up to 45 s) for the API host to resolve before the first request
#    (a wake from sleep often has no network for a few seconds); else exit 3.
#  - a hard deadline of 240 s on the whole run, under launchd's 300 s interval,
#    so runs never overlap; on expiry the run is killed and exits 3.
#  - avoids evaluating the flake on every run: `nix print-dev-env --profile`
#    is built once per flake.nix/flake.lock content into
#    ~/Library/Caches/historical/ (the profile is a GC root) and sourced
#    afterwards (about 2 s instead of ~13 s). If the cache is missing, cannot be
#    built, or its store paths were garbage-collected (exit 127), the wrapper
#    falls back to a plain `nix develop`.
#
# The repo path is derived from this script's location, never hard-coded.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${HL_POLL_LOG_DIR:-$HOME/Library/Logs/historical}"
LOG="$LOG_DIR/hyperliquid_ctx_poll.log"
CACHE_DIR="${HL_POLL_CACHE_DIR:-$HOME/Library/Caches/historical}"
HOST="${HL_POLL_HOST:-api.hyperliquid.xyz}"
DNS_WAIT_S="${HL_POLL_DNS_WAIT_S:-45}"
BUDGET_S="${HL_POLL_BUDGET_S:-240}"

mkdir -p "$LOG_DIR" || exit 2
log() { echo "$*" >> "$LOG"; }

log "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) hyperliquid ctx poll (repo: $REPO) ==="

# nix is not on launchd's minimal PATH.
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"

cd "$REPO" || exit 2

start=$SECONDS

# ── DNS wait ────────────────────────────────────────────────────────
resolves() { dscacheutil -q host -a name "$HOST" 2>/dev/null | grep -q '^ip_address'; }
until resolves; do
  if [ $((SECONDS - start)) -ge "$DNS_WAIT_S" ]; then
    log "=== INDETERMINATE: $HOST did not resolve within ${DNS_WAIT_S}s; exit status 3 ==="
    exit 3
  fi
  sleep 3
done
log "dns: $HOST resolves after $((SECONDS - start))s"

# ── Run under a deadline ────────────────────────────────────────────
# run_deadline SECONDS CMD...: output to the log; 124 when the deadline hit.
run_deadline() {
  limit="$1"; shift
  "$@" >> "$LOG" 2>&1 &
  pid=$!
  ( sleep "$limit"; pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
    sleep 5; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null ) 2>/dev/null &
  watchdog=$!
  disown "$watchdog"   # no job-status noise when it is killed
  wait "$pid"
  rc=$?
  if kill -0 "$watchdog" 2>/dev/null; then
    { pkill -P "$watchdog"; kill "$watchdog"; } 2>/dev/null
  else
    rc=124
  fi
  return "$rc"
}

# Cached dev environment, keyed by the flake's content.
key="$(cat "$REPO/flake.nix" "$REPO/flake.lock" 2>/dev/null | shasum | cut -c1-12)"
envfile="$CACHE_DIR/hl_devenv_$key.sh"
if [ ! -f "$envfile" ]; then
  mkdir -p "$CACHE_DIR"
  if nix print-dev-env "$REPO" --profile "$CACHE_DIR/hl_devenv_$key.profile" \
       > "$envfile.tmp" 2>> "$LOG"; then
    mv "$envfile.tmp" "$envfile"
    log "devenv: built cache $envfile"
  else
    rm -f "$envfile.tmp"
    log "devenv: could not build the cache; using nix develop"
  fi
fi

remaining=$((BUDGET_S - (SECONDS - start)))
[ "$remaining" -lt 1 ] && remaining=1

status=127
if [ -f "$envfile" ]; then
  run_deadline "$remaining" bash -c 'source "$1" >/dev/null 2>&1; shift; exec Rscript "$@"' \
    _ "$envfile" scripts/poll_hyperliquid_ctx.R "$@"
  status=$?
  [ "$status" -eq 127 ] && log "devenv: cached environment unusable (garbage-collected?); falling back"
fi
if [ "$status" -eq 127 ]; then
  remaining=$((BUDGET_S - (SECONDS - start)))
  [ "$remaining" -lt 1 ] && remaining=1
  run_deadline "$remaining" nix develop "$REPO" --command Rscript scripts/poll_hyperliquid_ctx.R "$@"
  status=$?
fi

if [ "$status" -eq 124 ] || [ "$status" -eq 143 ] || [ "$status" -eq 137 ]; then
  log "=== INDETERMINATE: run hit the ${BUDGET_S}s deadline ==="
  status=3
fi

log "=== exit status $status ==="
exit "$status"
