# Mechanical drawdown stop-loss rules — retrospective expectancy test (#588 G2/G3)
#
# Source: "The Stop-Loss That Stops Gains" (Samir Varma, summarising a Nov
# 2025 JPM paper) — https://samirvarma.substack.com/p/the-stop-loss-that-stops-gains
# Varma's claim (untested by the article itself for the regime-aware half):
# mechanical drawdown stops destroy expectancy via death-by-a-thousand-cuts,
# and a regime-conditioned threshold MIGHT do better than a static one but is
# explicitly not demonstrated in the source.
#
# This file implements the three-arm retrospective test agreed in the issue
# #588 comment thread (2026-07-21):
#   Arm A -- no-stop:      no drawdown exit at all (the current state of
#                          every strategy in this repo -- grep confirms zero
#                          hits for stop_loss/trailing_stop/dd_limit).
#   Arm B -- static-stop:  exit at a fixed -X% drawdown, X swept.
#   Arm C -- regime-stop:  exit at a percentile threshold that varies by an
#                          EXISTING regime label (reused, never invented --
#                          see hd_regime_stop_thresholds()).
#
# All three arms share one mechanical engine, hd_stop_rule_backtest(): the
# only thing that differs between B and C is whether `threshold` is a scalar
# or a per-period vector. Exposure decisions use dd measured through the end
# of period t and are applied to period t+1 (never t+0 -- see
# .claude/rules/feedback_alpha-decay-min-t1.md / hermetic execution timing
# convention used throughout this repo, e.g. R/plan_turn_of_month.R).
#
# hd_stop_rule_compare_arms() also implements the issue's PRE-REGISTERED
# sequencing rule: if the best static-stop arm already destroys expectancy
# relative to no-stop, the regime-stop arm is skipped by default (it would be
# optimising a mechanism already shown harmful) and the skip is reported
# explicitly rather than silently omitted (fail-loud-not-null.md).

# ── 1. Drawdown series ──────────────────────────────────────────────────────

#' Equity, running peak, and drawdown for a return series
#'
#' Pure utility shared by \code{\link{hd_stop_rule_backtest}} and
#' \code{\link{hd_regime_stop_thresholds}} so both compute drawdown the same
#' way. \code{ret[i] = NA} is not permitted -- filter before calling, per
#' this repo's NA-propagation convention
#' (\code{.claude/rules/fail-loud-not-null.md}).
#'
#' @param ret Numeric vector of periodic returns, no NAs.
#'
#' @return A list with \code{equity} (cumprod(1+ret)), \code{peak}
#'   (cummax(equity)), and \code{dd} (equity/peak - 1, always <= 0).
#'
#' @family stop-rule
#' @export
hd_drawdown <- function(ret) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (anyNA(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must not contain NA values.",
      "i" = "Filter NAs before calling {.fn hd_drawdown} -- a silently dropped period would shift every downstream index (fail-loud-not-null.md)."
    ))
  }
  equity <- cumprod(1 + ret)
  peak   <- cummax(equity)
  list(equity = equity, peak = peak, dd = equity / peak - 1)
}


# ── 2. Mechanical stop-rule engine (Arms B and C share this) ──────────────

