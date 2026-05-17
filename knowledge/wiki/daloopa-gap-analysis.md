---
title: daloopa/investing Gap Analysis
canonical_question: What does daloopa/investing offer that our backtesting library lacks, and what should we adopt?
status: active
fresh_until: 2027-05-16
consensus_level: direct
sources:
  - https://github.com/JohnGavin/historical/issues/78
compiled_by: claude-sonnet-4-6
compiled_on: 2026-05-16
tags: [data-gaps, fundamentals, mcp, gap-analysis]
---

## One-Line Gist

Daloopa fills our zero-coverage gap on company fundamentals and SEC filings; we fill their zero-coverage gap on macro, factors, commodities, and volatility surfaces — but most of daloopa's 24 analyst-workflow skills are out-of-scope for a backtesting library.

## Daloopa Overview

[daloopa/investing](https://github.com/daloopa/investing) is a Claude Code MCP integration targeting hedge fund analysts. It exposes 4 MCP tools, 12 REST endpoints, and 24 Claude Code skills covering GAAP fundamentals (12,000+ US companies), KPIs, segment revenue, earnings tracking, and SEC full-text search. Issue #78 contains the full tabulation; see the Sources section.

> ⚠ AI-inferred: The 24 skills are oriented toward equity research deliverables (DCF models, IB decks, research notes) rather than systematic backtesting, implying limited overlap with our quantitative pipeline.

## What Our Project Has Today

Sourced from `packages/historicaldata/R/registry.R` (`hd_datasets()` and `hd_macro_registry()`):

| Category | Datasets / Series | Source |
|----------|-------------------|--------|
| Equity OHLCV (daily) | US equities, Yahoo Finance | `equity_daily.parquet` |
| Crypto prices | CoinGecko daily close + market cap | `crypto_daily.parquet` |
| Macro series (81 series) | FRED: rates, spreads, inflation, GDP, CPI, housing, money supply | `macro_daily.parquet` |
| Factor returns | Fama-French 3/5 + Momentum, 1926+ | `factors.parquet` |
| Ticker metadata | Exchange, sector, market cap, ETF fees/yield, coverage stats | `metadata.parquet` |
| Macro vintages | FRED ALFRED revision history (point-in-time) | `macro_vintages.parquet` |
| Implied volatility surfaces | CBOE VIX term structure (9D/1M/3M/6M/1Y), VVIX, SKEW; equity index vols (VXN, VXD, RVX); single-stock vols (VXAPL, VXAZN, …); VSTOXX, VDAX, VCAC | `macro_daily.parquet` (cboe source_type) |
| Options strategy benchmarks | CBOE BXM, PUT, WPUT, PPUT, collars, condors | `macro_daily.parquet` (cboe source_type) |
| Implied correlation / dispersion | COR1M/3M/6M/1Y, DSPX | `macro_daily.parquet` |
| Variance risk premium | VPD, VPN | `macro_daily.parquet` |
| Credit spreads | ICE BofA HY/IG OAS | `macro_daily.parquet` |
| Commodities | WTI crude (FRED + CBOE OVX) | `macro_daily.parquet` |
| Currencies | Trade-weighted USD, EUR/USD vol | `macro_daily.parquet` |

**Zero coverage today:** company-level GAAP financials, non-GAAP KPIs, segment revenue, management guidance, earnings history, book value, shares outstanding — any per-ticker fundamental data.

## Gap Matrix

| Daloopa Capability | We Have | Status |
|-------------------|---------|--------|
| GAAP financials (income statement, balance sheet, cash flow) — 12,000+ US cos | None | **Missing** |
| Non-GAAP KPIs and operational metrics — 8,000+ cos | None | **Missing** |
| Segment revenue by geography / product — 7,000+ cos | None | **Missing** |
| Management guidance per announcement — 5,000+ cos | None | **Missing** |
| SEC filing full-text search | None | **Missing** |
| Company discovery / ticker lookup (`discover_companies`) | `hd_tickers()` (OHLCV only) | **Partial** |
| Market data (quotes, basic multiples) | Yahoo via `equity_daily`; metadata has P/E, beta, yield | **Has equivalent** |
| Earnings analysis reports (HTML output) | None planned | **Out of scope** |
| DCF / valuation modelling skills | None planned | **Out of scope** |
| Research notes (.docx) | None planned | **Out of scope** |
| IB pitch decks (.pdf) | None planned | **Out of scope** |
| Comparable company sheets (.xlsx) | None planned | **Out of scope** |
| Precedent transaction comps | None planned | **Out of scope** |
| Supply-chain network graph | None planned | **Out of scope** |
| Factor returns (FF3/FF5/Momentum) | `factors.parquet` (1926+) | **We exceed daloopa** |
| Macro series (81 FRED + CBOE vol) | `macro_daily.parquet` | **We exceed daloopa** |
| Implied vol surfaces (VIX term structure, international) | `macro_daily.parquet` | **We exceed daloopa** |
| Commodities, currencies, credit spreads | `macro_daily.parquet` | **We exceed daloopa** |

## Recommendations

### 1. Defer — `hd_fundamentals()` for RAFI-style factor construction (Phase 3 of issue #78)

**Verdict: Defer (medium-priority, multi-week effort)**

Building a `hd_fundamentals(ticker, metric, period)` wrapper caching key GAAP metrics (revenue, book value, earnings, shares outstanding) would unblock fundamental-weighted factor strategies (#75). This is the highest-value data gap because it enables factor construction beyond price-only signals.

However, it requires a paid Daloopa API account. Treat identically to #150 Option A (point-in-time data acquisition): label `low-priority`, estimate multi-week effort, do not block current roadmap.

Prerequisite: sign up for free Daloopa account and test rate limits / response format with AAPL/MSFT before committing to an `hd_fundamentals()` implementation.

### 2. Defer — MCP server integration for Claude Code sessions (Phase 2 of issue #78)

**Verdict: Defer (low-priority)**

Adding the Daloopa MCP server to `.mcp.json` enables natural-language fundamental queries during development sessions (`discover_companies`, `get_company_fundamentals`). This is useful for exploratory work and does not require writing any R package code. Blocked on: free account signup and OAuth flow verification.

> ⚠ AI-inferred: The MCP server requires a Bearer token; the free-tier rate limits are undocumented and may make it impractical for pipeline-scale use even if interactive use works.

### 3. Reject as out of scope — all 15 analyst-workflow skills

**Verdict: Reject (all analysis report and deliverable skills)**

The 15 HTML-report skills (`/earnings`, `/dcf`, `/comps`, `/bull-bear`, `/tearsheet`, etc.) and 6 document-output skills (`/research-note`, `/build-model`, `/ib-deck`, etc.) target equity research analysts producing client-facing deliverables. This project is a backtesting R package; it has no use for `.docx` research notes or `.pdf` pitch decks. Adopting these skills would add no value and would misalign the project's scope.

### 4. Adopt — REST API design patterns for our public API (#2)

**Verdict: Adopt (design lesson, no code cost)**

Daloopa's MCP-first design (4 tools covering full fundamental coverage) and REST endpoint patterns (`/companies`, `/export/{TICKER}`, `/status`, `/taxonomy`, `/series-continuation`) are directly applicable to our planned public API (#2). Specific adoptions:

- Expose `hd_search()` / `hd_ticker_meta()` via HTTP mirroring `/companies` search endpoint
- Add `/status` polling endpoint for data freshness (maps to our `macro_vintages` timestamps)
- Add `/series-continuation` pattern for FRED series retirement tracking
- Consider MCP-wrapping our DuckDB/Arrow store for natural-language queries

This is a zero-cost design adoption: incorporate lessons into #2 architecture planning.

### 5. Reject — earnings tracking, guidance, and SEC search as standalone features

**Verdict: Reject (out of scope without paid data)**

Earnings beat/miss tracking and SEC filing search are core to analyst workflows but tangential to systematic backtesting. If a fundamental factor strategy is ever built (Recommendation 1), earnings data becomes relevant — but as inputs to factor construction, not as standalone features. Do not build `hd_earnings()` or `hd_sec_search()` without a concrete factor-construction use case.

## Cost Considerations

Daloopa is institutional-grade paid data. The free REST API tier (available after free account signup) has undocumented rate limits. Pipeline-scale use (caching fundamentals for 500+ tickers) almost certainly requires a paid subscription.

> ⚠ AI-inferred: Institutional data subscriptions of this type typically cost $10,000-$50,000/year for hedge fund use cases. Academic or startup tiers may exist but are not advertised.

This places any Daloopa integration in the same cost bucket as #150 Option A (point-in-time historical data): tag as `low-priority`, multi-week effort, do not pursue until there is a concrete factor-construction use case that justifies the spend. The FinRetrieval benchmark (500 questions, 0% answerable today) is a useful evaluation harness when the integration is ready to test.

## Sources

- [Issue #78](https://github.com/JohnGavin/historical/issues/78) — full tabulation of daloopa MCP tools, REST endpoints, Claude Code skills, data coverage, and initial gap analysis. Primary source for this wiki entry; issue body not reproduced here.
- [daloopa/investing GitHub](https://github.com/daloopa/investing) — referenced via issue; not fetched independently (issue tabulation treated as current as of 2026-05-01 access test).
- `packages/historicaldata/R/registry.R` — source for "what we have today" inventory (read 2026-05-16).
