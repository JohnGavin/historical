# Exit prices for S&P 500 leavers, from Alpaca daily bars (#1041)
#
# WHAT THIS IS. For every ticker that left the point-in-time S&P 500 index
# (hd_sp500_exits()), a LAST-TRADE price taken from Alpaca bars plus a
# failure flag and a lower/upper bound on what a holder got. It is a bound,
# not a delisting return: Alpaca has no delisting reason or recovery value.
# Acquisitions: the last close is close to the deal value (upper == lower).
# Failures: the last exchange close overstates what holders received (SIVB's
# last close was 106.04, the equity was later worth close to zero), so a
# failure candidate carries a lower bound of 0.
#
# WHAT THIS IS NOT. Tickers that left before 2016-01-04 have no free source
# (464 of 706 as of 2026-11-08): they come back with has_bars = FALSE and no
# price. An index exit is also not a delisting: a demoted name keeps trading,
# and its "last trade" is then the last bar inside the exit + 30 day window.

#' The exit-price rule constants (single home, #1041)
#'
#' Every threshold of the exit-price rule lives here and nowhere else.
#' \describe{
#'   \item{`panel_start`}{First date the Alpaca `sip` feed covers (2016-01-04).
#'     Exits before it cannot be priced.}
#'   \item{`window_days`}{Days either side of a ticker's membership span within
#'     which bars are used. Clips ticker recycling (a later company reusing the
#'     symbol) and stale series that run on after a seizure.}
#'   \item{`max_gap_trading_days`}{A last trade MORE than this many trading
#'     days before the index exit date marks a failure candidate.}
#'   \item{`crash_drop`}{A close that fell by MORE than this fraction over
#'     `crash_lookback` trading days to the last trade marks a failure
#'     candidate.}
#'   \item{`crash_lookback`}{Trading days (bars with volume > 0) for the drop.}
#' }
#' A bar is a trade only if its `volume` is above zero.
#'
#' @return A named list.
#' @family alpaca
#' @export
hd_alpaca_exit_rule <- function() {
  list(
    panel_start          = as.Date("2016-01-04"),
    window_days          = 30L,
    max_gap_trading_days = 5L,
    crash_drop           = 0.5,
    crash_lookback       = 60L
  )
}

#' Tickers that left the point-in-time S&P 500
#'
#' One row per ticker whose latest membership spell ended before the last
#' snapshot. A ticker that left and later returned (still a member at the last
#' snapshot) is not an exit. `index_exit_date` is the first snapshot at which
#' the ticker was no longer a member; it is NOT a delisting date (an
#' acquisition, a bankruptcy and a demotion look alike).
#'
#' @param membership Output of [hd_sp500_membership()] (or any data frame with
#'   a Date `date` and character `ticker`, such as `stk_universe_pit`).
#' @return A tibble: `ticker`, `first_member_date` (first snapshot the ticker
#'   was ever a member), `last_member_date` (last snapshot of its final spell),
#'   `index_exit_date`, ordered by exit date then ticker.
#' @family sp500
#' @export
hd_sp500_exits <- function(membership) {
  u <- hd_sp500_pit_universe(membership)
  u <- u[order(u$ticker, u$date), , drop = FALSE]
  first <- u[!duplicated(u$ticker), , drop = FALSE]
  last <- u[!duplicated(u$ticker, fromLast = TRUE), , drop = FALSE]
  out <- tibble::tibble(
    ticker            = last$ticker,
    first_member_date = first$date,
    last_member_date  = last$date,
    index_exit_date   = last$delisting_date
  )
  out <- out[!is.na(out$index_exit_date), , drop = FALSE]
  out[order(out$index_exit_date, out$ticker), , drop = FALSE]
}

#' Weekdays strictly after `from` up to and including `to` (0 if `to <= from`)
#'
#' Exchange holidays are not removed, so this can overstate the trading-day
#' gap by one per holiday inside the interval.
#' @param from,to Date vectors of equal length.
#' @return Integer vector.
#' @keywords internal
.hd_weekdays_after <- function(from, to) {
  vapply(seq_along(from), function(i) {
    if (to[i] <= from[i]) return(0L)
    d <- seq(from[i] + 1L, to[i], by = "day")
    sum(!(format(d, "%u") %in% c("6", "7")))
  }, integer(1))
}