#' Apply a mechanical drawdown stop-loss rule to a return series
#'
#' Retrospective stress test on an EXISTING return series -- it does not
#' change position sizing or strategy construction, only interrupts
#' exposure. Monitoring uses the ALWAYS-INVESTED equity curve computed from
#' \code{ret} (the Kaminski & Lo 2014 convention: the reference drawdown is
#' the one you would see if you never left the market, since that is what a
#' timing overlay actually watches). A breach detected at the end of period
#' \code{t} takes the position OUT starting period \code{t+1} -- decisions
#' are never executed at \code{t+0}. Re-entry after \code{reentry_periods}
#' periods is UNCONDITIONAL (the Kaminski & Lo 2014 K-period holding rule --
#' it does not wait for the underlying drawdown to itself recover, which a
#' slow grind may never do within the window). Breach monitoring is paused
#' while already out and resumes strictly after the grace re-entry period,
#' so a still-depressed drawdown can trigger a fresh stop immediately after
#' re-entry -- this is intended: a slow grinding drawdown accrues more
#' switch cost than a sharp V-shaped one.
#'
#' @param ret Numeric vector of periodic strategy returns, no NAs (filter
#'   before calling).
#' @param threshold Either a single numeric in \verb{(-1, 0)} (the
#'   static-stop arm) or a numeric vector the same length as \code{ret} with
#'   every element in \verb{(-1, 0)} (the regime-stop arm -- see
#'   \code{\link{hd_regime_stop_thresholds}}). \code{-Inf} disables the stop
#'   for that period (used to build the no-stop arm from the same engine).
#' @param rf Numeric vector the same length as \code{ret}, or \code{NULL}.
#'   Return earned while stopped out. \code{NULL} means cash (0) while out --
#'   an explicit, documented default per fail-loud-not-null.md Required
#'   Pattern 2, not a silent one.
#' @param cost_bps Numeric scalar >= 0. One-way cost in basis points charged
#'   only on periods where exposure flips (matches the \code{is_switch} /
#'   \code{cost_bps} convention already used for binary in/out overlays --
#'   see \code{R/plan_turn_of_month.R}). Default 5 (that overlay's value).
#' @param reentry_periods Integer >= 1. Number of periods to remain out
#'   after a stop triggers before exposure is eligible to resume.
#'
#' @return A list with:
#'   \describe{
#'     \item{ret_net}{Numeric vector, same length as \code{ret}: realised
#'       return net of switch cost.}
#'     \item{exposed}{Logical vector, same length as \code{ret}: TRUE when
#'       invested in the strategy that period.}
#'     \item{n_stops}{Integer count of distinct stop events (exit
#'       transitions).}
#'     \item{turnover}{Integer count of exposure FLIPS (exits + re-entries
#'       combined) -- annualise by dividing by
#'       \code{length(ret) / periods_per_year} at the call site.}
#'   }
#'
#' @family stop-rule
#' @export
hd_stop_rule_backtest <- function(ret, threshold, rf = NULL, cost_bps = 5,
                                   reentry_periods = 1L) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (anyNA(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must not contain NA values.",
      "i" = "Filter NAs before calling {.fn hd_stop_rule_backtest} (fail-loud-not-null.md)."
    ))
  }
  n <- length(ret)
  if (n < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must have at least 2 observations.",
      "i" = "Got length {n}."
    ))
  }
  if (!is.numeric(threshold)) {
    cli::cli_abort(c(
      "x" = "{.arg threshold} must be numeric.",
      "i" = "Got {.cls {class(threshold)}}."
    ))
  }
  if (length(threshold) == 1L) {
    threshold <- rep(threshold, n)
  } else if (length(threshold) != n) {
    cli::cli_abort(c(
      "x" = "{.arg threshold} must be a single number or a vector the same length as {.arg ret}.",
      "i" = "Got length {length(threshold)}, expected 1 or {n}."
    ))
  }
  bad_threshold <- is.finite(threshold) & (threshold <= -1 | threshold >= 0)
  if (any(bad_threshold)) {
    cli::cli_abort(c(
      "x" = "Every finite {.arg threshold} value must lie in (-1, 0) -- it is a drawdown fraction.",
      "i" = "{sum(bad_threshold)} value{?s} out of range, e.g. {.val {threshold[which(bad_threshold)[1]]}}.",
      "i" = "Use -Inf to disable the stop for a period (the no-stop arm), never 0 or a value <= -1."
    ))
  }
  if (is.null(rf)) {
    rf <- rep(0, n)
  } else {
    if (!is.numeric(rf) || length(rf) != n) {
      cli::cli_abort(c(
        "x" = "{.arg rf} must be NULL or a numeric vector the same length as {.arg ret}.",
        "i" = "Got {.cls {class(rf)}} of length {length(rf)}, expected length {n}."
      ))
    }
    if (anyNA(rf)) {
      cli::cli_abort(c(
        "x" = "{.arg rf} must not contain NA values.",
        "i" = "A missing risk-free rate must never be silently treated as zero (fail-loud-not-null.md)."
      ))
    }
  }
  if (!is.numeric(cost_bps) || length(cost_bps) != 1L || cost_bps < 0) {
    cli::cli_abort(c(
      "x" = "{.arg cost_bps} must be a single non-negative number.",
      "i" = "Got {.val {cost_bps}}."
    ))
  }
  if (!is.numeric(reentry_periods) || length(reentry_periods) != 1L ||
      reentry_periods < 1 || reentry_periods != round(reentry_periods)) {
    cli::cli_abort(c(
      "x" = "{.arg reentry_periods} must be a single positive integer.",
      "i" = "Got {.val {reentry_periods}}."
    ))
  }

  dd_full <- hd_drawdown(ret)$dd

  exposed <- logical(n)
  exposed[1] <- TRUE

  # State machine, tracked by absolute period index (clearer and less
  # bug-prone than a decrementing counter -- see #588 PR discussion):
  #   out_until   -- last period index currently forced OUT (0 = none active)
  # A breach detected at t forces periods (t+1)..(t+reentry_periods) OUT,
  # then period (t+reentry_periods+1) is a GRACE re-entry: exposure resumes
  # UNCONDITIONALLY that period (this is the K-period holding-period rule of
  # Kaminski & Lo 2014 -- re-entry does not wait for the underlying
  # always-invested drawdown to itself recover, since with a slow-recovering
  # drawdown it may never cross back above threshold within the window).
  # Monitoring for a FRESH breach resumes strictly after the grace period.
  out_until <- 0L
  reentry_periods <- as.integer(reentry_periods)

  for (t in seq_len(n - 1L)) {
    if (t < out_until) {
      exposed[t + 1L] <- FALSE
      next
    }
    if (out_until > 0L && (t + 1L) == out_until + 1L) {
      exposed[t + 1L] <- TRUE   # grace re-entry, unconditional
      next
    }
    breached <- is.finite(threshold[t]) && dd_full[t] <= threshold[t]
    if (breached) {
      exposed[t + 1L] <- FALSE
      out_until <- t + reentry_periods
    } else {
      exposed[t + 1L] <- TRUE
    }
  }

  ret_realised <- ifelse(exposed, ret, rf)
  is_switch <- c(FALSE, exposed[-1] != exposed[-n])
  ret_net <- ret_realised - is_switch * (cost_bps / 1e4)

  exit_events <- sum(exposed[-1] < exposed[-n])  # TRUE(1) -> FALSE(0)

  list(
    ret_net  = ret_net,
    exposed  = exposed,
    n_stops  = exit_events,
    turnover = sum(is_switch)
  )
}


