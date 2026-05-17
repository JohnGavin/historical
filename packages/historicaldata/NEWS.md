# historicaldata 0.1.1

* `hd_ohlcv()` now correctly handles mixed-dataset batches (e.g.
  `c("AAPL", "BTC")`) by detecting each ticker's dataset, querying each
  parquet separately, and binding the results. Previously, only the first
  ticker's dataset was queried — non-matching tickers were silently dropped.
  When the batch spans datasets, the result is always materialised; pass
  an explicit `dataset = "equity_daily"` (or similar) to force single-dataset
  routing and preserve lazy frames.
