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
# Risk-free join: #724. daily_rf follows the NYSE trading calendar; this
#   mixed universe needs some dates that were never NYSE trading days.
#   .cmr_fill_non_trading_rf_gaps() carries the last available rf forward
#   for short (<=7 calendar day) gaps before the shared #679 interior-hole
#   guard runs. NOTE (explicitly out of scope for #724): cmr_portfolio's
#   own date column still mixes daily and monthly-stamped observations, so
#   ann_factor = 252 over-annualises the vol/cagr contribution of every
#   FRED-only month-start row. #724 fixes the crash; it does not fix that.
# Mixed frequency (#738): MEASURED, not fixed. cmr_portfolio_1m/3m/6m run at
#   12 obs/year before 2000-01 (13 FRED monthly indexes only -- Yahoo history
#   starts 2000) and ~255/year after; ~1.4% of observations are monthly-spaced
#   and the whole series is declared daily. .assert_cmr_ann_factor()'s
#   consistency check (#738) now DETECTS this; choosing the remedy (truncate
#   to 2000+, resample to monthly, or segment and report separately) was an
#   open decision on #738 -- item 1 below is the truncation half of that
#   answer, decided on #751 (see next paragraph). The remaining half --
#   resample vs segment vs leave as-is for the POST-cutoff mix of daily and
#   monthly-printing names -- is still open (#751 finding 3).
# Tradeable-era truncation (#751 item 1, decided 2026-08-24): CMR now drops
#   every observation before the earliest TRADEABLE (non-FRED/IMF) date via
#   cmr_tradeable_returns (below), replacing commodities_returns as the input
#   to every signal/portfolio target in this file. This is an INVESTABILITY
#   decision, not a frequency-repair one: the 13 pre-cutoff-only names are
#   IMF Primary Commodity Price System indexes served via FRED
#   (scripts/fetch_commodities.R) -- statistical price indexes, not
#   securities, that cannot be bought or shorted. A backtest era in which
#   every position is untradeable is not a track record, independent of any
#   resampling. See .cmr_truncate_to_tradeable_era() below for the cutoff
#   derivation (computed from the data every run, never a pasted date) and
#   #751 for the full record.
#   NOT done by this change: the 13 IMF/FRED series are NOT removed from the
#   universe -- they keep printing monthly through the present (#751 finding
#   3) and remain part of the post-cutoff cross-section. Whether they should
#   be positions, conditioning data, or dropped post-cutoff is a SEPARATE,
#   still-open decision on #751 -- this truncation does not resolve it.
# Fixed-fraction sizing (#751 item C, decided 2026-08-25, SUPERSEDED below):
#   the fixed n_long = n_short = 10L headcount was replaced by
#   hd_commodity_mr_portfolio()'s frac parameter (1/3, terciles). The old
#   fixed count was infeasible against the tradeable universe alone until
#   2006 (only 6 tradeable series existed as of mid-2000, 16-17 through 2005
#   -- 20 slots could not be filled without reaching into the untradeable
#   IMF/FRED names) and held ~10/24 = ~42% of the universe PER LEG (roughly
#   83% total) by 2015-2026 once 24 tradeable names existed -- the same
#   parameter meaning two structurally different strategies at the two ends
#   of the sample. A fixed fraction was feasible at every breadth
#   automatically, with no cutoff to choose. Superseded by item D below.
# Universe deduplication (#751 item B, implemented after C): the ranked
#   universe held multiple representations of the SAME underlying commodity
#   (WTI crude three times -- POILWTIUSDM IMF index, CL=F futures, USO ETF;
#   gold and silver each twice; four ETF baskets -- DBA, DBB, DBC, PDBC --
#   whose constituents were already held individually). A cross-sectional
#   sort ranks the ranked universe against ITSELF whenever two rows track the
#   same exposure, manufacturing a spurious long/short pair rather than
#   measuring one commodity against another. cmr_deduplicated_returns (below)
#   filters cmr_tradeable_returns down to one instrument per underlying
#   exposure via hd_commodity_mr_dedupe_universe() -- futures preferred over
#   ETF/index twins, per the literature (Miffre-Rallis 2007;
#   Asness-Moskowitz-Pedersen 2013 both rank futures). Every signal/portfolio
#   target below is rewired from cmr_tradeable_returns to
#   cmr_deduplicated_returns. See .HD_CMR_EXPOSURE_MAP's roxygen
#   (packages/historicaldata/R/commodities_mean_reversion.R) for the full
#   MANUAL-mapping rationale and #751 item B for the record.
# Rank-weighting (#751 item D, decided 2026-08-26, REPLACES item C): with
#   item B's deduplication in place, n_avail's median fell to 17, giving a
#   tercile leg of only 5 names -- a thin bucket where the boundary between
#   name 5 (in, full weight) and name 6 (out, zero weight) does a lot of
#   work. hd_commodity_mr_portfolio() no longer buckets into quantiles at
#   all: every ranked name gets a weight proportional to its rank distance
#   from the cross-section's mean rank (Asness-Moskowitz-Pedersen 2013's
#   construction), scaled to the strategy's declared gross exposure
#   (target_gross, default 2.0, matching strategy_gross_convention's
#   existing CMR entry in R/plan_exposure.R). This is scale-free in
#   n_avail (no fraction/headcount parameter to choose), has no bucket-edge
#   discontinuity, and is dollar-neutral / unit-gross BY CONSTRUCTION -- see
#   that function's roxygen for the full derivation, the tie-handling rule,
#   and the minimum-breadth floor (.HD_CMR_MIN_BREADTH_RANK) that replaces
#   item C's ceiling(.HD_CMR_MIN_LEG_NAMES / frac). REPLACES item C's `frac`
#   parameter outright rather than offering both as options -- two live
#   sizing mechanisms would invite silent divergence with no forcing
#   function to revisit either. The `held_frac` breadth diagnostic from item
#   C is retained (now closer to 1.0 by construction) and a new `n_eff`
#   diagnostic (effective breadth, inverse Herfindahl of normalised
#   |weight|) is added as the more meaningful signal under this scheme -- a
#   step toward item F.

