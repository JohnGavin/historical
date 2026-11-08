# Exit prices for S&P 500 leavers, from Alpaca daily bars (#1041)
#
# WHAT THIS IS. For every ticker that left the point-in-time S&P 500 index
# (hd_sp500_exits()), a classification of WHY it left (`exit_type`) and, where
# that is meaningful, a LAST-TRADE price with a lower/upper bound on what a
# holder got. It is a bound, not a delisting return: Alpaca has no delisting
# reason or recovery value. Acquisitions: the last close is close to the deal
# value (upper == lower). Failures: the last exchange close overstates what
# holders received (SIVB's last close was 106.04, the equity was later worth
# close to zero), so a failure candidate carries a lower bound of 0.
#
# THE RULE (third revision, owner-approved 2026-11-08). The first rule, a
# trading-gap test plus a 50% fall, misclassified 9 of 15 flags on real data.
# The second matched company names against Alpaca's asset list; on real data it
# found zero ticker changes (the list omits FI and DWDP has an empty name) and
# its 60-day fall was computed on UNADJUSTED bars, so spin-offs (DWDP, UTX) and
# a merger in the COVID crash (RTN) looked like failures. The third uses
# Alpaca's corporate-actions records where they exist, and otherwise a fall
# that is ADJUSTED for splits and spin-offs and RELATIVE to SPY. See
# hd_alpaca_exit_prices() for the order of the tests.
#
# WHAT THIS IS NOT. Tickers that left before 2016-01-04 have no free source
# (464 of 706 as of 2026-11-08): they come back with has_bars = FALSE and no
# price. An index exit is also not a delisting: a demoted name keeps trading.

