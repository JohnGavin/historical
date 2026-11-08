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

#' Parse a boolean environment variable
#'
#' Empty or unset is `FALSE`; "1", "true", "TRUE", "yes" is `TRUE`; "0",
#' "false", "FALSE", "no" is `FALSE`. Anything else aborts, naming the value.
#' @param name Environment variable name.
#' @param value The raw value (defaults to the variable's current value).
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.hd_env_flag <- function(name, value = Sys.getenv(name, "")) {
  if (!nzchar(value) || value %in% c("0", "false", "FALSE", "no")) return(FALSE)
  if (value %in% c("1", "true", "TRUE", "yes")) return(TRUE)
  cli::cli_abort(c(
    "x" = "{.envvar {name}} has unrecognised value {.val {value}}.",
    "i" = "Use one of 1, true, TRUE, yes, 0, false, FALSE, no, or leave it unset."
  ))
}

#' Digest of an Alpaca request set (tickers and their windows)
#'
#' sha256 of the sorted `ticker|win_start|win_end` lines, first 16 hex
#' characters. Part of the fetch cache key: a changed ticker set or window
#' changes it even when the ticker count does not.
#' @param tickers,win_start,win_end Parallel vectors, one element per request.
#' @return Character scalar, 16 hex characters.
#' @keywords internal
.hd_alpaca_request_digest <- function(tickers, win_start, win_end) {
  lines <- sort(paste(tickers, format(win_start), format(win_end), sep = "|"),
                method = "radix")
  substr(digest::digest(paste(lines, collapse = "\n"), algo = "sha256",
                        serialize = FALSE), 1L, 16L)
}

#' cli bullets for a fetch-cache params mismatch
#'
#' A params string is one long unbreakable token, so a bullet holding the whole
#' string wraps at the console width. The bullets show only the `key=value`
#' pieces (split on `;`) that differ. When the two strings differ but neither has
#' a piece the other lacks (reordered, repeated or empty pieces), both full
#' strings are shown, one per bullet, so the abort never lists empty bullets.
#' Values are rendered here, so the result is safe to pass to
#' [cli::cli_abort()] from any environment.
#' @param name File name the params belong to.
#' @param manifest_params,run_params Character scalars: the committed manifest's
#'   params and this run's params.
#' @return Named character vector for `cli::cli_abort()`.
#' @keywords internal
.hd_params_diff_bullets <- function(name, manifest_params, run_params) {
  esc <- function(x) gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
  val <- function(x) esc(cli::format_inline("{.val {x}}"))
  old_p <- strsplit(manifest_params, ";", fixed = TRUE)[[1L]]
  new_p <- strsplit(run_params, ";", fixed = TRUE)[[1L]]
  only_manifest <- setdiff(old_p, new_p)
  only_now <- setdiff(new_p, old_p)
  head <- c("x" = esc(cli::format_inline("{.file {name}} was fetched with different parameters.")))
  tail <- c("i" = "Re-fetch with {.code ALPACA_FORCE_REFETCH=1}.")
  if (length(only_manifest) == 0L && length(only_now) == 0L) {
    return(c(
      head,
      "i" = "Both params strings hold the same key=value pieces; only their order, repetition or an empty segment differ.",
      "i" = paste0("In the manifest: ", val(manifest_params)),
      "i" = paste0("In this run: ", val(run_params)),
      tail
    ))
  }
  c(
    head,
    "i" = paste0("In the manifest only: ", val(only_manifest)),
    "i" = paste0("In this run only: ", val(only_now)),
    tail
  )
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

#' File name of the cached split- and dividend-ADJUSTED bars parquet
#'
#' Adjusted daily bars (`adjustment = "all"`) of the exit tickers plus SPY. A
#' spin-off or split looks like a crash on raw prices and not on these.
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_exit_bars_adj_file_name <- function() "alpaca_exit_bars_adj.parquet"

#' Path of the cached adjusted-bars parquet
#'
#' @inheritParams hd_alpaca_exit_bars_path
#' @return Character path. Aborts if the file is absent, naming the fetch script.
#' @family alpaca
#' @export
hd_alpaca_exit_bars_adj_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_exit_bars_adj_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca adjusted-bars file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_exit_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_exit_bars_adj_file_name())}}."
    ))
  }
  path
}

#' File name of the cached corporate-actions parquet
#'
#' The flattened output of [hd_alpaca_corporate_actions()] for the exit tickers.
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_exit_corp_actions_file_name <- function() "alpaca_exit_corp_actions.parquet"

