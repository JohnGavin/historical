# Plan: survivorship bias and failure sensitivity of the stock MAX strategy (#1041)
#
# Issue refs: #1041 (this), #150 (survivorship bias), #816 (PIT universe),
# #972 (K trial count -- why nothing here is registered).
#
# QUESTION. stk_max_portfolio runs on today's top-100 stocks by market cap, a
# survivorship-biased universe (#150). How much does the MAX long-short change
# on the stocks that were ACTUALLY in the S&P 500 at the time, including those
# that were later taken over or failed?
#
# THREE VARIANTS, same months (the common non-NA-rf months of all three), same MAX signal, same
# deciles, same costs, same rf:
#   biased     today's top-100-by-market-cap universe (stk_max_portfolio),
#              restricted to the months the PIT variants cover.
#   pit_upper  point-in-time S&P 500 members; the final month of a stock that
#              stopped trading ends at exit_price_upper.
#   pit_lower  the same, ending at exit_price_lower (0 for a failure candidate,
#              so that month's return is -100%).
# The two PIT variants differ ONLY in exit months. They are BOUNDS, not a
# delisting return (Alpaca has none).
#
# REPORT ONLY. Nothing here is registered in the leaderboard or the research
# registry (register_runs): that would change published numbers and the trial
# count K (#972). The result is the one table stk_pit_max_comparison.
#
# WINSORISATION DECISION. portfolio_longshort() clips every monthly return at
# +-max_monthly_ret (20%). A -100% failure month would be clipped to -20%, and
# the lower bound would then be meaningless. So the PIT portfolios do NOT clip
# EXIT months (a stock's final month when it was taken over or failed, flagged
# `is_exit`); every other month is clipped exactly as in stk_max_portfolio. The
# same rule applies to both bounds, so upper and lower still differ only in
# exit months. tests/testthat/test-pit-max.R proves a -1 survives.
#
# Targets:
#   stk_member_bars_adj_file / stk_member_bars_adj  adjusted Alpaca bars of every
#                                member since 2016 (scripts/fetch_alpaca_member_bars.R)
#   stk_pit_series          one adjusted-price series per security
#   stk_pit_monthly         hd_pit_monthly_returns(): the PIT monthly returns
#   stk_pit_excluded        securities excluded, with the reason, counted (members
#                           within the backtest window; n_all = all leavers)
#   stk_pit_max_signal      MAX signal on the PIT series
#   stk_pit_max_panel       signal x held-month returns, valid months only
#   stk_pit_max_portfolio_upper / _lower
#   stk_max_portfolio_biased_2016
#   stk_pit_max_comparison  the comparison table

# ── Helpers (not targets) ─────────────────────────────────────────

#' MAX signal on point-in-time price series
#'
#' Same rule as stk_max_signal: the maximum daily adjusted return of the month,
#' kept when the month has at least `min_days` daily returns.
#' @param series Output of hd_pit_price_series(): `ticker`, `date`, `adj_close`.
#' @param min_days Minimum daily returns in the month.
#' @return Tibble: `ticker`, `ym` (the SIGNAL month), `max_ret`, `n_days`.
#' @noRd
pit_max_signal <- function(series, min_days = 10L) {
  series |>
    dplyr::arrange(ticker, date) |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(daily_ret = adj_close / dplyr::lag(adj_close) - 1) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(daily_ret)) |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::group_by(ticker, ym) |>
    dplyr::summarise(max_ret = max(daily_ret), n_days = dplyr::n(), .groups = "drop") |>
    dplyr::filter(n_days >= min_days)
}

#' Signal joined to the held-month returns, valid months only
#'
#' `pit_monthly` already carries the universe at the signal month-end and the
#' signal-to-held-month lag (`signal_ym` to `ym`), so the signal joins on
#' `(ticker, signal_ym)`.
#' @param pit_monthly Output of hd_pit_monthly_returns().
#' @param signal Output of pit_max_signal().
#' @param n_deciles Number of deciles; a month needs at least `n_deciles * 5`
#'   stocks (the stk_max_portfolio rule, #43).
#' @return Tibble: ticker, signal_ym, ym, max_ret, ret_upper, ret_lower,
#'   exit_type, is_exit.
#' @noRd
pit_max_panel <- function(pit_monthly, signal, n_deciles) {
  merged <- pit_monthly |>
    dplyr::inner_join(
      signal |> dplyr::select(ticker, signal_ym = ym, max_ret),
      by = c("ticker", "signal_ym")
    ) |>
    dplyr::mutate(is_exit = exit_type %in% c("takeover", "failure_candidate")) |>
    dplyr::select(ticker, signal_ym, ym, max_ret, ret_upper, ret_lower, exit_type, is_exit)
  n_by_month <- merged |> dplyr::count(ym, name = "n_stocks")
  valid <- n_by_month |> dplyr::filter(n_stocks >= n_deciles * 5) |> dplyr::pull(ym)
  merged |> dplyr::filter(ym %in% valid)
}

