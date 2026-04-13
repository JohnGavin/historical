# Package index

## Data Access

Fetch OHLCV, macro, and factor data from HF-hosted Parquet

- [`hd_ohlcv()`](https://johngavin.github.io/historical/pkg/reference/hd_ohlcv.md)
  : Query OHLCV data for one or more tickers
- [`hd_macro()`](https://johngavin.github.io/historical/pkg/reference/hd_macro.md)
  : Query FRED macro series
- [`hd_factors()`](https://johngavin.github.io/historical/pkg/reference/hd_factors.md)
  : Query Fama-French factor returns
- [`hd_lazy()`](https://johngavin.github.io/historical/pkg/reference/hd_lazy.md)
  : Lazy duckplyr query over a dataset

## Discovery

Search, explore, and summarise available datasets and tickers

- [`hd_search()`](https://johngavin.github.io/historical/pkg/reference/hd_search.md)
  : Search tickers by pattern across all datasets
- [`hd_summary()`](https://johngavin.github.io/historical/pkg/reference/hd_summary.md)
  : Summary of all datasets
- [`hd_exchanges()`](https://johngavin.github.io/historical/pkg/reference/hd_exchanges.md)
  : List all exchanges
- [`hd_tickers()`](https://johngavin.github.io/historical/pkg/reference/hd_tickers.md)
  : List available tickers in a dataset
- [`hd_macro_series()`](https://johngavin.github.io/historical/pkg/reference/hd_macro_series.md)
  : List available macro series
- [`hd_ticker_info()`](https://johngavin.github.io/historical/pkg/reference/hd_ticker_info.md)
  : Full metadata for one ticker
- [`hd_ticker_meta()`](https://johngavin.github.io/historical/pkg/reference/hd_ticker_meta.md)
  : Compact metadata table for a vector of tickers
- [`hd_fred_meta()`](https://johngavin.github.io/historical/pkg/reference/hd_fred_meta.md)
  : FRED series metadata (frequency, units)
- [`hd_datasets()`](https://johngavin.github.io/historical/pkg/reference/hd_datasets.md)
  : Dataset registry

## Curated Groups & Ranking

Pre-defined ticker groups and ranked ticker lists

- [`hd_ticker_groups()`](https://johngavin.github.io/historical/pkg/reference/hd_ticker_groups.md)
  : List all curated ticker groups
- [`hd_group()`](https://johngavin.github.io/historical/pkg/reference/hd_group.md)
  : Get tickers for a named group
- [`hd_top_by()`](https://johngavin.github.io/historical/pkg/reference/hd_top_by.md)
  : Top N tickers by a metadata metric
- [`hd_most_volatile()`](https://johngavin.github.io/historical/pkg/reference/hd_most_volatile.md)
  : Most volatile tickers by recent realised volatility

## Quality & Audit

Data quality checks and Point-in-Time amendment tracking

- [`hd_jumps()`](https://johngavin.github.io/historical/pkg/reference/hd_jumps.md)
  : Detect price jumps across all tickers in a dataset
- [`hd_quality()`](https://johngavin.github.io/historical/pkg/reference/hd_quality.md)
  : Summary of data quality per ticker
- [`hd_amendments()`](https://johngavin.github.io/historical/pkg/reference/hd_amendments.md)
  : Get price data amendments (Point-in-Time tracking)
- [`hd_metadata_amendments()`](https://johngavin.github.io/historical/pkg/reference/hd_metadata_amendments.md)
  : Get metadata amendments (Point-in-Time tracking)

## Infrastructure

DuckDB connections, caching, and downloads

- [`hd_connect()`](https://johngavin.github.io/historical/pkg/reference/hd_connect.md)
  : Create a DuckDB connection for remote Parquet access
- [`hd_connect_local()`](https://johngavin.github.io/historical/pkg/reference/hd_connect_local.md)
  : Create a DuckDB connection over local cached Parquet files
- [`hd_download()`](https://johngavin.github.io/historical/pkg/reference/hd_download.md)
  : Download dataset(s) to local cache
- [`hd_cache_path()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_path.md)
  : Get the local cache directory path
- [`hd_cache_clear()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_clear.md)
  : Clear the local cache

## Visualisation

Plot theme and colour palette for dark backgrounds

- [`hd_theme()`](https://johngavin.github.io/historical/pkg/reference/hd_theme.md)
  : Standard plot theme for historicaldata visualisations
- [`hd_palette()`](https://johngavin.github.io/historical/pkg/reference/hd_palette.md)
  : High-contrast colour palette for dark backgrounds
