# Historical Finance Data: Implementation Plan

## Architecture Decisions (Settled)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Pipeline orchestrator | **T language** | Polyglot R+Python, Nix-sandboxed, content-addressed caching. Template: `crypto_swarms` |
| R analysis layer | **targets + crew** | DAG inside T `rn` nodes. crew for parallel ticker fetching |
| Data query layer | **duckplyr** | Tidyverse syntax over DuckDB. Raw SQL only for complex ops |
| Package structure | **Single R package** (`historicaldata`) | Code-only, dataset registry. One install, all asset classes. Option 1. |
| Data distribution | **Hugging Face Datasets** | DuckDB `httpfs` predicate pushdown, cross-language, free, scalable |
| Distribution mirror | **GitHub Releases** via `piggyback` | Fallback / familiar |
| Storage format | **Parquet (zstd)** | Columnar, compressed, cross-language. Hive-partitioned locally, consolidated for distribution |
| Python access | **Same Parquet files** on HF | DuckDB or pandas/pyarrow. No separate Python build step |
| Adding new asset classes | **Registry entry + functions** | No new repo, no new package. Quarterly cadence expected |

## Data Sources (Ordered by Implementation Priority)

### Phase 1: Core (Month 1)

| Source | Language | R/Python package | Asset class | Priority |
|--------|----------|-----------------|-------------|----------|
| Yahoo Finance | Python | `yfinance` | US equities daily OHLCV | 1 |
| CoinGecko | R | `geckor` | Crypto daily (SOL, BTC, ETH, USDC, USDT) | 1 |
| CoinMarketCap | R | `crypto2` | Crypto bulk historical | 1 |
| FRED | R | `fredr` | Macro (S&P 500, VIX, yields, GDP) | 1 |
| Ken French | R | `frenchdata` | Fama-French factors | 1 |

### Phase 2: Verification + Depth (Month 2-3)

| Source | Language | R/Python package | Asset class | Priority |
|--------|----------|-----------------|-------------|----------|
| Tiingo | R | `riingo` | US equities (delisted stocks for survivorship bias) | 2 |
| Kaggle NASDAQ | Static | CSV download | Cross-reference verification dataset | 2 |
| Binance | Python | `ccxt` | Crypto minute-level, order book depth | 2 |
| Stooq | Static | CSV bulk | International indices | 2 |

### Phase 3: Expansion (Quarterly)

| Source | Language | R/Python package | Asset class | Priority |
|--------|----------|-----------------|-------------|----------|
| CryptoCompare | Python | `httr2` or `httpx` | Crypto social/blockchain metrics | 3 |
| EOD Historical | Python | `httpx` | International equities (70+ exchanges) | 3 |
| DefiLlama | Python | `httpx` | DeFi TVL, protocol revenue | 3 |
| Commodity futures | TBD | TBD | Commodities (new asset class) | 3 |

## Repository Structure

```
historical/                            # This directory — one git repo
├── PLAN.md                            # This file
├── prompt_historical.md               # Original brief
├── tproject.toml                      # T project manifest
├── flake.nix                          # Nix flake (R + Python + T)
├── flake.lock
├── src/
│   └── pipeline.t                     # T pipeline definition
├── scripts/
│   ├── fetch_equity.py                # yfinance bulk download
│   ├── fetch_crypto.py                # ccxt / geckor
│   ├── fetch_macro.R                  # fredr
│   ├── fetch_factors.R                # frenchdata
│   └── publish_hf.py                  # Upload consolidated Parquet to HF
├── _targets.R                         # R DAG: validate, clean, consolidate
├── R/                                 # Analysis functions for targets
│   ├── validate.R                     # pointblank checks
│   ├── clean.R                        # dedup, impute, adjust
│   ├── cross_reference.R             # multi-source verification
│   └── consolidate.R                 # Hive partitions → single Parquet per asset class
├── data/                              # Local pipeline artifacts (gitignored)
│   ├── raw/                           # Fetched data (append-only)
│   ├── clean/                         # Validated, deduped (Hive-partitioned)
│   └── dist/                          # Consolidated for upload to HF
├── packages/
│   └── historicaldata/                # R package (code-only, CRAN-submittable)
│       ├── DESCRIPTION
│       ├── NAMESPACE
│       ├── R/
│       │   ├── connect.R             # hd_connect() → DuckDB + httpfs
│       │   ├── query.R               # hd_ohlcv(), hd_macro(), hd_factors()
│       │   ├── registry.R            # Dataset URLs, schemas, versions
│       │   ├── cache.R               # hd_download(), hd_cache_path()
│       │   ├── equity.R              # hd_equity_ohlcv(), split/div adjustment helpers
│       │   ├── crypto.R              # hd_crypto_ohlcv(), depeg helpers
│       │   ├── macro.R               # hd_macro_series()
│       │   └── factors.R             # hd_factors_get()
│       ├── inst/extdata/
│       │   └── sample.parquet        # Tiny sample for tests (<1MB)
│       ├── tests/testthat/
│       ├── vignettes/
│       └── man/
├── python/                            # Optional Python companion
│   └── historicaldata/
│       ├── __init__.py
│       ├── connect.py                 # Same DuckDB httpfs pattern
│       ├── equity.py
│       └── crypto.py
├── tests/
│   └── testthat/                      # Pipeline-level tests
├── docs/
└── CHANGELOG.md
```

