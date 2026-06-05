---
title: Alpha Architect Factor Strategies — Taxonomy and Our Coverage
canonical_question: "What factor strategies does Alpha Architect publish, and which of them does our 14-strategy library cover?"
status: active
fresh_until: 2027-06-04
consensus_level: indirect
sources:
  - alphaarchitect-factor-strategies-2026-06-04.html
  - alphaarchitect-taxonomy-2026-06-04.md
compiled_by: claude-opus-4-7
compiled_on: 2026-06-04
tags: [alpha-architect, factor-investing, value, momentum, trend, gap-analysis, wesley-gray]
---

# Alpha Architect Factor Strategies — Taxonomy and Our Coverage

Alpha Architect (Wesley Gray, Jack Vogel, and team) publishes a deliberately
narrow factor taxonomy: **Value · Momentum · Trend / Managed Futures · a
combined Global Value Momentum Trend (GVMT) sleeve · and a long tail of
"Other" research themes** (asset-allocation, portfolio construction, the
ADD-style crowding work, equity duration, cash management via box spreads).
They explicitly do NOT publish standalone Quality, Low-Vol, or Size
strategies. Our library has strong overlap with the Momentum branch
(4 of our 14 strategies), partial overlap with the Combined / Multi-asset
branch (3 strategies are factor-rotation overlays), and material **gaps**
on the Value branch (no fundamental Value sleeve) and the Trend / Managed
Futures branch (no cross-asset TS-momentum).

The companion gap-analysis matrix is at
`alphaarchitect-gap-analysis-2026-06-04.md` and the recommended-issue stubs
are at the bottom of that file.

> ⚠ AI-inferred: This page synthesises content from four AA pages (live
> RSS + three Wayback snapshots) plus the Gray & Carlisle and Gray & Vogel
> reference books. Specific construction details (EV/EBIT cheapness,
> path-smoothness quality screen, quarterly rebalance) are NOT directly
> visible in the HTML we could fetch — they come from those external books.
> See the "AI disclosure" section at the bottom.

---

## Sources

