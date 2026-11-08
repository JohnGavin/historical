# Point-in-time monthly returns for S&P 500 members, with exit-month bounds (#1041)
#
# WHAT THIS IS. The monthly return of every stock that was in the S&P 500 at a
# month-end, held over the NEXT month, computed from ONE source (Alpaca
# split- and dividend-adjusted daily bars), so a return never splices two data
# sources. A stock that leaves because it stops trading (takeover, failure) has
# a final held month whose return is a LOWER and an UPPER bound (see
# hd_pit_monthly_returns()). It feeds a report-only measurement of
# survivorship bias and failure sensitivity for the stock MAX strategy; nothing
# here feeds the leaderboard.

#' Next calendar month of a "YYYY-MM" string (internal)
#' @param ym Character vector of "YYYY-MM".
#' @return Character vector of "YYYY-MM", the following month.
#' @keywords internal
.hd_pit_next_ym <- function(ym) {
  y <- as.integer(substr(ym, 1L, 4L))
  m <- as.integer(substr(ym, 6L, 7L))
  sprintf("%04d-%02d", y + (m == 12L), ifelse(m == 12L, 1L, m + 1L))
}

#' Validate the inputs of the point-in-time return functions (internal)
#' @param bars_adj,members,exit_prices See [hd_pit_monthly_returns()].
#' @param call Caller environment for the error.
#' @return `NULL`, invisibly; aborts when invalid.
#' @keywords internal
.hd_pit_check_inputs <- function(bars_adj, members, exit_prices,
                                 call = rlang::caller_env()) {
  .hd_check_exit_bars(bars_adj, "bars_adj", call = call)
  if (nrow(bars_adj) == 0L || !any(bars_adj$volume > 0)) {
    cli::cli_abort(c(
      "x" = "{.arg bars_adj} has no bar with {.field volume} > 0.",
      "i" = "Fetch them with {.code Rscript scripts/fetch_alpaca_member_bars.R}."
    ), call = call)
  }
  if (anyDuplicated(bars_adj[, c("symbol", "date")]) > 0L) {
    cli::cli_abort("{.arg bars_adj} has more than one row for some {.field symbol} and {.field date}.",
                   call = call)
  }
  if (!is.data.frame(members) || !all(c("ticker", "date") %in% names(members)) ||
      !is.character(members$ticker) || !inherits(members$date, "Date") ||
      anyNA(members$ticker) || anyNA(members$date) || nrow(members) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg members} must be a non-empty data frame with character {.field ticker} and Date {.field date} (no NA).",
      "i" = "Use {.fn hd_sp500_pit_universe} output, such as {.code stk_universe_pit}."
    ), call = call)
  }
  need <- c("ticker", "index_exit_date", "exit_type", "new_ticker",
            "last_trade_date", "last_close", "exit_price_upper",
            "exit_price_lower", "has_bars")
  if (!is.data.frame(exit_prices) || !all(need %in% names(exit_prices)) ||
      !is.character(exit_prices$ticker) || !is.character(exit_prices$exit_type) ||
      !inherits(exit_prices$index_exit_date, "Date") ||
      !inherits(exit_prices$last_trade_date, "Date") ||
      !is.logical(exit_prices$has_bars)) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field {need}}.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ), call = call)
  }
  if (anyNA(exit_prices$ticker) || anyDuplicated(exit_prices$ticker) > 0L) {
    cli::cli_abort("{.arg exit_prices} must have one row per ticker and no missing ticker.",
                   call = call)
  }
  priced <- exit_prices$exit_type %in% c("takeover", "failure_candidate") &
    exit_prices$has_bars %in% TRUE
  bad <- priced & (is.na(exit_prices$last_trade_date) | is.na(exit_prices$last_close) |
                     is.na(exit_prices$exit_price_upper) |
                     is.na(exit_prices$exit_price_lower) |
                     !(exit_prices$last_close > 0))
  if (any(bad)) {
    cli::cli_abort(c(
      "x" = "{sum(bad)} takeover or failure exit{?s} cannot be priced: {.val {exit_prices$ticker[bad]}}.",
      "i" = "Each needs {.field last_trade_date}, a positive {.field last_close}, {.field exit_price_upper} and {.field exit_price_lower}."
    ), call = call)
  }
  invisible(NULL)
}

