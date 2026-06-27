# Regression tests for #325: canonical adjusted_close column across datasets.
# Regression tests for #489 Cluster A: vig_eq_faang / vig_eq_vol adjusted→adjusted_close.

# ── Helpers used by vig_eq_faang and vig_eq_vol (inline in code-as-target strings) ──

# Simulate what hd_ohlcv() returns for equity tickers after the #325/#397 rename:
# a tibble with 'adjusted_close' (not bare 'adjusted').
.ohlcv_frame <- function() {
  tibble::tibble(
    date           = as.Date(c("2024-01-02", "2024-01-03", "2024-01-04")),
    close          = c(100.0, 110.0, 121.0),
    adjusted_close = c(100.0, 110.0, 121.0),
    ticker         = "AAPL"
  )
}

test_that("return calc with adjusted_close gives expected values (#489 Cluster A regression)", {
  # 3-row frame → ret = adjusted_close / lag(adjusted_close) - 1
  df <- .ohlcv_frame() |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(ret = adjusted_close / dplyr::lag(adjusted_close) - 1) |>
    dplyr::ungroup()

  # Row 1: NA (no lag)
  expect_true(is.na(df$ret[1L]))
  # Rows 2 and 3: exact 10% return each
  expect_equal(df$ret[2L], 0.1, tolerance = 1e-10)
  expect_equal(df$ret[3L], 0.1, tolerance = 1e-10)
})

test_that("cum-return calc with adjusted_close gives expected values (#489 Cluster A regression)", {
  # Mirrors vig_eq_faang: cum_ret = adjusted_close / first(adjusted_close) - 1
  df <- .ohlcv_frame() |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(cum_ret = adjusted_close / dplyr::first(adjusted_close) - 1) |>
    dplyr::ungroup()

  expect_equal(df$cum_ret[1L], 0.0,  tolerance = 1e-10)
  expect_equal(df$cum_ret[2L], 0.1,  tolerance = 1e-10)
  expect_equal(df$cum_ret[3L], 0.21, tolerance = 1e-10)
})

test_that("bare 'adjusted' column on an adjusted_close frame gives a clear dplyr error (#489 regression)", {
  # After #325/#397, hd_ohlcv() returns 'adjusted_close', not 'adjusted'.
  # Code that uses 'adjusted' on such a frame must fail loudly, not silently return NA.
  df <- .ohlcv_frame()   # has 'adjusted_close', NOT 'adjusted'

  expect_error(
    dplyr::mutate(df, ret = adjusted / dplyr::lag(adjusted) - 1),
    regexp = "adjusted",
    info   = "dplyr must error when bare 'adjusted' column is absent"
  )
})



test_that("equity_daily schema uses adjusted_close, not adjusted", {
  ds <- hd_datasets()
  schema <- ds[["equity_daily"]][["schema"]]
  expect_true("adjusted_close" %in% schema,
              label = "equity_daily schema must contain 'adjusted_close'")
  expect_false("adjusted" %in% schema,
               label = "equity_daily schema must NOT contain bare 'adjusted'")
})

test_that("alphavantage_daily schema uses adjusted_close", {
  ds <- hd_datasets()
  schema <- ds[["alphavantage_daily"]][["schema"]]
  expect_true("adjusted_close" %in% schema,
              label = "alphavantage_daily schema must contain 'adjusted_close'")
  expect_false("adjusted" %in% schema,
               label = "alphavantage_daily schema must NOT contain bare 'adjusted'")
})

test_that("backward-compat alias: old 'adjusted' column is renamed to 'adjusted_close'", {
  # Simulate a parquet-like tibble with the OLD column name
  old_frame <- tibble::tibble(
    date          = as.Date(c("2024-01-02", "2024-01-03")),
    open          = c(185.5, 186.0),
    high          = c(187.1, 188.0),
    low           = c(184.9, 185.5),
    close         = c(186.8, 187.5),
    adjusted      = c(186.0, 186.7),   # OLD column name
    volume        = c(50000000L, 48000000L),
    ticker        = c("AAPL", "AAPL"),
    source        = c("yahoo", "yahoo"),
    asset_class   = c("equity", "equity")
  )

  # Apply the same alias logic used inside hd_lazy() / hd_ohlcv_single()
  col_names <- names(old_frame)
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    old_frame <- dplyr::rename(old_frame, adjusted_close = adjusted)
  }

  expect_true("adjusted_close" %in% names(old_frame),
              label = "alias must produce 'adjusted_close'")
  expect_false("adjusted" %in% names(old_frame),
               label = "old 'adjusted' column must be gone after alias")
})