| Source | Date captured | Method | Confidence |
|---|---|---|---|
| RSS feed live https://alphaarchitect.com/feed/ | 2026-06-04 | curl HTTP 200; UA `Mozilla/5.0` | Direct (full article body) |
| Wayback `/focusedfactors/` (2025-08-04) | 2026-06-04 | curl through `web.archive.org` HTTP 200 | Direct (menu + 2 paragraphs) |
| Wayback `/research-category-list/` (2026-01-29) | 2026-06-04 | curl through `web.archive.org` HTTP 200 | Direct (headings + 20+ article titles) |
| Wayback `/alpha-architect-white-papers/` (2025-08-04) | 2026-06-04 | curl through `web.archive.org` HTTP 200 | Direct (23 paper titles) |
| Wayback `/managedfutures/` (2025-08-04) | 2026-06-04 | curl through `web.archive.org` HTTP 200 | Direct (one paragraph) |
| Wesley Gray & Tobias Carlisle, *Quantitative Value* (Wiley, 2012) | n/a | external reference book | High-confidence inferred |
| Wesley Gray & Jack Vogel, *Quantitative Momentum* (Wiley, 2016) | n/a | external reference book | High-confidence inferred |
| Issue [#18](https://github.com/JohnGavin/historical/issues/18) "Factor Max strategy backtest (Alpha Architect)" — closed | 2026-06-04 | `gh issue view 18` | Internal cross-ref |
| Issue [#119](https://github.com/JohnGavin/historical/issues/119) "Investigate momentum underperformance" — closed | 2026-06-04 | `gh issue view 119` | Internal cross-ref |
| Issue [#279](https://github.com/JohnGavin/historical/issues/279) "Anomaly-Driven Demand (ADD)" — closed | 2026-06-04 | `gh issue view 279` | Internal cross-ref (confirmed /factor-strategies/ is the ADD post, not a taxonomy) |
| Companion raw HTML capture | 2026-06-04 | this session | This file |

> ✓ verified: AA's site is behind Cloudflare and returns 403 for direct
> curl from non-JS clients. The only un-blocked endpoint is the main
> `/feed/` RSS (5 most recent items). All other pages came via Wayback.

---

## Fetch method and constraints

The dispatch's expected method (`curl` with browser UA + headers) returned
HTTP 403 across every AA URL tested. The site enforces Cloudflare's
"Just a moment..." JS challenge globally, including on the `sitemap.xml`,
the WP REST API, and category-level feeds. The only un-challenged
endpoint discovered was the main RSS feed at `/feed/`, which contains the
5 most recent posts with full `<content:encoded>` bodies.

For the full strategy taxonomy we fell back to **Wayback Machine snapshots**
from August 2025 (`/focusedfactors/`, `/alpha-architect-white-papers/`,
`/managedfutures/`) and January 2026 (`/research-category-list/`). All
returned HTTP 200 and yielded the menu structure, white-paper titles, and
short marketing paragraphs preserved in the raw capture.

**Critical reframe:** the URL the dispatch named —
`alphaarchitect.com/factor-strategies/` — is NOT a multi-factor taxonomy
page. It is a single Larry Swedroe blog post (2026-05-22) titled
**"When Everyone Trades the Same Factor Playbook"**, digesting the
Posselt & Kjær (March 2026) "Anomaly-Driven Demand" (ADD) paper. We've
already covered that paper in depth at [[anomaly-driven-demand]] (compiled
2026-05-25). This wiki page therefore covers the broader AA factor lineup,
not the ADD post.

---

## Alpha Architect's top-level taxonomy

> ✓ verified: AA's site Research navigation has exactly five top-level
> categories, in this order:

| Category | What it covers |
|---|---|
| **Value** | EV/EBIT cheapness with forensic + quality screens (Gray & Carlisle 2012) |
| **Momentum** | 12-2 cross-sectional momentum with path-quality screen (Gray & Vogel 2016) |
| **Trend** | Time-series momentum / managed-futures overlays |
| **White Papers** | Long-form firm research |
| **More** | Asset allocation, portfolio construction, behaviour, equity duration, ADD crowding, cash-management, EM, commodities |

> ⚠ AI-inferred: AA does NOT publish:
> - A standalone Quality strategy (quality is folded into Value and Momentum)
> - A Low-Vol / Min-Vol strategy (rejected as a value-tilt in disguise)
> - A Size strategy ("Long-Only Value Investing: Size Doesn't Matter!" is
>   an AA white paper title)
> - An ESG strategy
> - A macro / global-tactical-allocation strategy

This narrow taxonomy is itself a deliberate position. Wesley Gray's
public writing argues that the only **academically robust** premia worth
trading systematically are Value, Momentum, and Trend, and that
Quality, Low-Vol and Size either subsume each other or fold into the
three primary factors.

---

## AA's strategies in detail

### 1. Quantitative Value (long-only, ~50-stock concentrated)

> ✓ verified: AA describes this as "the cheapest, highest quality value
> stocks", linking to their white paper "[The Quantitative Value Investing
> Philosophy](https://alphaarchitect.com/the-quantitative-value-investing-philosophy/)".

> ⚠ AI-inferred construction (from Gray & Carlisle 2012):
> 1. Universe: US large-cap equities (top ~1,000 by market cap)
> 2. Forensic accounting filter (Beneish M-Score for manipulation, Sloan
>    accruals for earnings quality, distress indicators)
> 3. Quality screen (FCF/Assets, ROIC, leverage)
> 4. Cheapness rank by **EV/EBIT** (NOT P/B, NOT P/E — explicitly rejected
>    in their "What's the Story Behind EBIT/TEV?" white paper)
> 5. ~50-stock equal-weighted portfolio
> 6. Quarterly rebalance
> 7. Long-only, no shorting

Distinctive features vs textbook value:
- EV/EBIT (not B/M) — captures enterprise value and operating income
- Forensic accounting screen is a defining feature
- Concentration (~50 names) rather than broad (~300+ names like VLUE)
- Quarterly (not monthly) to reduce turnover and tax drag

### 2. Quantitative Momentum (long-only, ~50-stock concentrated)

> ✓ verified: AA describes this as "stocks with the highest quality
> momentum", linking to their white paper "[Quantitative Momentum Investing
> Philosophy](https://alphaarchitect.com/quantitative-momentum-investing-philosophy/)".

> ⚠ AI-inferred construction (from Gray & Vogel 2016):
> 1. Universe: US large-cap equities
> 2. Rank by **12-2 momentum** (cumulative return from t-12 to t-2,
>    skip the most recent month)
> 3. **Quality screen** for path-smoothness — favour stocks with smooth,
>    persistent 12-month return paths over jumpy ones. Sometimes called
>    "frog-in-the-pan" (FIP, Da/Gurun/Warachka 2014); also known as
>    "momentum-quality"
> 4. ~50-stock equal-weighted portfolio
> 5. **Quarterly rebalance** (NOT monthly — distinctive AA choice)
> 6. Long-only, no shorting

Distinctive features vs textbook 12-2 momentum:
- Path-quality screen (FIP) — this is the key innovation
- Quarterly (not monthly) rebalance — distinctive AA tax/cost choice
- ~50-stock concentration vs the academic decile portfolio (~100-200 names)

### 3. Global Value Momentum Trend (GVMT — combined, with trend overlay)

> ✓ verified: AA white paper "[The Global Value Momentum Trend
> Philosophy](https://alphaarchitect.com/the-value-momentum-trend-philosophy/)"
> documents this strategy. Lineup menu groups it under "Alternatives"
> alongside Managed Futures.

> ⚠ AI-inferred:
> - Combines a long-only Value sleeve + long-only Momentum sleeve (US + intl)
> - Adds a **trend overlay** that scales total equity exposure based on
>   either moving-average crosses or 12-month TS-momentum on the index
> - Trend signal switches the strategy to cash/bills during sustained
>   equity drawdowns
> - Targets reduced drawdown vs static long-only V+M while preserving
>   most of the upside

### 4. Managed Futures (long-short TS-momentum across asset classes)

> ✓ verified: AA's tagline is "tax-efficient, tail-risk hedged, absolute
> return for family offices and HNW individuals." (from /managedfutures/)

> ⚠ AI-inferred construction:
> - Long-short TS-momentum (Moskowitz, Ooi, Pedersen 2012)
> - Universe: liquid futures across equities, bonds, currencies, commodities
> - 12-month TS-momentum signal (sign of past-12m return → long or short)
> - Vol-targeting at both instrument and portfolio level
> - Tax-efficient wrapper (1256 contracts → 60/40 LTCG/STCG)
> - Tail-risk hedged via long-vol overlay or convexity hedge

---

## Our 14 strategies — quick map to AA's taxonomy

| # | Our strategy | AA branch | Match strength |
|---|---|---|---|
| 1 | Avoid Worst Days (VIX) | None — overlay | Adjacent to GVMT's trend overlay (different mechanism) |
| 2 | Factor DRIF | Value + Momentum + Quality (combined factor rotation) | Adjacent to GVMT (different mechanism: factor-on-factor rotation) |
| 3 | Factor MAX | Factor momentum | Closest to AA's "Enhancing Momentum Strategies" research |
| 4 | Risk State (VIX) | None — overlay | Adjacent to GVMT trend overlay |
| 5 | LTR (CS Momentum) | Momentum | **DIRECT** — but no path-quality / FIP screen |
| 6 | Turn-of-the-Month | None | Adjacent to AA's "calendar / seasonality" Other category |
| 7 | Stock MAX | Momentum (daily / volatility-sorted) | Adjacent to Momentum branch (different signal: lottery / extreme returns) |
| 8 | Stock DRIF | Quant ML | No direct AA match (ML signals not in AA lineup) |
| 9 | XGB DRIF | Quant ML | No direct AA match |
| 10 | PSO Optimal | Multi-strategy combination | Adjacent to GVMT (different combination method) |
| 11 | Commodities Mean Reversion | Other (commodities) | Adjacent to AA's "Commodity Futures Investing" white paper (different direction: MR not trend) |
| 12 | Mom Pre-Peak (Büsing) | Momentum decomposition | Adjacent to AA's "The Many Facets of Stock Momentum" research |
| 13 | Mom Post-Peak (Büsing) | Momentum decomposition | As above |
| 14 | Mom 12-2 (Büsing baseline) | **Momentum** | **DIRECT** — academic 12-2 baseline |

We have **strong Momentum coverage** (5 of 14 strategies are momentum
variants), **partial GVMT-style multi-factor coverage** (3 of 14 are
factor-rotation overlays), and **near-zero Value coverage** (no
fundamental Value sleeve) and **zero Managed Futures / cross-asset
TS-momentum coverage**.

The detailed per-strategy gap classification is in
`alphaarchitect-gap-analysis-2026-06-04.md`.

---

## Highest-leverage gaps (preview — full ranking in gap-analysis)

> ⚠ AI-inferred: ranking is the author's view of incremental edge,
> not yet user-approved.

1. **No fundamental Value sleeve.** Every momentum-class strategy we run
   loads on the opposite side of the value factor. Adding a long-only
   EV/EBIT value sleeve (à la AA Quantitative Value) would diversify the
   leaderboard. The Büsing momentum-decomposition work (#365) explicitly
   noted this asymmetry.
2. **No cross-asset TS-momentum (managed futures).** Our trend overlays
   (RSC, Avoid Worst) are all VIX-based on US equity. AA's Managed Futures
   uses 12-month TS-momentum across equities/bonds/FX/commodities and
   gets a different return stream. Cross-asset TS-momentum is one of the
   most-replicated premia in the academic literature.
3. **No "frog-in-the-pan" / momentum-quality screen on our momentum
   strategies.** Da, Gurun & Warachka (2014) showed that path-smoothness
   significantly improves 12-2 momentum returns net of transaction
   costs. AA's QMOM uses this; our LTR, Mom 12-2, and Pre/Post-Peak
   variants do not.

See gap-analysis file for the full prioritised list and the recommended
issue stubs.

---

## Cross-links

- [[anomaly-driven-demand]] — what `/factor-strategies/` actually is
  (the Swedroe-ADD post). This wiki page covers the broader AA lineup;
  ADD is the specific topic of that URL.
- [[priced-in-signals]] — companion rule for information being already
  priced. AA's argument for momentum and value being persistent is that
  they reflect behavioural mispricing, NOT priced-in macro info — see
  the contrast in section "What Might Work Instead" on that page.
- [[market-behavior-gap-analysis]] — broader factor-vs-implementation
  audit; this AA page slots into the "factor breadth" dimension of
  that analysis.
- [[swedroe-evidence-investing]] (if present; else `swedroe-anomaly-driven-demand-2026-05-22.md` raw) — Swedroe is AA's most prolific guest author. His five-criteria framework (persistent, pervasive, robust, investable, intuitive) and the `priced-in-prohibition` / `cross-geography-pervasiveness` / `resulting-prohibition` / `backtest-robustness` rules under `.claude/rules/` operationalise the AA/Swedroe stance.
- [[momentum-decomposition-cross-asset]] — our momentum work; map of which decomposition variants we cover.

> ⚠ AI-inferred: `[[swedroe-evidence-investing]]` is referenced in
> several `.claude/rules/*.md` files but I did NOT confirm a wiki page
> with that exact slug exists. The Swedroe content is captured in two
> raw files (`swedroe-anomaly-driven-demand-2026-05-22.md` and
> `anomaly-driven-demand-kjaer-posselt-2025.md`) and may be partly
> integrated in `anomaly-driven-demand.md` rather than a separate page.

---

## Methodology

### What this page computes

This page summarises Alpha Architect's published factor-strategy lineup
(value / momentum / trend / managed futures / GVMT combined) and maps
each of our 14 strategies onto AA's taxonomy. It is descriptive — no
new returns are computed.

### Data sources

- Live AA RSS feed at `https://alphaarchitect.com/feed/` (HTTP 200,
  2026-06-04 fetch, 5 items)
- Wayback Machine snapshots for `/focusedfactors/`, `/research-category-list/`,
  `/alpha-architect-white-papers/`, `/managedfutures/` (all HTTP 200,
  August 2025 / January 2026 snapshots)
- Wesley Gray & Tobias Carlisle, *Quantitative Value* (Wiley, 2012) — external
- Wesley Gray & Jack Vogel, *Quantitative Momentum* (Wiley, 2016) — external
- Our [`R/plan_strategy_names.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_names.R) for the 14-strategy roster
- Closed issues [#18](https://github.com/JohnGavin/historical/issues/18), [#119](https://github.com/JohnGavin/historical/issues/119), [#279](https://github.com/JohnGavin/historical/issues/279) on this repo for prior AA engagements

### AI disclosure

This vignette was developed with assistance from Anthropic's Claude (model:
Opus 4.7 and Sonnet 4.6). AI helped with code structure, prose drafting,
and visualization choices. All analytical decisions and data
interpretations are the author's responsibility.

Specific to this page: every construction detail tagged
`> ⚠ AI-inferred:` is sourced from external reference works (Gray &
Carlisle 2012, Gray & Vogel 2016) rather than from AA's HTML — which is
largely image-rendered marketing material. Where AA's HTML is the direct
source, the tag is `> ✓ verified:`. No code snippets were copied from
AA per `external-code-zero-trust`.
