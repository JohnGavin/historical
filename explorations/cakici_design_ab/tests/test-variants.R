# Snapshot tests for Cakici A/B decile construction variant logic
# Regression guard: verifies that the three variants (Baseline, A, B) produce
# stable, distinct decile assignments on synthetic data.
# Per snapshot-test-policy.md: snapshot wording drift is meaningful; snapshots
# are committed alongside this file.

library(testthat)
library(dplyr)

# Declare testthat edition 3 for expect_snapshot()
testthat::local_edition(3)

# ── Synthetic data ──────────────────────────────────────────────────────────
# 3 months, 15 tickers per month, hand-crafted ADV values that bracket the
# $5M threshold. Months: "2010-01", "2010-02", "2010-03"
# Tickers t01–t10 are liquid (ADV > $5M), t11–t15 are illiquid (ADV < $5M).
# predicted_ret is simply the ticker number so ranking is deterministic.

set.seed(42L)
months <- c("2010-01", "2010-02", "2010-03")
tickers <- sprintf("t%02d", 1:15)

# Build signal with predicted_ret = as.integer(sub("t","",ticker))
synthetic_signal <- expand.grid(
  ticker = tickers, ym = months, stringsAsFactors = FALSE
) |>
  as_tibble() |>
  dplyr::mutate(
    predicted_ret = as.integer(sub("t", "", ticker)) / 100,
    # monthly_ret is irrelevant for decile assignment; give it a tiny value
    monthly_ret = 0.01
  )

# ADV: t01-t10 get $10M (liquid), t11-t15 get $1M (illiquid)
synthetic_adv <- expand.grid(
  ticker = tickers, ym = months, stringsAsFactors = FALSE
) |>
  as_tibble() |>
  dplyr::mutate(
    adv_dollars = dplyr::if_else(
      as.integer(sub("t", "", ticker)) <= 10L,
      10e6,   # above $5M threshold
      1e6     # below $5M threshold
    )
  )

ADV_THRESHOLD <- 5e6
N_DECILES <- 5L  # use 5 instead of 10 so 10 liquid tickers fill all deciles cleanly

# ── Helper: build deciles (mirrors run.R logic) ──────────────────────────────
build_baseline <- function(signal, n_deciles) {
  signal |>
    dplyr::group_by(ym) |>
    dplyr::filter(dplyr::n() >= n_deciles) |>
    dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), n_deciles)) |>
    dplyr::ungroup()
}

build_variant_a <- function(signal, adv, threshold, n_deciles) {
  signal |>
    dplyr::inner_join(adv, by = c("ticker", "ym")) |>
    dplyr::filter(adv_dollars >= threshold) |>
    dplyr::group_by(ym) |>
    dplyr::filter(dplyr::n() >= n_deciles) |>
    dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), n_deciles)) |>
    dplyr::ungroup()
}

build_variant_b <- function(signal, adv, threshold, n_deciles) {
  signal |>
    dplyr::group_by(ym) |>
    dplyr::mutate(full_rank = dplyr::ntile(dplyr::desc(predicted_ret), n_deciles)) |>
    dplyr::ungroup() |>
    dplyr::inner_join(adv, by = c("ticker", "ym")) |>
    dplyr::filter(adv_dollars >= threshold) |>
    dplyr::group_by(ym) |>
    dplyr::filter(dplyr::n() >= n_deciles) |>
    dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), n_deciles)) |>
    dplyr::ungroup()
}

# ── Tests ──────────────────────────────────────────────────────────────────

test_that("Baseline includes all tickers and assigns 5 decile groups", {
  result <- build_baseline(synthetic_signal, N_DECILES)
  expect_equal(nrow(result), 45L)  # 15 tickers × 3 months
  expect_equal(sort(unique(result$decile)), 1:5)
  # snapshot: decile assignment per ticker-month is stable
  snap <- result |>
    dplyr::arrange(ym, ticker) |>
    dplyr::select(ticker, ym, decile)
  expect_snapshot(print(snap, n = 45L))
})

test_that("Variant A drops illiquid tickers BEFORE decile assignment", {
  result <- build_variant_a(synthetic_signal, synthetic_adv, ADV_THRESHOLD, N_DECILES)
  # Only t01–t10 pass the $5M ADV gate; 10 tickers × 3 months = 30 rows
  expect_equal(nrow(result), 30L)
  expect_true(all(!grepl("^t1[1-5]$", result$ticker)))
  expect_equal(sort(unique(result$decile)), 1:5)
  snap <- result |>
    dplyr::arrange(ym, ticker) |>
    dplyr::select(ticker, ym, decile)
  expect_snapshot(print(snap, n = 30L))
})

test_that("Variant B assigns full-universe rank THEN drops illiquid tickers", {
  result <- build_variant_b(synthetic_signal, synthetic_adv, ADV_THRESHOLD, N_DECILES)
  # Same 30 rows as A after gating, but re-cut deciles on the 10 survivors
  expect_equal(nrow(result), 30L)
  # Both full_rank and final decile columns present
  expect_true("full_rank" %in% names(result))
  expect_true("decile" %in% names(result))
  snap <- result |>
    dplyr::arrange(ym, ticker) |>
    dplyr::select(ticker, ym, full_rank, decile)
  expect_snapshot(print(snap, n = 30L))
})

test_that("Variant A and B produce identical final decile assignments on surviving tickers", {
  a <- build_variant_a(synthetic_signal, synthetic_adv, ADV_THRESHOLD, N_DECILES)
  b <- build_variant_b(synthetic_signal, synthetic_adv, ADV_THRESHOLD, N_DECILES)
  # For pure synthetic data: A and B should agree on decile assignment once the
  # same tickers survive (the re-cut in B re-assigns the same order).
  a_key <- a |> dplyr::arrange(ym, ticker) |> dplyr::select(ticker, ym, decile)
  b_key <- b |> dplyr::arrange(ym, ticker) |> dplyr::select(ticker, ym, decile)
  expect_equal(a_key, b_key)
})

test_that("Baseline assigns different deciles to illiquid tickers (they ARE included)", {
  baseline <- build_baseline(synthetic_signal, N_DECILES)
  illiquid_deciles <- baseline |>
    dplyr::filter(grepl("^t1[1-5]$", ticker)) |>
    dplyr::pull(decile)
  # illiquid tickers t11–t15 have predicted_ret > t06–t10, so they end up in
  # decile 1 (top predicted return) in the baseline but are absent from A/B
  expect_true(any(illiquid_deciles == 1L))
})

test_that("Snapshot of full-rank column in Variant B (regression guard)", {
  result <- build_variant_b(synthetic_signal, synthetic_adv, ADV_THRESHOLD, N_DECILES)
  snap <- result |>
    dplyr::filter(ym == "2010-01") |>
    dplyr::arrange(ticker) |>
    dplyr::select(ticker, full_rank, decile)
  expect_snapshot(print(snap))
})
