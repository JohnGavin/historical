# Alpaca daily stock bars (#1041)
#
# Thin httr2 wrapper over the Alpaca market-data endpoint
# `GET https://data.alpaca.markets/v2/stocks/bars`. Its job in this project is
# to price S&P 500 leavers (see alpaca_exit_prices.R): the `sip` feed carries
# bars for delisted symbols from 2016-01-04, which no other free source does.
# A live probe on 2026-11-08 (issue #1041) found that the feed has NO delisting
# return or reason, and that a seized bank's series can run on at a flat price
# after the seizure (SBNY), so callers must treat `volume == 0` bars as
# non-trades.

#' Directory holding the local Alpaca exit-bars cache
#'
#' Reads `ALPACA_BARS_DIR`, defaulting to `~/.cache/historical/alpaca_exit_bars`.
#' Only resolves the path; it is never created or written here. Populate it
#' with `scripts/fetch_alpaca_exit_bars.R`.
#'
#' @return Character path (not guaranteed to exist).
#' @family alpaca
#' @export
hd_alpaca_bars_data_dir <- function() {
  path.expand(Sys.getenv("ALPACA_BARS_DIR", "~/.cache/historical/alpaca_exit_bars"))
}

#' File name of the cached exit-bars parquet inside [hd_alpaca_bars_data_dir()]
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_exit_bars_file_name <- function() "alpaca_exit_bars.parquet"

#' Path of the cached Alpaca exit-bars parquet
#'
#' @param data_dir Directory holding the cache. Defaults to [hd_alpaca_bars_data_dir()].
#' @return Character path to the parquet. Aborts if the file is absent, naming
#'   the fetch script, so a machine without the cache fails loudly (never an
#'   empty result).
#' @family alpaca
#' @export
hd_alpaca_exit_bars_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_exit_bars_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca exit-bars file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_exit_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_exit_bars_file_name())}}."
    ))
  }
  path
}

#' File name of the cached Alpaca assets parquet inside [hd_alpaca_bars_data_dir()]
#'
#' The asset list (status active and inactive, us_equity) used to detect ticker
#' changes in [hd_alpaca_exit_prices()].
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_exit_assets_file_name <- function() "alpaca_assets_us_equity_both.parquet"

#' Path of the cached Alpaca assets parquet
#'
#' @inheritParams hd_alpaca_exit_bars_path
#' @return Character path. Aborts if the file is absent, naming the fetch script.
#' @family alpaca
#' @export
hd_alpaca_exit_assets_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_exit_assets_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca assets file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_exit_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_exit_assets_file_name())}}."
    ))
  }
  path
}

#' Zero-row bars table with the column types `hd_alpaca_bars()` returns
#' @return A zero-row tibble.
#' @keywords internal
.hd_alpaca_empty_bars <- function() {
  tibble::tibble(
    symbol      = character(),
    date        = as.Date(character()),
    open        = double(),
    high        = double(),
    low         = double(),
    close       = double(),
    volume      = double(),
    trade_count = double(),
    vwap        = double()
  )
}

#' Convert the `bars` object of one response page into a tibble
#' @param bars Named list (symbol -> list of bar records) from
#'   `jsonlite::fromJSON(simplifyVector = FALSE)`; `NULL` or empty is allowed.
#' @return A tibble in the shape of `.hd_alpaca_empty_bars()`.
#' @keywords internal
.hd_alpaca_parse_bars <- function(bars) {
  if (length(bars) == 0L) return(.hd_alpaca_empty_bars())
  parts <- lapply(names(bars), function(sym) {
    b <- bars[[sym]]
    if (length(b) == 0L) return(NULL)
    num <- function(field) {
      vapply(b, function(r) as.numeric(r[[field]] %||% NA_real_), numeric(1))
    }
    stamp <- vapply(b, function(r) as.character(r[["t"]] %||% NA_character_), character(1))
    tibble::tibble(
      symbol      = sym,
      # Daily bars are stamped at the start of the US trading day (04:00 or
      # 05:00 UTC), so the first ten characters ARE the trading date.
      date        = as.Date(substr(stamp, 1L, 10L)),
      open        = num("o"),
      high        = num("h"),
      low         = num("l"),
      close       = num("c"),
      volume      = num("v"),
      trade_count = num("n"),
      vwap        = num("vw")
    )
  })
  out <- dplyr::bind_rows(parts)
  if (nrow(out) == 0L) return(.hd_alpaca_empty_bars())
  if (anyNA(out$date)) {
    cli::cli_abort(c(
      "x" = "Alpaca returned {sum(is.na(out$date))} bar{?s} with a missing or unparseable timestamp."
    ))
  }
  out
}

