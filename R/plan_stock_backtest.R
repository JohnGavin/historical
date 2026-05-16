# Stock-level backtesting: shared infrastructure + Factor MAX + DRIF
#
# Cross-sectional strategies applied to 660+ individual stocks
# (S&P 500 + STOXX 600 majors, excluding LSE ETFs).
#
# Group 1: shared infrastructure (universe, features, helpers)
# Group 2: stock-level Factor MAX
# Group 3: stock-level DRIF (TODO — compute intensive)

# ── Helpers (not targets) ─────────────────────────────────────────

#' Shift a "YYYY-MM" string by one calendar month
#'
#' Replaces the look-ahead-prone `dplyr::lead(ym)` row-based shift, which
#' silently pairs a month-T signal with a non-T+1 return when a ticker has
#' gaps in its monthly panel. Calendar-based shift means the signal_ym -> ym
#' pairing is fixed at the calendar level — missing months become explicit
#' NA after the downstream join rather than silently shifting to the wrong
#' return. Vectorised; base R only (no lubridate dep).
#'
#' Fixes roborev #752 (R/plan_stock_backtest.R look-ahead).
#'
#' @noRd
next_ym <- function(ym) {
  vapply(ym, function(x) {
    if (is.na(x) || !nzchar(x)) return(NA_character_)
    d <- as.Date(paste0(x, "-01"))
    if (is.na(d)) return(NA_character_)
    d_next <- seq.Date(d, by = "1 month", length.out = 2L)[2L]
    format(d_next, "%Y-%m")
  }, character(1L), USE.NAMES = FALSE)
}

#' Assign decile ranks within each month
#' @param df Data frame with ym and signal columns
#' @param signal_col Name of signal column (unquoted)
#' @param n_groups Number of groups (default 10 = deciles)
#' @return df with added `decile` column (1 = highest signal)
assign_decile <- function(df, signal_col, n_groups = 10L) {
  df |>
    dplyr::group_by(ym) |>
    dplyr::mutate(
      decile = dplyr::ntile(dplyr::desc({{ signal_col }}), n_groups)
    ) |>
    dplyr::ungroup()
}

#' Compute long-short portfolio returns with realistic costs
#' @param df Data frame with ym, ticker, decile, and monthly_ret columns
#' @param long_decile Which decile to go long (default 1 = top)
#' @param short_decile Which decile to short (default 10 = bottom). NULL = long only.
#' @param cost_per_trade Cost per trade as fraction (default 0.005 = 0.50%)
#' @param borrow_rate_annual Annual borrow cost for short positions (default 0.03 = 3%)
#' @param max_monthly_ret Winsorise monthly returns at ±this (default 0.20 = 20%)
#' @return Tibble with ym, port_ret, long_ret, short_ret, n_long, n_short, turnover, total_cost
portfolio_longshort <- function(df, long_decile = 1L, short_decile = 10L,
                                cost_per_trade = 0.005,
                                borrow_rate_annual = 0.03,
                                max_monthly_ret = 0.20) {
  # Option 2: Winsorise extreme monthly returns
  df <- df |>
    dplyr::mutate(monthly_ret = pmin(pmax(monthly_ret, -max_monthly_ret), max_monthly_ret))

  # Option 4: Estimate turnover per decile per month
  # Count tickers per decile-month, assume ~80% turnover (conservative for monthly sort)
  est_turnover <- 0.80

  long <- df |>
    dplyr::filter(decile == long_decile) |>
    dplyr::group_by(ym) |>
    dplyr::summarise(long_ret = mean(monthly_ret, na.rm = TRUE),
                     n_long = dplyr::n(), .groups = "drop")

  if (is.null(short_decile)) {
    return(long |> dplyr::mutate(
      turnover = est_turnover,
      total_cost = turnover * cost_per_trade * 2,  # buy + sell
      port_ret = long_ret - total_cost,
      short_ret = 0, n_short = 0L
    ))
  }

  short <- df |>
    dplyr::filter(decile == short_decile) |>
    dplyr::group_by(ym) |>
    dplyr::summarise(short_ret = mean(monthly_ret, na.rm = TRUE),
                     n_short = dplyr::n(), .groups = "drop")

  dplyr::inner_join(long, short, by = "ym") |>
    dplyr::mutate(
      turnover = est_turnover,
      # Option 1+4: Transaction costs = turnover × cost × 2 legs × 2 (buy+sell)
      trade_cost = turnover * cost_per_trade * 2 * 2,  # both legs
      # Option 5: Borrow cost for short leg
      borrow_cost = borrow_rate_annual / 12,
      total_cost = trade_cost + borrow_cost,
      # Net long-short return
      port_ret = long_ret - short_ret - total_cost
    )
}

