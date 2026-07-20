testthat::local_edition(3)
source(here::here("R/liquidity.R"))

# ── calculate_adv() ───────────────────────────────────────────────────────

test_that("calculate_adv computes correct rolling dollar-volume mean", {
  df <- tibble::tibble(
    ticker = rep("AAA", 5),
    date = as.Date("2024-01-01") + 0:4,
    close = rep(10, 5),
    volume = rep(1e6, 5)
  )
  result <- calculate_adv(df, window_days = 3)

  # window_days = 3 -> .before = 2, .complete = TRUE: first 2 rows have no
  # complete window and must be NA; from row 3 onward dollar_volume is
  # constant (10 * 1e6 = 1e7) so the rolling mean is also 1e7.
  expect_equal(result$adv_usd, c(NA_real_, NA_real_, 1e7, 1e7, 1e7))
  # dollar_volume is an intermediate column and must not leak into the output
  expect_false("dollar_volume" %in% names(result))
})

test_that("calculate_adv computes each ticker's rolling window independently", {
  df <- tibble::tibble(
    ticker = c(rep("AAA", 3), rep("BBB", 3)),
    date = rep(as.Date("2024-01-01") + 0:2, 2),
    close = c(10, 10, 10, 100, 100, 100),
    volume = c(1e6, 1e6, 1e6, 1e6, 1e6, 1e6)
  )
  result <- calculate_adv(df, window_days = 3)

  aaa_last <- result$adv_usd[result$ticker == "AAA"][3]
  bbb_last <- result$adv_usd[result$ticker == "BBB"][3]
  expect_equal(aaa_last, 1e7)
  expect_equal(bbb_last, 1e8)
})

test_that("calculate_adv returns all NA when window_days exceeds available history (edge case)", {
  df <- tibble::tibble(
    ticker = rep("AAA", 2),
    date = as.Date("2024-01-01") + 0:1,
    close = c(10, 10),
    volume = c(1e6, 1e6)
  )
  result <- calculate_adv(df, window_days = 5)
  expect_true(all(is.na(result$adv_usd)))
  expect_length(result$adv_usd, 2L)
})

# ── filter_liquidity() ────────────────────────────────────────────────────

test_that("filter_liquidity flags liquid/illiquid/insufficient_data correctly (warn mode)", {
  df <- tibble::tibble(
    ticker = c("AAA", "AAA", "BBB"),
    adv_usd = c(NA_real_, 5e6, 1e5)
  )
  expect_warning(
    result <- filter_liquidity(df, min_adv_usd = 1e6, filter_mode = "warn"),
    "illiquid"
  )
  expect_equal(result$liquidity_flag, c("insufficient_data", "liquid", "illiquid"))
  # warn mode never drops rows
  expect_equal(nrow(result), 3L)
})

test_that("filter_liquidity removes illiquid rows in remove mode", {
  df <- tibble::tibble(
    ticker = c("AAA", "AAA", "BBB"),
    adv_usd = c(NA_real_, 5e6, 1e5)
  )
  result <- suppressWarnings(filter_liquidity(df, min_adv_usd = 1e6, filter_mode = "remove"))
  expect_equal(nrow(result), 1L)
  expect_equal(result$ticker, "AAA")
  expect_false("illiquid" %in% result$liquidity_flag)
})

test_that("filter_liquidity aborts with an informative error when adv_usd is missing", {
  expect_snapshot(
    error = TRUE,
    filter_liquidity(tibble::tibble(ticker = "AAA"))
  )
})

# ── liquidity_summary() ───────────────────────────────────────────────────

test_that("liquidity_summary computes correct per-ticker medians and orders by median_adv_usd desc", {
  df <- tibble::tibble(
    ticker = c("AAA", "AAA", "BBB", "BBB"),
    volume = c(100, 200, 10, 20),
    close = c(10, 12, 5, 6),
    adv_usd = c(1000, 1200, 50, 60),
    liquidity_flag = c("liquid", "liquid", "illiquid", "illiquid")
  )
  result <- liquidity_summary(df)

  # AAA has the higher median_adv_usd (1100 vs 55) -> arrange(desc()) puts it first
  expect_equal(result$ticker, c("AAA", "BBB"))
  expect_equal(result$n_obs, c(2L, 2L))

  aaa <- result[result$ticker == "AAA", ]
  expect_equal(aaa$median_volume, 150)
  expect_equal(aaa$median_price, 11)
  expect_equal(aaa$median_adv_usd, 1100)
  expect_equal(aaa$pct_illiquid, 0)

  bbb <- result[result$ticker == "BBB", ]
  expect_equal(bbb$pct_illiquid, 100)
})

# ── API stability ──────────────────────────────────────────────────────────

test_that("liquidity function signatures are stable (catches API drift)", {
  expect_snapshot(args(calculate_adv))
  expect_snapshot(args(filter_liquidity))
  expect_snapshot(args(liquidity_summary))
})