#' MAX decile long-short portfolio on one bound of the PIT returns
#'
#' Mirrors stk_max_portfolio: same deciles, costs, borrow and rf join. Exit
#' months are not winsorised (see the file header).
#' @param panel Output of pit_max_panel().
#' @param variant "upper" or "lower".
#' @param params stk_params (n_deciles, cost_per_trade, borrow_rate_annual,
#'   max_monthly_ret).
#' @param rf stk_rf: `ym`, `rf_ret`.
#' @return Tibble as stk_max_portfolio.
#' @noRd
pit_max_portfolio <- function(panel, variant = c("upper", "lower"), params, rf) {
  variant <- match.arg(variant)
  panel$monthly_ret <- if (variant == "upper") panel$ret_upper else panel$ret_lower
  deciled <- assign_decile(panel, max_ret, params$n_deciles)
  port <- portfolio_longshort(
    deciled, long_decile = 1L, short_decile = 10L,
    cost_per_trade = params$cost_per_trade,
    borrow_rate_annual = params$borrow_rate_annual,
    max_monthly_ret = params$max_monthly_ret,
    winsorise_exits = FALSE
  )
  port |>
    dplyr::left_join(rf, by = "ym") |>
    dplyr::mutate(
      date = as.Date(paste0(ym, "-15")),
      port_cum = cumprod(1 + port_ret),
      long_cum = cumprod(1 + long_ret)
    )
}

#' stk_max_portfolio restricted to the months of a PIT portfolio
#' @param biased stk_max_portfolio.
#' @param pit A PIT portfolio (its `ym` define the months).
#' @return Tibble as `biased`, with port_cum / long_cum recomputed.
#' @noRd
pit_restrict_biased <- function(biased, pit) {
  biased |>
    dplyr::filter(ym %in% pit$ym) |>
    dplyr::mutate(port_cum = cumprod(1 + port_ret), long_cum = cumprod(1 + long_ret))
}

#' Stocks per valid month in the biased universe (the stk_max_portfolio merge)
#' @param max_signal stk_max_signal.
#' @param monthly stk_monthly.
#' @param yms Months to keep.
#' @param n_deciles Number of deciles.
#' @return Tibble: `ym`, `n_stocks`.
#' @noRd
pit_biased_n_stocks <- function(max_signal, monthly, yms, n_deciles) {
  signal <- max_signal |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(ym) |>
    dplyr::mutate(ym = next_ym(ym)) |>
    dplyr::filter(!is.na(ym)) |>
    dplyr::ungroup()
  signal |>
    dplyr::select(ticker, ym, max_ret) |>
    dplyr::inner_join(monthly, by = c("ticker", "ym")) |>
    dplyr::count(ym, name = "n_stocks") |>
    dplyr::filter(n_stocks >= n_deciles * 5, ym %in% yms)
}

#' The comparison table: biased vs PIT upper vs PIT lower
#'
#' Metrics come from calc_backtest_metrics() with strategy "Stock MAX", exactly
#' as stk_max_metrics (long-short, EXCESS basis: no rf deducted, so
#' sharpe = cagr / vol). EVERY variant is measured over the COMMON set of months:
#' months present in all three portfolios AND with a non-NA `rf_ret` (the biased
#' universe and the rf series end earlier than the PIT bars). The window is shown
#' in `first_ym`, `last_ym` and `n_months`.
#' @param biased,upper,lower The three portfolios (`ym`, `port_ret`, `long_ret`,
#'   `short_ret`, `rf_ret`).
#' @param panel pit_max_panel() (for stocks per month and leaver-months).
#' @param biased_n pit_biased_n_stocks().
#' @param min_months Abort when fewer common months remain (default 24).
#' @return Tibble, one row per variant: variant, first_ym, last_ym, n_months,
#'   ann_return, ann_vol, sharpe, max_dd, long_ann, short_ann (mean leg return
#'   times 12), mean_n_stocks, n_takeover, n_failure_candidate, n_demotion
#'   (leaver-months in the common window; NA for biased, which has none).
#' @noRd
pit_max_comparison <- function(biased, upper, lower, panel, biased_n,
                               min_months = 24L) {
  ok_rf <- function(p) p$ym[!is.na(p$rf_ret)]
  common <- Reduce(intersect, list(
    intersect(biased$ym, ok_rf(biased)),
    intersect(upper$ym, ok_rf(upper)),
    intersect(lower$ym, ok_rf(lower))
  ))
  common <- sort(common)
  if (length(common) < min_months) {
    cli::cli_abort(c(
      "x" = "Only {length(common)} month{?s} are common to all three variants with a non-NA rf_ret; at least {min_months} are needed.",
      "i" = "Check that the member bars, equity_daily and stk_rf overlap."
    ))
  }
  panel <- panel[panel$ym %in% common, , drop = FALSE]
  one <- function(p, variant, mean_n, leavers) {
    p <- p[p$ym %in% common, , drop = FALSE]
    m <- calc_backtest_metrics(p, "Full Period", strategy = "Stock MAX")
    tibble::tibble(
      variant = variant, first_ym = min(p$ym), last_ym = max(p$ym),
      n_months = m$months, ann_return = m$cagr,
      ann_vol = m$vol, sharpe = m$sharpe, max_dd = m$max_dd,
      long_ann = mean(p$long_ret) * 12, short_ann = mean(p$short_ret) * 12,
      mean_n_stocks = mean_n,
      n_takeover = leavers[["takeover"]],
      n_failure_candidate = leavers[["failure_candidate"]],
      n_demotion = leavers[["demotion"]]
    )
  }
  pit_n <- panel |> dplyr::count(ym) |> dplyr::pull(n) |> mean()
  cnt <- function(type) sum(panel$exit_type %in% type)
  pit_leavers <- c(takeover = cnt("takeover"), failure_candidate = cnt("failure_candidate"),
                   demotion = cnt("demotion"))
  na_leavers <- c(takeover = NA_integer_, failure_candidate = NA_integer_,
                  demotion = NA_integer_)
  biased_n <- biased_n[biased_n$ym %in% common, , drop = FALSE]
  dplyr::bind_rows(
    one(biased, "biased", mean(biased_n$n_stocks), na_leavers),
    one(upper, "pit_upper", pit_n, pit_leavers),
    one(lower, "pit_lower", pit_n, pit_leavers)
  )
}

