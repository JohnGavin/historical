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
# FOUR VARIANTS, same months (the common non-NA-rf months of all four), same MAX signal, same
# deciles, same costs, same rf:
#   biased     today's top-100-by-market-cap universe (stk_max_portfolio),
#              restricted to the months the PIT variants cover.
#   current_members  TODAY's S&P 500 members (the latest membership snapshot),
#              carried back to 2016: the PIT size range (about 500 stocks) with
#              the survivors' hindsight, no exits by construction. Only bars of
#              today's symbols are used and renames are NOT spliced (Alpaca gives
#              the full history under the current symbol); a symbol reused by an
#              earlier, different company is trimmed (hd_trim_symbol_reuse()).
#   pit_upper  point-in-time S&P 500 members; the final month of a stock that
#              stopped trading ends at exit_price_upper.
#   pit_lower  the same, ending at exit_price_lower (0 for a failure candidate,
#              so that month's return is -100%).
# The two PIT variants differ ONLY in exit months. They are BOUNDS, not a
# delisting return (Alpaca has none).
#
# WHY THE FOURTH VARIANT. biased vs pit_upper mixes two effects: survivorship
# AND size (100 mega-caps vs about 500 stocks). current_members has the size
# range of the PIT variants but survivors only, so
#   biased - current_members     = size / concentration,
#   current_members - pit_upper  = survivorship,
#   pit_upper - pit_lower        = failure bound.
# stk_pit_max_decomposition reports each as a monthly-difference statistic.
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
#   stk_current_member_bars_adj_file / stk_current_member_bars_adj  adjusted bars of
#                           today's members (scripts/fetch_alpaca_current_member_bars.R),
#                           today's symbols only, symbol reuse trimmed; stk_current_member_trimmed lists the trims
#   stk_current_members_series / _monthly / _max_signal / _max_panel / _max_portfolio
#                           the current_members variant, as the PIT chain
#   stk_pit_max_comparison  the comparison table (four variants)
#   stk_pit_max_decomposition  monthly-difference statistics of the three effects

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

#' Months common to all portfolios, with a non-NA rf
#'
#' @param ports List of portfolios (`ym`, `rf_ret`).
#' @param min_months Abort when fewer common months remain.
#' @return Sorted character vector of "YYYY-MM".
#' @noRd
pit_common_months <- function(ports, min_months = 24L) {
  ok_rf <- function(p) intersect(p$ym, p$ym[!is.na(p$rf_ret)])
  common <- sort(Reduce(intersect, lapply(ports, ok_rf)))
  if (length(common) < min_months) {
    n_common <- length(common)
    n_variants <- length(ports)
    cli::cli_abort(c(
      "x" = "Only {n_common} month{?s} are common to all {n_variants} variants with a non-NA rf_ret; at least {min_months} are needed.",
      "i" = "Check that the member bars, equity_daily and stk_rf overlap."
    ))
  }
  common
}

