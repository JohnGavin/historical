# Plan: Commodities Mean Reversion (Issue #138)
#
# Counterpart to plan_commodities_momentum.R (#134).
# #134 found commodity momentum is broken (Sharpe -0.85 baseline,
# -0.89 to -0.91 decomposed). This plan tests the counter-hypothesis:
# if momentum doesn't work, mean reversion might — commodities have
# backwardation/contango cycles, supply/demand seasonality, and supply
# shocks that reverse.
#
# A clear negative result is fine and valuable.
#
# Data: re-uses commodities_raw + commodities_returns from
#       plan_commodities_momentum.R (DO NOT re-define those targets here).
# Frequency: DAILY (ann_factor = 252). #717: the universe mixes 13 FRED
#   monthly price indexes with 24 Yahoo Finance daily futures/ETF series
#   (scripts/fetch_commodities.R); the 24 daily series dominate the merged
#   `date` column (~96% of rows; measured 2026-08-22: 147821 total rows,
#   142426 from `source == "yahoo"`), so cmr_portfolio_1m/3m/6m -- one row
#   per unique date in the combined universe -- are themselves daily series
#   (median gap between dates = 1 day), not monthly, despite every function
#   in this file being named/commented as if they were. Verified against
#   scripts/fetch_commodities.R + data/raw/commodities.parquet directly for
#   #717, not merely re-asserted from this comment's own prior (wrong) text.
# Look-ahead safety: signal at t uses returns through t-1 only.
# Execution: signal at t -> trade at t+1 close.
# Transaction cost: 0.2% per trade (same as commodity momentum, #134).