#' Apply ADV-based participation cap to HRP weights
#'
#' For each (date, ticker) in a named weight vector, cap the weight so that
#' no single position exceeds adv_pct_cap × (stock ADV / total-leg ADV).
#' This is a portfolio-size-free cap: it bounds weight proportional to ADV share.
#' Residual weight is redistributed proportionally to remaining positions.
#'
#' @param w Named numeric vector of portfolio weights (must sum to 1)
#' @param adv_by_ticker Named numeric vector: ticker → monthly ADV in dollar terms
#' @param adv_pct_cap Maximum fraction of ADV-weighted capacity per stock (default 0.10)
#' @return List with capped_w (renormalised) and hit_cap (logical vector)
apply_adv_cap <- function(w, adv_by_ticker, adv_pct_cap = 0.10) {
  if (length(w) == 0L) return(list(capped_w = w, hit_cap = logical(0)))
  # Align ADV to weight vector; fill missing with median (conservative)
  tickers <- names(w)
  adv <- adv_by_ticker[tickers]
  adv[is.na(adv)] <- median(adv_by_ticker, na.rm = TRUE)
  adv[is.na(adv) | adv <= 0] <- 1  # guard: zero/missing ADV gets token liquidity

  # ADV-proportional capacity: each stock's share of total-leg ADV
  adv_share <- adv / sum(adv, na.rm = TRUE)
  w_max     <- adv_share * adv_pct_cap / min(adv_pct_cap, 1)
  # Simpler: max allowed weight = adv_pct_cap times the ADV-proportional share
  # scaled so that if all stocks are at cap they still sum to 1
  # => w_max_i = adv_share_i (when adv_pct_cap >= 1 no cap binds)
  # For adv_pct_cap < 1: allow up to adv_share_i / adv_pct_cap * adv_pct_cap = adv_share_i
  # More useful: allow up to adv_pct_cap per stock regardless of ADV (dollar-share cap).
  # Use: max weight = adv_share_i × (1 / adv_pct_cap) × adv_pct_cap = adv_share_i
  # (this is identical). Better interpretation: cap at adv_pct_cap × adv_share_i/min(adv_share_i)
  # which bounds positions proportional to ADV. Use the simplest defensible rule:
  # cap each weight at adv_pct_cap (absolute weight cap) where ADV ratio is < threshold.
  # For large-decile portfolios the uncapped HRP weight ≈ 1/n ≈ 0.015 for n=65.
  # adv_pct_cap=0.10 as absolute weight cap would bind almost nothing.
  # Correct approach: cap at adv_share_i × (1/adv_pct_cap) rescaled to sum=1 — too complex.
  # Final decision: use dollar-ADV cap where effective weight ≤ adv_pct_cap × ADV_share × n,
  # which simplifies to: if w_i > adv_pct_cap × adv_share_i × n, cap to that value.
  n <- length(w)
  w_max <- adv_pct_cap * adv_share * n  # cap: 10% × ADV-fraction × n_stocks
  w_max <- pmin(w_max, 1)               # never cap above 1

  hit_cap  <- w > w_max
  w_capped <- pmin(w, w_max)

  # Redistribute residual proportionally to uncapped positions
  residual <- sum(w) - sum(w_capped)
  if (residual > 1e-10 && any(!hit_cap)) {
    uncapped_sum <- sum(w_capped[!hit_cap])
    if (uncapped_sum > 0) {
      w_capped[!hit_cap] <- w_capped[!hit_cap] * (sum(w_capped[!hit_cap]) + residual) / uncapped_sum
    }
  }

  # Renormalise to sum to 1
  w_total <- sum(w_capped)
  if (w_total > 0) w_capped <- w_capped / w_total

  list(capped_w = w_capped, hit_cap = hit_cap)
}