#' The comparison table: biased, current members, PIT upper, PIT lower
#'
#' Metrics come from calc_backtest_metrics() with strategy "Stock MAX", exactly
#' as stk_max_metrics (long-short, EXCESS basis: no rf deducted, so
#' sharpe = cagr / vol). EVERY variant is measured over the COMMON set of months:
#' months present in all four portfolios AND with a non-NA `rf_ret` (the biased
#' universe and the rf series end earlier than the PIT bars). The window is shown
#' in `first_ym`, `last_ym` and `n_months`.
#' @param biased,current,upper,lower The four portfolios (`ym`, `port_ret`,
#'   `long_ret`, `short_ret`, `rf_ret`).
#' @param panel pit_max_panel() (for stocks per month and leaver-months).
#' @param current_panel The panel of the current-members variant (stocks per month).
#' @param biased_n pit_biased_n_stocks().
#' @param min_months Abort when fewer common months remain (default 24).
#' @return Tibble, one row per variant (biased, current_members, pit_upper,
#'   pit_lower): variant, first_ym, last_ym, n_months,
#'   ann_return, ann_vol, sharpe, max_dd, long_ann, short_ann (mean leg return
#'   times 12), mean_n_stocks, n_takeover, n_failure_candidate, n_demotion
#'   (leaver-months in the common window; NA for biased and current_members,
#'   which have none by construction).
#' @noRd
pit_max_comparison <- function(biased, current, upper, lower, panel,
                               current_panel, biased_n, min_months = 24L) {
  common <- pit_common_months(list(biased, current, upper, lower), min_months)
  panel <- panel[panel$ym %in% common, , drop = FALSE]
  current_panel <- current_panel[current_panel$ym %in% common, , drop = FALSE]
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
  mean_per_month <- function(pn) pn |> dplyr::count(ym) |> dplyr::pull(n) |> mean()
  cnt <- function(type) sum(panel$exit_type %in% type)
  pit_leavers <- c(takeover = cnt("takeover"), failure_candidate = cnt("failure_candidate"),
                   demotion = cnt("demotion"))
  na_leavers <- c(takeover = NA_integer_, failure_candidate = NA_integer_,
                  demotion = NA_integer_)
  biased_n <- biased_n[biased_n$ym %in% common, , drop = FALSE]
  dplyr::bind_rows(
    one(biased, "biased", mean(biased_n$n_stocks), na_leavers),
    one(current, "current_members", mean_per_month(current_panel), na_leavers),
    one(upper, "pit_upper", mean_per_month(panel), pit_leavers),
    one(lower, "pit_lower", mean_per_month(panel), pit_leavers)
  )
}

#' Monthly-difference statistics of one return series
#'
#' For a vector `d` of monthly differences: the annualised mean (times 12), the
#' plain t-statistic of the mean, a Newey-West t-statistic (Bartlett weights,
#' `lags` lags, long-run variance times n / (n - 1) so that `lags = 0` equals
#' the plain t exactly), and a moving-block bootstrap confidence interval of the
#' annualised mean (overlapping blocks of `block` months, `B` resamples of
#' length n). The bootstrap draws from the session RNG: call set.seed() first.
#' @param d Numeric vector of monthly differences, no NA, at least 3 values.
#' @param lags Newey-West lags (default 6).
#' @param block Bootstrap block length in months (default 6; capped at n).
#' @param B Bootstrap resamples (default 10000).
#' @param level Confidence level of the interval (default 0.95).
#' @return One-row tibble: n_months, mean_ann, t_plain, t_nw, ci_lo, ci_hi.
#' @noRd
pit_diff_stats <- function(d, lags = 6L, block = 6L, B = 10000L, level = 0.95) {
  if (!is.numeric(d) || anyNA(d) || length(d) < 3L) {
    cli::cli_abort(c(
      "x" = "{.arg d} must be numeric, without NA, with at least 3 values.",
      "i" = "Got {length(d)} value{?s}."
    ))
  }
  n <- length(d)
  lags <- min(as.integer(lags), n - 1L)
  block <- min(as.integer(block), n)
  m <- mean(d)
  e <- d - m
  gamma <- function(l) sum(e[(l + 1L):n] * e[seq_len(n - l)]) / n
  lrv <- gamma(0L)
  for (l in seq_len(lags)) lrv <- lrv + 2 * (1 - l / (lags + 1)) * gamma(l)
  lrv <- lrv * n / (n - 1L)
  s <- stats::sd(d)
  t_plain <- if (s > 1e-12) m / (s / sqrt(n)) else NA_real_
  t_nw <- if (lrv > 1e-24) m / sqrt(lrv / n) else NA_real_
  k <- ceiling(n / block)
  starts <- matrix(sample.int(n - block + 1L, B * k, replace = TRUE), nrow = B, ncol = k)
  idx <- matrix(0L, nrow = B, ncol = k * block)
  for (j in seq_len(k)) {
    idx[, (j - 1L) * block + seq_len(block)] <- starts[, j] + rep(0:(block - 1L), each = B)
  }
  boot_mean <- rowMeans(matrix(d[idx[, seq_len(n)]], nrow = B)) * 12
  ci <- stats::quantile(boot_mean, c((1 - level) / 2, 1 - (1 - level) / 2), names = FALSE)
  tibble::tibble(n_months = n, mean_ann = m * 12, t_plain = t_plain, t_nw = t_nw,
                 ci_lo = ci[1L], ci_hi = ci[2L])
}

