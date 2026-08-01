# Source record: aligrithm — "Chicken and Egg: Use the SPX to Time the VIX, Not Vice Versa"

- URL: https://aligrithm.com/chicken-and-egg-use-the-spx-to-time-the-vix-not-vice-versa/
- Author: Ali H. Askar (aligrithm)
- Retrieved: 2026-07-31
- Reviewed under: [historical#611](https://github.com/JohnGavin/historical/issues/611)

> External source. Recorded here as a **summary of claims in our own words**, per
> the zero-trust rule — read for ideas, re-implement in our own style. Short
> quotes only, for provenance. Nothing here was copied into our codebase.

## Claims as stated by the author

**Central thesis.** Causality runs SPX → VIX, not the reverse. Because VIX is
computed from SPX option prices, reading VIX to forecast SPX is "reading the
effect to predict the cause". The author's phrasing: *"The VIX is a reaction to
SPX price action, and option traders react rather than anticipate."*

**Long-horizon evidence (2007–2023).** SPX trend filters (price above year-ago
close, above 200-day MA, 50/200 golden cross) reportedly beat buy-and-hold on
risk-adjusted return. VIX-based filters lagged, at CAR/MDD 0.11–0.13 versus 0.14
for buy-and-hold. Author's conclusion: *"Long-term VIX levels do not filter the
SPX."*

**Short-horizon evidence.** SPX RSI(2) ≤ 20 → 57.66% win rate and 1.41 profit
factor on next-day SPX. VIX RSI(2) ≤ 20 → 55.51% win rate, 1.14 profit factor,
which the author calls "noise" by comparison.

**VIX futures asymmetry.** VX is claimed to mean-revert faster than SPX
recovers: after 2008 VX bottomed within ~7 months while SPX took ~5.5 years;
in 2022 VX made new lows in ~6 months while SPX stayed underwater ~2 years.

**Short-VX filtering (2007–2023), author's table.**

| filter | points captured | max drawdown | win rate | recovery factor |
|---|---|---|---|---|
| SPX RSI ≤ 20 | 178.6 | 21.04 | 62.9% | 8.49 |
| VIX RSI ≤ 20 | 80.23 | — | — | — |
| naked short VX | 213.52 | 68.86 | — | 3.1 |

SPX-filtered captured 178.6 points while in-market only 34% of the time, profit
factor 1.47 vs 1.13 unfiltered.

**Methodology notes.** RSI period 2 rather than 14 was chosen deliberately —
the author argues a 14-period RSI "parks almost everything between 30 and 70",
while 2 periods makes it "a mean-reversion detector, not a trend gauge". Also
uses the Rule of 16 (daily vol ≈ VIX ÷ 16, from √252).

## Author's own caveats

- RSI(2) lookback "is a choice rather than a law" — acknowledged overfitting risk.
- Results are historical backtest 2007–2023; no forward test or walk-forward
  validation is described.
- The traded vehicle (VX futures) differs from the index (VIX spot); the piece
  does not explore the structural difference in depth.

## What we did with it

Tested on our own data (SPY + FRED VIXCLS, 8,351 trading days, 1993-02-01 →
2026-04-10). Analysis: `explorations/vix_spx_leadlag/`. Findings compiled to
[`wiki/spx-vix-lead-lag.md`](../wiki/spx-vix-lead-lag.md).