#' Long-short portfolio with HRP weighting per leg (Lopez de Prado 2016)
#' @param df Data frame with ym, ticker, decile, monthly_ret (signal-to-return merged)
#' @param returns_wide Wide tibble: rows = ym, cols = ticker, values = monthly_ret
#' @param long_decile Which decile to go long (default 1 = top)
#' @param short_decile Which decile to short (default 10 = bottom)
#' @param lookback_months HRP covariance lookback (default 36L)
#' @param cost_per_trade Cost per trade as fraction (default 0.005 = 0.50%)
#' @param borrow_rate_annual Annual borrow cost for short positions (default 0.03 = 3%)
#' @param max_monthly_ret Winsorise monthly returns at ±this (default 0.20 = 20%)
#' @param adv_monthly Monthly ADV data: tibble(ym, ticker, adv_dollars). NULL = no cap.
#' @param adv_pct_cap Maximum participation per stock as multiple of ADV-weight share × n (default 0.10)
#' @return Tibble with same shape as portfolio_longshort, plus adv_cap columns when adv_monthly supplied
portfolio_longshort_hrp <- function(df, returns_wide,
                                    long_decile = 1L, short_decile = 10L,
                                    lookback_months = 36L,
                                    cost_per_trade = 0.005,
                                    borrow_rate_annual = 0.03,
                                    max_monthly_ret = 0.20,
                                    adv_monthly = NULL,
                                    adv_pct_cap = 0.10) {
  if (!requireNamespace("HierPortfolios", quietly = TRUE)) {
    cli::cli_abort("HierPortfolios package required for HRP weighting")
  }
  use_adv_cap <- !is.null(adv_monthly)
  # Winsorise returns
  df <- df |>
    dplyr::mutate(monthly_ret = pmin(pmax(monthly_ret, -max_monthly_ret), max_monthly_ret))

  # Helper: compute HRP weights for a vector of tickers given a returns_wide slice
  hrp_weights_for_tickers <- function(tickers, ret_slice) {
    sub <- ret_slice[, intersect(tickers, colnames(ret_slice)), drop = FALSE]
    # Drop tickers with too few observations
    n_obs <- colSums(!is.na(sub))
    keep <- n_obs >= max(12L, ceiling(nrow(sub) * 0.5))
    sub <- sub[, keep, drop = FALSE]
    if (ncol(sub) < 3L) return(NULL)  # signal fallback
    cov_mat <- stats::cov(sub, use = "pairwise.complete.obs")
    if (any(!is.finite(cov_mat))) return(NULL)
    w <- tryCatch({
      hrp_result <- HierPortfolios::HRP_Portfolio(cov_mat)
      w <- as.numeric(hrp_result$weights)
      names(w) <- colnames(cov_mat)
      w / sum(w)
    }, error = function(e) NULL)
    w
  }

  # Iterate months in order; for each, fit HRP per leg
  months <- sort(unique(df$ym))
  prev_w_long  <- numeric(0); names(prev_w_long)  <- character(0)
  prev_w_short <- numeric(0); names(prev_w_short) <- character(0)
  fallback_count <- 0L

  out <- vector("list", length(months))
  for (i in seq_along(months)) {
    ym_t <- months[i]
    # Lookback window: months strictly before ym_t in returns_wide
    ret_idx <- which(returns_wide$ym < ym_t)
    if (length(ret_idx) < lookback_months) {
      # Not enough history yet — skip this month
      next
    }
    ret_slice <- returns_wide[utils::tail(ret_idx, lookback_months), -1L, drop = FALSE]

    longs  <- df$ticker[df$ym == ym_t & df$decile == long_decile]
    shorts <- df$ticker[df$ym == ym_t & df$decile == short_decile]
    if (length(longs) == 0L || length(shorts) == 0L) next

    w_long  <- hrp_weights_for_tickers(longs,  ret_slice)
    w_short <- hrp_weights_for_tickers(shorts, ret_slice)

    if (is.null(w_long) || is.null(w_short)) {
      # Equal-weight fallback
      fallback_count <- fallback_count + 1L
      if (is.null(w_long))  w_long  <- setNames(rep(1 / length(longs),  length(longs)),  longs)
      if (is.null(w_short)) w_short <- setNames(rep(1 / length(shorts), length(shorts)), shorts)
    }

    # ADV participation cap (applied AFTER HRP, BEFORE return computation)
    n_cap_long  <- 0L
    n_cap_short <- 0L
    if (use_adv_cap) {
      adv_t <- adv_monthly[adv_monthly$ym == ym_t, c("ticker", "adv_dollars")]
      adv_vec <- setNames(adv_t$adv_dollars, adv_t$ticker)

      cap_long  <- apply_adv_cap(w_long,  adv_vec, adv_pct_cap)
      cap_short <- apply_adv_cap(w_short, adv_vec, adv_pct_cap)

      n_cap_long  <- sum(cap_long$hit_cap)
      n_cap_short <- sum(cap_short$hit_cap)

      w_long  <- cap_long$capped_w
      w_short <- cap_short$capped_w
    }

    # Compute weighted returns from this month's actual returns
    ret_long  <- df[df$ym == ym_t & df$decile == long_decile,  c("ticker", "monthly_ret")]
    ret_short <- df[df$ym == ym_t & df$decile == short_decile, c("ticker", "monthly_ret")]
    long_ret  <- sum(w_long[ret_long$ticker]   * ret_long$monthly_ret,   na.rm = TRUE)
    short_ret <- sum(w_short[ret_short$ticker] * ret_short$monthly_ret, na.rm = TRUE)

    # Actual turnover (vs prior month weights, aligned by ticker)
    align_turnover <- function(w_new, w_old) {
      all_t <- union(names(w_new), names(w_old))
      v_new <- ifelse(all_t %in% names(w_new), w_new[all_t], 0)
      v_old <- ifelse(all_t %in% names(w_old), w_old[all_t], 0)
      0.5 * sum(abs(v_new - v_old), na.rm = TRUE)
    }
    turnover_long  <- if (length(prev_w_long)  == 0L) 1.0 else align_turnover(w_long,  prev_w_long)
    turnover_short <- if (length(prev_w_short) == 0L) 1.0 else align_turnover(w_short, prev_w_short)
    turnover <- (turnover_long + turnover_short) / 2

    trade_cost  <- turnover * cost_per_trade * 2 * 2   # both legs, buy + sell
    borrow_cost <- borrow_rate_annual / 12
    total_cost  <- trade_cost + borrow_cost
    port_ret    <- long_ret - short_ret - total_cost

    out[[i]] <- dplyr::tibble(
      ym         = ym_t,
      port_ret   = port_ret,
      long_ret   = long_ret,
      short_ret  = short_ret,
      n_long     = length(w_long),
      n_short    = length(w_short),
      turnover   = turnover,
      total_cost = total_cost,
      n_cap_long  = n_cap_long,
      n_cap_short = n_cap_short
    )

    prev_w_long  <- w_long
    prev_w_short <- w_short
  }

  if (fallback_count > 0L) {
    cli::cli_warn(
      "HRP fell back to equal weight in {fallback_count} of {length(months)} months (insufficient covariance history)"
    )
  }
  dplyr::bind_rows(out)
}

