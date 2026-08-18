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
#' Sharpe is NOT computed by this function as of #677. The canonical
#' rf-adjusted geometric Sharpe helper (\code{sharpe_ratio_rf()}) lives in
#' \code{R/utils_metrics.R} at the pipeline layer, not inside the
#' \code{historicaldata} package -- this package cannot call it (it is not
#' part of the package's NAMESPACE/Imports; calling it here would only work
#' by accident when both happen to be loaded in the same session, and would
#' fail \code{R CMD check} / \code{devtools::test()} on the package alone).
#' \code{sharpe} is therefore returned as \code{NA_real_} here; the caller
#' MUST overwrite it -- see \code{.mom_prepeak_sharpe()} in
#' \code{R/plan_mom_prepeak.R}, which reuses \code{blown_up} /
#' \code{bankrupt_month} from this function's output to recompute the same
#' pre-bankruptcy slice and calls \code{sharpe_ratio_rf()} on it, keeping
#' the Sharpe FORMULA single-sourced even though the two halves of the
#' calculation live either side of the package/pipeline boundary.
#'
#' Pillar-8 drawdown-duration and loss-clustering metrics (avg_dd_days,
#' max_dd_days, max_cons_losses, loss_clustered) are computed on the
#' pre-bankruptcy slice of returns when blown_up == TRUE.  Post-bankruptcy
#' "returns" are economically meaningless (the portfolio has zero equity) so
#' including them would inflate dd duration and loss-cluster metrics.
#'
#' @param returns_tbl Tibble with column `ret_ls` (numeric monthly L/S returns).
#' @param strategy Character. Strategy code_name label.
#' @param ann_factor Integer. Annualisation factor (12 for monthly).
#'
#' @return One-row tibble: strategy, n_months, sharpe (always NA_real_ -- see
#'   above), cagr, vol, max_dd, blown_up (logical), bankrupt_month (integer
#'   or NA), avg_dd_days (numeric), max_dd_days (numeric), max_cons_losses
#'   (integer), loss_clustered (logical).
#' @noRd
.mom_prepeak_compute_metrics <- function(returns_tbl,
                                          strategy,
                                          ann_factor = 12L) {
  r <- returns_tbl$ret_ls
  r <- r[!is.na(r)]
  n <- length(r)

  if (n < 12L) {
    return(tibble::tibble(
      strategy        = strategy,
      n_months        = n,
      sharpe          = NA_real_,
      cagr            = NA_real_,
      vol             = NA_real_,
      max_dd          = NA_real_,
      blown_up        = NA,
      bankrupt_month  = NA_integer_,
      avg_dd_days     = NA_real_,
      max_dd_days     = NA_real_,
      max_cons_losses = NA_integer_,
      loss_clustered  = NA
    ))
  }

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

  vol <- stats::sd(r) * sqrt(ann_factor)

  # ── Pillar-8: dd-duration + loss-clustering ──────────────────────────────
  # Use only the pre-bankruptcy slice so post-bankruptcy zero-equity "returns"
  # do not inflate duration estimates.  When not blown_up the full series is
  # used.  #677: the same slice is independently reconstructed by
  # .mom_prepeak_sharpe() (R/plan_mom_prepeak.R) from blown_up/bankrupt_month
  # to compute the geometric rf-adjusted Sharpe outside this package -- see
  # roxygen above.
  r_pillar <- if (blown_up && !is.na(bankrupt_idx)) {
    r[seq_len(bankrupt_idx - 1L)]
  } else {
    r
  }

  # sharpe is a placeholder here -- see roxygen above (#677). The caller
  # (R/plan_mom_prepeak.R) MUST overwrite it via .mom_prepeak_sharpe().
  sharpe <- NA_real_

  if (length(r_pillar) >= 3L) {
    dd_dur  <- hd_dd_duration(r_pillar)
    lc      <- hd_loss_clustering(r_pillar)
    avg_dd_days     <- dd_dur$avg_dd_duration
    max_dd_days     <- dd_dur$max_dd_duration
    max_cons_losses <- .max_consecutive_losses(r_pillar)
    loss_clustered  <- lc$clustered
  } else {
    avg_dd_days     <- NA_real_
    max_dd_days     <- NA_real_
    max_cons_losses <- NA_integer_
    loss_clustered  <- NA
  }

  tibble::tibble(
    strategy        = strategy,
    n_months        = n,
    sharpe          = round(sharpe, 3),
    cagr            = if (is.na(cagr)) NA_real_ else round(cagr * 100, 1),
    vol             = round(vol * 100, 1),
    max_dd          = round(max_dd * 100, 1),
    blown_up        = blown_up,
    bankrupt_month  = if (blown_up) as.integer(bankrupt_idx) else NA_integer_,
    avg_dd_days     = avg_dd_days,
    max_dd_days     = max_dd_days,
    max_cons_losses = as.integer(max_cons_losses),
    loss_clustered  = loss_clustered
  )
}


# ── Internal: maximum consecutive losses ──────────────────────────────────────
# Counts the longest run of negative returns in a return vector.
# Returns 0L if no negative returns, NA_integer_ if input is empty.
.max_consecutive_losses <- function(r) {
  r <- r[!is.na(r)]
  if (length(r) == 0L) return(NA_integer_)
  is_loss <- r < 0
  if (!any(is_loss)) return(0L)
  rle_obj <- rle(is_loss)
  loss_runs <- rle_obj$lengths[rle_obj$values]
  if (length(loss_runs) == 0L) return(0L)
  as.integer(max(loss_runs))
}