#' Exit price and failure flag for each S&P 500 leaver
#'
#' Applies the #1041 exit-price rule (constants in [hd_alpaca_exit_rule()]):
#'
#' 1. Bars of a ticker are clipped to its membership span plus or minus
#'    `window_days` (lower edge: `max(panel_start, first_member_date)`), so a
#'    later company that reused the symbol is ignored.
#' 2. A bar is a trade only if `volume > 0`. The last trade is the last such
#'    bar on or before `index_exit_date + window_days`.
#' 3. `gap_trading_days` is the number of weekdays between the last trade and
#'    the index exit (0 if the last trade is on or after the exit). Exchange
#'    holidays are not removed.
#' 4. `ret_60d` is the last close over the close `crash_lookback` trading days
#'    earlier, minus 1 (`NA` with fewer bars).
#' 5. `failure_candidate` is `TRUE` when `gap_trading_days >
#'    max_gap_trading_days`, or `ret_60d < -crash_drop`, or the ticker is in
#'    `known_failed`. With no usable bars it is `TRUE` for a known failure and
#'    `NA` (unknown) otherwise.
#' 6. `exit_price_upper` is the last close; `exit_price_lower` is 0 for a
#'    failure candidate, else the last close.
#'
#' @param bars Output of [hd_alpaca_bars()] (needs `symbol`, `date`, `close`,
#'   `volume`; no `NA` in `date`, `close`, `volume`).
#' @param exits Output of [hd_sp500_exits()] (needs `ticker`,
#'   `first_member_date`, `index_exit_date`; one row per ticker).
#' @param known_failed Character vector of tickers known to have failed
#'   (e.g. `hd_sp500_known_delisted()$ticker`); they are forced to
#'   `failure_candidate = TRUE`.
#' @param rule Rule constants. Defaults to [hd_alpaca_exit_rule()].
#' @return A tibble, one row per exit: `ticker`, `index_exit_date`,
#'   `last_trade_date`, `last_close`, `gap_trading_days`, `ret_60d`,
#'   `failure_candidate`, `exit_price_upper`, `exit_price_lower`, `has_bars`.
#' @family alpaca
#' @export
hd_alpaca_exit_prices <- function(bars, exits, known_failed = character(),
                                  rule = hd_alpaca_exit_rule()) {
  need_b <- c("symbol", "date", "close", "volume")
  if (!is.data.frame(bars) || !all(need_b %in% names(bars)) ||
      !inherits(bars$date, "Date") || !is.character(bars$symbol) ||
      !is.numeric(bars$close) || !is.numeric(bars$volume)) {
    cli::cli_abort(c(
      "x" = "{.arg bars} must be a data frame with {.field {need_b}} (Date {.field date}, numeric {.field close} and {.field volume}).",
      "i" = "Build it with {.fn hd_alpaca_bars}."
    ))
  }
  if (anyNA(bars$date) || anyNA(bars$close) || anyNA(bars$volume) || anyNA(bars$symbol)) {
    cli::cli_abort("{.arg bars} has missing {.field symbol}, {.field date}, {.field close} or {.field volume} values.")
  }
  need_e <- c("ticker", "first_member_date", "index_exit_date")
  if (!is.data.frame(exits) || !all(need_e %in% names(exits)) ||
      !inherits(exits$first_member_date, "Date") || !inherits(exits$index_exit_date, "Date") ||
      anyNA(exits$ticker) || anyNA(exits$first_member_date) || anyNA(exits$index_exit_date)) {
    cli::cli_abort(c(
      "x" = "{.arg exits} must be a data frame with {.field {need_e}} (Dates, no NA).",
      "i" = "Build it with {.fn hd_sp500_exits}."
    ))
  }
  if (anyDuplicated(exits$ticker) > 0L) {
    cli::cli_abort("{.arg exits} must have one row per ticker.")
  }
  if (!is.character(known_failed) || anyNA(known_failed)) {
    cli::cli_abort("{.arg known_failed} must be a character vector without NA.")
  }
  need_r <- names(hd_alpaca_exit_rule())
  if (!is.list(rule) || !all(need_r %in% names(rule))) {
    cli::cli_abort("{.arg rule} must be a list with {.field {need_r}}; see {.fn hd_alpaca_exit_rule}.")
  }

  by_sym <- split(bars, bars$symbol)
  rows <- lapply(seq_len(nrow(exits)), function(i) {
    tk <- exits$ticker[i]
    exit_d <- exits$index_exit_date[i]
    lo <- max(rule$panel_start, exits$first_member_date[i]) - rule$window_days
    hi <- exit_d + rule$window_days
    b <- by_sym[[tk]]
    if (!is.null(b)) {
      b <- b[b$date >= lo & b$date <= hi & b$volume > 0, , drop = FALSE]
      b <- b[order(b$date), , drop = FALSE]
    }
    known <- tk %in% known_failed
    n <- if (is.null(b)) 0L else nrow(b)
    if (n == 0L) {
      return(tibble::tibble(
        ticker = tk, index_exit_date = exit_d,
        last_trade_date = as.Date(NA), last_close = NA_real_,
        gap_trading_days = NA_integer_, ret_60d = NA_real_,
        failure_candidate = if (known) TRUE else NA,
        exit_price_upper = NA_real_,
        exit_price_lower = if (known) 0 else NA_real_,
        has_bars = FALSE
      ))
    }
    last_d <- b$date[n]
    last_c <- b$close[n]
    gap <- .hd_weekdays_after(last_d, exit_d)
    ret <- if (n > rule$crash_lookback) {
      last_c / b$close[n - rule$crash_lookback] - 1
    } else {
      NA_real_
    }
    fail <- known || gap > rule$max_gap_trading_days ||
      isTRUE(ret < -rule$crash_drop)
    tibble::tibble(
      ticker = tk, index_exit_date = exit_d,
      last_trade_date = last_d, last_close = last_c,
      gap_trading_days = gap, ret_60d = ret,
      failure_candidate = fail,
      exit_price_upper = last_c,
      exit_price_lower = if (fail) 0 else last_c,
      has_bars = TRUE
    )
  })
  out <- dplyr::bind_rows(rows)
  if (nrow(out) == 0L) {
    return(tibble::tibble(
      ticker = character(), index_exit_date = as.Date(character()),
      last_trade_date = as.Date(character()), last_close = double(),
      gap_trading_days = integer(), ret_60d = double(),
      failure_candidate = logical(), exit_price_upper = double(),
      exit_price_lower = double(), has_bars = logical()
    ))
  }
  out[order(out$index_exit_date, out$ticker), , drop = FALSE]
}

#' Exit-price coverage by index-exit year
#'
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @return A tibble: `exit_year`, `n_exits`, `n_with_bars`,
#'   `n_failure_candidates` (count of `TRUE`; `NA` is not counted).
#' @family alpaca
#' @export
hd_alpaca_exit_coverage <- function(exit_prices) {
  need <- c("index_exit_date", "has_bars", "failure_candidate")
  if (!is.data.frame(exit_prices) || !all(need %in% names(exit_prices)) ||
      !inherits(exit_prices$index_exit_date, "Date") || anyNA(exit_prices$index_exit_date)) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field {need}} and no missing exit date.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ))
  }
  yr <- as.integer(format(exit_prices$index_exit_date, "%Y"))
  years <- sort(unique(yr))
  tibble::tibble(
    exit_year            = years,
    n_exits              = as.integer(vapply(years, function(y) sum(yr == y), numeric(1))),
    n_with_bars          = as.integer(vapply(years, function(y) sum(yr == y & exit_prices$has_bars), numeric(1))),
    n_failure_candidates = as.integer(vapply(years, function(y) sum(yr == y & exit_prices$failure_candidate %in% TRUE), numeric(1)))
  )
}
