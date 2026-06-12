# Current Work (Session 2026-06-11 → 2026-06-12 #17 — registry 14/14 + Kraken dataset live + 9 PRs, ENDED)

**Last updated:** session end 2026-06-12
**Previous sessions:** #16 (#425 cost-bug + Tier 1, 7 PRs), #15 (#400 SSR closed, 5 PRs), #14 (12 PRs)

## This session — 9 PRs merged + 6 issues closed; parallel-worktree agent mode

### Headline

User-directed parallel-agent session. **#442 closed at 14/14 registry coverage** (Tiers 2+3 + a pipeline run materialising every sentinel); **#436 closed** with a 19-pair Kraken OHLCVT dataset (6 crypto + 12 spot FX + PAXG gold; 957,650 rows) **live on HF** and queryable via the new `hd_kraken_ohlcvt()`; **#312 closed** (filter-then-rank applied to stk_drif); two latent bugs found by real runs and fixed same-day (#453 duckplyr TIMESTAMP_NS binder; Kraken `master_q4/` ZIP layout).

### PRs merged (9)

| PR | Subject |
|---|---|
| #446 | #438 Stop-hook pkgctx regen + CI gate (+ determinism fix: header churn + ordering) |
| #447 | #442 Tier 2 — stk_max/stk_drif/xgb_drif sentinels (agent salvage) |
| #448 | #442 Tier 3 — tom/pso new, cmr verified |
| #452 | #312 stk_drif ADV gate before decile construction |
| #393 | #389 Phase A audit doc (stale PR cleared; #389 reopened post-auto-close) |
| #454 | #453 typed date literals — hd_ohlcv/hd_macro/hd_factors/hd_macro_vintages |
| #455 | #436 Phase A Kraken fetch pipeline |
| #456 | Kraken ZIP-layout fix + #389 Phase B (cov_annual + corr-plan repair, agent salvage) + QuantMind PDF |
| #457 | #436 complete — 19 pairs, hd_kraken_ohlcvt(), HF upload |

### Issues: closed #423 #312 #436 #438 #442 #453; filed #449 #450 #451 #453; #389 reopened (B done, C–E remain)

### Key operational lessons (see CHANGELOG Failed Approaches)

- 3/7 agents killed by monthly API spend limit — salvage-from-worktree protocol worked every time; prefer inline until limit resets
- `git diff -I` needs `--no-ext-diff` when an external diff driver is configured
- `roborev close` on failed jobs 404s (no review row) — phantom backlog count is structural
- Kraken Drive archive: manual download only; `master_q4/` layout; FX history only from 2020-03 (fiat-fiat launch)

## Next Session

- Branch: session branch merged via #456/#457; fork fresh from main
- Suggested priorities:
  a. **#443 BDBB-SOL Phase 1** — fully unblocked; `hd_kraken_ohlcvt("SOL")` = 39,743 hourly bars from 2021-06. M/G/∞ fit + R/θ/signed-flow diagnostics + R-vs-Amihud-vs-Kyle tail test
  b. **#449** — xgb_drif A/B (mirror cakici_design_ab) + ADV gate + missing min-stocks guard
  c. **#389 Phase C** — `simulate_paths()` (parametric mvrnorm + block bootstrap) per audit spec
  d. **#435** — index collapsible-row articles table
  e. **#451** — QuantMind review (browser needed for SPA pages; paper digest → wiki promotable any time)
  f. Re-render leaderboard/vignettes after next full `tar_make` (picks up #452 deltas + registry rows)
- Quarterly chore (from #457): Kraken update ZIP → `KRAKEN_ZIP_PATH=... Rscript scripts/fetch_kraken_ohlcvt.R` → `bash scripts/upload_kraken_hf.sh`
- Deferred/awaiting user: #278 OLMAR data source $ decision (Norgate vs EODHD vs CRSP vs defer); #450 $20M ADV sweep (low-pri)