## T Pipeline Design

```
pipeline.t

  pyn: fetch_equity        # yfinance → data/raw/equity/*.parquet
  pyn: fetch_crypto        # ccxt → data/raw/crypto/*.parquet
  rn:  fetch_macro         # fredr → data/raw/macro/*.parquet
  rn:  fetch_factors       # frenchdata → data/raw/factors/*.parquet

  rn:  analysis            # targets DAG (inside this node):
  │    ├── tar: validate            # pointblank per source
  │    ├── tar: cross_reference     # multi-source price verification
  │    ├── tar: deduplicate         # prefer valued rows, latest download
  │    ├── tar: adjust              # splits, dividends, corporate actions
  │    ├── tar: impute              # LOCF, interpolation options
  │    ├── tar: consolidate_equity  # Hive → single Parquet
  │    ├── tar: consolidate_crypto  # Hive → single Parquet
  │    ├── tar: consolidate_macro   # Hive → single Parquet
  │    └── tar: consolidate_factors # Hive → single Parquet

  pyn: publish_hf          # Upload dist/*.parquet to HF dataset repo

  node: report             # Quarto: what changed, data quality summary
```

## R Package API (historicaldata)

```r
# --- Core query (zero-download via DuckDB httpfs) ---
hd_ohlcv("AAPL", from = "2024-01-01")
hd_ohlcv("SOL", from = "2024-01-01")
hd_macro("GDP", from = "2020-01-01")
hd_factors("FF3", from = "2020-01-01")

# --- Dataset discovery ---
hd_datasets()                      # List all registered datasets
hd_tickers("equity_daily")        # List tickers in a dataset
hd_schema("crypto_daily")         # Show columns + types

# --- Lazy query (duckplyr, no collect) ---
hd_lazy("equity_daily") |>
  filter(ticker == "AAPL", date >= "2024-01-01") |>
  mutate(ret = (close - lag(close)) / lag(close)) |>
  collect()

# --- Offline / bulk download ---
hd_download("equity_daily")       # Cache full dataset locally
hd_download()                     # Cache everything
hd_ohlcv("AAPL", local = TRUE)   # Query local cache

# --- Registry (adding new asset class = adding entry here) ---
# R/registry.R contains:
hd_registry <- function() {
  list(
    equity_daily = list(
      url = "https://huggingface.co/datasets/{user}/finance-data/resolve/main/equity_daily.parquet",
      schema = c("date", "open", "high", "low", "close", "adjusted", "volume", "ticker", "source"),
      frequency = "daily",
      description = "US equities daily OHLCV"
    ),
    crypto_daily = list(
      url = "https://huggingface.co/datasets/{user}/finance-data/resolve/main/crypto_daily.parquet",
      # ...
    )
    # Adding commodities = add an entry here. That's it.
  )
}
```

## Data Schema