#' The decomposition table: three effects, three legs
#'
#' Over the months common to the four portfolios (see pit_common_months()),
#' the monthly difference of each leg between two variants:
#' biased - current_members (size / concentration), current_members - pit_upper
#' (survivorship), pit_upper - pit_lower (failure bound). The long-short leg is
#' `port_ret`: costs are the same for every variant, so they cancel in a
#' difference.
#' @param biased,current,upper,lower The four portfolios.
#' @param min_months Abort when fewer common months remain.
#' @param ... Passed to pit_diff_stats() (`lags`, `block`, `B`, `level`).
#' @return Tibble: comparison, effect, leg ("long", "short", "long_short"),
#'   then the columns of pit_diff_stats().
#' @noRd
pit_max_decomposition <- function(biased, current, upper, lower,
                                  min_months = 24L, ...) {
  common <- pit_common_months(list(biased, current, upper, lower), min_months)
  get <- function(p, col) p[[col]][match(common, p$ym)]
  pairs <- list(
    list(a = biased, b = current, comparison = "biased - current_members",
         effect = "size / concentration"),
    list(a = current, b = upper, comparison = "current_members - pit_upper",
         effect = "survivorship"),
    list(a = upper, b = lower, comparison = "pit_upper - pit_lower",
         effect = "failure bound")
  )
  legs <- c(long = "long_ret", short = "short_ret", long_short = "port_ret")
  dplyr::bind_rows(lapply(pairs, function(pr) {
    dplyr::bind_rows(lapply(names(legs), function(leg) {
      st <- pit_diff_stats(get(pr$a, legs[[leg]]) - get(pr$b, legs[[leg]]), ...)
      dplyr::bind_cols(
        tibble::tibble(comparison = pr$comparison, effect = pr$effect, leg = leg), st
      )
    }))
  }))
}

#' Bars of today's S&P 500 members only, symbol reuse trimmed
#'
#' Alpaca returns a renamed company's FULL history under its CURRENT symbol
#' (META, FISV and DOC each have the whole 2016 to 2026 history, no gaps). The
#' fetch also pulled the OLD symbols (FB, FI, HCP, ...), and several old symbols
#' were later REUSED by other companies: HCP is Healthpeak's old symbol (to
#' 2019-11), then, after a gap, HashiCorp (2021-12 to 2025-02). Using the old
#' symbols and splicing them onto the current ticker would put HashiCorp's bars
#' on Healthpeak's series. So only bars whose symbol is in the latest snapshot of
#' `universe` are kept, and renames are NOT spliced. hd_trim_symbol_reuse() runs
#' AFTER the filter: it still matters for current symbols that an earlier company
#' used (DOW: Dow Chemical before 2017; EXE; SMCI).
#' @param bars Adjusted bars (`symbol`, `date`, `close`, `volume`, ...).
#' @param universe stk_universe_pit (`ticker`, `date`).
#' @return The kept bars, with the attribute `trimmed` (hd_trim_symbol_reuse()).
#' @noRd
pit_current_member_bars <- function(bars, universe) {
  latest <- max(universe$date)
  today <- unique(universe$ticker[universe$date == latest])
  hd_trim_symbol_reuse(bars[bars$symbol %in% today, , drop = FALSE])
}

#' Monthly returns of today's S&P 500 members, carried back
#'
#' Calls hd_pit_monthly_returns() with ONE membership snapshot, dated the day
#' before `panel_start`, listing the tickers of the latest snapshot of
#' `universe`: every month's universe is today's list. A stock listed later
#' enters when it first has a signal-month and a held-month bar. The exit table
#' is passed with ZERO rows: no exits by construction, and no rename is spliced
#' (see pit_current_member_bars()).
#' @param bars Bars of today's members (pit_current_member_bars()).
#' @param universe stk_universe_pit (`ticker`, `date`).
#' @param exit_prices stk_exit_prices (only its columns are used; all rows dropped).
#' @param panel_start Date; first day of the backtest window.
#' @return As hd_pit_monthly_returns().
#' @noRd
pit_current_members_monthly <- function(bars, universe, exit_prices, panel_start) {
  latest <- max(universe$date)
  members <- tibble::tibble(
    ticker = sort(unique(universe$ticker[universe$date == latest])),
    date = as.Date(panel_start) - 1L
  )
  hd_pit_monthly_returns(bars, members, exit_prices[0L, , drop = FALSE])
}

