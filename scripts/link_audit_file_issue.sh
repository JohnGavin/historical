#!/usr/bin/env bash
# link_audit_file_issue.sh -- file or update the link-audit alert.
#
# Usage: scripts/link_audit_file_issue.sh <report.md>
#
# If an OPEN issue labelled `link-audit` exists, the lychee report is added
# to it as a comment. Otherwise ONE new issue is created. Never creates a
# second open issue while one is open. Does not close anything.
#
# Env:
#   GH       gh executable (default: gh); overridable so tests can stub it.
#   REPO     optional OWNER/NAME passed as --repo (default: gh's own context).
#
# Exit codes: 0 done; 1 failure (including "could not tell whether an issue
# exists" and a missing/empty report); 2 usage.
set -euo pipefail

GH="${GH:-gh}"
TITLE="link-audit: broken links detected on Pages site"
LABELS="bug,deploy,link-audit"
MAX_BYTES=60000

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <report.md>" >&2
  exit 2
fi
REPORT="$1"

if [ ! -s "$REPORT" ]; then
  echo "ERROR: report file missing or empty: $REPORT" >&2
  exit 1
fi

repo_args=()
if [ -n "${REPO:-}" ]; then
  repo_args=(--repo "$REPO")
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
body="$tmp/body.md"

size="$(wc -c < "$REPORT" | tr -d ' ')"
if [ "$size" -gt "$MAX_BYTES" ]; then
  head -c "$MAX_BYTES" "$REPORT" > "$body"
  printf '\n\n[truncated] report was %s bytes; cut to %s bytes (GitHub comment limit). See the lychee-output artifact of the run for the full report.\n' \
    "$size" "$MAX_BYTES" >> "$body"
else
  cp "$REPORT" "$body"
fi

if ! existing="$("$GH" issue list "${repo_args[@]}" --label link-audit --state open \
      --json number --jq '.[0].number // empty' --limit 1)"; then
  echo "ERROR: could not tell whether an open link-audit issue exists (gh issue list failed); not creating an issue." >&2
  exit 1
fi

if [ -n "$existing" ]; then
  echo "Open link-audit issue #$existing exists; adding report as a comment."
  "$GH" issue comment "$existing" "${repo_args[@]}" --body-file "$body"
else
  echo "No open link-audit issue; creating one."
  "$GH" issue create "${repo_args[@]}" --title "$TITLE" --label "$LABELS" --body-file "$body"
fi
