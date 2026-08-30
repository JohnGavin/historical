# Tests for hd_sharpe_haircut() — Harvey-Liu multiple-testing haircut (#490 Gap 1)
#
# hd_sharpe_haircut() is a second, independent view of the same question
# hd_deflated_sharpe() answers via Lopez de Prado's Deflated Sharpe Ratio: how
# much of a reported Sharpe survives once the number of strategies tried is
# accounted for. It converts the Sharpe to a two-sided normal p-value, applies
# one of three named multiple-testing corrections (Bonferroni / Holm / BHY)
# via stats::p.adjust(), and reports the Sharpe ratio implied by the adjusted
# p-value.
#
# Key algebraic facts these tests pin down:
#  - n_tests = 1 is a no-op REGARDLESS of rho or method: M_eff = 1, and
#    p.adjust() with n = 1 on a length-1 p-value is the identity for all
#    three methods, so haircut_sharpe reproduces sharpe EXACTLY (not just
#    approximately) -- the two-sided normal inversion round-trips exactly.
#  - bonferroni and holm are IDENTICAL for a single p-value (Holm's step-down
#    only differs from Bonferroni across a full vector of p-values, which
#    this scalar-summary function never has).
#  - bhy (Benjamini-Yekutieli) is MORE conservative than bonferroni/holm for
#    M_eff > 1 (extra harmonic-sum factor >= 1), so it must haircut at least
#    as hard.
#  - rho shrinks the effective test count: rho = 0 gives M_eff = n_tests
#    (independent); rho -> 1 drives M_eff -> 1 (fully redundant, haircut
#    vanishes).

test_that("n_tests = 1 reproduces sharpe exactly, for every rho and method", {
  for (rho in c(0, 0.3, 0.7, 0.99)) {
    for (method in c("bonferroni", "holm", "bhy")) {
      out <- hd_sharpe_haircut(
        sharpe = 0.85, n_tests = 1, rho = rho, T_obs = 240,
        ann_factor = 252L, method = method
      )
      expect_equal(out$haircut_sharpe, 0.85, tolerance = 1e-8)
      expect_equal(out$M_eff, 1)
    }
  }
})

test_that("bonferroni and holm are identical for a single reported Sharpe", {
  out_b <- hd_sharpe_haircut(
    sharpe = 1.2, n_tests = 20, rho = 0.2, T_obs = 120,
    ann_factor = 12L, method = "bonferroni"
  )
  out_h <- hd_sharpe_haircut(
    sharpe = 1.2, n_tests = 20, rho = 0.2, T_obs = 120,
    ann_factor = 12L, method = "holm"
  )
  expect_equal(out_b$haircut_sharpe, out_h$haircut_sharpe, tolerance = 1e-10)
  expect_equal(out_b$p_value_adj, out_h$p_value_adj, tolerance = 1e-10)
})

test_that("bhy is at least as conservative as bonferroni/holm when M_eff > 1", {
  out_bonf <- hd_sharpe_haircut(
    sharpe = 1.1, n_tests = 50, rho = 0, T_obs = 300,
    ann_factor = 252L, method = "bonferroni"
  )
  out_bhy <- hd_sharpe_haircut(
    sharpe = 1.1, n_tests = 50, rho = 0, T_obs = 300,
    ann_factor = 252L, method = "bhy"
  )
  expect_gte(out_bhy$p_value_adj, out_bonf$p_value_adj)
  expect_lte(abs(out_bhy$haircut_sharpe), abs(out_bonf$haircut_sharpe))
  expect_gte(out_bhy$haircut_pct, out_bonf$haircut_pct)
})

test_that("rho = 0 gives M_eff = n_tests; rho -> 1 drives M_eff -> 1", {
  out_indep <- hd_sharpe_haircut(
    sharpe = 0.9, n_tests = 30, rho = 0, T_obs = 200, ann_factor = 252L, method = "bhy"
  )
  expect_equal(out_indep$M_eff, 30)

  out_redundant <- hd_sharpe_haircut(
    sharpe = 0.9, n_tests = 30, rho = 0.999, T_obs = 200, ann_factor = 252L, method = "bhy"
  )
  expect_equal(out_redundant$M_eff, 1, tolerance = 1e-2)
  # Near-total redundancy: haircut should nearly vanish (M_eff ~ 1).
  expect_equal(out_redundant$haircut_sharpe, 0.9, tolerance = 1e-2)
})

test_that("larger n_tests (fixed rho) haircuts the Sharpe monotonically harder", {
  ns <- c(1, 5, 20, 100, 500)
  haircuts <- vapply(ns, function(n) {
    hd_sharpe_haircut(
      sharpe = 1.0, n_tests = n, rho = 0.1, T_obs = 240,
      ann_factor = 252L, method = "bhy"
    )$haircut_sharpe
  }, numeric(1))
  # Non-increasing in magnitude as the family grows.
  expect_true(all(diff(abs(haircuts)) <= 1e-8))
})

test_that("negative sharpe is haircut symmetrically (sign preserved)", {
  pos <- hd_sharpe_haircut(
    sharpe = 0.8, n_tests = 40, rho = 0.1, T_obs = 200, ann_factor = 252L, method = "bhy"
  )
  neg <- hd_sharpe_haircut(
    sharpe = -0.8, n_tests = 40, rho = 0.1, T_obs = 200, ann_factor = 252L, method = "bhy"
  )
  expect_equal(neg$haircut_sharpe, -pos$haircut_sharpe, tolerance = 1e-10)
  expect_equal(neg$p_value, pos$p_value, tolerance = 1e-10)
})

test_that("sharpe near zero gives NA haircut_pct, matching hd_deflated_sharpe's convention", {
  out <- hd_sharpe_haircut(
    sharpe = 0.0001, n_tests = 10, rho = 0.1, T_obs = 100, ann_factor = 252L, method = "bhy"
  )
  expect_true(is.na(out$haircut_pct))
})

test_that("echoed inputs are returned unchanged", {
  out <- hd_sharpe_haircut(
    sharpe = 0.7, n_tests = 12, rho = 0.25, T_obs = 150,
    ann_factor = 12L, method = "holm"
  )
  expect_identical(out$n_tests, 12)
  expect_identical(out$rho, 0.25)
  expect_identical(out$method, "holm")
  expect_identical(out$T_obs, 150)
})

test_that("input validation: invalid sharpe aborts with informative message", {
  expect_snapshot(error = TRUE, hd_sharpe_haircut(NA_real_, n_tests = 5, rho = 0.1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(Inf, n_tests = 5, rho = 0.1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(c(0.1, 0.2), n_tests = 5, rho = 0.1, T_obs = 100))
})

test_that("input validation: invalid n_tests aborts with informative message", {
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 0, rho = 0.1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = NA_real_, rho = 0.1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = -1, rho = 0.1, T_obs = 100))
})

test_that("input validation: invalid rho aborts with informative message", {
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = -0.1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = 1, T_obs = 100))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = NA_real_, T_obs = 100))
})

test_that("input validation: invalid T_obs aborts with informative message", {
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = 1))
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = NA_real_))
})

test_that("input validation: invalid ann_factor aborts with informative message", {
  expect_snapshot(error = TRUE, hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = 100, ann_factor = 0))
})

test_that("invalid method aborts via match.arg", {
  expect_error(
    hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = 100, method = "sidak"),
    "should be one of"
  )
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_sharpe_haircut))
})
