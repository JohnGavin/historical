testthat::local_edition(3)

# Regression tests for issue #669: pipeline errors from an adjusted vs
# adjusted_close schema mismatch, broken for ~10 weeks and masked by
# target caching. hd_ohlcv()/hd_lazy() apply a read-time alias so callers
# always see adjusted_close; twelve root-level plan_*.R consumers had
# drifted to reference the pre-#325 bare adjusted name instead and were
# fixed here. See also the hd_ohlcv()-level hermetic contract tests in
# packages/historicaldata/tests/testthat/test-hd-ohlcv-adjusted-close-contract.R.
#
# .hd_assert_price_schema() lives in packages/historicaldata/R/query.R and
# depends only on base R + cli (no duckplyr) -- sourced directly here,
# same pattern as test-cov-routing.R, to keep this file hermetic and
# independent of whether duckplyr is loadable in this test environment.
source(here::here("packages/historicaldata/R/registry.R"))
source(here::here("packages/historicaldata/R/query.R"))

# ── Static regression guard: no fixed plan file may reintroduce a bare
# adjusted symbol reference (#669) ─────────────────────────────────────

test_that("fixed plan_*.R files reference adjusted_close, never bare adjusted (#669)", {
  fixed_files <- c(
    "R/plan_backtest.R", "R/plan_etf_replication.R", "R/plan_avoid_worst.R",
    "R/plan_circuit_breaker.R", "R/plan_factormax.R", "R/plan_guardian.R",
    "R/plan_integration.R", "R/plan_nyt_sentiment.R", "R/plan_olmar.R",
    "R/plan_risk_state.R", "R/plan_quiz.R", "R/plan_vix_macro_overlay.R"
  )
  for (f in fixed_files) {
    exprs <- parse(here::here(f))
    syms <- unlist(lapply(exprs, function(e) all.names(e, unique = TRUE)))
    expect_false("adjusted" %in% syms, label = paste("bare adjusted symbol in", f))
    expect_true("adjusted_close" %in% syms, label = paste("expected adjusted_close symbol in", f))
  }
})

# ── hd_datasets() contract: equity_daily promises adjusted_close ───────

test_that("hd_datasets() equity_daily schema promises adjusted_close (#669)", {
  ds <- hd_datasets()
  expect_true("adjusted_close" %in% ds[["equity_daily"]][["schema"]])
  expect_false("adjusted" %in% ds[["equity_daily"]][["schema"]])
})

# ── .hd_assert_price_schema(): the access-boundary schema guard (#669) ──

test_that(".hd_assert_price_schema() aborts when a promised dataset is missing adjusted_close", {
  expect_snapshot(
    error = TRUE,
    .hd_assert_price_schema(c("date", "open", "close", "volume"), "equity_daily")
  )
})

test_that(".hd_assert_price_schema() aborts carry the hd_schema_drift class", {
  cnd <- tryCatch(
    .hd_assert_price_schema(c("date"), "equity_daily"),
    error = function(e) e
  )
  expect_true(inherits(cnd, "hd_schema_drift"))
})

test_that(".hd_assert_price_schema() is silent when adjusted_close is present", {
  expect_no_error(.hd_assert_price_schema(c("date", "adjusted_close"), "equity_daily"))
})

test_that(".hd_assert_price_schema() is silent for datasets that do not promise adjusted_close", {
  expect_no_error(.hd_assert_price_schema(c("date", "open", "close", "volume"), "crypto_daily"))
  expect_no_error(.hd_assert_price_schema(c("date", "value", "series_id"), "macro_daily"))
})

test_that(".hd_assert_price_schema() is silent for an unknown dataset (defensive default)", {
  expect_no_error(.hd_assert_price_schema(c("date"), "not_a_real_dataset"))
})