#' Path of the cached corporate-actions parquet
#'
#' @inheritParams hd_alpaca_exit_bars_path
#' @return Character path. Aborts if the file is absent, naming the fetch script.
#' @family alpaca
#' @export
hd_alpaca_exit_corp_actions_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_exit_corp_actions_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca corporate-actions file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_exit_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_exit_corp_actions_file_name())}}."
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

#' Zero-row corporate-actions table with the column types
#' `hd_alpaca_corporate_actions()` returns
#' @return A zero-row tibble.
#' @keywords internal
.hd_alpaca_empty_corp_actions <- function() {
  tibble::tibble(
    type            = character(),
    symbol          = character(),
    new_symbol      = character(),
    acquirer_symbol = character(),
    rate            = double(),
    cash_rate       = double(),
    acquirer_rate   = double(),
    acquiree_rate   = double(),
    effective_date  = as.Date(character()),
    process_date    = as.Date(character())
  )
}

#' Flatten the `corporate_actions` object of one response page (internal)
#'
#' The object maps a plural type name (`name_changes`, `cash_mergers`, ...) to
#' a list of records. `symbol` is the first present of `symbol`, `old_symbol`,
#' `acquiree_symbol`, `source_symbol` (the company that stops existing in its
#' old form). `type` is the plural name without its trailing "s".
#' @param cas Named list from `jsonlite::fromJSON(simplifyVector = FALSE)`;
#'   `NULL` or empty is allowed.
#' @return A tibble in the shape of `.hd_alpaca_empty_corp_actions()`.
#' @keywords internal
.hd_alpaca_parse_corp_actions <- function(cas) {
  if (length(cas) == 0L) return(.hd_alpaca_empty_corp_actions())
  parts <- lapply(names(cas), function(plural) {
    recs <- cas[[plural]]
    if (length(recs) == 0L) return(NULL)
    chr <- function(fields) {
      vapply(recs, function(r) {
        for (f in fields) {
          v <- r[[f]]
          if (!is.null(v)) return(as.character(v)[1L])
        }
        NA_character_
      }, character(1))
    }
    num <- function(field) {
      vapply(recs, function(r) as.numeric(r[[field]] %||% NA_real_), numeric(1))
    }
    day <- function(field) as.Date(substr(chr(field), 1L, 10L))
    tibble::tibble(
      type            = sub("s$", "", plural),
      symbol          = chr(c("symbol", "old_symbol", "acquiree_symbol", "source_symbol")),
      new_symbol      = chr("new_symbol"),
      acquirer_symbol = chr("acquirer_symbol"),
      rate            = num("rate"),
      cash_rate       = num("cash_rate"),
      acquirer_rate   = num("acquirer_rate"),
      acquiree_rate   = num("acquiree_rate"),
      effective_date  = day("effective_date"),
      process_date    = day("process_date")
    )
  })
  out <- dplyr::bind_rows(parts)
  if (nrow(out) == 0L) .hd_alpaca_empty_corp_actions() else out
}