#' The exit-price rule constants (single home, #1041)
#'
#' Every threshold of the exit-price rule lives here and nowhere else.
#' \describe{
#'   \item{`panel_start`}{First date the Alpaca `sip` feed covers (2016-01-04).
#'     Exits before it cannot be priced.}
#'   \item{`window_days`}{Days either side of a ticker's membership span within
#'     which bars are used. Clips ticker recycling (a later company reusing the
#'     symbol) and stale series that run on after a seizure.}
#'   \item{`crash_drop`}{A name that stopped trading, has no corporate-action
#'     record, and whose ADJUSTED close fell by MORE than this fraction RELATIVE
#'     to SPY over `crash_lookback` trading days to its last trade is a failure
#'     candidate. 0.40: relative fall = (1 + stock return) / (1 + SPY return) - 1.
#'     SBNY fell 43% against a SPY gain; the false failures were spin-offs
#'     (-44% raw, ~0% adjusted) and a merger in the COVID crash (-48% against
#'     SPY -25%, relative -31%).}
#'   \item{`crash_lookback`}{Trading days (bars with volume > 0) for the fall.}
#'   \item{`too_recent_weekdays`}{An exit within this many weekdays of the last
#'     date in the fetched bars cannot yet be told from a demotion.}
#'   \item{`ca_days_before`, `ca_days_after`}{A corporate-action record counts
#'     for an exit if its date (`effective_date`, else `process_date`) lies
#'     from `ca_days_before` days before the exit to `ca_days_after` days after it.}
#' }
#' A bar is a trade only if its `volume` is above zero.
#'
#' @return A named list.
#' @family alpaca
#' @export
hd_alpaca_exit_rule <- function() {
  list(
    panel_start         = as.Date("2016-01-04"),
    window_days         = 30L,
    crash_drop          = 0.40,
    crash_lookback      = 60L,
    too_recent_weekdays = 5L,
    ca_days_before      = 30L,
    ca_days_after       = 10L
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

#' Validate a bars table (internal)
#' @param x Object to check.
#' @param arg Argument name for the message.
#' @param call Caller environment for the error.
#' @return `NULL`, invisibly; aborts when invalid.
#' @keywords internal
.hd_check_exit_bars <- function(x, arg, call = rlang::caller_env()) {
  need_b <- c("symbol", "date", "close", "volume")
  if (!is.data.frame(x) || !all(need_b %in% names(x)) ||
      !inherits(x$date, "Date") || !is.character(x$symbol) ||
      !is.numeric(x$close) || !is.numeric(x$volume)) {
    cli::cli_abort(c(
      "x" = "{.arg {arg}} must be a data frame with {.field {need_b}} (Date {.field date}, numeric {.field close} and {.field volume}).",
      "i" = "Build it with {.fn hd_alpaca_bars}."
    ), call = call)
  }
  if (anyNA(x$date) || anyNA(x$close) || anyNA(x$volume) || anyNA(x$symbol)) {
    cli::cli_abort("{.arg {arg}} has missing {.field symbol}, {.field date}, {.field close} or {.field volume} values.",
                   call = call)
  }
  invisible(NULL)
}

#' Exit type, price and failure flag for each S&P 500 leaver
#'
#' Applies the #1041 exit-price rule (constants in [hd_alpaca_exit_rule()]).
#' Bars of a ticker are clipped to its membership span plus or minus
#' `window_days` (lower edge: `max(panel_start, first_member_date)`), so a later
#' company that reused the symbol is ignored, and only `volume > 0` bars count
#' as trades. Each exit gets one `exit_type`, tested in this order:
#'
#' 1. `known_failed` ticker: `failure_candidate` (override).
#' 2. no bars: `no_bars`.
#' 3. `demotion`: at least one trade strictly after `index_exit_date`. The name
#'    kept trading, so the index exit is not a delisting. Price (upper = lower)
#'    is the close of the last trade ON OR BEFORE the exit date.
#' 4. `too_recent`: the exit is within `too_recent_weekdays` weekdays of the
#'    last date in `bars`, so whether it keeps trading is not yet known. No price.
#' 5. Stopped trading, and `corp_actions` holds a record for the ticker dated
#'    from `ca_days_before` days before the exit to `ca_days_after` days after
#'    it (`ca_source = "corporate_action"`). If several, `name_change` wins, then
#'    `cash_merger`, `stock_and_cash_merger`, `stock_merger`, then the record
#'    closest to the exit:
#'    * `name_change`: `ticker_change`, `new_ticker` = the new symbol, no price
#'      (not an exit; join to the new ticker).
#'    * `cash_merger`: `takeover`, upper = lower = the deal price (`rate`).
#'    * `stock_merger` / `stock_and_cash_merger`: `takeover` at the last close,
#'      with `acquirer`, `acquirer_rate` and `cash_rate` recorded.
#'    A `spin_off` record alone classifies nothing.
#' 6. Stopped trading, no record (`ca_source = "rule"`): `failure_candidate` if
#'    the RELATIVE fall over `crash_lookback` trading days to the last trade,
#'    on ADJUSTED closes, is worse than `-crash_drop`; upper = last close,
#'    lower = 0. Otherwise `takeover` at the last close (also when the fall
#'    cannot be computed: fewer than `crash_lookback + 1` adjusted bars, or no
#'    SPY close).
#'
#' `ret_60d` is the adjusted close at the priced bar over the adjusted close
#' `crash_lookback` trading days earlier, minus 1; `ret_60d_spy` the SPY return
#' over the same two dates; `ret_60d_rel = (1 + ret_60d) / (1 + ret_60d_spy) - 1`
#' (all `NA` when not computable). `last_trade_date` and `last_close` (raw) are
#' the last trade inside the window (after the exit date for a demotion);
#' `gap_trading_days` counts weekdays from it to the exit (0 if on or after;
#' holidays not removed) and is informational only.
#'
#' @param bars Output of [hd_alpaca_bars()] with raw prices (needs `symbol`,
#'   `date`, `close`, `volume`; no `NA` in those).
#' @param bars_adj The same for `adjustment = "all"`, for the exit tickers AND
#'   `SPY` (aborts without SPY rows).
#' @param corp_actions Output of `hd_alpaca_corporate_actions()` (needs the
#'   columns of that function).
#' @param exits Output of [hd_sp500_exits()] (needs `ticker`,
#'   `first_member_date`, `index_exit_date`; one row per ticker).
#' @param known_failed Character vector of tickers known to have failed
#'   (e.g. `hd_sp500_known_delisted()$ticker`); they are forced to
#'   `exit_type = "failure_candidate"`.
#' @param rule Rule constants. Defaults to [hd_alpaca_exit_rule()].
#' @return A tibble, one row per exit: `ticker`, `index_exit_date`, `exit_type`,
#'   `new_ticker`, `ca_source` (`"corporate_action"` when a record decided the
#'   type, `"rule"` otherwise, `NA` for `no_bars`), `acquirer`, `acquirer_rate`,
#'   `cash_rate`, `last_trade_date`, `last_close`, `gap_trading_days`,
#'   `ret_60d`, `ret_60d_spy`, `ret_60d_rel`, `failure_candidate`
#'   (`exit_type == "failure_candidate"`; `NA` for `no_bars` and `too_recent`,
#'   where it is unknown), `exit_price_upper`, `exit_price_lower`, `has_bars`.
#' @family alpaca
#' @export
hd_alpaca_exit_prices <- function(bars, bars_adj, corp_actions, exits,
                                  known_failed = character(),
                                  rule = hd_alpaca_exit_rule()) {
  .hd_check_exit_bars(bars, "bars")
  .hd_check_exit_bars(bars_adj, "bars_adj")
  need_c <- names(.hd_alpaca_empty_corp_actions())
  if (!is.data.frame(corp_actions) || !all(need_c %in% names(corp_actions)) ||
      !inherits(corp_actions$effective_date, "Date") ||
      !inherits(corp_actions$process_date, "Date") ||
      !is.character(corp_actions$type) || !is.character(corp_actions$symbol)) {
    cli::cli_abort(c(
      "x" = "{.arg corp_actions} must be a data frame with {.field {need_c}}.",
      "i" = "Build it with {.fn hd_alpaca_corporate_actions}."
    ))
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
  spy <- bars_adj[bars_adj$symbol == "SPY", , drop = FALSE]
  if (nrow(spy) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg bars_adj} has no {.val SPY} rows, so the relative fall cannot be computed.",
      "i" = "Fetch them with {.code Rscript scripts/fetch_alpaca_exit_bars.R}."
    ))
  }
  spy <- spy[order(spy$date), , drop = FALSE]
  spy <- spy[!duplicated(spy$date), , drop = FALSE]
  spy_dates <- as.numeric(spy$date)
  # SPY close on the last trading day on or before `d`.
  spy_at <- function(d) {
    if (is.na(d)) return(NA_real_)
    j <- findInterval(as.numeric(d), spy_dates)
    if (j == 0L) NA_real_ else spy$close[j]
  }

  last_bar_date <- if (nrow(bars) > 0L) max(bars$date) else as.Date(NA)

  # Corporate-action records the rule can use, by symbol.
  ca_prio <- c("name_change", "cash_merger", "stock_and_cash_merger", "stock_merger")
  ca <- corp_actions[corp_actions$type %in% ca_prio, , drop = FALSE]
  ca$event_date <- dplyr::coalesce(ca$effective_date, ca$process_date)
  ca <- ca[!is.na(ca$symbol) & !is.na(ca$event_date), , drop = FALSE]
  ca_by <- split(ca, ca$symbol)
  pick_record <- function(tk, exit_d) {
    r <- ca_by[[tk]]
    if (is.null(r)) return(NULL)
    r <- r[r$event_date >= exit_d - rule$ca_days_before &
             r$event_date <= exit_d + rule$ca_days_after, , drop = FALSE]
    if (nrow(r) == 0L) return(NULL)
    r <- r[order(match(r$type, ca_prio), abs(as.numeric(r$event_date - exit_d))), , drop = FALSE]
    r[1L, , drop = FALSE]
  }

  by_sym <- split(bars, bars$symbol)
  by_adj <- split(bars_adj, bars_adj$symbol)
  rows <- lapply(seq_len(nrow(exits)), function(i) {
    tk <- exits$ticker[i]
    exit_d <- exits$index_exit_date[i]
    lo <- max(rule$panel_start, exits$first_member_date[i]) - rule$window_days
    hi <- exit_d + rule$window_days
    clip <- function(b) {
      if (is.null(b)) return(NULL)
      b <- b[b$date >= lo & b$date <= hi & b$volume > 0, , drop = FALSE]
      b[order(b$date), , drop = FALSE]
    }
    b <- clip(by_sym[[tk]])
    ba <- clip(by_adj[[tk]])
    known <- tk %in% known_failed
    n <- if (is.null(b)) 0L else nrow(b)
    if (n == 0L) {
      return(tibble::tibble(
        ticker = tk, index_exit_date = exit_d,
        exit_type = if (known) "failure_candidate" else "no_bars",
        new_ticker = NA_character_,
        ca_source = if (known) "rule" else NA_character_,
        acquirer = NA_character_, acquirer_rate = NA_real_, cash_rate = NA_real_,
        last_trade_date = as.Date(NA), last_close = NA_real_,
        gap_trading_days = NA_integer_, ret_60d = NA_real_,
        ret_60d_spy = NA_real_, ret_60d_rel = NA_real_,
        failure_candidate = if (known) TRUE else NA,
        exit_price_upper = NA_real_,
        exit_price_lower = if (known) 0 else NA_real_,
        has_bars = FALSE
      ))
    }
    last_d <- b$date[n]
    last_c <- b$close[n]
    gap <- .hd_weekdays_after(last_d, exit_d)
    after <- b$date > exit_d
    # Priced bar: the last trade on or before the exit date for a name that
    # kept trading, else the last trade. NA if every trade is after the exit.
    px_i <- if (any(after)) {
      on_or_before <- which(!after)
      if (length(on_or_before) > 0L) max(on_or_before) else NA_integer_
    } else {
      n
    }
    px_c <- if (is.na(px_i)) NA_real_ else b$close[px_i]
    px_d <- if (is.na(px_i)) as.Date(NA) else b$date[px_i]

    # Adjusted fall over `crash_lookback` trading days to the priced bar, and
    # SPY over the same two dates.
    ret <- ret_spy <- ret_rel <- NA_real_
    j <- if (is.null(ba) || is.na(px_d)) NA_integer_ else match(px_d, ba$date)
    if (!is.na(j) && j > rule$crash_lookback) {
      d0 <- ba$date[j - rule$crash_lookback]
      ret <- ba$close[j] / ba$close[j - rule$crash_lookback] - 1
      s0 <- spy_at(d0)
      s1 <- spy_at(px_d)
      if (!is.na(s0) && !is.na(s1)) {
        ret_spy <- s1 / s0 - 1
        ret_rel <- (1 + ret) / (1 + ret_spy) - 1
      }
    }

    new_tk <- NA_character_
    src <- "rule"
    rec <- NULL
    type <- if (known) {
      "failure_candidate"
    } else if (any(after)) {
      "demotion"
    } else if (!is.na(last_bar_date) &&
               .hd_weekdays_after(exit_d, last_bar_date) <= rule$too_recent_weekdays) {
      "too_recent"
    } else {
      rec <- pick_record(tk, exit_d)
      if (!is.null(rec)) {
        src <- "corporate_action"
        if (rec$type == "name_change") {
          new_tk <- rec$new_symbol
          "ticker_change"
        } else {
          "takeover"
        }
      } else if (isTRUE(ret_rel < -rule$crash_drop)) {
        "failure_candidate"
      } else {
        "takeover"
      }
    }

    priced <- type %in% c("failure_candidate", "demotion", "takeover")
    up <- if (priced) px_c else NA_real_
    low <- if (!priced) NA_real_ else if (type == "failure_candidate") 0 else px_c
    acq <- NA_character_
    acq_rate <- cash_rate <- NA_real_
    if (!is.null(rec) && type == "takeover") {
      if (rec$type == "cash_merger") {
        up <- low <- rec$rate
        cash_rate <- rec$rate
      } else {
        acq <- rec$acquirer_symbol
        acq_rate <- rec$acquirer_rate
        cash_rate <- rec$cash_rate
      }
    }
    tibble::tibble(
      ticker = tk, index_exit_date = exit_d,
      exit_type = type, new_ticker = new_tk, ca_source = src,
      acquirer = acq, acquirer_rate = acq_rate, cash_rate = cash_rate,
      last_trade_date = last_d, last_close = last_c,
      gap_trading_days = gap, ret_60d = ret,
      ret_60d_spy = ret_spy, ret_60d_rel = ret_rel,
      failure_candidate = if (type == "too_recent") NA else type == "failure_candidate",
      exit_price_upper = up, exit_price_lower = low,
      has_bars = TRUE
    )
  })
  out <- dplyr::bind_rows(rows)
  if (nrow(out) == 0L) {
    return(tibble::tibble(
      ticker = character(), index_exit_date = as.Date(character()),
      exit_type = character(), new_ticker = character(), ca_source = character(),
      acquirer = character(), acquirer_rate = double(), cash_rate = double(),
      last_trade_date = as.Date(character()), last_close = double(),
      gap_trading_days = integer(), ret_60d = double(),
      ret_60d_spy = double(), ret_60d_rel = double(),
      failure_candidate = logical(), exit_price_upper = double(),
      exit_price_lower = double(), has_bars = logical()
    ))
  }
  out[order(out$index_exit_date, out$ticker), , drop = FALSE]
}

