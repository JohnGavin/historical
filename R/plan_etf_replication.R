# ETF replication of factor strategies (#39)
#
# Approach A: DRIF applied directly to factor ETF daily returns
# Approach B: Academic factor DRIF signal mapped to ETFs for execution
#
# Both use ~0.20%/month costs (ETFs are highly liquid)

# ETF-to-factor mapping
ETF_FACTOR_MAP <- list(
  HML = c("VLUE", "VTV", "IWD"),   # value
  Mom = c("MTUM"),                   # momentum
  RMW = c("QUAL"),                   # profitability/quality
  SMB = c("SIZE"),                   # size
  CMA = c("VUG", "IWF")             # investment/growth (inverse proxy)
)

plan_etf_replication <- function() {
  list(
    # ── ETF parameters ────────────────────────────────────────────
    targets::tar_target(etf_params, {
      p <- bt_partitions$equity
      list(
        etf_tickers = c("VLUE", "MTUM", "QUAL", "USMV", "SIZE", "VTV", "VUG", "IWD", "IWF"),
        benchmark = "SPY",
        top_n = 3L,            # long top 3 ETFs
        bottom_n = 3L,         # short bottom 3
        lookback_days = 21L,
        alpha = 0.5,           # elastic net
        min_train_months = 36L, # shorter than factor (less history)
        cost_per_trade = 0.001, # 0.10% per trade (ETFs are liquid)
        borrow_rate_annual = 0.005, # 0.5% for highly liquid ETFs
        max_monthly_ret = 0.20,
        start_date = as.Date("2013-05-01"),  # VLUE/MTUM inception
        is_end = p$train_end,
        test_start = p$test_start,
        test_end = p$test_end,
        val_start = p$val_start,
        val_end = p$val_end
      )
    }),

    # ── ETF daily returns ─────────────────────────────────────────
    targets::tar_target(etf_daily, {
      library(dplyr)

      all_tickers <- c(etf_params$etf_tickers, etf_params$benchmark)
      raw <- hd_ohlcv(all_tickers, from = as.character(etf_params$start_date))

      raw |>
        group_by(ticker) |>
        arrange(date) |>
        mutate(daily_ret = adjusted / dplyr::lag(adjusted) - 1) |>
        filter(!is.na(daily_ret)) |>
        ungroup() |>
        select(ticker, date, daily_ret, close, adjusted) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
    }),

    # ── ETF monthly returns ───────────────────────────────────────
    targets::tar_target(etf_monthly, {
      library(dplyr)

      etf_daily |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        group_by(ticker) |>
        arrange(date) |>
        mutate(monthly_ret = adjusted / dplyr::lag(adjusted) - 1) |>
        filter(!is.na(monthly_ret)) |>
        ungroup() |>
        select(ticker, date, ym, monthly_ret) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
    }),

    # ══ APPROACH A: DRIF on ETF returns ═══════════════════════════

    # ── A: Feature matrix (42 features per ETF-month) ─────────────
    targets::tar_target(etf_a_features, {
      library(dplyr)

      lb <- etf_params$lookback_days
      daily <- etf_daily |>
        filter(ticker %in% etf_params$etf_tickers) |>
        mutate(ym = format(date, "%Y-%m"))

      all_months <- sort(unique(daily$ym))

      features_list <- lapply(seq_along(all_months)[-1], function(i) {
        m <- all_months[i]
        prev_m <- all_months[i - 1]

        prior <- daily |>
          filter(ym == prev_m) |>
          group_by(ticker) |>
          filter(n() >= 15) |>
          mutate(day_rank = row_number()) |>
          ungroup()

        if (nrow(prior) == 0) return(NULL)

        chrono <- prior |>
          filter(day_rank <= lb) |>
          tidyr::pivot_wider(id_cols = ticker, names_from = day_rank,
                             names_prefix = "c", values_from = daily_ret)

        ranked <- prior |>
          group_by(ticker) |>
          arrange(daily_ret) |>
          mutate(rank_idx = row_number()) |>
          ungroup() |>
          filter(rank_idx <= lb) |>
          tidyr::pivot_wider(id_cols = ticker, names_from = rank_idx,
                             names_prefix = "r", values_from = daily_ret)

        target <- etf_monthly |>
          filter(ym == m, ticker %in% etf_params$etf_tickers) |>
          select(ticker, target_ret = monthly_ret)

        chrono |>
          inner_join(ranked, by = "ticker") |>
          inner_join(target, by = "ticker") |>
          mutate(ym = m)
      })

      bind_rows(Filter(Negate(is.null), features_list))
    }),

    # ── A: Elastic net signal on ETF features ─────────────────────
    targets::tar_target(etf_a_signal, {
      library(dplyr)
      rlang::check_installed("glmnet")

      features <- etf_a_features
      lb <- etf_params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols <- paste0("r", seq_len(lb))
      feat_cols <- intersect(c(chrono_cols, rank_cols), names(features))

      months <- sort(unique(features$ym))
      min_train <- etf_params$min_train_months
      trade_months <- months[(min_train + 1):length(months)]

      predictions <- lapply(trade_months, function(m) {
        m_idx <- which(months == m)
        train <- features |> filter(ym %in% months[1:(m_idx - 1)])
        test <- features |> filter(ym == m)
        if (nrow(test) == 0) return(NULL)

        X_train <- as.matrix(train[, feat_cols])
        y_train <- train$target_ret
        X_test <- as.matrix(test[, feat_cols])

        complete <- complete.cases(X_train, y_train)
        X_train <- X_train[complete, , drop = FALSE]
        y_train <- y_train[complete]
        if (length(y_train) < 30) return(NULL)

        fit <- tryCatch(
          glmnet::cv.glmnet(X_train, y_train, alpha = etf_params$alpha,
                            nfolds = min(5, floor(nrow(X_train) / 3)),
                            type.measure = "mse"),
          error = function(e) NULL
        )
        if (is.null(fit)) return(NULL)

        pred <- as.numeric(predict(fit, X_test, s = "lambda.min"))
        tibble(ticker = test$ticker, ym = m, predicted_ret = pred,
               actual_ret = test$target_ret)
      })

      bind_rows(Filter(Negate(is.null), predictions))
    }),

    # ── A: Portfolio ──────────────────────────────────────────────
    targets::tar_target(etf_a_portfolio, {
      library(dplyr)

      signal <- etf_a_signal |>
        group_by(ym) |>
        mutate(rank = rank(-predicted_ret)) |>
        ungroup()

      months <- sort(unique(signal$ym))
      top_n <- etf_params$top_n
      bot_n <- etf_params$bottom_n
      cost <- etf_params$cost_per_trade * 2 * 2 * 0.8  # turnover * cost * legs * buy/sell
      borrow <- etf_params$borrow_rate_annual / 12

      results <- lapply(months, function(m) {
        s <- signal |> filter(ym == m)
        if (nrow(s) < top_n + bot_n) return(NULL)

        long_ret <- mean(s$actual_ret[s$rank <= top_n])
        short_ret <- mean(s$actual_ret[s$rank > (max(s$rank) - bot_n)])
        # Winsorise
        long_ret <- pmin(pmax(long_ret, -etf_params$max_monthly_ret), etf_params$max_monthly_ret)
        short_ret <- pmin(pmax(short_ret, -etf_params$max_monthly_ret), etf_params$max_monthly_ret)

        tibble(ym = m,
               long_ret = long_ret, short_ret = short_ret,
               port_ret = long_ret - short_ret - cost - borrow,
               long_only_ret = long_ret - cost/2,
               n_etfs = nrow(s))
      })

      bind_rows(Filter(Negate(is.null), results)) |>
        mutate(date = as.Date(paste0(ym, "-15")),
               port_cum = cumprod(1 + port_ret),
               long_cum = cumprod(1 + long_only_ret))
    }),

    # ── A: Metrics ────────────────────────────────────────────────
    targets::tar_target(etf_a_metrics, {
      library(dplyr)
      p <- etf_a_portfolio
      calc_m <- function(df, label) {
        n <- nrow(df); if (n < 6) return(NULL)
        m      <- calc_backtest_metrics(df$port_ret)
        m_long <- calc_backtest_metrics(df$long_only_ret)
        tibble(period = label, months = n,
               cagr = m$cagr,
               long_cagr = m_long$cagr,
               vol = m$vol,
               sharpe = m$sharpe,
               max_dd = m$max_dd)
      }
      bind_rows(
        calc_m(p |> filter(date <= etf_params$is_end), "Training"),
        calc_m(p |> filter(date >= etf_params$test_start, date <= etf_params$test_end), "Testing"),
        calc_m(p |> filter(date >= etf_params$val_start), "Validation"),
        calc_m(p, "Full Period")
      )
    }),

    # ══ APPROACH B: Academic signal → ETF execution ═══════════════

    # ── B: Use factor-level DRIF signal to weight ETFs ────────────
    targets::tar_target(etf_b_portfolio, {
      library(dplyr)

      # Get factor-level DRIF predictions (already computed)
      fac_signals <- drif_signal |>
        filter(factor_name %in% names(ETF_FACTOR_MAP))

      # Map factor predictions to ETFs
      months <- sort(unique(fac_signals$ym))
      # Only months where ETF data exists
      etf_months <- sort(unique(etf_monthly$ym))
      shared_months <- intersect(months, etf_months)

      cost <- etf_params$cost_per_trade * 2 * 2 * 0.8
      borrow <- etf_params$borrow_rate_annual / 12
      top_n <- etf_params$top_n

      results <- lapply(shared_months, function(m) {
        # Factor predictions for this month
        fac_pred <- fac_signals |>
          filter(ym == m) |>
          arrange(desc(predicted_ret))

        if (nrow(fac_pred) < 3) return(NULL)

        # Top factors → their ETFs
        top_factors <- head(fac_pred$factor_name, top_n)
        bot_factors <- tail(fac_pred$factor_name, top_n)

        long_etfs <- unique(unlist(ETF_FACTOR_MAP[top_factors]))
        short_etfs <- unique(unlist(ETF_FACTOR_MAP[bot_factors]))
        # Remove overlap
        short_etfs <- setdiff(short_etfs, long_etfs)

        # Get actual ETF returns for this month
        etf_rets <- etf_monthly |> filter(ym == m)

        long_ret <- mean(etf_rets$monthly_ret[etf_rets$ticker %in% long_etfs], na.rm = TRUE)
        short_ret <- mean(etf_rets$monthly_ret[etf_rets$ticker %in% short_etfs], na.rm = TRUE)

        if (is.nan(long_ret) || is.nan(short_ret)) return(NULL)

        long_ret <- pmin(pmax(long_ret, -etf_params$max_monthly_ret), etf_params$max_monthly_ret)
        short_ret <- pmin(pmax(short_ret, -etf_params$max_monthly_ret), etf_params$max_monthly_ret)

        tibble(ym = m,
               long_ret = long_ret, short_ret = short_ret,
               port_ret = long_ret - short_ret - cost - borrow,
               long_only_ret = long_ret - cost/2,
               n_long = length(long_etfs), n_short = length(short_etfs),
               long_etfs_str = paste(long_etfs, collapse = ","),
               short_etfs_str = paste(short_etfs, collapse = ","))
      })

      bind_rows(Filter(Negate(is.null), results)) |>
        mutate(date = as.Date(paste0(ym, "-15")),
               port_cum = cumprod(1 + port_ret),
               long_cum = cumprod(1 + long_only_ret))
    }),

    # ── B: Metrics ────────────────────────────────────────────────
    targets::tar_target(etf_b_metrics, {
      library(dplyr)
      p <- etf_b_portfolio
      calc_m <- function(df, label) {
        n <- nrow(df); if (n < 6) return(NULL)
        m      <- calc_backtest_metrics(df$port_ret)
        m_long <- calc_backtest_metrics(df$long_only_ret)
        tibble(period = label, months = n,
               cagr = m$cagr,
               long_cagr = m_long$cagr,
               vol = m$vol,
               sharpe = m$sharpe,
               max_dd = m$max_dd)
      }
      bind_rows(
        calc_m(p |> filter(date <= etf_params$is_end), "Training"),
        calc_m(p |> filter(date >= etf_params$test_start, date <= etf_params$test_end), "Testing"),
        calc_m(p |> filter(date >= etf_params$val_start), "Validation"),
        calc_m(p, "Full Period")
      )
    }),

    # ══ Comparison ════════════════════════════════════════════════

    targets::tar_target(etf_comparison_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      a <- etf_a_portfolio |> select(date, `A: DRIF on ETFs` = port_cum)
      b <- etf_b_portfolio |> select(date, `B: Academic → ETFs` = port_cum)

      comp <- inner_join(a, b, by = "date") |>
        tidyr::pivot_longer(-date, names_to = "approach", values_to = "growth")

      ggplot(comp, aes(date, growth, colour = approach)) +
        geom_line(linewidth = 0.6) +
        geom_hline(yintercept = 1, linetype = "dotted", colour = "grey50") +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "ETF Replication: Approach A vs B (net of costs)") +
        scale_y_log10(labels = dollar) +
        hd_theme()
    })
  )
}
