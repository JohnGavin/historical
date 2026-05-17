---
title: Quantocracy May 3 2026 Roundup
canonical_question: What did the Quantocracy May 3 2026 quant research roundup cover, and what is relevant to this project?
status: active
fresh_until: 2026-08-16
consensus_level: direct
sources:
  - quantocracy-may-2026.md
compiled_by: claude-sonnet-4-6
compiled_on: 2026-05-16
tags: [roundup, trend-following, risk-parity, transaction-costs, yield-curve, implied-volatility, regime]
---

# Quantocracy May 3 2026 Roundup

Five curated quant research links published by Quantocracy on 2026-05-04. Topics span transaction cost realism for crypto strategies, risk parity drawdown audits, implied volatility computation, regime-dependent trend following allocation, and yield curve macro signals. Three of the five articles overlap existing open issues; two introduce new angles worth tracking.

## Articles Surveyed

### 1. I paper-traded 22 popular crypto strategies on real fees for 10 days [Strat Proof]

**URL:** https://stratproof.com/blog/paper-trading-22-strategies-real-fees

The author built a trading bot integrated with TradingView and ran 22 popular crypto strategies on Binance using real L2 spread and real fees for 10 days, finding that backtests were "way too optimistic compared to what happened when I actually ran them." ([raw/quantocracy-may-2026.md:L44](../raw/quantocracy-may-2026.md#L44))

> ⚠ AI-inferred: The gap between backtest and live performance likely stems from spread cost underestimation in backtests and order-book impact at L2 depth — consistent with the literature on crypto market microstructure showing bid-ask spreads of 5-30 bps for altcoins vs 1-2 bps assumed in naive backtests. Individual article not fetched (WebFetch denied); synthesis from Quantocracy blurb only.

**Cross-reference:** #125 (already covers this article with additional detail including "16 of 22 strategies lost money" finding)

---

### 2. Where Risk Parity Hurts: A 58-Year Audit of Tails and Drawdowns [Beyond Passive]

**URL:** https://beyondpassive.substack.com/p/where-risk-parity-hurts-a-58-year

A 58-year (1968-2026) backtest of inverse-volatility allocation across SPY, TLT, and GLD using synthetic price construction prior to ETF inception. Reported results: CAGR 7.1%, volatility 7.5%, Sharpe 0.97, maximum drawdown 22%. Includes a volatility-targeting overlay "justified by the persistence of volatility across the same window." ([raw/quantocracy-may-2026.md:L59](../raw/quantocracy-may-2026.md#L59))

> ⚠ AI-inferred: The Sharpe of 0.97 over 58 years is a strong result for a 3-asset risk parity portfolio. The 22% maximum drawdown is notably lower than SPY-only drawdowns (55% in 2008-2009). The critical question is how drawdowns behave in inflationary regimes (1968-1982) where both bonds and stocks underperformed — the use of synthetic price construction pre-1986 (TLT inception) introduces significant uncertainty about true historical behaviour. Individual article not fetched; synthesis from Quantocracy blurb only.

**Cross-reference:** #114 (risk parity R package implementation — this article provides empirical drawdown context). Not covered by #142 (which is about FX risk, not risk parity drawdowns).

**New issue warranted:** Yes — extends #114 with empirical tail/drawdown evidence over 58 years. See Recommended New Issues below.

---

### 3. Almost Explicit Implied Volatility [Chase the Devil]

**URL:** https://chasethedevil.github.io/post/almost-explicit-implied-volatility/

Reviews a new paper by Wolfgang Schadner presenting an "almost explicit" formula for Black-Scholes implied volatility — "almost" because it relies on some approximation rather than being fully closed-form. The author previously explored multiple IV computation methods; Jherek Healy proposed improvements over the author's baseline. ([raw/quantocracy-may-2026.md:L74](../raw/quantocracy-may-2026.md#L74))

> ⚠ AI-inferred: Near-explicit IV formulas matter for options pricing speed (no root-finding iteration required). Schadner's formula likely uses a rational approximation or Taylor expansion of the normal CDF inversion. For this project's purposes, IV computation is only relevant if we implement options-based signals (e.g., VIX term structure beyond existing VVIX work). Individual article not fetched; synthesis from Quantocracy blurb only.

**Cross-reference:** #105 (VVIX and vol surface coverage — tangentially related). No direct project issue.

---

### 4. Rethinking Trend Following: Optimal Regime-Dependent Allocation [Alpha Architect]

**URL:** https://alphaarchitect.com/rethinking-trend-following-optimal-regime-dependent-allocation/

Argues that most trend-following research focuses on signal construction (detecting trends faster/earlier) rather than asking the more actionable question: given a regime has been identified, what is the optimal portfolio exposure? The article reviews a paper proposing optimal (rather than heuristic) exposure sizing conditional on regime state, moving beyond traditional TSMOM discrete rules. ([raw/quantocracy-may-2026.md:L87](../raw/quantocracy-may-2026.md#L87))

> ⚠ AI-inferred: Our existing regime code (plan_regime.R, plan_risk_state.R, plan_avoid_worst.R) uses heuristic discrete scaling (100%/70%/40% or binary on/off). The paper's "optimal" framing likely uses mean-variance or utility-maximising exposure conditional on regime transition probabilities — a direct upgrade path for our regime implementations. This is distinct from #119 (momentum underperformance from vol spikes) and from #141 (LLM regime labelling) — it targets exposure *sizing* within a regime rather than *classification* of regime. Individual article not fetched; synthesis from Quantocracy blurb only.

**Cross-reference:** #119 (momentum/volatility regime — same blog, different paper/question), #141 (LLM regime labelling). No existing issue covers optimal exposure within regime.

**New issue warranted:** Yes — directly actionable upgrade to existing regime scaling code. See Recommended New Issues below.

---

### 5. Curve trades with macroeconomic signals [Macrosynergy]

**URL:** https://macrosynergy.com/research/curve-trades-with-macroeconomic-signals/

Yield curve shape in developed swap markets reflects growth, inflation, and credit supply because central banks adjust short rates to economic conditions while credibility anchors longer-term forward rates. Under price-stability regimes with short rates above zero lower bound, curve shape provides a macro signal. ([raw/quantocracy-may-2026.md:L101](../raw/quantocracy-may-2026.md#L101))

> ⚠ AI-inferred: The "curve trade" framing suggests long/short positioning on the yield curve steepener/flattener based on macro regime signals. This is consistent with academic evidence that the yield curve slope predicts economic slowdowns with a 6-18 month lead. Our existing pipeline has 29 ECB series including yield curve slope (10Y-2Y) — this article suggests a systematic framework for using that data as a tradeable signal rather than only a regime indicator. Individual article not fetched; synthesis from Quantocracy blurb only.

**Cross-reference:** #124 (Macrosynergy yield curve macro signals — this is the same article; #124 already covers it)

---

## Cross-References to Project Issues

| Article | Relevant Issues | Relationship |
|---------|----------------|--------------|
| StratProof 22 crypto strategies | #125 | Already covered; #125 has full article detail |
| Beyond Passive risk parity 58yr audit | #114 | Empirical drawdown evidence for risk parity; no existing issue covers this specific article |
| Chase the Devil implied vol | #105 | Tangential; only relevant if options signals added |
| Alpha Architect regime exposure | #119, #141 | Different question (optimal sizing vs identification); no existing issue |
| Macrosynergy curve trades | #124 | Already covered |

**Issues with no match in this roundup:** #120 (StockGPT), #122 (ML ensembles), #105 (VVIX coverage gaps), #142 (FX risk)

---

## Recommended New Issues

### Issue A: Research — Optimal regime-dependent exposure sizing for trend following (Alpha Architect 2026)

**Proposed title:** `research: Optimal regime-dependent exposure sizing for trend following (Alpha Architect 2026)`
**Scope:** Obtain and review the paper referenced in the Alpha Architect article. Assess whether optimal (utility-maximising or mean-variance) exposure sizing can replace heuristic discrete scaling in plan_regime.R and plan_risk_state.R. Compare against current 100%/70%/40% heuristic using out-of-sample Sharpe.
**Difficulty:** M — reading + one backtest comparison against existing regime code
**Why new:** #119 covers momentum/vol spike interaction; #141 covers regime *classification*. Neither addresses optimal *exposure within regime*.

### Issue B: Research — Beyond Passive 58-year risk parity tail audit — drawdown evidence for #114

**Proposed title:** `research: Risk parity 58-year tail/drawdown audit — empirical context for HRP (#114)`
**Scope:** Review the Beyond Passive article in full. Extract the 58-year drawdown profile across inflationary vs deflationary regimes. Cross-reference with #114 (HRP) to assess whether HRP's diversification claims hold across the 1968-1982 inflationary period. Note the synthetic pre-ETF price construction methodology and document uncertainty.
**Difficulty:** S — primarily literature review; may surface a need for pre-1986 synthetic data in our pipeline
**Why new:** #114 is about HRP *implementation*; this fills the *empirical evidence* gap on how risk parity drawdowns behave in regimes we haven't tested.

---

## Sources

- [[quantocracy-may-2026]] — raw capture at `knowledge/raw/quantocracy-may-2026.md` (blurbs from Quantocracy HTML lines 122-154)
- Original URL: https://quantocracy.com/recent-quant-links-from-quantocracy-as-of-05032026/
- Related wiki entries: [[regime-trend-following]], [[macrosynergy-research]]
