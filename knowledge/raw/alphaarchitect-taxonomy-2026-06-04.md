# RAW: Alpha Architect Factor Taxonomy Extract (2026-06-04)

> Provenance (append-only raw source — do not edit)
> - Captured: 2026-06-04 by Claude Code agent (worktree-agent-adaaa38b4004a8bcb)
> - Issue: #415 (Subtasks 1–4 only; subtasks 5–7 deferred to user)
> - Companion raw HTML: `alphaarchitect-factor-strategies-2026-06-04.html`
> - Companion wiki digest: `../wiki/alphaarchitect-factor-strategies.md`
> - Companion gap analysis: `../wiki/alphaarchitect-gap-analysis-2026-06-04.md`

## How to read the confidence markers

- `> ✓ verified:` — quoted/inferred directly from one of the four HTML sources
  archived in `alphaarchitect-factor-strategies-2026-06-04.html`
- `> ⚠ AI-inferred:` — pieced together from Alpha Architect's publicly known
  framework (Wesley Gray's books *Quantitative Value* (2012) and *Quantitative
  Momentum* (2016), AA white papers titles, AA blog post titles surfaced in
  the research-category list, and the broader academic literature AA publishes
  from). Tagged because the specific construction details below the level of
  the strategy name are not in any HTML page we could fetch — they come from
  external reference works, not the AA site itself.

## CRITICAL: dispatch premise correction

The dispatch's framing assumed `alphaarchitect.com/factor-strategies/` was a
multi-factor taxonomy page (value/momentum/quality/low-vol/size/multi-factor).
That URL is actually a single Larry Swedroe blog post (2026-05-22) digesting
the Posselt & Kjær (March 2026) "Anomaly-Driven Demand" (ADD) paper. This is
already digested at `../wiki/anomaly-driven-demand.md`.

This file therefore audits AA's **actual** factor taxonomy — reconstructed
from `/focusedfactors/` (Wayback 2025-08-04), `/research-category-list/`
(Wayback 2026-01-29), `/alpha-architect-white-papers/` (Wayback 2025-08-04),
and the Wesley Gray reference works — against our 14 strategies.

---

## Alpha Architect's actual factor taxonomy

> ✓ verified: The site's top-level Research navigation has exactly five
> categories: **Value · Momentum · Trend · White Papers · More**
> (from research-category-list HTML, lines extracted in raw HTML capture).

> ✓ verified: AA's long-only ETF strategy menu has these entries:
> **Quantitative Value · Quantitative Momentum · Global Value Momentum Trend
> (combined) · Managed Futures · Custom Solutions · 1042 QRP Solutions**
> (from focusedfactors HTML menu extract).

> ⚠ AI-inferred: AA does NOT publish a low-volatility / minimum-variance
> strategy, does NOT publish a quality-only strategy (quality is folded into
> their value and momentum screens), and does NOT publish a size strategy.
> This is consistent with Wesley Gray's published position that "low-vol" is
> a value-tilt in disguise and that "quality" is best used as a defensive
> screen on top of value and momentum, not as a standalone factor.
> Inferred from absence in focusedfactors menu + white-paper titles like
> "Value Factor Diversification: Is Quality Better Than Momentum?" (which
> compares quality against momentum, suggesting they don't run both
> separately).

---

## Category 1: Value

### 1.1 Quantitative Value (long-only, concentrated)

> ✓ verified: "The strategy seeks to buy the cheapest, highest quality
> value stocks." Linked white paper: "The Quantitative Value Investing
> Philosophy." Published as an ETF.

> ⚠ AI-inferred (from Gray & Carlisle, *Quantitative Value*, 2012; AA process
> diagram qv-process.png on /focusedfactors/):
> - Universe: large-cap US equities (top ~1,000)
> - Step 1: forensic accounting screen (Beneish M-Score, Sloan accruals,
>   distress filter)
> - Step 2: economic moat / quality screen (FCF/A, ROIC, leverage)
> - Step 3: cheapness rank by **EV/EBIT** (NOT P/B, NOT P/E)
> - Step 4: ~50-stock concentrated equal-weighted portfolio
> - Rebalance: quarterly
> - Long-only, no shorting

### 1.2 International Value (no longer in current lineup)

> ⚠ AI-inferred: AA previously ran an International Value strategy (IVAL ETF
> ticker, since converted/closed); not in the current focusedfactors menu.

### 1.3 Value-related white papers AA publishes

