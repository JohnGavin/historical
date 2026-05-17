# Current Work (Session 2026-05-17 — roborev cluster sweep, ENDED)

**Last updated:** 2026-05-17 session end (13 PRs merged, 4 issues filed, 4 worktrees recovered)
**Previous session:** 2026-05-16 (Opus marathon, ended — summary preserved below)

## Final state

`main` synced through `fbdbefe`. Working tree clean. 0 commits ahead of origin.

## 2026-05-17 merged (13 PRs)

| PR | Subject | Notes |
|---|---|---|
| #183 | fix(vignette): NA hygiene in 3 vig_pair code targets (PR-E) | rolling vol default, survivorship filter, `recode`→`case_match` |
| #184 | fix(ranked): deterministic LAST() in vol GROUP BY (PR-G) | `LAST(vol ORDER BY date)` + `MAX(date)` |
| #185 | fix(query): split-and-bind hd_ohlcv for mixed-dataset batches (PR-F) | closes silent data loss on `c("AAPL","BTC")` |
| #187 | fix(stock-backtest): turnover drift + iterative ADV cap (cluster A) | F1 cash-proxy DEFERRED (stale) |
| #188 | fix(momentum): F1-F6 (cluster B, squashed) | **agent hit budget — needs spot-check** |
| #189 | fix(ecb+guardian): timeout / CISS frequency / rate-limit / defensive extract (cluster C) | 30 new tests, all pass |
| #190 | fix(docs): dark-mode + bslib + XSS + DRY (cluster D, 5 commits) | **contrast check not run — needs visual review** |
| #191 | feat(qa): qa_look_ahead_bias gate (cluster E) | **mandatory follow-up from PR #181 done.** Live tripwire passes (0 detections) |
| #193 | fix(L+O+M): dynamic prose + substitute + NA cumprod + cor complete.obs (PR-LMO) | L2 deferred |
| #195 | docs(wiki): daloopa gap analysis (#78) | recovered from prior-session worktree |
| #197 | docs(knowledge): Quantocracy May-3 roundup (#126) | recovered + CHANGELOG conflict dropped |
| #198 | fix(equity+groups): SP500 fetch integrity + MIDD.L FTSE 250 (PR-Q) | haiku-then-Opus recovery pattern |
| #199 | chore(repo): untrack 74 orphan vignette RDS (~7.5 MB) (PR-S) | smaller than originally pitched |

Plus **#196 closed as duplicate** of PR #164 (pairwise alignment, recovered worktree was redundant).

## 2026-05-17 issues filed (4)

- **#186** registry/parquet schema drift — `crypto_daily` declares `market_cap` but parquet doesn't carry it. Side-finding from PR-F test assertion.
- **#192** Kinlay agentic-research workflow gap audit — verbatim build order + DuckDB 5-table schema + per-pillar `HAVE/PARTIAL/MISSING` checklist. Most pillars MISSING. PR #191 covers 1 of 6 Critic defect classes.
- **#194** AlphaVantage tracker — [business-science/alphavantager](https://github.com/business-science/alphavantager) + `AlphaVantage_API_KEY` env var + 5-phase plan + free-tier constraints (5/min, 500/day).
- **#200** OLMAR-1222 strategy adoption + **first concrete use case for #192's research-log DB**. 5-phase plan including S&P 500 MVP, leverage sweep, research-log DB integration, S&P 600 fetch, FTSE 250 cross-geography.

## Mandatory follow-up DONE this session

