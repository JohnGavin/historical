# Create a DuckDB connection for remote Parquet access

Returns a DBI connection to an ephemeral DuckDB instance. DuckDB 0.10+
supports `hf://datasets/...` URLs natively — no httpfs needed. httpfs is
loaded as a fallback for non-HF HTTPS URLs.

## Usage

``` r
hd_connect()
```

## Value

DBI connection object

## See also

Other infrastructure:
[`hd_cache_clear()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_clear.md),
[`hd_cache_path()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_path.md),
[`hd_connect_local()`](https://johngavin.github.io/historical/pkg/reference/hd_connect_local.md),
[`hd_download()`](https://johngavin.github.io/historical/pkg/reference/hd_download.md)
