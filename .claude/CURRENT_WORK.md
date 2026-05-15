# Current Work (Session 2026-05-14)

**Last updated:** 2026-05-14 → 2026-05-15 (session ended)

## Active Branch

`main` — clean, all 4 session commits pushed to origin

## Session Summary

Two empirical experiments on the `stk_max` long-short factor strategy:

1. **#114 HRP allocator** (Lopez de Prado 2016, via `HierPortfolios` CRAN)
   - Phase 1: 4-strategy meta-allocator — HRP underperformed PSO (wrong universe)
   - Phase 2: 660-stock per-leg HRP — improved Sharpe 0.3 across all periods, cut turnover 21%, but still negative Sharpe everywhere

2. **#143 gap #3 ADV-cap cost realism**
   - 10% participation cap on per-stock notional
   - Improved Sharpe 0.18 further (Full -1.04→-0.86, Validation -0.61→-0.26)
   - Counter to thesis: cap *raised* turnover and monthly cost; improvement came from weight redistribution, not cost reduction

3. **#158 filed** — Solana APIs investigation (incl. tokenised-equity DEX depth as ADV proxy)

## Commits Pushed

- `2105727` — HierPortfolios dependency (#114 Phase 0)
- `5e72205` — port_hrp_weights target (#114 Phase 1)
- `cde2ea2` — HRP-weighted Factor MAX long-short (#114 Phase 2)
- `796a42b` — ADV-based participation cap (#143 gap #3)

## Empirical Conclusion

Three sequential portfolio-construction improvements (PSO → HRP → HRP+ADV) moved `stk_max` Full Period Sharpe from -1.33 to -0.86. **Never crossed zero.** Cost drag floor reached at 17-18%/year. Validation seal now broken on `stk_max` family.

## Next Session Tasks

### Immediate (highest leverage)

- [ ] **Pivot to #150** (survivorship bias in 660-stock universe). Three sequential allocation/cost interventions on `stk_max` cannot beat a survivorship-inflated gross alpha number. Until #150 is resolved, every leaderboard Sharpe is biased upward.

### Deferred

- [ ] #114 Phase 2b (DRIF with HRP) — likely reproduces Phase 2 pattern; defer until #150
- [ ] #114 Phase 3 (HERC + DHRP) — same reason
- [ ] #114 Phase 6 (Wasserstein regime detector via `tdaverse::phutil`) — only `tdaverse` application that doesn't require profitable underlying; speculative
- [ ] #143 gap #3 follow-ups: Almgren-style square-root impact + per-stock spread proxy — would *reduce* turnover (real cost levers, unlike ADV cap)
- [ ] #143 other open gaps: #1 multiple-testing, #4 regime-conditional Sharpe, #5 qa gates, #6 loss-cluster analysis, #7 ±20% sweeps
- [ ] #158 — Solana API smoke-test (defer to bandwidth)

### Sealed but worth noting

- Validation period for `stk_max` family is now compromised by tuning. Future deployment requires either a new validation window post-2026 or vignette-level disclosure.

## Open Issues This Session

- #114 (HRP) — 2 phase-summary comments; open
- #143 (Tinsley audit) — 1 implementation comment; open
- #158 (Solana APIs) — newly filed

## Files Modified This Session

- `tproject.toml`, `flake.nix`, `packages/historicaldata/DESCRIPTION` (HierPortfolios dep)
- `R/plan_portfolio_opt.R` (HRP Phase 1)
- `R/plan_stock_backtest.R` (HRP Phase 2 + ADV cap, ~417 net lines)

## Burn Notes

Session burn: ~$294 → projected ~$687 (137% of $500 weekly cap). Resume #150 in fresh context to avoid quadratic continuation cost.
