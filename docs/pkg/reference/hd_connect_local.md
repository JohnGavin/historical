# Create a DuckDB connection over local cached Parquet files

Create a DuckDB connection over local cached Parquet files

## Usage

``` r
hd_connect_local(cache_dir = hd_cache_path())
```

## Arguments

- cache_dir:

  Path to local cache directory

## Value

DBI connection with views registered

## See also

Other infrastructure:
[`hd_cache_clear()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_clear.md),
[`hd_cache_path()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_path.md),
[`hd_connect()`](https://johngavin.github.io/historical/pkg/reference/hd_connect.md),
[`hd_download()`](https://johngavin.github.io/historical/pkg/reference/hd_download.md)
