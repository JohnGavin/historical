# Tests for hd_simulate_paths() — Phase C of issue #389
#
# Parametric tests use toy 2x2 mu + Sigma so no database is needed.
# Bootstrap tests use a toy 24-row data frame with date + 2 asset columns.

# ---- helpers ----------------------------------------------------------------

make_mu <- function() c(A = 0.07, B = 0.05)

make_sigma <- function() {
  matrix(
    c(0.04, 0.01,
      0.01, 0.02),
    nrow = 2L, ncol = 2L,
    dimnames = list(c("A", "B"), c("A", "B"))
  )
}

make_returns_wide <- function(n = 24L) {
  set.seed(1L)
  tibble::tibble(
    date = seq(as.Date("2020-01-01"), by = "month", length.out = n),
    A    = rnorm(n, mean = 0.005, sd = 0.04),
    B    = rnorm(n, mean = 0.003, sd = 0.03)
  )
}

# ---- schema -----------------------------------------------------------------

test_that("output has 7 columns with correct names (parametric)", {
  result <- hd_simulate_paths(
    n_paths       = 5L,
    horizon_years = 3L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    seed          = 1L
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(ncol(result), 7L)
  expect_equal(
    colnames(result),
    c("path_id", "year", "asset", "return_nominal", "return_real", "cum_nominal", "cum_real")
  )
})

# ---- row count --------------------------------------------------------------

test_that("nrow equals n_paths * horizon_years * n_assets", {
  result <- hd_simulate_paths(
    n_paths       = 5L,
    horizon_years = 3L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    seed          = 1L
  )

  expect_equal(nrow(result), 5L * 3L * 2L)  # 30 rows
})

# ---- cumulative monotonicity ------------------------------------------------

test_that("cum_nominal at year=2 equals (1+r1)*(1+r2) for a single path-asset pair", {
  result <- hd_simulate_paths(
    n_paths       = 1L,
    horizon_years = 3L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    seed          = 99L
  )

  path_a <- result[result$path_id == 1L & result$asset == "A", ]
  path_a <- path_a[order(path_a$year), ]

  r1 <- path_a$return_nominal[1L]
  r2 <- path_a$return_nominal[2L]

  expect_equal(
    path_a$cum_nominal[2L],
    (1 + r1) * (1 + r2),
    tolerance = 1e-10
  )
})

# ---- bootstrap schema -------------------------------------------------------

test_that("bootstrap output has same schema and row count as parametric", {
  rw <- make_returns_wide()

  result <- hd_simulate_paths(
    n_paths        = 5L,
    horizon_years  = 3L,
    assets         = c("A", "B"),
    method         = "bootstrap",
    block_size     = 6L,
    .returns_wide  = rw,
    seed           = 1L
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(ncol(result), 7L)
  expect_equal(
    colnames(result),
    c("path_id", "year", "asset", "return_nominal", "return_real", "cum_nominal", "cum_real")
  )
  expect_equal(nrow(result), 5L * 3L * 2L)
})

# ---- error: missing .returns_wide for bootstrap -----------------------------

test_that("bootstrap without .returns_wide aborts with informative message", {
  expect_snapshot(
    error = TRUE,
    hd_simulate_paths(
      n_paths       = 3L,
      horizon_years = 2L,
      assets        = c("A", "B"),
      method        = "bootstrap"
    )
  )
})

# ---- error: asset not in .returns_wide --------------------------------------

test_that("asset absent from .returns_wide aborts with informative message", {
  rw <- make_returns_wide()

  expect_snapshot(
    error = TRUE,
    hd_simulate_paths(
      n_paths       = 3L,
      horizon_years = 2L,
      assets        = c("A", "X_MISSING"),
      method        = "parametric",
      mu            = c(A = 0.07, X_MISSING = 0.05),
      Sigma         = make_sigma(),
      .returns_wide = rw
    )
  )
})

# ---- error: non-positive n_paths --------------------------------------------

test_that("non-positive n_paths aborts with informative message", {
  expect_snapshot(
    error = TRUE,
    hd_simulate_paths(
      n_paths       = 0L,
      horizon_years = 2L,
      assets        = c("A", "B"),
      mu            = make_mu(),
      Sigma         = make_sigma()
    )
  )
})

# ---- function signature snapshot --------------------------------------------

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_simulate_paths))
})

# ---- seed reproducibility ---------------------------------------------------

test_that("same seed yields identical draws (parametric)", {
  res1 <- hd_simulate_paths(
    n_paths       = 10L,
    horizon_years = 5L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    seed          = 7L
  )
  res2 <- hd_simulate_paths(
    n_paths       = 10L,
    horizon_years = 5L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    seed          = 7L
  )
  expect_equal(res1, res2)
})

# ---- mu estimation from .returns_wide ---------------------------------------

test_that("mu estimated from .returns_wide when mu=NULL", {
  rw <- make_returns_wide()

  result <- hd_simulate_paths(
    n_paths       = 4L,
    horizon_years = 2L,
    assets        = c("A", "B"),
    Sigma         = make_sigma(),
    mu            = NULL,
    method        = "parametric",
    .returns_wide = rw,
    seed          = 1L
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 4L * 2L * 2L)
  expect_false(anyNA(result$return_nominal))
})

# ---- Phase E: CPI bootstrap ------------------------------------------------

test_that("bootstrapped CPI changes return_real relative to constant-CPI baseline", {
  set.seed(42L)
  cpi_monthly <- rnorm(120L, mean = 0.003, sd = 0.001)  # 10yr of monthly CPI

  # constant CPI baseline
  res_const <- hd_simulate_paths(
    n_paths       = 10L,
    horizon_years = 5L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    cpi_annual_rate = 0.03,
    seed          = 1L
  )

  # bootstrapped CPI (same seed — note: CPI bootstrap consumes RNG before
  # return draws, so nominal returns will differ; that's expected behaviour)
  res_boot <- hd_simulate_paths(
    n_paths       = 10L,
    horizon_years = 5L,
    assets        = c("A", "B"),
    mu            = make_mu(),
    Sigma         = make_sigma(),
    method        = "parametric",
    .cpi_monthly  = cpi_monthly,
    seed          = 1L
  )

  # schema and row count are identical in both cases
  expect_equal(ncol(res_const), ncol(res_boot))
  expect_equal(nrow(res_const), nrow(res_boot))
  expect_equal(colnames(res_const), colnames(res_boot))

  # real returns differ because CPI rates differ from 0.03 constant
  expect_false(isTRUE(all.equal(res_const$return_real, res_boot$return_real)))

  # no NAs introduced by the bootstrapped CPI path
  expect_false(anyNA(res_boot$return_real))
  expect_false(anyNA(res_boot$cum_real))
})

test_that(".cpi_monthly non-numeric aborts with informative message", {
  expect_snapshot(
    error = TRUE,
    hd_simulate_paths(
      n_paths       = 3L,
      horizon_years = 2L,
      assets        = c("A", "B"),
      mu            = make_mu(),
      Sigma         = make_sigma(),
      .cpi_monthly  = "not_numeric"
    )
  )
})
