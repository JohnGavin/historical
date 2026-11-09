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
# (R/plan_exposure.R). `strategy_names` was missing an `olmar` row when this
# file was authored (#626, #629), but that gap was closed in #747; the
# `by = "strategy"` join key is retained here for consistency with
# `strategy_gross_convention`, not because of any remaining gap.
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
#   - "CMR": directionality is long_short (10-long/10-short construction,
#     R/plan_commodities_mean_reversion.R), and it previously derived to
#     "unmodelled" (short leg exists, no borrow_rate_annual set). #665
#     reclassifies it to "not_applicable" -- CMR's universe (verified
#     against data/raw/commodities.parquet: CL=F/GC=F/ZC=F.../ commodity
#     FUTURES, IMF PxxxUSDM price indices, and commodity ETFs DBA/DBC/GLD/
#     USO/...) has no equity-style short-borrow leg at all. Futures
#     financing is embedded in the futures curve, the identical reasoning
#     already used for the Managed Futures override above -- a JUDGEMENT
#     CALL like that row, not a verified absence, flagged in the PR body.
#     Charging CMR an equity borrow rate would be wrong in KIND, not just
#     magnitude, and CMR is the most borrow-sensitive of the eight rows
#     swept by borrow_sensitivity_sweep (-0.58 Sharpe at a flat 3%), so an
#     incorrect rate there does the most damage.
BORROW_STATUS_OVERRIDES <- tibble::tibble(
  strategy = c(
    "Value (HML)", "PSO Optimal", "Avoid Worst", "Managed Futures", "CMR"
  ),
  borrow_status_override = c(
    "embedded_in_source", "inherited", "not_tradeable", "not_applicable",
    "not_applicable"
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
#'   has no `strategy_names` row and no override (see #629/#747: this used
#'   to be OLMAR-1's state before it gained a `strategy_names` row).
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
# #665 (Part 1 of 2): record the securities-lending decision as data.
#
# Securities-lending income was previously modelled NOWHERE -- an absence
# nobody had decided on, not a decision (fail-loud-not-null.md: the null-ish
# state and the deliberate-zero state are indistinguishable unless the
# decision is itself recorded). `lending_status` below is that decision,
# made explicit and machine-readable, alongside `borrow_status` above.
#
# THE DECISION (recorded here, not re-derived -- see the PR body for the
# reasoning that produced it): securities-lending income is deliberately
# modelled as ZERO for every strategy. Not because it is zero, but because
# it is judged IMMATERIAL at this book's composition -- the long book is
# S&P-500-constituent/liquid-ETF names (`ltr_universe`, R/plan_mom_prepeak.R,
# 529 tickers), which lend as general collateral at single-digit bps,
# against a 50bp borrow assumption whose own uncertainty is roughly +-25bp.
# A ~1-5bp revenue line sits below the resolution of everything around it.
# This is a MATERIALITY JUDGEMENT, not a measurement -- `# MANUAL: no
# source` below, the same convention as the unsourced `0.03`/`0.005`
# borrow_rate_annual constants above -- and it stops holding the moment the
# book holds hard-to-borrow names.
#
# LENDING_STATUS_ALLOWED is the single source of truth for the vocabulary,
# deliberately reusing BORROW_STATUS_ALLOWED's non-numeric categories --
# lending shares the same three "no independently-financeable position"
# exceptions borrow already documents (Value (HML), PSO Optimal, Avoid
# Worst -- LENDING_STATUS_OVERRIDES below), because whether a position can
# be lent is symmetric with whether it can be borrowed against: both require
# a position that exists, separately, in this codebase's model.
#   - "zero_assumed_immaterial" -- the default; a real, separately-held long
#                                  position exists, lending income on it is
#                                  assumed zero per the documented judgement
#                                  above.
#   - "embedded_in_source"       -- long exposure is inside a pre-computed
#                                  factor return series, not a
#                                  separately-lendable position.
#   - "inherited"                 -- a meta-portfolio blending already-net
#                                  constituent returns; lending (if any) is a
#                                  property of the constituents, not this row.
#   - "not_tradeable"             -- registry states this is not a tradeable
#                                  strategy at all (no cost model of any
#                                  kind, so no modelled position to lend).
LENDING_STATUS_ALLOWED <- c(
  "zero_assumed_immaterial", "embedded_in_source", "inherited", "not_tradeable"
)

# Three rows have no independently-financeable position at all (regardless
# of side), for the identical reason their borrow_status is overridden away
# from a directionality-derived default -- see BORROW_STATUS_OVERRIDES above
# for the source verification each of these three cites. Managed Futures and
# CMR are NOT in this list: their borrow_status override is about their
# SHORT leg (futures financing embedded in the curve), which says nothing
# about whether their ETF-proxy LONG leg is a real, lendable position -- it
# is, so they take the "zero_assumed_immaterial" default like every other
# row with a real long book.
LENDING_STATUS_OVERRIDES <- tibble::tibble(
  strategy = c("Value (HML)", "PSO Optimal", "Avoid Worst"),
  lending_status_override = c("embedded_in_source", "inherited", "not_tradeable")
)

#' Derive each strategy's lending_status (#665)
#'
#' Every strategy defaults to `"zero_assumed_immaterial"` -- the single,
#' portfolio-level decision documented in the comment block above. Three
#' rows have no independently-financeable position at all, mirroring the
#' identical three borrow_status overrides for the identical reason
#' (`LENDING_STATUS_OVERRIDES`). Fails loud (fail-loud-not-null.md) on an
#' override outside `LENDING_STATUS_ALLOWED` rather than silently accepting
#' it.
#'
#' @param strategy Character vector. Strategy display names, used only in
#'   error messages.
#' @param override Character vector (same length as `strategy`), or NA where
#'   the default applies. Values from `LENDING_STATUS_OVERRIDES`.
#' @return Character vector of lending_status values, each a member of
#'   `LENDING_STATUS_ALLOWED`.
#' @noRd
derive_lending_status <- function(strategy, override = NA_character_) {
  n <- length(strategy)
  if (length(override) == 1L) override <- rep(override, n)
  if (length(override) != n) {
    cli::cli_abort(c("x" = "derive_lending_status(): override must have length 1 or {n}."))
  }

  vapply(seq_len(n), function(i) {
    ov <- override[i]
    if (!is.na(ov)) {
      if (!ov %in% LENDING_STATUS_ALLOWED) {
        cli::cli_abort(c(
          "x" = "{.val {strategy[i]}}: override lending_status {.val {ov}} is not in the allowed set.",
          "i" = "Allowed values: {paste(LENDING_STATUS_ALLOWED, collapse = ', ')}."
        ))
      }
      return(ov)
    }
    "zero_assumed_immaterial"
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
#' @param ret_pre_borrow Numeric vector, portfolio returns BEFORE any borrow
#'   charge (trade costs already deducted), one per period. No NA allowed
#'   -- filter upstream.
#' @param ann_factor Single positive finite number: periods per year of
#'   `ret_pre_borrow` (12 monthly, 252 daily). REQUIRED, never inferred from
#'   `n` (#936: the daily CMR series was annualised as monthly). The annual
#'   borrow rate is charged at `rate / ann_factor` per period, which equals
#'   the `rate / 12` monthly convention above when `ann_factor = 12`.
#' @param series_label Label used in error messages.
#' @param borrow_rates_annual Numeric vector of annual borrow rates to sweep.
#'   MUST include 0 (the baseline `sharpe_delta` is computed against).
#' @param short_notional_frac Numeric scalar in `[0, 1]`. Fraction of NAV
#'   held short each period. Default `1` (100%, per the verified convention
#'   above).
#' @return Tibble: borrow_rate_annual, cagr, vol, sharpe, sharpe_delta
#'   (sharpe at this rate minus sharpe at rate 0).
#' @noRd
compute_borrow_sensitivity <- function(ret_pre_borrow,
                                        ann_factor,
                                        borrow_rates_annual = c(0, 0.03, 0.10, 0.25),
                                        short_notional_frac = 1,
                                        series_label = "series") {
  if (missing(ann_factor) || !is.numeric(ann_factor) || length(ann_factor) != 1L ||
      !is.finite(ann_factor) || ann_factor <= 0) {
    cli::cli_abort(c(
      "x" = "compute_borrow_sensitivity(): {.arg ann_factor} for {.val {series_label}} must be a single positive finite number.",
      "i" = "Pass the series' own periods per year (12 monthly, 252 daily); it is never guessed from n (#936)."
    ))
  }
  if (!is.numeric(ret_pre_borrow) || length(ret_pre_borrow) < 12L) {
    cli::cli_abort(c(
      "x" = "compute_borrow_sensitivity() requires >= 12 returns.",
      "i" = "Got {length(ret_pre_borrow)}."
    ))
  }
  if (anyNA(ret_pre_borrow)) {
    cli::cli_abort(c(
      "x" = "compute_borrow_sensitivity(): ret_pre_borrow contains NA.",
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

  n <- length(ret_pre_borrow)

  rows <- purrr::map_dfr(borrow_rates_annual, function(rate) {
    period_charge <- short_notional_frac * rate / ann_factor
    r       <- ret_pre_borrow - period_charge
    ann_ret <- prod(1 + r)^(ann_factor / n) - 1
    ann_vol <- stats::sd(r) * sqrt(ann_factor)
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
#'   returns per strategy, one per period (may contain NA -- filtered
#'   per-strategy).
#' @param ann_factor_by_strategy Named numeric vector: periods per year for
#'   EACH strategy in `returns_by_strategy` (see [compute_borrow_sensitivity()]).
#'   Aborts naming any strategy without an entry (#936).
#' @param borrow_rates_annual Numeric vector to sweep.
#' @return Tibble: strategy, borrow_rate_annual, cagr, vol, sharpe, sharpe_delta.
#' @noRd
build_borrow_sensitivity_table <- function(returns_by_strategy,
                                            ann_factor_by_strategy,
                                            borrow_rates_annual = c(0, 0.03, 0.10, 0.25)) {
  if (!is.list(returns_by_strategy) || length(returns_by_strategy) == 0L ||
      is.null(names(returns_by_strategy)) || any(!nzchar(names(returns_by_strategy)))) {
    cli::cli_abort(c(
      "x" = "build_borrow_sensitivity_table(): returns_by_strategy must be a non-empty NAMED list."
    ))
  }
  if (missing(ann_factor_by_strategy) || !is.numeric(ann_factor_by_strategy) ||
      is.null(names(ann_factor_by_strategy))) {
    cli::cli_abort(c(
      "x" = "build_borrow_sensitivity_table(): ann_factor_by_strategy must be a NAMED numeric vector.",
      "i" = "One periods-per-year entry per strategy (#936)."
    ))
  }
  no_af <- setdiff(names(returns_by_strategy), names(ann_factor_by_strategy))
  if (length(no_af) > 0L) {
    cli::cli_abort(c(
      "x" = "build_borrow_sensitivity_table(): no ann_factor for {length(no_af)} strateg{?y/ies}: {.val {no_af}}.",
      "i" = "Never guessed from series length (#936)."
    ))
  }
  purrr::imap_dfr(returns_by_strategy, function(r, strategy) {
    r <- r[!is.na(r)]
    sweep <- compute_borrow_sensitivity(
      r, ann_factor = unname(ann_factor_by_strategy[[strategy]]),
      borrow_rates_annual = borrow_rates_annual, series_label = strategy
    )
    dplyr::mutate(sweep, strategy = strategy, .before = 1L)
  })
}

# ── Realised turnover per strategy (#663 Phase 1, #567 A1/A2) ────────────────
# MEASUREMENT ONLY. Nothing below feeds any return, cost, Sharpe or CAGR: the
# `strategy_realised_turnover` target sits NEXT TO the hand-typed
# `turnover_pct_per_period_avg` (R/plan_strategy_names.R) so the two can be
# compared; the cost model in R/plan_leaderboard.R is unchanged.
#
# One definition (packages/historicaldata/R/turnover.R, hd_turnover()):
# one-way turnover = sum(|w_new - w_prev|) / 2 on the SIGNED NAV weights, over
# the union of names (a missing name has weight 0, so an exit is a trade).
# Hence a dollar-neutral 100%/100% long-short book that fully replaces both
# legs has turnover 2.0, not 1.0; a long-only fully invested book that
# replaces everything has 1.0.
#
# Columns of the result (one row per strategy_names row):
#   avg_turnover_oneway     mean one-way turnover per rebalance period, on the
#                           definition above
#   periods_per_year        strategy_names$ann_factor (252 daily, 12 monthly)
#   annualised_turnover_oneway  avg_turnover_oneway * periods_per_year
#   legs                    2 for directionality == "long_short", else 1
#   turnover_realised       annualised_turnover_oneway / 12 / legs: the
#                           per-MONTH, per-LEG fraction. This is the SAME basis
#                           as turnover_pct_per_period_avg / 100, which
#                           .strategy_turnover_cost_basis() multiplies by
#                           cost_per_trade * leg_multiplier as a monthly figure.
#   turnover_hand_typed     turnover_pct_per_period_avg / 100
#   turnover_ratio          turnover_realised / turnover_hand_typed
#   na_reason               non-empty text exactly when no turnover could be
#                           measured (fail-loud-not-null.md): never a blank NA.
#
# Sources, and the convention each one's own code uses (not changed here):
#   weights   -> hd_turnover_series() on the strategy's own weight table
#   column    -> the strategy's existing `turnover` column, converted to the
#                definition above where its own convention differs (noted per
#                row in `convention_note`)

#' One measured-turnover entry for build_strategy_realised_turnover()
#'
#' @param turnover Numeric vector, one-way turnover per period ON THE
#'   PORTFOLIO DEFINITION (see header). `NA` is allowed only in the first
#'   position (a first period with no previous book).
#' @param source Character: where the series came from.
#' @param drift_adjusted Logical: was the previous book drifted by returns?
#' @param note Character: the convention note for this row.
#' @param drop_leading Integer: periods to drop from the front before
#'   averaging (warm-up, or an entry period that is not a rebalance).
#' @return A list entry.
#' @noRd
.rt_entry <- function(turnover, source, drift_adjusted, note, drop_leading = 0L) {
  list(turnover = turnover, source = source, drift_adjusted = drift_adjusted,
       note = note, drop_leading = as.integer(drop_leading), na_reason = NA_character_)
}

#' An entry for a strategy that exposes no weight vector
#' @param reason Non-empty character: why turnover cannot be measured.
#' @return A list entry.
#' @noRd
.rt_na_entry <- function(reason) {
  if (!is.character(reason) || length(reason) != 1L || is.na(reason) || !nzchar(reason)) {
    cli::cli_abort(c(
      "x" = ".rt_na_entry(): `reason` must be one non-empty string.",
      "i" = "A strategy with no measurable turnover must say why (fail-loud-not-null)."
    ))
  }
  list(turnover = NULL, source = NA_character_, drift_adjusted = NA,
       note = NA_character_, drop_leading = 0L, na_reason = reason)
}

#' Summarise one turnover series
#' @param entry An entry from .rt_entry().
#' @return List(avg, n).
#' @noRd
.rt_summarise <- function(entry, label) {
  x <- entry$turnover
  if (!is.numeric(x) || length(x) == 0L) {
    cli::cli_abort(c("x" = "{.val {label}}: turnover must be a non-empty numeric vector."))
  }
  if (entry$drop_leading > 0L) {
    if (entry$drop_leading >= length(x)) {
      cli::cli_abort(c(
        "x" = "{.val {label}}: drop_leading ({entry$drop_leading}) leaves no periods out of {length(x)}."
      ))
    }
    x <- x[-seq_len(entry$drop_leading)]
  }
  if (anyNA(x[-1L]) || !all(is.finite(x[!is.na(x)])) || any(x < 0, na.rm = TRUE)) {
    cli::cli_abort(c(
      "x" = "{.val {label}}: turnover must be finite and >= 0, with NA allowed only in the first period.",
      "i" = "Got {sum(is.na(x))} NA, {sum(!is.finite(x) & !is.na(x))} non-finite, {sum(x < 0, na.rm = TRUE)} negative."
    ))
  }
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    cli::cli_abort(c("x" = "{.val {label}}: no measured periods left after dropping the first."))
  }
  list(avg = mean(x), n = length(x))
}

#' Per-strategy realised turnover table (#663 Phase 1)
#'
#' @param entries Named list keyed by `strategy_names$code_name`; each element
#'   from `.rt_entry()` or `.rt_na_entry()`. Aborts naming any code_name
#'   missing from `entries` or not in `strategy_names_tbl`.
#' @param strategy_names_tbl `hd_strategy_names_tbl()` / the `strategy_names`
#'   target (code_name, short_name, frequency, ann_factor,
#'   turnover_pct_per_period_avg, directionality).
#' @return Tibble, one row per strategy_names row (see header for columns).
#' @noRd
build_strategy_realised_turnover <- function(entries, strategy_names_tbl) {
  need <- c("code_name", "short_name", "frequency", "ann_factor",
            "turnover_pct_per_period_avg", "directionality")
  miss_cols <- setdiff(need, names(strategy_names_tbl))
  if (length(miss_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "build_strategy_realised_turnover(): strategy_names_tbl lacks column(s) {.field {miss_cols}}."
    ))
  }
  if (!is.list(entries) || is.null(names(entries))) {
    cli::cli_abort(c("x" = "build_strategy_realised_turnover(): `entries` must be a named list."))
  }
  missing_e <- setdiff(strategy_names_tbl$code_name, names(entries))
  extra_e   <- setdiff(names(entries), strategy_names_tbl$code_name)
  if (length(missing_e) > 0L || length(extra_e) > 0L) {
    cli::cli_abort(c(
      "x" = "build_strategy_realised_turnover(): entries and strategy_names disagree.",
      "i" = "No entry for: {.val {missing_e}}.",
      "i" = "Entry for a strategy not in strategy_names: {.val {extra_e}}.",
      "i" = "Every strategy needs a measured series or an explicit na_reason."
    ))
  }

  rows <- lapply(seq_len(nrow(strategy_names_tbl)), function(i) {
    sn <- strategy_names_tbl[i, ]
    e  <- entries[[sn$code_name]]
    legs <- if (as.character(sn$directionality) == "long_short") 2 else 1
    base <- tibble::tibble(
      strategy              = sn$short_name,
      code_name             = sn$code_name,
      measurement_interval  = as.character(sn$frequency),
      periods_per_year      = as.numeric(sn$ann_factor),
      legs                  = legs,
      turnover_hand_typed   = sn$turnover_pct_per_period_avg / 100
    )
    if (!is.na(e$na_reason)) {
      return(dplyr::bind_cols(base, tibble::tibble(
        n_periods = 0L,
        avg_turnover_oneway = NA_real_, annualised_turnover_oneway = NA_real_,
        turnover_realised = NA_real_, turnover_ratio = NA_real_,
        turnover_source = NA_character_, drift_adjusted = NA,
        convention_note = NA_character_, na_reason = e$na_reason
      )))
    }
    s <- .rt_summarise(e, sn$short_name)
    ann <- s$avg * base$periods_per_year
    realised <- ann / 12 / legs
    dplyr::bind_cols(base, tibble::tibble(
      n_periods = as.integer(s$n),
      avg_turnover_oneway = s$avg, annualised_turnover_oneway = ann,
      turnover_realised = realised,
      turnover_ratio = realised / base$turnover_hand_typed,
      turnover_source = e$source, drift_adjusted = e$drift_adjusted,
      convention_note = e$note, na_reason = NA_character_
    ))
  })
  dplyr::bind_rows(rows)
}

#' Entry from a long weight table (Mom Pre-Peak / Post-Peak / 12-2)
#'
#' @param panel Data frame with `as_of_date`, `ticker`, `weight` (signed).
#' @return A .rt_entry(): not drifted (the table carries no per-name returns).
#' @noRd
.rt_entry_weight_panel <- function(panel, source) {
  ts <- hd_turnover_series(
    data.frame(date = panel$as_of_date, name = panel$ticker, weight = panel$weight),
    first = "na"
  )
  .rt_entry(
    ts$turnover, source = source, drift_adjusted = FALSE,
    note = paste0("hd_turnover_series() on the decile weight table; compared with the previous ",
                  "rebalance's weights as given (no per-name returns in the table to drift them); ",
                  "first rebalance excluded (initial funding)."),
    drop_leading = 1L
  )
}

#' Entry for managed futures: vol-targeted positions, drifted by asset returns
#'
#' ret_ls = RF + sum(pos_i * exc_i) / 4 = sum(w_i * r_i) + (1 - sum w) * RF with
#' w_i = pos_i / 4, so the book is w_i on each asset plus CASH = 1 - sum(w).
#'
#' @param mf The `mf_portfolios` target (date, SPY, TLT, GLD, DBC, RF, pos_*).
#' @return A .rt_entry().
#' @noRd
.rt_entry_managed_futures <- function(mf, source = "weights: mf_portfolios (pos_* / 4 + CASH)") {
  assets <- c("SPY", "TLT", "GLD", "DBC")
  mf <- mf[order(mf$date), ]
  pos <- as.matrix(mf[paste0("pos_", assets)])
  # Drop the warm-up months before the first signal: all-cash with no trade.
  first_live <- which(rowSums(abs(pos)) > 0)[1L]
  if (is.na(first_live)) {
    cli::cli_abort(c("x" = ".rt_entry_managed_futures(): no month has a non-zero position."))
  }
  keep <- seq(first_live, nrow(mf))
  mf <- mf[keep, ]
  w <- pos[keep, , drop = FALSE] / 4
  n <- nrow(mf)
  weights <- data.frame(
    date = rep(mf$date, each = 5L),
    name = rep(c(assets, "CASH"), times = n),
    weight = as.vector(t(cbind(w, 1 - rowSums(w))))
  )
  rets <- data.frame(
    date = rep(mf$date, each = 5L),
    name = rep(c(assets, "CASH"), times = n),
    ret = as.vector(t(cbind(as.matrix(mf[assets]), mf$RF)))
  )
  ts <- hd_turnover_series(weights, returns = rets, first = "na")
  .rt_entry(
    ts$turnover, source = source, drift_adjusted = TRUE,
    note = paste0("positions pos_*/4 plus CASH = 1 - sum(w), drifted by the month's asset returns and RF ",
                  "before comparison; warm-up months before the first signal and the first live month excluded."),
    drop_leading = 1L
  )
}

#' Entry for a SPY/cash exposure overlay (TOM, Risk State)
#'
#' @param df Data frame with the date column and exposure column named below.
#' @param exposure Name of the exposure column (fraction of NAV in SPY held on
#'   that day; the rest is cash).
#' @param spy_ret,cash_ret Names of the SPY and cash return columns, or `NULL`
#'   for no drift. Drift is exactly moot for a 0/1 exposure (the held asset is
#'   still 100% of the book), so TOM passes `NULL`.
#' @return A .rt_entry().
#' @noRd
.rt_entry_exposure <- function(df, exposure, spy_ret = NULL, cash_ret = NULL,
                               source, note, date = "date") {
  df <- df[order(df[[date]]), ]
  e <- df[[exposure]]
  if (anyNA(e)) {
    cli::cli_abort(c("x" = ".rt_entry_exposure(): {.field {exposure}} has NA; filter upstream."))
  }
  n <- nrow(df)
  weights <- data.frame(
    date = rep(df[[date]], each = 2L),
    name = rep(c("SPY", "CASH"), times = n),
    weight = as.vector(rbind(e, 1 - e))
  )
  rets <- NULL
  if (!is.null(spy_ret)) {
    rets <- data.frame(
      date = rep(df[[date]], each = 2L),
      name = rep(c("SPY", "CASH"), times = n),
      ret = as.vector(rbind(df[[spy_ret]], df[[cash_ret]]))
    )
  }
  ts <- hd_turnover_series(weights, returns = rets, first = "na")
  .rt_entry(ts$turnover, source = source, drift_adjusted = !is.null(rets),
            note = note, drop_leading = 1L)
}

#' Entry from a strategy's own existing `turnover` column
#'
#' @param x Numeric vector (its own convention).
#' @param drift_adjusted Logical: does the strategy's own code drift the previous book?
#' @param scale Multiplier onto the portfolio one-way definition.
#' @noRd
.rt_entry_column <- function(x, source, note, drift_adjusted, scale = 1,
                             drop_leading = 0L) {
  .rt_entry(x * scale, source = source, drift_adjusted = drift_adjusted,
            note = note, drop_leading = drop_leading)
}

plan_cost_convention <- function() {
  list(
    # ── #663 Phase 1 / #567 A1-A2: realised turnover, beside the hand-typed one ──
    # MEASUREMENT ONLY (see the block comment above build_strategy_realised_turnover()).
    # Every strategy_names row gets a measured series or an explicit na_reason.
    targets::tar_target(strategy_realised_turnover, {
      by_date <- function(df) df[order(df$date), ]

      cmr_best <- cmr_selection$chosen
      cmr_port <- switch(cmr_best,
        "1m" = cmr_portfolio_1m,
        "3m" = cmr_portfolio_3m,
        "6m" = cmr_portfolio_6m,
        cli::cli_abort(c(
          "x" = "strategy_realised_turnover: unrecognised CMR lookback {.val {cmr_best}} selected by cmr_selection.",
          "i" = "Allowed values: 1m, 3m, 6m (R/plan_commodities_mean_reversion.R)."
        ))
      )

      eq_long_only_note <- paste0(
        "own `turnover` column: fraction of the equal-weight long-only book that changed vs the previous ",
        "month (one-way; not drifted); first month (entry = 1.0) excluded."
      )
      stk_na_reason <- paste0(
        "The portfolio's `turnover` column is the constant est_turnover = 0.80 hard-coded in ",
        "portfolio_longshort() (R/plan_stock_backtest.R:150): an assumption, not a measurement, and no ",
        "per-name weights are retained to measure it. Only the separate HRP variants compute drifted ",
        "turnover, and they are not this leaderboard row."
      )
      entries <- list(
        avoid_worst = .rt_na_entry(paste0(
          "Hindsight return series (worst-N days excluded ex post, R/plan_avoid_worst.R: 'NOT a tradeable ",
          "strategy'): there is no weight vector to trade."
        )),
        drif = .rt_entry_column(by_date(drif_portfolio)$turnover, "column: drif_portfolio$turnover",
                                eq_long_only_note, drift_adjusted = FALSE, drop_leading = 1L),
        fac_max = .rt_entry_column(by_date(fm_portfolio)$turnover, "column: fm_portfolio$turnover",
                                   eq_long_only_note, drift_adjusted = FALSE, drop_leading = 1L),
        rsc = .rt_entry_exposure(
          dplyr::filter(rsc_portfolio, !is.na(spy_ret), !is.na(exposure)),
          exposure = "exposure", spy_ret = "spy_ret", cash_ret = "rf_daily",
          source = "weights: rsc_portfolio (exposure SPY + cash)",
          note = paste0("SPY weight = exposure, cash = 1 - exposure, drifted by the day's SPY and cash returns; ",
                        "counts the daily trade back to target exposure as well as regime switches ",
                        "(the cost model charges switch days only). First day excluded.")
        ),
        ltr = .rt_na_entry(paste0(
          "ltr_portfolio keeps only n_long / n_short counts, no per-name weights; its cost is a flat ",
          "2 x cost_per_trade every month (full turnover assumed), so no turnover is observable."
        )),
        tom = .rt_entry_exposure(
          dplyr::mutate(tom_portfolio, exposure = as.numeric(in_tom)),
          exposure = "exposure",
          source = "weights: tom_portfolio (in_tom SPY / cash)",
          note = paste0("SPY weight = in_tom (0 or 1), cash = 1 - in_tom; one-way turnover is 1 on each ",
                        "switch day. Drift is moot for a 0/1 book. First day excluded.")
        ),
        stk_max = .rt_na_entry(stk_na_reason),
        stk_drif = .rt_na_entry(stk_na_reason),
        xgb_drif = .rt_na_entry(stk_na_reason),
        pso_optimal = .rt_na_entry(paste0(
          "Meta-portfolio blend of already-net constituent returns (R/plan_portfolio_opt.R): there is no ",
          "position-level weight vector; the blend weights are constants."
        )),
        cmr = .rt_entry_column(by_date(cmr_port)$turnover,
                               paste0("column: cmr_portfolio_", cmr_best, "$turnover"),
                               paste0("own `turnover` column: sum|dw|/2 on +/-1/n leg weights, but computed on the ",
                                      "traded-only table (packages/historicaldata/R/commodities_mean_reversion.R:893-905) ",
                                      "so a series that EXITS is not counted as a sale at the exit date: this ",
                                      "understates turnover (#567 A2). Flat pre-breadth dates count as 0."),
                               drift_adjusted = FALSE),
        mom_prepeak = .rt_entry_weight_panel(mom_prepeak_portfolio, "weights: mom_prepeak_portfolio"),
        mom_postpeak = .rt_entry_weight_panel(mom_postpeak_portfolio, "weights: mom_postpeak_portfolio"),
        mom_combined = .rt_entry_weight_panel(mom_combined_portfolio, "weights: mom_combined_portfolio"),
        ev_ebit = .rt_na_entry(paste0(
          "Pre-computed Fama-French factor-return series (R/plan_ev_ebit.R: ret_value_hml = RF + HML - cost); ",
          "no weight vector exists."
        )),
        mf_tsm = .rt_entry_managed_futures(mf_portfolios),
        olmar = .rt_entry_column(by_date(olmar_portfolio)$turnover, "column: olmar_portfolio$turnover",
                                 paste0("own `turnover` column: sum|b_new - b_prev|/2 on the full weight ",
                                        "vector (packages/historicaldata/R/olmar.R, via hd_turnover(); previous ",
                                        "weights NOT drifted); first window-1 warm-up days excluded."),
                                 drift_adjusted = FALSE, drop_leading = olmar_params$window - 1L),
        cmr_conditioned = .rt_na_entry(paste0(
          "Exposure-scaling overlay on the cmr tercile book (R/plan_commodities_mean_reversion.R): its ",
          "traded weights are m_t x the cmr weights and are not retained, so the overlay's own turnover ",
          "is not observable from cmr_portfolio_*_conditioned (only exposure_mult and switch_cost)."
        ))
      )

      out <- build_strategy_realised_turnover(entries, strategy_names)
      cli::cli_inform(c("v" = paste0(
        "strategy_realised_turnover: ", sum(is.na(out$na_reason)), " measured, ",
        sum(!is.na(out$na_reason)), " with na_reason (measurement only, #663 Phase 1)"
      )))
      out
    }),

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
          0.005, 0.005, 0.005,
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
          "R/plan_commodities_mean_reversion.R:51,61,71 (cost_bps = 20 for all 3 lookback variants); 10-long/10-short construction on commodity futures/ETFs/price indices (data/raw/commodities.parquet) -- no equity-style borrow leg applies (#665: reclassified not_applicable, see BORROW_STATUS_OVERRIDES; supersedes the prior 'verified absent, not a long-only NA' framing)",
          "R/plan_risk_state.R:38 (cost_per_trade = 0.0005, comment: '5 bps one-way ... applied only on regime-switch days'), R/plan_risk_state.R:194 (trade_cost = rsc_params$cost_per_trade * exposure_change * 2.0); exposure in [0.10, 1.00], never short -- borrow NA",
          "R/plan_avoid_worst.R:5 (comment: 'NOT a tradeable strategy'); no cost_per_trade/cost_bps field exists anywhere in this file -- zero is a verified absence, not a default",
          "R/plan_mom_prepeak.R:31 (cost_per_trade = 0.0010, comment: 'matches ltr_params'), R/plan_mom_prepeak.R (borrow_rate_annual = 0.005, `# MANUAL: no source`, GC-rate reasoning), R/plan_mom_prepeak.R:.mom_prepeak_compute_returns() (ret_ls = ret_long - ret_short - 2*cost_per_trade - borrow_rate_annual/12); #665 -- 100% short leg on the loser decile of ltr_universe (~53 of 529 tickers) charged at 0.5%/yr general-collateral rate; supersedes the prior 'verified absent' framing",
          "R/plan_mom_prepeak.R (same shared helper + params as Mom Pre-Peak; borrow_rate_annual = 0.005); #665 -- same GC-rate borrow charge on its 100% short leg",
          "R/plan_mom_prepeak.R (same shared helper + params as Mom Pre-Peak; borrow_rate_annual = 0.005); #665 -- same GC-rate borrow charge on its 100% short leg",
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
      # OLMAR-1 previously had no row in strategy_names (#626/#629 known
      # join gap) and required an explicit post-join fill here. #747 added
      # the missing `olmar` row (directionality = "long_only", matching
      # what this file used to fill in by hand -- verified against
      # R/plan_olmar.R:30's long-only simplex projection), so the join
      # alone now resolves OLMAR-1 correctly and the fill was removed. A
      # genuinely undeclared strategy still fails loud below, via
      # derive_borrow_status()'s NA-directionality abort (fail-loud-not-
      # null.md) -- and via QA gate S7's reverse leaderboard/strategy_names
      # set-equality check (R/plan_qa_gates.R, check_leaderboard_coverage()).
      sn_lookup <- dplyr::transmute(
        strategy_names,
        strategy = short_name,
        directionality = as.character(directionality)
      )

      with_direction <- base |>
        dplyr::left_join(sn_lookup, by = "strategy") |>
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

      # ── #665 Part 1: attach the securities-lending decision ────────────
      # See the LENDING_STATUS_ALLOWED comment block above for the decision
      # itself. lending_source_ref follows the SAME "file:line, verified at
      # authoring commit" convention as cost_source_ref, except the claim
      # being verified is a materiality JUDGEMENT, not a code fact -- hence
      # the `# MANUAL: no source` marker on every row (reproducible-ingestion
      # discipline, CLAUDE.md: a hand-entered figure/decision with no parser
      # is technical debt, flagged on sight, not silently treated as settled).
      with_lending <- with_status |>
        dplyr::left_join(LENDING_STATUS_OVERRIDES, by = "strategy") |>
        dplyr::mutate(
          lending_status = derive_lending_status(
            strategy = strategy,
            override = lending_status_override
          ),
          lending_source_ref = dplyr::case_when(
            strategy == "Value (HML)" ~ paste0(
              "# MANUAL: no source -- #665 zero-lending decision; ",
              "embedded_in_source for the same reason as its borrow_status ",
              "override (R/plan_ev_ebit.R:33,79): the pre-computed FF ",
              "factor series holds no separately-tradeable long position ",
              "to lend."
            ),
            strategy == "PSO Optimal" ~ paste0(
              "# MANUAL: no source -- #665 zero-lending decision; ",
              "inherited for the same reason as its borrow_status override ",
              "(R/plan_portfolio_opt.R): a meta-portfolio blending ",
              "already-net constituent returns, so lending income (if any) ",
              "is a property of the constituents, not this row."
            ),
            strategy == "Avoid Worst" ~ paste0(
              "# MANUAL: no source -- #665 zero-lending decision; ",
              "not_tradeable for the same reason as its borrow_status ",
              "override (R/plan_avoid_worst.R:5): no cost model of any ",
              "kind exists in code, so there is no modelled position to ",
              "lend."
            ),
            TRUE ~ paste0(
              "# MANUAL: no source -- #665 zero-lending decision; deliberate ",
              "zero, judged immaterial for this book's composition, not a ",
              "measurement. Long book here is general collateral ",
              "(ltr_universe: 529 S&P-500-constituent/liquid-ETF tickers, ",
              "R/plan_mom_prepeak.R), lending revenue on GC is single-digit ",
              "bps against a 50bp borrow assumption whose own uncertainty ",
              "is ~25bp -- below the resolution of everything around it. ",
              "Reassess if the book ever holds hard-to-borrow names."
            )
          )
        ) |>
        dplyr::select(-lending_status_override)

      # Visible at every tar_make() (fail-loud-not-null.md: an unrecognised /
      # unmodelled state must be visible, never silently absorbed).
      unmodelled <- with_lending$strategy[with_lending$borrow_status == "unmodelled"]
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

      with_lending
    }),

    # ── #665 (quantification only): borrow-rate sensitivity sweep ───────
    #
    # REPORTING ONLY -- see build_borrow_sensitivity_table() /
    # compute_borrow_sensitivity() roxygen above. Does NOT feed leaderboard,
    # all_metrics, or any published return.
    #
    # Post-#665 status of the 8 rows below: Mom Pre-Peak / Mom Post-Peak /
    # Mom 12-2 moved from "unmodelled" to "modelled" (0.005 GC rate, see
    # mom_prepeak_params); CMR moved from "unmodelled" to "not_applicable"
    # (commodity futures/ETF short leg, no equity-style borrow -- see
    # BORROW_STATUS_OVERRIDES above). CMR is kept in this sweep for
    # illustrative "what if we were wrong about the reclassification"
    # comparison only -- it is NOT evidence that CMR should be charged an
    # equity borrow rate (Part 2 of #665's PR argues the opposite: wrong in
    # KIND, not just magnitude). Stock MAX / Stock DRIF / XGB DRIF / LTR
    # remain "modelled" at the flat 0.03 rate (so a reader can see how
    # sensitive those already-costed strategies are to that rate being
    # wrong -- see the `# MANUAL: no source` markers in
    # R/plan_stock_backtest.R and R/plan_ltr_momentum.R).
    #
    # Each series is reconstructed as the PRE-BORROW per-period return (CMR is
    # DAILY, the other seven monthly -- each annualised on its own
    # strategy_names$ann_factor, #936):
    #   - CMR: its return series has zero borrow charge (not_applicable, no
    #     rate was ever subtracted), so it is used as-is.
    #   - Mom Pre-Peak / Mom Post-Peak / Mom 12-2: the now-applied
    #     mom_prepeak_params$borrow_rate_annual/12 monthly charge is added
    #     back so the sweep starts from the same zero-borrow baseline as
    #     CMR (#665 -- without this, the 0-rate row here would silently
    #     double-subtract the borrow already baked into ret_ls).
    #   - Stock MAX / Stock DRIF / XGB DRIF / LTR: the currently-applied
    #     0.03/12 monthly charge is added back (port_ret + borrow_cost, or
    #     ls_ret_net + borrow for LTR's pre-computed parquet columns).
    #
    # CMR reports 3 lookback variants (1m/3m/6m); the leaderboard displays
    # whichever the pipeline chose PRE-OOS (.norm_cmr(), R/plan_leaderboard.R
    # -- reading cmr_selection$chosen, S41/#910 item 1, #917) -- the SAME
    # selection is read here (not re-derived from cmr_summary's full-sample
    # sharpe, which is exactly the trap #917 found) so the swept strategy
    # matches what is actually published.
    targets::tar_target(borrow_sensitivity_sweep, {
      cmr_best <- cmr_selection$chosen
      cmr_port <- switch(cmr_best,
        "1m" = cmr_portfolio_1m,
        "3m" = cmr_portfolio_3m,
        "6m" = cmr_portfolio_6m,
        cli::cli_abort(c(
          "x" = "borrow_sensitivity_sweep: unrecognised CMR lookback {.val {cmr_best}} selected by cmr_selection.",
          "i" = "Allowed values: 1m, 3m, 6m (R/plan_commodities_mean_reversion.R)."
        ))
      )

      # Add back the now-embedded 0.005/12 monthly borrow charge (#665) so
      # these three start from the same zero-borrow baseline as CMR below --
      # see the target-level comment above for why this is required.
      mom_borrow_monthly <- mom_prepeak_params$borrow_rate_annual / 12

      returns_by_strategy <- list(
        "Mom Pre-Peak"  = mom_prepeak_returns$ret_ls + mom_borrow_monthly,
        "Mom Post-Peak" = mom_postpeak_returns$ret_ls + mom_borrow_monthly,
        "Mom 12-2"      = mom_combined_returns$ret_ls + mom_borrow_monthly,
        "CMR"           = cmr_port$net_ret,
        "Stock MAX"     = stk_max_portfolio$port_ret + stk_max_portfolio$borrow_cost,
        "Stock DRIF"    = stk_drif_portfolio$port_ret + stk_drif_portfolio$borrow_cost,
        "XGB DRIF"      = xgb_drif_portfolio$port_ret + xgb_drif_portfolio$borrow_cost,
        "LTR"           = ltr_portfolio$ls_ret_net + ltr_portfolio$borrow
      )

      # Periods per year come from strategy_names$ann_factor (the single
      # home, R/plan_strategy_names.R), joined on short_name -- never guessed
      # from n (#936: CMR is daily, 252; the other seven are monthly, 12).
      ann_factor_by_strategy <- stats::setNames(
        strategy_names$ann_factor[match(names(returns_by_strategy), strategy_names$short_name)],
        names(returns_by_strategy)
      )
      ann_factor_by_strategy <- ann_factor_by_strategy[!is.na(ann_factor_by_strategy)]

      out <- build_borrow_sensitivity_table(returns_by_strategy, ann_factor_by_strategy)

      cli::cli_inform(c("v" = paste0(
        "borrow_sensitivity_sweep: ", dplyr::n_distinct(out$strategy),
        " strategies x ", length(unique(out$borrow_rate_annual)),
        " borrow rates (reporting only, #665; CMR variant = ", cmr_best, ")"
      )))
      out
    })
  )
}
