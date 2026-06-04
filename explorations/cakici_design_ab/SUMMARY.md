# Cakici A/B Decile Construction — Prototype Results

**Issue:** #312 | **ADV threshold:** $5M | **Date run:** 2026-06-04

---

## Setup

Three variants of DRIF decile construction are compared using cached pipeline targets. The signal is `stk_drif_signal` (elastic-net predicted returns, 41578 rows). Monthly returns from `stk_monthly`; liquidity from `stk_monthly_adv` (column `adv_dollars`). Risk-free rate from `stk_rf`. ADV threshold: $5M (NYSE median ADV, applied uniformly across all months). Partition windows from `bt_partitions$equity`: Training 2005-01-01–2019-12-31 (120 months); Testing 2020-01-01–2022-12-31 (26 months); Validation 2023-01-01–present (23 months). Cost model: 0.5%/trade, 3%/yr borrow, ±20% winsorise. All variants use equal-weight long decile 1, short decile 10, 80% monthly turnover assumption.

---

## Results

| Variant | Period | Months | Gross SR | Net SR | Net CAGR | Max DD | Avg Long |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline | Training | 120 | -0.62 | -1.84 | -26.8% | -95.4% | 9 |
| Baseline | Testing | 26 | 1.22 | -0.45 | -5.6% | -19.2% | 10 |
| Baseline | Validation | 23 | 2.19 | 0.67 | 17.6% | -6.9% | 10 |
| Baseline | Full | 272 | -0.06 | -1.09 | -19.8% | -99.6% | 9 |
| A: filter-then-rank | Training | 120 | -0.63 | -1.84 | -27.0% | -95.5% | 9 |
| A: filter-then-rank | Testing | 26 | 1.22 | -0.45 | -5.6% | -19.2% | 10 |
| A: filter-then-rank | Validation | 23 | 2.19 | 0.67 | 17.6% | -6.9% | 10 |
| A: filter-then-rank | Full | 242 | -0.01 | -1.02 | -19.0% | -99.1% | 9 |
| B: rank-then-renormalise | Training | 120 | -0.63 | -1.84 | -27.0% | -95.5% | 9 |
| B: rank-then-renormalise | Testing | 26 | 1.22 | -0.45 | -5.6% | -19.2% | 10 |
| B: rank-then-renormalise | Validation | 23 | 2.19 | 0.67 | 17.6% | -6.9% | 10 |
| B: rank-then-renormalise | Full | 242 | -0.01 | -1.02 | -19.0% | -99.1% | 9 |

---

## Decile Turnover

Mean monthly Spearman rank correlations between decile assignments: Baseline vs A = **0.998**, Baseline vs B = **0.998**, A vs B = **1**. High correlations (> 0.90) indicate that the three variants assign most stocks to the same deciles, meaning the Baseline currently captures most of the same signal as A and B. Low correlation between Baseline and A/B would indicate the ADV gate materially shifts which names appear in the extreme deciles. See `results/decile_turnover.png` for the time-series of these correlations.

---

## Trade-off

Variant A (filter-then-rank) is closer to the Cakici (2023) paper: the universe is restricted to liquid names _before_ sorting on predicted returns, which avoids placing illiquid micro-caps in the long or short decile solely because of an extreme prediction. Variant B (rank-then-renormalise) preserves the full-universe ranking as an intermediate step and re-cuts deciles after gating, which captures information about where the survivors sit in the original rank distribution. In the full period, net Sharpe ratios are: Baseline = -1.09, A = -1.02, B = -1.02. In the held-out test period (2020-01-01–2022-12-31): Baseline = -0.45, A = -0.45, B = -0.45. The delta between variants in Sharpe terms reflects the practical impact of the ADV gate on portfolio composition under the current DRIF signal.

---

## Recommendation

On the evidence here, Variant A (filter-then-rank) is preferred for production because: (1) it matches the paper's construction intent most closely; (2) it avoids the risk of placing illiquid names in extreme deciles due to noisy predictions; (3) the Spearman correlation with the Baseline is high, suggesting the gate does not destroy the signal. Variant B adds complexity (the `full_rank` column is an intermediate artefact) without a clear performance advantage. The user should make the final call after reviewing the equity curves and considering whether the $5M ADV threshold is appropriate for their target portfolio size (a larger portfolio needs a higher threshold; a smaller portfolio may accept $1M).

---

## Caveats

- **Survivorship bias:** `stk_universe` is the current top-100 by market cap; delisted names are absent. This inflates all Sharpe ratios relative to a full CRSP universe. The `survivorship_biased = TRUE` flag is set in the production `stk_drif_metrics` target.
- **Spearman as heuristic:** Spearman correlation measures decile _rank_ agreement, not portfolio-return impact. A modest drop in correlation can translate to a large change in portfolio composition if it is concentrated in the extreme deciles.
- **ADV threshold sensitivity:** $5M is a single-point estimate. The threshold should be swept over $1M–$20M before productionising.
- **No transaction cost difference modelled:** All three variants use the same cost model. In practice Variant A/B may have lower transaction costs because illiquid names are excluded (lower market-impact), but this is not captured here.
- **No benchmark or factor adjustment:** Sharpe ratios are raw portfolio Sharpe; no Fama-French alpha reported.

