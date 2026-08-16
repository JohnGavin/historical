# Plan: Strategy Transaction-Cost Convention Registry (#624)
#
# Measurement only. No target here changes any strategy's construction,
# weights, or returns -- this plan documents, as data, the transaction-cost
# assumption each strategy's own code already applies (or, in several rows,
# does not apply).
#
# Origin: `audits/cost-assumptions-2026-06-04.md` flagged `drif` and
# `fac_max` as CRITICAL (0% cost, apples-to-oranges against cost-charging
# rows) and `rsc` as MAJOR (0% cost on regime switches). Issue #425 closed
# those three gaps after the audit was written -- every value below was
# re-verified against current code on 2026-08-04 and several entries in
# this registry therefore DIFFER from the 2026-06-04 audit. The audit
# document is left unmodified as a historical record; this registry is the
# current source of truth.
#
# `strategy` values match the display labels used by the `leaderboard`
# target's own `strategy` column (see R/plan_leaderboard.R, `add_meta()`
# calls) -- the same join key used by `strategy_gross_convention`
# (R/plan_exposure.R), including the "OLMAR-1" naming gap documented there
# (#626, #629: `strategy_names` is missing an `olmar` row).
#
# `cost_per_trade_bps`: the transaction-cost figure the strategy's own code
#   deducts, in basis points, verified against source at the commit this
#   file was authored against. This is NOT always a per-trade, round-trip
#   figure -- `cost_convention` (below) states the actual unit and timing,
#   because the underlying strategies charge cost in three genuinely
#   different ways (per-trade on turnover, per calendar month regardless of
#   turnover, per discrete regime/state switch). Treating the number alone
#   as directly comparable across rows would be exactly the kind of
#   apples-to-oranges error #624 exists to prevent. NA only where no cost
#   figure exists in the strategy's own code (never a substituted default).
# `cost_convention`: short description of how `cost_per_trade_bps` is
#   applied -- unit + timing + which legs it covers.
# `borrow_rate_annual`: annualised borrow-cost fraction charged on short
#   positions, where the strategy's own code applies one. NA where the
#   strategy is long-only (no short leg exists) OR where a short leg exists
#   but no borrow cost is modelled for it (`cost_source_ref` states which).
# `cost_source_ref`: "file:line" of the code this claim was verified
#   against.
#
# ─────────────────────────────────────────────────────────────────────────
# #664: `borrow_rate_annual == NA` conflates two very different states --
# "no short leg, borrow correctly not applicable" and "short leg exists,
# borrow genuinely unmodelled" -- and the distinction previously lived only
# as free prose in `cost_source_ref`, which nothing can filter, sort, count,
# or gate on (fail-loud-not-null.md). `borrow_status` below makes it
# machine-readable.
#
# BORROW_STATUS_ALLOWED is the single source of truth for the vocabulary
# (same pattern as PERIOD_LABELS_ALLOWED, R/plan_partitions.R):
#   - "not_applicable"     -- long-only or overlay; genuinely no short leg.
#   - "modelled"            -- short leg exists; borrow_rate_annual is set.
#   - "unmodelled"           -- short leg exists; NO borrow cost charged --
#                              the defect class #664 exists to surface.
#   - "embedded_in_source"   -- the short leg is inside a pre-computed factor
#                              return series (e.g. HML), not separately
#                              financeable by our own code.
#   - "inherited"            -- a meta-portfolio blending already-net
#                              constituent returns; borrow (if any) is a
#                              property of the constituents, not this row.
#   - "not_tradeable"        -- registry states this is not a tradeable
#                              strategy at all (no cost model of any kind).
BORROW_STATUS_ALLOWED <- c(
  "not_applicable", "modelled", "unmodelled",
  "embedded_in_source", "inherited", "not_tradeable"
)

