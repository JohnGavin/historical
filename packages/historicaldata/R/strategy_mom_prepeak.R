# Pre-peak / post-peak 12-2 momentum decomposition (Büsing et al. 2022)
#
# Reference: Büsing, Mohrschladt & Siedhoff (2022) "Pre-peak and post-peak
# momentum" — show that ~84% of 12-2 momentum profits are earned in the
# pre-peak sub-period (formation start to peak price date) and ~16% in the
# post-peak sub-period (peak price date to formation end).
#
# Universe in this project: ltr_universe (~51 US non-ETF equities).
# NOTE: this is methodology-demo scale, not CRSP. The paper's headline 84/16
# figure was computed on CRSP-scale data. Paper replication at CRSP scale is
# deferred to a v2 follow-up (issue #365).


#' Pre-peak / post-peak 12-2 momentum decomposition (Büsing et al. 2022)
#'
#' For each (ticker, as_of_date), find the single date within the formation
#' window [as_of_date - lookback_months_start, as_of_date - lookback_months_end]
#' on which the stock's adjusted price was highest, then decompose the
#' formation-window return into pre-peak (start -> peak) and post-peak
#' (peak -> formation-end) components.
#'
#' Look-ahead safety: the formation window is strictly before as_of_date.
#' No price at or after as_of_date enters the computation.
#'
#' @param daily_prices Tibble with columns `ticker` (character), `date`
#'   (Date), `adjusted` (numeric, adjusted close).
#' @param as_of_dates Date vector. One row per (ticker, as_of_date) is
#'   produced for tickers with sufficient history.
#' @param lookback_months_start Integer. Start of formation window expressed
#'   as months before `as_of_date`. Default 12L (the "12" in 12-2).
#' @param lookback_months_end Integer. End of formation window expressed as
#'   months before `as_of_date`. Default 2L (the "2" in 12-2 — skips the
#'   most recent month to avoid short-term reversal).
#' @param min_obs_days Integer. Minimum trading days required in the formation
#'   window for a row to be returned. Default 100L. Rows below this threshold
#'   are dropped (NOT returned as NA — they have no decomposition to report).
#'
#' @return Tibble with one row per (ticker, as_of_date) that had >= `min_obs_days`
#'   observations in the formation window. Columns:
#'   * `ticker` — character
#'   * `as_of_date` — Date
#'   * `formation_start` — Date (first date in window)
#'   * `formation_end`   — Date (last date in window)
#'   * `peak_date`       — Date (date of max adjusted price)
#'   * `n_obs`           — integer (trading days in window)
#'   * `pre_peak_return`  — numeric (price(peak) / price(formation_start) - 1)
#'   * `post_peak_return` — numeric (price(formation_end) / price(peak) - 1)
#'   * `total_return`    — numeric (price(formation_end) / price(formation_start) - 1)
#'   * `peak_position`   — numeric in [0, 1] (peak's relative position in window;
#'     0 = peak on day 1, 1 = peak on last day) — useful for replicating
#'     paper Figure 1 (peak-date distribution histogram)
#'
#' @details
#' Sanity identity (verified in tests): up to compounding,
#' `(1 + pre_peak_return) * (1 + post_peak_return) == (1 + total_return)`.
#'
#' Edge cases:
#' * Peak on formation-start (day 1) -> `pre_peak_return == 0`,
#'   `post_peak_return == total_return`.
#' * Peak on formation-end (last day) -> `pre_peak_return == total_return`,
#'   `post_peak_return == 0`.
#' * Ties for peak: the FIRST occurrence is used (deterministic via
#'   `which.max()` semantics).
#'
#' @family momentum_prepeak
#' @export
hd_mom_prepeak_signal <- function(daily_prices,
                                  as_of_dates,
                                  lookback_months_start = 12L,
                                  lookback_months_end   = 2L,
                                  min_obs_days          = 100L) {
  # ---- Input validation -------------------------------------------------------
  if (!is.data.frame(daily_prices)) {
    cli::cli_abort(c(
      "x" = "{.arg daily_prices} must be a data frame, not {.cls {class(daily_prices)}}."
    ))
  }

  required_cols <- c("ticker", "date", "adjusted")
  missing_cols  <- setdiff(required_cols, names(daily_prices))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg daily_prices} is missing required columns: {.field {missing_cols}}."
    ))
  }

  # Coerce POSIXct date to Date (see data-validation-timeseries rule, Section 9)
  if (inherits(daily_prices$date, "POSIXct")) {
    daily_prices$date <- as.Date(daily_prices$date)
  }
  if (!inherits(daily_prices$date, "Date")) {
    cli::cli_abort(c(
      "x" = "{.arg daily_prices}$date must be a Date column, got {.cls {class(daily_prices$date)}}."
    ))
  }

  as_of_dates <- tryCatch(
    as.Date(as_of_dates),
    error = function(e) {
      cli::cli_abort(c(
        "x" = "{.arg as_of_dates} must be coercible to Date.",
        "i" = "Original error: {conditionMessage(e)}"
      ))
    }
  )

  if (!is.numeric(lookback_months_start) || length(lookback_months_start) != 1L ||
      is.na(lookback_months_start)) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months_start} must be a single positive integer, got {lookback_months_start}."
    ))
  }
  lookback_months_start <- as.integer(lookback_months_start)

  if (!is.numeric(lookback_months_end) || length(lookback_months_end) != 1L ||
      is.na(lookback_months_end)) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months_end} must be a single non-negative integer, got {lookback_months_end}."
    ))
  }
  lookback_months_end <- as.integer(lookback_months_end)

  if (lookback_months_end < 0L) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months_end} must be >= 0, got {lookback_months_end}."
    ))
  }
  if (lookback_months_start <= lookback_months_end) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months_start} ({lookback_months_start}) must be > {.arg lookback_months_end} ({lookback_months_end})."
    ))
  }

  if (!is.numeric(min_obs_days) || length(min_obs_days) != 1L ||
      is.na(min_obs_days) || min_obs_days < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg min_obs_days} must be a positive integer, got {min_obs_days}."
    ))
  }
  min_obs_days <- as.integer(min_obs_days)

  # ---- Core computation -------------------------------------------------------
  # Split prices by ticker once to avoid re-filtering the full table per row.
  prices_by_ticker <- split(daily_prices, daily_prices$ticker)

  # Compute one decomposition per (ticker, as_of_date).
  # Use purrr::map + dplyr::bind_rows (map_dfr is deprecated in purrr >= 1.0).
  dplyr::bind_rows(purrr::map(
    names(prices_by_ticker),
    function(tk) {
      tk_prices <- prices_by_ticker[[tk]]
      tk_prices <- tk_prices[order(tk_prices$date), ]

      dplyr::bind_rows(purrr::map(
        as_of_dates,
        function(aod) {
          .mom_prepeak_one(
            tk_prices             = tk_prices,
            ticker                = tk,
            as_of_date            = aod,
            lookback_months_start = lookback_months_start,
            lookback_months_end   = lookback_months_end,
            min_obs_days          = min_obs_days
          )
        }
      ))
    }
  ))
}