#' Securities excluded from the PIT backtest, in-window and overall
#'
#' Leavers that left the index before the backtest window (`panel_start`) were
#' never candidates for a held month, so the headline count is restricted to
#' securities that were members at some snapshot on or after `panel_start`. The
#' count over all securities stays in `n_all`, so nothing is hidden.
#' @param excluded `attr(stk_pit_monthly, "excluded")`: `ticker` (permanent id),
#'   `reason`.
#' @param member_ids Permanent ids of securities that were members at a snapshot
#'   on or after `panel_start`.
#' @return Tibble: `reason`, `n_securities` (in-window), `n_all` (all).
#' @noRd
pit_excluded_summary <- function(excluded, member_ids) {
  excluded |>
    dplyr::group_by(reason) |>
    dplyr::summarise(
      n_securities = sum(ticker %in% member_ids),
      n_all = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(n_securities), dplyr::desc(n_all))
}

plan_pit_max <- function() {
  list(

    # A machine without the cache fails loudly, naming the fetch script
    # (hd_alpaca_member_bars_adj_path() aborts; never an empty result).
    targets::tar_target(
      stk_member_bars_adj_file,
      hd_alpaca_member_bars_adj_path(),
      format = "file"
    ),

    targets::tar_target(stk_member_bars_adj, {
      tibble::as_tibble(arrow::read_parquet(stk_member_bars_adj_file))
    }),

    targets::tar_target(stk_pit_series, {
      hd_pit_price_series(stk_member_bars_adj, stk_exit_prices)
    }),

    targets::tar_target(stk_pit_monthly, {
      hd_pit_monthly_returns(stk_member_bars_adj, stk_universe_pit, stk_exit_prices)
    }),

    # Coverage loss made visible: one row per exclusion reason, for securities
    # that were members within the backtest window; `n_all` keeps the full count.
    targets::tar_target(stk_pit_excluded, {
      win <- stk_universe_pit[stk_universe_pit$date >= historicaldata::hd_alpaca_exit_rule()$panel_start, ]
      ids <- historicaldata:::.hd_pit_permanent_id(unique(win$ticker), stk_exit_prices)
      pit_excluded_summary(attr(stk_pit_monthly, "excluded"), ids)
    }),

    targets::tar_target(stk_pit_max_signal, {
      pit_max_signal(stk_pit_series)
    }),

    targets::tar_target(stk_pit_max_panel, {
      pit_max_panel(stk_pit_monthly, stk_pit_max_signal, stk_params$n_deciles)
    }),

    targets::tar_target(stk_pit_max_portfolio_upper, {
      pit_max_portfolio(stk_pit_max_panel, "upper", stk_params, stk_rf)
    }),

    targets::tar_target(stk_pit_max_portfolio_lower, {
      pit_max_portfolio(stk_pit_max_panel, "lower", stk_params, stk_rf)
    }),

    targets::tar_target(stk_max_portfolio_biased_2016, {
      pit_restrict_biased(stk_max_portfolio, stk_pit_max_portfolio_upper)
    }),

    targets::tar_target(stk_pit_max_comparison, {
      pit_max_comparison(
        stk_max_portfolio_biased_2016,
        stk_pit_max_portfolio_upper,
        stk_pit_max_portfolio_lower,
        stk_pit_max_panel,
        pit_biased_n_stocks(stk_max_signal, stk_monthly,
                            stk_pit_max_portfolio_upper$ym, stk_params$n_deciles)
      )
    })

  )
}
