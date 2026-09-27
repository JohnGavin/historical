# Overnight / intraday return decomposition (issue #914 Gap 1)
#
# Source idea (read for ideas only, nothing copied): "The overnight gain is
# real, no trade keeps it, the rule that chases it buys wrecks" -- Serhat
# Girgin, QuanterLab, 2026-09-13. Its central diagnostic -- decomposing a
# daily return into a close->open (overnight) leg and an open->close
# (intraday) leg -- has no equivalent anywhere in this package
# (`grep -iE "overnight|intraday|close_to_open"` found only unrelated
# comments and the VIX1D registry entry before this file).
#
# THE HAZARD THIS FILE EXISTS TO HANDLE: `equity_daily`'s `open` and `close`
# are both RAW (unadjusted) prices; `adjusted_close` is the sole
# split/dividend-adjusted column (packages/historicaldata/inst/COLUMN_NAMING.md
# -- "close: Unadjusted closing price"; "adjusted_close: dividend- and
# split-adjusted close"). A naive overnight leg computed as
# `open_t / close_{t-1} - 1` from RAW prices fabricates a huge fake jump on
# any date with a split (e.g. a 2:1 split makes the raw open ~50% below the
# prior raw close, with no real return behind it) and a smaller fake jump on
# any ex-dividend date. hd_return_legs() corrects for this by carrying the
# adjustment ratio (adjusted_close / close) across the close_{t-1} -> open_t
# boundary -- see the "Adjustment" section below for the derivation. The
# intraday leg (close_t / open_t - 1) needs no such correction: both prices
# are quoted on the SAME calendar day, so any adjustment ratio applicable to
# that day cancels out of the ratio.

