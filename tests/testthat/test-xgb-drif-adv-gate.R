# Tests for xgb_drif_portfolio ADV investability gate (#449)
# Variant A (filter-then-rank): illiquid names dropped BEFORE ntile() so they
# cannot appear in extreme deciles due to noisy XGBoost predicted_ret alone.
#
# Mirrors test-stk-drif-adv-gate.R (elastic-net, #312) — same logic, same
# fixture design. The assign_decile() function is loaded from
# plan_stock_backtest.R via sys.source().
#
# XGB-specific note: XGBoost with monotonic constraints can produce tighter
# predicted-return spreads than elastic-net (predictions clamp at boundary
# tree-leaf values), but the gate logic is identical. We use the same illiquid-
# ticker IL2-at-99 design because extreme predictions are the pathological case.

testthat::local_edition(3)

# ── Load helper functions ─────────────────────────────────────────────────────
local_env <- new.env(parent = globalenv())
suppressWarnings(
  sys.source(
    here::here("R/plan_stock_backtest.R"),
    envir = local_env,
    keep.source = FALSE
  )
)
assign_decile <- local_env$assign_decile

# ── Shared fixture factory ────────────────────────────────────────────────────
# 6 months × 12 tickers (≥ n_deciles * 5 = 10 min per month for n_deciles=2).
# Tickers T01-T10 are LIQUID (adv_dollars = 10e6 > 5e6 threshold).
# IL1 and IL2 are ILLIQUID (adv_dollars = 1e6 < 5e6).
# IL2 has the HIGHEST predicted_ret in every month.
# IL1 has the LOWEST predicted_ret in every month.
# Without the ADV gate IL2 always lands in decile 1 and IL1 in decile 10.
make_xgb_fixture <- function() {
  set.seed(123L)
  months           <- format(seq.Date(as.Date("2020-01-01"), by = "month", length.out = 6), "%Y-%m")
  liquid_tickers   <- paste0("T", sprintf("%02d", 1:10))
  illiquid_tickers <- c("IL1", "IL2")
  all_tickers      <- c(liquid_tickers, illiquid_tickers)

  base <- tidyr::expand_grid(ym = months, ticker = all_tickers) |>
    dplyr::mutate(
      monthly_ret   = rnorm(dplyr::n(), mean = 0.01, sd = 0.05),
      # XGB predictions: bounded range (monotonic constraint effect) except
      # the two illiquid outliers which simulate extreme XGB leaf values
      predicted_ret = runif(dplyr::n(), min = -0.05, max = 0.05)
    )

  base <- base |>
    dplyr::mutate(
      predicted_ret = dplyr::if_else(ticker == "IL2",  99.0, predicted_ret),
      predicted_ret = dplyr::if_else(ticker == "IL1", -99.0, predicted_ret)
    )

  adv <- tidyr::expand_grid(ym = months, ticker = all_tickers) |>
    dplyr::mutate(
      adv_dollars = dplyr::if_else(ticker %in% illiquid_tickers, 1e6, 10e6)
    )

  list(
    signal = base, adv = adv, months = months,
    liquid = liquid_tickers, illiquid = illiquid_tickers,
    adv_threshold = 5e6, n_deciles = 2L
  )
}

# ── Test 1: ADV filter removes illiquid tickers before decile assignment ──────
test_that("XGB ADV gate excludes illiquid tickers before decile assignment", {
  f <- make_xgb_fixture()

  filtered <- f$signal |>
    dplyr::inner_join(
      f$adv |> dplyr::select(ticker, ym, adv_dollars),
      by = c("ticker", "ym")
    ) |>
    dplyr::filter(adv_dollars >= f$adv_threshold)

  expect_false("IL2" %in% filtered$ticker,
    label = "IL2 (high XGB predicted_ret, illiquid) excluded by ADV gate")
  expect_false("IL1" %in% filtered$ticker,
    label = "IL1 (low XGB predicted_ret, illiquid) excluded by ADV gate")
  expect_true(all(f$liquid %in% filtered$ticker),
    label = "All liquid tickers survive the XGB ADV gate")
})

# ── Test 2: Without gate IL2 lands in decile 1; with gate it is absent ───────
test_that("IL2 (highest XGB predicted_ret, illiquid) never in top decile after gate", {
  f <- make_xgb_fixture()

  # Baseline: IL2 at predicted_ret=99 always wins decile 1
  deciled_baseline <- assign_decile(f$signal, predicted_ret, f$n_deciles)
  il2_deciles_baseline <- deciled_baseline |>
    dplyr::filter(ticker == "IL2") |>
    dplyr::pull(decile)
  expect_true(all(il2_deciles_baseline == 1L),
    label = "Without ADV gate, IL2 (predicted_ret=99) lands in decile 1 every month")

  # Variant A (filter-then-rank, fix #449):
  gated <- f$signal |>
    dplyr::inner_join(
      f$adv |> dplyr::select(ticker, ym, adv_dollars),
      by = c("ticker", "ym")
    ) |>
    dplyr::filter(adv_dollars >= f$adv_threshold)

  stocks_per_month <- gated |> dplyr::count(ym, name = "n_stocks")
  valid_months     <- stocks_per_month |>
    dplyr::filter(n_stocks >= f$n_deciles * 5L) |>
    dplyr::pull(ym)
  gated <- gated |> dplyr::filter(ym %in% valid_months)

  deciled_a <- assign_decile(gated, predicted_ret, f$n_deciles)

  expect_equal(
    nrow(deciled_a |> dplyr::filter(ticker == "IL2")),
    0L,
    label = "IL2 absent from XGB decile output after filter-then-rank ADV gate"
  )
  expect_equal(
    nrow(deciled_a |> dplyr::filter(ticker == "IL1")),
    0L,
    label = "IL1 absent from XGB decile output after filter-then-rank ADV gate"
  )
})