# Documented borrow_status overrides (#664). `strategy_names$directionality`
# plus borrow_rate_annual presence/absence is sufficient to derive
# not_applicable / modelled / unmodelled for MOST rows (see
# derive_borrow_status() below) -- but four rows need a status that
# directionality alone cannot distinguish. Each override is verified against
# source at the commit this file was authored against, same convention as
# `cost_source_ref` above:
#
#   - "Value (HML)": directionality is long_only (this strategy's own
#     construction never holds a separately-tradeable short position), but
#     the HML factor value ITSELF nets a long-value/short-growth spread
#     inside the pre-computed Fama-French series (R/plan_ev_ebit.R:33,79) --
#     "embedded_in_source", not "not_applicable".
#   - "PSO Optimal": directionality is long_only (blend weights are all
#     >= 0), but it is a meta-portfolio over already-net constituent returns
#     (R/plan_portfolio_opt.R), several of which ARE long_short with their
#     own borrow_status -- "inherited", not "not_applicable".
#   - "Avoid Worst": directionality is "overlay" like Risk State/TOM, but
#     unlike those two it has NO cost model of any kind implemented in code
#     (R/plan_avoid_worst.R:5, "NOT a tradeable strategy") -- "not_tradeable",
#     distinct from an overlay that simply never needs to borrow.
#   - "Managed Futures": directionality is long_short (the TSM sleeve does
#     take short positions), but futures financing is embedded in the
#     futures price itself, not a separately-financeable equity-style
#     short-borrow cost (R/plan_managed_futures.R). This is a JUDGEMENT
#     CALL, not a verified absence like the other three rows -- flagged in
#     the PR body for review rather than asserted as settled fact.
BORROW_STATUS_OVERRIDES <- tibble::tibble(
  strategy = c("Value (HML)", "PSO Optimal", "Avoid Worst", "Managed Futures"),
  borrow_status_override = c(
    "embedded_in_source", "inherited", "not_tradeable", "not_applicable"
  )
)

#' Derive each strategy's borrow_status from directionality + rate presence (#664)
#'
#' Pure, vectorised, unit-testable. Fails loud (fail-loud-not-null.md) rather
#' than defaulting to NA: an unrecognised directionality, a missing
#' directionality with no override, or an override outside
#' BORROW_STATUS_ALLOWED all `cli_abort()`.
#'
#' @param strategy Character vector. Strategy display names, used only in
#'   error messages.
#' @param directionality Character vector (same length as `strategy`). Values
#'   from `strategy_names$directionality` (R/plan_strategy_names.R):
#'   long_only, long_short, market_neutral, overlay -- or NA if the strategy
#'   has no `strategy_names` row (see the OLMAR-1 fill in the
#'   `strategy_cost_convention` target below) and no override.
#' @param has_borrow_rate Logical vector (same length). `TRUE` where
#'   `borrow_rate_annual` is non-NA in the cost registry.
#' @param override Character vector (same length), or NA where no override
#'   applies. Values from BORROW_STATUS_OVERRIDES take priority over the
#'   directionality-based derivation.
#' @return Character vector of borrow_status values, each a member of
#'   BORROW_STATUS_ALLOWED.
#' @noRd
derive_borrow_status <- function(strategy, directionality, has_borrow_rate,
                                  override = NA_character_) {
  n <- length(strategy)
  if (length(directionality) != n || length(has_borrow_rate) != n) {
    cli::cli_abort(c(
      "x" = "derive_borrow_status(): strategy, directionality, has_borrow_rate must be the same length."
    ))
  }
  if (length(override) == 1L) override <- rep(override, n)
  if (length(override) != n) {
    cli::cli_abort(c("x" = "derive_borrow_status(): override must have length 1 or {n}."))
  }

  vapply(seq_len(n), function(i) {
    ov <- override[i]
    if (!is.na(ov)) {
      if (!ov %in% BORROW_STATUS_ALLOWED) {
        cli::cli_abort(c(
          "x" = "{.val {strategy[i]}}: override borrow_status {.val {ov}} is not in the allowed set.",
          "i" = "Allowed values: {paste(BORROW_STATUS_ALLOWED, collapse = ', ')}."
        ))
      }
      return(ov)
    }

    d <- directionality[i]
    if (is.na(d)) {
      cli::cli_abort(c(
        "x" = "{.val {strategy[i]}}: cannot derive borrow_status -- directionality is NA and no override is set.",
        "i" = "Add a row to strategy_names (R/plan_strategy_names.R) or an entry to BORROW_STATUS_OVERRIDES (R/plan_cost_convention.R)."
      ))
    }
    if (d %in% c("long_only", "overlay")) {
      return("not_applicable")
    }
    if (d %in% c("long_short", "market_neutral")) {
      return(if (isTRUE(has_borrow_rate[i])) "modelled" else "unmodelled")
    }
    cli::cli_abort(c(
      "x" = "{.val {strategy[i]}}: unrecognised directionality {.val {d}}.",
      "i" = "Allowed values: long_only, long_short, market_neutral, overlay."
    ))
  }, character(1L))
}