# ── 3. Regime-conditioned thresholds (Arm C only) ──────────────────────────

#' Regime-conditioned drawdown-percentile stop thresholds
#'
#' Builds the per-period threshold vector for the regime-stop arm by reusing
#' an EXISTING regime label (per #588 G2: "reuse, do not invent" -- e.g.
#' \code{regime_classification$regime} from \code{R/plan_regime.R}, or the
#' VVIX hostile/cautious label from \code{R/plan_risk_state.R}). For each
#' regime level, the threshold is the \code{percentile}-th quantile of the
#' drawdown depths observed WITHIN that regime during \code{train_idx} only
#' -- the same training-quantile, no-look-ahead convention
#' \code{regime_classification} itself already uses (see
#' \code{R/plan_regime.R}, "Use TRAINING-period quantiles to avoid
#' look-ahead bias"). Periods whose regime is \code{NA}, or whose regime
#' level had fewer than \code{min_train_obs} training observations, fall
#' back to the POOLED (all-regime) training percentile -- this fallback is
#' returned so callers can report how often it fired.
#'
#' @param ret Numeric vector of periodic returns, no NAs.
#' @param regime A vector (character or factor) the same length as
#'   \code{ret}. \code{NA} entries are allowed (fall back to pooled).
#' @param percentile Numeric scalar in \verb{(0, 1)}. Quantile of in-regime
#'   drawdown depths used as that regime's threshold (a LOWER percentile is
#'   a MORE lenient/deeper stop, since drawdowns are <= 0 -- e.g.
#'   \code{percentile = 0.05} sets the threshold at the depth exceeded by
#'   only the worst 5% of in-regime drawdowns).
#' @param train_idx Logical vector the same length as \code{ret}, or
#'   \code{NULL} (default: all \code{TRUE}, i.e. use the full series --
#'   only appropriate when this function is itself being called on a
#'   training subset upstream).
#' @param min_train_obs Integer. Minimum in-regime training observations
#'   required before that regime gets its own threshold; below this, the
#'   pooled fallback is used and counted.
#'
#' @return A list with \code{threshold} (numeric vector, same length as
#'   \code{ret}, every finite value in \verb{(-1, 0)}), \code{regime_levels}
#'   (the per-level thresholds actually computed), and \code{n_fallback}
#'   (count of periods that used the pooled fallback).
#'
#' @family stop-rule
#' @export
hd_regime_stop_thresholds <- function(ret, regime, percentile = 0.05,
                                       train_idx = NULL, min_train_obs = 12L) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  n <- length(ret)
  if (length(regime) != n) {
    cli::cli_abort(c(
      "x" = "{.arg regime} must be the same length as {.arg ret}.",
      "i" = "Got length {length(regime)}, expected {n}."
    ))
  }
  if (!is.numeric(percentile) || length(percentile) != 1L ||
      percentile <= 0 || percentile >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg percentile} must be a single number in (0, 1).",
      "i" = "Got {.val {percentile}}."
    ))
  }
  if (is.null(train_idx)) {
    train_idx <- rep(TRUE, n)
  } else if (!is.logical(train_idx) || length(train_idx) != n) {
    cli::cli_abort(c(
      "x" = "{.arg train_idx} must be NULL or a logical vector the same length as {.arg ret}.",
      "i" = "Got {.cls {class(train_idx)}} of length {length(train_idx)}, expected length {n}."
    ))
  }

  if (anyNA(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must not contain NA values.",
      "i" = "Filter NAs before calling {.fn hd_regime_stop_thresholds} (fail-loud-not-null.md)."
    ))
  }
  dd <- hd_drawdown(ret)$dd

  train_regime <- regime[train_idx]
  train_dd     <- dd[train_idx]
  levels_present <- unique(train_regime[!is.na(train_regime)])

  pooled_threshold <- stats::quantile(train_dd, probs = percentile, na.rm = TRUE, names = FALSE)

  level_thresholds <- list()
  for (lev in levels_present) {
    lev_dd <- train_dd[train_regime == lev & !is.na(train_regime)]
    if (length(lev_dd) >= min_train_obs) {
      level_thresholds[[as.character(lev)]] <-
        stats::quantile(lev_dd, probs = percentile, na.rm = TRUE, names = FALSE)
    }
  }

  threshold <- vapply(seq_len(n), function(i) {
    lev <- as.character(regime[i])
    if (!is.na(lev) && !is.null(level_thresholds[[lev]])) {
      level_thresholds[[lev]]
    } else {
      pooled_threshold
    }
  }, numeric(1))

  is_fallback <- vapply(seq_len(n), function(i) {
    lev <- as.character(regime[i])
    is.na(lev) || is.null(level_thresholds[[lev]])
  }, logical(1))

  list(
    threshold     = threshold,
    regime_levels = level_thresholds,
    n_fallback    = sum(is_fallback)
  )
}