- ✅ `qa_look_ahead_bias` target in `R/plan_qa_gates.R` per `look-ahead-bias-prevention` rule (PR #191) — the carryover from PR #181 is complete

## Next-session task buckets

### High priority

- [ ] **#187 F1 cash-proxy decision** — agent deferred as STALE (identifiers `cash`/`etf_m`/`cash_proxy` not found in current `R/plan_stock_backtest.R`). User must decide: was a cash-proxy fallback ever intended for OOS, or did the finding reference deleted code? If yes-intended, file Phase 2 issue + new branch.
- [ ] **#188 cluster B spot-check** — momentum/utils_align changes (290 LOC squashed, agent budget-killed) touched FF month-key joins, ASOF coercion, baseline definition, turnover, overfit guard. Run `tar_make()` and compare metrics vs prior; flag any unexpected deltas.
- [ ] **#190 cluster D visual review** — render `docs/examples.qmd` + `docs/backtest.qmd` + `docs/macro-defense-rotation.qmd` in BOTH light and dark mode; run `~/docs_gh/llm/.claude/scripts/check_dark_contrast.sh`; smoke `quarto render`.

### Tier 3-4 roborev backlog still LIVE

- [ ] **PR-R metrics canonicalisation** — `plan_kelly_variants.R` uses `sd × √12` for vol + `mean/sd × √12` for Sharpe (simple); `plan_etf_replication.R` uses `prod(1+r)^(12/n)-1` for return + `sd × √12` for vol (compound). Leaderboard compares incomparable numbers. Extract `R/utils_metrics.R::calc_backtest_metrics()` once, swap all sites. Sonnet, medium PR.
- [ ] **PR-T pkgload sweep** — 11+ in-target `pkgload::load_all()` calls. Replace with single `tar_option_set(packages="historicaldata")` in `_targets.R`. Sonnet, refactor.
- [ ] **L2 vignette Sharpe prose audit** — hardcoded `(0.26)` / `(0.79)` in `docs/stock-backtest.qmd` and "42 features" repeated in `docs/drif.qmd`. Each must read from a specific target's metric. Sonnet, prose-focused.
- [ ] **Tier 5 test coverage gaps** — `hd_macro_vintages()` / `hd_revision_analysis()` zero tests; `qa_summary` has no deps so validates nothing; QA pipeline skips fm_*/bt_* targets (12+15).

### Roborev hygiene

- [ ] `roborev close` sweep — 74 failed verdicts in tracker since 2026-05-10, most overlap with today's merged PRs but no formal close ran. Batch-close confirmed-stale per-job.
- [ ] Other Tier 5/6 findings from the deep sweep (`@param dataset` doc lies, `dataset_registry` fm_monthly date assumption, `plan_qa_vignette.R` raw SQL).

### Infrastructure (from #192 audit)

- [ ] Pick one pillar from #192's per-pillar checklist. Recommended order per Kinlay: PIT data wrapper enforcement → research-log DB (DuckDB 5 tables) → 4-role agent definitions → Critic validation suite → human-gate UI.
- [ ] **#200 OLMAR-1222 Phase 1** (`R/plan_olmar.R`) would benefit from #192 Phase 3 (research-log DB integration) — sequencing question.

### Other issues carried forward

- [ ] **#171 Alpaca scrape** — pending `ALPACA_KEY`/`ALPACA_SECRET` in `~/.Renviron`
- [ ] **#194 AlphaVantage Phase 0** — pending `AlphaVantage_API_KEY` in `~/.Renviron` + add to `tproject.toml`
- [ ] **#178 NMOF/neighbours** — research/adopt
- [ ] **#170 Macrosynergy** — research, defer
- [ ] **#168 Phase 2+** — IBKR Gateway install manual step
- [ ] **#142 Phase 1** — restate USD strategies in EUR using DEXUSEU + DEXGEUS chain (now in registry from #174)
- [ ] **#160 PR 3** — `strat_corr_matrix` + `strat_keff_vertox` + `strat_deflated_sharpe` targets + leaderboard column + vignette
- [ ] **#160 PR 4** — rule updates (`backtest-robustness`, `statistical-reporting`, `analytical-review-checklist`)

## Key learnings logged this session

1. **Quick-fix (haiku) cannot commit/push** — has no Bash tool. With `isolation: "worktree"` it'll Edit whichever absolute paths the prompt names (orchestrator's main checkout if you give those paths). Use `fixer` (sonnet) for anything that must commit; reserve quick-fix for pure-Edit tasks where orchestrator commits.
2. **Parallel sonnet dispatch can blow budget** — 3 of 5 clusters hit "org monthly limit" mid-flight. Survivor commits were preserved in worktrees; orchestrator pushed and verified on their behalf. Sequential dispatch with verification between would have been safer.
3. **Working-tree size ≠ git-tracked size** — initial PR-S pitched as "200 MB cleanup" was based on `du -sh inst/extdata/vignettes/`; the 3 huge files were already untracked. Real win was 7.5 MB. Always check `git ls-files` size separately from working-tree size.
4. **Worktree recovery is high-value** — 3 prior-session worktrees contained unpushed real work (daloopa wiki, Quantocracy curation, pairwise commit). Per `safe-deletion` rule, never delete agent worktrees without verifying branch state + uncommitted content. Pushing on behalf preserves the work.
5. **roborev finding stale-rate continues high** — many cluster findings (cluster A F1, cluster D in some areas, parts of the original deep sweep tabulation like the 226 MB git bloat) turned out STALE once verified against current code. Always read current code before planning fix scope.
6. **Live tripwire validates new QA gates** — PR #191's `qa_look_ahead_bias` test runs against current `R/` to assert 0 detections; this caught a comment-line false-positive that would have broken every future `tar_make()`. Refined the checkers; tripwire now passes. Pattern worth repeating for every new QA gate.

