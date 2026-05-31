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
#' @return One-row tibble: strategy, n_months, sharpe, cagr, vol, max_dd,
#'   blown_up (logical), bankrupt_month (integer or NA), avg_dd_days (numeric),
#'   max_dd_days (numeric), max_cons_losses (integer), loss_clustered (logical).
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

  # ── Pillar-8: dd-duration + loss-clustering ──────────────────────────────
  # Use only the pre-bankruptcy slice so post-bankruptcy zero-equity "returns"
  # do not inflate duration estimates.  When not blown_up the full series is used.
  r_pillar <- if (blown_up && !is.na(bankrupt_idx)) {
    r[seq_len(bankrupt_idx - 1L)]
  } else {
    r
  }

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