#' Corporate actions from the Alpaca market-data API
#'
#' Calls `GET https://data.alpaca.markets/v1/corporate-actions` for `symbols`,
#' in batches, following `next_page_token`, and flattens every record type into
#' one table. The records used by the exit-type rule (#1041) are
#' `name_change` (`old_symbol` to `new_symbol`), `cash_merger` (deal price in
#' `rate`), and `stock_merger` / `stock_and_cash_merger` (`acquirer_symbol`,
#' `acquirer_rate`, `acquiree_rate`, `cash_rate`). A live probe on 2026-11-08
#' found the feed starting around 2020: earlier events have no record.
#'
#' A non-200 response aborts with the HTTP status and the API message.
#'
#' @inheritSection hd_alpaca_bars Credentials
#'
#' @param symbols Character vector of ticker symbols (no `NA`, no empty
#'   strings; duplicates are dropped).
#' @param start,end Inclusive date range (Date or coercible).
#' @param types Record types to request; any of `"name_change"`,
#'   `"cash_merger"`, `"stock_merger"`, `"stock_and_cash_merger"`,
#'   `"spin_off"`. Default: all five.
#' @param key,secret Optional explicit credentials; default to the environment.
#' @param batch_size Symbols per request. Default 50.
#' @param limit Records per page (API maximum 1000). Default 1000.
#' @return A tibble: `type`, `symbol`, `new_symbol`, `acquirer_symbol`, `rate`,
#'   `cash_rate`, `acquirer_rate`, `acquiree_rate`, `effective_date` (Date),
#'   `process_date` (Date). Fields a record type does not have are `NA`. Zero
#'   rows (same columns) when nothing is returned.
#' @family alpaca
#' @export
hd_alpaca_corporate_actions <- function(symbols, start, end,
                                        types = c("name_change", "cash_merger",
                                                  "stock_merger", "stock_and_cash_merger",
                                                  "spin_off"),
                                        key = NULL, secret = NULL,
                                        batch_size = 50L, limit = 1000L) {
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
  all_types <- c("name_change", "cash_merger", "stock_merger",
                 "stock_and_cash_merger", "spin_off")
  if (!is.character(types) || length(types) == 0L || anyNA(types) ||
      !all(types %in% all_types)) {
    cli::cli_abort(c(
      "x" = "{.arg types} must be one or more of {.val {all_types}}."
    ))
  }
  types <- unique(types)
  if (length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L ||
      length(limit) != 1L || is.na(limit) || limit < 1L || limit > 1000L) {
    cli::cli_abort("{.arg batch_size} must be >= 1 and {.arg limit} must be in 1..1000.")
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
      types      = paste(types, collapse = ","),
      start      = format(start),
      end        = format(end),
      limit      = as.integer(limit),
      page_token = token
    )
    req <- httr2::request("https://data.alpaca.markets") |>
      httr2::req_url_path_append("v1", "corporate-actions") |>
      httr2::req_headers(
        `APCA-API-KEY-ID` = key,
        `APCA-API-SECRET-KEY` = secret
      ) |>
      httr2::req_url_query(!!!query) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_retry(max_tries = 3L) |>
      httr2::req_throttle(rate = 200 / 60)
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
        "x" = "Alpaca corporate-actions request failed: HTTP {status}.",
        "i" = "API message: {.val {msg}}",
        "i" = "Symbols in this batch ({length(batch)}): {.val {utils::head(batch, 5L)}}."
      ), call = rlang::caller_env())
    }
    if (!jsonlite::validate(body)) {
      cli::cli_abort(c(
        "x" = "Alpaca corporate-actions response was HTTP 200 but not valid JSON.",
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
      pieces[[length(pieces) + 1L]] <- .hd_alpaca_parse_corp_actions(page[["corporate_actions"]])
      token <- page[["next_page_token"]]
      if (is.null(token) || !is.character(token) || !nzchar(token)) break
    }
  }
  out <- dplyr::bind_rows(pieces)
  if (nrow(out) == 0L) return(.hd_alpaca_empty_corp_actions())
  out[order(out$symbol, out$effective_date, out$process_date, out$type), , drop = FALSE]
}

#' File name of the cached adjusted bars of every S&P 500 member since 2016
#'
#' Adjusted daily bars (`adjustment = "all"`) of every ticker that was a
#' point-in-time S&P 500 member on or after the first date Alpaca covers, one
#' window per ticker (see `scripts/fetch_alpaca_member_bars.R`).
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_member_bars_adj_file_name <- function() "alpaca_member_bars_adj.parquet"

#' Path of the cached member-bars parquet
#'
#' @inheritParams hd_alpaca_exit_bars_path
#' @return Character path. Aborts if the file is absent, naming the fetch script.
#' @family alpaca
#' @export
hd_alpaca_member_bars_adj_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_member_bars_adj_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca member-bars file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_member_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_member_bars_adj_file_name())}}."
    ))
  }
  path
}

#' File name of the cached adjusted bars of TODAY's S&P 500 members
#'
#' Adjusted daily bars (`adjustment = "all"`) of the tickers on the latest
#' membership snapshot, each over the whole backtest window, plus the old
#' symbols of their renames (see `scripts/fetch_alpaca_current_member_bars.R`).
#' @return Character scalar.
#' @keywords internal
.hd_alpaca_current_member_bars_adj_file_name <- function() "alpaca_current_member_bars_adj.parquet"

#' Path of the cached current-member-bars parquet
#'
#' @inheritParams hd_alpaca_exit_bars_path
#' @return Character path. Aborts if the file is absent, naming the fetch script.
#' @family alpaca
#' @export
hd_alpaca_current_member_bars_adj_path <- function(data_dir = hd_alpaca_bars_data_dir()) {
  path <- file.path(data_dir, .hd_alpaca_current_member_bars_adj_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Alpaca current-member-bars file not found: {.path {path}}.",
      "i" = "Fetch it first (needs {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET}): {.code Rscript scripts/fetch_alpaca_current_member_bars.R}",
      "i" = "Or set {.envvar ALPACA_BARS_DIR} to a directory that holds {.file {(.hd_alpaca_current_member_bars_adj_file_name())}}."
    ))
  }
  path
}
