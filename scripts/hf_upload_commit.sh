#!/usr/bin/env bash
# Upload a staging folder to the public Hugging Face dataset as ONE commit, then read
# every file back and compare it with the local copy (#1088).
#
# Usage: bash scripts/hf_upload_commit.sh <stage-dir> [commit-message]
#   The folder's own layout is the layout in the repo: <stage-dir>/hyperliquid/... goes
#   to hyperliquid/... .
#
# It FAILS CLOSED. Nothing is uploaded unless ALL hold:
#   * the repo is exactly JohnGavin/finance-data (HD_HF_REPO, if set, must equal it)
#   * HD_HF_REPO_VISIBILITY=public is declared, and an unauthenticated request to the
#     dataset's API page succeeds (a private dataset answers 401/404)
#   * every file in the folder lies under hyperliquid/, and none is a symlink, .tmp or .part
#   * the `hf` CLI and HF_TOKEN are present (a cached login is NOT accepted: this is for CI)
#
# Unlike scripts/upload_hf.sh, a missing tool or token is NEVER exit 0.
#
# Exit status: 0 uploaded AND every file read back identical | 1 FAIL (policy refused,
#   the upload failed, or a file is missing or different on read-back) | 2 usage (no
#   folder, or nothing in it) | 3 INDETERMINATE (hf CLI or token absent, or the public
#   check could not be answered).
#
# Test seams: HD_HF_READBACK_TRIES (default 3) and HD_HF_READBACK_SLEEP (default 5 s).
set -uo pipefail

EXPECTED_REPO="JohnGavin/finance-data"
REQUIRED_PREFIX="hyperliquid/"
REPO="${HD_HF_REPO:-$EXPECTED_REPO}"
DIR="${1:-}"
MSG="${2:-data: hyperliquid 5-minute snapshots ($(date -u +%Y-%m-%d)) (#1088)}"
TRIES="${HD_HF_READBACK_TRIES:-3}"
PAUSE="${HD_HF_READBACK_SLEEP:-5}"

say() { echo "hf_upload_commit.sh: $*" >&2; }

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  say "usage: bash scripts/hf_upload_commit.sh <stage-dir> [commit-message] (folder not found)"
  exit 2
fi
DIR="${DIR%/}"

# ── Policy, before any tool is needed ───────────────────────────────
if [ "$REPO" != "$EXPECTED_REPO" ]; then
  say "REFUSED: repo '$REPO' is not the only allowed target '$EXPECTED_REPO'"
  exit 1
fi
if [ "${HD_HF_REPO_VISIBILITY:-}" != "public" ]; then
  say "REFUSED: HD_HF_REPO_VISIBILITY=public is not declared; publishing here is only for a dataset known to be public"
  exit 1
fi

FILES="$(find "$DIR" -type f | LC_ALL=C sort)"
if [ -n "$(find "$DIR" -type l)" ]; then
  say "REFUSED: the folder contains a symlink"
  exit 1
fi
if [ -z "$FILES" ]; then
  say "nothing to upload: $DIR holds no files"
  exit 2
fi
COUNT=0
while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  case "$rel" in
    "$REQUIRED_PREFIX"*) ;;
    *) say "REFUSED: '$rel' is not under $REQUIRED_PREFIX"; exit 1 ;;
  esac
  case "$rel" in
    *..*|*.tmp|*.part) say "REFUSED: '$rel' is not an upload candidate"; exit 1 ;;
  esac
  COUNT=$((COUNT + 1))
done <<< "$FILES"

# ── Tools and credentials ───────────────────────────────────────────
if ! command -v hf >/dev/null 2>&1; then
  say "INDETERMINATE: the 'hf' CLI is not on PATH (pip install --upgrade huggingface_hub); nothing uploaded"
  exit 3
fi
if ! command -v curl >/dev/null 2>&1; then
  say "INDETERMINATE: curl is not on PATH; the dataset's visibility cannot be checked"
  exit 3
fi
if [ -z "${HF_TOKEN:-}" ]; then
  say "INDETERMINATE: HF_TOKEN is not set; nothing uploaded"
  exit 3
fi

CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "https://huggingface.co/api/datasets/$REPO")"
case "$CODE" in
  200) ;;
  401|403|404) say "REFUSED: the dataset does not answer publicly (HTTP $CODE), so it is not known to be public"; exit 1 ;;
  *) say "INDETERMINATE: the visibility check got HTTP '$CODE'"; exit 3 ;;
esac

# ── ONE commit ──────────────────────────────────────────────────────
say "uploading $COUNT file(s) from $DIR to the dataset in one commit"
if ! hf upload "$REPO" "$DIR" . --repo-type dataset --commit-message "$MSG"; then
  say "FAIL: hf upload failed"
  exit 1
fi

# ── Read back: every file must be on the hub, identical ─────────────
BACK="$(mktemp -d)"
MISSING=0
while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  ok=0
  n=1
  while [ "$n" -le "$TRIES" ]; do
    if hf download "$REPO" "$rel" --repo-type dataset --local-dir "$BACK" >/dev/null 2>&1 \
       && cmp -s "$f" "$BACK/$rel"; then
      ok=1
      break
    fi
    n=$((n + 1))
    [ "$n" -le "$TRIES" ] && sleep "$PAUSE"
  done
  if [ "$ok" -ne 1 ]; then
    say "MISSING or different after commit: $rel"
    MISSING=$((MISSING + 1))
  fi
done <<< "$FILES"
find "$BACK" -mindepth 1 -delete

if [ "$MISSING" -gt 0 ]; then
  say "FAIL: $MISSING of $COUNT file(s) not found identical on the hub after the commit"
  exit 1
fi
say "PASS: $COUNT file(s) uploaded in one commit and read back identical"
exit 0