> ✓ verified titles (from white-papers page):
> - "Alternative" Facts about Formulaic Value Investing
> - Do Portfolio Factors or Characteristics Drive Expected Returns?
> - Even God would get fired as an Active Investor (drawdowns of value strategies)
> - Long-Only Value Investing: Size Doesn't Matter!
> - Value Factor Diversification: Is Quality Better Than Momentum?
> - Value Investing: An Examination of the 1,000 Largest Firms
> - What's the Story Behind EBIT/TEV?
> - Is Value Investing Dead? (research-category page)

| Sub-strategy | AA's definition | Signal | Rebalance | Universe | Cited paper |
|---|---|---|---|---|---|
| Quantitative Value (long-only) | Cheapest, highest-quality value stocks | EV/EBIT after quality + accounting screens | Quarterly | US large cap (~top 1000) | Gray & Carlisle (2012) |

---

## Category 2: Momentum

### 2.1 Quantitative Momentum (long-only, concentrated)

> ✓ verified: "The strategy seeks to buy stocks with the highest quality
> momentum." Linked white paper: "Quantitative Momentum Investing Philosophy."

> ⚠ AI-inferred (from Gray & Vogel, *Quantitative Momentum*, 2016; AA process
> diagram qm-steps.png on /focusedfactors/):
> - Step 1: rank by 12-2 (intermediate) momentum
> - Step 2: momentum-**quality** ("path") screen — favour smooth/persistent
>   12-month paths over jumpy ones; sometimes referred to as the "frog-in-the-pan"
>   (FIP) screen (Da, Gurun & Warachka 2014)
> - Step 3: ~50-stock concentrated equal-weighted portfolio
> - Rebalance: quarterly (NOT monthly — AA's distinctive choice to reduce
>   turnover and tax drag)
> - Long-only, no shorting

### 2.2 International Momentum (IMOM, currently in lineup)

> ⚠ AI-inferred: Same construction as Quantitative Momentum, applied to
> developed international equities. Not separately documented in our raw
> capture.

### 2.3 Momentum-related white papers AA publishes

> ✓ verified titles:
> - Momentum Investing, Like Value Investing, is Simple, but NOT Easy
> - The Many Facets of Stock Momentum
> - Enhancing Momentum Strategies
> - Momentum factor investing: Evidence and evolution
> - Can AI Read the News Better Than You? How ChatGPT Could Transform Momentum

| Sub-strategy | AA's definition | Signal | Rebalance | Universe | Cited paper |
|---|---|---|---|---|---|
| Quantitative Momentum (long-only) | Highest-quality 12-2 momentum stocks | 12-2 + FIP/path-smoothness screen | Quarterly | US large cap | Gray & Vogel (2016); Da, Gurun & Warachka (2014) |

---

## Category 3: Trend / Managed Futures

### 3.1 Global Value Momentum Trend (combined)

> ✓ verified: AA white paper "The Global Value Momentum Trend Philosophy"
> (URL on white-papers page). The lineup menu groups this under
> "Alternatives" alongside Managed Futures.

> ⚠ AI-inferred:
> - Combines: long-only value sleeve + long-only momentum sleeve + trend
>   overlay (TS-momentum on the equity sleeves to scale exposure during
>   sustained drawdowns)
> - Trend signal: simple moving-average-cross or 12-month TS-momentum
> - Universe: global equities (US + international)

### 3.2 Managed Futures

> ✓ verified: "Seek to provide a tax-efficient, tail-risk hedged, absolute
> return for family offices and HNW individuals." (from /managedfutures/)

> ⚠ AI-inferred:
> - Long-short time-series momentum across a basket of futures (equities,
>   bonds, currencies, commodities)
> - Trend signal: classic 12-month TS-momentum (Moskowitz, Ooi, Pedersen 2012)
> - Vol-targeting at portfolio and instrument level
> - Tax-efficient wrapper (LP / 1256 contracts → 60/40 long/short cap-gains)
> - Tail-risk hedged via long-vol overlay

### 3.3 Trend-related white papers AA publishes

> ✓ verified titles:
> - Trend Following: The Epitome of No Pain, No Gain
> - Avoiding the Big Drawdown with Trend-Following Investment Strategies
> - Trend-Following: A Deep Dive Into A Unique Risk Premium
> - The World's Longest Trend-Following Backtest

| Sub-strategy | AA's definition | Signal | Rebalance | Universe | Cited paper |
|---|---|---|---|---|---|
| Global Value Momentum Trend | Combined long-only V+M with trend overlay | EV/EBIT + 12-2 + TS-momentum trend filter | Quarterly | Global equities | AA white paper "GVMT Philosophy" |
| Managed Futures | TS-momentum across global futures, vol-targeted | 12-month TS-momentum | Daily/weekly | Equities, bonds, FX, commodities futures | Moskowitz, Ooi & Pedersen (2012) |

