# Plan: Real vs Simulated Time Series Quiz (#70)
#
# Uses REAL market data (SPY, QQQ, IWM, TLT, GLD, individual stocks)
# vs simulated null environments. NOT strategy returns.

plan_quiz <- function() {
  list(

    targets::tar_target(quiz_params, {
      list(
        n_per_difficulty = 5L,
        T_obs            = 100L,
        seed             = 123L
      )
    }),

    targets::tar_target(quiz_rounds, {
      library(dplyr)
      set.seed(quiz_params$seed)

      T_obs <- quiz_params$T_obs
      n_per <- quiz_params$n_per_difficulty
      gh <- "https://johngavin.github.io/historical"

      # ── Real market data: ETFs and stocks ────���─────────────────
      tickers <- c("SPY", "QQQ", "IWM", "TLT", "GLD",
                    "AAPL", "MSFT", "JPM", "XOM", "JNJ")
      ticker_labels <- c(
        SPY = "S&P 500 ETF", QQQ = "Nasdaq 100 ETF",
        IWM = "Russell 2000 ETF", TLT = "20+ Year Treasury Bond ETF",
        GLD = "Gold ETF", AAPL = "Apple Inc.", MSFT = "Microsoft Corp.",
        JPM = "JPMorgan Chase", XOM = "ExxonMobil", JNJ = "Johnson & Johnson"
      )
      ticker_urls <- paste0(
        "https://finance.yahoo.com/quote/", tickers, "/chart/"
      )
      names(ticker_urls) <- tickers

      # Fetch daily returns for each ticker
      all_data <- lapply(tickers, function(tkr) {
        tryCatch({
          d <- hd_ohlcv(tkr) |>
            dplyr::arrange(date) |>
            dplyr::mutate(ret = adjusted / dplyr::lag(adjusted) - 1) |>
            dplyr::filter(!is.na(ret))
          d |> dplyr::select(date, ret)
        }, error = function(e) NULL)
      })
      names(all_data) <- tickers
      all_data <- Filter(Negate(is.null), all_data)

      # Helper: sample T_obs contiguous returns with dates
      sample_real <- function(df, T_obs) {
        if (nrow(df) <= T_obs) return(list(ret = df$ret, dates = df$date))
        start <- sample.int(nrow(df) - T_obs, 1L)
        idx <- start:(start + T_obs - 1L)
        list(ret = df$ret[idx], dates = df$date[idx])
      }

      # Helper: build one round
      make_round <- function(round_id, ticker, difficulty, null_env_label,
                              sim_ret, real_sample) {
        real_ret <- real_sample$ret
        dates <- real_sample$dates
        date_range <- paste0(format(min(dates), "%b %Y"), " to ",
                              format(max(dates), "%b %Y"))
        if (sd(sim_ret) > 0 && sd(real_ret) > 0) {
          sim_ret <- sim_ret * (sd(real_ret) / sd(sim_ret))
        }

        real_first <- sample(c(TRUE, FALSE), 1L)

        list(
          id          = round_id,
          difficulty  = difficulty,
          real_name   = paste0(ticker, " (", ticker_labels[ticker], ")"),
          real_url    = ticker_urls[ticker],
          null_env    = null_env_label,
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          dates_from  = format(min(dates), "%Y-%m-%d"),
          dates_to    = format(max(dates), "%Y-%m-%d"),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(ticker, " daily returns (", date_range, ")"),
          sim_source  = null_env_label
        )
      }

      available_tickers <- names(all_data)
      rounds <- list()
      round_id <- 0L

      # ── Easy: White Noise ──────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        tkr <- available_tickers[((i - 1L) %% length(available_tickers)) + 1L]
        real_s <- sample_real(all_data[[tkr]], T_obs)
        sim_list <- hd_null_env_white_noise(length(real_s$ret), M = 1L,
                                             seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, tkr, "easy", "White Noise (iid Gaussian)",
          sim_list[[1]], real_s
        )
      }

      # ── Medium: GARCH(1,1) ─────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        tkr <- available_tickers[((i + 4L) %% length(available_tickers)) + 1L]
        real_s <- sample_real(all_data[[tkr]], T_obs)
        sim_list <- hd_null_env_garch11(length(real_s$ret), M = 1L,
                                         seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, tkr, "medium", "GARCH(1,1) volatility clustering",
          sim_list[[1]], real_s
        )
      }

      # ── Hard: GJR-GARCH ────────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        tkr <- available_tickers[((i + 2L) %% length(available_tickers)) + 1L]
        real_s <- sample_real(all_data[[tkr]], T_obs)
        sim_list <- hd_null_env_gjr_garch(length(real_s$ret), M = 1L,
                                            seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, tkr, "hard", "GJR-GARCH (asymmetric leverage)",
          sim_list[[1]], real_s
        )
      }

      # ── Pseudo: time-reversed real data ─────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        tkr <- available_tickers[((i + 7L) %% length(available_tickers)) + 1L]
        real_s <- sample_real(all_data[[tkr]], T_obs)
        rounds[[round_id]] <- make_round(
          round_id, tkr, "pseudo",
          paste0("Time-reversed ", tkr),
          rev(real_s$ret), real_s
        )
      }

      rounds[sample(length(rounds))]
    }),

    targets::tar_target(quiz_json, {
      jsonlite::toJSON(quiz_rounds, auto_unbox = TRUE, digits = 6)
    })

  )
}
