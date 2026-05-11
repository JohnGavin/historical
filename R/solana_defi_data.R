# Solana DeFi Data Pipeline
#
# Fetches spot and perp data from Solana DeFi protocols
# Target frequency: 4-hourly for signal generation, daily for backtesting
#
# Data sources:
# - Birdeye API: Spot prices (all SPL tokens)
# - Drift Protocol: Perp prices + funding rates
# - Pyth Network: Oracle prices (cross-asset reference)

#' Fetch Solana token spot prices from Birdeye
#'
#' @param tokens Character vector of token symbols (e.g., "SOL", "RAY", "BONK")
#' @param start_date Date, start of historical period
#' @param end_date Date, end of historical period
#' @param interval Character, "1D" (daily), "4H", "1H", "15m"
#' @param api_key Character, Birdeye API key (free tier: 100/day, paid: unlimited)
#'
#' @return tibble with columns: ticker, timestamp, open, high, low, close, volume
#'
#' @details
#' Birdeye aggregates prices across all Solana DEXs (Orca, Raydium, Jupiter).
#' Free tier sufficient for daily/4H backtests. Paid tier needed for minute-level.
#'
#' Token mint addresses (required for API):
#' - SOL: So11111111111111111111111111111111111111112
#' - RAY: 4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R
#' - BONK: DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263
#' - JUP: JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN
#' - PYTH: HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3
#'
fetch_birdeye_spot <- function(tokens, start_date, end_date,
                               interval = c("1D", "4H", "1H", "15m"),
                               api_key = Sys.getenv("BIRDEYE_API_KEY")) {

  interval <- match.arg(interval)

  # Token mint address mapping (expand as needed)
  mint_map <- c(
    "SOL" = "So11111111111111111111111111111111111111112",
    "RAY" = "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
    "BONK" = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "JUP" = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
    "PYTH" = "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3",
    "ORCA" = "orcaEKTdK7LKz57vaAYr9QeNsVEPfiu6QeMU1kektZE",
    "JTO" = "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL",
    "HNT" = "hntyVP6YFm1Hg25TN9WGLqM12b8TQmcknKrdu1oxWux"
  )

  start_unix <- as.numeric(as.POSIXct(start_date))
  end_unix <- as.numeric(as.POSIXct(end_date))

  results <- purrr::map_dfr(tokens, function(token) {
    mint <- mint_map[[token]]
    if (is.null(mint)) {
      cli::cli_warn("Unknown token {token}, skipping")
      return(NULL)
    }

    url <- sprintf(
      "https://public-api.birdeye.so/defi/ohlcv?address=%s&type=%s&time_from=%d&time_to=%d",
      mint, interval, start_unix, end_unix
    )

    resp <- httr2::request(url) |>
      httr2::req_headers("X-API-KEY" = api_key) |>
      httr2::req_perform() |>
      httr2::resp_body_json()

    if (!is.null(resp$data$items)) {
      tibble::tibble(
        ticker = token,
        timestamp = as.POSIXct(purrr::map_dbl(resp$data$items, "unixTime"), origin = "1970-01-01"),
        open = purrr::map_dbl(resp$data$items, "o"),
        high = purrr::map_dbl(resp$data$items, "h"),
        low = purrr::map_dbl(resp$data$items, "l"),
        close = purrr::map_dbl(resp$data$items, "c"),
        volume = purrr::map_dbl(resp$data$items, "v")
      )
    } else {
      cli::cli_warn("No data for {token}")
      NULL
    }
  })

  results
}

#' Fetch Drift Protocol perpetual prices and funding rates
#'
#' @param markets Character vector of Drift market symbols (e.g., "SOL-PERP", "BTC-PERP")
#' @param start_date Date, start of historical period
#' @param end_date Date, end of historical period
#'
#' @return tibble with columns: market, timestamp, mark_price, funding_rate, open_interest
#'
#' @details
#' Drift Protocol S3 bucket: drift-historical-data-v2.s3.eu-west-1.amazonaws.com
#'
#' Market IDs (as of 2024):
#' - 0: SOL-PERP
#' - 1: BTC-PERP
#' - 2: ETH-PERP
#' - 16: BONK-PERP
#' - 18: JUP-PERP
#' - 24: PYTH-PERP
#'
#' Funding rates: Updated hourly, stored as CSV per month
#'
fetch_drift_perps <- function(markets, start_date, end_date) {

  # Market ID mapping (expand from Drift docs)
  market_ids <- c(
    "SOL-PERP" = 0,
    "BTC-PERP" = 1,
    "ETH-PERP" = 2,
    "BONK-PERP" = 16,
    "JUP-PERP" = 18,
    "PYTH-PERP" = 24,
    "RAY-PERP" = 20  # Example, verify from Drift
  )

  # Generate month sequence for data fetch
  months <- seq(
    lubridate::floor_date(start_date, "month"),
    lubridate::floor_date(end_date, "month"),
    by = "month"
  )

  results <- purrr::map_dfr(markets, function(market) {
    market_id <- market_ids[[market]]
    if (is.null(market_id)) {
      cli::cli_warn("Unknown Drift market {market}, skipping")
      return(NULL)
    }

    purrr::map_dfr(months, function(month) {
      month_str <- format(month, "%Y-%m")

      # Funding rate CSV
      url <- sprintf(
        "https://drift-historical-data-v2.s3.eu-west-1.amazonaws.com/program/dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH/market/%d/fundingRate/fundingRate-%d-%s.csv",
        market_id, market_id, month_str
      )

      tryCatch({
        df <- readr::read_csv(url, show_col_types = FALSE) |>
          dplyr::mutate(
            market = market,
            timestamp = as.POSIXct(ts / 1000, origin = "1970-01-01")  # Drift uses ms
          ) |>
          dplyr::select(market, timestamp, funding_rate = fundingRateLong,
                       mark_price = markPriceBefore, open_interest = baseAssetAmountWithAmm)

        df
      }, error = function(e) {
        cli::cli_warn("Failed to fetch {market} for {month_str}: {e$message}")
        NULL
      })
    })
  })

  results |>
    dplyr::filter(timestamp >= start_date, timestamp <= end_date)
}

