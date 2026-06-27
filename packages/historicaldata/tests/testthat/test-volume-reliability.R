# Tests for hd_unreliable_volume_ticker() and the volume-nulling logic in
# hd_ohlcv_single(). These run fully offline — no parquet files needed.
#
# Issue #21: yfinance reports incorrect volume for non-US exchanges.
# Issue #489: qa_volume_sanity was false-flagging 111 LSE tickers + 1 SW + 3 US
#             mega-caps (SPY/QQQ/TSLA). This test suite validates the fix.

# ── hd_unreliable_volume_ticker ───────────────────────────────────────────────

test_that("hd_unreliable_volume_ticker: US tickers return FALSE", {
  us_tickers <- c("AAPL", "MSFT", "SPY", "QQQ", "TSLA", "NVDA", "BTC", "ETH")
  result <- hd_unreliable_volume_ticker(us_tickers)
  expect_type(result, "logical")
  expect_length(result, length(us_tickers))
  expect_true(all(!result))
})

test_that("hd_unreliable_volume_ticker: each non-US suffix returns TRUE", {
  # One representative ticker per documented suffix
  non_us <- c(
    "ISF.L",      # London
    "SAP.DE",     # XETRA
    "AIR.PA",     # Euronext Paris
    "ASML.AS",    # Euronext Amsterdam
    "NESN.SW",    # SIX Swiss
    "SAN.MC",     # BME Madrid
    "ISP.MI",     # Borsa Italiana
    "VOLV-B.ST",  # Nasdaq Stockholm
    "GN.CO"       # Nasdaq Copenhagen
  )
  result <- hd_unreliable_volume_ticker(non_us)
  expect_type(result, "logical")
  expect_length(result, length(non_us))
  expect_true(all(result), info = paste("Should all be TRUE; got FALSE for:", paste(non_us[!result], collapse = ", ")))
})

test_that("hd_unreliable_volume_ticker: mixed vector returns correct logical mask", {
  tickers <- c("AAPL", "ISF.L", "SAP.DE", "SPY", "NESN.SW", "BTC", "GN.CO")
  expected <- c(FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE)
  result <- hd_unreliable_volume_ticker(tickers)
  expect_equal(result, expected)
})

test_that("hd_unreliable_volume_ticker: vectorised over length-1 inputs", {
  expect_false(hd_unreliable_volume_ticker("AAPL"))
  expect_true(hd_unreliable_volume_ticker("ISF.L"))
})

test_that("hd_unreliable_volume_ticker: empty vector returns logical(0)", {
  result <- hd_unreliable_volume_ticker(character(0))
  expect_type(result, "logical")
  expect_length(result, 0L)
})

test_that("hd_unreliable_volume_ticker: function signature is stable", {
  expect_snapshot(args(hd_unreliable_volume_ticker))
})

# ── Volume-nulling logic (synthetic frame) ────────────────────────────────────
# Mirrors what hd_ohlcv_single() does after collect().

test_that("volume nulling sets non-US volume to NA, preserves US volume", {
  # Synthetic frame with one US and one non-US ticker
  df <- tibble::tibble(
    ticker = c("AAPL", "AAPL", "ISF.L", "ISF.L"),
    date   = as.Date(c("2024-01-02", "2024-01-03", "2024-01-02", "2024-01-03")),
    close  = c(185.0, 186.0, 10.5, 10.6),
    volume = c(50e6,  55e6,  1e9,  1.1e9)
  )

  # Apply the same logic as hd_ohlcv_single (collect = TRUE branch)
  result <- dplyr::mutate(
    df,
    volume = dplyr::if_else(
      hd_unreliable_volume_ticker(ticker),
      NA_real_,
      as.numeric(volume)
    )
  )

  us_rows  <- result[result$ticker == "AAPL", ]
  non_us_rows <- result[result$ticker == "ISF.L", ]

  expect_true(all(!is.na(us_rows$volume)),     info = "US volume should be preserved")
  expect_true(all(is.na(non_us_rows$volume)),  info = "non-US volume should be NA after nulling")
  expect_equal(us_rows$volume, c(50e6, 55e6))  # unchanged
})

