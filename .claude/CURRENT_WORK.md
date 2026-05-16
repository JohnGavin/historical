# Current Work (Session 2026-05-16 — Opus marathon, ended)

**Last updated:** 2026-05-16 (session ended)
**Previous session:** 2026-05-14 → 2026-05-15 (#114 HRP + #143 ADV cap + #158 Solana, all merged to main)
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