# ─────────────────────────────────────────────────────────────────────────
# #665 (quantification only): borrow-rate sensitivity sweep.
#
# REPORTING ONLY. Nothing here feeds `leaderboard` / `all_metrics` / any
# published return -- it answers "what WOULD Sharpe/CAGR be at borrow rate
# X", holding trade costs, signal, and weights fixed. See
# `borrow_sensitivity_sweep` target below for how each strategy's PRE-BORROW
# monthly return series is assembled.

#' Recompute CAGR/Sharpe/vol at a swept annual borrow rate (#665)
#'
#' The borrow charge is applied at `rate / 12` per month against
#' `short_notional_frac` of NAV -- the convention every borrow-charging
#' strategy in this codebase already uses for a monthly-rebalanced,
#' dollar-neutral decile long-short book (verified: R/plan_stock_backtest.R
#' `portfolio_longshort()`, `borrow_cost <- borrow_rate_annual / 12`;
#' R/plan_mom_prepeak.R:224-228, weight = +-1/n_leg per leg, i.e. 100% leg
#' notional; packages/historicaldata/R/commodities_mean_reversion.R:185,
#' same +-1/n_leg convention). CAGR/vol/Sharpe formulas mirror
#' `calc_backtest_metrics()` (R/plan_stock_backtest.R:431) with the
#' risk-free adjustment omitted -- this function reports RELATIVE deltas
#' across borrow rates for a single strategy, so a constant rf term would
#' cancel in `sharpe_delta` and is left out for simplicity (noted, not
#' silently assumed away).
#'
#' @param monthly_ret_pre_borrow Numeric vector, monthly portfolio returns
#'   BEFORE any borrow charge (trade costs already deducted). No NA allowed
#'   -- filter upstream.
#' @param borrow_rates_annual Numeric vector of annual borrow rates to sweep.
#'   MUST include 0 (the baseline `sharpe_delta` is computed against).
#' @param short_notional_frac Numeric scalar in `[0, 1]`. Fraction of NAV
#'   held short each period. Default `1` (100%, per the verified convention
#'   above).
#' @return Tibble: borrow_rate_annual, cagr, vol, sharpe, sharpe_delta
#'   (sharpe at this rate minus sharpe at rate 0).
#' @noRd
compute_borrow_sensitivity <- function(monthly_ret_pre_borrow,
                                        borrow_rates_annual = c(0, 0.03, 0.10, 0.25),
                                        short_notional_frac = 1) {
  if (!is.numeric(monthly_ret_pre_borrow) || length(monthly_ret_pre_borrow) < 12L) {
    cli::cli_abort(c(
      "x" = "compute_borrow_sensitivity() requires >= 12 monthly returns.",
      "i" = "Got {length(monthly_ret_pre_borrow)}."
    ))
  }
  if (anyNA(monthly_ret_pre_borrow)) {
    cli::cli_abort(c(
      "x" = "compute_borrow_sensitivity(): monthly_ret_pre_borrow contains NA.",
      "i" = "Filter NA out before calling -- never coerced or dropped silently here."
    ))
  }
  if (!is.numeric(short_notional_frac) || length(short_notional_frac) != 1L ||
      is.na(short_notional_frac) || short_notional_frac < 0 || short_notional_frac > 1) {
    cli::cli_abort(c(
      "x" = "short_notional_frac must be a single numeric value in [0, 1].",
      "i" = "Got {short_notional_frac}."
    ))
  }
  if (!0 %in% borrow_rates_annual) {
    cli::cli_abort(c(
      "x" = "borrow_rates_annual must include 0 -- it is the sharpe_delta baseline.",
      "i" = "Got: {paste(borrow_rates_annual, collapse = ', ')}."
    ))
  }

  n <- length(monthly_ret_pre_borrow)

  rows <- purrr::map_dfr(borrow_rates_annual, function(rate) {
    monthly_charge <- short_notional_frac * rate / 12
    r       <- monthly_ret_pre_borrow - monthly_charge
    ann_ret <- prod(1 + r)^(12 / n) - 1
    ann_vol <- stats::sd(r) * sqrt(12)
    sharpe  <- ann_ret / ann_vol
    tibble::tibble(
      borrow_rate_annual = rate, cagr = ann_ret, vol = ann_vol, sharpe = sharpe
    )
  })

  sharpe_at_zero <- rows$sharpe[rows$borrow_rate_annual == 0][1]
  rows$sharpe_delta <- rows$sharpe - sharpe_at_zero
  rows
}