test_that("backward-compat alias is a no-op when adjusted_close already present", {
  new_frame <- tibble::tibble(
    date           = as.Date("2024-01-02"),
    close          = 186.8,
    adjusted_close = 186.0,
    ticker         = "AAPL"
  )

  col_names <- names(new_frame)
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    new_frame <- dplyr::rename(new_frame, adjusted_close = adjusted)
  }

  expect_true("adjusted_close" %in% names(new_frame))
  expect_false("adjusted" %in% names(new_frame))
  expect_equal(nrow(new_frame), 1L)
})

# ── Fix 1 (#489 Cluster D): mr_daily and mr_plot use adjusted_close ──────────
# plan_mean_reversion.R previously referenced bare `adjusted` (→ "object not found").
# Regression: the return-calc pattern used in both mr_daily and mr_plot targets
# must work with adjusted_close, not adjusted.

test_that("mr_daily return-calc pattern with adjusted_close (multi-ticker, #489 Cluster D)", {
  # Simulate what hd_ohlcv() returns for two tickers: adjusted_close present
  tickers <- c("AAPL", "MSFT")
  make_ticker_frame <- function(tkr) {
    tibble::tibble(
      date           = as.Date(c("2024-01-02", "2024-01-03", "2024-01-04")),
      adjusted_close = c(100.0, 105.0, 110.25),
      volume         = c(1e6, 1.1e6, 1.2e6),
      ticker         = tkr
    )
  }

  result <- purrr::map_dfr(tickers, function(tkr) {
    make_ticker_frame(tkr) |>
      dplyr::arrange(date) |>
      dplyr::mutate(
        ret = adjusted_close / dplyr::lag(adjusted_close) - 1
      ) |>
      dplyr::filter(!is.na(ret)) |>
      dplyr::select(date, ticker, ret, adjusted_close, volume)
  })

  # 2 tickers × 2 non-NA rows each = 4 rows
  expect_equal(nrow(result), 4L)
  # All returns should be approximately 5%
  expect_true(all(abs(result$ret - 0.05) < 1e-8))
  # adjusted_close column must be present (no bare 'adjusted')
  expect_true("adjusted_close" %in% names(result))
  expect_false("adjusted" %in% names(result))
})

test_that("mr_plot spy-benchmark return-calc uses adjusted_close (#489 Cluster D)", {
  spy_frame <- tibble::tibble(
    date           = as.Date(c("2024-01-02", "2024-01-03", "2024-01-04",
                               "2024-01-05")),
    adjusted_close = c(400.0, 404.0, 408.04, 412.12)
  )

  spy <- spy_frame |>
    dplyr::arrange(date) |>
    dplyr::mutate(ret = adjusted_close / dplyr::lag(adjusted_close) - 1) |>
    dplyr::filter(!is.na(ret)) |>
    dplyr::mutate(cum_spy = cumprod(1 + ret)) |>
    dplyr::select(date, cum_spy)

  expect_equal(nrow(spy), 3L)
  # Cumulative value after 3 ~1% returns should be ~(1.01)^3 ≈ 1.0303
  expect_equal(spy$cum_spy[3L], (404 / 400) * (408.04 / 404) * (412.12 / 408.04),
               tolerance = 1e-8)
})

test_that("hd_alphavantage output uses adjusted_close", {
  skip_if_not_installed("alphavantager")
  mock_result <- tibble::tibble(
    timestamp         = as.Date(c("2024-01-02", "2024-01-03")),
    open              = c(185.5, 186.0),
    high              = c(187.1, 188.0),
    low               = c(184.9, 185.5),
    close             = c(186.8, 187.5),
    adjusted_close    = c(186.0, 186.7),
    volume            = c(50000000L, 48000000L),
    dividend_amount   = c(0, 0),
    split_coefficient = c(1, 1)
  )
  testthat::local_mocked_bindings(
    av_get = function(...) mock_result,
    .package = "alphavantager"
  )
  withr::with_envvar(c(ALPHAVANTAGE_API_KEY = "demo"), {
    result <- hd_alphavantage("AAPL", from = "2024-01-01")
  })
  expect_true("adjusted_close" %in% names(result),
              label = "hd_alphavantage() must return 'adjusted_close'")
  expect_false("adjusted" %in% names(result),
               label = "hd_alphavantage() must NOT return bare 'adjusted'")
})