#' Split daily returns into an overnight leg and an intraday leg
#'
#' Decomposes each day's return into two legs: the **overnight** leg
#' (previous close to today's open -- the return earned by holding a
#' position through the close, without trading) and the **intraday** leg
#' (today's open to today's close -- the return earned by holding a position
#' opened at today's open). The two legs compound back to a close-to-close
#' return by construction (see Details); `hd_return_legs()` asserts this on
#' every call and aborts if it does not hold, which mainly guards against a
#' future refactor breaking the arithmetic (see the "Verification" section)
#' rather than validating the input data itself.
#'
#' @details
#' # Why this needs `adjusted_close`, not just `open`/`close`
#'
#' `open` and `close` are raw, unadjusted quoted prices; `adjusted_close` is
#' the dividend/split-adjusted close (see
#' `packages/historicaldata/inst/COLUMN_NAMING.md`). A split or a dividend
#' changes the raw price level overnight without any real economic return --
#' e.g. a 2:1 split makes tomorrow's raw open roughly half of today's raw
#' close. Computing `open_t / close_{t-1} - 1` directly from raw prices would
#' report this as a ~-50% "overnight return", which is not real: the
#' investor's actual wealth is unaffected by a split.
#'
#' `hd_return_legs()` corrects for this using the ratio
#' \eqn{a_t = adjusted\_close_t / close_t} (the cumulative back-adjustment
#' factor applicable to date \eqn{t}). This ratio is constant across most
#' day-to-day transitions and changes discretely only on the calendar day of
#' a split or ex-dividend event, because \code{adjusted_close} back-adjusts
#' every date by all corporate actions occurring after it. The corrected
#' overnight leg is:
#' \deqn{overnight_t = \frac{open_t \cdot a_t}{close_{t-1} \cdot a_{t-1}} - 1}
#' Because \eqn{a_t} multiplies BOTH prices on date \eqn{t} equally, it
#' cancels out of the intraday leg entirely:
#' \deqn{intraday_t = \frac{close_t \cdot a_t}{open_t \cdot a_t} - 1 = \frac{close_t}{open_t} - 1}
#' and the two legs compound to exactly the adjusted (total-return)
#' close-to-close return:
#' \deqn{(1 + overnight_t)(1 + intraday_t) - 1 = \frac{adjusted\_close_t}{adjusted\_close_{t-1}} - 1}
#' (substitute \eqn{a_{t-1} \cdot close_{t-1} = adjusted\_close_{t-1}} by
#' definition of \eqn{a_{t-1}} to see this cancels exactly). Rows flagged
#' \code{corp_action_adjusted = TRUE} in the output are the dates where
#' \eqn{a_t \ne a_{t-1}} -- i.e. where this correction was non-trivial.
#'
#' # Verification is an implementation check, not a data-quality check
#'
#' Given the algebra above, the compounding identity holds EXACTLY for any
#' input where `open`, `close`, `adjusted_close` are internally consistent
#' (same-day quotes on the same price scale) -- it cannot distinguish a real
#' corporate action from a data error, and cannot fail from normal data no
#' matter how large a split or dividend is. Its purpose is to catch an
#' IMPLEMENTATION bug (e.g. a future refactor that mixes up `close_t` and
#' `close_{t-1}`), not a data-quality issue. See
#' \code{historicaldata:::.hd_check_compounding()} and
#' \code{test-return-legs.R} for the falsification test that proves the
#' check actually fires when the arithmetic is wrong (per
#' `.claude/rules/verification-before-completion.md` -- "a check you have
#' never seen fail is not a check").
#'
#' # Dropped rows
#'
#' A row cannot appear in the output when either leg is undefined:
#' \itemize{
#'   \item the first row for a given `ticker` (no previous close to compute
#'     the overnight leg against);
#'   \item `open` is `NA` on that row (breaks both legs);
#'   \item (adjusted method only) `adjusted_close` is `NA` on that row or the
#'     previous row (breaks the overnight-leg correction).
#' }
#' Every dropped row is counted under exactly one of these reasons (see
#' `attr(result, "n_dropped_first_row")` etc.) and the counts are checked to
#' exhaustively account for every dropped row (e.g. an unreported `NA` in
#' `close` on a non-first row is a **distinct** failure mode this function
#' will not silently pass through -- see the "unaccounted drop" abort path).
#'
#' @param data A data frame with one row per (`ticker`, `date`), containing
#'   at minimum `date`, `ticker`, `open`, `close`. An `adjusted_close` column
#'   is required unless `unadjusted_ok = TRUE` (see below). Extra columns are
#'   ignored. Prices must be strictly positive where present.
#' @param unadjusted_ok Logical scalar, default `FALSE`. When `data` has no
#'   `adjusted_close` column, `hd_return_legs()` aborts by default rather
#'   than silently computing the overnight leg from raw prices alone, because
#'   that fabricates large fake overnight jumps on any split/dividend date
#'   (see Details). Pass `TRUE` only when the panel has been independently
#'   verified to contain no corporate actions over the requested window.
#' @param tolerance Numeric scalar > 0, default `1e-6`. Maximum allowed
#'   absolute deviation between `(1 + overnight)(1 + intraday) - 1` and the
#'   independently-computed close-to-close return before
#'   `hd_return_legs()` aborts (see "Verification is an implementation check"
#'   above).
#' @param quiet Logical scalar, default `FALSE`. When `FALSE`, emits a
#'   `cli::cli_inform()` summary of rows kept/dropped and corporate-action
#'   adjustments made. The same information is always available via
#'   `attr(result, ...)` regardless of `quiet`.
#'
#' @return A tibble with one row per retained (`ticker`, `date`):
#'   \describe{
#'     \item{date}{Date.}
#'     \item{ticker}{Character.}
#'     \item{overnight}{Close\eqn{_{t-1}} to open\eqn{_t} return (adjusted
#'       for corporate actions when `adjusted_close` is available).}
#'     \item{intraday}{Open\eqn{_t} to close\eqn{_t} return.}
#'     \item{close_to_close}{\eqn{(1 + overnight)(1 + intraday) - 1}; equals
#'       the adjusted close-to-close return when `adjusted_close` is used,
#'       or the raw close-to-close return under `unadjusted_ok = TRUE`.}
#'     \item{corp_action_adjusted}{Logical; `TRUE` when the overnight-leg
#'       adjustment ratio changed vs the previous day (a detected
#'       split/dividend event). `NA` for every row when `unadjusted_ok =
#'       TRUE` was used (no adjustment ratio is available to detect this).}
#'   }
#'   with attributes `method` (`"adjusted"` or `"unadjusted"`),
#'   `n_input_rows`, `n_dropped_first_row`, `n_dropped_missing_open`,
#'   `n_dropped_missing_adjusted_close`, and `n_corp_action_adjusted`.
#'
#' @examples
#' # A single split event: X's raw close halves overnight (2:1 split)
#' # between day 2 and day 3; adjusted_close carries the true total return.
#' toy <- tibble::tibble(
#'   ticker         = "X",
#'   date           = as.Date("2024-01-01") + 0:3,
#'   open           = c(99, 100, 51, 52),
#'   close          = c(100, 100, 52, 53),
#'   adjusted_close = c(50, 50, 52, 53)
#' )
#' hd_return_legs(toy)
#'
#' @family return-decomposition
#' @export
hd_return_legs <- function(data, unadjusted_ok = FALSE, tolerance = 1e-6,
                            quiet = FALSE) {
  # Threshold for flagging `corp_action_adjusted` (a detected split/dividend
  # day, i.e. a day where adj_ratio genuinely changed vs the previous day).
  # NOT 0 or a floating-point epsilon: adjusted_close/close carries real
  # day-to-day rounding noise even absent any corporate action -- measured
  # empirically on SPY 1993-2026 (explorations/overnight_intraday_split/,
  # issue #914 Gap 1): 90th percentile |ratio change| ~= 5.0e-7, while every
  # one of SPY's 134 real quarterly ex-dividend days over that period showed
  # a ratio change >= 4.0e-3 -- a three-order-of-magnitude gap with nothing
  # in between (count > 1e-4 == count > 1e-3 == 134 exactly). 1e-4 sits
  # cleanly in that gap. Using 1e-9 (a bare "any nonzero change") instead
  # flagged 8253 of 8355 SPY days (99% of the whole series) as a "detected"
  # corporate action, which made the diagnostic meaningless -- discovered by
  # actually running this function on SPY, not assumed.
  .HD_CORP_ACTION_RATIO_EPS <- 1e-4
  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "x" = "{.arg data} must be a data frame.",
      "i" = "Got an object of class {.cls {class(data)}}."
    ), class = "hd_return_legs_bad_input")
  }
  required_cols <- c("date", "ticker", "open", "close")
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg data} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "hd_return_legs() needs {.field {required_cols}} (plus optional {.field adjusted_close})."
    ), class = "hd_return_legs_missing_columns")
  }
  if (!is.logical(unadjusted_ok) || length(unadjusted_ok) != 1L || is.na(unadjusted_ok)) {
    cli::cli_abort(c(
      "x" = "{.arg unadjusted_ok} must be a single TRUE/FALSE.",
      "i" = "Got {.val {unadjusted_ok}}."
    ), class = "hd_return_legs_bad_input")
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1L || is.na(tolerance) || tolerance <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg tolerance} must be a single positive number.",
      "i" = "Got {.val {tolerance}}."
    ), class = "hd_return_legs_bad_input")
  }
  if (!is.logical(quiet) || length(quiet) != 1L || is.na(quiet)) {
    cli::cli_abort(c(
      "x" = "{.arg quiet} must be a single TRUE/FALSE.",
      "i" = "Got {.val {quiet}}."
    ), class = "hd_return_legs_bad_input")
  }

  has_adjusted <- "adjusted_close" %in% names(data)
  if (!has_adjusted && !unadjusted_ok) {
    cli::cli_abort(c(
      "x" = "{.arg data} has no {.field adjusted_close} column.",
      "i" = paste0(
        "hd_return_legs() needs adjusted_close to correct the overnight leg ",
        "for splits/dividends occurring between close_(t-1) and open_t -- ",
        "using raw open/close alone can fabricate large fake overnight jumps ",
        "on ex-dates."
      ),
      "i" = paste0(
        "Pass {.code unadjusted_ok = TRUE} to proceed anyway, only if this ",
        "panel has been independently verified to contain no corporate ",
        "actions over the requested window."
      )
    ), class = "hd_return_legs_adjustment_required")
  }
  method <- if (has_adjusted) "adjusted" else "unadjusted"

  d <- data
  d$date <- as.Date(d$date)
  d <- dplyr::arrange(d, ticker, date)

  # ── Positive-price guard (before any ratio arithmetic) ────────────────
  # A zero/negative price is a data error, not a real quote -- letting it
  # through would silently produce Inf/NaN/-100% "returns" downstream
  # instead of failing loudly (fail-loud-not-null.md).
  price_cols <- c("open", "close", if (has_adjusted) "adjusted_close")
  bad_price <- Reduce(`|`, lapply(price_cols, function(cn) {
    x <- d[[cn]]
    !is.na(x) & x <= 0
  }))
  if (any(bad_price)) {
    n_bad <- sum(bad_price)
    first_bad <- which(bad_price)[1L]
    cli::cli_abort(c(
      "x" = "{n_bad} row{?s} found with a non-positive price in {.field {price_cols}}.",
      "i" = "First offender: {.val {d$ticker[first_bad]}} on {.val {as.character(d$date[first_bad])}}.",
      "i" = "Prices must be strictly positive; a non-positive quote is a data error, not a real return."
    ), class = "hd_return_legs_non_positive_price")
  }

  d <- dplyr::mutate(
    d,
    prev_close = dplyr::lag(close),
    .by = ticker
  )
  if (has_adjusted) {
    d <- dplyr::mutate(
      d,
      adj_ratio = adjusted_close / close,
      prev_adj_ratio = dplyr::lag(adj_ratio),
      # Lagged independently of adj_ratio/prev_adj_ratio so that
      # expected_close_to_close below is computed via a genuinely separate
      # code path from `overnight` -- see ".hd_check_compounding" roxygen.
      prev_adjusted_close = dplyr::lag(adjusted_close),
      .by = ticker
    )
  }

  n_total_input <- nrow(d)
  is_first_row <- is.na(d$prev_close)
  is_missing_open <- is.na(d$open) & !is_first_row
  if (has_adjusted) {
    is_missing_adj <- (is.na(d$adjusted_close) | is.na(d$prev_adj_ratio)) &
      !is_first_row & !is_missing_open
  } else {
    is_missing_adj <- rep(FALSE, n_total_input)
  }

  d$intraday <- d$close / d$open - 1
  if (has_adjusted) {
    d$overnight <- (d$open * d$adj_ratio) / (d$prev_close * d$prev_adj_ratio) - 1
    d$expected_close_to_close <- d$adjusted_close / d$prev_adjusted_close - 1
  } else {
    d$overnight <- d$open / d$prev_close - 1
    d$expected_close_to_close <- d$close / d$prev_close - 1
  }
  d$close_to_close <- (1 + d$overnight) * (1 + d$intraday) - 1

  valid <- !is.na(d$overnight) & !is.na(d$intraday)
  out <- d[valid, , drop = FALSE]

  n_dropped_first_row <- sum(is_first_row)
  n_dropped_missing_open <- sum(is_missing_open)
  n_dropped_missing_adj <- sum(is_missing_adj)
  n_dropped_total <- n_total_input - nrow(out)
  n_accounted <- n_dropped_first_row + n_dropped_missing_open + n_dropped_missing_adj
  if (n_dropped_total != n_accounted) {
    cli::cli_abort(c(
      "x" = paste0(
        "{n_dropped_total - n_accounted} row{?s} dropped for an unrecognised ",
        "reason (not first-row-per-ticker, not missing open, not missing ",
        "adjusted_close)."
      ),
      "i" = "This usually means `close` (or another required value) is NA for some row.",
      "i" = "Inspect rows where {.field close} is NA to find the cause."
    ), class = "hd_return_legs_unaccounted_drop")
  }

  # ── Compounding assertion (implementation check, see Details) ────────
  .hd_check_compounding(
    observed = out$close_to_close,
    expected = out$expected_close_to_close,
    ticker = out$ticker,
    date = out$date,
    tolerance = tolerance
  )

  if (has_adjusted) {
    corp_action_adjusted <- !is.na(out$prev_adj_ratio) &
      abs(out$adj_ratio / out$prev_adj_ratio - 1) > .HD_CORP_ACTION_RATIO_EPS
  } else {
    corp_action_adjusted <- rep(NA, nrow(out))
  }
  n_corp_action_adjusted <- sum(corp_action_adjusted, na.rm = TRUE)

  result <- tibble::tibble(
    date = out$date,
    ticker = out$ticker,
    overnight = out$overnight,
    intraday = out$intraday,
    close_to_close = out$close_to_close,
    corp_action_adjusted = corp_action_adjusted
  )

  attr(result, "method") <- method
  attr(result, "n_input_rows") <- n_total_input
  attr(result, "n_dropped_first_row") <- n_dropped_first_row
  attr(result, "n_dropped_missing_open") <- n_dropped_missing_open
  attr(result, "n_dropped_missing_adjusted_close") <- n_dropped_missing_adj
  attr(result, "n_corp_action_adjusted") <- n_corp_action_adjusted

  if (!quiet) {
    cli::cli_inform(c(
      "v" = "hd_return_legs(): {nrow(result)} row{?s} kept (method: {method}).",
      "i" = paste0(
        "Dropped {n_dropped_first_row} first-row-per-ticker, ",
        "{n_dropped_missing_open} missing-open",
        if (has_adjusted) paste0(", ", n_dropped_missing_adj, " missing-adjusted_close") else "",
        "."
      ),
      "i" = "{n_corp_action_adjusted} row{?s} adjusted for a detected split/dividend event."
    ))
  }

  result
}