#' Canonical annualisation metrics, mirrored inside the package (#588)
#'
#' Deliberately duplicates the formula in \code{R/utils_metrics.R}'s
#' \code{annualise_returns()} (root pipeline script) rather than calling it:
#' a root-level \code{R/} script is sourced only into the
#' \code{docs/_targets.R} pipeline environment and is not part of the
#' \code{historicaldata} package namespace, so the package cannot depend on
#' it. Kept formula-identical on purpose so a stop-rule Sharpe/CAGR/vol/max_dd
#' is directly comparable to every other leaderboard metric. Not exported.
#'
#' @param ret Numeric vector of periodic returns, no NAs.
#' @param periods_per_year Integer.
#' @noRd
.hd_stop_rule_annualise <- function(ret, periods_per_year) {
  n <- length(ret)
  if (n < 2L) {
    return(list(cagr = NA_real_, vol = NA_real_, sharpe = NA_real_, max_dd = NA_real_))
  }
  equity <- cumprod(1 + ret)
  cagr   <- equity[n]^(periods_per_year / n) - 1
  vol    <- stats::sd(ret) * sqrt(periods_per_year)
  sharpe <- if (vol > 0) cagr / vol else NA_real_
  max_dd <- min(equity / cummax(equity) - 1)
  list(cagr = cagr, vol = vol, sharpe = sharpe, max_dd = max_dd)
}


# ── 4. Top-level: compare Arm A / B / C ─────────────────────────────────────