#' Apply compute_borrow_sensitivity() across a named list of strategies (#665)
#'
#' @param returns_by_strategy Named list of numeric vectors: PRE-BORROW
#'   monthly returns per strategy (may contain NA -- filtered per-strategy).
#' @param borrow_rates_annual Numeric vector to sweep.
#' @return Tibble: strategy, borrow_rate_annual, cagr, vol, sharpe, sharpe_delta.
#' @noRd
build_borrow_sensitivity_table <- function(returns_by_strategy,
                                            borrow_rates_annual = c(0, 0.03, 0.10, 0.25)) {
  if (!is.list(returns_by_strategy) || length(returns_by_strategy) == 0L ||
      is.null(names(returns_by_strategy)) || any(!nzchar(names(returns_by_strategy)))) {
    cli::cli_abort(c(
      "x" = "build_borrow_sensitivity_table(): returns_by_strategy must be a non-empty NAMED list."
    ))
  }
  purrr::imap_dfr(returns_by_strategy, function(r, strategy) {
    r <- r[!is.na(r)]
    sweep <- compute_borrow_sensitivity(r, borrow_rates_annual)
    dplyr::mutate(sweep, strategy = strategy, .before = 1L)
  })
}

plan_cost_convention <- function() {
  list(
    targets::tar_target(strategy_cost_convention, {
      base <- tibble::tibble(
        strategy = c(
          "Factor MAX", "Factor DRIF",
          "Stock MAX", "Stock DRIF", "XGB DRIF",
          "LTR", "OLMAR-1", "TOM", "CMR", "Risk State", "Avoid Worst",
          "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
          "Value (HML)", "Managed Futures", "PSO Optimal"
        ),
        cost_per_trade_bps = c(
          10, 10,
          50, 50, 50,
          10, 10, 5, 20, 5, 0,
          10, 10, 10,
          20, 10, NA_real_
        ),
        cost_convention = c(
          "per-trade bps, round-trip (turnover x2)",
          "per-trade bps, round-trip (turnover x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip (2x cost_per_trade)",
          "per-trade bps, applied to turnover directly",
          "per-switch bps, round-trip (only on month-end switch days)",
          "per-trade bps, one-way",
          "per-trade bps, one-way (only on regime-switch days)",
          "none -- no cost model implemented in code",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-calendar-month bps, NOT per-trade (charged regardless of turnover)",
          "per-calendar-month bps, NOT per-trade (ETF proxy; comment notes real futures ~20bps)",
          "meta-portfolio -- no separate cost applied at blend level; inherits constituents' already-net returns"
        ),
        borrow_rate_annual = c(
          NA_real_, NA_real_,
          0.03, 0.03, 0.03,
          0.03, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_,
          NA_real_, NA_real_, NA_real_,
          NA_real_, NA_real_, NA_real_
        ),
        cost_source_ref = c(
          "R/plan_factormax.R:27 (cost_per_trade = 0.001), R/plan_factormax.R:134 (cost <- fm_params$cost_per_trade * turnover * 2.0); no short leg -- borrow NA",
          "R/plan_drif.R:30 (cost_per_trade = 0.001), R/plan_drif.R:238 (cost <- drif_params$cost_per_trade * turnover * 2.0); no short leg -- borrow NA",
          "R/plan_stock_backtest.R:392-393 (stk_params: cost_per_trade = 0.005, borrow_rate_annual = 0.03), R/plan_stock_backtest.R:56-98 (portfolio_longshort(): trade_cost = turnover*cost_per_trade*2*2; borrow_cost = borrow_rate_annual/12)",
          "R/plan_stock_backtest.R:392-393 (stk_params, shared with Stock MAX), R/plan_stock_backtest.R:56-98 (portfolio_longshort(), same shared helper)",
          "R/plan_xgb_signal.R:129-130 (passes stk_params$cost_per_trade / borrow_rate_annual into the shared helper), R/plan_stock_backtest.R:56-98 portfolio_longshort()",
          "R/plan_ltr_momentum.R:27-28 (cost_per_trade = 0.0010, borrow_rate_annual = 0.03), scripts/compute_ltr_model.R:146-150 (cost = 2*cost_per_trade; borrow = borrow_cost_annual/12)",
          "R/plan_olmar.R:30 (cost_bps = 10), R/plan_olmar.R:277 (net_ret = gross_ret - (cost_bps/1e4) * turnover); long-only simplex projection -- borrow NA",
          "R/plan_turn_of_month.R:31 (cost_bps = 5L), R/plan_turn_of_month.R:222 (cost_daily = if_else(is_switch, cost_bps/1e4, 0)); SPY/cash only -- borrow NA",
          "R/plan_commodities_mean_reversion.R:51,61,71 (cost_bps = 20 for all 3 lookback variants); 10-long/10-short construction has no borrow cost modelled for the short leg -- verified absent, not a long-only NA",
          "R/plan_risk_state.R:38 (cost_per_trade = 0.0005, comment: '5 bps one-way ... applied only on regime-switch days'), R/plan_risk_state.R:194 (trade_cost = rsc_params$cost_per_trade * exposure_change * 2.0); exposure in [0.10, 1.00], never short -- borrow NA",
          "R/plan_avoid_worst.R:5 (comment: 'NOT a tradeable strategy'); no cost_per_trade/cost_bps field exists anywhere in this file -- zero is a verified absence, not a default",
          "R/plan_mom_prepeak.R:31 (cost_per_trade = 0.0010, comment: 'matches ltr_params'), R/plan_mom_prepeak.R:338 (ret_ls = ret_long - ret_short - 2*cost_per_trade); 100% short leg exists but no borrow cost is modelled -- verified absent, not a long-only NA",
          "R/plan_mom_prepeak.R:31,338 (same shared param + formula as Mom Pre-Peak); same unmodelled-borrow gap on its 100% short leg",
          "R/plan_mom_prepeak.R:31,338 (same shared param + formula as Mom Pre-Peak); same unmodelled-borrow gap on its 100% short leg",
          "R/plan_ev_ebit.R:33 (cost_per_rebalance = 0.002), R/plan_ev_ebit.R:79 (ret_value_hml = RF + HML - cost); pre-computed FF factor-return series, no explicit short-borrow leg -- borrow NA",
          "R/plan_managed_futures.R:48 (cost_monthly = 0.001, comment: '10 bps/month: ETF proxy (real futures ~20bps)'); no borrow cost field found in this file -- borrow NA",
          "R/plan_portfolio_opt.R (no cost_per_trade/cost_bps field found; w <- w/sum(w) blends already cost-net constituent returns; see R/plan_exposure.R source_ref for the same meta-portfolio caveat on gross exposure)"
        )
      )

      # ── #664: derive borrow_status ────────────────────────────────────
      # strategy_names is the single source of truth for directionality
      # (R/plan_strategy_names.R). Join on strategy == short_name -- the
      # same join key strategy_gross_convention (R/plan_exposure.R) uses.
      #
      # OLMAR-1 has no row in strategy_names (#626/#629 known join gap) --
      # filled explicitly (long-only simplex projection, R/plan_olmar.R:30)
      # rather than left NA (fail-loud-not-null.md): a silently-NA
      # directionality would make derive_borrow_status() abort below, which
      # is correct for a GENUINELY unknown strategy but wrong for a known,
      # documented gap.
      sn_lookup <- dplyr::transmute(
        strategy_names,
        strategy = short_name,
        directionality = as.character(directionality)
      )

      with_direction <- base |>
        dplyr::left_join(sn_lookup, by = "strategy") |>
        dplyr::mutate(
          directionality = dplyr::if_else(
            strategy == "OLMAR-1", "long_only", directionality
          )
        ) |>
        dplyr::left_join(BORROW_STATUS_OVERRIDES, by = "strategy")

      with_status <- with_direction |>
        dplyr::mutate(
          borrow_status = derive_borrow_status(
            strategy        = strategy,
            directionality  = directionality,
            has_borrow_rate = !is.na(borrow_rate_annual),
            override        = borrow_status_override
          )
        ) |>
        dplyr::select(-directionality, -borrow_status_override)

      # Visible at every tar_make() (fail-loud-not-null.md: an unrecognised /
      # unmodelled state must be visible, never silently absorbed).
      unmodelled <- with_status$strategy[with_status$borrow_status == "unmodelled"]
      if (length(unmodelled) > 0L) {
        cli::cli_warn(c(
          "!" = paste0(
            length(unmodelled), " strategy/strategies have a short leg with ",
            "NO borrow cost modelled (#664):"
          ),
          setNames(sprintf("  %s", unmodelled), rep("i", length(unmodelled))),
          "i" = paste0(
            "See the borrow_status column of strategy_cost_convention ",
            "(R/plan_cost_convention.R) and the borrow_sensitivity_sweep ",
            "target for the CAGR/Sharpe impact at borrow != 0 (#665)."
          )
        ))
      }

      with_status
    }),

    # ── #665 (quantification only): borrow-rate sensitivity sweep ───────
    #
    # REPORTING ONLY -- see build_borrow_sensitivity_table() /
    # compute_borrow_sensitivity() roxygen above. Does NOT feed leaderboard,
    # all_metrics, or any published return. Covers the 4 currently-
    # "unmodelled" strategies (their whole edge is at stake if a borrow cost
    # is ever added) plus the 4 currently-"modelled" strategies (so a reader
    # can see how sensitive the already-costed strategies are to the flat
    # 0.03 rate being wrong -- see the `# MANUAL: no source` markers on that
    # constant in R/plan_stock_backtest.R and R/plan_ltr_momentum.R).
    #
    # Each series is reconstructed as the PRE-BORROW monthly return:
    #   - unmodelled strategies: their return series already has zero
    #     borrow charge, so it is used as-is.
    #   - modelled strategies: the currently-applied 0.03/12 monthly charge
    #     is added back (port_ret + borrow_cost, or ls_ret_net + borrow for
    #     LTR's pre-computed parquet columns) so the sweep starts from the
    #     same zero-borrow baseline as the unmodelled strategies.
    #
    # CMR reports 3 lookback variants (1m/3m/6m); the leaderboard displays
    # whichever has the best Sharpe (.norm_cmr(), R/plan_leaderboard.R) --
    # the same "best lookback" selection is replicated here from cmr_summary
    # so the swept strategy matches what is actually published.
    targets::tar_target(borrow_sensitivity_sweep, {
      cmr_best <- cmr_summary$lookback[which.max(cmr_summary$sharpe)]
      cmr_port <- switch(cmr_best,
        "1m" = cmr_portfolio_1m,
        "3m" = cmr_portfolio_3m,
        "6m" = cmr_portfolio_6m,
        cli::cli_abort(c(
          "x" = "borrow_sensitivity_sweep: unrecognised CMR lookback {.val {cmr_best}} selected by cmr_summary.",
          "i" = "Allowed values: 1m, 3m, 6m (R/plan_commodities_mean_reversion.R)."
        ))
      )

      returns_by_strategy <- list(
        "Mom Pre-Peak"  = mom_prepeak_returns$ret_ls,
        "Mom Post-Peak" = mom_postpeak_returns$ret_ls,
        "Mom 12-2"      = mom_combined_returns$ret_ls,
        "CMR"           = cmr_port$net_ret,
        "Stock MAX"     = stk_max_portfolio$port_ret + stk_max_portfolio$borrow_cost,
        "Stock DRIF"    = stk_drif_portfolio$port_ret + stk_drif_portfolio$borrow_cost,
        "XGB DRIF"      = xgb_drif_portfolio$port_ret + xgb_drif_portfolio$borrow_cost,
        "LTR"           = ltr_portfolio$ls_ret_net + ltr_portfolio$borrow
      )

      out <- build_borrow_sensitivity_table(returns_by_strategy)

      cli::cli_inform(c("v" = paste0(
        "borrow_sensitivity_sweep: ", dplyr::n_distinct(out$strategy),
        " strategies x ", length(unique(out$borrow_rate_annual)),
        " borrow rates (reporting only, #665; CMR variant = ", cmr_best, ")"
      )))
      out
    })
  )
}
