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
# THE RULE (owner-approved 2026-11-08 after the first rule, a trading-gap test
# plus a 50% fall, misclassified 9 of 15 flags on real data). See
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
#'   \item{`crash_drop`}{A name that stopped trading and whose close fell by
#'     MORE than this fraction over `crash_lookback` trading days to its last
#'     trade is a failure candidate. 0.30: the real failures fell 43% (SBNY) to
#'     98% (FRC), the real takeovers moved -2% to +31%.}
#'   \item{`crash_lookback`}{Trading days (bars with volume > 0) for the drop.}
#'   \item{`too_recent_weekdays`}{An exit within this many weekdays of the last
#'     date in the fetched bars cannot yet be told from a demotion.}
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
    crash_drop          = 0.30,
    crash_lookback      = 60L,
    too_recent_weekdays = 5L
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

#' Normalise a company name for matching (internal)
#'
#' Lower-case, punctuation to spaces, then repeatedly drop a leading "the" and
#' trailing share-class / legal-form words (common stock, ordinary shares,
#' class a/b/c, incorporated, corporation, company, holdings, inc, corp, co,
#' ltd, plc). "Fiserv, Inc." and "Fiserv, Inc. Common Stock" both become
#' "fiserv".
#' @param x Character vector.
#' @return Character vector (`NA` stays `NA`).
#' @keywords internal
.hd_normalise_company_name <- function(x) {
  one <- function(s) {
    if (is.na(s)) return(NA_character_)
    s <- tolower(s)
    s <- gsub("[[:punct:]]+", " ", s)
    s <- trimws(gsub("[[:space:]]+", " ", s))
    repeat {
      before <- s
      s <- sub("^the ", "", s)
      s <- sub(" (common stock|ordinary shares|class [abc]|incorporated|corporation|company|holdings|inc|corp|co|ltd|plc|the)$", "", s)
      if (identical(s, before)) break
    }
    s
  }
  vapply(as.character(x), one, character(1), USE.NAMES = FALSE)
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
#' 5. `ticker_change`: stopped trading, and exactly one ACTIVE asset with a
#'    different symbol has the same normalised company name as this symbol
#'    (see `.hd_normalise_company_name()`). `new_ticker` names it. No price: it
#'    is not an exit, join to the new ticker. Several active matches:
#'    `ticker_change_ambiguous`, nothing chosen, no price.
#' 6. `failure_candidate`: stopped trading, `ret_60d < -crash_drop`. Upper =
#'    last close, lower = 0.
#' 7. `takeover`: stopped trading otherwise. Upper = lower = last close.
#'
#' `ret_60d` is the close at the priced bar over the close `crash_lookback`
#' trading days earlier, minus 1 (`NA` with fewer bars). `last_trade_date` and
#' `last_close` are the last trade inside the window (after the exit date for a
#' demotion); `gap_trading_days` counts weekdays from it to the exit (0 if on or
#' after; holidays not removed) and is informational only.
#'
#' @param bars Output of [hd_alpaca_bars()] (needs `symbol`, `date`, `close`,
#'   `volume`; no `NA` in `date`, `close`, `volume`).
#' @param exits Output of [hd_sp500_exits()] (needs `ticker`,
#'   `first_member_date`, `index_exit_date`; one row per ticker).
#' @param assets Alpaca assets, status active and inactive (needs character
#'   `symbol`, `name`, `status`), as saved by `scripts/fetch_alpaca_exit_bars.R`.
#'   Used only to detect ticker changes.
#' @param known_failed Character vector of tickers known to have failed
#'   (e.g. `hd_sp500_known_delisted()$ticker`); they are forced to
#'   `exit_type = "failure_candidate"`.
#' @param rule Rule constants. Defaults to [hd_alpaca_exit_rule()].
#' @return A tibble, one row per exit: `ticker`, `index_exit_date`, `exit_type`,
#'   `new_ticker`, `last_trade_date`, `last_close`, `gap_trading_days`,
#'   `ret_60d`, `failure_candidate` (`exit_type == "failure_candidate"`; `NA`
#'   for `no_bars` and `too_recent`, where it is unknown), `exit_price_upper`,
#'   `exit_price_lower`, `has_bars`.
#' @family alpaca
#' @export
hd_alpaca_exit_prices <- function(bars, exits, assets, known_failed = character(),
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
  need_a <- c("symbol", "name", "status")
  if (!is.data.frame(assets) || !all(need_a %in% names(assets)) ||
      !is.character(assets$symbol) || !is.character(assets$name) ||
      !is.character(assets$status)) {
    cli::cli_abort(c(
      "x" = "{.arg assets} must be a data frame with character {.field {need_a}}.",
      "i" = "Fetch it with {.code Rscript scripts/fetch_alpaca_exit_bars.R}."
    ))
  }
  if (!is.character(known_failed) || anyNA(known_failed)) {
    cli::cli_abort("{.arg known_failed} must be a character vector without NA.")
  }
  need_r <- names(hd_alpaca_exit_rule())
  if (!is.list(rule) || !all(need_r %in% names(rule))) {
    cli::cli_abort("{.arg rule} must be a list with {.field {need_r}}; see {.fn hd_alpaca_exit_rule}.")
  }

  a_sym <- assets$symbol
  a_nm <- .hd_normalise_company_name(assets$name)
  a_active <- assets$status %in% "active"
  last_bar_date <- if (nrow(bars) > 0L) max(bars$date) else as.Date(NA)

  # Active assets under a different symbol with the same normalised name.
  active_matches <- function(tk) {
    nm <- unique(a_nm[a_sym == tk & !is.na(a_nm) & nzchar(a_nm)])
    if (length(nm) == 0L) return(character())
    unique(a_sym[a_active & a_sym != tk & !is.na(a_nm) & a_nm %in% nm])
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
        exit_type = if (known) "failure_candidate" else "no_bars",
        new_ticker = NA_character_,
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
    ret <- if (!is.na(px_i) && px_i > rule$crash_lookback) {
      px_c / b$close[px_i - rule$crash_lookback] - 1
    } else {
      NA_real_
    }

    new_tk <- NA_character_
    type <- if (known) {
      "failure_candidate"
    } else if (any(after)) {
      "demotion"
    } else if (!is.na(last_bar_date) &&
               .hd_weekdays_after(exit_d, last_bar_date) <= rule$too_recent_weekdays) {
      "too_recent"
    } else {
      m <- active_matches(tk)
      if (length(m) == 1L) {
        new_tk <- m
        "ticker_change"
      } else if (length(m) > 1L) {
        "ticker_change_ambiguous"
      } else if (isTRUE(ret < -rule$crash_drop)) {
        "failure_candidate"
      } else {
        "takeover"
      }
    }

    priced <- type %in% c("failure_candidate", "demotion", "takeover")
    tibble::tibble(
      ticker = tk, index_exit_date = exit_d,
      exit_type = type, new_ticker = new_tk,
      last_trade_date = last_d, last_close = last_c,
      gap_trading_days = gap, ret_60d = ret,
      failure_candidate = if (type == "too_recent") NA else type == "failure_candidate",
      exit_price_upper = if (priced) px_c else NA_real_,
      exit_price_lower = if (!priced) NA_real_ else if (type == "failure_candidate") 0 else px_c,
      has_bars = TRUE
    )
  })
  out <- dplyr::bind_rows(rows)
  if (nrow(out) == 0L) {
    return(tibble::tibble(
      ticker = character(), index_exit_date = as.Date(character()),
      exit_type = character(), new_ticker = character(),
      last_trade_date = as.Date(character()), last_close = double(),
      gap_trading_days = integer(), ret_60d = double(),
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
  c("demotion", "ticker_change", "ticker_change_ambiguous",
    "failure_candidate", "takeover", "too_recent", "no_bars")
}

#' Exit-price coverage by index-exit year
#'
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @return A tibble: `exit_year`, `n_exits`, `n_with_bars`,
#'   `n_failure_candidates` (count of `TRUE`; `NA` is not counted), then one
#'   `n_<exit_type>` column per exit type (demotion, ticker_change,
#'   ticker_change_ambiguous, failure_candidate, takeover, too_recent, no_bars).
#' @family alpaca
#' @export
hd_alpaca_exit_coverage <- function(exit_prices) {
  need <- c("index_exit_date", "has_bars", "failure_candidate", "exit_type")
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
  out
}

#' Positive control for the exit-type rule against named real cases
#'
#' Real S&P 500 leavers whose true fate is known (checked by hand on the
#' 2026-11-08 build, #1041): SIVB, FRC, SBNY failed; TWTR, ATVI, CELG, NBL, JNPR
#' were taken over; XEC, ARNC, M, AIV, LUMN were demoted and kept trading; FI
#' became FISV. The function compares `exit_type` (and `new_ticker` for FI) with
#' that truth for each control present in `exit_prices`.
#'
#' Aborts, listing every mismatch, if any present control disagrees. Controls
#' absent from `exit_prices` are reported (a message), never passed silently;
#' if fewer than `min_present` of them are present the check is INDETERMINATE
#' and aborts too.
#'
#' @param exit_prices Output of [hd_alpaca_exit_prices()].
#' @param min_present Minimum number of controls that must be present.
#' @return A tibble, one row per control: `ticker`, `expected`,
#'   `expected_new_ticker`, `observed`, `observed_new_ticker`, `status`
#'   (`"PASS"`, `"FAIL"`, `"ABSENT"`).
#' @family alpaca
#' @export
hd_alpaca_exit_controls <- function(exit_prices, min_present = 10L) {
  need <- c("ticker", "exit_type", "new_ticker")
  if (!is.data.frame(exit_prices) || !all(need %in% names(exit_prices))) {
    cli::cli_abort(c(
      "x" = "{.arg exit_prices} must be a data frame with {.field {need}}.",
      "i" = "Build it with {.fn hd_alpaca_exit_prices}."
    ))
  }
  ctl <- tibble::tibble(
    ticker = c("SIVB", "FRC", "SBNY",
               "TWTR", "ATVI", "CELG", "NBL", "JNPR",
               "XEC", "ARNC", "M", "AIV", "LUMN",
               "FI"),
    expected = c(rep("failure_candidate", 3L), rep("takeover", 5L),
                 rep("demotion", 5L), "ticker_change"),
    expected_new_ticker = c(rep(NA_character_, 13L), "FISV")
  )
  i <- match(ctl$ticker, exit_prices$ticker)
  ctl$observed <- exit_prices$exit_type[i]
  ctl$observed_new_ticker <- exit_prices$new_ticker[i]
  ctl$status <- ifelse(
    is.na(i), "ABSENT",
    ifelse(ctl$observed == ctl$expected &
             .hd_both_na_or_equal(ctl$observed_new_ticker, ctl$expected_new_ticker),
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
    lines <- sprintf(
      "%s: expected %s%s, got %s%s", bad$ticker,
      bad$expected, ifelse(is.na(bad$expected_new_ticker), "", paste0(" -> ", bad$expected_new_ticker)),
      bad$observed, ifelse(is.na(bad$observed_new_ticker), "", paste0(" -> ", bad$observed_new_ticker))
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