#' The exit types `hd_alpaca_exit_prices()` can return
#' @return Character vector.
#' @keywords internal
.hd_alpaca_exit_types <- function() {
  c("demotion", "ticker_change", "failure_candidate", "takeover",
    "too_recent", "no_bars")
}

#' Exit-price coverage by index-exit year
#'
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @return A tibble: `exit_year`, `n_exits`, `n_with_bars`,
#'   `n_failure_candidates` (count of `TRUE`; `NA` is not counted), one
#'   `n_<exit_type>` column per exit type (demotion, ticker_change,
#'   failure_candidate, takeover, too_recent, no_bars), then `n_ca_corporate_action`
#'   and `n_ca_rule` (exits decided by a corporate-action record vs by the rule;
#'   `no_bars` is in neither).
#' @family alpaca
#' @export
hd_alpaca_exit_coverage <- function(exit_prices) {
  need <- c("index_exit_date", "has_bars", "failure_candidate", "exit_type", "ca_source")
  if (!is.data.frame(exit_prices) || !all(need %in% names(exit_prices)) ||
      !inherits(exit_prices$index_exit_date, "Date") || anyNA(exit_prices$index_exit_date)) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field {need}} and no missing exit date.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ))
  }
  yr <- as.integer(format(exit_prices$index_exit_date, "%Y"))
  years <- sort(unique(yr))
  out <- tibble::tibble(
    exit_year            = years,
    n_exits              = as.integer(vapply(years, function(y) sum(yr == y), numeric(1))),
    n_with_bars          = as.integer(vapply(years, function(y) sum(yr == y & exit_prices$has_bars), numeric(1))),
    n_failure_candidates = as.integer(vapply(years, function(y) sum(yr == y & exit_prices$failure_candidate %in% TRUE), numeric(1)))
  )
  for (ty in .hd_alpaca_exit_types()) {
    out[[paste0("n_", ty)]] <- as.integer(vapply(
      years, function(y) sum(yr == y & exit_prices$exit_type %in% ty), numeric(1)
    ))
  }
  for (src in c("corporate_action", "rule")) {
    out[[paste0("n_ca_", src)]] <- as.integer(vapply(
      years, function(y) sum(yr == y & exit_prices$ca_source %in% src), numeric(1)
    ))
  }
  out
}