#' Compare no-stop, static-stop, and regime-stop arms on one return series
#'
#' Orchestrates the full #588 G2/G3 retrospective test for a single
#' strategy's return series: Arm A (no-stop, current state), Arm B
#' (static-stop, swept across \code{static_thresholds}), and -- unless
#' skipped by the sequencing rule below -- Arm C (regime-stop, reusing
#' \code{regime}).
#'
#' Implements the issue's PRE-REGISTERED sequencing rule (issue #588,
#' comment 2026-07-21): "if a FIXED stop (Arm B) already destroys expectancy
#' relative to no stop (Arm A), that alone is strong evidence against
#' building the more elaborate regime-conditioned version." Concretely: if
#' the BEST (highest-Sharpe) static-stop arm has a lower Sharpe than the
#' no-stop arm, Arm C is skipped by default (\code{run_regime_arm =
#' "auto"}) and \code{skipped_regime_arm} in the result explains why --
#' never silently, per fail-loud-not-null.md. Pass \code{"always"} to force
#' Arm C regardless (e.g. for a deliberate robustness check), or
#' \code{"never"} to never compute it.
#'
#' @param ret Numeric vector of periodic strategy returns, no NAs.
#' @param regime A vector the same length as \code{ret}, or \code{NULL}.
#'   Required (and must be non-NULL) if \code{run_regime_arm != "never"}.
#' @param static_thresholds Numeric vector, each element in \verb{(-1, 0)}.
#'   The static-stop sweep for Arm B. Default \code{c(-0.10, -0.15, -0.20)}.
#' @param regime_percentile Numeric scalar in \verb{(0, 1)}, passed to
#'   \code{\link{hd_regime_stop_thresholds}}.
#' @param rf Numeric vector the same length as \code{ret}, or \code{NULL}
#'   (cash while stopped out). See \code{\link{hd_stop_rule_backtest}}.
#' @param cost_bps Numeric scalar >= 0. See \code{\link{hd_stop_rule_backtest}}.
#' @param periods_per_year Integer. Default 12L (monthly). Use 252L for
#'   daily returns. Used only to annualise \code{turnover} and to compute
#'   Sharpe/CAGR/vol/max_dd (formula matches \code{R/utils_metrics.R}'s
#'   \code{annualise_returns()}, mirrored internally -- see
#'   \code{.hd_stop_rule_annualise}).
#' @param train_idx Logical vector the same length as \code{ret}, or
#'   \code{NULL} (whole series). Passed to
#'   \code{\link{hd_regime_stop_thresholds}}.
#' @param reentry_periods Integer >= 1. See \code{\link{hd_stop_rule_backtest}}.
#' @param run_regime_arm One of \code{"auto"} (default, sequencing rule
#'   above), \code{"always"}, or \code{"never"}.
#' @param degradation_margin Numeric scalar >= 0. In \code{"auto"} mode, Arm
#'   C is skipped only when the best Arm B Sharpe is at least this much
#'   BELOW Arm A's Sharpe (default \code{0}, i.e. any degradation triggers
#'   the skip -- widen this if a marginal/noisy difference should not count).
#'
#' @return A list with \code{results} (a tibble, one row per arm x
#'   threshold, columns \code{arm}, \code{threshold}, \code{sharpe},
#'   \code{cagr}, \code{vol}, \code{max_dd}, \code{turnover}, \code{n_stops},
#'   \code{n}), \code{best_static} (the Arm B row with the highest Sharpe),
#'   \code{skipped_regime_arm} (\code{FALSE}, or a character string
#'   explaining why Arm C was skipped), and \code{regime_arm_note}
#'   (character; NA if Arm C ran, else the same explanation).
#'
#' @family stop-rule
#' @export
hd_stop_rule_compare_arms <- function(ret, regime = NULL,
                                       static_thresholds = c(-0.10, -0.15, -0.20),
                                       regime_percentile = 0.05,
                                       rf = NULL, cost_bps = 5,
                                       periods_per_year = 12L,
                                       train_idx = NULL,
                                       reentry_periods = 1L,
                                       run_regime_arm = c("auto", "always", "never"),
                                       degradation_margin = 0) {
  run_regime_arm <- match.arg(run_regime_arm)
  if (!is.numeric(ret) || anyNA(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector with no NA values.",
      "i" = "Filter NAs before calling {.fn hd_stop_rule_compare_arms} (fail-loud-not-null.md)."
    ))
  }
  if (!is.numeric(static_thresholds) || length(static_thresholds) < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg static_thresholds} must be a non-empty numeric vector.",
      "i" = "Got {.cls {class(static_thresholds)}} of length {length(static_thresholds)}."
    ))
  }
  if (run_regime_arm != "never" && is.null(regime)) {
    cli::cli_abort(c(
      "x" = "{.arg regime} must not be NULL when {.arg run_regime_arm} is {.val {run_regime_arm}}.",
      "i" = "Reuse an existing regime label (regime_classification$regime, R/plan_regime.R; or the VVIX hostile/cautious label, R/plan_risk_state.R) -- see #588 G2.",
      "i" = "Pass run_regime_arm = \"never\" if this call only needs Arms A/B."
    ))
  }

  n <- length(ret)

  metrics_row <- function(ret_net, arm, threshold, n_stops, turnover_raw) {
    m <- .hd_stop_rule_annualise(ret_net, periods_per_year = periods_per_year)
    years <- n / periods_per_year
    tibble::tibble(
      arm       = arm,
      threshold = threshold,
      sharpe    = m$sharpe,
      cagr      = m$cagr,
      vol       = m$vol,
      max_dd    = m$max_dd,
      turnover  = if (years > 0) turnover_raw / years else NA_real_,
      n_stops   = n_stops,
      n         = n
    )
  }

  # Arm A -- no-stop: threshold = -Inf disables the stop entirely.
  arm_a_bt <- hd_stop_rule_backtest(ret, threshold = -Inf, rf = rf,
                                     cost_bps = cost_bps,
                                     reentry_periods = reentry_periods)
  row_a <- metrics_row(arm_a_bt$ret_net, "no-stop", NA_real_,
                        arm_a_bt$n_stops, arm_a_bt$turnover)

  # Arm B -- static-stop, swept.
  rows_b <- lapply(static_thresholds, function(x) {
    bt <- hd_stop_rule_backtest(ret, threshold = x, rf = rf, cost_bps = cost_bps,
                                 reentry_periods = reentry_periods)
    metrics_row(bt$ret_net, "static-stop", x, bt$n_stops, bt$turnover)
  })
  rows_b <- dplyr::bind_rows(rows_b)

  best_static <- rows_b[which.max(rows_b$sharpe), , drop = FALSE]

  sharpe_a <- row_a$sharpe
  sharpe_best_b <- if (nrow(best_static) == 1L) best_static$sharpe else NA_real_
  b_destroys_expectancy <- is.finite(sharpe_a) && is.finite(sharpe_best_b) &&
    (sharpe_best_b < sharpe_a - degradation_margin)

  skip_regime <- switch(run_regime_arm,
    never  = "run_regime_arm = \"never\"",
    always = FALSE,
    auto   = if (isTRUE(b_destroys_expectancy)) {
      sprintf(
        "auto sequencing: best static-stop Sharpe (%.3f, threshold %.2f) < no-stop Sharpe (%.3f) by >= %.3f -- per #588 sequencing rule, a regime-conditioned version of an already-harmful mechanism is not worth building.",
        sharpe_best_b, best_static$threshold, sharpe_a, degradation_margin
      )
    } else {
      FALSE
    }
  )

  if (isFALSE(skip_regime)) {
    thr <- hd_regime_stop_thresholds(ret, regime, percentile = regime_percentile,
                                      train_idx = train_idx)
    bt_c <- hd_stop_rule_backtest(ret, threshold = thr$threshold, rf = rf,
                                   cost_bps = cost_bps,
                                   reentry_periods = reentry_periods)
    row_c <- metrics_row(bt_c$ret_net, "regime-stop", NA_real_,
                          bt_c$n_stops, bt_c$turnover)
    row_c$n_fallback <- thr$n_fallback
    results <- dplyr::bind_rows(row_a, rows_b, row_c)
    regime_arm_note <- NA_character_
  } else {
    results <- dplyr::bind_rows(row_a, rows_b)
    regime_arm_note <- skip_regime
  }

  list(
    results             = results,
    best_static         = best_static,
    skipped_regime_arm  = skip_regime,
    regime_arm_note     = regime_arm_note
  )
}
