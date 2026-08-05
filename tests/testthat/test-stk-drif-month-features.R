testthat::local_edition(3)
# Tests for stk_drif_month_features() -- #641 fix.
#
# Root cause of #641: the pre-fix implementation confined the DRIF lookback
# window to the single PRECEDING calendar month (`daily |> filter(ym ==
# prev_m)`). February supplies only 19-21 trading days a year (never
# reliably `lookback_days` = 21), so the `c20`/`c21` (and `r20`/`r21`)
# feature columns came out NA for nearly every ticker whenever the target
# month was March -- and `predict.glmnet()` propagates any NA feature to an
# NA prediction for the whole row, wiping out 14 of 17 March months (and,
# by the identical mechanism, 23 further single-year months fed by an
# unusually short predecessor month).
#
# The fix (`stk_drif_month_features()`) pulls a genuine trailing
# `lb`-trading-day window per ticker, spanning calendar-month boundaries as
# needed, instead of confining the window to one calendar month.

local_env <- new.env(parent = globalenv())
suppressWarnings(
  sys.source(
    here::here("R/plan_stock_backtest.R"),
    envir = local_env,
    keep.source = FALSE
  )
)
stk_drif_month_features <- local_env$stk_drif_month_features

# ── Fixture: a short (19-trading-day) February preceded by 10 days of
#    January history, so a full 21-day trailing window requires reaching
#    back across the calendar-month boundary. ────────────────────────────
make_jan_feb_fixture <- function(tickers = c("AAA", "BBB"), n_jan = 10L, n_feb = 19L) {
  jan_days <- as.Date("2013-01-02") + seq_len(n_jan) - 1L
  feb_days <- as.Date("2013-02-01") + seq_len(n_feb) - 1L
  mar_first <- as.Date("2013-03-04")

  set.seed(1L)
  daily <- purrr::map_dfr(tickers, function(tk) {
    dplyr::bind_rows(
      tibble::tibble(ticker = tk, date = c(jan_days, feb_days),
                      daily_ret = rnorm(n_jan + n_feb, 0, 0.01)),
      tibble::tibble(ticker = tk, date = mar_first, daily_ret = 0.001)
    )
  })
  daily <- daily |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::arrange(ticker, date)

  monthly <- tibble::tibble(
    ticker = tickers, ym = "2013-03",
    monthly_ret = seq(0.01, by = 0.01, length.out = length(tickers))
  )

  list(daily = daily, monthly = monthly, jan_days = jan_days, feb_days = feb_days)
}

# ── Test 1: full lb-day window achieved by spanning Jan into Feb ────────

test_that("trailing window spans the calendar-month boundary when February is short (#641)", {
  f <- make_jan_feb_fixture()
  feat <- stk_drif_month_features(f$daily, "2013-03", f$monthly, lb = 21L, min_days = 10L)

  expect_equal(nrow(feat), 2L)
  expect_true(all(paste0("c", 1:21) %in% names(feat)))
  expect_true(all(paste0("r", 1:21) %in% names(feat)))
  expect_false(anyNA(as.matrix(feat[, paste0("c", 1:21)])))
  expect_false(anyNA(as.matrix(feat[, paste0("r", 1:21)])))
})

test_that("chrono column c1 is the OLDEST day and c{lb} is the most recent day before cutoff", {
  f <- make_jan_feb_fixture()
  feat <- stk_drif_month_features(f$daily, "2013-03", f$monthly, lb = 21L, min_days = 10L)

  aaa_daily <- f$daily |>
    dplyr::filter(ticker == "AAA", date < as.Date("2013-03-04")) |>
    dplyr::arrange(date)
  # Trailing 21 days: the last 21 rows of aaa_daily (29 total: 10 Jan + 19 Feb).
  window <- utils::tail(aaa_daily, 21L)

  aaa_feat <- feat |> dplyr::filter(ticker == "AAA")
  expect_equal(unname(as.numeric(aaa_feat[["c1"]])), window$daily_ret[1L])
  expect_equal(unname(as.numeric(aaa_feat[["c21"]])), window$daily_ret[21L])
})

# ── Test 2: without prior-month history, window is truncated (not NA) ───

test_that("with no history before the short month, c-columns beyond available days are simply absent", {
  f <- make_jan_feb_fixture(n_jan = 0L)  # only February exists -- 19 days
  feat <- stk_drif_month_features(f$daily, "2013-03", f$monthly, lb = 21L, min_days = 10L)

  expect_equal(nrow(feat), 2L)
  expect_true("c19" %in% names(feat))
  expect_false("c20" %in% names(feat))
  expect_false("c21" %in% names(feat))
  expect_false(anyNA(as.matrix(feat[, paste0("c", 1:19)])))
})

# ── Test 3: ticker below min_days is dropped ─────────────────────────────

test_that("a ticker with fewer than min_days trailing trading days is dropped", {
  feb_days <- as.Date("2013-02-01") + 0:18   # 19 days -- plenty for AAA
  thin_days <- as.Date("2013-02-15") + 0:3   # only 4 days -- below min_days for BBB
  mar_first <- as.Date("2013-03-04")

  set.seed(2L)
  daily <- dplyr::bind_rows(
    tibble::tibble(ticker = "AAA", date = feb_days, daily_ret = rnorm(length(feb_days), 0, 0.01)),
    tibble::tibble(ticker = "AAA", date = mar_first, daily_ret = 0.001),
    tibble::tibble(ticker = "BBB", date = thin_days, daily_ret = rnorm(length(thin_days), 0, 0.01)),
    tibble::tibble(ticker = "BBB", date = mar_first, daily_ret = 0.002)
  ) |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::arrange(ticker, date)

  monthly <- tibble::tibble(ticker = c("AAA", "BBB"), ym = "2013-03", monthly_ret = c(0.01, 0.02))

  feat <- stk_drif_month_features(daily, "2013-03", monthly, lb = 21L, min_days = 10L)
  expect_false("BBB" %in% feat$ticker)
  expect_true("AAA" %in% feat$ticker)
})

# ── Test 4: target month absent from daily entirely -> zero rows, not NULL ──

test_that("a target month with no trading dates in daily returns zero rows, not NULL", {
  f <- make_jan_feb_fixture()
  feat <- stk_drif_month_features(f$daily, "2099-01", f$monthly, lb = 21L, min_days = 10L)
  expect_s3_class(feat, "data.frame")
  expect_equal(nrow(feat), 0L)
})

# ── Test 5: function signature is stable (catches API drift) ────────────

test_that("stk_drif_month_features signature is stable (catches API drift)", {
  expect_snapshot(args(stk_drif_month_features))
})