#' Positive control for the exit-type rule against named real cases
#'
#' Real S&P 500 leavers whose true fate is known (checked by hand, #1041):
#' SIVB, FRC, SBNY failed; TWTR (cash deal, 54.20 a share), NBL (stock deal,
#' acquirer CVX), ATVI, CELG, JNPR, RTN, DWDP were taken over or merged (DWDP
#' was a spin-off, not a loss); XEC, ARNC, M, AIV, LUMN were demoted and kept
#' trading; FI became FISV and UTX became RTX. The function compares
#' `exit_type`, `new_ticker`, and, where the truth names one, `acquirer` and
#' `exit_price_upper`, for each control present in `exit_prices`.
#'
#' Aborts, listing every mismatch, if any present control disagrees. Controls
#' absent from `exit_prices` are reported (a message), never passed silently;
#' if fewer than `min_present` of them are present the check is INDETERMINATE
#' and aborts too.
#'
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @param min_present Minimum number of controls that must be present.
#' @return A tibble, one row per control: `ticker`, `expected`,
#'   `expected_new_ticker`, `expected_acquirer`, `expected_price`, `observed`,
#'   `observed_new_ticker`, `observed_acquirer`, `observed_price`, `status`
#'   (`"PASS"`, `"FAIL"`, `"ABSENT"`).
#' @family alpaca
#' @export
hd_alpaca_exit_controls <- function(exit_prices, min_present = 13L) {
  need <- c("ticker", "exit_type", "new_ticker", "acquirer", "exit_price_upper")
  if (!is.data.frame(exit_prices) || !all(need %in% names(exit_prices))) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field {need}}.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ))
  }
  ctl <- tibble::tibble(
    ticker = c("SIVB", "FRC", "SBNY",
               "TWTR", "NBL", "ATVI", "CELG", "JNPR", "RTN", "DWDP",
               "XEC", "ARNC", "M", "AIV", "LUMN",
               "FI", "UTX"),
    expected = c(rep("failure_candidate", 3L), rep("takeover", 7L),
                 rep("demotion", 5L), rep("ticker_change", 2L)),
    expected_new_ticker = c(rep(NA_character_, 15L), "FISV", "RTX"),
    expected_acquirer = c(rep(NA_character_, 4L), "CVX", rep(NA_character_, 12L)),
    expected_price = c(rep(NA_real_, 3L), 54.2, rep(NA_real_, 13L))
  )
  i <- match(ctl$ticker, exit_prices$ticker)
  ctl$observed <- exit_prices$exit_type[i]
  ctl$observed_new_ticker <- exit_prices$new_ticker[i]
  ctl$observed_acquirer <- exit_prices$acquirer[i]
  ctl$observed_price <- exit_prices$exit_price_upper[i]
  # Acquirer and price are checked only where the truth names one.
  acq_ok <- is.na(ctl$expected_acquirer) |
    .hd_both_na_or_equal(ctl$observed_acquirer, ctl$expected_acquirer)
  px_ok <- is.na(ctl$expected_price) |
    (!is.na(ctl$observed_price) & abs(ctl$observed_price - ctl$expected_price) < 1e-6)
  ctl$status <- ifelse(
    is.na(i), "ABSENT",
    ifelse(ctl$observed == ctl$expected &
             .hd_both_na_or_equal(ctl$observed_new_ticker, ctl$expected_new_ticker) &
             acq_ok & px_ok,
           "PASS", "FAIL")
  )
  absent <- ctl$ticker[ctl$status == "ABSENT"]
  if (length(absent) > 0L) {
    cli::cli_inform(c("i" = "{length(absent)} control ticker{?s} not in the exit table (not checked): {.val {absent}}."))
  }
  n_present <- sum(ctl$status != "ABSENT")
  if (n_present < min_present) {
    cli::cli_abort(c(
      "x" = "INDETERMINATE: only {n_present} of {nrow(ctl)} control tickers are present; at least {min_present} are needed.",
      "i" = "Absent: {.val {absent}}."
    ))
  }
  bad <- ctl[ctl$status == "FAIL", , drop = FALSE]
  if (nrow(bad) > 0L) {
    describe <- function(type, new_tk, acq, px) {
      paste0(type,
             ifelse(is.na(new_tk), "", paste0(" -> ", new_tk)),
             ifelse(is.na(acq), "", paste0(" (acquirer ", acq, ")")),
             ifelse(is.na(px), "", paste0(" (price ", format(px), ")")))
    }
    lines <- sprintf(
      "%s: expected %s, got %s", bad$ticker,
      describe(bad$expected, bad$expected_new_ticker, bad$expected_acquirer, bad$expected_price),
      describe(bad$observed, bad$observed_new_ticker,
               ifelse(is.na(bad$expected_acquirer), NA_character_, bad$observed_acquirer),
               ifelse(is.na(bad$expected_price), NA_real_, bad$observed_price))
    )
    cli::cli_abort(c(
      "x" = "Exit-type rule disagrees with {nrow(bad)} named real case{?s}:",
      stats::setNames(lines, rep("*", length(lines)))
    ))
  }
  ctl
}

#' Elementwise equality treating two NAs as equal (internal)
#' @param x,y Vectors of equal length.
#' @return Logical vector.
#' @keywords internal
.hd_both_na_or_equal <- function(x, y) {
  (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
}
