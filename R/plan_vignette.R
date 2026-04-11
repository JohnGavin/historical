# Vignette targets: pre-compute all data and plots for examples.qmd
#
# Every vig_* target produces a data.frame or ggplot object.
# The vignette uses tar_read("vig_*") for zero inline computation.
#
# Run: targets::tar_make(names = starts_with("vig_"))

plan_vignette <- function() {
  list(

    # ── Equity ──────────────────────────────────────────────────────

    targets::tar_target(vig_eq_aapl, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      raw <- hd_ohlcv("AAPL", from = "2023-01-01")
      # Moving averages via cumsum (no zoo/slider needed)
      raw |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          cs = cumsum(close),
          ma_50  = dplyr::if_else(dplyr::row_number() >= 50,
            (cs - dplyr::lag(cs, 50)) / 50, NA_real_),
          ma_200 = dplyr::if_else(dplyr::row_number() >= 200,
            (cs - dplyr::lag(cs, 200)) / 200, NA_real_)
        ) |>
        dplyr::select(-cs)
    }),

    targets::tar_target(vig_eq_aapl_plot, {
      ggplot2::ggplot(vig_eq_aapl, ggplot2::aes(date)) +
        ggplot2::geom_line(ggplot2::aes(y = close), colour = "white", linewidth = 0.4) +
        ggplot2::geom_line(ggplot2::aes(y = ma_50), colour = "#3498db",
                           linewidth = 0.5, linetype = "dashed") +
        ggplot2::geom_line(ggplot2::aes(y = ma_200), colour = "#e74c3c",
                           linewidth = 0.5, linetype = "dashed") +
        ggplot2::scale_y_continuous(labels = scales::dollar) +
        ggplot2::labs(
          x = NULL, y = "Close (USD)",
          title = "AAPL daily close with 50d and 200d moving averages",
          caption = paste0(
            "White = close. Blue dashed = 50d MA. Red dashed = 200d MA. ",
            nrow(vig_eq_aapl), " trading days. Source: Yahoo Finance via hd_ohlcv().")
        )
    }),

    targets::tar_target(vig_eq_faang, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- c("AAPL", "AMZN", "GOOGL", "META", "NFLX")
      dplyr::bind_rows(lapply(tickers, \(t) hd_ohlcv(t, from = "2024-01-01"))) |>
        dplyr::group_by(ticker) |>
        dplyr::mutate(cum_ret = adjusted / dplyr::first(adjusted) - 1) |>
        dplyr::ungroup()
    }),

    targets::tar_target(vig_eq_faang_plot, {
      ggplot2::ggplot(vig_eq_faang, ggplot2::aes(date, cum_ret, colour = ticker)) +
        ggplot2::geom_line(linewidth = 0.5) +
        ggplot2::geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
        ggplot2::scale_y_continuous(labels = scales::percent) +
        ggplot2::labs(
          x = NULL, y = "Cumulative return", colour = NULL,
          title = "FAANG cumulative returns rebased to 2024-01-01",
          caption = paste0(
            "FAANG = Meta (META), Apple (AAPL), Amazon (AMZN), Netflix (NFLX), Alphabet (GOOGL). ",
            "Split-adjusted close. Source: Yahoo Finance via hd_ohlcv().")
        )
    }),

    targets::tar_target(vig_eq_vol, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- c("AAPL", "NVDA", "TSLA", "SPY")
      dplyr::bind_rows(lapply(tickers, \(t) hd_ohlcv(t, from = "2023-06-01"))) |>
        dplyr::group_by(ticker) |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          log_ret = log(adjusted / dplyr::lag(adjusted)),
          cum_sq = cumsum(dplyr::if_else(is.na(log_ret), 0, log_ret^2)),
          vol_21d = sqrt(pmax((cum_sq - dplyr::lag(cum_sq, 21, default = 0)) / 21, 0)) * sqrt(252)
        ) |>
        dplyr::filter(!is.na(vol_21d), date >= as.Date("2024-01-01")) |>
        dplyr::ungroup()
    }),

    targets::tar_target(vig_eq_vol_plot, {
      ggplot2::ggplot(vig_eq_vol, ggplot2::aes(date, vol_21d, colour = ticker)) +
        ggplot2::geom_line(linewidth = 0.4) +
        ggplot2::scale_y_continuous(labels = scales::percent) +
        ggplot2::labs(
          x = NULL, y = "21d annualised volatility", colour = NULL,
          title = "Realised volatility: AAPL, NVDA, TSLA vs SPY benchmark",
          caption = "21-day rolling SD of log returns x sqrt(252). SPY = S&P 500 ETF. Source: hd_ohlcv()."
        )
    }),

    targets::tar_target(vig_eq_coverage, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- hd_tickers("equity_daily")
      dplyr::bind_rows(lapply(tickers, \(t) {
        d <- hd_ohlcv(t, from = "1900-01-01")
        dplyr::tibble(
          Ticker = t,
          `Trading Days` = nrow(d),
          From = as.character(min(d$date)),
          To = as.character(max(d$date))
        )
      })) |>
        dplyr::arrange(dplyr::desc(`Trading Days`))
    }),

    # ── Crypto ──────────────────────────────────────────────────────

    targets::tar_target(vig_cr_major, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- c("BTC", "ETH", "SOL", "BNB")
      dplyr::bind_rows(lapply(tickers, \(t) hd_ohlcv(t, from = "2022-01-01")))
    }),

    targets::tar_target(vig_cr_major_plot, {
      ggplot2::ggplot(vig_cr_major, ggplot2::aes(date, close, colour = ticker)) +
        ggplot2::geom_line(linewidth = 0.4) +
        ggplot2::scale_y_log10(labels = scales::dollar) +
        ggplot2::labs(
          x = NULL, y = "Close USD (log scale)", colour = NULL,
          title = "BTC, ETH, SOL, BNB daily close prices",
          caption = paste0(
            "Log scale: equal vertical distances = equal % changes. ",
            nrow(vig_cr_major), " total observations. Source: Yahoo Finance via hd_ohlcv().")
        )
    }),

    targets::tar_target(vig_cr_stable, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      dplyr::bind_rows(
        hd_ohlcv("USDC", from = "2022-01-01"),
        hd_ohlcv("USDT", from = "2022-01-01")
      )
    }),

    targets::tar_target(vig_cr_stable_plot, {
      ggplot2::ggplot(vig_cr_stable, ggplot2::aes(date, close, colour = ticker)) +
        ggplot2::geom_line(linewidth = 0.4) +
        ggplot2::geom_hline(yintercept = 1.0, linetype = "dashed", colour = "grey50") +
        ggplot2::scale_y_continuous(limits = c(0.97, 1.03)) +
        ggplot2::labs(
          x = NULL, y = "USD price", colour = NULL,
          title = "Stablecoin peg: USDC and USDT deviation from $1.00",
          caption = "Dashed line = $1.00 peg. Y-axis zoomed to $0.97-$1.03. Source: hd_ohlcv()."
        )
    }),

    targets::tar_target(vig_cr_corr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- c("BTC", "ETH", "SOL", "BNB", "ADA", "XRP")
      wide <- dplyr::bind_rows(lapply(tickers, \(t) hd_ohlcv(t, from = "2023-01-01"))) |>
        dplyr::group_by(ticker) |>
        dplyr::arrange(date) |>
        dplyr::mutate(ret = log(close / dplyr::lag(close))) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::ungroup() |>
        dplyr::select(date, ticker, ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = ret) |>
        dplyr::filter(dplyr::if_all(dplyr::everything(), ~ !is.na(.)))

      cor_mat <- cor(wide |> dplyr::select(-date), use = "complete.obs")
      cor_mat |>
        as.data.frame() |>
        dplyr::mutate(row = rownames(cor_mat)) |>
        tidyr::pivot_longer(-row, names_to = "col", values_to = "cor")
    }),

    targets::tar_target(vig_cr_corr_plot, {
      ggplot2::ggplot(vig_cr_corr, ggplot2::aes(row, col, fill = cor)) +
        ggplot2::geom_tile() +
        ggplot2::geom_text(ggplot2::aes(label = round(cor, 2)), colour = "white", size = 3.5) +
        ggplot2::scale_fill_gradient2(
          low = "#3498db", mid = "grey20", high = "#e74c3c",
          midpoint = 0.5, limits = c(0, 1)) +
        ggplot2::labs(
          x = NULL, y = NULL, fill = "Corr",
          title = "Crypto log-return correlation matrix (2023+)",
          caption = "Daily log returns. All pairs >0.5 = limited diversification benefit. Source: hd_ohlcv()."
        ) +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    }),

    targets::tar_target(vig_cr_coverage, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      tickers <- hd_tickers("crypto_daily")
      dplyr::bind_rows(lapply(tickers, \(t) {
        d <- hd_ohlcv(t, from = "2010-01-01")
        dplyr::tibble(Token = t, Days = nrow(d),
          From = as.character(min(d$date)), To = as.character(max(d$date)))
      })) |> dplyr::arrange(dplyr::desc(Days))
    }),

    # ── Macro ───────────────────────────────────────────────────────

    targets::tar_target(vig_ma_rates, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      dplyr::bind_rows(lapply(
        c("DGS2", "DGS10", "DGS30", "DFF"),
        \(s) hd_macro(s, from = "2020-01-01")
      )) |> dplyr::filter(!is.na(value))
    }),

    targets::tar_target(vig_ma_rates_plot, {
      ggplot2::ggplot(vig_ma_rates, ggplot2::aes(date, value, colour = series_id)) +
        ggplot2::geom_line(linewidth = 0.4) +
        ggplot2::labs(
          x = NULL, y = "Yield (%)", colour = NULL,
          title = "US Treasury yields and Fed Funds rate (2020+)",
          caption = "DGS2/10/30 = constant-maturity yields. DFF = effective Fed Funds rate. Source: FRED via hd_macro()."
        )
    }),

    targets::tar_target(vig_ma_yieldcurve, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_macro("T10Y2Y", from = "2018-01-01") |> dplyr::filter(!is.na(value))
    }),

    targets::tar_target(vig_ma_yc_plot, {
      inv_dates <- vig_ma_yieldcurve |> dplyr::filter(value < 0)
      inv_start <- min(inv_dates$date)
      inv_end <- max(inv_dates$date)

      ggplot2::ggplot(vig_ma_yieldcurve, ggplot2::aes(date, value)) +
        ggplot2::geom_line(linewidth = 0.4, colour = "#e74c3c") +
        ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
        ggplot2::annotate("rect", xmin = inv_start, xmax = inv_end,
          ymin = -Inf, ymax = 0, fill = "#e74c3c", alpha = 0.15) +
        ggplot2::labs(
          x = NULL, y = "10Y - 2Y spread (%)",
          title = "Yield curve: 10Y-2Y spread with inversion shading",
          caption = paste0("Red shading = inverted (", inv_start, " to ", inv_end,
            "). Inversion historically precedes recessions by 6-18 months. Source: FRED T10Y2Y via hd_macro().")
        )
    }),

    targets::tar_target(vig_ma_spreads, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      dplyr::bind_rows(
        hd_macro("BAMLH0A0HYM2", from = "2020-01-01"),
        hd_macro("BAMLC0A4CBBB", from = "2020-01-01")
      ) |>
        dplyr::filter(!is.na(value)) |>
        dplyr::mutate(series_id = dplyr::recode(series_id,
          BAMLH0A0HYM2 = "HY Spread", BAMLC0A4CBBB = "BBB Spread"))
    }),

    targets::tar_target(vig_ma_spreads_plot, {
      ggplot2::ggplot(vig_ma_spreads, ggplot2::aes(date, value, colour = series_id)) +
        ggplot2::geom_line(linewidth = 0.4) +
        ggplot2::labs(
          x = NULL, y = "OAS (percentage points)", colour = NULL,
          title = "ICE BofA credit spreads: High Yield vs BBB (2020+)",
          caption = "Option-adjusted spread over Treasuries. Wider = more default risk. Source: FRED via hd_macro()."
        )
    }),

    targets::tar_target(vig_ma_coverage, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      series <- hd_macro_series()
      dplyr::bind_rows(lapply(series, \(s) {
        d <- hd_macro(s)
        dplyr::tibble(Series = s, Obs = nrow(d),
          From = as.character(min(d$date)), To = as.character(max(d$date)))
      })) |> dplyr::arrange(Series)
    }),

    # ── Factors ─────────────────────────────────────────────────────

    targets::tar_target(vig_fa_ff3, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factors("FF3", "daily", from = "2020-01-01")
    }),

    targets::tar_target(vig_fa_ff3_plot, {
      ggplot2::ggplot(vig_fa_ff3, ggplot2::aes(date, value, colour = factor_name)) +
        ggplot2::geom_line(alpha = 0.6, linewidth = 0.3) +
        ggplot2::geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.2) +
        ggplot2::facet_wrap(~factor_name, ncol = 1, scales = "free_y") +
        ggplot2::labs(
          x = NULL, y = "Return (%)",
          title = "Fama-French 3 factors: daily returns (2020+)",
          caption = "Mkt-RF = market excess return. SMB = small minus big. HML = high minus low B/M. RF = risk-free rate. Source: Ken French via hd_factors()."
        ) +
        ggplot2::theme(legend.position = "none")
    }),

    targets::tar_target(vig_fa_ff5_cum, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factors("FF5", "daily", from = "2000-01-01") |>
        dplyr::filter(factor_name != "RF") |>
        dplyr::group_by(factor_name) |>
        dplyr::arrange(date) |>
        dplyr::mutate(cum_ret = cumprod(1 + value / 100) - 1) |>
        dplyr::ungroup()
    }),

    targets::tar_target(vig_fa_ff5_plot, {
      ggplot2::ggplot(vig_fa_ff5_cum, ggplot2::aes(date, cum_ret, colour = factor_name)) +
        ggplot2::geom_line(linewidth = 0.5) +
        ggplot2::geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
        ggplot2::scale_y_continuous(labels = scales::percent) +
        ggplot2::labs(
          x = NULL, y = "Cumulative return", colour = NULL,
          title = "FF5 cumulative factor returns (2000-2026)",
          caption = "Mkt-RF dominates. HML (value) struggled post-2010. RMW = profitability. CMA = investment. Source: Ken French via hd_factors()."
        )
    }),

    targets::tar_target(vig_fa_mom, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factors("Mom", "daily", from = "2000-01-01") |>
        dplyr::arrange(date) |>
        dplyr::mutate(cum_ret = cumprod(1 + value / 100) - 1)
    }),

    targets::tar_target(vig_fa_mom_plot, {
      ggplot2::ggplot(vig_fa_mom, ggplot2::aes(date, cum_ret)) +
        ggplot2::geom_line(linewidth = 0.5, colour = "#2ecc71") +
        ggplot2::geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
        ggplot2::scale_y_continuous(labels = scales::percent) +
        ggplot2::labs(
          x = NULL, y = "Cumulative return",
          title = "Momentum factor cumulative return (2000-2026)",
          caption = "WML = Winners Minus Losers. Note 2009 crash (momentum reversal) and post-2020 recovery. Source: Ken French via hd_factors()."
        )
    }),

    targets::tar_target(vig_fa_coverage, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      con <- hd_connect()
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
      ds <- hd_datasets()[["factors"]]
      DBI::dbGetQuery(con, sprintf(
        "SELECT dataset AS Dataset, frequency AS Freq, factor_name AS Factor,
                COUNT(*) AS Obs, MIN(date) AS From, MAX(date) AS To
         FROM read_parquet('%s')
         GROUP BY dataset, frequency, factor_name
         ORDER BY dataset, frequency, factor_name", ds$url
      )) |> dplyr::as_tibble()
    })
  )
}