#' Permanent security id: the end of each ticker-change chain (internal)
#'
#' Follows `exit_type == "ticker_change"` rows (`ticker` to `new_ticker`)
#' repeatedly, so a company renamed twice maps to its last ticker. A ticker
#' that was never renamed maps to itself.
#' @param tickers Character vector.
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @param call Caller environment for the error.
#' @return Character vector the length of `tickers`. Aborts on a cycle.
#' @keywords internal
.hd_pit_permanent_id <- function(tickers, exit_prices, call = rlang::caller_env()) {
  rn <- exit_prices[exit_prices$exit_type %in% "ticker_change" &
                      !is.na(exit_prices$new_ticker), , drop = FALSE]
  nxt <- stats::setNames(rn$new_ticker, rn$ticker)
  resolve <- function(tk) {
    seen <- tk
    while (tk %in% names(nxt)) {
      tk <- nxt[[tk]]
      if (tk %in% seen) {
        cli::cli_abort(c(
          "x" = "Ticker-change chain has a cycle: {.val {c(seen, tk)}}.",
          "i" = "A rename must lead to a ticker that is not renamed back; check {.field new_ticker} in {.arg exit_prices}."
        ), call = call)
      }
      seen <- c(seen, tk)
    }
    tk
  }
  starts <- unique(c(names(nxt), tickers))
  map <- stats::setNames(vapply(starts, resolve, character(1)), starts)
  unname(map[tickers])
}

#' Chain-link the bars of one security that traded under several symbols (internal)
#'
#' Adjusted series of two symbols are adjusted independently, so their levels
#' need not match at a rename. The later symbol is rescaled so its first close
#' equals the earlier one's last close (the overnight return across the switch
#' is taken as zero); the earlier symbol is cut off where the later starts.
#' @param d Rows of one security: `symbol`, `date`, `close`, `ticker`.
#' @return A tibble: `ticker`, `date`, `adj_close`.
#' @keywords internal
.hd_pit_splice <- function(d) {
  d <- d[order(d$date), , drop = FALSE]
  syms <- unique(d$symbol)
  out <- d[d$symbol == syms[1L], , drop = FALSE]
  for (s in syms[-1L]) {
    nb <- d[d$symbol == s, , drop = FALSE]
    out <- out[out$date < nb$date[1L], , drop = FALSE]
    if (nrow(out) > 0L) nb$close <- nb$close * out$close[nrow(out)] / nb$close[1L]
    out <- rbind(out, nb)
  }
  tibble::tibble(ticker = out$ticker[1L], date = out$date, adj_close = out$close)
}

#' The spliced adjusted-price series, without validation (internal)
#' @inheritParams hd_pit_price_series
#' @param call Caller environment for errors.
#' @return See [hd_pit_price_series()].
#' @keywords internal
.hd_pit_series <- function(bars_adj, exit_prices, call = rlang::caller_env()) {
  b <- bars_adj[bars_adj$volume > 0, c("symbol", "date", "close"), drop = FALSE]
  b$ticker <- .hd_pit_permanent_id(b$symbol, exit_prices, call = call)
  out <- dplyr::bind_rows(lapply(split(b, b$ticker), .hd_pit_splice))
  if (nrow(out) == 0L) {
    return(tibble::tibble(ticker = character(), date = as.Date(character()),
                          adj_close = double()))
  }
  # A takeover or failure ends at its last trade: later bars (a stale tail) go.
  cl <- exit_prices[exit_prices$exit_type %in% c("takeover", "failure_candidate") &
                      exit_prices$has_bars %in% TRUE &
                      !is.na(exit_prices$last_trade_date), , drop = FALSE]
  if (nrow(cl) > 0L) {
    lim <- stats::setNames(cl$last_trade_date,
                           .hd_pit_permanent_id(cl$ticker, exit_prices, call = call))
    i <- match(out$ticker, names(lim))
    out <- out[is.na(i) | out$date <= lim[i], , drop = FALSE]
  }
  out[order(out$ticker, out$date), , drop = FALSE]
}

#' One adjusted-price series per security
#'
#' Daily split- and dividend-adjusted closes (bars with `volume > 0` only),
#' keyed by a permanent id: every ticker-change chain (`exit_type ==
#' "ticker_change"` rows of `exit_prices`) is one security, identified by the
#' LAST ticker of the chain, and a cycle aborts. The bars of the symbols of one
#' security are chain-linked (the later symbol rescaled so the series is
#' continuous across the switch). A `takeover` or `failure_candidate` series
#' ends at its `last_trade_date`.
#'
#' @inheritParams hd_pit_monthly_returns
#' @return A tibble: `ticker` (permanent id), `date` (Date), `adj_close`,
#'   ordered by ticker then date.
#' @family pit
#' @export
hd_pit_price_series <- function(bars_adj, exit_prices) {
  .hd_check_exit_bars(bars_adj, "bars_adj")
  if (!is.data.frame(exit_prices) ||
      !all(c("ticker", "exit_type", "new_ticker", "last_trade_date", "has_bars") %in%
           names(exit_prices))) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field ticker}, {.field exit_type}, {.field new_ticker}, {.field last_trade_date} and {.field has_bars}.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ))
  }
  .hd_pit_series(bars_adj, exit_prices)
}

