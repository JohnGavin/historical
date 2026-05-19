#!/usr/bin/env bash
# default.post.sh — Idempotent patch to re-apply the closure-rebuild shellHook
# after `t update` regenerates flake.nix.
#
# Per nix-nested-shell-isolation rule (defensive workflow):
# When `t update` regenerates flake.nix, it strips hand-edited shellHook blocks.
# Run this script immediately after `t update` to re-apply the patch.
#
# Overlay being re-applied:
#   - closure-rebuild: discards inherited R_LIBS_SITE from outer nix shells
#     (fixes ABI mismatch segfault in slider/dplyr/glmnet/arrow when entering
#     this project shell from inside another nix-shell). Closes #211.
#
# Usage:
#   t update           # regenerates flake.nix (strips shellHook patch)
#   bash default.post.sh   # re-applies the patch (idempotent)
#
# Idempotency guard: checks for presence of "Closure-rebuild" marker before patching.
set -euo pipefail

NIX_FILE="$(dirname "$0")/flake.nix"

if [ ! -f "$NIX_FILE" ]; then
  echo "ERROR: $NIX_FILE not found" >&2
  exit 1
fi

MARKER="Closure-rebuild"
if grep -q "$MARKER" "$NIX_FILE"; then
  echo "default.post.sh: closure-rebuild shellHook already present in flake.nix — skipping"
  exit 0
fi

echo "default.post.sh: applying closure-rebuild shellHook patch to $NIX_FILE..."

export NIX_FILE

python3 - <<'PYEOF'
import sys
import os

filepath = os.environ["NIX_FILE"]

with open(filepath, 'r') as f:
    content = f.read()

insertion = '''            # ----------------------------------------------------------------
            # Closure-rebuild: discard any inherited R_LIBS_SITE from outer
            # nix shells (global nix-nested-shell-isolation rule, 2026-05-18).
            # When this shell is entered from inside another nix-shell, the
            # outer R_LIBS_SITE points at libraries compiled against a
            # DIFFERENT R binary -> segfault on first native call
            # (slider::slide_dbl, dplyr::mutate, glmnet, arrow, etc.).
            # Fix: rebuild R_LIBS_SITE from this shell\'s own buildInputs
            # closure, discarding all inherited paths. Closes #211.
            # ----------------------------------------------------------------
            R_LIBS_SITE=""
            for pkg in $buildInputs; do
              for dep in $(nix-store -qR "$pkg" 2>/dev/null); do
                if [ -d "$dep/library" ]; then
                  case ":$R_LIBS_SITE:" in
                    *":$dep/library:"*) ;;
                    *) R_LIBS_SITE="\'\'${R_LIBS_SITE:+$R_LIBS_SITE:}$dep/library" ;;
                  esac
                fi
              done
            done
            export R_LIBS_SITE
            unset R_LIBS_USER
            unset R_LIBS
'''

marker = "          shellHook = ''\n"
pos = content.find(marker)
if pos == -1:
    print("ERROR: shellHook marker not found in flake.nix", file=sys.stderr)
    sys.exit(1)

insert_pos = pos + len(marker)
new_content = content[:insert_pos] + insertion + content[insert_pos:]

with open(filepath, 'w') as f:
    f.write(new_content)

print(f"Patch applied: inserted closure-rebuild block ({len(insertion)} chars)")
PYEOF

echo "default.post.sh: done. Verify with: grep -c 'Closure-rebuild' $NIX_FILE"