test_that("volume nulling does not affect price columns (close, open, high, low)", {
  df <- tibble::tibble(
    ticker = c("ISF.L", "ISF.L"),
    date   = as.Date(c("2024-01-02", "2024-01-03")),
    open   = c(10.4, 10.5),
    high   = c(10.6, 10.7),
    low    = c(10.3, 10.4),
    close  = c(10.5, 10.6),
    volume = c(1e9,  1.1e9)
  )

  result <- dplyr::mutate(
    df,
    volume = dplyr::if_else(hd_unreliable_volume_ticker(ticker), NA_real_, as.numeric(volume))
  )

  # Price columns unchanged
  expect_equal(result$open,  df$open)
  expect_equal(result$high,  df$high)
  expect_equal(result$low,   df$low)
  expect_equal(result$close, df$close)
  # Volume nulled
  expect_true(all(is.na(result$volume)))
})

# ── qa_volume_sanity recalibration logic ─────────────────────────────────────
# Test the updated flagging logic (ratio > 50 only, no absolute threshold).
# Uses a synthetic summary table that mimics what qa_volume_sanity produces
# after DuckDB summarisation + non-US nulling + filter(!is.na(avg_dollar_vol)).

test_that("recalibrated flag: SPY-like US mega-cap (high absolute, low ratio) does NOT flag", {
  # SPY: ~$17B/day; US median across 50 large caps ~$2B → ratio ~8.5x
  # Should NOT be flagged by ratio > 50
  ticker_stats <- tibble::tibble(
    ticker        = c("SPY", "AAPL", "MSFT", "NVDA", "META",
                      "WMT", "KO",   "PEP",  "DIS",  "T"),
    avg_dollar_vol = c(17e9, 8e9, 6e9, 5e9, 4e9,
                       2e9,  1e9, 1e9, 0.8e9, 0.5e9),
    exchange      = rep("US", 10L)
  )

  exchange_stats <- dplyr::summarise(
    ticker_stats,
    median_vol = median(avg_dollar_vol, na.rm = TRUE),
    n_tickers  = dplyr::n(),
    .by = exchange
  )

  flagged <- ticker_stats |>
    dplyr::left_join(exchange_stats, by = "exchange") |>
    dplyr::mutate(ratio_to_median = avg_dollar_vol / pmax(median_vol, 1)) |>
    dplyr::filter(ratio_to_median > 50)

  expect_equal(nrow(flagged), 0L,
    info = paste("Expected 0 flagged; got:", paste(flagged$ticker, collapse = ", ")))
})

test_that("recalibrated flag: genuinely anomalous volume DOES flag (>50x median)", {
  # Simulates a ticker with a data error: volume 200x the US median
  ticker_stats <- tibble::tibble(
    ticker        = c("BADTICKER", "AAPL", "MSFT", "NVDA", "META",
                      "WMT", "KO", "PEP", "DIS", "T"),
    avg_dollar_vol = c(400e9, 8e9, 6e9, 5e9, 4e9,   # BADTICKER ~400B: data error
                       2e9,  1e9, 1e9, 0.8e9, 0.5e9),
    exchange      = rep("US", 10L)
  )

  exchange_stats <- dplyr::summarise(
    ticker_stats,
    median_vol = median(avg_dollar_vol, na.rm = TRUE),
    n_tickers  = dplyr::n(),
    .by = exchange
  )

  flagged <- ticker_stats |>
    dplyr::left_join(exchange_stats, by = "exchange") |>
    dplyr::mutate(ratio_to_median = avg_dollar_vol / pmax(median_vol, 1)) |>
    dplyr::filter(ratio_to_median > 50)

  expect_equal(nrow(flagged), 1L)
  expect_equal(flagged$ticker, "BADTICKER")
})

test_that("recalibrated flag: non-US tickers excluded BEFORE flagging (NA after nulling)", {
  # After nulling, non-US tickers have NA avg_dollar_vol and are filtered out.
  # Even with enormous raw volume (the yfinance bug), they should not appear in stats.
  ticker_stats_all <- tibble::tibble(
    ticker        = c("ISF.L", "VUKE.L", "SPY", "AAPL"),
    avg_dollar_vol = c(NA_real_, NA_real_, 17e9, 8e9),  # non-US already nulled
    exchange      = c("L", "L", "US", "US")
  )

  # filter step from qa_volume_sanity: exclude NA (non-US)
  ticker_stats <- dplyr::filter(ticker_stats_all, !is.na(avg_dollar_vol))

  expect_equal(nrow(ticker_stats), 2L)
  expect_equal(sort(ticker_stats$ticker), c("AAPL", "SPY"))
})
