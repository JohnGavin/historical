# Project Configuration — historical

## Tooling reminders

**API doc regen:** when `packages/historicaldata/R/*` exports change, run `scripts/regen_api_context.sh` before committing. The deployed link from `docs/index.qmd` → `docs/api-historicaldata.md` depends on it. The "functions" stat on the landing page is counted dynamically from `kind: function` lines in that file.
