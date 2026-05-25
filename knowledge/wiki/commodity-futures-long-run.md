---
title: "Long-Run Commodity Futures Index: 1871–2025"
canonical_question: "What is the long-run risk premium for commodity futures, and can the underlying data be freely accessed?"
status: active
fresh_until: 2026-11-25
consensus_level: direct
sources:
  - commodity-futures-index-since-1871-janardanan-2026.md
compiled_by: claude-sonnet-4-6
compiled_on: 2026-05-25
tags: [commodity, futures, long-run, risk-premium, carry, roll-yield, survivorship, SummerHaven, AQR]
---

# Long-Run Commodity Futures Index: 1871–2025

Janardanan, Qiao, and Rouwenhorst (January 2026) present a 155-year equally-weighted, collateralised commodity futures index built from 230 hand-collected contracts traded on U.S. exchanges since 1871. The paper establishes commodity futures as a distinct asset class with a risk premium comparable in magnitude to equities, provides a rigorous carry/roll-yield decomposition, and corrects for survivorship bias by explicitly including obsolete contracts. The underlying index is proprietary SummerHaven data; a freely downloadable alternative from AQR (Levine et al. 2018) covers substantially the same history.

## The Index

### Data collection

> "The data used in this chapter draws from a hand-collected dataset of **230 contracts** going back to **1871** when futures trading commenced in the United States. This comprehensive dataset combines prices from prominent newspapers with exchange handbooks." — [commodity-futures-index-since-1871-janardanan-2026.md:183](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L183)

> "A unique and important aspect of the database is the extensive coverage of contracts that have ceased trading over time. Janardanan et al. (2025) show that poor investor performance is negatively correlated with contract survival." — [raw:187](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L187)

Earlier data efforts are notably thin: CRB/Barchart starts 1959, Levine et al. (2018) and Geczy-Samanov (2019) "cover very few contracts prior to 1950" ([raw:180](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L180)). This makes the 1871 origin a genuine contribution. See also #150 (survivorship-bias filter gap) for implications on the in-house pipeline.

### Construction rules

Three choices define the index ([raw:215](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L215)):

| Rule | Detail |
|------|--------|
| Contract maturity | Nearest-to-maturity contract that does **not** expire in month t+1 (front contract, most liquid) |
| Commodity weighting | **Equal weight**; same underlying on different exchanges treated as separate commodities |
| Rebalancing | **Monthly** |

The index is fully collateralised — notional is invested in T-Bills, so the excess return is equivalent to the commodity risk premium ([raw:142](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L142)).

Index breadth grew from <20 commodities in the 1870s to ~30 by 1900 and ~50 by the early 2000s; wars caused temporary contractions ([raw:277](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L277)).

## Key Findings

### Risk premium

> "Commodity futures have earned an average annual risk premium of **5.4%** over the risk-free rate and a premium over US inflation of more than **6% per annum**." — [raw:36](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L36)

Table 1 (full sample 1871–2025) gives slightly higher numbers in the sub-panel reading:

| Series | Risk premium (% p.a.) | Volatility (% p.a.) | Sharpe ratio |
|--------|----------------------|---------------------|--------------|
| Commodity futures (EW, collateralised) | **5.5** | **14.3** | **0.38** |
| Commodity spot index | lower (markedly) | 14.3 | 0.22 |
| Stock index | 6.6 | 16.2 | 0.41 |

([raw:433](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L433))

The abstract quotes 5.4% while the body text (Section 7 summary) quotes 5.5%; the difference reflects geometric vs arithmetic averaging conventions. Sharpe ratios for commodity futures (0.38) and equities (0.41) are statistically close over 155 years.

### Consistency across sub-periods

Fifty-year geometric total returns fall in the narrow range of **7.8–8.7%** for commodity futures versus **6.5–12.6%** for equities ([raw:459](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L459)). Sharpe ratios (0.31–0.48) also show less variability than equities (0.29–0.57), making commodity futures unusually stable as an asset class across long historical windows.

### Commodity futures vs equities

> "Commodity futures have outperformed equities in roughly **43%** of years and in **two out of every five decades**, suggesting distinct return drivers and meaningful diversification benefits." — [raw:37](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L37)

The divergence-then-convergence pattern visible in cumulative log-scale charts (Figure 2) is the empirical signature of different fundamental return drivers — commodities provide periodic outperformance precisely when equities do not ([raw:295](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L295)). This is the diversification case for commodities as an asset class.

> ⚠ AI-inferred: Synthesising Section 5.2 ([raw:333](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L333)) and the quality-gate framing from [[swedroe-evidence-investing]], the "two out of five decades" outperformance rate is consistent with Swedroe's documented multi-decade underperformance periods being the norm, not evidence against the strategy. See issue #273 (commodities QIS/carry) for tactical implications.

## Carry and Roll-Yield Decomposition

### The three-way identity

The paper provides a precise decomposition (equations [5]–[7], [raw:363](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L363)):

**Equation [5] — Futures excess return identity:**

```
Futures Excess Return = Spot Return + Roll Yield
```

where **Roll Yield** (= "carry") is the slope of the futures curve between the front and the next contract. Backwardation (downward-sloping curve) → positive roll yield; Contango (upward-sloping) → negative roll yield.

**Equation [6] — Theory of Storage decomposition:**

```
Roll Yield = Convenience Yield (y) − [Interest (r) + Storage Costs (u)]
```

The convenience yield is the benefit of holding the physical commodity for productive use (Kaldor 1939, Working 1949).

**Equation [7] — Interest-adjusted carry (futures vs spot on a like-for-like basis):**

```
Futures Excess Return − Spot Excess Return = Convenience Yield − Storage Costs  (y − u)
```

### Empirical findings on carry