```sql
-- Shared OHLCV schema (all asset classes)
CREATE TABLE ohlcv (
  date        DATE NOT NULL,
  open        DOUBLE,
  high        DOUBLE,
  low         DOUBLE,
  close       DOUBLE NOT NULL,
  adjusted    DOUBLE,            -- split/dividend adjusted (equities)
  volume      DOUBLE,            -- DOUBLE not BIGINT (crypto has fractional)
  ticker      VARCHAR NOT NULL,
  asset_class VARCHAR NOT NULL,  -- 'equity', 'crypto', 'commodity'
  exchange    VARCHAR,
  currency    VARCHAR DEFAULT 'USD',
  source      VARCHAR NOT NULL,  -- 'yahoo', 'coingecko', 'binance'
  updated_at  TIMESTAMP
);

-- Macro series (different shape)
CREATE TABLE macro (
  date        DATE NOT NULL,
  value       DOUBLE,
  series_id   VARCHAR NOT NULL,  -- 'SP500', 'VIXCLS', 'DGS10'
  frequency   VARCHAR,           -- 'daily', 'monthly', 'quarterly'
  source      VARCHAR DEFAULT 'fred'
);

-- Factor returns (different shape)
CREATE TABLE factors (
  date        DATE NOT NULL,
  factor_name VARCHAR NOT NULL,  -- 'Mkt-RF', 'SMB', 'HML', 'RMW', 'CMA', 'Mom'
  value       DOUBLE NOT NULL,
  dataset     VARCHAR NOT NULL,  -- 'FF3', 'FF5', 'Mom'
  frequency   VARCHAR            -- 'daily', 'monthly'
);
```

## Data Cleaning Pipeline (targets DAG detail)

### Deduplication
- Same (ticker, date) from multiple sources: prefer source with value > NULL
- Same source, multiple downloads: prefer latest `updated_at`
- Log conflicts where values differ >5% for review

### Cross-Reference Verification
- Compare closing prices from 2+ sources
- Flag discrepancies >1% tolerance
- Store verification result as metadata column

### Missing Data
- Option A: LOCF (last observation carried forward) — default
- Option B: Linear interpolation — for short gaps (<5 days)
- Option C: NA — preserve missingness, document why
- Store imputation method as metadata column

### Corporate Actions (equities)
- Raw prices: never modified after trading day
- Adjusted prices: recomputed when splits/dividends change history
- Store adjustment factor so users can verify

## Nix Environment

```nix
# flake.nix inputs
inputs = {
  nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-04-04";  # Pin date
  t-lang.url = "...";                                         # Match crypto_swarms
  flake-utils.url = "github:numtide/flake-utils";
};

# R packages
r-env: dplyr, arrow, duckdb, duckplyr, slider, pointblank,
       targets, crew, tidyquant, riingo, fredr, frenchdata,
       crypto2, geckor, piggyback, hfhub, contentid,
       testthat, cli, rlang

# Python packages
py-env: yfinance, ccxt, httpx, pandas, pyarrow, huggingface-hub, pytest
```

## DuckDB Sandbox Fix

The `HOME=/homeless-shelter` issue from crypto_swarms is solved by setting `HOME=$TMPDIR` in the T node shellHook:

```nix
shellHook = ''
  export HOME=$TMPDIR
  # ... plus R_LIBS_SITE rebuild from nix-nested-shell-isolation rule
'';
```

Feed this fix back to crypto_swarms.

## Prototype: Option F (AAPL + BTC, 2 sources each)

### Goal

Validate the full pipeline end-to-end with the smallest possible scope that exercises
both asset classes, both languages, cross-referencing, and the R package API.

**Two tickers, two asset classes, two sources each.**

### Prototype Data Sources

| Ticker | Asset class | Static source | API source | Overlap period |
|--------|-------------|--------------|------------|----------------|
| AAPL | Equity | Kaggle NASDAQ dataset (AAPL.csv, daily OHLCV) | `yfinance` via T `pyn` node | Full history of Kaggle file |
| BTC | Crypto | crypto_swarms CoinGecko backfill (already on disk) or Kaggle BTC dataset | `geckor::coin_history_range("bitcoin")` via T `rn` node | 1yr+ |

### Why AAPL

- 4:1 stock split on 2020-08-31 — tests split adjustment logic
- Dividends quarterly — tests dividend adjustment
- In Kaggle NASDAQ dataset — free, CC0
- Highly liquid — Yahoo data is reliable
- Everyone knows it — easy to spot anomalies by eye

### Why BTC

- No splits, no dividends — tests that crypto code path skips these
- High volatility — tests imputation edge cases (no trading halts but exchange gaps)
- Available in crypto_swarms backfill — zero extra download
- CoinGecko vs Kaggle/CMC prices differ by exchange weighting — genuine cross-ref test

### Pipeline Stages Exercised

