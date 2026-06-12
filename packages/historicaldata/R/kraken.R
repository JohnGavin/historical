# Kraken OHLCVT query helper (#436 Phase B)
#
# Reads the kraken_ohlcvt dataset (hourly + daily bars for 19 pairs:
# 6 crypto majors, 12 spot FX pairs, PAXG gold) from the HF parquet
# registered in hd_datasets(). Produced by scripts/fetch_kraken_ohlcvt.R
# from Kraken's quarterly OHLCVT archive.

#' Query Kraken OHLCVT bars (crypto majors, spot FX, PAXG gold)
#'
#' Returns hourly (60-min) or daily (1440-min) OHLCVT bars from the
#' `kraken_ohlcvt` dataset. See `hd_datasets()$kraken_ohlcvt$description`
#' for the pair universe and venue caveats (bars exist only where trades
#' occurred; FX volume is retail crypto-exchange flow, not interbank).
#'
#' @param ticker Character vector of tickers to filter (e.g. `"SOL"`,
#'   `c("EURUSD", "GBPUSD")`). `NULL` (default) returns all pairs.
#' @param interval_min Bar interval in minutes: `60L` (hourly, default)
#'   or `1440L` (daily).
#' @param from,to Optional date bounds (anything `as.POSIXct()` accepts;
#'   inclusive). Typed literals are injected per the #453 discipline —
#'   the parquet's `time` column is TIMESTAMP.
#' @param local If `TRUE`, read `kraken_ohlcvt.parquet` from the local
#'   cache dir (`hd_cache_path()`) instead of the HF remote.
#' @param collect If `TRUE` (default), materialise to a tibble; if
#'   `FALSE`, return the lazy duckplyr frame.
#'
#' @return Tibble (or lazy frame) with columns: `ticker`, `pair`,
#'   `interval_min`, `time` (POSIXct UTC), `open`, `high`, `low`,
#'   `close`, `volume`, `trades`.
#' @section Point-in-time guard:
#'   Passing `to > Sys.Date()` raises a classed error (`"hd_future_date"`),
#'   matching `hd_ohlcv()`.
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_kraken_ohlcvt("SOL", from = "2021-07-01", to = "2021-12-31")
#' hd_kraken_ohlcvt(c("EURUSD", "GBPUSD"), interval_min = 1440L)
hd_kraken_ohlcvt <- function(ticker = NULL, interval_min = 60L,
                             from = NULL, to = NULL,
                             local = FALSE, collect = TRUE) {
  .hd_check_pit(to)
  if (!interval_min %in% c(60L, 1440L)) {
    cli::cli_abort(c(
      "x" = "{.arg interval_min} must be 60 (hourly) or 1440 (daily), not {interval_min}.",
      "i" = "The kraken_ohlcvt dataset ships only these two intervals (#436)."
    ))
  }

  ds <- hd_datasets()[["kraken_ohlcvt"]]
  source_path <- if (local) {
    p <- file.path(hd_cache_path(), "kraken_ohlcvt.parquet")
    if (!file.exists(p)) {
      cli::cli_abort(c(
        "Local cache not found for kraken_ohlcvt",
        "i" = "Run {.file scripts/fetch_kraken_ohlcvt.R} first, or use {.code local = FALSE}."
      ))
    }
    p
  } else {
    ds$url
  }

  lf <- duckplyr::read_parquet_duckdb(source_path) |>
    dplyr::filter(interval_min == !!as.integer(interval_min))

  if (!is.null(ticker)) {
    ticker <- as.character(ticker)
    lf <- lf |> dplyr::filter(ticker %in% !!ticker)
  }

  # Typed time-filter injection (#453): the parquet 'time' column is
  # TIMESTAMP; probe once and coerce bounds to the matching literal type
  # so DuckDB binds without falling back (or silently zero-matching).
  if (!is.null(from) || !is.null(to)) {
    schema0 <- lf |> head(0) |> dplyr::collect()
    time_is_timestamp <- inherits(schema0[["time"]], "POSIXct")
    time_coerce <- if (time_is_timestamp) {
      function(x) as.POSIXct(x, tz = "UTC")
    } else {
      as.Date
    }
    if (!is.null(from)) lf <- lf |> dplyr::filter(time >= !!time_coerce(from))
    if (!is.null(to))   lf <- lf |> dplyr::filter(time <= !!time_coerce(to))
  }

  lf <- lf |> dplyr::arrange(ticker, time)

  if (collect) dplyr::collect(lf) else lf
}
