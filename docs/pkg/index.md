Code-only R package providing access to historical OHLCV data for
equities, crypto, macro series, and factor returns. Data is stored as
Parquet on Hugging Face Datasets and queried via DuckDB httpfs with
predicate pushdown. No data is bundled — the package ships access
functions and a dataset registry.
