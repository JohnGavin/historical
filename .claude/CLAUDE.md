# Project Configuration — historical

## Tooling reminders

**API doc regen:** when `packages/historicaldata/R/*` exports change, run `scripts/regen_api_context.sh` before committing. The deployed link from `docs/index.qmd` → `docs/api-historicaldata.md` depends on it. The "functions" stat on the landing page is counted dynamically from `kind: function` lines in that file.

**Automation (issue #438):** A project-local Stop hook (`.claude/hooks/pkgctx_regen_on_stop.sh`) runs automatically at session end. If `packages/historicaldata/R/` was touched during the session it invokes `scripts/regen_api_context.sh`; otherwise it exits silently. The hook is fail-open — a regen failure prints a warning but never blocks the session. A CI check (`.github/workflows/pkgctx-check.yml`) catches any stale doc on PRs that touch `packages/historicaldata/R/` or `docs/api-historicaldata.md`.