plan_commodities_mean_reversion <- function() {
  list(

    # ── Tradeable universe (#751 item 1): truncate to the investable era ──
    # commodities_returns (from plan_commodities_momentum.R) is NOT modified
    # -- that target is shared with commodity momentum, which is out of
    # scope for this decision. CMR gets its own truncated copy here. See the
    # file header above and .cmr_truncate_to_tradeable_era()'s roxygen for
    # the full rationale; this target does date filtering ONLY -- it does
    # not remove any series from the universe.

    targets::tar_target(cmr_tradeable_returns, {
      .cmr_truncate_to_tradeable_era(commodities_returns)
    }),


    # ── Universe deduplication (#751 item B): one instrument per exposure ──
    # Built on cmr_tradeable_returns (#751 item 1) -- date truncation and
    # instrument deduplication are independent decisions, applied in
    # sequence. See the file header above and hd_commodity_mr_dedupe_universe()'s
    # roxygen (packages/historicaldata/R/commodities_mean_reversion.R) for
    # the full rationale. This target does instrument filtering ONLY -- it
    # does not change the date range cmr_tradeable_returns already set.

    targets::tar_target(cmr_deduplicated_returns, {
      hd_commodity_mr_dedupe_universe(cmr_tradeable_returns)
    }),


    # ── Signals: three lookback windows ──────────────────────────────────
    # Built on cmr_deduplicated_returns (#751 items 1 + B), not the raw
    # commodities_returns -- see the targets above.
    # Each signal: mr_signal = -(cumulative return over prior L months).
    # Higher signal -> bigger recent loser -> long candidate.

    targets::tar_target(cmr_signals_1m, {
      hd_commodity_mr_signal(cmr_deduplicated_returns, lookback_months = 1L)
    }),

    targets::tar_target(cmr_signals_3m, {
      hd_commodity_mr_signal(cmr_deduplicated_returns, lookback_months = 3L)
    }),

    targets::tar_target(cmr_signals_6m, {
      hd_commodity_mr_signal(cmr_deduplicated_returns, lookback_months = 6L)
    }),


    # ── Portfolios: long-losers / short-winners ───────────────────────────
    # t+1 execution: signal at t -> trade executes at t+1 closing prices.
    # #751 item D (decided 2026-08-26): rank-weighted, not quantile-bucketed.
    # hd_commodity_mr_portfolio()'s own default (target_gross = 2.0) is used
    # here rather than overridden -- see that function's roxygen for the
    # Asness-Moskowitz-Pedersen citation and the full construction. This
    # replaces item C's fixed fraction (terciles), which in turn replaced the
    # original n_long = n_short = 10L -- see the file header above and #751
    # for the full record of all three constructions.
    # 0.2% one-way transaction cost.
    # returns_tbl is cmr_deduplicated_returns (#751 items 1 + B), matching
    # the signal targets above -- both legs of the t -> t+1 join must be
    # drawn from the same truncated, deduplicated universe.

    targets::tar_target(cmr_portfolio_1m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_1m,
        returns_tbl = cmr_deduplicated_returns,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_3m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_3m,
        returns_tbl = cmr_deduplicated_returns,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_6m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_6m,
        returns_tbl = cmr_deduplicated_returns,
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
    #
    # periodicity_check = "warn" (TEMPORARY STAGING, #738): the #738
    # consistency check fires on CMR's real production data (94/92/90
    # out-of-band gaps against an allowance of 7 -- see the frequency note at
    # the top of this file), so its documented default of "abort" would turn
    # every `tar_make()` red until the mixed-frequency remedy (truncate to
    # 2000+, resample to monthly, or segment and report separately) is chosen
    # on #738. "warn" is the staging lever `.assert_cmr_ann_factor()`
    # documents for exactly this situation: it publishes the finding loudly
    # in every build log without blocking the pipeline. This is NOT a
    # decision that the mixed frequency is acceptable -- it is a decision to
    # keep `main` green while that separate decision is still open.
    # Ends when: the #738 remedy lands and CMR's dates are no longer mixed
    # frequency. At that point the guard passes on its own with the
    # documented "abort" default, and this argument should be DELETED at all
    # three call sites below, not left in place or flipped back manually.

    targets::tar_target(cmr_metrics_1m, {
      .compute_cmr_metrics(cmr_portfolio_1m, lookback = "1m", daily_rf = daily_rf, ann_factor = 252L,
                           periodicity_check = "warn")
    }),

    targets::tar_target(cmr_metrics_3m, {
      .compute_cmr_metrics(cmr_portfolio_3m, lookback = "3m", daily_rf = daily_rf, ann_factor = 252L,
                           periodicity_check = "warn")
    }),

    targets::tar_target(cmr_metrics_6m, {
      .compute_cmr_metrics(cmr_portfolio_6m, lookback = "6m", daily_rf = daily_rf, ann_factor = 252L,
                           periodicity_check = "warn")
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

#' Derive the CMR tradeable-era cutoff date (#751 item 1)
#'
#' The tradeable era begins at the EARLIEST date any tradeable (non-FRED/IMF,
#' i.e. \code{source != "fred_imf"}) observation exists in the supplied
#' returns tibble. Computed from the live data on every call -- never a
#' pasted literal date -- per \code{.claude/rules/fail-loud-not-null.md}'s
#' hand-entered-constant prohibition: the natural definition of "the
#' tradeable era begins" is exactly this quantity, so it is derived rather
#' than typed in, and the cutoff moves automatically if the fetch history
#' changes.
#'
#' Series are classified programmatically by their \code{source} tag, not by
#' a hand-typed list of tickers. \code{scripts/fetch_commodities.R} stamps
#' every row \code{source = "fred_imf"} (the 13 IMF Primary Commodity Price
#' System indexes) or \code{source = "yahoo"} (the tradeable futures/ETF
#' series) at fetch time, and \code{calculate_commodity_returns()}
#' (R/commodities_momentum.R) passes that column through unchanged -- it is
#' never selected away. A hand-typed vector of the 13 IMF tickers would drift
#' the moment the fetch universe changes; reading \code{source} does not.
#'
#' @param returns_tbl Tibble with columns \code{date} and \code{source}
#'   (produced by \code{calculate_commodity_returns()} from
#'   \code{commodities_raw}).
#' @return A single \code{Date}: the earliest date with a tradeable
#'   (non-FRED/IMF) observation.
#' @noRd
.cmr_tradeable_cutoff_date <- function(returns_tbl) {
  if (!"source" %in% names(returns_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} has no {.field source} column.",
      "i" = paste0(
        "Cannot distinguish tradeable (Yahoo futures/ETF) series from ",
        "untradeable (FRED/IMF index) series without it."
      ),
      "i" = paste0(
        "See #751 item 1 and scripts/fetch_commodities.R for the ",
        "source-tagging contract that calculate_commodity_returns() relies on."
      )
    ))
  }
  tradeable_dates <- returns_tbl$date[returns_tbl$source != "fred_imf"]
  if (length(tradeable_dates) == 0L) {
    cli::cli_abort(c(
      "x" = "No tradeable (non-FRED/IMF) commodity observations found in {.arg returns_tbl}.",
      "i" = "Cannot derive the CMR tradeable-era cutoff -- see #751 item 1."
    ))
  }
  min(tradeable_dates)
}

#' Truncate a commodities returns tibble to the tradeable era (#751 item 1)
#'
#' Decision (#751, 2026-08-24): exclude the pre-2000 era from CMR on
#' INVESTABILITY grounds. The pre-cutoff-only names are IMF Primary
#' Commodity Price System indexes served via FRED
#' (\code{scripts/fetch_commodities.R}) -- statistical price indexes, not
#' securities: they cannot be bought and cannot be shorted. A backtest era
#' in which every position is untradeable is not a track record, and no
#' amount of resampling changes that. This is explicitly the
#' INVESTABILITY argument, not a frequency-merge-repair argument -- the
#' mixed-frequency problem (#738) is separate and is NOT resolved by this
#' truncation, because the 13 IMF/FRED series keep printing monthly through
#' the present and remain part of the post-cutoff universe (#751 finding 3).
#'
#' This function ONLY truncates dates. It does NOT remove the FRED/IMF
#' series from the universe -- they remain present (and rankable) after the
#' cutoff. Whether they should be positions, conditioning data, or dropped
#' post-cutoff is a SEPARATE, still-open decision on #751 and is not made
#' here.
#'
#' @param returns_tbl Tibble with columns \code{date}, \code{source} (plus
#'   whatever else \code{calculate_commodity_returns()} produces).
#' @return \code{returns_tbl} filtered to \code{date >= cutoff}, where
#'   \code{cutoff} is derived by \code{\link{.cmr_tradeable_cutoff_date}}.
#' @noRd
.cmr_truncate_to_tradeable_era <- function(returns_tbl) {
  cutoff  <- .cmr_tradeable_cutoff_date(returns_tbl)
  dropped <- sum(returns_tbl$date < cutoff)

  cli::cli_inform(c(
    "v" = paste0(
      "CMR (#751 item 1): truncated to the tradeable era, {format(cutoff)} onward."
    ),
    "i" = paste0(
      "Dropped {dropped} pre-cutoff observation{?s} (untradeable IMF/FRED-only era). ",
      "FRED/IMF series that continue printing after the cutoff are NOT removed."
    )
  ))

  returns_tbl |> dplyr::filter(.data$date >= cutoff)
}

#' Carry `daily_rf` forward across short non-trading gaps CMR's universe needs (#724)
#'
#' #723 switched CMR to the daily \code{daily_rf} target (#722's fix for the
#' month-vs-day frequency bug), which immediately tripped the #679
#' interior-hole guard: 163 dates CMR's merged universe needs have no
#' \code{daily_rf} row (measured 2026-08-23, against
#' \code{data/raw/commodities.parquet} + the live FF3 daily series -- see
#' #724). Every single one was checked BY HAND against the actual NYSE
#' calendar for that date, not assumed: weekends, New Year's Day, Memorial
#' Day, Independence Day, Labor Day, Thanksgiving, Christmas, Good Friday
#' (1994-04-01), the four-day 9/11 closure (2001-09-11..14), and three
#' presidential state-funeral closures (2004-06-11 Reagan, 2007-01-02 Ford,
#' 2025-01-09 Carter). None were a genuine hole in \code{daily_rf} itself --
#' \code{daily_rf} follows the NYSE trading calendar (it IS the Fama-French
#' daily series), and CMR's 13 FRED monthly commodity series stamp
#' month-start dates without regard to whether the equity market traded that
#' day, while a handful of the 24 Yahoo daily series occasionally carry a
#' stray row on an equity holiday too (e.g. 2002-07-04).
#'
#' A hardcoded holiday table would have missed several of the above on day
#' one (Good Friday and the funeral closures are exactly the kind of
#' one-off this function was written to avoid enumerating) and would still
#' be incomplete for the next one. Instead: for every date `df` needs that
#' falls INSIDE `daily_rf`'s own span but has no row, find the nearest PRIOR
#' available `daily_rf` date (never a later one -- that would be
#' look-ahead) and carry its `rf_ret` forward, but ONLY if that date is
#' within `max_gap_days` calendar days. Every one of the 163 real #724 gaps
#' was <= 4 days from its prior available date (the 9/11 closure was the
#' longest); `max_gap_days = 7L` leaves a week of headroom. A date further
#' than that is left unfilled and falls straight through to
#' \code{.join_rf_series()}'s INTERIOR abort, unchanged -- at that distance
#' something other than a holiday is wrong, and the guard should still fire.
#'
#' This function touches nothing outside CMR: \code{.join_rf_series()}
#' (R/utils_metrics.R) and its other three callers (LTR, ToM, mom_prepeak,
#' #677) are not modified. CMR pre-fills its own COPY of \code{daily_rf}
#' before handing it to that shared guard, so a genuine interior hole --
#' here or on any other strategy's rf join -- still aborts exactly as
#' before.
#'
#' @param df Tibble with a `date` column (CMR's daily portfolio).
#' @param daily_rf Tibble with columns `date`, `rf_ret` (the `daily_rf`
#'   target, R/plan_stock_backtest.R).
#' @param lookback Character. Lookback label, used only for the inform message.
#' @param max_gap_days Integer. Maximum calendar-day distance to the nearest
#'   prior available `daily_rf` date that may be carried forward. See #724
#'   for how this bound was set.
#' @return `daily_rf` with synthetic LOCF rows appended for short gaps that
#'   `df` needs; dates further than `max_gap_days` from the nearest prior
#'   available rate are left uncovered.
#' @noRd
.cmr_fill_non_trading_rf_gaps <- function(df, daily_rf, lookback, max_gap_days = 7L) {
  needed    <- sort(unique(as.Date(df$date)))
  rf_dates  <- sort(unique(as.Date(daily_rf$date)))
  if (length(rf_dates) == 0L) return(daily_rf)  # let .join_rf_series report the real problem

  rf_min <- min(rf_dates)
  rf_max <- max(rf_dates)

  missing  <- needed[!(needed %in% rf_dates)]
  interior <- missing[missing >= rf_min & missing <= rf_max]
  if (length(interior) == 0L) return(daily_rf)

  fill_dates <- as.Date(character(0))
  fill_gaps  <- integer(0)

  # NOTE: `for (d in interior)` would silently strip the Date class on each
  # iteration (a base-R for-loop gotcha) -- index instead, per #724 review.
  for (i in seq_along(interior)) {
    d <- interior[i]
    prior_candidates <- rf_dates[rf_dates < d]
    if (length(prior_candidates) == 0L) next  # defensive; d >= rf_min makes this unreachable
    prior <- max(prior_candidates)
    gap   <- as.numeric(d - prior)
    if (gap <= max_gap_days) {
      fill_dates <- c(fill_dates, d)
      fill_gaps  <- c(fill_gaps, gap)
    }
  }

  if (length(fill_dates) == 0L) return(daily_rf)

  # NOTE: vapply()/sapply() also silently drop the Date class from a Date
  # return value (they unlist() the result) -- round-trip through numeric
  # explicitly rather than relying on FUN.VALUE to preserve it (#724 review;
  # same underlying gotcha as the for-loop fix above).
  prior_for <- as.Date(
    vapply(fill_dates, function(d) as.numeric(max(rf_dates[rf_dates < d])), numeric(1)),
    origin = "1970-01-01"
  )
  filled_rows <- tibble::tibble(
    date   = fill_dates,
    rf_ret = daily_rf$rf_ret[match(prior_for, daily_rf$date)]
  )

  cli::cli_inform(c(
    "v" = paste0(
      "CMR {lookback}: carried daily_rf forward for {length(fill_dates)} ",
      "non-trading date{?s} inside its own span (weekends/market holidays; ",
      "longest gap to the prior available rate was {max(fill_gaps)} day{?s})."
    ),
    "i" = "Dates more than {max_gap_days} day{?s} from the prior available rate are left uncovered and still abort via the #679 interior-hole guard."
  ))

  dplyr::bind_rows(daily_rf, filled_rows) |> dplyr::arrange(.data$date)
}

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

#' Per-periodicity gap tolerances for the CMR periodicity guard (#738)
#'
#' One row per recognised annualisation factor. \code{min_gap}/\code{max_gap}
#' bound a SINGLE inter-observation gap that is still consistent with that
#' declared periodicity. They are calendar-day bounds, and each is argued
#' from a calendar fact rather than picked to make the current data pass:
#'
#' \describe{
#'   \item{252 (daily), 1-10 days}{Nominal spacing is 365.25/252 = 1.45
#'     calendar days. The upper bound must absorb the worst real gap a
#'     genuine business-daily series produces. The longest US market closure
#'     since 1990 is 9/11 (last print 2001-09-10, next 2001-09-17 -- a
#'     7-calendar-day gap); Christmas/New-Year holidays adjacent to a weekend
#'     reach 4-5; Hurricane Sandy (2012) gave 4. 10 clears the worst observed
#'     with headroom and still sits a full 3 weeks below a monthly spacing
#'     (28-31 days), so a monthly observation can never be mistaken for a
#'     long holiday. Lower bound 1: a date-keyed series cannot be denser
#'     than one observation per calendar day.}
#'   \item{52 (weekly), 4-24 days}{Nominal 7.02. Upper bound tolerates two
#'     consecutive missing weeks plus slack; lower bound rejects
#'     sub-half-week spacing, which indicates daily data mislabelled weekly.}
#'   \item{12 (monthly), 20-75 days}{Nominal 30.44. Lower bound 20 clears a
#'     28-day February with margin while rejecting weekly-or-denser prints;
#'     upper bound 75 tolerates one entirely missing month (2 x 31 = 62)
#'     plus slack, while staying below a quarterly spacing.}
#'   \item{4 (quarterly), 60-200 days}{Nominal 91.31. Same construction: one
#'     missing quarter tolerated, monthly spacing rejected.}
#' }
#'
#' @noRd
CMR_PERIODICITY_TOLERANCE <- tibble::tibble(
  ann_factor = c(252L, 52L, 12L, 4L),
  label      = c("daily", "weekly", "monthly", "quarterly"),
  min_gap    = c(1, 4, 20, 60),
  max_gap    = c(10, 24, 75, 200)
)

#' Fraction of gaps allowed to fall outside the declared periodicity's band
#'
#' The smallest frequency REGIME CHANGE worth catching is a single year of a
#' different periodicity embedded in a longer series -- 12 monthly
#' observations inside a ~27-year daily series (~6800 gaps) is 0.18% of
#' gaps. 0.1% therefore catches a one-year regime change with roughly 2x
#' margin, while anything below it is an isolated vendor outage rather than
#' a change of periodicity. Deliberately NOT zero: a single missing print in
#' a decades-long series is a data hiccup, not a mis-declared frequency, and
#' a guard that aborts the whole pipeline on one bad row would be turned off
#' rather than fixed.
#'
#' @noRd
CMR_PERIODICITY_MAX_OUT_OF_BAND_FRAC <- 0.001

#' Minimum absolute number of out-of-band gaps tolerated, regardless of n
#'
#' On a short series the fraction above rounds down to zero, so one isolated
#' outage would abort. This floor keeps the tolerance at "at least two
#' isolated gaps" for any series length, so the guard fires on a PATTERN and
#' never on a single print.
#'
#' @noRd
CMR_PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE <- 2L

#' Reconcile a declared `ann_factor` against the observed date frequency
#'
#' Guard from #717 (fail-loud-not-null.md Required Pattern 5), rewritten for
#' #738. Deliberately placed at the point where \code{ann_factor} is
#' SUPPLIED to \code{.compute_cmr_metrics()} -- not buried in the CAGR/vol
#' arithmetic further down -- so a future caller that passes the wrong
#' constant fails immediately, on the value it got wrong, rather than
#' producing a plausible-looking but silently mis-annualised number (exactly
#' what happened with \code{ann_factor = 12L} against CMR's actually-daily
#' data).
#'
#' Two checks, in order:
#'
#' \enumerate{
#'   \item \strong{Classification} (unchanged from #720). The MEDIAN gap
#'     between distinct sorted dates is mapped to an expected
#'     \code{ann_factor} and compared against the declared one. The median is
#'     the right statistic for this question -- "what is the typical
#'     spacing" -- because it is robust to the weekend/holiday gaps every
#'     real business-daily series carries.
#'   \item \strong{Consistency} (new, #738). Counts the gaps falling OUTSIDE
#'     \code{CMR_PERIODICITY_TOLERANCE}'s band for the declared periodicity,
#'     and aborts when that count exceeds
#'     \code{max(CMR_PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE,
#'     ceiling(CMR_PERIODICITY_MAX_OUT_OF_BAND_FRAC * n_gaps))}.
#' }
#'
#' Check 2 exists because check 1 alone cannot see a series that CHANGES
#' frequency partway through. #738 measured \code{cmr_portfolio_1m} as 12
#' observations/year before 2000 and ~255/year after: 94 of 6851 gaps are
#' monthly, 6757 are daily, and the series is declared daily throughout.
#' The overall median gap is 1 day, so 94 monthly gaps out of 6851 cannot
#' move it and check 1 passes -- correctly by its own logic, on a series
#' where 1.4% of observations sit at a twenty-one-fold different frequency.
#' A median is precisely the statistic chosen to be insensitive to the
#' minority that reveals the answer is "no". The property we want is "is the
#' spacing CONSISTENT with one declared periodicity", which is a question
#' about dispersion, and no measure of central tendency can answer it.
#'
#' The tolerance is a count of out-of-band gaps rather than a requirement
#' that all gaps be identical, because holidays and short weeks mean a naive
#' equality test false-positives on every genuine daily series. See
#' \code{CMR_PERIODICITY_TOLERANCE} and
#' \code{CMR_PERIODICITY_MAX_OUT_OF_BAND_FRAC} for how each bound is argued.
#'
#' @param dates A date vector (one entry per observation; duplicates and
#'   unsorted input are handled).
#' @param ann_factor Integer. The annualisation factor about to be used.
#' @param lookback Character. Lookback label, used only for the abort message.
#' @param on_violation One of `"abort"` (default) or `"warn"`. Governs the
#'   CONSISTENCY check only -- the classification check always aborts.
#'   `"warn"` exists solely as a staging lever: the consistency check fires
#'   on CMR's production data as it stands today (that is the point -- see
#'   #738), so landing it in abort mode turns the build red until CMR's
#'   remedy is chosen. Setting the three `cmr_metrics_*` call sites to
#'   `"warn"` for one release lets the finding be published without blocking
#'   the pipeline. It is NOT a way to keep a mixed-frequency series in
#'   production indefinitely.
#' @return `NULL`, invisibly. Called for its abort side effect.
#' @noRd
.assert_cmr_ann_factor <- function(dates, ann_factor, lookback,
                                   on_violation = c("abort", "warn")) {
  on_violation <- match.arg(on_violation)

  d <- sort(unique(as.Date(dates)))
  if (length(d) < 3L) {
    # Too few points for a frequency to be meaningfully observed.
    return(invisible(NULL))
  }
  gaps <- as.numeric(diff(d))
  median_gap <- stats::median(gaps)

  # ── Check 1: classification (median gap -> expected ann_factor) ──────────
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

  # ── Check 2: consistency (dispersion of gaps, not their centre) ──────────
  tol <- CMR_PERIODICITY_TOLERANCE[
    CMR_PERIODICITY_TOLERANCE$ann_factor == ann_factor, , drop = FALSE
  ]
  if (nrow(tol) != 1L) {
    cli::cli_abort(c(
      "x" = "CMR {lookback}: no periodicity tolerance defined for declared ann_factor {ann_factor}.",
      "i" = "Known factors: {.val {CMR_PERIODICITY_TOLERANCE$ann_factor}}.",
      "i" = "Add a row to CMR_PERIODICITY_TOLERANCE rather than skipping the consistency check."
    ))
  }

  n_gaps    <- length(gaps)
  too_short <- gaps < tol$min_gap
  too_long  <- gaps > tol$max_gap
  n_out     <- sum(too_short) + sum(too_long)
  allowance <- max(
    CMR_PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE,
    ceiling(CMR_PERIODICITY_MAX_OUT_OF_BAND_FRAC * n_gaps)
  )

  if (n_out > allowance) {
    # Name the observed bands and their counts, per fail-loud-not-null.md:
    # the reader must be able to see WHICH minority frequency is present
    # without re-deriving it.
    obs_band <- vapply(
      gaps,
      function(g) {
        hit <- which(g >= CMR_PERIODICITY_TOLERANCE$min_gap &
                       g <= CMR_PERIODICITY_TOLERANCE$max_gap)
        if (length(hit) == 0L) "unclassified" else CMR_PERIODICITY_TOLERANCE$label[hit[1]]
      },
      character(1)
    )
    band_counts <- sort(table(obs_band), decreasing = TRUE)
    band_txt <- paste0(names(band_counts), ": ", as.integer(band_counts), collapse = "; ")

    out_gaps  <- gaps[too_short | too_long]
    where_out <- d[-1L][too_short | too_long]

    msg <- c(
      "x" = paste0(
        "CMR {lookback}: the observation spacing is NOT consistent with a ",
        "single declared periodicity (ann_factor {ann_factor}, {tol$label})."
      ),
      "i" = paste0(
        "{n_out} of {n_gaps} gaps ({round(100 * n_out / n_gaps, 3)}%) fall outside the ",
        "{tol$label} band [{tol$min_gap}, {tol$max_gap}] calendar days; ",
        "allowance is {allowance}."
      ),
      "i" = "Observed gap bands: {band_txt}.",
      "i" = paste0(
        "Out-of-band gaps range {min(out_gaps)}-{max(out_gaps)} calendar days, ",
        "spanning {format(min(where_out))}..{format(max(where_out))}."
      ),
      "i" = paste0(
        "The median gap ({median_gap} calendar days) agrees with the declared ",
        "factor, which is why the #720 median-gap check passes -- a median cannot ",
        "see a minority at a different frequency. See #738."
      ),
      "i" = "See .claude/rules/fail-loud-not-null.md Required Pattern 5."
    )

    if (identical(on_violation, "warn")) {
      cli::cli_warn(msg)
    } else {
      cli::cli_abort(msg)
    }
  }

  invisible(NULL)
}

.compute_cmr_metrics <- function(portfolio_tbl, lookback, daily_rf, ann_factor = 252L,
                                 periodicity_check = c("abort", "warn")) {
  library(dplyr)
  periodicity_check <- match.arg(periodicity_check)

  df <- portfolio_tbl |>
    dplyr::filter(!is.na(.data$net_ret)) |>
    dplyr::mutate(date = as.Date(.data$date))

  # #717 guard: declared ann_factor must match the observed frequency of
  # this portfolio's own dates, checked at the point ann_factor is supplied.
  # #738 extends it from "is the TYPICAL spacing right" to "is the spacing
  # CONSISTENT" -- see .assert_cmr_ann_factor()'s roxygen. `periodicity_check`
  # is the staging lever documented there; production call sites use the
  # abort default.
  .assert_cmr_ann_factor(df$date, ann_factor, lookback,
                         on_violation = periodicity_check)

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
  # #724: daily_rf follows the NYSE trading calendar; CMR's merged universe
  # needs some dates NYSE didn't trade (weekends, holidays, one-off
  # closures). Pre-fill short (<=7 calendar day) non-trading gaps via LOCF
  # before the shared #679 guard runs -- genuine interior holes still abort.
  daily_rf_filled <- .cmr_fill_non_trading_rf_gaps(df, daily_rf, lookback = lookback)
  df <- .cmr_join_rf(df, daily_rf_filled, lookback = lookback)
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
