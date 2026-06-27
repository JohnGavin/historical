testthat::local_edition(3)

# Tests for cov-routing (#498 Phase 2) — behaviour-preserving regression guards.
#
# These tests verify that:
#   1. COV_METHOD defaults to "sample" and COV_LW_TARGET defaults to "const_cor"
#      (guards against accidental flip of the default).
#   2. hd_cov_estimate(X, method = "sample") produces values equal to
#      stats::cov(X, use = "complete.obs") — i.e. the substitution is a no-op.
#   3. The routed result is symmetric and matches the legacy expression on
#      a representative complete frame.
#
# Per snapshot-test-policy: these are algorithmic tests (expected values can
# be hand-derived or trivially computed from the same inputs). No snapshots
# are needed or added here.
#
# hd_cov_estimate() is in the historicaldata package; the package is loaded
# via pkgload::load_all() in this project's docs/_targets.R, but here we
# load it directly.

# ── Package setup ──────────────────────────────────────────────────────────────

# Source hd_cov_estimate() directly from cov_estimate.R.
# pkgload::load_all(historicaldata) fails in this test env because duckplyr
# is not installed, but hd_cov_estimate() only depends on cli, rlang, and
# stats — all of which are available. Sourcing the file directly avoids the
# full-package import check while still exercising the exact function being routed.
source(here::here("packages/historicaldata/R/cov_estimate.R"))

# Source the config constants from R/cov_config.R.
# (When running via test_dir() this file is not auto-sourced.)
source(here::here("R/cov_config.R"))

# ── Fixtures ───────────────────────────────────────────────────────────────────

make_complete_matrix <- function(n = 60L, p = 4L, seed = 42L) {
  set.seed(seed)
  m <- matrix(rnorm(n * p), nrow = n, ncol = p)
  colnames(m) <- paste0("A", seq_len(p))
  m
}

# ============================================================================
# Guard 1: default constants
# ============================================================================

test_that("COV_METHOD is 'sample' (Phase 2 default; Phase 3 will flip to ledoit_wolf)", {
  expect_equal(COV_METHOD, "sample",
               info = paste0(
                 "COV_METHOD must be 'sample' in Phase 2. ",
                 "Changing it now would alter deployed numbers. ",
                 "Phase 3 flip requires OOS diagnostic (#498)."
               ))
})

test_that("COV_LW_TARGET is 'const_cor' (used only when COV_METHOD == 'ledoit_wolf')", {
  expect_equal(COV_LW_TARGET, "const_cor",
               info = "COV_LW_TARGET default is 'const_cor'; only active when COV_METHOD == 'ledoit_wolf'.")
})

# ============================================================================
# Guard 2: numerical equivalence — hd_cov_estimate("sample") == stats::cov()
# ============================================================================

test_that("hd_cov_estimate(method='sample') values equal stats::cov(use='complete.obs')", {
  X <- make_complete_matrix(n = 60L, p = 4L)

  routed <- hd_cov_estimate(X, method = "sample", lw_target = "const_cor")
  legacy <- stats::cov(X, use = "complete.obs")

  # Values are bit-identical up to floating-point tolerance (ignore extra attrs)
  expect_equal(routed, legacy,
               ignore_attr = TRUE,
               tolerance   = 1e-14,
               info        = paste0(
                 "hd_cov_estimate(method='sample') must be numerically ",
                 "identical to stats::cov(use='complete.obs')."
               ))
})

test_that("hd_cov_estimate(method='sample') values equal stats::cov() on larger matrix", {
  X <- make_complete_matrix(n = 120L, p = 4L, seed = 99L)

  routed <- hd_cov_estimate(X, method = "sample", lw_target = "const_cor")
  legacy <- stats::cov(X, use = "complete.obs")

  expect_equal(routed, legacy,
               ignore_attr = TRUE,
               tolerance   = 1e-14,
               info        = "Equivalence must hold regardless of n.")
})

# ============================================================================
# Guard 3: symmetry and regression guard for the routed result
# ============================================================================

test_that("hd_cov_estimate(method='sample') returns a symmetric matrix", {
  X      <- make_complete_matrix(n = 80L, p = 4L)
  routed <- hd_cov_estimate(X, method = "sample", lw_target = "const_cor")

  expect_equal(routed, t(routed),
               ignore_attr = TRUE,
               tolerance   = 1e-12,
               info        = "Routed covariance matrix must be symmetric.")
})

test_that("hd_cov_estimate(method='sample') matches legacy cov_annual expression (annualised)", {
  # Reproduce the cov_annual target logic: Sigma_annual = 12 * (Sigma_m + t(Sigma_m)) / 2
  X <- make_complete_matrix(n = 80L, p = 4L)

  # Legacy path (what was in plan_returns.R before Phase 2)
  Sigma_m_legacy   <- stats::cov(X, use = "complete.obs")
  Sigma_ann_legacy <- 12L * ((Sigma_m_legacy + t(Sigma_m_legacy)) / 2)

  # Routed path (Phase 2)
  Sigma_m_routed   <- hd_cov_estimate(X, method = COV_METHOD, lw_target = COV_LW_TARGET)
  Sigma_ann_routed <- 12L * ((Sigma_m_routed + t(Sigma_m_routed)) / 2)

  expect_equal(Sigma_ann_routed, Sigma_ann_legacy,
               ignore_attr = TRUE,
               tolerance   = 1e-14,
               info        = paste0(
                 "Phase 2 routing must produce identical annualised covariance. ",
                 "If this fails, COV_METHOD is not 'sample' or hd_cov_estimate ",
                 "changed its 'sample' implementation."
               ))
})

test_that("only changing COV_METHOD would alter deployed numbers (Phase 3 guard)", {
  # When COV_METHOD != "sample", the routed result DIFFERS from the legacy path.
  # This test documents (and tests) the change that Phase 3 will introduce.
  X <- make_complete_matrix(n = 80L, p = 4L)

  legacy <- stats::cov(X, use = "complete.obs")
  lw     <- hd_cov_estimate(X, method = "ledoit_wolf", lw_target = "const_cor")

  # ledoit_wolf != sample (shrinks off-diagonal elements)
  expect_false(isTRUE(all.equal(lw, legacy, ignore_attr = TRUE, tolerance = 1e-10)),
               info = paste0(
                 "ledoit_wolf result must differ from sample result (Ledoit-Wolf shrinks). ",
                 "Confirms that flipping COV_METHOD to 'ledoit_wolf' WILL change deployed numbers."
               ))
})