#' Daily stock bars from the Alpaca market-data API
#'
#' Calls `GET https://data.alpaca.markets/v2/stocks/bars` (`timeframe =
#' "1Day"`) for `symbols`, in batches, following `next_page_token` until the
#' response is exhausted. Delisted symbols are served: on the `sip`
#' (consolidated) feed history starts 2016-01-04. Symbols the API does not
#' know are simply absent from the result, which is not an error, so compare
#' the returned `symbol` set with the request when completeness matters.
#'
#' A non-200 response aborts with the HTTP status and the API message. There
#' is no silent fallback.
#'
#' @section Credentials:
#' Reads `ALPACA_KEY` / `ALPACA_SECRET` from the environment (same as
#' [hd_alpaca_assets_snapshot()]) unless `key` / `secret` are passed. Aborts
#' early if either is missing.
#'
#' @section Zero-volume bars:
#' The API can return bars with `volume == 0` (a flat price carried on after
#' a delisting or seizure). They are returned unchanged; deciding that they
#' are not trades is the caller's job (see [hd_alpaca_exit_prices()]).
#'
#' @param symbols Character vector of ticker symbols (no `NA`, no empty
#'   strings; duplicates are dropped).
#' @param start,end Inclusive date range (Date or coercible).
#' @param feed One of `"sip"`, `"iex"`, `"otc"`. Default `"sip"`.
#' @param adjustment One of `"raw"`, `"split"`, `"dividend"`, `"all"`.
#'   Default `"raw"`.
#' @param key,secret Optional explicit credentials; default to the
#'   environment variables above.
#' @param batch_size Symbols per request. Default 50.
#' @param limit Bars per page (API maximum 10000). Default 10000.
#' @return A tibble: `symbol`, `date` (Date), `open`, `high`, `low`, `close`,
#'   `volume`, `trade_count`, `vwap` (all double), ordered by symbol then
#'   date. Zero rows (same columns) when nothing is returned.
#' @family alpaca
#' @export
hd_alpaca_bars <- function(symbols, start, end,
                           feed = "sip", adjustment = "raw",
                           key = NULL, secret = NULL,
                           batch_size = 50L, limit = 10000L) {
  rlang::check_installed(c("httr2", "jsonlite"))

  if (!is.character(symbols) || length(symbols) == 0L || anyNA(symbols) ||
      any(!nzchar(trimws(symbols)))) {
    cli::cli_abort(c(
      "x" = "{.arg symbols} must be a non-empty character vector without NA or empty strings."
    ))
  }
  symbols <- unique(trimws(symbols))
  start <- as.Date(start)
  end <- as.Date(end)
  if (length(start) != 1L || length(end) != 1L || is.na(start) || is.na(end) || start > end) {
    cli::cli_abort(c(
      "x" = "{.arg start} and {.arg end} must be single dates with {.arg start} <= {.arg end}."
    ))
  }
  feed <- match.arg(feed, c("sip", "iex", "otc"))
  adjustment <- match.arg(adjustment, c("raw", "split", "dividend", "all"))
  if (length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L ||
      length(limit) != 1L || is.na(limit) || limit < 1L || limit > 10000L) {
    cli::cli_abort("{.arg batch_size} must be >= 1 and {.arg limit} must be in 1..10000.")
  }

  key <- key %||% Sys.getenv("ALPACA_KEY", unset = NA_character_)
  secret <- secret %||% Sys.getenv("ALPACA_SECRET", unset = NA_character_)
  if (is.na(key) || !nzchar(key) || is.na(secret) || !nzchar(secret)) {
    cli::cli_abort(c(
      "x" = "Alpaca credentials missing.",
      "i" = "Set {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET} in {.file ~/.Renviron} (then restart R), or pass {.arg key}/{.arg secret} explicitly."
    ))
  }

  fetch_page <- function(batch, token) {
    query <- list(
      symbols    = paste(batch, collapse = ","),
      timeframe  = "1Day",
      # Date-only bounds could be read as midnight and drop the final day's
      # bar, so the bounds are explicit instants covering whole days.
      start      = paste0(format(start), "T00:00:00Z"),
      end        = paste0(format(end), "T23:59:59Z"),
      limit      = as.integer(limit),
      adjustment = adjustment,
      feed       = feed,
      page_token = token
    )
    req <- httr2::request("https://data.alpaca.markets") |>
      httr2::req_url_path_append("v2", "stocks", "bars") |>
      httr2::req_headers(
        `APCA-API-KEY-ID` = key,
        `APCA-API-SECRET-KEY` = secret
      ) |>
      httr2::req_url_query(!!!query) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_retry(max_tries = 3L) |>
      httr2::req_throttle(rate = 200 / 60)  # 200 req/min free tier
    resp <- httr2::req_perform(req)
    status <- httr2::resp_status(resp)
    body <- httr2::resp_body_string(resp)
    if (status != 200L) {
      msg <- if (nzchar(body) && jsonlite::validate(body)) {
        parsed <- jsonlite::fromJSON(body, simplifyVector = FALSE)
        as.character(parsed[["message"]] %||% body)[1L]
      } else {
        body
      }
      cli::cli_abort(c(
        "x" = "Alpaca bars request failed: HTTP {status}.",
        "i" = "API message: {.val {msg}}",
        "i" = "Symbols in this batch ({length(batch)}): {.val {utils::head(batch, 5L)}}."
      ), call = rlang::caller_env())
    }
    if (!jsonlite::validate(body)) {
      cli::cli_abort(c(
        "x" = "Alpaca bars response was HTTP 200 but not valid JSON.",
        "i" = "Symbols in this batch ({length(batch)}): {.val {utils::head(batch, 5L)}}."
      ), call = rlang::caller_env())
    }
    jsonlite::fromJSON(body, simplifyVector = FALSE)
  }

  batches <- split(symbols, ceiling(seq_along(symbols) / batch_size))
  pieces <- list()
  for (batch in batches) {
    token <- NULL
    repeat {
      page <- fetch_page(batch, token)
      pieces[[length(pieces) + 1L]] <- .hd_alpaca_parse_bars(page[["bars"]])
      token <- page[["next_page_token"]]
      if (is.null(token) || !nzchar(token)) break
    }
  }
  out <- dplyr::bind_rows(pieces)
  if (nrow(out) == 0L) return(.hd_alpaca_empty_bars())
  out[order(out$symbol, out$date), , drop = FALSE]
}
