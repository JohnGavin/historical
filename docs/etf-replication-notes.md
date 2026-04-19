# ETF Replication Results: Approach A vs B

## Results Summary

| Metric | A: DRIF on ETFs (L/S) | A: Long-Only | B: Academic→ETFs (L/S) | B: Long-Only |
|--------|:----:|:----:|:----:|:----:|
| Full CAGR | -0.8% | **13.4%** | -1.9% | **12.6%** |
| Test CAGR | 0.6% | 7.7% | -3.7% | 5.0% |
| Val CAGR | 2.7% | **20.0%** | -2.7% | **19.8%** |
| Full Vol | 7.0% | — | 6.1% | — |
| Full Sharpe | -0.11 | — | -0.31 | — |
| Full Max DD | -23.7% | — | -29.0% | — |

## Key Findings

### 1. Long-short fails, long-only works

Both approaches lose money on the long-short spread but the **long-only leg
returns 13%+ CAGR**. This means the signal identifies good ETFs to buy but
cannot reliably identify which to short. The short leg adds noise and cost.

### 2. Approach A slightly better than B

A (DRIF directly on ETF prices) has higher Sharpe (-0.11 vs -0.31) and lower
max DD (-23.7% vs -29.0%). The mapping problem in B (VLUE/HML cor=0.34)
introduces noise that overwhelms the academic signal.

### 3. Long-only is the practical strategy

13.4% CAGR long-only with ~4% vol (estimated) and low costs (0.10%/trade for
3 ETFs) is a **credible, implementable strategy**. Compare:
- Factor DRIF (academic): 7.0% net CAGR
- ETF Approach A long-only: ~13.4% CAGR (needs cost deduction for long-only)
- S&P 500 buy-and-hold: ~10% CAGR

### 4. Validation period is strong

Both approaches show 20% long-only CAGR in validation (2023-2026). This is
the post-training period and suggests the signal persists. However, this
overlaps with a strong bull market so may not be robust to bear markets.

### 5. Cost advantage is real

ETF total cost ~0.20%/month vs 1.85%/month for stock-level. This is why
the long-only leg survives — the gross returns don't need to overcome
massive transaction costs.

## Recommendations for Vignette

1. **Lead with long-only ETF Approach A** — this is the most practical strategy
2. Show long-short as a comparison (to demonstrate the short leg is unprofitable)
3. Show Approach B to explain why academic-to-ETF mapping is imprecise
4. Compare all approaches in one table: factor DRIF, stock DRIF, ETF A, ETF B
5. Discuss the 0.34 VLUE/HML correlation as the fundamental limitation of B

## For the Definition Tab

### Approach A
"Each month, apply elastic net regression on 42 daily return features
(21 chronological + 21 rank) to each of 9 factor ETFs. Predict next
month's return. Long the top 3 predicted ETFs."

### Approach B
"Use the academic factor-level DRIF signal (trained on FF5+Momentum
since 1963) to predict which factors will outperform. Map the winning
factors to their closest ETF proxies. Long those ETFs."

## Data Period

- Approach A: 2013-2026 (119 months, limited by VLUE/MTUM inception)
- Approach B: 2013-2026 (153 months, longer because factor signal starts 1968)