#' Standard backtest metrics
calc_backtest_metrics <- function(df, label, rf_col = "rf_ret") {
  n <- nrow(df)
  if (n < 12) return(NULL)
  ann_ret <- prod(1 + df$port_ret)^(12/n) - 1
  ann_vol <- sd(df$port_ret) * sqrt(12)
  rf_ann <- if (rf_col %in% names(df)) mean(df[[rf_col]], na.rm = TRUE) * 12 else 0
  sharpe <- (ann_ret - rf_ann) / ann_vol
  cum <- cumprod(1 + df$port_ret)
  max_dd <- min(cum / cummax(cum) - 1)

  dplyr::tibble(
    period = label, months = n,
    cagr = ann_ret, vol = ann_vol, sharpe = sharpe, max_dd = max_dd,
    avg_long = mean(df$n_long), avg_short = mean(df$n_short, na.rm = TRUE)
  )
}


plan_stock_backtest <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(stk_params, {
      p <- bt_partitions$equity
      list(
        min_history_days = 252L,
        lookback_days = 21L,
        n_deciles = 10L,
        start_date = p$train_start,
        is_end = p$train_end,
        test_start = p$test_start,
        test_end = p$test_end,
        val_start = p$val_start,
        val_end = p$val_end,
        oos_start = p$test_start,
        # Cost model (Options 1, 4, 5)
        cost_per_trade = 0.005,       # 0.50% per trade (Option 1: higher than 0.10%)
        borrow_rate_annual = 0.03,    # 3% annualised borrow cost for shorts (Option 5)
        max_monthly_ret = 0.20,       # Winsorise at ±20% (Option 2)
        hrp_lookback_months = 36L,    # HRP covariance lookback for stock-level long-short
        adv_pct_cap = 0.10,           # ADV participation cap: 10% of ADV-weighted share × n
        top_n_market_cap = 100L       # #150 Option C: restrict to top-N by current market cap
      )
    }),

    # ── Group 1: Top-N tickers by current market cap (#150 Option C) ──
    targets::tar_target(stk_top_tickers, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      meta_url <- hd_datasets()[["metadata"]]$url
      duckplyr::read_parquet_duckdb(meta_url) |>
        filter(dataset == "equity_daily", !is.na(market_cap), !grepl("\\.L$", ticker)) |>
        collect() |>
        slice_max(market_cap, n = stk_params$top_n_market_cap) |>
        pull(ticker)
    }, cue = targets::tar_cue(mode = "always")),

    # ── Group 1: Universe — top-N non-ETF stocks with sufficient history ──
    targets::tar_target(stk_universe, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      ds <- hd_datasets()[["equity_daily"]]

      # All daily data for non-LSE-ETF tickers, restricted to top-N by market cap (#150 Option C)
      all_data <- duckplyr::read_parquet_duckdb(ds$url) |>
        filter(!grepl("\\.L$", ticker), ticker %in% stk_top_tickers) |>
        select(date, ticker, close, adjusted, volume) |>
        collect()

      # Filter to tickers with enough history
      ticker_stats <- all_data |>
        group_by(ticker) |>
        summarise(n_days = n(), first_date = min(date), last_date = max(date),
                  .groups = "drop") |>
        filter(n_days >= stk_params$min_history_days)

      # Keep only qualifying tickers, from start_date onward
      all_data |>
        filter(ticker %in% ticker_stats$ticker,
               date >= stk_params$start_date) |>
        arrange(ticker, date) |>
        mutate(date = as.Date(date, tz = "UTC"))   # coerce POSIXct from DuckDB TIMESTAMP
    }),

    # ── Group 1: Monthly returns for all stocks ───────────────────
    targets::tar_target(stk_monthly, {
      library(dplyr)

      stk_universe |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        group_by(ticker) |>
        arrange(date) |>
        mutate(monthly_ret = adjusted / dplyr::lag(adjusted) - 1) |>
        filter(!is.na(monthly_ret)) |>
        ungroup() |>
        select(ticker, date, ym, monthly_ret)
    }),

    # ── Group 1: Daily returns (for MAX signal + DRIF features) ───
    targets::tar_target(stk_daily_ret, {
      library(dplyr)

      stk_universe |>
        group_by(ticker) |>
        arrange(date) |>
        mutate(daily_ret = adjusted / dplyr::lag(adjusted) - 1) |>
        filter(!is.na(daily_ret)) |>
        ungroup() |>
        select(ticker, date, daily_ret)
    }),

    # ── Group 1: Risk-free rate (monthly) ─────────────────────────
    targets::tar_target(stk_rf, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      hd_factors(dataset = "FF3", frequency = "daily",
                 from = as.character(stk_params$start_date)) |>
        filter(factor_name == "RF") |>
        mutate(value = value / 100, ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(rf_ret = prod(1 + value) - 1, .groups = "drop")
    }),

    # ── Group 1: Monthly ADV per ticker (for ADV participation cap) ──
    targets::tar_target(stk_monthly_adv, {
      library(dplyr)

      stk_universe |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        summarise(
          adv_shares = median(volume, na.rm = TRUE),   # median daily volume over month
          avg_close  = mean(close,  na.rm = TRUE),
          adv_dollars = adv_shares * avg_close,        # approx daily ADV in dollar terms
          .groups = "drop"
        ) |>
        filter(!is.na(adv_dollars), adv_dollars > 0)
    }),

    # ── Group 2: Stock-level Factor MAX signal ────────────────────
    targets::tar_target(stk_max_signal, {
      library(dplyr)

      stk_daily_ret |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        summarise(
          max_ret = max(daily_ret, na.rm = TRUE),
          n_days = n(),
          .groups = "drop"
        ) |>
        filter(n_days >= 10)  # 10 days minimum (was 15 — dropped March due to holidays, see #43)
    }),

    # ── Group 2: Stock MAX decile portfolios ──────────────────────
    targets::tar_target(stk_max_portfolio, {
      library(dplyr)

      # Signal: use PREVIOUS month's MAX to predict NEXT month's return
      signal <- stk_max_signal |>
        group_by(ticker) |>
        arrange(ym) |>
        mutate(signal_ym = ym, ym = next_ym(ym)) |>
        filter(!is.na(ym)) |>
        ungroup()

      # Merge signal with next month's actual return
      merged <- signal |>
        select(ticker, ym, max_ret) |>
        inner_join(stk_monthly, by = c("ticker", "ym"))

      # Drop months with too few stocks for meaningful deciles (#43)
      stocks_per_month <- merged |> count(ym, name = "n_stocks")
      valid_months <- stocks_per_month |> filter(n_stocks >= stk_params$n_deciles * 5) |> pull(ym)
      merged <- merged |> filter(ym %in% valid_months)

      # Assign deciles and compute portfolio returns
      deciled <- assign_decile(merged, max_ret, stk_params$n_deciles)
      port <- portfolio_longshort(deciled, long_decile = 1L, short_decile = 10L,
                                   cost_per_trade = stk_params$cost_per_trade,
                                   borrow_rate_annual = stk_params$borrow_rate_annual,
                                   max_monthly_ret = stk_params$max_monthly_ret)

      # Add risk-free rate
      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          port_cum = cumprod(1 + port_ret),
          long_cum = cumprod(1 + long_ret)
        )
    }),

    # ── Group 2: Stock MAX HRP-weighted variant (#114 Phase 2) ────
    targets::tar_target(stk_max_portfolio_hrp, {
      library(dplyr)

      # Wide-format monthly returns for HRP covariance
      returns_wide <- stk_monthly |>
        select(ym, ticker, monthly_ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = monthly_ret) |>
        arrange(ym)

      # Same signal-merge as stk_max_portfolio
      signal <- stk_max_signal |>
        group_by(ticker) |>
        arrange(ym) |>
        mutate(signal_ym = ym, ym = next_ym(ym)) |>
        filter(!is.na(ym)) |>
        ungroup()

      merged <- signal |>
        select(ticker, ym, max_ret) |>
        inner_join(stk_monthly, by = c("ticker", "ym"))

      stocks_per_month <- merged |> count(ym, name = "n_stocks")
      valid_months <- stocks_per_month |> filter(n_stocks >= stk_params$n_deciles * 5) |> pull(ym)
      merged <- merged |> filter(ym %in% valid_months)

      deciled <- assign_decile(merged, max_ret, stk_params$n_deciles)
      port <- portfolio_longshort_hrp(
        deciled, returns_wide,
        long_decile = 1L, short_decile = 10L,
        lookback_months = stk_params$hrp_lookback_months,
        cost_per_trade = stk_params$cost_per_trade,
        borrow_rate_annual = stk_params$borrow_rate_annual,
        max_monthly_ret = stk_params$max_monthly_ret
      )

      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          port_cum = cumprod(1 + port_ret),
          long_cum = cumprod(1 + long_ret)
        )
    }),

    # ── Group 2: Stock MAX HRP + ADV-cap variant (#143 gap #3) ──────
    targets::tar_target(stk_max_portfolio_hrp_adv, {
      library(dplyr)

      # Wide-format monthly returns for HRP covariance
      returns_wide <- stk_monthly |>
        select(ym, ticker, monthly_ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = monthly_ret) |>
        arrange(ym)

      # Same signal-merge as stk_max_portfolio
      signal <- stk_max_signal |>
        group_by(ticker) |>
        arrange(ym) |>
        mutate(signal_ym = ym, ym = next_ym(ym)) |>
        filter(!is.na(ym)) |>
        ungroup()

      merged <- signal |>
        select(ticker, ym, max_ret) |>
        inner_join(stk_monthly, by = c("ticker", "ym"))

      stocks_per_month <- merged |> count(ym, name = "n_stocks")
      valid_months <- stocks_per_month |> filter(n_stocks >= stk_params$n_deciles * 5) |> pull(ym)
      merged <- merged |> filter(ym %in% valid_months)

      deciled <- assign_decile(merged, max_ret, stk_params$n_deciles)
      port <- portfolio_longshort_hrp(
        deciled, returns_wide,
        long_decile = 1L, short_decile = 10L,
        lookback_months = stk_params$hrp_lookback_months,
        cost_per_trade = stk_params$cost_per_trade,
        borrow_rate_annual = stk_params$borrow_rate_annual,
        max_monthly_ret = stk_params$max_monthly_ret,
        adv_monthly = stk_monthly_adv,
        adv_pct_cap = stk_params$adv_pct_cap
      )

      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          port_cum = cumprod(1 + port_ret),
          long_cum = cumprod(1 + long_ret)
        )
    }),

    # ── Group 2: ADV cap impact analysis (#143 gap #3) ───────────
    targets::tar_target(stk_max_adv_cap_impact, {
      library(dplyr)

      p <- stk_max_portfolio_hrp_adv
      n_months <- nrow(p)

      # Overall cap statistics
      overall <- tibble::tibble(
        metric = c(
          "months_in_backtest",
          "pct_months_any_cap_long",
          "pct_months_any_cap_short",
          "avg_caps_per_month_long",
          "avg_caps_per_month_short",
          "avg_turnover_hrp",
          "avg_turnover_hrp_adv"
        ),
        value = c(
          n_months,
          round(100 * mean(p$n_cap_long  > 0, na.rm = TRUE), 1),
          round(100 * mean(p$n_cap_short > 0, na.rm = TRUE), 1),
          round(mean(p$n_cap_long,  na.rm = TRUE), 2),
          round(mean(p$n_cap_short, na.rm = TRUE), 2),
          round(mean(stk_max_portfolio_hrp$turnover, na.rm = TRUE), 4),
          round(mean(p$turnover, na.rm = TRUE), 4)
        )
      )

      # Annual cap rate
      by_year <- p |>
        mutate(year = substr(ym, 1, 4)) |>
        group_by(year) |>
        summarise(
          n_months  = dplyr::n(),
          pct_cap_long  = round(100 * mean(n_cap_long  > 0, na.rm = TRUE), 1),
          pct_cap_short = round(100 * mean(n_cap_short > 0, na.rm = TRUE), 1),
          avg_turnover  = round(mean(turnover, na.rm = TRUE), 4),
          avg_cost      = round(mean(total_cost, na.rm = TRUE), 4),
          .groups = "drop"
        )

      list(overall = overall, by_year = by_year)
    }),

    # ── Group 2: Stock MAX metrics ────────────────────────────────
    targets::tar_target(stk_max_metrics, {
      library(dplyr)

      p <- stk_max_portfolio
      bind_rows(
        calc_backtest_metrics(p |> filter(date <= stk_params$is_end), "Training"),
        calc_backtest_metrics(p |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_backtest_metrics(p |> filter(date >= stk_params$val_start), "Validation"),
        calc_backtest_metrics(p, "Full Period")
      ) |> mutate(survivorship_biased = TRUE)  # stk_universe is survivorship-biased; see #150
    }),

    # ── Group 2: Stock MAX EW vs HRP vs HRP+ADV comparison (#143) ──
    targets::tar_target(stk_max_hrp_comparison, {
      library(dplyr)

      ew  <- stk_max_portfolio
      hrp <- stk_max_portfolio_hrp
      adv <- stk_max_portfolio_hrp_adv

      add_cost_cols <- function(port, label) {
        bind_rows(
          calc_backtest_metrics(port |> filter(date <= stk_params$is_end), "Training"),
          calc_backtest_metrics(port |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
          calc_backtest_metrics(port |> filter(date >= stk_params$val_start), "Validation"),
          calc_backtest_metrics(port, "Full Period")
        ) |>
          mutate(
            weighting    = label,
            avg_turnover = round(mean(port$turnover, na.rm = TRUE), 3),
            avg_cost_mth = round(mean(port$total_cost, na.rm = TRUE), 4)
          )
      }

      bind_rows(
        add_cost_cols(ew,  "PSO Equal Weight"),
        add_cost_cols(hrp, "HRP"),
        add_cost_cols(adv, "HRP+ADV-cap")
      ) |>
        select(weighting, period, months, cagr, vol, sharpe, max_dd,
               avg_turnover, avg_cost_mth) |>
        mutate(survivorship_biased = TRUE)  # see #150
    }),

    # ── Group 2: Stock MAX cumulative return plot ─────────────────
    targets::tar_target(stk_max_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      p <- stk_max_portfolio
      plot_data <- p |>
        select(date,
               `Long-Short (D1-D10)` = port_cum,
               `Long Only (D1)` = long_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        annotate("text", x = stk_params$oos_start, y = max(plot_data$growth) * 0.9,
                 label = "OOS", colour = "grey60", hjust = -0.1, size = 3) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = paste0("Stock-Level Factor MAX (",
                            round(mean(stk_max_portfolio$n_long)), " stocks/decile)")) +
        hd_theme()
    }),

    # ── Group 2: Stock MAX vs Factor MAX comparison ───────────────
    targets::tar_target(stk_max_vs_factor, {
      library(dplyr)

      stock <- stk_max_portfolio |> select(ym, stock_ret = port_ret)
      factor <- fm_portfolio |> select(ym, factor_ret = portfolio_ret)

      inner_join(stock, factor, by = "ym") |>
        mutate(
          stock_cum = cumprod(1 + stock_ret),
          factor_cum = cumprod(1 + factor_ret),
          date = as.Date(paste0(ym, "-15"))
        )
    }),

    targets::tar_target(stk_max_vs_factor_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      comp <- stk_max_vs_factor
      plot_data <- comp |>
        select(date,
               `Stock-Level MAX (D1-D10)` = stock_cum,
               `Factor-Level MAX (top 2)` = factor_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Factor MAX: Stock-Level vs Factor-Level") +
        hd_theme()
    }),

    # ══ Group 3: Stock-Level DRIF ═════════════════════════════════

    # ── DRIF features: 42 features per stock-month (vectorised) ───
    targets::tar_target(stk_drif_features, {
      library(dplyr)

      lb <- stk_params$lookback_days
      daily <- stk_daily_ret |> mutate(ym = format(date, "%Y-%m"))

      # For each stock-month, get the prior month's daily returns
      # Strategy: pivot wide by day-of-month rank, then compute features
      all_months <- sort(unique(daily$ym))

      # Pre-compute: for each stock, the last `lb` trading days before each month
      # Using a rolling join approach for efficiency
      features_list <- lapply(seq_along(all_months)[-1], function(i) {
        m <- all_months[i]
        prev_m <- all_months[i - 1]

        # Get prior month's trading days for all stocks
        prior <- daily |>
          filter(ym == prev_m) |>
          group_by(ticker) |>
          filter(n() >= 10) |>  # 10 days minimum (was 15 — see #43)
          mutate(day_rank = row_number()) |>
          ungroup()

        if (nrow(prior) == 0) return(NULL)

        # Chronological features: pad/trim to exactly lb days
        chrono <- prior |>
          filter(day_rank <= lb) |>
          tidyr::pivot_wider(
            id_cols = ticker,
            names_from = day_rank,
            names_prefix = "c",
            values_from = daily_ret
          )

        # Rank features: sort within each stock, then pivot
        ranked <- prior |>
          group_by(ticker) |>
          arrange(daily_ret) |>
          mutate(rank_idx = row_number()) |>
          ungroup() |>
          filter(rank_idx <= lb) |>
          tidyr::pivot_wider(
            id_cols = ticker,
            names_from = rank_idx,
            names_prefix = "r",
            values_from = daily_ret
          )

        # Get next month's return as target
        target <- stk_monthly |> filter(ym == m) |> select(ticker, target_ret = monthly_ret)

        # Combine
        result <- chrono |>
          inner_join(ranked, by = "ticker") |>
          inner_join(target, by = "ticker") |>
          mutate(ym = m)

        result
      })

      bind_rows(Filter(Negate(is.null), features_list))
    }),

    # ── DRIF signal: pooled elastic net, expanding window ─────────
    targets::tar_target(stk_drif_signal, {
      library(dplyr)
      rlang::check_installed("glmnet")

      features <- stk_drif_features
      lb <- stk_params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols <- paste0("r", seq_len(lb))
      feat_cols <- intersect(c(chrono_cols, rank_cols), names(features))

      months <- sort(unique(features$ym))
      min_train <- 60L  # 60 months minimum expanding window

      trade_months <- months[(min_train + 1):length(months)]
      cli::cli_inform(c("i" = "DRIF stock-level: {length(trade_months)} months to process"))

      predictions <- lapply(seq_along(trade_months), function(j) {
        m <- trade_months[j]
        if (j %% 24 == 0) cli::cli_inform(c("i" = "  Month {j}/{length(trade_months)}: {m}"))
        m_idx <- which(months == m)
        train_months <- months[1:(m_idx - 1)]

        train <- features |> filter(ym %in% train_months)
        test <- features |> filter(ym == m)

        if (nrow(test) == 0) return(NULL)

        X_train <- as.matrix(train[, feat_cols])
        y_train <- train$target_ret
        X_test <- as.matrix(test[, feat_cols])

        # Remove incomplete rows
        complete <- complete.cases(X_train, y_train)
        X_train <- X_train[complete, , drop = FALSE]
        y_train <- y_train[complete]

        if (length(y_train) < 200) return(NULL)  # need decent sample

        fit <- tryCatch({
          glmnet::cv.glmnet(X_train, y_train, alpha = 0.5,
                            nfolds = 5, type.measure = "mse")
        }, error = function(e) NULL)

        if (is.null(fit)) return(NULL)
        pred <- as.numeric(predict(fit, X_test, s = "lambda.min"))

        tibble(
          ticker = test$ticker, ym = m,
          predicted_ret = pred, actual_ret = test$target_ret
        )
      })

      bind_rows(Filter(Negate(is.null), predictions))
    }),

    # ── DRIF decile portfolios ────────────────────────────────────
    targets::tar_target(stk_drif_portfolio, {
      library(dplyr)

      signal <- stk_drif_signal |>
        filter(!is.na(predicted_ret)) |>
        inner_join(stk_monthly |> select(ticker, ym, monthly_ret), by = c("ticker", "ym"))

      # Drop months with too few stocks for meaningful deciles (#43)
      stocks_per_month <- signal |> count(ym, name = "n_stocks")
      valid_months <- stocks_per_month |> filter(n_stocks >= stk_params$n_deciles * 5) |> pull(ym)
      signal <- signal |> filter(ym %in% valid_months)

      deciled <- assign_decile(signal, predicted_ret, stk_params$n_deciles)
      port <- portfolio_longshort(deciled, long_decile = 1L, short_decile = 10L,
                                   cost_per_trade = stk_params$cost_per_trade,
                                   borrow_rate_annual = stk_params$borrow_rate_annual,
                                   max_monthly_ret = stk_params$max_monthly_ret)

      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          port_cum = cumprod(1 + port_ret),
          long_cum = cumprod(1 + long_ret)
        )
    }),

    # ── DRIF metrics ──────────────────────────────────────────────
    targets::tar_target(stk_drif_metrics, {
      library(dplyr)
      p <- stk_drif_portfolio
      bind_rows(
        calc_backtest_metrics(p |> filter(date <= stk_params$is_end), "Training"),
        calc_backtest_metrics(p |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_backtest_metrics(p |> filter(date >= stk_params$val_start), "Validation"),
        calc_backtest_metrics(p, "Full Period")
      ) |> mutate(survivorship_biased = TRUE)  # stk_universe is survivorship-biased; see #150
    }),

    # ── DRIF cumulative return plot ───────────────────────────────
    targets::tar_target(stk_drif_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      p <- stk_drif_portfolio
      plot_data <- p |>
        select(date,
               `Long-Short (D1-D10)` = port_cum,
               `Long Only (D1)` = long_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = paste0("Stock-Level DRIF (",
                            round(mean(p$n_long)), " stocks/decile)")) +
        hd_theme()
    }),

    # ── All strategies comparison ─────────────────────────────────
    targets::tar_target(stk_all_comparison, {
      library(dplyr)

      stk_max <- stk_max_portfolio |> select(ym, stk_max = port_ret)
      stk_drif <- stk_drif_portfolio |> select(ym, stk_drif = port_ret)
      fac_max <- fm_portfolio |> select(ym, fac_max = portfolio_ret)
      fac_drif <- drif_portfolio |> select(ym, fac_drif = portfolio_ret)

      stk_max |>
        inner_join(stk_drif, by = "ym") |>
        inner_join(fac_max, by = "ym") |>
        inner_join(fac_drif, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          stk_max_cum = cumprod(1 + stk_max),
          stk_drif_cum = cumprod(1 + stk_drif),
          fac_max_cum = cumprod(1 + fac_max),
          fac_drif_cum = cumprod(1 + fac_drif)
        )
    }),

    targets::tar_target(stk_all_comparison_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      comp <- stk_all_comparison
      plot_data <- comp |>
        select(date,
               `Stock MAX (D1-D10)` = stk_max_cum,
               `Stock DRIF (D1-D10)` = stk_drif_cum,
               `Factor MAX (top 2)` = fac_max_cum,
               `Factor DRIF (top 2)` = fac_drif_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(4)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "All Strategies: Stock-Level vs Factor-Level") +
        hd_theme()
    }),

    targets::tar_target(stk_all_caption, {
      library(dplyr)
      comp <- stk_all_comparison
      years <- as.numeric(difftime(max(comp$date), min(comp$date),
                                   units = "days")) / 365.25
      last <- tail(comp, 1)

      # Final growth of $1
      fmt_growth <- function(x) {
        if (x < 0.01) return("~$0")
        if (x >= 10) return(paste0("$", round(x, 0)))
        paste0("$", round(x, 2))
      }

      # Annualised volatility
      fmt_vol <- function(ret_col) paste0(round(sd(ret_col, na.rm = TRUE) * sqrt(12) * 100), "%")

      # CAGR
      fmt_cagr <- function(cum_val) {
        if (cum_val <= 0) return("N/A")
        paste0(round((cum_val^(1 / years) - 1) * 100, 1), "%")
      }

      paste0(
        "**Equity curves (4 factor/stock strategies).** Growth of $1, log scale, ",
        round(years), " years (",
        format(min(comp$date), "%Y"), "\u2013", format(max(comp$date), "%Y"), "). ",
        "Stock-level strategies lose money net of costs: ",
        "Stock MAX ends at ", fmt_growth(last$stk_max_cum),
        " (vol ", fmt_vol(comp$stk_max), "), ",
        "Stock DRIF at ", fmt_growth(last$stk_drif_cum),
        " (vol ", fmt_vol(comp$stk_drif), "). ",
        "Factor-level strategies survive costs: ",
        "Factor MAX at ", fmt_growth(last$fac_max_cum),
        " (CAGR ", fmt_cagr(last$fac_max_cum), ", vol ", fmt_vol(comp$fac_max), "), ",
        "Factor DRIF at ", fmt_growth(last$fac_drif_cum),
        " (CAGR ", fmt_cagr(last$fac_drif_cum), ", vol ", fmt_vol(comp$fac_drif), "). ",
        "The difference is execution cost, not diversification: ",
        "stock-level decile sorts produce ~80% monthly turnover across ~130 positions ",
        "at 0.50%/trade = ~1.85%/month (~22%/yr). ",
        "Factor-level trades 2\u20134 positions with ~40% turnover at 0.10%/trade = ",
        "~0.16%/month (~2%/yr). ",
        "Dashed line = test partition start (",
        format(stk_params$oos_start, "%Y"), ")."
      )
    })
  )
}
