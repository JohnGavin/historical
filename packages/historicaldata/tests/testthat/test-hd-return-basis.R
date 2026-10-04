testthat::local_edition(3)

# #919: the return-basis registry is the single home of "total vs excess".

test_that("registry schema is stable", {
  reg <- hd_return_basis()
  expect_snapshot_value(
    list(names = names(reg), classes = vapply(reg, class, character(1L)),
         strategy = reg$strategy, basis = reg$basis),
    style = "deparse"
  )
})

test_that("registry has unique strategies, a legal basis and evidence for each", {
  reg <- hd_return_basis()
  expect_false(anyDuplicated(reg$strategy) > 0L)
  expect_true(all(reg$basis %in% c("total", "excess", "indeterminate")))
  expect_true(all(nzchar(reg$evidence)))
})

test_that("Value (HML) is total; dollar-neutral spreads are excess", {
  expect_identical(hd_return_basis_of("Value (HML)"), "total")
  expect_identical(hd_return_basis_of("Mom Pre-Peak"), "excess")
  expect_identical(hd_return_basis_of("CMR Conditioned"), "indeterminate")
})

test_that("an unregistered strategy aborts (never a silent default)", {
  expect_snapshot(error = TRUE, hd_return_basis_of("Not A Strategy"))
  expect_snapshot(error = TRUE, hd_return_basis_of(NA_character_))
})

test_that("FALSIFICATION: excess-basis strategy has NO rf deducted", {
  rf <- c(0.003, 0.004, 0.002)
  out <- hd_rf_for_basis(rf, "Mom Pre-Peak")
  expect_identical(out, c(0, 0, 0))
  # a total-basis strategy keeps its rf
  expect_identical(hd_rf_for_basis(rf, "Value (HML)"), rf)
  # indeterminate is unchanged legacy behaviour (rf still deducted)
  expect_identical(hd_rf_for_basis(rf, "CMR Conditioned"), rf)
})

test_that("hd_excess_returns subtracts rf only for total basis", {
  ret <- c(0.010, 0.020, -0.010)
  rf  <- c(0.003, 0.004, 0.002)
  expect_equal(hd_excess_returns(ret, rf, "Value (HML)"), ret - rf)
  expect_identical(hd_excess_returns(ret, rf, "Mom Pre-Peak"), ret)
  expect_identical(hd_excess_returns(ret, rf, "CMR Conditioned"), ret)
})

test_that("FALSIFICATION: HML RF-inclusive series is NOT flattered once excess", {
  set.seed(919)
  hml <- rnorm(600, 0.0005, 0.03)
  rf  <- rep(0.004, 600)
  total <- rf + hml
  raw_sr    <- mean(total) / sd(total)
  excess_sr <- mean(hd_excess_returns(total, rf, "Value (HML)")) /
    sd(hd_excess_returns(total, rf, "Value (HML)"))
  # the raw (RF-inclusive) per-period Sharpe is inflated by ~rf/sd
  expect_gt(raw_sr - excess_sr, 0.1)
  expect_equal(excess_sr, mean(hml) / sd(hml), tolerance = 1e-8)
})

test_that("invalid inputs abort with cli errors", {
  expect_snapshot(error = TRUE, hd_rf_for_basis("a", "Value (HML)"))
  expect_snapshot(error = TRUE, hd_excess_returns(c(1, 2), c(1), "Value (HML)"))
  expect_snapshot(error = TRUE, hd_excess_returns(c(1, 2), NULL, "Value (HML)"))
})

test_that("function signatures are stable", {
  expect_snapshot(args(hd_return_basis_of))
  expect_snapshot(args(hd_rf_for_basis))
  expect_snapshot(args(hd_excess_returns))
})