> "The futures excess return has historically **lagged** the spot return due to the cumulative effect of **negative carry** (roll yield) over the past 150 years." — [raw:413](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L413)

> "The futures excess return has historically **exceeded** the spot price excess return (positive **interest-adjusted carry**)." — [raw:415](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L415)

In plain terms: raw roll yield has been slightly negative on net (contango outweighed backwardation over the full 155 years), but once collateral interest is included, futures still beat the spot index. The convenience yield net of storage has been positive in aggregate.

> ⚠ AI-inferred: This finding directly speaks to issue #273 (commodities QIS / carry). A negative average roll yield over the long run does not mean a carry strategy has no edge — it means the *cross-sectional* dispersion of carry across individual commodities is where the edge lives, not the time-series average. See also #138 and #134 (failed commodity momentum) where signal decay at the index level parallels this aggregate carry result.

### Keynes' Theory of Normal Backwardation

The risk-premium interpretation — producers pay a premium to hedge by selling futures forward; speculators on the long side earn that premium — is attributed to Keynes (1930) and is described as "commonly known as the Theory of Normal Backwardation" ([raw:160](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L160)). The empirical finding that the majority of the 230 individual contracts earned a positive average excess return over their lifetimes ([raw:311](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L311)) is consistent with this theory.

## Data Access

The 1871 index itself is **proprietary SummerHaven Investment Management data** — it is not publicly downloadable. This mirrors the situation with DMS data in issue #98 (DMS→JST decision), where we adopted a free alternative (JST) rather than a commercial dataset.

### Free alternatives

#### Levine, Ooi, Richardson & Sasseville (2018) — AQR data library [RECOMMENDED]

**Coverage:** Daily futures prices from **1877** through December 2015 in the original-paper dataset; a separately maintained monthly-updated series extends to at least May 2025.

**Download status: FREE, no registration required.**

Two datasets on the AQR Insights page:

| Dataset | URL | Period | Format |
|---------|-----|--------|--------|
| Original Paper Data | [aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Original-Paper-Data](https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Original-Paper-Data) | 1877–Dec 2015 | Excel (.xlsx) |
| Index Level Data, Monthly (updated) | [aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly](https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly) | 1877–present | Excel (.xlsx) |

Both datasets provide: equal-weighted portfolio excess returns, long-short (backwardation/contango) portfolio excess returns, spot/carry decomposition. The monthly-updated version was last refreshed May 2025.

> ⚠ AI-inferred: The AQR dataset starts in 1877 (six years after the Janardanan 1871 index) and covers a narrower contract universe (Levine et al. note "very few contracts prior to 1950"), but for practical pipeline purposes the 1877–present coverage is more than adequate for the regime-classification and carry-signal work in #273.

#### Bhardwaj, Gorton & Rouwenhorst (2021) — "The First Commodity Futures Index of 1933"

Published in the *Journal of Commodity Markets* (Vol. 23, 2021). The paper documents the Dow Jones Commodity Futures Index from 1933. The SSRN preprint is free ([ssrn.com/abstract=3451443](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3451443)), but **no standalone downloadable dataset was found** — data access appears to be request-only via journal supplementary materials or author contact. Lower priority than the AQR series for our use case given the shorter history.

#### CRB / Barchart (1959+)

Commercial dataset. Acknowledged in the paper as "one of the most popular commercial datasets" ([raw:179](../raw/commodity-futures-index-since-1871-janardanan-2026.md#L179)). Starts 1959. Not free; not recommended when the AQR series provides 80 additional years for free.

#### SummerHaven SDCI (current index product)

SummerHaven publishes a Data Dashboard at [summerhavenindex.com/data-dashboard/](https://summerhavenindex.com/data-dashboard/) but this covers the current SDCI product (14 futures, selected monthly on momentum/carry signals), not the historical 1871 research database. The 1871 dataset is not publicly available.

### Recommendation

**Adopt the AQR Levine et al. dataset as the free long-run commodity benchmark.** This mirrors the DMS→JST decision (#98): use the best freely available alternative rather than a commercial/proprietary series. The 1877–present monthly Excel file from AQR requires no registration, has a documented methodology, and covers the same carry decomposition components (spot return + roll yield) that the Janardanan paper uses.

The practical onboarding path (when issue #280 is actioned): download the Excel, ingest to DuckDB parquet, register in `R/dataset_registry.R`. The carry decomposition column (interest-adjusted carry) makes it directly usable for the commodities QIS work in #273.

## Related

See also [[swedroe-evidence-investing]] for the five-criteria factor evaluation framework (persistent, pervasive, robust, investable, intuitive) and how commodity futures scores against it.

Issues: #280 (this wiki page), #273 (commodity QIS / carry strategies), #138 and #134 (failed commodity momentum — note the aggregate-vs-cross-sectional carry distinction above), #98 (DMS→JST free-data precedent), #150 (survivorship-bias filter).

## Sources

- [commodity-futures-index-since-1871-janardanan-2026.md](../raw/commodity-futures-index-since-1871-janardanan-2026.md) — full paper digest; key sections: Abstract (L34-41), Findings (L88-96), Data (L174-205), Index Construction (L207-238), Equity Comparison (L283-344), Carry Decomposition (L348-425), Table 1 (L429-461)
- [AQR Insights — Commodities for the Long Run: Original Paper Data](https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Original-Paper-Data) — free Excel download, 1877–2015
- [AQR Insights — Commodities for the Long Run: Index Level Data, Monthly](https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly) — free Excel download, 1877–present (updated May 2025)
- [Bhardwaj, Gorton & Rouwenhorst (2021) on SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3451443) — "First Commodity Futures Index of 1933"; paper free, data request-only
- [SummerHaven Data Dashboard](https://summerhavenindex.com/data-dashboard/) — current SDCI product only; 1871 historical database not publicly available
