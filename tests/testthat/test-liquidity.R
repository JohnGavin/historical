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

# ── filter_liquidity() percentile threshold_mode (#625) ──────────────────
#
# The nominal $ threshold drifts in liquidity-percentile terms as ADV grows
# over a multi-decade sample -- see .claude/rules/valuation-spread-threshold.md
# and issue #625's "A real modelling concern" section. threshold_mode =
# "percentile" recomputes the cutoff from the current cross-section (`by`,
# default "date") each period instead of a fixed dollar figure, so the gate
# is regime-invariant.

test_that("filter_liquidity threshold_mode='nominal' is unchanged default behaviour", {
  df <- tibble::tibble(
    ticker = c("AAA", "AAA", "BBB"),
    adv_usd = c(NA_real_, 5e6, 1e5)
  )
  expect_warning(
    result <- filter_liquidity(df, min_adv_usd = 1e6),
    "illiquid"
  )
  expect_equal(result$liquidity_flag, c("insufficient_data", "liquid", "illiquid"))
})

test_that("filter_liquidity threshold_mode='percentile' flags the bottom fraction per cross-section", {
  # Two dates, 4 tickers each. adv_usd ranks are stable within each date, but
  # the ABSOLUTE dollar levels double from date 1 to date 2 -- a nominal
  # threshold would misclassify a differently-sized bottom fraction on each
  # date; a percentile threshold flags the same rank fraction on both.
  df <- tibble::tibble(
    date = rep(as.Date(c("2024-01-01", "2024-01-02")), each = 4),
    ticker = rep(c("AAA", "BBB", "CCC", "DDD"), 2),
    adv_usd = c(1e5, 2e5, 3e5, 4e5, 2e5, 4e5, 6e5, 8e5)
  )
  result <- suppressWarnings(filter_liquidity(
    df,
    threshold_mode = "percentile",
    min_adv_percentile = 0.30,
    by = "date"
  ))
  # Bottom 30% by rank (percent_rank < 0.30) is the single lowest-ADV name
  # (percent_rank 0) on each date -- AAA on date 1, AAA (2e5) on date 2.
  expect_equal(
    result$liquidity_flag[result$date == as.Date("2024-01-01") & result$ticker == "AAA"],
    "illiquid"
  )
  expect_equal(
    result$liquidity_flag[result$date == as.Date("2024-01-02") & result$ticker == "AAA"],
    "illiquid"
  )
  # DDD (highest ADV on both dates) is always liquid despite the absolute
  # dollar level doubling between dates -- this is the regime-invariance
  # property nominal thresholds lack.
  expect_true(all(
    result$liquidity_flag[result$ticker == "DDD"] == "liquid"
  ))
})

test_that("filter_liquidity threshold_mode='percentile' preserves insufficient_data for NA adv_usd", {
  df <- tibble::tibble(
    date = as.Date("2024-01-01"),
    ticker = c("AAA", "BBB", "CCC"),
    adv_usd = c(NA_real_, 1e5, 2e5)
  )
  result <- suppressWarnings(filter_liquidity(
    df,
    threshold_mode = "percentile",
    min_adv_percentile = 0.30,
    by = "date"
  ))
  expect_equal(result$liquidity_flag[result$ticker == "AAA"], "insufficient_data")
})

test_that("filter_liquidity threshold_mode='percentile' aborts when the `by` column is absent", {
  expect_snapshot(
    error = TRUE,
    filter_liquidity(
      tibble::tibble(ticker = "AAA", adv_usd = 1e6),
      threshold_mode = "percentile",
      by = "date"
    )
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