---

## Category 4: Other (single-name "More" in AA's nav)

> ⚠ AI-inferred: The "More" item in AA's nav expands to a long list of
> non-headline factor research themes. Sample article titles from the
> research-category-list page that fit here:

| AA Theme | Example articles |
|---|---|
| Asset allocation / multi-asset | "Are Factors Better and More Diversifying Than Asset Classes?", "Cut Through the Noise! These Two Factors Tend to Drive Portfolio Success" |
| Portfolio construction | "How Many Stocks Should Be In Your Portfolio?", "Intelligent Concentration: Buffett and Diversification" |
| Anomaly-Driven Demand (ADD) crowding | "When Everyone Trades the Same Factor Playbook" (this is the /factor-strategies/ slug!) |
| Mutual-fund flows | "Do Mutual Fund Flows Really Say What We Think They Say?" |
| Equity duration | "Equity duration and predictability" |
| Private credit | "Is There A Bubble In Private Credit?" |
| Commodities | "Commodity Futures Investing: Complex and Unique" (white paper) |
| Emerging markets | "Does Emerging Markets Investing Make Sense?" (white paper) |
| Box spreads (cash management) | "Box Spreads: An Alternative to Treasury Bills?" (white paper) |
| Behavioural / process | "Why you should trust the investment process (even though it's hard)" |
| Drawdown psychology | "Even God would get fired as an Active Investor" |

---

## CRITICAL gap (vs the dispatch's prior model)

The dispatch's specification asked for "one table per factor category
(value, momentum, quality, low-vol, size, multi-factor, alternative)". That
categorisation is closer to MSCI's or Morningstar's factor taxonomy than
to AA's. **AA does not publish standalone Quality, Low-Vol, or Size
strategies** — they fold quality into both value and momentum (as a
defensive screen), reject low-vol as a distinct factor (treating it as a
value-tilt in disguise), and do not target size. This is itself a
deliberate position visible in their white-paper titles ("Long-Only Value
Investing: Size Doesn't Matter!").

The gap-analysis file therefore uses AA's own categorisation
(Value · Momentum · Trend · Multi-factor combined · Other) rather than
forcing a standardised factor-zoo grid.

---

## What we could NOT extract

| Item | Why not |
|---|---|
| Specific Sharpe ratios, holding periods, factor loadings | Embedded in PNG process diagrams (qv-process.png, qm-steps.png); not in HTML; not transcribed per `external-code-zero-trust` |
| Current ETF tickers + AUM | Behind Cloudflare on /disclaimer page; not fetchable |
| Backtest start dates | Inside white-paper PDFs; not fetched |
| Performance attribution by sub-factor | Behind login wall |
| Cross-asset (bonds, FX) implementations beyond Managed Futures | No standalone page found |

These gaps are tagged in the wiki digest with a `> ⚠ AI-inferred:` marker
or a "PARKED" note in the recommended-issue stubs.

---

## Sources (in confidence order)

| # | Source | Confidence | What it gave us |
|---|---|---|---|
| 1 | RSS feed `/feed/` live HTTP 200 (2026-06-04) | direct quote | The full /factor-strategies/ Swedroe post body |
| 2 | Wayback `/focusedfactors/` 2025-08-04 HTTP 200 | direct nav + 2 short paragraphs | AA's actual long-only menu + two captions |
| 3 | Wayback `/research-category-list/` 2026-01-29 HTTP 200 | direct headings + 20+ article titles | AA's 5-category research taxonomy + article catalogue |
| 4 | Wayback `/alpha-architect-white-papers/` 2025-08-04 HTTP 200 | direct titles | The 23 verified white-paper titles |
| 5 | Wayback `/managedfutures/` 2025-08-04 HTTP 200 | one direct paragraph | One-line marketing description |
| 6 | Wesley Gray & Tobias Carlisle, *Quantitative Value* (Wiley, 2012) | external reference work | Inferred QV construction details |
| 7 | Wesley Gray & Jack Vogel, *Quantitative Momentum* (Wiley, 2016) | external reference work | Inferred QM construction details |
| 8 | Issue #279 (closed) | internal | Confirmed /factor-strategies/ is the ADD post, not a taxonomy |
| 9 | Issue #18 (closed) | internal | Original /factor-max/ Factor Max strategy reference |
| 10 | Issue #119 (closed) | internal | Original /momentum-investing-struggling/ Mozes paper |

External-code-zero-trust note: no AA code snippets, no AA-hosted "free
analyser" tools were used. All external-reference inferences are from
published books that have been in our reading list since the project
started.
