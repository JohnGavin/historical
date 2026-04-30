# Plan: VIX Regime Overlay on Macro Strategies (#59)
#
# VIX overlay failed on SPY (R²=41%, no alpha). Test on macro assets:
# TLT (bonds), GLD (gold), DBC (commodities), UUP (USD).
# Hypothesis: VIX may be a better timing signal for non-equity assets
# because the correlation structure differs.

plan_vix_macro_overlay <- function() {
  list(

    targets::tar_target(vmo_params, {
      list(
        tickers = c("TLT", "GLD", "DBC", "UUP"),
        ticker_labels = c(
          TLT = "20+ Year Treasury Bonds",
          GLD = "Gold",
          DBC = "Commodities Broad",
          UUP = "US Dollar"
        ),
        vix_high = 25,
        vix_reentry = 20,
        min_cooloff = 3L
      )
    }),

    targets::tar_target(vmo_daily, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # VIX
      vix <- hd_macro("VIXCLS") |>
        mutate(date = as.Date(date)) |>
        select(date, vix = value)

      # Asset returns
      purrr::map_dfr(vmo_params$tickers, function(tkr) {
        tryCatch({
          hd_ohlcv(tkr) |>
            mutate(date = as.Date(date)) |>
            arrange(date) |>
            mutate(ret = adjusted / lag(adjusted) - 1, ticker = tkr) |>
            filter(!is.na(ret)) |>
            select(date, ticker, ret) |>
            left_join(vix, by = "date")
        }, error = function(e) NULL)
      })
    }),

    targets::tar_target(vmo_results, {
      library(dplyr)

      run_overlay <- function(d, vix_high, vix_reentry, min_cooloff) {
        n <- nrow(d)
        in_market <- rep(TRUE, n)
        cooloff <- 0L

        for (i in 2:n) {
          if (cooloff > 0) cooloff <- cooloff - 1L

          # t+1 execution: use PREVIOUS day's VIX
          vix_prev <- d$vix[i - 1]

          if (!is.na(vix_prev) && vix_prev > vix_high) {
            in_market[i] <- FALSE
            cooloff <- max(cooloff, min_cooloff)
          } else if (cooloff > 0) {
            in_market[i] <- FALSE
          } else if (!is.na(vix_prev) && vix_prev > vix_reentry) {
            in_market[i] <- FALSE
          }
        }

        strat_ret <- ifelse(in_market, d$ret, 0)
        list(ret_bh = d$ret, ret_overlay = strat_ret, in_market = in_market)
      }

      purrr::map_dfr(vmo_params$tickers, function(tkr) {
        d <- vmo_daily |>
          filter(ticker == tkr, !is.na(vix)) |>
          arrange(date)

        if (nrow(d) < 100) return(NULL)

        res <- run_overlay(d, vmo_params$vix_high, vmo_params$vix_reentry,
                            vmo_params$min_cooloff)

        n <- length(res$ret_bh)
        years <- n / 252

        calc_metrics <- function(ret, label) {
          ret <- ret[!is.na(ret)]
          if (length(ret) < 20) return(NULL)
          tibble(
            ticker = tkr,
            asset = vmo_params$ticker_labels[tkr],
            strategy = label,
            cagr_pct = round((prod(1 + ret)^(252/length(ret)) - 1) * 100, 1),
            vol_pct = round(sd(ret) * sqrt(252) * 100, 1),
            sharpe = round(mean(ret) / sd(ret) * sqrt(252), 2),
            max_dd_pct = round(min((cumprod(1 + ret) - cummax(cumprod(1 + ret))) /
                                     cummax(cumprod(1 + ret))) * 100, 1),
            pct_in_market = round(mean(res$in_market) * 100, 1)
          )
        }

        bind_rows(
          calc_metrics(res$ret_bh, "Buy & Hold"),
          calc_metrics(res$ret_overlay, "VIX Overlay")
        )
      })
    }),

    targets::tar_target(vmo_caption, {
      library(dplyr)
      r <- vmo_results

      # Which assets benefit from overlay?
      comparison <- r |>
        select(ticker, asset, strategy, sharpe) |>
        tidyr::pivot_wider(names_from = strategy, values_from = sharpe) |>
        mutate(benefit = `VIX Overlay` - `Buy & Hold`)

      winners <- comparison |> filter(benefit > 0.05)
      losers <- comparison |> filter(benefit < -0.05)

      paste0(
        "VIX overlay (exit at VIX > ", vmo_params$vix_high,
        ", re-enter at VIX < ", vmo_params$vix_reentry,
        ") on 4 macro assets. t+1 execution enforced. ",
        if (nrow(winners) > 0) paste0(
          "Improves: ", paste(winners$asset, collapse = ", "), ". "
        ) else "No asset benefits from the overlay. ",
        if (nrow(losers) > 0) paste0(
          "Hurts: ", paste(losers$asset, collapse = ", "), ". "
        ) else "",
        "VIX is a concurrent, not leading, indicator — ",
        "by the time VIX > 25, the move has already happened."
      )
    })

  )
}