plan_commodities_mean_reversion <- function() {
  list(

    # ── Signals: three lookback windows ──────────────────────────────────
    # Re-uses commodities_returns from plan_commodities_momentum.R.
    # Each signal: mr_signal = -(cumulative return over prior L months).
    # Higher signal -> bigger recent loser -> long candidate.

    targets::tar_target(cmr_signals_1m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 1L)
    }),

    targets::tar_target(cmr_signals_3m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 3L)
    }),

    targets::tar_target(cmr_signals_6m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 6L)
    }),


    # ── Portfolios: long-losers / short-winners ───────────────────────────
    # t+1 execution: signal at t -> trade executes at t+1 closing prices.
    # 10 long + 10 short, equal weight within each leg.
    # 0.2% one-way transaction cost.

    targets::tar_target(cmr_portfolio_1m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_1m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_3m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_3m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_6m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_6m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),


    # ── Daily net returns (thin wrappers for falsification bridge) ────────
    # #717: these are the SAME net_ret column as cmr_portfolio_1m/3m/6m
    # (one row per date, ~252 obs/year) with no monthly resampling -- despite
    # the misleading name/comment this file previously carried. Consumers
    # (plan_falsification.R, plan_structural_breaks.R) must use ann_factor/
    # ppy = 252, not 12.

    targets::tar_target(cmr_returns_1m, {
      cmr_portfolio_1m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),

    targets::tar_target(cmr_returns_3m, {
      cmr_portfolio_3m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),

    targets::tar_target(cmr_returns_6m, {
      cmr_portfolio_6m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),


    # ── Performance metrics per lookback ──────────────────────────────────
    # Sharpe, MDD, max DD duration (hd_dd_duration from risk_metrics.R).

    targets::tar_target(cmr_metrics_1m, {
      .compute_cmr_metrics(cmr_portfolio_1m, lookback = "1m", daily_rf = daily_rf, ann_factor = 252L)
    }),

    targets::tar_target(cmr_metrics_3m, {
      .compute_cmr_metrics(cmr_portfolio_3m, lookback = "3m", daily_rf = daily_rf, ann_factor = 252L)
    }),

    targets::tar_target(cmr_metrics_6m, {
      .compute_cmr_metrics(cmr_portfolio_6m, lookback = "6m", daily_rf = daily_rf, ann_factor = 252L)
    }),


    # ── Summary: comparison across lookbacks ─────────────────────────────

    targets::tar_target(cmr_summary, {
      dplyr::bind_rows(cmr_metrics_1m, cmr_metrics_3m, cmr_metrics_6m) |>
        dplyr::arrange(lookback)
    }),


    # ── Head-to-head: mean reversion vs momentum (Part C) ─────────────────
    # Joins commodity-momentum metrics (from plan_commodities_momentum.R)
    # with MR metrics. Lightweight: no new data fetch.
    # Momentum baseline = 12m lookback (Sharpe -0.85 per #134).

    targets::tar_target(cmr_vs_mom_compare, {
      library(dplyr)

      mom_metrics <- commodities_perf_summary |>
        dplyr::filter(strategy == "baseline") |>
        dplyr::transmute(
          lookback     = "12m (momentum)",
          mom_sharpe   = round(sharpe, 3),
          mom_mdd      = round(max_dd, 3)
        )

      mr_metrics <- cmr_summary |>
        dplyr::transmute(
          lookback   = paste0(lookback, " (MR)"),
          mr_sharpe  = round(sharpe, 3),
          mr_mdd     = round(max_dd, 3)
        )

      # One row per configuration; NA where comparison doesn't apply.
      tibble::tibble(
        lookback    = c(mr_metrics$lookback, mom_metrics$lookback),
        type        = c(rep("mean_reversion", nrow(mr_metrics)), "momentum"),
        sharpe      = c(mr_metrics$mr_sharpe, mom_metrics$mom_sharpe),
        max_dd      = c(mr_metrics$mr_mdd,    mom_metrics$mom_mdd)
      ) |>
        dplyr::arrange(type, lookback)
    }),


    # ── Registry sentinel (#347 PR 2/4; stability metrics #400 PR 5/6) ──────
    # First strategy to write into the bt.* registry. One bt.strategy row
    # + three bt.run rows (one per lookback partition: 1m, 3m, 6m). The
    # registry path is overridable via HD_REGISTRY_PATH so CI / tests can
    # point it at a tempfile. Returns a tibble of the run_uuids for
    # inspection via tar_read(cmr_registry_run).
    # Also records SSR + top5pct stability metrics via hd_record_stability_metrics().

    targets::tar_target(cmr_registry_run, {
      .cmr_register_runs(
        strategy_names = strategy_names,
        cmr_summary    = cmr_summary,
        portfolio_list = list(
          `1m` = cmr_portfolio_1m,
          `3m` = cmr_portfolio_3m,
          `6m` = cmr_portfolio_6m
        )
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Not exported; called only within this plan's targets.

#' Join a daily risk-free series onto a CMR portfolio (#722)
#'
#' Mirrors \code{.tom_join_rf_daily()} in R/plan_turn_of_month.R and
#' \code{.olmar_join_rf()} in R/plan_olmar.R: joins on \code{date} at DAILY
#' granularity, not \code{ym} at monthly granularity -- CMR's portfolios are
#' themselves daily series (#717; see the frequency note at the top of this
#' file), so the risk-free series annualised alongside them with
#' \code{ann_factor = 252L} must be daily too. Before #722, this function
#' joined the MONTHLY \code{stk_rf} on \code{ym}, which produced a
#' physically-impossible ~41% annualised risk-free rate (mean monthly rf
#' multiplied by 252, the daily annualisation factor).
#'
#' As of #677 slice 3b the coverage policy itself lives in the shared
#' \code{.join_rf_series()} (R/utils_metrics.R), which distinguishes THREE
#' cases (leading / trailing / interior) -- see that function's roxygen for
#' the full policy. A missing risk-free series must never be treated as zero
#' -- see fail-loud-not-null.md.
#'
#' @param df Tibble with a `date` column (CMR's daily portfolio), and
#'   `net_ret`.
#' @param daily_rf Tibble with columns `date`, `rf_ret` (the `daily_rf`
#'   target, R/plan_stock_backtest.R).
#' @param lookback Character. Lookback label, used only for error/warning text.
#' @return `df` with `rf_ret` joined, trailing uncovered dates removed.
#' @noRd
.cmr_join_rf <- function(df, daily_rf, lookback) {
  .join_rf_series(
    df = df, rf = daily_rf, key = "date",
    label = ".cmr_join_rf", rf_label = "daily_rf",
    rf_source = "the daily_rf target, R/plan_stock_backtest.R",
    df_label = paste0("CMR ", lookback, " portfolio"),
    strategy_label = paste0("CMR ", lookback),
    period_noun = "date"
  )
}

#' Reconcile a declared `ann_factor` against the observed date frequency
#'
#' Guard from #717 (fail-loud-not-null.md Required Pattern 5): computes the
#' median gap between the distinct, sorted dates in \code{dates} and aborts
#' if that gap is inconsistent with \code{ann_factor}. This is deliberately
#' placed at the point where \code{ann_factor} is SUPPLIED to
#' \code{.compute_cmr_metrics()} -- not buried in the CAGR/vol arithmetic
#' further down -- so a future caller that passes the wrong constant fails
#' immediately, on the value it got wrong, rather than producing a
#' plausible-looking but silently mis-annualised number (exactly what
#' happened with \code{ann_factor = 12L} against CMR's actually-daily data).
#'
#' Uses the MEDIAN gap, not the mean or min: commodity data has real gaps
#' (weekends, holidays, and -- because CMR's universe mixes 24 Yahoo daily
#' futures/ETF series with 13 FRED monthly indexes, #717 -- occasional
#' months where only the sparser monthly series print). The median is
#' robust to that without a hand-tuned outlier filter. Bands are
#' deliberately wide (e.g. daily tolerates gaps up to 3 days) to absorb long
#' weekends/holiday clusters without false-positiving on a genuine daily
#' series; they are not so wide that a real classification error (e.g.
#' monthly data declared daily) would slip through undetected.
#'
#' @param dates A date vector (one entry per observation; duplicates and
#'   unsorted input are handled).
#' @param ann_factor Integer. The annualisation factor about to be used.
#' @param lookback Character. Lookback label, used only for the abort message.
#' @return `NULL`, invisibly. Called for its abort side effect.
#' @noRd
.assert_cmr_ann_factor <- function(dates, ann_factor, lookback) {
  d <- sort(unique(as.Date(dates)))
  if (length(d) < 3L) {
    # Too few points for a frequency to be meaningfully observed.
    return(invisible(NULL))
  }
  gaps <- as.numeric(diff(d))
  median_gap <- stats::median(gaps)

  expected_ann_factor <- dplyr::case_when(
    median_gap <= 3   ~ 252L,  # daily (business days; weekends widen some gaps)
    median_gap <= 10  ~ 52L,   # weekly
    median_gap <= 45  ~ 12L,   # monthly
    median_gap <= 135 ~ 4L,    # quarterly
    TRUE ~ NA_integer_
  )

  if (is.na(expected_ann_factor)) {
    cli::cli_abort(c(
      "x" = paste0(
        "CMR {lookback}: cannot classify the observed data frequency ",
        "against declared ann_factor {ann_factor}."
      ),
      "i" = paste0(
        "Median gap between observation dates is {median_gap} day{?s}, ",
        "which does not match a recognised daily/weekly/monthly/quarterly band."
      ),
      "i" = "See .claude/rules/fail-loud-not-null.md Required Pattern 5."
    ))
  }

  if (expected_ann_factor != ann_factor) {
    cli::cli_abort(c(
      "x" = paste0(
        "CMR {lookback}: declared ann_factor ({ann_factor}) disagrees with ",
        "the observed data frequency."
      ),
      "i" = paste0(
        "Median gap between observation dates is {median_gap} day{?s}, ",
        "consistent with ann_factor = {expected_ann_factor}, not {ann_factor}."
      ),
      "i" = "This is the reconciliation guard added for #717 -- see .claude/rules/fail-loud-not-null.md Required Pattern 5."
    ))
  }

  invisible(NULL)
}

.compute_cmr_metrics <- function(portfolio_tbl, lookback, daily_rf, ann_factor = 252L) {
  library(dplyr)

  df <- portfolio_tbl |>
    dplyr::filter(!is.na(.data$net_ret)) |>
    dplyr::mutate(date = as.Date(.data$date))

  # #717 guard: declared ann_factor must match the observed frequency of
  # this portfolio's own dates, checked at the point ann_factor is supplied.
  .assert_cmr_ann_factor(df$date, ann_factor, lookback)

  n <- nrow(df)

  if (n < 12L) {
    return(tibble::tibble(
      lookback = lookback, n_days = n,
      sharpe = NA_real_, cagr = NA_real_, vol = NA_real_, ann_rf = NA_real_,
      max_dd = NA_real_, avg_dd_duration = NA_real_, max_dd_duration = NA_real_
    ))
  }

  # #722: real Fama-French DAILY rf (daily_rf), replacing the monthly stk_rf
  # that was previously joined against this daily portfolio (#677 introduced
  # the real rf but on the wrong frequency; #717 fixed ann_factor without
  # fixing the rf join that #722 catches).
  df <- .cmr_join_rf(df, daily_rf, lookback = lookback)
  n  <- nrow(df)  # may shrink if a trailing rf gap was trimmed above

  r  <- df$net_ret
  rf <- df$rf_ret

  cum        <- cumprod(1 + r)
  years      <- n / ann_factor
  cagr       <- (cum[n])^(1 / years) - 1
  sd_r       <- sd(r)
  vol        <- sd_r * sqrt(ann_factor)

  # #677: canonical rf-adjusted geometric Sharpe (R/utils_metrics.R::sharpe_ratio_rf()),
  # replacing the arithmetic-mean numerator + hardcoded rf formula.
  sr     <- sharpe_ratio_rf(r, rf, periods_per_year = ann_factor)
  sharpe <- sr$sharpe

  cum_max    <- cummax(cum)
  dd         <- (cum - cum_max) / cum_max
  max_dd     <- min(dd)

  dd_stats   <- hd_dd_duration(r)

  # Unit convention (#336): cagr, vol, max_dd are stored as DECIMAL fractions
  # (e.g., -0.21 = -21% drawdown), matching the canonical convention used by
  # plan_factormax.R, plan_drif.R, commodities_momentum.R, and the leaderboard
  # normalizers in plan_leaderboard.R. Display-time formatting (× 100, "%")
  # belongs to the consumer (DT::datatable, plot label), not the producer.
  tibble::tibble(
    lookback        = lookback,
    n_days          = n,
    sharpe          = round(sharpe, 3),
    cagr            = round(cagr, 4),
    vol             = round(vol, 4),
    # ann_rf published alongside sharpe (#677 slice 4), same FRACTION
    # convention as cagr/vol above -- QA gate S17
    # (check_leaderboard_sharpe_coherence(), R/plan_qa_gates.R) asserts
    # sharpe == (cagr - ann_rf) / vol for every leaderboard row.
    ann_rf          = round(sr$ann_rf, 4),
    max_dd          = round(max_dd, 4),
    avg_dd_duration = dd_stats$avg_dd_duration,
    max_dd_duration = dd_stats$max_dd_duration
  )
}


# ── Registry sentinel helper (#347 PR 2/4; stability metrics #400 PR 5/6) ──
# Initialises (idempotent) + upserts CMR strategy + records one bt.run
# row per lookback partition. Also records SSR + top5pct stability metrics
# via hd_record_stability_metrics() when portfolio_list is supplied.
# Returns a tibble of (partition, run_uuid).
.cmr_register_runs <- function(strategy_names, cmr_summary,
                               portfolio_list = list()) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      partition = character(),
      run_uuid  = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  cmr_row <- strategy_names |>
    dplyr::filter(.data$code_name == "cmr") |>
    dplyr::transmute(
      strategy_id       = .data$code_name,
      short_name        = .data$short_name,
      long_name         = .data$long_name,
      asset_class       = .data$asset_class,
      frequency         = .data$frequency,
      ann_factor        = as.integer(.data$ann_factor),
      directionality    = as.character(.data$directionality),
      liquidity_tier    = as.character(.data$liquidity_tier),
      time_horizon_days = as.integer(.data$time_horizon_days_avg),
      trades_per_year   = as.numeric(.data$trades_per_year_avg),
      turnover_pct      = as.numeric(.data$turnover_pct_per_period_avg),
      tags              = .data$tags,
      research_paper_doi = .data$research_paper_doi
    )
  historicaldata::hd_strategy_upsert(con, cmr_row)

  partitions <- unique(cmr_summary$lookback)
  uuids <- character(length(partitions))
  for (i in seq_along(partitions)) {
    p <- partitions[i]
    uu <- historicaldata::hd_run_upsert(
      con,
      strategy_id      = "cmr",
      partition        = p,
      pipeline_version = "phase1"
    )
    uuids[i] <- uu

    # PR 3/4 — record long-form metrics for this partition.
    # Units (#640, corrected #717): cagr/vol/max_dd are decimal fractions per
    # the "Unit convention (#336)" comment above, sharpe is a scale-free
    # ratio, n_days is a count. avg_dd_duration/max_dd_duration are drawdown
    # lengths measured in the return series' own periodicity (days, for
    # CMR's daily returns, #717) — classified as "count" (periods), not
    # "days" [hd_metric_units()'s "days" unit type], matching the same
    # count-of-periods convention every other daily strategy in this
    # registry uses for its own period column (e.g. tom_units/aw_units
    # classify n_days as "count", not "days" -- R/plan_turn_of_month.R,
    # R/plan_avoid_worst.R).
    # ann_rf (#677 slice 4, #691) is a decimal fraction, same convention as
    # cagr (round(sr$ann_rf, 4) above, never *100).
    row <- cmr_summary[cmr_summary$lookback == p, , drop = FALSE]
    if (nrow(row) == 1L) {
      metric_cols <- setdiff(names(row), "lookback")
      wide <- row[, metric_cols, drop = FALSE]
      cmr_units <- c(
        n_days = "count", sharpe = "ratio", cagr = "fraction",
        vol = "fraction", max_dd = "fraction",
        avg_dd_duration = "count", max_dd_duration = "count",
        ann_rf = "fraction"
      )
      historicaldata::hd_metric_record(con, uu, wide, units = cmr_units)
    }

    # Record SSR + top5pct stability metrics (#400 PR 5/6).
    # #717: CMR's returns are daily (see file header + .assert_cmr_ann_factor()
    # above), not monthly. w = ann_factor = 252 matches every other daily
    # strategy's call site (avoid_worst, turn_of_month, risk_state all pass
    # w = 252L, ann_factor = 252L; the monthly strategies -- drif, factormax,
    # ltr_momentum, xgb_signal, portfolio_opt, stock_backtest, mom_prepeak --
    # all pass w = 36L, ann_factor = 12L). hd_record_stability_metrics()'s own
    # @param w roxygen doc states this exact convention: "Typical choices: 252
    # (daily) or 36 (monthly)."
    port <- portfolio_list[[p]]
    if (!is.null(port) && is.data.frame(port) && "net_ret" %in% names(port)) {
      rets <- port$net_ret
      if (length(rets) > 0L) {
        historicaldata::hd_record_stability_metrics(
          con        = con,
          run_uuid   = uu,
          returns    = rets,
          w          = 252L,
          ann_factor = 252L
        )
      }
    }
  }

  tibble::tibble(partition = partitions, run_uuid = uuids)
}