# ---- Internal helper ----------------------------------------------------------

#' Compute pre/post-peak decomposition for a single (ticker, as_of_date)
#'
#' @param tk_prices Data frame of prices for ONE ticker, ordered by date.
#' @param ticker Character scalar.
#' @param as_of_date Date scalar.
#' @param lookback_months_start Integer.
#' @param lookback_months_end Integer.
#' @param min_obs_days Integer.
#'
#' @return Zero-row tibble (if insufficient data) or one-row tibble.
#' @noRd
.mom_prepeak_one <- function(tk_prices,
                             ticker,
                             as_of_date,
                             lookback_months_start,
                             lookback_months_end,
                             min_obs_days) {
  # Formation window: strictly before as_of_date.
  # lubridate::`%m-%` handles month arithmetic with roll-back on month-end dates.
  formation_start <- lubridate::`%m-%`(as_of_date, months(lookback_months_start))
  formation_end   <- lubridate::`%m-%`(as_of_date, months(lookback_months_end))

  # Filter to window (look-ahead safe: date <= formation_end < as_of_date)
  win <- tk_prices[
    tk_prices$date >= formation_start &
      tk_prices$date <= formation_end, ,
    drop = FALSE
  ]

  n_obs <- nrow(win)
  if (n_obs < min_obs_days) {
    return(tibble::tibble(
      ticker          = character(0),
      as_of_date      = as.Date(character(0)),
      formation_start = as.Date(character(0)),
      formation_end   = as.Date(character(0)),
      peak_date       = as.Date(character(0)),
      n_obs           = integer(0),
      pre_peak_return  = numeric(0),
      post_peak_return = numeric(0),
      total_return     = numeric(0),
      peak_position    = numeric(0)
    ))
  }

  # Identify peak (first occurrence on tie — which.max() semantics)
  peak_idx  <- which.max(win$adjusted)
  peak_date <- win$date[peak_idx]

  price_start <- win$adjusted[1L]
  price_peak  <- win$adjusted[peak_idx]
  price_end   <- win$adjusted[n_obs]

  pre_peak_return  <- price_peak  / price_start - 1
  post_peak_return <- price_end   / price_peak  - 1
  total_return     <- price_end   / price_start - 1
  # peak_position: 0 = first day, 1 = last day
  peak_position    <- (peak_idx - 1L) / (n_obs - 1L)

  tibble::tibble(
    ticker          = ticker,
    as_of_date      = as_of_date,
    formation_start = win$date[1L],
    formation_end   = win$date[n_obs],
    peak_date       = peak_date,
    n_obs           = n_obs,
    pre_peak_return  = pre_peak_return,
    post_peak_return = post_peak_return,
    total_return     = total_return,
    peak_position    = peak_position
  )
}
