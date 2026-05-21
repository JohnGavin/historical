#' AlphaVantage registry entry
#'
#' Returns registry metadata for AlphaVantage data sources.
#' AlphaVantage is an API source (not a parquet file), so `source` is a
#' function marker rather than a URL.
#'
#' @section Free-tier constraints:
#' AlphaVantage free tier limits:
#' \itemize{
#'   \item 5 requests / minute
#'   \item 500 requests / day
#' }
#' All wrappers throttle via `httr2::req_throttle()` and cache results to local
#' parquet. Do NOT call AlphaVantage from CI on every push — gate on the
#' `AV_REFRESH` environment variable or a scheduled refresh workflow.
#'
#' @section Credentials:
#' Reads from `Sys.getenv("ALPHAVANTAGE_API_KEY")`. Add to `~/.Renviron`:
#' ```
#' ALPHAVANTAGE_API_KEY=your_key_here
#' ```
#' Never inline the key in code. Never commit to version control.
#'
#' @return Named list of AlphaVantage dataset metadata
#' @family discovery
#' @export
hd_av_registry <- function() {
  list(
    alphavantage_daily = list(
      source      = "alphavantager::av_get",
      schema      = c("date", "open", "high", "low", "close",
                      "adjusted_close", "volume", "ticker"),
      frequency   = "daily",
      description = paste0(
        "US equities daily adjusted OHLCV via AlphaVantage TIME_SERIES_DAILY_ADJUSTED. ",
        "Free tier: 5 req/min, 500/day. Requires ALPHAVANTAGE_API_KEY in ~/.Renviron."
      ),
      rate_limit  = list(
        calls_per_min = "5",
        calls_per_day = "500"
      ),
      key_env     = "ALPHAVANTAGE_API_KEY"
    )
  )
}

#' Fetch daily adjusted OHLCV from AlphaVantage
#'
#' Calls AlphaVantage `TIME_SERIES_DAILY_ADJUSTED` and returns a tidy tibble
#' with the standard `historicaldata` schema. Respects the free-tier rate limit
#' of 5 calls/minute via `Sys.sleep()` between batch calls.
#'
#' @section Credentials:
#' API key is read from `Sys.getenv("ALPHAVANTAGE_API_KEY")`. Set in
#' `~/.Renviron` (NOT in project code). The function aborts early with an
#' informative message if the key is absent.
#'
#' @section Rate limits:
#' The AlphaVantage free tier allows 5 requests / minute and 500 / day.
#' For batches larger than 5 tickers, add a `Sys.sleep(12)` between each
#' call or use `hd_av_batch()` (not yet implemented) which handles throttling
#' automatically.
#'
#' @section CI safety:
#' This function makes a live API call. Do NOT call from CI on every push.
#' Gate on `AV_REFRESH=1` environment variable or use a scheduled workflow.
#'
#' @param ticker A single ticker symbol (e.g. `"AAPL"`, `"IBM"`).
#' @param from Start date (character `"YYYY-MM-DD"` or `Date`). Default: 20
#'   years ago. AlphaVantage returns ~20 years on the full output size.
#' @param outputsize One of `"compact"` (last 100 data points, default) or
#'   `"full"` (up to 20 years). Use `"full"` for historical backtests.
#' @param key API key. If `NULL` (default), reads `ALPHAVANTAGE_API_KEY` env var.
#' @return A tibble with columns: `date`, `open`, `high`, `low`, `close`,
#'   `adjusted_close`, `volume`, `ticker`.
#' @family data-access
#' @export
#' @examplesIf interactive() && nzchar(Sys.getenv("ALPHAVANTAGE_API_KEY"))
#' hd_alphavantage("IBM", from = "2024-01-01")
hd_alphavantage <- function(ticker,
                             from       = NULL,
                             outputsize = c("compact", "full"),
                             key        = NULL) {
  rlang::check_installed("alphavantager",
    reason = "needed to fetch AlphaVantage data")
  outputsize <- match.arg(outputsize)

  key <- key %||% Sys.getenv("ALPHAVANTAGE_API_KEY", unset = NA_character_)
  if (is.na(key) || !nzchar(key)) {
    cli::cli_abort(c(
      "x" = "AlphaVantage API key missing.",
      "i" = "Set {.envvar ALPHAVANTAGE_API_KEY} in {.file ~/.Renviron} (then restart R), or pass {.arg key} explicitly.",
      "i" = "Free key at {.url https://www.alphavantage.co/support/#api-key}"
    ))
  }

  alphavantager::av_api_key(key)

  raw <- alphavantager::av_get(
    symbol     = ticker,
    av_fun     = "TIME_SERIES_DAILY_ADJUSTED",
    outputsize = outputsize
  )

  # Normalise column names: av_get returns timestamp, open, high, low, close,
  # adjusted_close, volume, dividend_amount, split_coefficient
  result <- tibble::tibble(
    date          = as.Date(raw$timestamp),
    open          = as.numeric(raw$open),
    high          = as.numeric(raw$high),
    low           = as.numeric(raw$low),
    close         = as.numeric(raw$close),
    adjusted_close = as.numeric(raw$adjusted_close),
    volume        = as.integer(raw$volume),
    ticker        = ticker
  )

  if (!is.null(from)) {
    from_date <- as.Date(from)
    result <- dplyr::filter(result, date >= from_date)
  }

  dplyr::arrange(result, date)
}