#' Securities excluded from the PIT backtest, in-window and overall
#'
#' Leavers that left the index before the backtest window (`panel_start`) were
#' never candidates for a held month, so the headline count is restricted to
#' securities that were members at some snapshot on or after `panel_start`. The
#' count over all securities stays in `n_all`, so nothing is hidden.
#' @param excluded `attr(stk_pit_monthly, "excluded")`: `ticker` (permanent id),
#'   `reason`, `last_member_date` (latest snapshot at which it was a member).
#' @param panel_start Date; first day of the backtest window.
#' @return Tibble: `reason`, `n_securities` (in-window), `n_all` (all).
#' @noRd
pit_excluded_summary <- function(excluded, panel_start) {
  excluded |>
    dplyr::group_by(reason) |>
    dplyr::summarise(
      n_securities = sum(last_member_date >= panel_start),
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
      pit_excluded_summary(attr(stk_pit_monthly, "excluded"),
                           hd_alpaca_exit_rule()$panel_start)
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

    # ---- Fourth variant: today's S&P 500 members carried back (#1041) -------
    # A machine without the cache fails loudly, naming the fetch script.
    targets::tar_target(
      stk_current_member_bars_adj_file,
      hd_alpaca_current_member_bars_adj_path(),
      format = "file"
    ),

    # Only today's symbols (old symbols of renames are fetched but NOT used:
    # Alpaca gives the full history under the current symbol, and a reused old
    # symbol, e.g. HCP -> HashiCorp, would corrupt the series), then symbol reuse
    # trimmed; the trims stay on the attribute "trimmed" and in
    # stk_current_member_trimmed.
    targets::tar_target(stk_current_member_bars_adj, {
      pit_current_member_bars(
        tibble::as_tibble(arrow::read_parquet(stk_current_member_bars_adj_file)),
        stk_universe_pit
      )
    }),

    targets::tar_target(stk_current_member_trimmed, {
      attr(stk_current_member_bars_adj, "trimmed")
    }),

    targets::tar_target(stk_current_members_series, {
      hd_pit_price_series(stk_current_member_bars_adj, stk_exit_prices[0L, , drop = FALSE])
    }),

    targets::tar_target(stk_current_members_monthly, {
      pit_current_members_monthly(
        stk_current_member_bars_adj, stk_universe_pit, stk_exit_prices,
        hd_alpaca_exit_rule()$panel_start
      )
    }),

    targets::tar_target(stk_current_members_max_signal, {
      pit_max_signal(stk_current_members_series)
    }),

    targets::tar_target(stk_current_members_max_panel, {
      pit_max_panel(stk_current_members_monthly, stk_current_members_max_signal,
                    stk_params$n_deciles)
    }),

    # No exits, so ret_upper == ret_lower; "upper" is the same series either way.
    targets::tar_target(stk_current_members_max_portfolio, {
      pit_max_portfolio(stk_current_members_max_panel, "upper", stk_params, stk_rf)
    }),

    targets::tar_target(stk_pit_max_comparison, {
      pit_max_comparison(
        stk_max_portfolio_biased_2016,
        stk_current_members_max_portfolio,
        stk_pit_max_portfolio_upper,
        stk_pit_max_portfolio_lower,
        stk_pit_max_panel,
        stk_current_members_max_panel,
        pit_biased_n_stocks(stk_max_signal, stk_monthly,
                            stk_pit_max_portfolio_upper$ym, stk_params$n_deciles)
      )
    }),

    # Monthly-difference statistics of the three effects (size, survivorship,
    # failure bound); the seed makes the bootstrap interval reproducible.
    targets::tar_target(stk_pit_max_decomposition, {
      set.seed(1041L)
      pit_max_decomposition(
        stk_max_portfolio_biased_2016,
        stk_current_members_max_portfolio,
        stk_pit_max_portfolio_upper,
        stk_pit_max_portfolio_lower,
        lags = 6L, block = 6L, B = 10000L
      )
    })

  )
}