| Stage | What it validates | Prototype exercises it? |
|-------|-------------------|------------------------|
| T `pyn` node | Python fetch in Nix sandbox | Yes — `yfinance` for AAPL |
| T `rn` node | R fetch in Nix sandbox | Yes — `geckor` for BTC |
| Static ingest | CSV/Parquet read + schema enforcement | Yes — Kaggle AAPL.csv + BTC backfill |
| Cross-reference | Multi-source price verification | Yes — AAPL: Kaggle vs Yahoo. BTC: backfill vs CoinGecko |
| Schema unification | Equity + crypto → same output schema | Yes — both go through `hd_ohlcv()` |
| Deduplication | Same (ticker, date) from 2 sources | Yes — overlapping date ranges |
| Corporate actions | Split/dividend adjustment | Yes — AAPL 2020 split |
| Missing data | Detect + impute gaps | Yes — weekends/holidays in equity, exchange gaps in crypto |
| pointblank validation | Schema/type/range checks | Yes — both datasets |
| Parquet consolidation | Hive → single file per asset class | Yes — 2 files (equity_daily.parquet, crypto_daily.parquet) |
| R package query | `hd_ohlcv()` returns tibble | Yes — both tickers |
| DuckDB httpfs | Zero-download query over HTTPS | Yes — upload to HF, read back |
| duckplyr lazy query | `hd_lazy() |> filter() |> collect()` | Yes |
| Python access | Same Parquet, DuckDB from Python | Yes — verify with 3-line Python script |

### Prototype File Structure

```
historical/
├── PLAN.md
├── prompt_historical.md
├── tproject.toml
├── flake.nix
├── src/
│   └── pipeline.t
├── scripts/
│   ├── fetch_equity.py               # yfinance: download AAPL daily OHLCV
│   └── publish_hf.py                 # Upload dist/*.parquet to HF (stub)
├── _targets.R                         # R DAG: validate, clean, cross-ref, consolidate
├── R/
│   ├── validate.R                     # pointblank checks
│   ├── clean.R                        # dedup, adjust, impute
│   ├── cross_reference.R             # compare sources, flag discrepancies
│   └── consolidate.R                 # Hive → single Parquet
├── data/
│   ├── raw/                           # gitignored, append-only
│   │   ├── kaggle_aapl.csv           # Manual download from Kaggle
│   │   ├── btc_backfill.parquet      # Copy from crypto_swarms or Kaggle
│   │   ├── yfinance_aapl.parquet     # Written by fetch_equity.py
│   │   └── geckor_btc.parquet        # Written by targets
│   ├── clean/                         # Validated, deduped
│   │   ├── ticker=AAPL/2020.parquet
│   │   └── ticker=BTC/2024.parquet
│   └── dist/                          # Consolidated for HF
│       ├── equity_daily.parquet
│       └── crypto_daily.parquet
├── packages/
│   └── historicaldata/                # R package skeleton
│       ├── DESCRIPTION
│       ├── NAMESPACE
│       ├── R/
│       │   ├── connect.R
│       │   ├── query.R
│       │   ├── registry.R
│       │   └── cache.R
│       ├── inst/extdata/
│       │   └── sample.parquet
│       └── tests/testthat/
│           ├── test-connect.R
│           └── test-query.R
├── tests/
│   └── testthat/
│       ├── test-validate.R
│       ├── test-clean.R
│       └── test-cross-reference.R
└── docs/
    └── prototype-results.qmd          # What matched, what didn't, lessons
```

### Prototype T Pipeline

```
pipeline.t

  # --- Fetch ---
  pyn: fetch_equity                    # yfinance AAPL → data/raw/yfinance_aapl.parquet
  rn:  fetch_crypto                    # geckor BTC → data/raw/geckor_btc.parquet
  rn:  ingest_static                   # Read Kaggle CSVs → standardised parquet

  # --- Analysis (targets DAG) ---
  rn:  analysis
  │    ├── tar: raw_equity_api         # Read yfinance parquet
  │    ├── tar: raw_equity_static      # Read Kaggle AAPL CSV
  │    ├── tar: raw_crypto_api         # Read geckor parquet
  │    ├── tar: raw_crypto_static      # Read BTC backfill
  │    ├── tar: validate_equity        # pointblank: schema, types, ranges
  │    ├── tar: validate_crypto        # pointblank: schema, types, ranges
  │    ├── tar: xref_equity            # Compare AAPL close: Kaggle vs Yahoo
  │    ├── tar: xref_crypto            # Compare BTC close: backfill vs CoinGecko
  │    ├── tar: clean_equity           # Dedup, adjust splits/dividends, impute
  │    ├── tar: clean_crypto           # Dedup, impute
  │    ├── tar: consolidate_equity     # → dist/equity_daily.parquet
  │    └── tar: consolidate_crypto     # → dist/crypto_daily.parquet

  # --- Publish ---
  pyn: publish_hf                      # Upload dist/*.parquet to HF (stub initially)

  # --- Report ---
  node: report                         # Quarto: cross-ref results, data quality
```

