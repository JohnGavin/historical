# Project Configuration — historical

Full verification fact table: [`.claude/rules/verification-workflow.md`](rules/verification-workflow.md)
(loads automatically when you touch `scripts/`, `tests/`, `R/`, `packages/*/R/`, `docs/_targets.R`, `flake.nix`).

## Tooling reminders

**API doc regen:** when `packages/historicaldata/R/*` exports change, run `scripts/regen_api_context.sh` before committing. The deployed link from `docs/index.qmd` → `docs/api-historicaldata.md` depends on it. The "functions" stat on the landing page is counted dynamically from `kind: function` lines in that file.

**Automation (issue #438):** A project-local Stop hook (`.claude/hooks/pkgctx_regen_on_stop.sh`) runs automatically at session end. If `packages/historicaldata/R/` was touched during the session it invokes `scripts/regen_api_context.sh`; otherwise it exits silently. The hook is fail-open — a regen failure prints a warning but never blocks the session. A CI check (`.github/workflows/pkgctx-check.yml`) catches any stale doc on PRs that touch `packages/historicaldata/R/` or `docs/api-historicaldata.md`.

**`macro_daily`/`equity_daily` are archived, not stale-pending-refresh (#619, #655, #673):** both HuggingFace-backed datasets read by `hd_macro()`/`hd_ohlcv()` were seeded once (2026-05-06) by duplicating `dsfefvx/finance-historical-data`, which was itself already inactive and has had no commits since 2026-04-23. No replacement source is currently being sourced — this is a decision, not an open outage. Read [`docs/DATA_SOURCING_LESSONS.md`](../docs/DATA_SOURCING_LESSONS.md) before touching any code that reasons about these datasets' staleness or the Validation-seal boundary (`R/plan_partitions.R`, `R/plan_risk_state.R`).

## Verifying a change (issue #569) — summary

**Run `scripts/verify.sh` — the one command to run before claiming a change is verified.** `--quick` is a fast parse-only check; plain runs the full suite. Do not hand-roll a verification sequence.

- **Necessary, not sufficient (#680, #693).** `verify.sh` parses `_targets.R` and `docs/_targets.R`, runs `tar_validate(script = "docs/_targets.R")` and the root + package testthat suites. It runs **no target body**, so a pass does not establish that `tar_make()` still succeeds. A change that could plausibly break a target (new/changed upstream dependency, changed column name, new NA-producing path) needs `scripts/build.sh` as well — **main checkout only** (a worktree has no store and must not build one that could race the main checkout's `docs/_targets`).
- **A change under `packages/*/R/` needs `scripts/build.sh`, not just `verify.sh` (#753).** `load_all()` imports are not tracked as target dependencies, so `tar_make()` can silently skip a stale target; only `build.sh` Step 2c (`scripts/check_pkg_staleness.R`) proves nothing was left stale.
- **`scripts/build.sh --render` (#695)** re-renders dashboards flagged stale; never commits or pushes.
- **Build system is `flake.nix`, not `default.nix`.** There is no R on the bare PATH: use `nix develop <repo-root> --command Rscript -e '...'`. Warm shell ~13s, cold build 10+ minutes — run verification in the background and wait for it; never report "waiting on the build" as a result.
- **`parse("_targets.R")` MUST succeed before every commit** (global rule). There are two `_targets.R` files; `docs/_targets.R` is the real pipeline (`docs/_targets.yaml` is gitignored and absent in worktrees, so always pass `script =` explicitly).
- **Tests:** the root is not a package — use `testthat::test_dir("tests/testthat")`, never `test_local()`. `verify.sh` exports `NOT_CRAN=true` and `TESTTHAT_EDITION=3`; new root test files MUST keep `testthat::local_edition(3)` at the top. The 3 root-suite baseline failures and the package-suite skip baseline are encoded in `verify.sh`; a rising SKIP count is lost coverage, not success — do not raise the baseline to silence a real outage.
- **CI covers only `packages/historicaldata/**`.** Changes to root `R/`, `scripts/`, `tests/` get no CI; local `verify.sh` is the only gate.
- **`{alphavantager}` tests are correctly skipped (#654)** — keep as-is; do not add the package to the nix environment.

Everything above is detailed (with evidence and issue history) in `.claude/rules/verification-workflow.md`.
