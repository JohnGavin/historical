# Internal helper: annualised performance metrics for one L/S strategy.
# Extracted from R/plan_mom_prepeak.R so it can be tested independently
# without sourcing the full plan file (which has tar_target library() calls).


#' Compute annualised performance metrics for one sibling strategy
#'
#' Bankruptcy-aware version: when the L/S portfolio's cumulative product goes
#' non-positive (extreme short-leg return causes ret_ls < -1), reported metrics
#' are:
#'   - blown_up = TRUE, bankrupt_month = first index where cum <= 0
#'   - cagr = NA_real_ (no meaningful CAGR after bankruptcy)
#'   - max_dd = -100% (floor; -100 on the percentage scale returned)
#'
#' Sharpe is computed from per-period returns and is unaffected by bankruptcy.
#'
#' @param returns_tbl Tibble with column `ret_ls` (numeric monthly L/S returns).
#' @param strategy Character. Strategy code_name label.
#' @param ann_factor Integer. Annualisation factor (12 for monthly).
#'
#' @return One-row tibble: strategy, n_months, sharpe, cagr, vol, max_dd,
#'   blown_up (logical), bankrupt_month (integer or NA).
#' @noRd
.mom_prepeak_compute_metrics <- function(returns_tbl,
                                          strategy,
                                          ann_factor = 12L) {
  r <- returns_tbl$ret_ls
  r <- r[!is.na(r)]
  n <- length(r)

  if (n < 12L) {
    return(tibble::tibble(
      strategy       = strategy,
      n_months       = n,
      sharpe         = NA_real_,
      cagr           = NA_real_,
      vol            = NA_real_,
      max_dd         = NA_real_,
      blown_up       = NA,
      bankrupt_month = NA_integer_
    ))
  }

  monthly_rf <- (1.02)^(1 / ann_factor) - 1
  mean_r     <- mean(r)
  sd_r       <- sd(r)
  sharpe     <- if (sd_r > 0) (mean_r - monthly_rf) / sd_r * sqrt(ann_factor) else NA_real_

  cum   <- cumprod(1 + r)
  years <- n / ann_factor

  # Bankruptcy detection: an unrisk-managed L/S portfolio can go to / past zero
  # equity when ret_ls < -1 in a single month (extreme short squeeze in a single
  # rebalance window — see #365 follow-up). The cumulative product passes through
  # zero; reported cagr and max_dd must reflect bankruptcy honestly rather than
  # returning NaN or impossible values like max_dd < -100%.
  blown_up <- any(cum <= 0)

  if (blown_up) {
    bankrupt_idx <- which(cum <= 0)[1]
    cagr         <- NA_real_
    max_dd       <- -1.0                    # capped at -100% by definition
  } else {
    bankrupt_idx <- NA_integer_
    cagr         <- cum[[n]]^(1 / years) - 1
    cum_max      <- cummax(cum)
    dd           <- (cum - cum_max) / cum_max
    max_dd       <- min(dd)
  }

  vol <- sd_r * sqrt(ann_factor)

  tibble::tibble(
    strategy       = strategy,
    n_months       = n,
    sharpe         = round(sharpe, 3),
    cagr           = if (is.na(cagr)) NA_real_ else round(cagr * 100, 1),
    vol            = round(vol * 100, 1),
    max_dd         = round(max_dd * 100, 1),
    blown_up       = blown_up,
    bankrupt_month = if (blown_up) as.integer(bankrupt_idx) else NA_integer_
  )
}
