---
title: Alpha Architect Gap Analysis (2026-06-04)
canonical_question: "For each strategy that Alpha Architect publishes, do we have an equivalent, an adjacent variant, or a genuine gap?"
status: active
fresh_until: 2027-06-04
consensus_level: indirect
sources:
  - alphaarchitect-factor-strategies-2026-06-04.html
  - alphaarchitect-taxonomy-2026-06-04.md
  - alphaarchitect-factor-strategies.md
compiled_by: claude-opus-4-7
compiled_on: 2026-06-04
tags: [alpha-architect, gap-analysis, factor-investing, strategy-roadmap, value, momentum, trend, managed-futures]
---

# Alpha Architect Gap Analysis (2026-06-04)

## Sources

| Source | Confidence |
|---|---|
| Raw HTML capture: `alphaarchitect-factor-strategies-2026-06-04.html` | Direct (curl + Wayback) |
| Structured extract: `alphaarchitect-taxonomy-2026-06-04.md` | Direct + AI-inferred (tagged) |
| Wiki digest: [[alphaarchitect-factor-strategies]] | This session |
| Our strategy roster: [`R/plan_strategy_names.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_names.R) | Direct (source code) |
| Closed issues [#18](https://github.com/JohnGavin/historical/issues/18), [#119](https://github.com/JohnGavin/historical/issues/119), [#279](https://github.com/JohnGavin/historical/issues/279) | Direct (GitHub API) |
| Wesley Gray & Tobias Carlisle, *Quantitative Value* (Wiley 2012) | External reference book |
| Wesley Gray & Jack Vogel, *Quantitative Momentum* (Wiley 2016) | External reference book |

---

## How to read the classification

| Code | Meaning |
|---|---|
| **COVERED** | We have a strategy that closely matches AA's construction (signal, universe, frequency). |
| **PARTIAL** | We have a strategy in the same family but with a different signal or screen — adjacent, but not equivalent. |
| **GAP** | AA publishes the strategy; we don't have anything in that family. Worth considering. |
| **DELIBERATELY EXCLUDED** | We know about the strategy and have chosen not to implement it. Explanation given. |
| **NOT APPLICABLE** | AA "strategy" is actually a service or non-strategy (e.g., 1042 QRP, Custom Solutions). |

---

## The matrix

### Branch A — Value

| AA Factor | AA Sub-strategy | Our coverage | Classification | Notes |
|---|---|---|---|---|
| Value | Quantitative Value (long-only ~50 names, EV/EBIT after forensic + quality screens, quarterly) | None — none of our 14 use fundamentals | **GAP** | Highest-leverage gap; would diversify our momentum-heavy book |
| Value | International Value (IVAL; no longer in lineup) | None | **NOT APPLICABLE** | AA appears to have rationalised this; track but don't prioritise |
| Value | Value Factor Diversification (Quality vs Momentum overlay on value) | Adjacent: Factor DRIF rotates between V/Q/M | **PARTIAL** | Different mechanism (we rotate factors; AA layers quality screen onto value selection) |

### Branch B — Momentum

| AA Factor | AA Sub-strategy | Our coverage | Classification | Notes |
|---|---|---|---|---|
| Momentum | Quantitative Momentum (long-only, ~50 names, 12-2 + FIP path-quality screen, quarterly) | LTR (12-2, **no FIP**), Mom 12-2 (12-2, **no FIP**) | **PARTIAL** | We have 12-2 sort but no path-quality screen. FIP screen could be additive |
| Momentum | International Momentum (IMOM equivalent) | None | **GAP** | Cross-geography pervasiveness (see `cross-geography-pervasiveness` rule) — adding intl momentum would test our US-momentum signals across markets |
| Momentum | "Enhancing Momentum Strategies" — alternative momentum signals | Factor MAX, Stock MAX, Stock DRIF, XGB DRIF, Pre/Post-Peak (Büsing) | **COVERED** (with depth) | We have 5+ momentum variants; arguably more diverse momentum coverage than AA |
| Momentum | "The Many Facets of Stock Momentum" — momentum decomposition | Mom Pre-Peak, Mom Post-Peak (Büsing 2022) | **COVERED** | Our momentum-decomposition work (#365) is the AA-style "facets" exploration |

### Branch C — Trend / Managed Futures

| AA Factor | AA Sub-strategy | Our coverage | Classification | Notes |
|---|---|---|---|---|
| Trend | Time-series momentum on equity index (MA-cross / 12-month TS-mom) | Avoid Worst (VIX-based, not TS-mom); Risk State (VIX-based) | **PARTIAL** | Adjacent — both protect against equity drawdowns but via VIX, not TS-momentum |
| Trend | Managed Futures (long-short TS-mom across equities/bonds/FX/commodities) | None — Commodities Mean Reversion is the opposite direction | **GAP** | Cross-asset TS-momentum is one of the most-replicated premia in academic literature; we have zero coverage. Big gap |
| Trend | "World's Longest Trend-Following Backtest" (AA's research piece) | None | **GAP** (research) | AA has 200+ year trend-following backtest; we could replicate with our JST data |
| Trend | "Avoiding the Big Drawdown with Trend-Following Investment Strategies" | Avoid Worst (different mechanism — VIX not trend) | **PARTIAL** | Same goal (drawdown avoidance), different signal |

### Branch D — Combined / Multi-strategy

| AA Factor | AA Sub-strategy | Our coverage | Classification | Notes |
|---|---|---|---|---|
| Combined | Global Value Momentum Trend (GVMT) — long-only Value sleeve + long-only Momentum sleeve + trend overlay | None — but Factor DRIF + Factor MAX rotate factors; PSO Optimal combines strategies | **PARTIAL** | Different mechanism (factor rotation / PSO portfolio optimisation vs sleeve combination + trend overlay). A direct GVMT replica would require the missing Value sleeve first |
| Combined | "Value and Momentum Investing: Combine or Separate?" white paper | Factor DRIF (rotation); PSO Optimal (optimisation) | **COVERED** (different angle) | Our factor-rotation strategies address the "combine or separate" question via a different lens (rotate vs combine in fixed weights) |

### Branch E — "More" (other research themes)

| AA Theme | AA Sub-strategy / Research | Our coverage | Classification | Notes |
|---|---|---|---|---|
| Anomaly-Driven Demand (ADD) | The /factor-strategies/ Swedroe post (#279) | None as a STRATEGY; rule clauses added | **PARTIAL** | Issue #279 covered the digest; recommended ADD-aware crowding metric on leaderboard (#160-linked) but not yet built. See [[anomaly-driven-demand]] |
| Asset allocation / portfolio construction | "Are Factors Better and More Diversifying Than Asset Classes?" | Not addressed | **GAP** (research) | Asset-class vs factor diversification audit — interesting one-off vignette |
| Behavioural / process | "Even God would get fired as an Active Investor" | Captured via `resulting-prohibition` + `underperformance-prior` rules | **COVERED** (as rules, not as a strategy) | These are AA-style behavioural cautionary tales; we already enforce them as rules |
| Mutual fund flows | "Do Mutual Fund Flows Really Say What We Think They Say?" | Not addressed | **NOT APPLICABLE** | Out-of-scope for a backtesting library |
| Equity duration | "Equity duration and predictability" | Not addressed | **GAP** (research) | Could be a vignette; low priority |
| Private credit | "Is There A Bubble In Private Credit?" | Not addressed | **NOT APPLICABLE** | Out-of-scope |
| Box spreads / cash management | "Box Spreads: An Alternative to Treasury Bills?" | Not addressed | **DELIBERATELY EXCLUDED** | Implementation detail, not a strategy. Treasuries are fine as a risk-free asset for our backtests |
| Emerging markets | "Does Emerging Markets Investing Make Sense?" | Not addressed | **GAP** (universe) | Currently US-only; adding EM is a universe extension, not a new strategy |
| Commodity futures | "Commodity Futures Investing: Complex and Unique" white paper | Commodities Mean Reversion (CMR) | **COVERED** (different direction) | We have a mean-reversion commodities strategy; AA's piece is more general |
| Transaction costs | "Do factor portfolios survive transaction costs?" | Tracked via `backtesting-assumptions` rule + #125 cost-reality-check | **COVERED** (as rule + issue) | The discipline is in our rules; the empirical work in #125 |

### Branch F — Things that look like strategies but aren't

| AA Item | Why not a strategy gap | Classification |
|---|---|---|
| 1042 QRP Solutions | ESOP tax-deferral wrapper, not a quant strategy | **NOT APPLICABLE** |
| Custom Solutions | Consulting offering | **NOT APPLICABLE** |
| Start an ETF (ETFarchitect.com) | White-label ETF infrastructure | **NOT APPLICABLE** |

---

## Summary counts

> ⚠ AI-inferred: classification is the author's judgement and may shift
> on user review.

| Classification | Count | Examples |
|---|---|---|
| COVERED | 5 | Momentum variants (5), CMR, Combine-or-separate (via rotation), Transaction costs (as rule), Process rules |
| PARTIAL | 6 | QV (no fundamental Value sleeve), QMOM (no FIP screen), Trend (VIX not TS-mom), GVMT (different combiner), Factor-quality overlay, ADD (rule but no metric) |
| GAP | 6 | Fundamental Value sleeve, International Momentum, **Managed Futures (cross-asset TS-mom)**, Long-history trend backtest, Asset-class vs factor diversification audit, Equity duration |
| DELIBERATELY EXCLUDED | 2 | Box spreads (Treasuries fine for us), Mutual-fund flow sentiment (already covered in `priced-in-signals.md` — newspaper sentiment found no edge; mutual-fund flows likely the same) |
| NOT APPLICABLE | 5 | International Value (rationalised by AA), 1042 QRP, Custom Solutions, Private credit, ETF white-label |

---

## Recommended new issues (stubs only — DO NOT FILE; for user review)

> The dispatch explicitly DEFERRED Subtask 5 (filing new issues). These
> stubs are for the user to triage and file selectively. Each stub
> includes title, rationale, applicable rules, and a recommended template.

### Stub 1: Fundamental Value sleeve — Quantitative-Value-style EV/EBIT long-only

**Title:** research: add fundamental Value sleeve — EV/EBIT screen with forensic + quality filters (AA-QVAL gap)

**Rationale:** All 14 of our current strategies are price-based. The
Büsing momentum-decomposition work (#365) and the Cakici factor-zoo audit
both noted that we systematically load on the opposite side of the
fundamental Value factor, meaning a value drawdown materially hurts our
leaderboard. AA's Quantitative Value (Gray & Carlisle 2012) is the
canonical concentrated long-only Value implementation: EV/EBIT cheapness
after forensic accounting (Beneish, Sloan) and quality (FCF/A, ROIC)
screens. Adding even a basic EV/EBIT-only Value sleeve would diversify
the leaderboard's factor exposures. Daloopa-style fundamentals data (#78
deferred) would unlock this; in the meantime, Yahoo/FMP free-tier
EV/EBIT might be enough for a v0.

**Applicable rules:**
- `priced-in-prohibition` — EV/EBIT is a long-watched metric, but Value's
  premium is well-documented over 90+ years
- `cross-geography-pervasiveness` — Value is documented across markets
  (US, intl, EM); strong evidence base
- `backtest-robustness` — parameter sensitivity sweep (EV/EBIT cutoff %)
  required before adoption
- `underperformance-prior` — 14-year max value drawdown (1969-2008) MUST be
  on the dashboard before evaluating recent results

**Template:** Use #414 (recent strategy-addition template) or #280

**Estimated effort:** 4-8 hours for v0 (Yahoo / FMP EV/EBIT), 1-2 days
for v1 with forensic screens

**Priority:** HIGH (biggest leaderboard diversification gap)

---

### Stub 2: Cross-asset TS-momentum (managed futures) sleeve

**Title:** research: add cross-asset time-series momentum sleeve (managed futures) — AA-Managed-Futures gap

**Rationale:** Our trend overlays (Avoid Worst, Risk State) are all VIX-based
and US-equity-only. AA's Managed Futures (and the broader Moskowitz-Ooi-Pedersen
2012 literature) uses 12-month TS-momentum across equities, bonds,
currencies, and commodities, with vol-targeting at instrument and portfolio
level. Returns are largely uncorrelated with equity beta — exactly the
diversification our overlay-heavy book needs. We have FRED data on rates
and currencies, commodity futures (WTI), and equity-index prices, so the
data prerequisites are mostly met. Liquidity caveat: real-world managed
futures uses actual futures contracts (1256 cap-gains treatment); a v0
could use cash-equivalent ETFs (TLT, UUP, DBC, SPY).

**Applicable rules:**
- `cross-geography-pervasiveness` — MOP 2012 documents TS-momentum across
  58 instruments in 4 asset classes back to 1900s; meets the bar
- `backtest-robustness` — parameter sensitivity for lookback (3/6/12/24
  months) and vol-target level required
- `backtesting-assumptions` — cross-asset TS-mom has well-documented
  transaction costs that MUST be in the backtest
- `priced-in-prohibition` — TS-mom is widely-known; recent crowding may
  reduce edge (cross-reference [[anomaly-driven-demand]])

**Template:** Use #414 / #280 with a `backtest-robustness` sensitivity
sweep section

**Estimated effort:** 1-2 weeks for v0 (~4 instruments via ETFs)

**Priority:** HIGH (no current cross-asset coverage; large diversification benefit)

---

### Stub 3: Path-quality / "frog-in-the-pan" (FIP) screen on momentum strategies

**Title:** research: add path-smoothness (FIP) quality screen to LTR / Mom 12-2 / Pre-Peak / Post-Peak (AA-QMOM enhancement)

**Rationale:** Da, Gurun & Warachka (2014, "A Closer Look at the Disposition
Effect") showed that path-smoothness of the 12-month return significantly
improves momentum's risk-adjusted return. Gray & Vogel (2016)
operationalise this as the FIP screen in AA's Quantitative Momentum
(QMOM). Our LTR, Mom 12-2, Pre-Peak, and Post-Peak strategies all use raw
12-2 momentum WITHOUT a path-quality filter. Adding a FIP-style screen
is a low-effort, high-evidence enhancement to four of our existing
strategies. Could also be tested as a falsification check — does the FIP
screen survive our `K_eff_strat` (#160) deflated-Sharpe budget?

**Applicable rules:**
- `backtest-robustness` — sensitivity to FIP threshold and definition
- `priced-in-prohibition` — FIP has been published since 2014; check
  edge persistence post-publication (likely partly priced in by now)
- `backtest-partitions` — apply across our existing momentum partitions
  (different periods, different deciles)

**Template:** Strategy enhancement (not new strategy) — modify existing
plans + add comparison vignette

**Estimated effort:** 4-6 hours (single new function, applied to 4 existing strategies)

**Priority:** MEDIUM (incremental improvement, well-documented evidence)

---

### Stub 4: International Momentum (universe extension)

**Title:** research: add International Momentum sleeve (universe extension)

**Rationale:** AA's IMOM is the international counterpart of QMOM. Our
LTR is currently US-only. Adding a developed-international momentum
strategy (Europe + Japan + UK + Australia) tests `cross-geography-pervasiveness`
on our own US momentum findings. If US momentum and intl momentum produce
correlated returns, that's evidence the factor is real; if uncorrelated,
that's a diversification benefit; if intl works but US has decayed,
that's a `priced-in-prohibition` warning. The data prerequisite is
international equity OHLCV which we don't currently have — would need
Yahoo or Stooq.

**Applicable rules:**
- `cross-geography-pervasiveness` — this IS the pervasiveness test
- `backtest-robustness` — universe + lookback sensitivity
- `underperformance-prior` — intl momentum has different drawdown history

**Template:** Universe-extension issue (not a new strategy logic)

**Estimated effort:** 1 week for data acquisition + v0

**Priority:** MEDIUM (universe extension; depends on Stub 1 + 2 priorities)

---

### Stub 5: ADD-aware crowding metric on leaderboard

**Title:** feature: add Anomaly-Driven Demand (ADD) crowding column to leaderboard (continuation of #279)

**Rationale:** Issue #279 closed with a recommendation to add a
crowding/capacity metric to the leaderboard that flags strategies whose
returns are concentrated in the first ~6 trading days of the month
(month-start rebalance window — the ADD signature). This was an
ACCEPTED recommendation in #279 ("Angle A: a crowding-warning column /
capacity check on the leaderboard is the higher-value, lower-risk choice")
but the implementation issue was never opened. AA's "When Everyone Trades
the Same Factor Playbook" post (URL `/factor-strategies/`) is the
reference. The Chen-Zimmermann open anomaly dataset is the underlying
data source (free, openassetpricing.com).

**Applicable rules:**
- `priced-in-prohibition` — ADD is a distinct flow channel from
  information-priced-in; the rule already contains an ADD clause
- `backtest-robustness` — `K_eff_strat` (#160) deflated-Sharpe budget
  applies if ADD becomes a signal

**Template:** Leaderboard enhancement (not new strategy)

**Estimated effort:** 1-2 days for v0 (compute month-start vs rest-of-month
return concentration per strategy)

**Priority:** MEDIUM (closing-the-loop on #279)

---

### Stub 6: Long-history trend-following backtest (200+ year)

**Title:** research: replicate AA "World's Longest Trend-Following Backtest" with our JST data

**Rationale:** AA published "The World's Longest Trend-Following Backtest"
extending TS-momentum / MA-cross trend-following back to the 1800s. We
have JST data going back to 1870. A replica would (a) cross-validate
our long-history regime work, (b) test trend-following pervasiveness over
much longer history than typical 50-year backtests, and (c) directly
inform Stub 2 (managed futures sleeve). Low risk — research / educational,
not a deployed strategy.

**Applicable rules:**
- `underperformance-prior` — long history reveals max-drawdown periods
- `cross-geography-pervasiveness` — JST covers 17 advanced economies
- `backtest-robustness` — parameter sensitivity over 150 years

**Template:** Vignette / research piece (not a strategy)

**Estimated effort:** 1 week

**Priority:** LOW-MEDIUM (interesting research; mainly supports Stub 2)

---

### Stub 7: Asset-class vs factor diversification audit

**Title:** research: replicate AA "Are Factors Better and More Diversifying Than Asset Classes?" with our data

**Rationale:** AA published research arguing that factor diversification
beats asset-class diversification net-of-cost. With our 14 strategies plus
the macro/factor/commodity datasets, we could run a head-to-head: 60/40
asset-class vs 14-strategy factor-blend on the same time series. Mainly
a position-sizing / portfolio-construction vignette.

**Applicable rules:**
- `position-sizing-guardrails`
- `backtest-robustness`

**Template:** Vignette / research piece

**Estimated effort:** 3-5 days

**Priority:** LOW (nice-to-have; explains the why behind our existing leaderboard)

---

## What we are NOT recommending (and why)

| AA item | Why not | Decision basis |
|---|---|---|
| Quality-only strategy | Quality is best as a screen on Value/Momentum, not standalone (AA's own position) | Follow AA's framework |
| Low-Vol / Min-Vol strategy | AA explicitly rejects this as a value-tilt in disguise; AQR + Asness research agrees | `priced-in-prohibition` + Swedroe framework |
| Size strategy | AA published "Long-Only Value Investing: Size Doesn't Matter!" | Follow AA's evidence |
| Box spreads / cash management | Implementation detail; T-bills suffice for our backtest's risk-free asset | Scope |
| ESG / sustainable factor | AA does not publish ESG strategies; we don't either; our backtest data lacks ESG anyway | Scope + data |
| Mutual fund flow sentiment | Adjacent to `priced-in-signals` work (#82, #89) which found newspaper sentiment has no edge | `priced-in-prohibition` likely applies |
| Private credit | Out-of-scope for a public-market backtesting library | Scope |

---

## Methodology

### What this page computes

A descriptive classification of AA's published factor strategies against
our 14-strategy library. No new returns computed.

### Data sources

- Companion raw HTML: `alphaarchitect-factor-strategies-2026-06-04.html`
- Companion taxonomy extract: `alphaarchitect-taxonomy-2026-06-04.md`
- Companion wiki digest: [[alphaarchitect-factor-strategies]]
- Our [`R/plan_strategy_names.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_names.R)
- Closed issues [#18](https://github.com/JohnGavin/historical/issues/18), [#119](https://github.com/JohnGavin/historical/issues/119), [#279](https://github.com/JohnGavin/historical/issues/279)

### AI disclosure

This vignette was developed with assistance from Anthropic's Claude (model:
Opus 4.7 and Sonnet 4.6). AI helped with code structure, prose drafting,
and visualization choices. All analytical decisions and data
interpretations are the author's responsibility.

The classification of each AA strategy as COVERED/PARTIAL/GAP/EXCLUDED
is the author's judgement. The user MUST review and confirm before any
of the recommended issue stubs are filed.