#' Point-in-time monthly returns for S&P 500 members, with exit bounds
#'
#' One row per security and HELD month. A security is in the universe at the
#' end of month `signal_ym` if it was a member on the last membership snapshot
#' on or before the last trading day of that month (the last date any bar
#' trades). It is held over the next month `ym`: signal at `signal_ym`, return
#' at `ym`, as `stk_max_portfolio` lags its MAX signal. `ym` is therefore the
#' HELD (return) month and `signal_ym` the month of membership and signal.
#'
#' Return rules (all on split- and dividend-adjusted closes):
#' \itemize{
#'   \item Normal month: `adj_close(ym end) / adj_close(signal_ym end) - 1`,
#'     identical for `ret_upper` and `ret_lower`.
#'   \item `demotion`: the stock keeps trading, so its real return is used; it
#'     leaves the universe afterwards. Its final held month is tagged.
#'   \item `takeover` and `failure_candidate` (the bars stop): in the held month
#'     that contains the last trade,
#'     `ret_b = (adj_last / adj_signal_end) * (exit_price_b / last_close) - 1`
#'     for `b` in upper and lower. The ratio is of RAW prices, both from
#'     `exit_prices`, applied to the ADJUSTED path. A failure candidate's lower
#'     bound is `exit_price_lower = 0`, so `ret_lower = -1` in that month. No
#'     later rows exist.
#'   \item `ticker_change`: old and new ticker are one security (see
#'     [hd_pit_price_series()]); a rename never produces an exit.
#' }
#'
#' Securities that cannot be handled are EXCLUDED and COUNTED, never dropped
#' silently: they are listed in `attr(x, "excluded")` (columns `ticker`,
#' `reason`): `no_bars` (leaver with no bars, mostly before the Alpaca history
#' starts), `failure_no_bars` (a known failure with no bars, which understates
#' failures), `too_recent` (exit too recent to classify), `member_no_bars` (a
#' member the bars do not cover and `exit_prices` does not list),
#' `exit_bar_missing` (a takeover or failure whose last-trade bar is absent
#' from `bars_adj`), `rename_no_new_bars` (a renamed ticker whose new symbol has
#' no bars of its own).
#'
#' @param bars_adj Adjusted daily bars (`adjustment = "all"`) as from
#'   [hd_alpaca_bars()]: `symbol`, `date`, `close`, `volume`, no `NA`, one row per
#'   symbol and date. Only `volume > 0` bars count as trades.
#' @param members Membership snapshots (`ticker`, Date `date`), such as
#'   `hd_sp500_pit_universe()` output. A member stays a member until the next
#'   snapshot that omits it.
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @return A tibble: `ticker` (permanent id), `signal_ym`, `ym` (held month),
#'   `signal_date` (last bar of the signal month), `date` (last bar of the held
#'   month; the last trade in an exit month), `ret_upper`, `ret_lower`,
#'   `exit_type` (`NA` except in a security's final held month, when it is
#'   `takeover`, `failure_candidate` or `demotion`), ordered by `ym` then
#'   `ticker`; with the attribute `excluded`.
#' @family pit
#' @export
hd_pit_monthly_returns <- function(bars_adj, members, exit_prices) {
  .hd_pit_check_inputs(bars_adj, members, exit_prices)
  this_call <- rlang::current_env()
  pid <- function(x) .hd_pit_permanent_id(x, exit_prices, call = this_call)
  ser <- .hd_pit_series(bars_adj, exit_prices)
  ser$ym <- format(ser$date, "%Y-%m")

  # Month calendar: the last date any bar trades in each month.
  traded <- bars_adj[bars_adj$volume > 0, , drop = FALSE]
  cal_max <- tapply(as.numeric(traded$date), format(traded$date, "%Y-%m"), max)
  cal <- tibble::tibble(ym = names(cal_max),
                        cal_date = as.Date(unname(cal_max), origin = "1970-01-01"))

  # Members by snapshot, under the permanent id.
  mem <- tibble::tibble(ticker = pid(members$ticker), date = members$date)
  mem <- mem[!duplicated(mem), , drop = FALSE]
  snaps <- sort(unique(mem$date))
  by_snap <- split(mem$ticker, factor(as.numeric(mem$date), levels = as.numeric(snaps)))

  # Exclusions, with a reason each.
  all_perm <- unique(mem$ticker)
  own <- exit_prices[exit_prices$ticker == pid(exit_prices$ticker), , drop = FALSE]
  own_i <- match(all_perm, own$ticker)
  own_type <- own$exit_type[own_i]
  own_bars <- own$has_bars[own_i]
  renamed_to <- unique(pid(exit_prices$new_ticker[exit_prices$exit_type %in% "ticker_change" &
                                                    !is.na(exit_prices$new_ticker)]))
  has_series <- all_perm %in% ser$ticker
  last_bar <- tapply(as.numeric(ser$date), ser$ticker, max)
  last_bar_p <- as.numeric(last_bar[all_perm])
  own_ltd <- as.numeric(own$last_trade_date[own_i])
  reason <- rep(NA_character_, length(all_perm))
  reason[!is.na(own_type) & own_type == "too_recent"] <- "too_recent"
  no_bars <- is.na(reason) & !has_series
  reason[no_bars] <- ifelse(
    !is.na(own_type[no_bars]) & own_type[no_bars] == "failure_candidate" &
      !(own_bars[no_bars] %in% TRUE), "failure_no_bars",
    ifelse(!is.na(own_type[no_bars]) & (own_type[no_bars] == "no_bars" |
                                         !(own_bars[no_bars] %in% TRUE)),
           "no_bars", "member_no_bars")
  )
  miss <- is.na(reason) & has_series & own_type %in% c("takeover", "failure_candidate") &
    own_bars %in% TRUE & (is.na(last_bar_p) | last_bar_p != own_ltd)
  reason[miss] <- "exit_bar_missing"
  rn <- is.na(reason) & has_series & all_perm %in% renamed_to &
    !(all_perm %in% bars_adj$symbol[bars_adj$volume > 0])
  reason[rn] <- "rename_no_new_bars"
  excluded <- tibble::tibble(ticker = all_perm[!is.na(reason)],
                             reason = reason[!is.na(reason)])
  excluded <- excluded[order(excluded$reason, excluded$ticker), , drop = FALSE]

  # Universe at each signal month-end.
  j <- findInterval(as.numeric(cal$cal_date), as.numeric(snaps))
  uni <- dplyr::bind_rows(lapply(which(j > 0L), function(i) {
    tibble::tibble(ticker = by_snap[[j[i]]], signal_ym = cal$ym[i])
  }))
  empty <- tibble::tibble(
    ticker = character(), signal_ym = character(), ym = character(),
    signal_date = as.Date(character()), date = as.Date(character()),
    ret_upper = double(), ret_lower = double(), exit_type = character()
  )
  if (nrow(uni) == 0L) {
    attr(empty, "excluded") <- excluded
    return(empty)
  }
  uni <- uni[!(uni$ticker %in% excluded$ticker), , drop = FALSE]
  uni$ym <- .hd_pit_next_ym(uni$signal_ym)

  # Month-end price of every security.
  key <- paste(ser$ticker, ser$ym, sep = "|")
  me <- ser[!duplicated(key, fromLast = TRUE), c("ticker", "ym", "date", "adj_close")]
  sig <- stats::setNames(me, c("ticker", "signal_ym", "signal_date", "signal_px"))
  held <- stats::setNames(me, c("ticker", "ym", "date", "held_px"))
  out <- dplyr::inner_join(uni, sig, by = c("ticker", "signal_ym"))
  out <- dplyr::inner_join(out, held, by = c("ticker", "ym"))
  if (nrow(out) == 0L) {
    attr(empty, "excluded") <- excluded
    return(empty)
  }

  # Exit month: the held month containing the last trade of a takeover/failure.
  cl <- exit_prices[exit_prices$exit_type %in% c("takeover", "failure_candidate") &
                      exit_prices$has_bars %in% TRUE, , drop = FALSE]
  cl_perm <- pid(cl$ticker)
  k <- match(out$ticker, cl_perm)
  is_exit <- !is.na(k) & out$ym == format(cl$last_trade_date[k], "%Y-%m")
  mult_up <- ifelse(is_exit, cl$exit_price_upper[k] / cl$last_close[k], 1)
  mult_lo <- ifelse(is_exit, cl$exit_price_lower[k] / cl$last_close[k], 1)

  dm <- exit_prices[exit_prices$exit_type %in% "demotion", , drop = FALSE]
  dm_perm <- pid(dm$ticker)
  d <- match(out$ticker, dm_perm)
  is_dm <- !is.na(d) & out$ym == format(dm$index_exit_date[d], "%Y-%m")

  out$ret_upper <- out$held_px / out$signal_px * mult_up - 1
  out$ret_lower <- out$held_px / out$signal_px * mult_lo - 1
  out$exit_type <- ifelse(is_exit, cl$exit_type[k], ifelse(is_dm, "demotion", NA_character_))
  out <- out[order(out$ym, out$ticker),
             c("ticker", "signal_ym", "ym", "signal_date", "date",
               "ret_upper", "ret_lower", "exit_type")]
  out <- tibble::as_tibble(out)
  attr(out, "excluded") <- excluded
  out
}
