# Tests for hd_exposure_metrics() — gross/net/long/short/cash_borrow (#626)
#
# Test structure:
#   1. Long-only unlevered
#   2. Long-only levered (margin debt -> positive cash_borrow)
#   3. Dollar-neutral 2.0x gross (100 long / 100 short) -> cash_borrow 0
#   4. Dollar-neutral 1.0x gross (50 long / 50 short)  -> cash_borrow 0
#   5. Named vector: names are not part of the contract (values only)
#   6-8. Error snapshots: NA, non-numeric, zero-length
#   9.  Non-finite (Inf) input aborts
#   10. Function signature stability snapshot
#
# Snapshot count: 4 snapshots (error msgs x3 + args x1) out of 10 blocks
# => ratio 4/10 >= 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Test 1: long-only unlevered ---------------------------------------
test_that("long-only unlevered: gross 1, net 1, cash_borrow 0", {
  m <- hd_exposure_metrics(c(0.5, 0.5))
  expect_equal(m$gross, 1)
  expect_equal(m$net, 1)
  expect_equal(m$long, 1)
  expect_equal(m$short, 0)
  expect_equal(m$cash_borrow, 0)
})

# ---- Test 2: long-only levered (margin debt) ----------------------------
test_that("long-only levered: gross 1.2, net 1.2, cash_borrow 0.2", {
  m <- hd_exposure_metrics(c(0.7, 0.5))
  expect_equal(m$gross, 1.2, tolerance = 1e-12)
  expect_equal(m$net, 1.2, tolerance = 1e-12)
  expect_equal(m$long, 1.2, tolerance = 1e-12)
  expect_equal(m$short, 0)
  expect_equal(m$cash_borrow, 0.2, tolerance = 1e-12)
})

# ---- Test 3: dollar-neutral 2.0x gross (100 long / 100 short) -----------
test_that("dollar-neutral 2.0x: gross 2, net 0, long 1, short 1, cash_borrow 0", {
  m <- hd_exposure_metrics(c(0.5, 0.5, -0.5, -0.5))
  expect_equal(m$gross, 2)
  expect_equal(m$net, 0)
  expect_equal(m$long, 1)
  expect_equal(m$short, 1)
  expect_equal(m$cash_borrow, 0)
})

# ---- Test 4: dollar-neutral 1.0x gross (50 long / 50 short) -------------
test_that("dollar-neutral 1.0x: gross 1, net 0, cash_borrow 0", {
  m <- hd_exposure_metrics(c(0.25, 0.25, -0.25, -0.25))
  expect_equal(m$gross, 1)
  expect_equal(m$net, 0)
  expect_equal(m$long, 0.5)
  expect_equal(m$short, 0.5)
  expect_equal(m$cash_borrow, 0)
})

# ---- Test 5: named vector -- names are not part of the returned contract ----
test_that("named input vector does not error and produces the same values", {
  w <- c(AAPL = 0.6, MSFT = 0.4, TSLA = -0.3)
  m <- hd_exposure_metrics(w)
  expect_equal(m$gross, 1.3, tolerance = 1e-12)
  expect_equal(m$net, 0.7, tolerance = 1e-12)
  expect_equal(m$long, 1.0, tolerance = 1e-12)
  expect_equal(m$short, 0.3, tolerance = 1e-12)
  expect_s3_class(m, "tbl_df")
  expect_equal(nrow(m), 1L)
})

# ---- Test 6: NA input aborts with snapshot -------------------------------
test_that("NA in w aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_exposure_metrics(c(0.5, NA_real_))
  )
})

# ---- Test 7: non-numeric input aborts with snapshot ----------------------
test_that("character input aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_exposure_metrics(c("0.5", "0.5"))
  )
})

# ---- Test 8: zero-length input aborts with snapshot ----------------------
test_that("zero-length input aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_exposure_metrics(numeric(0))
  )
})

# ---- Test 9: non-finite (Inf) input aborts -------------------------------
test_that("Inf in w aborts with informative error", {
  expect_error(
    hd_exposure_metrics(c(0.5, Inf)),
    regexp = "finite"
  )
})

# ---- Test 10: function signature stability -------------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_exposure_metrics))
})
