# SPX ↔ VIX lead-lag: testing "use the SPX to time the VIX, not vice versa"

Source: [aligrithm — Chicken and Egg](https://aligrithm.com/chicken-and-egg-use-the-spx-to-time-the-vix-not-vice-versa/).
Issue: [historical#611](https://github.com/JohnGavin/historical/issues/611).

Reproduce: `nix develop . --command Rscript explorations/vix_spx_leadlag/run.R`
Output: [`results/run_output.txt`](results/run_output.txt)

Data: SPY `adjusted_close` + FRED `VIXCLS`, 8,351 complete trading days,
1993-02-01 → 2026-04-10. Contemporaneous `cor(spx_ret, vix_chg) = -0.79`.

## Verdict: the practical claim replicates, the causal claim does not

The article makes two claims and treats them as one. They separate cleanly under test.

### Claim A — "SPX RSI(2) is a better filter than VIX RSI(2)" → **replicates**

| condition | share of days | next-day SPX mean | win rate | next-day VIX mean | down-rate |
|---|---|---|---|---|---|
| SPX RSI(2) ≤ 20 | 27.8% | **+0.109%** | **55.6%** | **−0.168** | **57.6%** |
| VIX RSI(2) ≤ 20 | 35.7% | +0.041% | 54.4% | +0.076 | 50.5% |
| unconditional | 100% | +0.047% | 54.0% | +0.001 | 53.0% |

SPX oversold more than doubles the next-day SPX drift versus unconditional, and
flips the next-day VIX change from flat to clearly negative. VIX oversold does
neither — its next-day SPX return (+0.041%) is *below* unconditional (+0.047%).

The article reported 57.66% vs 55.51% win rates; we get 55.6% vs 54.4%. Lower in
level, same in ordering, smaller in gap (1.2pp vs 2.15pp). Different sample
(1993–2026 vs 2007–2023) and a simple-MA rather than Wilder RSI smoothing.

### Claim B — "SPX leads VIX, so don't use VIX to time SPX" → **not supported; mildly reversed**

Cross-correlation is overwhelmingly contemporaneous, and what little lead-lag
exists is symmetric:

| lag k | `cor(spx_ret[t], vix_chg[t+k])` |
|---|---|
| −1 (VIX first) | +0.086 |
| **0** | **−0.792** |
| +1 (SPX first) | +0.106 |

Predictive regressions, each controlling for the target's own lag:

| direction | β | t | p | FPR @ equipoise | model R² |
|---|---|---|---|---|---|
| SPX_t → VIX_{t+1} | −0.289 | **−0.11** | 0.911 | n/a | 0.0183 |
| VIX_t → SPX_{t+1} | +0.0004 | **+3.15** | 0.0016 | 0.027 | 0.0079 |

SPX has **no** incremental power over tomorrow's VIX change. VIX change has
modest but real incremental power over tomorrow's SPX return. That is the
opposite of the stated direction.

### Why both can be true

They are different claims. Claim A is about **signal quality** — SPX price is a
cleaner series than VIX, which is itself a nonlinear transform of option prices
and noisier as a mean-reversion trigger. Claim B is about **causal timing**. The
article's mechanism ("the VIX is a reaction to SPX price action") is true by
construction, but it does not imply SPX *predicts* VIX at daily horizon — a
reaction that is instantaneous leaves nothing to forecast.

## Lévy area: a real ordering signature that is probably not tradeable

Using `hd_levy_area()` ([#605](https://github.com/JohnGavin/historical/issues/605), merged today; positive = first series leads):

| window | mean | fraction > 0 | n |
|---|---|---|---|
| 5d | +0.377 | 0.582 | 8,347 |
| 10d | +1.004 | 0.623 | 8,342 |
| 21d | +2.555 | 0.671 | 8,331 |
| 63d | +9.917 | 0.778 | 8,289 |

Systematically positive, and strengthening with window length — SPX does lead
VIX in the path-geometry sense. But this is most plausibly the **volatility
hysteresis loop**: price falls → VIX spikes fast → price recovers → VIX decays
slowly. That asymmetric loop encloses signed area regardless of any exploitable
lead, which is exactly why it coexists with the null result in Claim B.

**The t-statistics are omitted deliberately.** Windows overlap n-deep, so
effective sample size is far below 8,289 and any t-statistic computed on the
nominal count is meaningless — see [#601](https://github.com/JohnGavin/historical/issues/601).

## What this cannot test

- **The headline backtest.** The article's result is a short-**VX-futures**
  strategy. We hold VIX *spot*. Not replicable without futures data.
- **Intraday causality.** At daily close, VIX is computed from SPX options
  quoted at the same instant. Contemporaneity is structural, not a finding.
- **Collinearity.** The two regressors in the asymmetry test are 79% correlated
  (VIF ≈ 2.7), inflating standard errors ~1.6×. The asymmetry survives; the
  coefficients are not precisely identified.

Everything here is in-sample, with no train/test split — the same defect the
article carries.