#' Abort if observed and expected close-to-close returns diverge
#'
#' Internal helper factored out of [hd_return_legs()] specifically so it can
#' be falsification-tested on its own (per
#' `.claude/rules/verification-before-completion.md`): given the algebra in
#' [hd_return_legs()]'s Details, the compounding identity cannot actually
#' diverge for internally-consistent input, so `test-return-legs.R` calls
#' this helper directly with a deliberately wrong `expected` to prove the
#' check fires, rather than trying (and failing) to construct real data that
#' triggers it through [hd_return_legs()] itself.
#'
#' @param observed,expected Numeric vectors, same length.
#' @param ticker,date Vectors, same length, used only for the error message.
#' @param tolerance Numeric scalar > 0.
#' @return `invisible(TRUE)` if no violation; otherwise aborts.
#' @noRd
.hd_check_compounding <- function(observed, expected, ticker, date, tolerance) {
  diff <- abs(observed - expected)
  bad <- which(!is.na(diff) & diff > tolerance)
  bad_nonfinite <- which(!is.finite(observed) | !is.finite(expected))
  bad <- sort(union(bad, bad_nonfinite))
  if (length(bad) == 0L) {
    return(invisible(TRUE))
  }
  ord <- order(-abs(observed[bad] - expected[bad]))
  bad <- bad[ord]
  cli::cli_abort(c(
    "x" = paste0(
      "{length(bad)} row{?s} failed the overnight x intraday compounding ",
      "check (tolerance {.val {tolerance}})."
    ),
    "i" = paste0(
      "Worst offender: {.val {ticker[bad[1]]}} on {.val {as.character(date[bad[1]])}} -- ",
      "(1+overnight)(1+intraday)-1 = {.val {signif(observed[bad[1]], 6)}}, ",
      "expected {.val {signif(expected[bad[1]], 6)}}."
    ),
    "i" = paste0(
      "This usually means `open` is not on the same (unadjusted) price ",
      "scale as `close`/`adjusted_close`, or the overnight/intraday ",
      "formulas were changed inconsistently."
    )
  ), class = "hd_return_legs_compounding_violation")
}