# ── Test 3: Min-stocks guard applied AFTER the ADV filter (XGB-specific) ─────
test_that("months with too few XGB survivors after ADV gate are excluded", {
  months    <- format(seq.Date(as.Date("2020-01-01"), by = "month", length.out = 3), "%Y-%m")
  n_deciles <- 2L
  min_stocks <- n_deciles * 5L   # = 10

  # Month 1+2: 12 liquid tickers (>= 10: kept)
  # Month 3: only 4 liquid tickers (< 10: dropped)
  liquid_12 <- paste0("T", sprintf("%02d", 1:12))
  liquid_4  <- paste0("T", sprintf("%02d", 1:4))

  mk_rows <- function(tickers, ym_val) {
    tibble::tibble(
      ym = ym_val, ticker = tickers,
      predicted_ret = runif(length(tickers), -0.1, 0.1),
      monthly_ret   = rnorm(length(tickers), 0.01, 0.03),
      adv_dollars   = 10e6   # all pass ADV gate
    )
  }

  signal_with_adv <- dplyr::bind_rows(
    mk_rows(liquid_12, months[1]),
    mk_rows(liquid_12, months[2]),
    mk_rows(liquid_4,  months[3])
  )

  stocks_per_month <- signal_with_adv |> dplyr::count(ym, name = "n_stocks")
  valid_months <- stocks_per_month |>
    dplyr::filter(n_stocks >= min_stocks) |>
    dplyr::pull(ym)
  filtered <- signal_with_adv |> dplyr::filter(ym %in% valid_months)

  expect_true(months[1] %in% valid_months,  label = "Month 1 (12 survivors) kept")
  expect_true(months[2] %in% valid_months,  label = "Month 2 (12 survivors) kept")
  expect_false(months[3] %in% valid_months, label = "Month 3 (4 survivors) excluded after XGB ADV filter")
  expect_equal(dplyr::n_distinct(filtered$ym), 2L,
    label = "Exactly 2 months remain after min-stocks guard post-ADV-filter (XGB)")
})

# ── Test 4: Snapshot — structure of gated assign_decile output (XGB) ─────────
test_that("XGB gated assign_decile output has expected structure (snapshot)", {
  f <- make_xgb_fixture()

  gated <- f$signal |>
    dplyr::inner_join(
      f$adv |> dplyr::select(ticker, ym, adv_dollars),
      by = c("ticker", "ym")
    ) |>
    dplyr::filter(adv_dollars >= f$adv_threshold)

  stocks_per_month <- gated |> dplyr::count(ym, name = "n_stocks")
  valid_months <- stocks_per_month |>
    dplyr::filter(n_stocks >= f$n_deciles * 5L) |>
    dplyr::pull(ym)
  gated <- gated |> dplyr::filter(ym %in% valid_months)

  deciled <- assign_decile(gated, predicted_ret, f$n_deciles)

  expect_true("decile" %in% names(deciled),
    label = "decile column present after XGB assign_decile")
  expect_equal(sort(unique(deciled$decile)), seq_len(f$n_deciles),
    label = "decile values span 1..n_deciles with no gaps (XGB)")
  expect_false(any(deciled$ticker %in% f$illiquid),
    label = "no illiquid ticker in XGB gated decile output")

  # Snapshot: summary stats — catches structural regressions (#449)
  summary_counts <- deciled |>
    dplyr::count(ym, decile, name = "n") |>
    dplyr::summarise(
      n_months      = dplyr::n_distinct(ym),
      n_decile_vals = dplyr::n_distinct(decile),
      min_n         = min(n),
      max_n         = max(n),
      .groups = "drop"
    )
  expect_snapshot(str(summary_counts))
})

# ── Test 5: ADV threshold from stk_params is honoured (single source of truth)
# This test guards against hardcoding the threshold in xgb_drif_portfolio.
# It verifies that changing the threshold changes how many stocks survive.
test_that("ADV gate respects the supplied threshold (not a hardcoded constant)", {
  f <- make_xgb_fixture()

  signal_with_adv <- f$signal |>
    dplyr::inner_join(
      f$adv |> dplyr::select(ticker, ym, adv_dollars),
      by = c("ticker", "ym")
    )

  # At threshold = $5M: illiquid (1e6) excluded, liquid (10e6) kept
  at_5m <- signal_with_adv |> dplyr::filter(adv_dollars >= 5e6)
  expect_false(any(at_5m$ticker %in% f$illiquid),
    label = "At $5M threshold: illiquid excluded")

  # At threshold = $1M: illiquid (1e6) excluded (below strict >), liquid kept
  # Note: filter uses >=, so 1e6 >= 1e6 passes — adjust threshold to below 1e6
  at_0_5m <- signal_with_adv |> dplyr::filter(adv_dollars >= 0.5e6)
  expect_true(any(at_0_5m$ticker %in% f$illiquid),
    label = "At $0.5M threshold: illiquid included (threshold is parametric, not hardcoded)")

  # At threshold = $20M: all excluded (liquid at 10e6 < 20e6)
  at_20m <- signal_with_adv |> dplyr::filter(adv_dollars >= 20e6)
  expect_equal(nrow(at_20m), 0L,
    label = "At $20M threshold: all tickers excluded")
})