### Success Criteria

| Test | Pass condition |
|------|---------------|
| AAPL cross-ref | Kaggle vs Yahoo adjusted close within 0.1% for >99% of overlapping dates |
| AAPL split handling | 2020-08-31 split correctly reflected in adjusted prices from both sources |
| BTC cross-ref | Backfill vs CoinGecko close within 1% for >95% of overlapping dates |
| Schema unification | `hd_ohlcv("AAPL")` and `hd_ohlcv("BTC")` return identical column names |
| DuckDB httpfs | Query HF-hosted Parquet with predicate pushdown (verify via EXPLAIN) |
| Python access | `duckdb.connect().execute("SELECT * FROM read_parquet('https://hf.co/...') WHERE ticker='AAPL'")` returns data |
| Pipeline reproducibility | `t run` produces identical output on second run (content-addressed cache hit) |
| R package installs | `pak::local_install("packages/historicaldata")` succeeds |
| Lazy query | `hd_lazy("equity_daily") |> filter(ticker == "AAPL") |> collect()` returns tibble |

### Prototype Lessons to Capture

After the prototype, document in `docs/prototype-results.qmd`:

1. **Cross-reference discrepancies** — How much do sources actually differ? Is 0.1%/1% realistic?
2. **Split/dividend handling** — Does Yahoo's adjusted price match manual adjustment from Kaggle raw?
3. **DuckDB httpfs latency** — Is zero-download query fast enough for interactive use?
4. **T sandbox friction** — Did `HOME=$TMPDIR` fix DuckDB? Any other sandbox issues?
5. **Schema decisions** — Did the unified schema work or does equity need columns crypto doesn't?
6. **Parquet sizing** — How big are the consolidated files? Row group size tuning needed?
7. **What to change in PLAN.md** — Update plan based on reality, not assumptions

### Prototype Timeline

| Step | Est. | Deliverable |
|------|------|-------------|
| P1 | 2h | Scaffold: flake.nix, tproject.toml, pipeline.t skeleton (copy from crypto_swarms, strip) |
| P2 | 2h | fetch_equity.py: yfinance AAPL download + Kaggle AAPL.csv ingest |
| P3 | 2h | fetch_crypto: geckor BTC + BTC backfill ingest |
| P4 | 3h | R targets DAG: validate, cross-reference, clean, consolidate |
| P5 | 2h | R package skeleton: registry, connect, query, cache for 2 datasets |
| P6 | 1h | Upload to HF, test httpfs, test Python access |
| P7 | 1h | Quarto report: prototype-results.qmd |
| P8 | 1h | Update PLAN.md with lessons learned |
| **Total** | **~14h** | **Full pipeline, 2 tickers, 4 sources, working R package** |

## Schedule

| Phase | Timeline | Deliverable |
|-------|----------|-------------|
| **P** | **Week 0-1** | **Prototype: AAPL + BTC, 4 sources, full pipeline (see above)** |
| 1a | Week 1 | Scaffold: flake.nix, tproject.toml, pipeline.t, _targets.R, package skeleton |
| 1b | Week 2 | fetch_equity.py (yfinance, 50 tickers proof of concept) |
| 1c | Week 2 | fetch_crypto (geckor/crypto2, 16 tokens from crypto_swarms) |
| 1d | Week 3 | fetch_macro.R (fredr, 20 key series) + fetch_factors.R |
| 1e | Week 3 | R targets DAG: validate, clean, consolidate |
| 1f | Week 4 | R package: registry, connect, query, cache |
| 1g | Week 4 | Publish to HF, test httpfs queries, cross-reference verification |
| 2 | Month 2 | Scale to 1000 tickers, add Tiingo (delisted), Kaggle verification |
| 3 | Month 3 | Binance minute-level crypto, Stooq international indices |
| 4+ | Quarterly | New asset class (commodities, futures, etc.) |

## When to Revisit Single-Package Decision

Split into multiple packages only if:
- Package exceeds ~50 exported functions
- Different datasets need incompatible dependencies
- CRAN reviewers object to scope
- Different teams need independent release authority

None expected in Year 1.
