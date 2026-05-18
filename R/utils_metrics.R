# Canonical backtest annualisation metrics
#
# Single source of truth for leaderboard metrics so all plans produce
# comparable Sharpe, CAGR, vol, max drawdown, and Calmar values.
# Uses compound (geometric) annualisation — what investors actually earn.
#
# Formula:
#   CAGR   = cumprod(1 + r)[n] ^ (periods_per_year / n) - 1
#   vol    = sd(r) * sqrt(periods_per_year)
#   Sharpe = CAGR / vol

#' Annualise periodic returns — canonical helper
#'
#' Annualises a vector of periodic returns (monthly assumed by default).
#' Returns include CAGR (geometric), annual vol, Sharpe (CAGR / vol),
#' max drawdown, and Calmar.
#'
#' Uses compound (geometric) annualisation throughout so results from
#' different plans are directly comparable on the leaderboard.
#'
#' @param ret Numeric vector of periodic returns (e.g., monthly).
#' @param periods_per_year Integer. Default 12L (monthly). Use 252L for
#'   daily or 4L for quarterly returns.
#' @param na.rm Logical. If \code{TRUE} (default), NA values are dropped
#'   before computation.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{cagr}{Compound annual growth rate (decimal, not percent).}
#'     \item{vol}{Annualised volatility (sd * sqrt(periods_per_year)).}
#'     \item{sharpe}{Sharpe ratio (CAGR / vol); NA when vol is zero.}
#'     \item{max_dd}{Maximum drawdown (negative number, e.g. -0.12 = -12\%).}
#'     \item{calmar}{Calmar ratio (CAGR / abs(max_dd)); NA when max_dd is zero.}
#'     \item{n}{Number of non-NA observations used.}
#'   }
#'
#' @family backtest
#' @export
annualise_returns <- function(ret, periods_per_year = 12L, na.rm = TRUE) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      periods_per_year <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a single positive number.",
      "i" = "Got {periods_per_year}."
    ))
  }

  if (isTRUE(na.rm)) ret <- ret[!is.na(ret)]

  n <- length(ret)
  if (n < 2L) {
    return(list(
      cagr   = NA_real_,
      vol    = NA_real_,
      sharpe = NA_real_,
      max_dd = NA_real_,
      calmar = NA_real_,
      n      = n
    ))
  }

  equity <- cumprod(1 + ret)
  cagr   <- equity[n]^(periods_per_year / n) - 1
  vol    <- stats::sd(ret) * sqrt(periods_per_year)
  sharpe <- if (vol > 0) cagr / vol else NA_real_
  max_dd <- min(equity / cummax(equity) - 1)
  calmar <- if (max_dd < 0) cagr / abs(max_dd) else NA_real_

  list(
    cagr   = cagr,
    vol    = vol,
    sharpe = sharpe,
    max_dd = max_dd,
    calmar = calmar,
    n      = n
  )
}
