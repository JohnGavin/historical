# OLMAR Phase 4 — Scoping: Point-in-Time S&P 600 Small-Cap Universe

**Status:** SCOPING ONLY — no backtests run. Decision required from user
before any code that produces survivorship-corrected numbers is wired in.

**Issue refs:** [#278](https://github.com/JohnGavin/historical/issues/278)
(OLMAR P4), [#150](https://github.com/JohnGavin/historical/issues/150)
(survivorship bias), [#200](https://github.com/JohnGavin/historical/issues/200)
(OLMAR research log).

**Hard blocker recap.** The existing `equity_daily` universe is
currently-listed-only — zero delistings in 56 years, all 8 known-delisted
benchmark tickers absent (LEH, BSC, ENRN, WCOM, WAMU, TYC, MER, old GM).
A survivorship-biased S&P 600 run on this dataset is explicitly forbidden
in [#278](https://github.com/JohnGavin/historical/issues/278) because
small-caps delist far more often than large-caps. We need a PIT universe
*before* running any OLMAR P4 numbers — that is the entire reason this
scoping pass exists.

---

## A. Data-source comparison

The two columns that matter for OLMAR P4 are **PIT membership** (the
ticker set as of each historical date) and **delisting records** (a
final price / delisting date for each ticker that left the index). Both
are required — having either alone leaves a measurable bias.

| # | Source | License / cost | Coverage | API / format | PIT membership? | Delisting records? | Suitable for OLMAR P4? |
|---|--------|----------------|----------|--------------|----------------|---------------------|------------------------|
| 1 | **CRSP** (via WRDS) | Academic institutional only; ~free with university affiliation; commercial license very expensive (>$10k/yr) | Full US, 1925→ | WRDS SQL, parquet via PG, R `wrds-r-package` | YES (CRSP MSP1500 / Compustat constituents history) | YES (CRSP delist code + delist price) | **Best-in-class but gated by WRDS access.** Needs user confirmation re: academic affiliation. |
| 2 | **Sharadar SF1 + SEP + TICKERS** (Nasdaq Data Link) | Retail: ~$50/mo each dataset; bundle pricing not on public page — **needs user confirmation** | US listed + delisted, 1998→ (SF1 from 1999) | Nasdaq Data Link REST / R `Quandl` pkg / Python `nasdaqdatalink` | YES — `SF1.SHARADAR/TICKERS` carries `firstpricedate`, `lastpricedate`, and SF1 has historical index membership flags | YES — `lastpricedate` + final SEP price | **Yes — common retail quant choice, decent QC, but $50–200/mo and needs verification of S&P 600 constituent history specifically.** |
| 3 | **Norgate Data** | Retail: ~$30/mo Platinum (per online forums; **needs user confirmation** — pricing page returned 404) | US, Australian, Canadian; 1990→ | Proprietary native client + Python/R wrappers | YES — "survivorship-bias-free" is their headline marketing claim; daily index membership flags including S&P 600 | YES — delisting prices + reasons | **Very common with retail quants exactly because of PIT S&P 600 / 400 / 500.** Strong recommendation pending pricing confirmation. |
| 4 | **EODHD** (eodhistoricaldata.com) | $19.99/mo "All World" (confirmed via WebFetch 2026-06-04); $99.99/mo "All-In-One" with fundamentals | US + global, varies by tier | REST + Python/R wrappers | **POSSIBLY** — they advertise an "Indices Historical Constituents API" via S&P Global partnership but coverage of S&P 600 specifically needs verification | **YES** — explicitly "Delisted Data" on every paid plan | **Cheapest paid option that has both features; needs verification of S&P 600 constituent history.** |
| 5 | **OpenBB Platform** / **yfinance** (free) | Free | Partial — yfinance has SOME delisted symbols; OpenBB wraps multiple providers | Python; R via reticulate or HTTP | NO native PIT index membership | PARTIAL — yfinance keeps prices for some delisted symbols but quality is uneven; many are gone | **No on its own.** Could supply pricing for tickers identified via another PIT-membership source, but cannot supply the membership list itself. |
| 6 | **Wayback Machine + Wikipedia revisions** | Free | Wikipedia S&P 600 component list back to ~2005; Wayback snapshots of S&P DJI fact-sheets back further | Manual + Python `internetarchive` / `requests` | YES (at snapshot granularity — month/quarter/year) | NO — only gives the membership snapshot; need separate price source | **Free PIT membership source; pair with another source for prices.** This is the cheapest viable starting point. |
| 7 | **Tiingo** | $10/mo "Power" / $30/mo "Commercial Power" | US listed + delisted via "End-of-Day Prices"; 1962→ | REST + R `riingo` pkg | NO — does not publish index constituent history | YES for prices of delisted tickers | **No on its own** — same constraint as yfinance: prices for delisted tickers but no membership history. |
| 8 | **Polygon.io** | $29/mo "Starter" / $79+/mo with corporate-actions | US, intraday + EOD; 2003→ | REST + websocket; R via httr2 | NO native PIT index membership | YES (delisted reference data on paid tiers) | **No on its own** — same constraint. |

### Sources requiring user confirmation

Before committing to any paid path, the user should confirm directly:

1. **CRSP/WRDS** — does the user have current WRDS access (academic affiliation, institutional login)?
2. **Sharadar SF1 bundle pricing** — Nasdaq Data Link has moved pricing behind sign-in; retail rate may have changed since 2024
3. **Norgate Platinum monthly price** — pricing page returned 404 during scoping; commonly quoted at ~$30/mo on retail-quant forums (Elite Trader, Wilmott)
4. **EODHD S&P 600 historical constituents** — `Indices Historical Constituents API` is advertised but S&P 600 specifically needs confirming on the API tier we'd subscribe to

---

## B. Recommendation

### Primary: **Norgate Data Platinum** (paid, ~$30/mo) — if pricing confirms

Rationale:
- Survivorship-bias-free is the **headline product**, not a side feature
- Daily index membership flags including S&P 400 / 500 / **600** — exactly the universe #278 calls for
- Strong R/Python integration; widely used by retail quant blogs (PaperToProfit, the OLMAR reference itself almost certainly uses something like this)
- Verified delisting prices + delisting reasons
- Cost is bounded and predictable

**Time to first survivorship-corrected OLMAR P4 result if path A chosen:** ~3-5 days
(1 day data download + ingest; 1 day target wiring; 1 day code review; 1-2 days
QA + research-log lineage).

### Fallback: **Wayback Machine + Wikipedia historical S&P 600 lists**
(free) **paired with EODHD All-World ($20/mo) for delisted-ticker prices**

Rationale:
- Eliminates the chicken-and-egg problem: Wayback gives us PIT membership lists at low resolution (yearly snapshots, optionally quarterly); EODHD gives us prices for any ticker including delisted ones
- Total cost ≤ $20/mo
- Gets us SOMETHING runnable without committing to a paid PIT provider
- Acceptable for a Phase 4 "is the edge real at all in small-caps?" sanity check, NOT acceptable for a publishable result

**What we lose by going free/proxy:**
1. **Snapshot granularity** — Wayback snapshots are roughly yearly; real S&P 600 turnover is ~20% per year (small-caps churn faster than the S&P 500's ~5%). A yearly snapshot will mis-classify membership for ~10% of stock-months on average, with the bias depending on whether you snap at year-start or year-end.
2. **Pre-2005 coverage** — Wikipedia's S&P 600 list only really exists from ~2005 onwards. The S&P 600 itself was launched in 1994. We lose 11 years.
3. **Delisting reason / liquidation price quality** — EODHD has delisting flags but the data depth varies; Norgate/Sharadar/CRSP have explicit liquidation prices for bankruptcies. The difference matters when a delisted ticker's final price is e.g. $0.02 (worthless) vs the last quoted close from 30 days earlier ($3.50) — a 175× ratio difference.
4. **No direct path to publishable Sharpe numbers** — anything from this stack stays in "exploratory, biased" territory per [#150](https://github.com/JohnGavin/historical/issues/150) Option D.

**Time to first result if path B chosen:** ~2-4 days
(1 day Wayback scrape + parse; 1 day EODHD price fetch + delisting reconciliation;
1 day target wiring; 1 day QA showing it works on the existing OLMAR plan).

### Decision tree

```
  Does the user have current WRDS / CRSP access?
    │
    ├── YES ──> Path 0: CRSP (best-in-class, gated)
    │
    └── NO ──> Is the user willing to spend ~$30/mo on a paid provider?
              │
              ├── YES ──> Path A: Norgate Platinum (recommended primary)
              │           ── confirm pricing first; if higher than budget,
              │              fall through to EODHD path
              │
              └── NO  ──> Path B: Wayback + EODHD ($20/mo)
                          ── flag as exploratory-only per #150 Option D
                          ── must add survivorship-biased=FALSE flag scaffold
                             AND keep documenting bias direction
```

---

## C. Integration plan (for the recommended path)

### Where the data lives

Mirror the existing `equity_daily` HF parquet pattern in `packages/historicaldata/R/hd_datasets()` — add a new dataset key
`equity_universe_pit` (or similar). Schema:

| Column | Type | Description |
|--------|------|-------------|
| `ticker` | character | Ticker symbol as of the listed date |
| `date` | Date | Trading day |
| `in_universe_pit` | logical | TRUE if ticker was an index constituent on that date |
| `index_name` | character | "SP600" / "SP500" / "SP400" |
| `delisting_date` | Date (nullable) | Date the ticker stopped trading (or left the index) |
| `delisting_reason` | character (nullable) | "bankruptcy" / "acquired" / "merged" / "index_removed" / "other" |
| `delisting_price` | double (nullable) | Final traded price; `0` for liquidations to zero |

This is a SEPARATE table from `equity_daily` — keeps the existing pipeline
unbroken and lets `stk_universe_pit` be added as a new target without
disturbing the survivorship-biased baseline (we WANT to keep both for
side-by-side comparison per [#150](https://github.com/JohnGavin/historical/issues/150) Option B).

### Files to change

Read the current state first (no edits in this scoping pass):

1. **`packages/historicaldata/R/groups.R`** — currently has curated editorial groups
   (FAANG, Mag 7, sectors, ETFs) but NO S&P 500 or S&P 600 lists. Action: add a new
   helper `hd_sp600_pit(as_of_date)` returning the constituent ticker vector at a
   given historical date. NOT a `hd_ticker_groups()` row — the PIT universe is a
   function of date, not a static list.

2. **`scripts/fetch_equity.py`** — currently has `load_sp500_tickers()` and a
   `STOXX600_MAJORS` static list. Action: add `load_sp600_pit(as_of_date)` which:
   - Reads from the chosen PIT source (Norgate / Wayback+EODHD)
   - Writes one parquet file per historical date or a single long-format parquet
   - Logs to the existing `download_log.parquet` telemetry

3. **`R/plan_stock_backtest.R`** — currently has `stk_universe` (the
   survivorship-biased target). Action: add a parallel `stk_universe_pit` target
   that filters by `in_universe_pit == TRUE` for each calendar date. **Do NOT
   replace `stk_universe`** — `#150` Option B requires keeping both for bias
   quantification.

4. **`R/plan_olmar.R`** — currently has `olmar_params$tickers` as a hardcoded
   30-ticker large-cap + ETF list. Action: add a new params target
   `olmar_params_sp600_pit` that points at `stk_universe_pit` filtered to
   `index_name == "SP600"` and `date == data_date` (per-day membership). The
   `olmar_prices` target needs a parallel `olmar_prices_sp600_pit` that gets
   prices for each ticker only over its in-universe dates (zero-pad before
   listing and after delisting).

### `stk_universe_pit` vs new parameter on `stk_universe`?

**Recommendation: new parallel target, not a parameter.** Reasons:
- `stk_universe` is consumed by ~10+ downstream targets (`stk_monthly`,
  `stk_daily_ret`, `stk_max_*`, `stk_drif_*`, mean-reversion inputs, etc.).
  Adding a `pit = TRUE/FALSE` parameter forces every downstream consumer to
  decide what to pass. Tar's invalidation graph becomes harder to reason
  about.
- A parallel `stk_universe_pit` lets us produce side-by-side leaderboard
  rows: "Stock MAX on `stk_universe`" vs "Stock MAX on `stk_universe_pit`"
  with both visible. This is what #150 Option B asks for.
- The two universes will diverge in tickers AND dates — every metric that
  reads `stk_universe` (turnover, ADV cap, n_stocks/month) is computed
  separately on the PIT path. Parallel targets keep the dependency graph
  honest.

A `pit = TRUE` parameter MAY make sense later as a *single source of truth*
once the PIT path is stable and we're ready to deprecate the biased version,
but Phase 4 needs both visible.

---

## D. Cost-realism check

The author's claim is **106% CAGR at 0.2× leverage** on S&P 600 small-caps.
OLMAR-1 turnover is **68× annual** (from #278; observed in our large-cap
run). Combined with realistic small-cap costs, what does the gross return
need to be to net 106%?

**Small-cap spread + commission assumption.** Per `backtesting-assumptions`
rule, small-cap (sub-$2B market cap) bid-ask spreads are typically 15–25 bps
one-way. Our current OLMAR run uses 10 bps. For an honest small-cap variant
we should use at least 20 bps one-way (40 bps round-trip), arguably 30 bps
including market impact at non-trivial size.

**Cost arithmetic at 0.2× leverage:**

| Assumption | Value | Annual cost drag |
|------------|-------|------------------|
| Turnover (one-way, annual) | 68× | — |
| Per-trade cost (one-way) | 0.10% (current default) | 68 × 0.10% = **6.8%/yr** |
| Per-trade cost (one-way, small-cap-realistic) | 0.20% | 68 × 0.20% = **13.6%/yr** |
| Per-trade cost (one-way, small-cap + impact) | 0.30% | 68 × 0.30% = **20.4%/yr** |

At 0.2× leverage, the strategy's gross return must exceed the cost drag
PLUS the desired net return.

**Author's 106% net at 0.2× leverage, with the author's 10 bps assumption:**

```
gross  = net + cost_drag
       = 106% + 6.8%
       = 112.8% gross at 0.2× leverage
```

Implied 1× gross ≈ 564%/yr. This is **extraordinarily high** even for a
strategy with documented small-cap mean-reversion edge. The published OLMAR
literature (Li & Hoi 2012, *MLJ*) reports cumulative wealth of 10× to 100×
over 3-5 year periods on similar universes, which is more like 100–300%
CAGR on the unlevered backbone — but those are gross numbers on
synthetic/illiquid data without realistic costs.

**Our breakeven check with realistic small-cap costs:**

```
gross required to net 106% at 0.2× leverage,
  with 20 bps one-way:    106% + 13.6% = 119.6% gross
  with 30 bps one-way:    106% + 20.4% = 126.4% gross
```

Implied 1× gross ≈ 600-630%/yr. Either:
1. The author is using 10 bps which is too low for small-caps (likely)
2. The author is excluding market impact at non-trivial AUM (likely)
3. The strategy genuinely has that much gross edge in the bottom-cap
   bucket (possible but extraordinary)
4. The backtest is survivorship-biased (the very thing #278 is trying to
   correct — and small-caps are the most affected bucket per #150)

**Conclusion.** Before we even get to the data-sourcing question, the
cost-realism arithmetic suggests we should:

- Default the `cost_bps` parameter in any `olmar_params_sp600_pit` target
  to **20 bps** not 10 bps
- Add a **second variant** at **30 bps** to show what mid-cap-realistic
  costs do to the result
- Report the author's 10 bps version as a "for comparison only" row, NOT
  as the headline result
- Even a survivorship-corrected, properly-costed result may not show the
  106% claim — that may be the actual finding of Phase 4: **the edge is
  smaller than claimed because of cost realism, not because of survivorship
  bias**. Both contributions need disentangling.

---

## E. Acceptance gate before any code

Before any `tar_make()` runs that would generate `stk_universe_pit`-based
numbers — and before any OLMAR P4 results land on the leaderboard or in a
vignette — the following must ALL be true:

1. **PIT data source chosen and licensed.** User has explicitly picked one
   of the paths above (CRSP / Norgate / Wayback+EODHD), confirmed pricing,
   and (if paid) has the credentials in `.Renviron` per the
   `credential-management` rule.

2. **`survivorship_biased = FALSE` flag** is added to the OLMAR P4
   metrics target (`olmar_metrics_sp600_pit`) — mirroring the pattern
   `stk_max_metrics` already uses for the bias-known case
   (`survivorship_biased = TRUE` is currently set on `stk_max_metrics`,
   `stk_drif_metrics`, `stk_max_hrp_comparison`).

3. **Known-delisted-ticker presence test** passes: at least one of LEH
   (Lehman, 2008), BSC (Bear Stearns, 2008), ENRN (Enron, 2001), WCOM
   (WorldCom, 2002) is present in the PIT universe at its actual listing
   dates (LEH and BSC were in S&P 500 not S&P 600 — but if we adopt the
   same data source for any S&P-X PIT universe, the test should pass for
   the appropriate index). For small-cap-specific delisted-ticker
   verification, source needs to surface at least 3 known S&P 600 leavers
   from a known year (e.g. 2008 small-cap financials, 2020 energy
   bankruptcies).

4. **Cost-bps default is at least 20 bps**, with a 30 bps sensitivity
   variant present in the metrics output. The 10 bps "comparison-with-
   author" row is OK but cannot be the headline.

5. **Research-log lineage** for the S&P 600 variant has a NEW
   `hyp_id` / `impl_id` / `res_id` chain (per
   [#278](https://github.com/JohnGavin/historical/issues/278) requirement
   that the two universes be comparable in the DB), AND a NEW
   `critiques` row with `defect_class = "survivorship"` documenting that
   the PIT-corrected variant fixes the bias the original large-cap run
   was already free of (it had no small-caps at all).

6. **Bias quantification** (per [#150](https://github.com/JohnGavin/historical/issues/150)
   Option B) — the OLMAR P4 metrics target produces BOTH:
   - `olmar_metrics_sp600_biased` (using `stk_universe` style: no PIT filter, but restricted to top-N small-caps by current market cap as an approximation)
   - `olmar_metrics_sp600_pit` (using the new PIT data)
   
   The difference between the two columns IS the survivorship-bias
   estimate for OLMAR on the small-cap universe — a contribution to
   [#150](https://github.com/JohnGavin/historical/issues/150) Option B's
   bias-quantification requirement.

7. **No production deployment** of OLMAR P4 metrics to leaderboard /
   vignette until the above are green. Stays in `explorations/` or as a
   feature-flagged target until quality gate passes.

---

## What we do NOT do as part of this scoping pass

- Do not modify `_targets.R`, `default.nix`, `default.R`, `DESCRIPTION`
- Do not run `tar_make()` on anything
- Do not commit credentials or test API keys
- Do not write a paid API wrapper before the user has chosen a source
- Do not produce any numbers that look like OLMAR P4 results without the
  acceptance gate cleared

---

## Next concrete step

The user reviews this document and picks ONE primary path. The
[follow-up checklist](olmar-phase4-scoping-checklist.md) then breaks the
chosen path into ≤ 1 hour tasks that can be dispatched separately.
