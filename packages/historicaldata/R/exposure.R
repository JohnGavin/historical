# Exposure measurement (#626)
#
# hd_exposure_metrics() — gross / net / long / short / cash_borrow exposure
# from a single weight vector. Measurement only: this function does NOT
# renormalise, cap, or otherwise alter the input weights. It reports what
# is already there.

#' Gross, net, and cash-borrowing exposure of a weight vector
#'
#' @title Portfolio Exposure Metrics (`hd_exposure_metrics`)
#'
#' @description
#' Computes five exposure summary statistics from a numeric portfolio-weight
#' vector `w`. This is a pure measurement function: it never renormalises,
#' rescales, or caps `w`. It exists because, across this project's
#' strategies, gross exposure ranges from 1.0x (long-only) to 2.0x
#' (dollar-neutral long-short) up to a 3.0x cap (managed futures), and no
#' target previously computed `sum(abs(w))` anywhere — the leaderboard's
#' `vol`, `cagr`, and `max_dd` columns were being compared across strategies
#' built at different exposure levels without that fact being visible.
#'
#' **Why `cash_borrow` is a separate quantity from `gross` and `net`:**
#' `gross` (\eqn{\sum |w_i|}) and `net` (\eqn{\sum w_i}) describe the shape of
#' the weight vector, but neither answers "how much cash does this portfolio
#' need to borrow?" A dollar-neutral book with 100% long and 100% short
#' (`gross = 2`, `net = 0`) borrows **zero** cash in the conventional prime-
#' brokerage sense: the long leg is funded by the investor's own equity, and
#' the short leg is funded by the proceeds of the short sale itself (held as
#' collateral), not by borrowed cash. Cash borrowing only arises when the
#' **long** leg exceeds 100% of equity — i.e. margin debt used to buy more
#' long exposure than the account is worth. `cash_borrow` therefore measures
#' `max(0, long - 1)`, which is zero for every long-short strategy in this
#' project's registry (see `strategy_gross_convention`) and positive only for
#' a leveraged long-only book.
#'
#' @param w A numeric vector of portfolio weights. May contain negative
#'   values (short positions) and may be named. Must have length >= 1, be
#'   fully numeric, and contain no `NA`, `NaN`, or infinite values.
#'
#' @return A one-row [tibble::tibble()] with columns:
#'   \describe{
#'     \item{`gross`}{`sum(abs(w))` — total notional exposure (long + short
#'       legs). 1.0 for an unlevered long-only book; 2.0 for a dollar-neutral
#'       long-short book at 100/100.}
#'     \item{`net`}{`sum(w)` — directional exposure. 0 for a dollar-neutral
#'       book; equals `gross` for a long-only book.}
#'     \item{`long`}{`sum(w[w > 0])` — total long-leg notional.}
#'     \item{`short`}{`abs(sum(w[w < 0]))` — total short-leg notional
#'       (reported as a positive number).}
#'     \item{`cash_borrow`}{`max(0, long - 1)` — cash borrowed as a fraction
#'       of equity to fund the long leg above 1.0x capital. Zero whenever
#'       `long <= 1`, which includes every dollar-neutral long-short book
#'       regardless of its `gross` exposure.}
#'   }
#'
#' @examples
#' # Long-only, unlevered (100% in one asset)
#' hd_exposure_metrics(c(0.5, 0.5))
#'
#' # Long-only, levered to 120% (20% margin debt)
#' hd_exposure_metrics(c(0.7, 0.5))
#'
#' # Dollar-neutral long-short at 2.0x gross (100 long / 100 short) --
#' # cash_borrow is 0: the short leg is proceeds-funded, not cash-borrowed.
#' hd_exposure_metrics(c(0.5, 0.5, -0.5, -0.5))
#'
#' @family risk_metrics
#' @export
hd_exposure_metrics <- function(w) {
  if (!is.numeric(w)) {
    cli::cli_abort(
      c(
        "{.arg w} must be a numeric vector.",
        "x" = "Got {.cls {class(w)}}."
      )
    )
  }

  if (length(w) == 0L) {
    cli::cli_abort(
      c(
        "{.arg w} must have length >= 1.",
        "x" = "Got a zero-length vector."
      )
    )
  }

  if (anyNA(w)) {
    cli::cli_abort(
      c(
        "{.arg w} must not contain {.val NA} or {.val NaN}.",
        "i" = "Found {sum(is.na(w))} missing value{?s} at position{?s} {which(is.na(w))}.",
        "i" = "Resolve missingness upstream; {.fun hd_exposure_metrics} does not {.code na.rm}."
      )
    )
  }

  if (!all(is.finite(w))) {
    cli::cli_abort(
      c(
        "{.arg w} must contain only finite values.",
        "x" = "Found non-finite value{?s} at position{?s} {which(!is.finite(w))}."
      )
    )
  }

  long  <- sum(w[w > 0])
  short <- abs(sum(w[w < 0]))

  tibble::tibble(
    gross       = sum(abs(w)),
    net         = sum(w),
    long        = long,
    short       = short,
    cash_borrow = max(0, long - 1)
  )
}
