# Cost Assumptions Audit — 2026-06-04

**Issue:** [#125 — Cost model audit: are our assumptions realistic?](https://github.com/JohnGavin/historical/issues/125)
**Related:** [#424 — DRIF net SR -1.84 Training dominates by cost model](https://github.com/JohnGavin/historical/issues/424)
**Auditor:** fixer agent (worktree-agent-a5c4bb1f2615254e9)
**Date:** 2026-06-04
**Scope:** Read-only audit of all 14 named strategies. No R files modified.

---

## Method

For each of the 14 strategies in `R/plan_strategy_names.R`:

1. Located the plan file (`R/plan_<name>.R`)
2. Read the `*_params` target to find `cost_per_trade`, `borrow_rate_annual`, and any cost-related fields
3. Located the portfolio/returns target and inspected the actual cost deduction call
4. Cross-referenced `backtesting-assumptions.md` defaults:
   - cost_per_trade = 0.005 (0.50%)
   - borrow_rate_annual = 0.03 (3%/yr)
   - est_turnover = 0.80 (monthly decile strategy)
   - winsor_cap = ±20%/month
5. Computed break-even gross cost where applicable using:
   `breakeven_cost = cost_per_trade × 2 × n_trades_per_year / 2`
   where `n_trades_per_year = turnover_pct_per_period × periods_per_year`
6. Compared to StratProof benchmark (0.25–0.30% round-trip per trade, institutional-grade)

Sources read:
- `R/plan_strategy_names.R` — 14-strategy inventory with turnover/frequency metadata
- `R/plan_stock_backtest.R` — shared `portfolio_longshort()` and `portfolio_longshort_hrp()` helpers
- `R/plan_drif.R` — factor DRIF
- `R/plan_factormax.R` — factor MAX
- `R/plan_ltr_momentum.R` — LTR LambdaMART
- `R/plan_risk_state.R` — RSC VIX overlay
- `R/plan_turn_of_month.R` — TOM calendar overlay
- `R/plan_avoid_worst.R` — avoid worst days (not tradeable)
- `R/plan_mom_prepeak.R` — pre-peak/post-peak/combined momentum
- `R/plan_commodities_mean_reversion.R` — CMR commodity mean reversion
- `R/plan_xgb_signal.R` — XGB monotonic DRIF
- `R/plan_portfolio_opt.R` — PSO meta-strategy
- `.claude/rules/backtesting-assumptions.md`

---

## Per-Strategy Table

| # | code_name | plan_file | cost_per_trade | borrow_rate | turnover_est (× annual) | winsor_cap | asset_class | cost_realism_verdict |
|---|-----------|-----------|---------------|-------------|------------------------|------------|-------------|---------------------|
| 1 | avoid_worst | plan_avoid_worst.R | **None** | None | N/A | None | equity_etf | N/A — not tradeable |
| 2 | drif | plan_drif.R | **0.00% (MISSING)** | 0.00% | ~0.4× (factor) | ±20% | equity_factor | **CRITICAL** |
| 3 | fac_max | plan_factormax.R | **0.00% (MISSING)** | 0.00% | ~0.3× (factor) | ±20% | equity_factor | **CRITICAL** |
| 4 | rsc | plan_risk_state.R | **0.00% (MISSING)** | 0.00% | ~0.1× (regime switch) | None | equity_etf | **MAJOR** |
| 5 | ltr | plan_ltr_momentum.R | 0.10% (10bps) | 3.00% | ~2.4× | ±20% | equity_stock | REALISTIC |
| 6 | tom | plan_turn_of_month.R | 0.05% (5bps RT/switch) | 0.00% | ~0.24× | None | equity_etf | REALISTIC |
| 7 | stk_max | plan_stock_backtest.R | 0.50% (50bps) | 3.00% | 9.6× | ±20% | equity_stock | AGGRESSIVE |
| 8 | stk_drif | plan_stock_backtest.R | 0.50% (50bps) | 3.00% | 9.6× | ±20% | equity_stock | AGGRESSIVE |
| 9 | xgb_drif | plan_xgb_signal.R | 0.50% (50bps) | 3.00% | 9.6× | ±20% | equity_stock | AGGRESSIVE |
| 10 | pso_optimal | plan_portfolio_opt.R | **None (meta)** | None | N/A | None | multi_strategy | N/A — meta |
| 11 | cmr | plan_commodities_mean_reversion.R | 0.20% (20bps) | 0.00% | 12.0× | None | commodity | REASONABLE |
| 12 | mom_prepeak | plan_mom_prepeak.R | 0.10% (10bps) | 0.00% | 1.2× | ±20% | equity_stock | POSSIBLY LOW |
| 13 | mom_postpeak | plan_mom_prepeak.R | 0.10% (10bps) | 0.00% | 1.2× | ±20% | equity_stock | POSSIBLY LOW |
| 14 | mom_combined | plan_mom_prepeak.R | 0.10% (10bps) | 0.00% | 1.2× | ±20% | equity_stock | POSSIBLY LOW |

**Turnover × annual** = (turnover_pct_per_period_avg from strategy_names × periods/yr). Monthly strategies: × 12. Daily strategies (avoid_worst, rsc, tom): daily frequency but most hold positions for days to weeks.

---

## Detailed Findings

### Critical Issues (2)

#### Finding 1 — drif: Zero Cost Deduction (links to #424)

**File:** `R/plan_drif.R`
**Target:** `drif_portfolio`
**Code:**
```r
port_ret <- mean(selected$actual_ret)  # gross, no cost subtracted
```

**drif_params** contains: `n_top`, `enet_params`, training dates — **no cost fields whatsoever**.

**The caption in `R/plan_stock_backtest.R`** (function `stk_all_caption`) explicitly states "Factor-level trades 2–4 positions with ~40% turnover at **0.10%/trade**." This implies a cost model, but **no code implements it** in `plan_drif.R`.

**What gross returns represent:** Factor DRIF selects the top-N DRIF factors (e.g., HML, SMB) from a universe of factor ETFs. Each month: 2–4 positions held. With ~40% turnover and 2–4 positions, monthly cost at 0.10%/trade would be approximately:
- 0.40 × 0.10% × 2 (round-trip) = 0.08%/month = ~0.96%/yr

At factor-ETF level, 10bps/trade is plausible but not applied. **Net returns = Gross returns for drif.**

**Impact:** This is the proximate cause of the phenomenon documented in #424 (net SR -1.84 Training, +0.67 Validation-only). The DRIF cost model used at the stock-level in `stk_drif` (0.50%/trade × 80% turnover) is dramatically larger than what would be appropriate for the factor-level `drif` strategy. The leaderboard compares `drif` (zero-cost factor returns) against `stk_drif` (heavily cost-penalised stock returns) — an apples-to-oranges comparison.

**Cross-link:** See #424 for the SR decomposition that motivates this finding.

#### Finding 2 — fac_max: Zero Cost Deduction

**File:** `R/plan_factormax.R`
**Target:** `fm_portfolio`
**Code:**
```r
port_ret <- mean(factor_rets$monthly_ret)  # gross, no cost subtracted
```

**fm_params** similarly has no cost fields. Same gap as drif. The stk_all_caption implies 0.10%/trade at factor-level, but no code implements it.

**Impact:** Factor MAX appears in `pso_optimal` as a constituent. PSO optimises on `fac_max` gross returns, not net returns. The combined PSO weight vector is therefore optimised to a cost-inflated objective.

---

### Major Issues (1)

#### Finding 3 — rsc: No Cost for Regime Switches

**File:** `R/plan_risk_state.R`
**Target:** `rsc_portfolio`
**Code:**
```r
ret_strategy = exposure * spy_ret + (1 - exposure) * rf_daily
```

No cost subtracted on regime transitions. RSC switches between 100%/50%/10% SPY exposure when regime changes (benign → cautious → hostile). Each switch requires an ETF trade.

**Estimated impact:** RSC uses daily SPY returns. Regime changes occur infrequently — perhaps 10–20 times per year based on the VVIX/VIX threshold design. At SPY's typical spread of ~0.01% (1 basis point), round-trip cost ≈ 0.02% per switch × 15 switches/yr ≈ 0.30%/yr. At institutional scale with slippage: still small. The gap is real but the economic impact is likely minor (< 0.5%/yr). **MAJOR** rather than Critical.

**rsc_overlay_drif and rsc_overlay_fac_max:** These apply the regime scaling to existing drif/fac_max returns, which already have no cost model. No incremental cost issue in the overlay, but it inherits Finding 1/2.

---

### Minor Issues (2)

#### Finding 4 — mom_prepeak / mom_postpeak / mom_combined: 10bps May Be Low

**File:** `R/plan_mom_prepeak.R`
**Params:** `cost_per_trade = 0.0010`
**Universe:** ~51 US non-ETF equities (same as LTR)

**Verdict:** The comment says "10bps per trade (matches ltr_params)". For a 51-stock universe of US equities, 10bps is likely too optimistic. Real mid-cap US stocks have spreads of 5–20bps depending on liquidity. Institutional impact for 51 stocks is small (positions are small relative to float). **10bps is borderline realistic** but the note "methodology-demo scope" correctly signals that these results are not representative of a full-universe backtest.

**Annual cost at 10bps, 30% turnover/period, monthly:** 0.30 × 0.10% × 2 (round-trip) × 12 months = **0.72%/yr**. This is low for stock-level strategies. Break-even gross CAGR = 0.72%.

#### Finding 5 — pso_optimal: Inherits Cost Gaps from Constituents

**File:** `R/plan_portfolio_opt.R`
**Params:** No `cost_per_trade` (meta-strategy — correct)
**Issue:** PSO uses `fac_drif = drif_portfolio$portfolio_ret` and `fac_max = fm_portfolio$portfolio_ret` directly. These are **gross returns** (Findings 1 and 2). PSO therefore optimises weights against an inflated objective for the factor strategies. The resulting optimal weights likely overweight `fac_max` and `fac_drif` because they appear better (gross) than `stk_max` and `stk_drif` (net). This is a downstream consequence of Findings 1–2, not an independent gap.

---

## Comparison to StratProof / Realistic Costs

The StratProof framework (referenced in issue #125) applied 0.25–0.30% round-trip per trade and found **16 of 22 crypto strategies lost money**.

For equities, realistic costs by asset class:

| Asset class | StratProof equivalent | Our assumption | Gap |
|-------------|----------------------|----------------|-----|
| Large-cap equity ETF (SPY, QQQ) | 0.02–0.05% RT | TOM: 0.05% RT ✓, RSC: 0% ✗ | RSC missing |
| Factor ETFs (2–4 positions) | 0.05–0.10% RT | drif/fac_max: 0% ✗ | Both critical |
| Mid/large-cap US stocks | 0.15–0.30% RT | stk_max/stk_drif/xgb_drif: 0.50% × 2 = 1.0% RT | Ours is MORE conservative than StratProof |
| Commodity futures ETFs | 0.20–0.40% RT | CMR: 0.20% RT | At low end of realistic |
| Small ~51-stock demo universe | 0.10–0.20% RT | ltr/mom: 0.10% RT | Below mid-range |

**Key takeaway:** The stock-level strategies (stk_max, stk_drif, xgb_drif) use MORE aggressive cost assumptions than StratProof would apply (1.0% round-trip vs 0.25–0.30%). The factor-level strategies (drif, fac_max) use NO cost assumptions. The portfolio is therefore internally inconsistent: factor strategies are systematically favoured over stock strategies in any composite view.

---

## Turnover Estimates from strategy_names Target

From `R/plan_strategy_names.R` (`turnover_pct_per_period_avg`):

| code_name | frequency | turnover_pct/period | annual_equivalent | cost_annual (at coded rate) |
|-----------|-----------|--------------------|--------------------|----------------------------|
| avoid_worst | daily | 50% | not applicable | N/A |
| drif | monthly | 30% | 3.6× | 0% (MISSING) |
| fac_max | monthly | 30% | 3.6× | 0% (MISSING) |
| rsc | daily | 50% | not direct (regime-based) | 0% (MISSING) |
| ltr | monthly | 20% | 2.4× | 0.048%/yr (gross) |
| tom | daily | 10% | ~12 switches/yr | 0.60%/yr (gross) |
| stk_max | monthly | 100% | 12× | 2.40%/yr + 3% borrow |
| stk_drif | monthly | 100% | 12× | 2.40%/yr + 3% borrow |
| xgb_drif | monthly | 100% | 12× | 2.40%/yr + 3% borrow |
| pso_optimal | monthly | 10% | 1.2× | meta |
| cmr | monthly | 100% | 12× | 4.80%/yr |
| mom_prepeak | monthly | 30% | 3.6× | 0.072%/yr (gross) |
| mom_postpeak | monthly | 30% | 3.6× | 0.072%/yr (gross) |
| mom_combined | monthly | 30% | 3.6× | 0.072%/yr (gross) |

Note: stk_max/stk_drif/xgb_drif list 100% turnover/period, which combined with the `est_turnover = 0.80` hardcoded in `portfolio_longshort()` means 80% of the portfolio turns monthly. Annual cost = 0.80 × 0.50% × 2 × 12 = **9.6%/yr** in one-way costs plus **3%/yr borrow** = **12.6%/yr total before winsorisation**.

---

## Break-Even Sensitivity

The break-even gross CAGR (minimum gross return needed to produce 0% net) as a function of cost and turnover:

| Strategy tier | Annual cost | Break-even gross CAGR |
|---------------|------------|----------------------|
| drif/fac_max (0% cost) | 0%/yr | 0% — any positive gross is net-positive |
| TOM/RSC ETF overlay | ~0.30–0.60%/yr | ~0.60% gross |
| LTR/mom (10bps, 2-3× turn) | ~0.72–1.44%/yr | ~1.44% gross |
| CMR (20bps, 12× turn) | ~4.80%/yr | ~4.80% gross |
| stk_max/stk_drif/xgb_drif (50bps, 9.6× turn) | ~12.60%/yr | ~22% gross (including borrow) |

**The `backtesting-assumptions.md` rule states:** any net CAGR > 20% should be treated as not credible. The stock-level strategies must achieve 22% gross CAGR simply to break even — an extremely high bar that naturally explains why stock-level strategies show poor or negative net returns in backtests.

**For the factor-level strategies** (drif, fac_max): the true break-even at realistic costs (0.10%/trade, 30–40% turnover, factor ETFs) is approximately:
- Annual cost = 0.35 × 0.10% × 2 × 12 ≈ 0.84%/yr
- Break-even gross CAGR ≈ **0.84%** — extremely low, essentially any positive factor premium passes this bar

This explains the internal inconsistency: drif (gross) will almost always beat stk_drif (net) purely because drif has no cost penalty, not because it has better gross returns.

---

## Phase 2 Recommendations

### Priority 1 (Critical — Block Leaderboard Comparisons Until Fixed)

**P1A — Add cost model to drif (plan_drif.R)**

Add `cost_per_trade` to `drif_params` (suggest 0.10% = 10bps for factor ETF trades) and deduct it in `drif_portfolio`:

```r
# Proposed addition to drif_params:
cost_per_trade = 0.0010,  # 10bps for factor ETF round-trip
est_turnover   = 0.35     # ~35% factor rotation per month

# Proposed deduction in drif_portfolio:
# After computing port_ret (gross):
cost_monthly <- drif_params$est_turnover * drif_params$cost_per_trade * 2
port_ret_net  <- port_ret_gross - cost_monthly
```

Alternatively, add the cost subtraction inside `drif_portfolio` using the stk_all_caption implied rate of 0.10%/trade with the actual number of positions changed.

**P1B — Add cost model to fac_max (plan_factormax.R)**

Same pattern. `fm_params` needs `cost_per_trade = 0.0010` and the `fm_portfolio` target needs the deduction. Factor MAX trades 2–4 positions; similar logic applies.

**P1C — Rerun leaderboard after P1A/P1B**

After adding costs to drif/fac_max, rerun `tar_make()` and regenerate the leaderboard metrics. The drif Training SR of -1.84 (documented in #424) should improve once the gross-vs-net comparison is eliminated.

### Priority 2 (Major)

**P2A — Add cost model to rsc (plan_risk_state.R)**

Add `cost_per_switch` to `rsc_params` (suggest 0.01% = 1bp for SPY one-way, 2bp round-trip) and apply on regime-change days:

```r
# On switch days (exposure changes):
# ret_net = ret_gross - switch_cost
```

Expected impact: < 0.30%/yr — minor but correct to include for internal consistency.

### Priority 3 (Minor)

**P3A — Document why ltr/mom use 10bps**

Add an explicit comment in `ltr_params` and `mom_prepeak_params` noting the "demo scope" rationale and referencing the 51-stock universe size. This prevents future readers from assuming 10bps is the project-wide assumption for stock-level strategies.

**P3B — Standardise stk_all_caption claim**

The `stk_all_caption` text says "Factor-level trades ... at 0.10%/trade" but the code has 0% cost. Fix by either: (a) implementing 0.10%/trade in plan_drif.R + plan_factormax.R (preferred — P1A/P1B), or (b) changing the caption to state "gross returns (cost model forthcoming)" until P1A/P1B are implemented.

---

## Phase 3 Candidates (Architectural)

These require user decisions before implementation.

### C1 — Centralise cost parameters

Currently each plan file declares its own `cost_per_trade`. A centralised `cost_params` target (analogous to `stk_params`) would enforce consistency across strategies that share an asset class:

```r
# Proposed: plan_cost_params.R
tar_target(cost_params, {
  list(
    equity_etf_rt   = 0.0002,  # 2bps round-trip for SPY/QQQ
    equity_factor_rt = 0.0010, # 10bps for factor ETFs
    equity_stock_rt  = 0.0050, # 50bps for mid-cap stocks
    commodity_rt     = 0.0020, # 20bps for commodity futures ETFs
    borrow_annual   = 0.03     # 3%/yr for short positions
  )
})
```

Each plan would then reference `cost_params$equity_factor_rt` rather than hardcoding.

### C2 — HRP-weighted cost for stk_max_portfolio_hrp

`stk_max_portfolio_hrp` uses `portfolio_longshort_hrp()` which has `adv_monthly` and `adv_pct_cap` parameters for ADV-constrained sizing. The cost model should account for capacity — larger positions in less liquid stocks cost more. A size-weighted cost model (e.g., cost scales with position_size / adv_cap) would be more realistic but requires ADV data.

### C3 — Borrow rate sensitivity for short strategies

The borrow rate (3%/yr default) applies to stk_max, stk_drif, xgb_drif, and ltr. For small-cap stocks, borrow can be 5–15%/yr. For the 51-stock demo universe (ltr/mom), borrow is absent from the cost model. A sensitivity table showing net SR vs borrow_rate (0%, 3%, 6%) would quantify the impact without requiring code changes.

---

## Summary by Severity

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 2 | drif and fac_max have zero cost deduction — gross returns in leaderboard |
| Major | 1 | rsc has no cost on regime switches |
| Minor | 2 | mom_* at 10bps likely too low; stk_all_caption inconsistent with drif code |
| Architectural | 3 | Centralise cost params; HRP capacity-cost; borrow sensitivity |

The Critical findings directly explain the phenomenon in #424 (DRIF net SR dominated by cost model at stock-level vs zero cost at factor-level). Phase 2 Priorities P1A and P1B must be implemented before any cross-strategy SR comparisons in the leaderboard are meaningful.

---

## Files Audited (Read-Only)

No R files were modified during this audit. All findings are based on static code inspection of:

- `R/plan_strategy_names.R`
- `R/plan_stock_backtest.R`
- `R/plan_drif.R`
- `R/plan_factormax.R`
- `R/plan_ltr_momentum.R`
- `R/plan_risk_state.R`
- `R/plan_turn_of_month.R`
- `R/plan_avoid_worst.R`
- `R/plan_mom_prepeak.R`
- `R/plan_commodities_mean_reversion.R`
- `R/plan_xgb_signal.R`
- `R/plan_portfolio_opt.R`
- `.claude/rules/backtesting-assumptions.md`
- `.claude/rules/execution-delay-sensitivity.md`
- `.claude/rules/position-sizing-guardrails.md`