#' Calculate liquidity metrics for Solana tokens
#'
#' @param spot_data tibble from fetch_birdeye_spot()
#' @param perp_data tibble from fetch_drift_perps()
#' @param min_daily_volume Numeric, minimum daily volume (USD) for liquidity filter
#'
#' @return tibble with columns: ticker, avg_daily_volume_spot, avg_daily_volume_perp,
#'   liquidity_ratio (perp/spot), is_liquid
#'
#' @details
#' Liquidity criteria:
#' - Min daily volume: $1M spot, $1M perp
#' - Liquidity ratio: perp volume should be 50-200% of spot (similar liquidity)
#' - Max spread: <0.5% (spot-perp basis)
#'
calculate_liquidity_metrics <- function(spot_data, perp_data,
                                       min_daily_volume = 1e6) {

  spot_liquidity <- spot_data |>
    dplyr::group_by(ticker) |>
    dplyr::summarise(
      avg_daily_volume_spot = mean(volume * close, na.rm = TRUE),
      .groups = "drop"
    )

  perp_liquidity <- perp_data |>
    dplyr::mutate(ticker = sub("-PERP", "", market)) |>
    dplyr::group_by(ticker) |>
    dplyr::summarise(
      avg_daily_volume_perp = mean(open_interest * mark_price, na.rm = TRUE),
      .groups = "drop"
    )

  spot_liquidity |>
    dplyr::left_join(perp_liquidity, by = "ticker") |>
    dplyr::mutate(
      avg_daily_volume_perp = tidyr::replace_na(avg_daily_volume_perp, 0),
      liquidity_ratio = avg_daily_volume_perp / avg_daily_volume_spot,
      is_liquid = avg_daily_volume_spot >= min_daily_volume &
                  avg_daily_volume_perp >= min_daily_volume &
                  liquidity_ratio >= 0.5 &
                  liquidity_ratio <= 2.0
    )
}

#' Build momentum signals with configurable parameters
#'
#' @param returns tibble with columns: ticker, date, return
#' @param btc_returns tibble with columns: date, btc_return
#' @param lookback_days Numeric, momentum lookback period (default 252 = 12 months)
#' @param beta_window Numeric, rolling window for BTC beta estimation (default 252)
#' @param vol_adjust Logical, whether to use volatility-adjusted position sizing
#' @param leverage Numeric, leverage multiplier (default 1.0 = unleveraged)
#'
#' @return tibble with columns: ticker, date, baseline_mom, btc_adj_mom, residual_mom,
#'   btc_beta, position_size
#'
build_momentum_signals <- function(returns, btc_returns,
                                  lookback_days = 252,
                                  beta_window = 252,
                                  vol_adjust = TRUE,
                                  leverage = 1.0) {

  # Join returns with BTC
  data <- returns |>
    dplyr::left_join(btc_returns, by = "date")

  # Calculate rolling moments
  signals <- data |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      # Baseline momentum (trailing return)
      baseline_mom = RcppRoll::roll_sum(return, n = lookback_days, fill = NA, align = "right"),

      # BTC momentum
      btc_mom = RcppRoll::roll_sum(btc_return, n = lookback_days, fill = NA, align = "right"),

      # Rolling BTC beta
      cov_crypto_btc = RcppRoll::roll_cov(return, btc_return, n = beta_window, fill = NA, align = "right"),
      var_btc = RcppRoll::roll_var(btc_return, n = beta_window, fill = NA, align = "right"),
      btc_beta = cov_crypto_btc / var_btc,

      # BTC-adjusted momentum
      btc_adj_mom = baseline_mom - (btc_beta * btc_mom),

      # Residual-only momentum (regress out BTC)
      residual = return - (btc_beta * btc_return),
      residual_mom = RcppRoll::roll_sum(residual, n = lookback_days, fill = NA, align = "right"),

      # Volatility (for position sizing)
      vol_252 = RcppRoll::roll_sd(return, n = 252, fill = NA, align = "right")
    ) |>
    dplyr::ungroup()

  # Position sizing
  if (vol_adjust) {
    signals <- signals |>
      dplyr::group_by(date) |>
      dplyr::mutate(
        # Inverse volatility weighting
        inv_vol = 1 / vol_252,
        inv_vol_sum = sum(inv_vol, na.rm = TRUE),
        position_size = (inv_vol / inv_vol_sum) * leverage
      ) |>
      dplyr::ungroup() |>
      dplyr::select(-inv_vol, -inv_vol_sum)
  } else {
    signals <- signals |>
      dplyr::mutate(position_size = leverage / dplyr::n_distinct(ticker))
  }

  signals |>
    dplyr::select(ticker, date, baseline_mom, btc_adj_mom, residual_mom,
                 btc_beta, vol_252, position_size)
}