## Cleanup completed this session

- 4 agent worktrees removed (3 prior-session + 1 PR-LMO duplicate mystery worktree)
- 14 stale `worktree-agent-*` local branches deleted
- 10 stale `origin/...` remote refs pruned
- `.claude/worktrees/` from 380 MB → 12 K

---

# Previous Session Summary (2026-05-16 — Opus marathon, ended)

PR-H verified STALE (momentum look-ahead findings already fixed by #181 monthly_ret_lead).

## 2026-05-17 issues filed

- **#186** Registry/parquet schema drift — crypto_daily declares `market_cap` column not present in parquet. Side-finding from PR-F test assertion failure.

---

# Previous Session Summary (2026-05-16 — Opus marathon, ended)

**Burn:** session-start $421 → end (well over weekly cap; full inline Opus per user direction).

## Active Branch

`main` — clean, fully synced with origin. 12 PRs merged this session.

## Session Summary

Marathon session: data-source registry adds, Vertox K_eff disambiguation + helper, roborev sweep, multiple research issues + audits. All work merged.

### Merged to main (12 PRs)

| PR | Subject | Commit |
|---|---|---|
| #169 | feat(registry): DGS20 20Y Treasury yield (closes #167) | `59d5a34` |
| #172 | feat(historicaldata): yfscreen + UK ETF universe snapshot (#168 Phase 1.5) | `a3ca96e` |
| #173 | feat(historicaldata): Alpaca assets snapshot scaffolding (#171) | `d55f894` |
| #174 | feat(registry): DEXUSEU + DEXGEUS EUR/USD chain (#142 Phase 0) | `c4216d2` |
| #175 | refactor: K_eff → K_eff_acf (#160 PR 1) | `0496227` |
| #177 | feat: hd_strat_keff_vertox helper + Frobenius rename (#160 PR 2) | (squashed) |
| #179 | fix(security): SQL injection in metadata.R (roborev PR A) | `a9728b5` |
| #180 | fix: silent tryCatch sweep (roborev PR B) | `7450759` |
| #181 | fix: look-ahead bias calendar-shift + slider lead (roborev PR C) | `4564b20` |
| #182 | chore(roborev): HTML-in-git wontfix policy (PR D, 10 jobs closed) | `dfc98bc` |

### New issues filed
- **#170** — Macrosynergy macro-aware equity indices; JPMaQS → FRED mapping; Annex 2 (55 rows) transcribed inline. `enhancement, low-priority`.
- **#171** — Datawookie alpacar tradability flags (`shortable`, `easy_to_borrow`, `fractionable`, `marginable`, `attributes`). Direct dep for #114 Phase 2 long-short. `enhancement, low-priority`.
- **#178** — NMOF + neighbours for least-correlated K-of-N subset selection (Schumann 2021). Optimisation dual of `hd_strat_keff_vertox` from #160 PR 2. `enhancement, low-priority`.

### Issue audits added
- **#142** Beyond Passive FX overlay — amendment comment on data-availability gaps + tail-protective vs drift split + named regimes; labels added.
- **#160** Vertox K_eff — full 4-PR phased plan with file-by-file collision map, naming decision (`K_eff_acf` / `K_eff_strat` / `K_eff_frob`), per-PR LOC + vehicle.
- **#168** IBKR CPAPI — Phase 1-2 spike comment + yfscreen Phase 1.5 amendment.

### Roborev impact
- High-severity backlog on main: **179 → ~44** (~25 findings off the active list).
- 10 HTML-in-git jobs closed as wontfix with policy doc in `.roborev.toml`.
- 5 SQL findings closed by code refactor (PR A audit confirmed stale).
- 3 silent-tryCatch findings closed by PR B.
- 2 look-ahead findings closed by PR C.

## Next Session Tasks

### Mandatory follow-up (from PR C)

- [ ] **Add `qa_look_ahead_bias` target to `plan_qa_gates.R`** per `look-ahead-bias-prevention` rule. ~50 LOC, 4 sub-checks. Template lives in `model-evaluation-calibration` skill. Without this gate the lead-shift / forward-window pattern can recur in new code.

### High-leverage but multi-file (sonnet-worktree work per `auto-delegation` rule)

- [ ] **#150** Option A (point-in-time delisting data) — gated on either Alpaca creds (free path via #171 scrape) or paid CRSP/Sharadar. Still the highest-leverage unresolved issue per prior session's documented assessment.
- [ ] **#160 PR 3**: `strat_corr_matrix`, `strat_keff_vertox`, `strat_deflated_sharpe` targets + `deflated_sharpe` leaderboard column + vignette comparing raw vs deflated Sharpe.
- [ ] **#160 PR 4**: rule updates — `backtest-robustness` (K_eff_strat-guided stopping criterion), `statistical-reporting` §2 (K_eff_strat-aware FDR), `analytical-review-checklist` (which deflation method).
- [ ] **#142 Phase 1**: restate USD strategies in EUR using newly-merged DEXUSEU + DEXGEUS chain. ~5 backtests affected.

### Smaller cleanups (roborev backlog reduction)

- [ ] `R/plan_stock_backtest.R:181-183` — same silent-tryCatch antipattern in HRP weight computation (audit-caught but not roborev-flagged; in PR B body's out-of-scope follow-up).
- [ ] `R/plan_factormax.R` — `qa_summary` target has no dependency on `fm_*` targets; 9 factor-max outputs unvalidated by QA (roborev finding).
- [ ] `docs/stock-backtest.qmd` — hardcoded Sharpe values in prose violate `dynamic-prose-values` rule.
- [ ] `docs/vignette_utils.R` — unconditional dark-mode CSS breaks light-mode users.
- [ ] `R/plan_backtest.R` — outdated `tar_make` comment.

### Backtest re-run + CHANGELOG numbers

- [ ] `tar_make()` to surface any latent failures the new `cli_warn`s in PR B now expose.
- [ ] Re-run leaderboard targets to produce before/after Sharpe/CAGR numbers for the CHANGELOG "Accuracy fixes" entry referenced in PR C's body (look-ahead fix changes results).

### Other open issues (carried forward)

- [ ] **#171 follow-up**: run Alpaca scrape once `ALPACA_KEY`/`ALPACA_SECRET` in `~/.Renviron`. Wire to `equity_daily` to add tradability flags. Build `dv_long_short_tradability` validator.
- [ ] **#178** NMOF / neighbours — assess and adopt for subset selection.
- [ ] **#170** Macrosynergy — research issue, defer.
- [ ] **#168 Phase 2+** — IBKR Client Portal Gateway install (manual ~30 min) → resolve conids for 5 LSE ETFs → daily history pull for one ticker.

### Research backlog
- #163 Risk parity 58-year tail audit · #162 Optimal regime-dependent exposure sizing · #157 2^N multiverse · #144 stacking ensemble · #143 follow-ups (gaps #1, #4, #5, #6, #7).

## Key Learnings Worth Carrying Forward

1. **Roborev finding stale-rate is high** — 7 of 9 SQL findings from April-May reviews were already fixed by historical refactors but never closed. The post-commit hook doesn't re-check old open jobs. Recommend `roborev compact` periodically OR manual triage at session start.
2. **`yfscreen::create_payload(size = N)` is TOTAL desired, not page size** — internal chunking at 250/request. Documented in helper docstring.
3. **Audit before action** — original #160 audit missed `hd_keff` in `falsification.R` (third K_eff variant). Caught mid-PR-2; expanded scope. Future audits should grep ALL candidate files, not just those the issue body cites.
4. **PR scope can shrink dramatically when findings are stale** — PR A planned as "~7 file SQL sweep" became "2-site fix + close 7 stale jobs". Read code before planning fix scope.
5. **HTML-in-git is intentional for this project** — `docs/*.html` serves the Pages site directly from `main` `/docs/`. Reviewer pattern recognition (committed HTML is noisy) doesn't apply. Documented in `.roborev.toml`.
6. **Calendar-shift vs row-shift on grouped panels** — `dplyr::lead(ym)` after `group_by(ticker)` returns row-next, not calendar-next. For tickers with gaps, signal silently pairs with wrong-period returns. Use `seq.Date(d, by="1 month", length.out=2)[2]` for calendar-correct shift. New `next_ym()` helper in `plan_stock_backtest.R`.

## Burn Notes

Session ran inline Opus throughout (user explicitly bypassed audit recommendation to use sonnet worktrees). 12 PRs in one session is very high throughput for Opus. Next session opener should `/check` burn rate first; if still over cap, use a sonnet worktree for #160 PR 3 (multi-file targets work) and the `qa_look_ahead_bias` follow-up.
