# Download dataset(s) to local cache

Downloads Parquet files from HF for offline use.

## Usage

``` r
hd_download(dataset = NULL, force = FALSE)
```

## Arguments

- dataset:

  Dataset name(s). If NULL, downloads all registered datasets.

- force:

  If TRUE, re-download even if cached file exists.

## Value

Invisibly, paths to cached files.

## See also

Other infrastructure:
[`hd_cache_clear()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_clear.md),
[`hd_cache_path()`](https://johngavin.github.io/historical/pkg/reference/hd_cache_path.md),
[`hd_connect()`](https://johngavin.github.io/historical/pkg/reference/hd_connect.md),
[`hd_connect_local()`](https://johngavin.github.io/historical/pkg/reference/hd_connect_local.md)
