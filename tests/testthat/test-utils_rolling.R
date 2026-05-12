testthat::local_edition(3)
source(here::here("R/utils_rolling.R"))

# ── Length preservation ───────────────────────────────────────────────────────

test_that("roll_mean_safe preserves vector length", {
  x <- 1:100
  expect_length(roll_mean_safe(x, n = 10), 100L)
})

test_that("roll_sd_safe preserves vector length", {
  x <- 1:100
  expect_length(roll_sd_safe(x, n = 10), 100L)
})

test_that("roll_quantile_safe preserves vector length", {
  x <- 1:100
  expect_length(roll_quantile_safe(x, n = 10, probs = 0.5), 100L)
})

# ── Correctness on clean data ─────────────────────────────────────────────────

test_that("roll_mean_safe matches manual rolling mean on clean data", {
  x <- as.numeric(1:20)
  result <- roll_mean_safe(x, n = 5, min_frac = 0.01)
  # Right-aligned window of 5: position 5 = mean(1:5), position 6 = mean(2:6), ...
  manual <- vapply(5:20, function(i) mean(x[(i - 4):i]), numeric(1))
  expect_equal(result[5:20], manual, tolerance = 1e-10)
})

test_that("roll_quantile_safe median matches manual at position 5", {
  # median(1:5) = 3
  result <- roll_quantile_safe(1:10, n = 5, probs = 0.5, min_frac = 0.01)
  expect_equal(result[5], 3)
})

# ── NA handling: sparse NAs — helper produces fewer NAs than RcppRoll ─────────

test_that("roll_mean_safe produces fewer NAs than RcppRoll on sparse-NA data", {
  set.seed(42)
  x <- rnorm(100)
  na_positions <- sample(100, 5)
  x[na_positions] <- NA

  result_safe <- roll_mean_safe(x, n = 10, min_frac = 0.5)

  # RcppRoll::roll_mean returns NA for any window touching an NA
  # We simulate that behaviour: a window of 10 from position i covers i-9:i
  rcpproll_na <- vapply(seq_along(x), function(i) {
    window <- x[max(1, i - 9):i]
    if (any(is.na(window))) NA_real_ else mean(window)
  }, numeric(1))

  n_na_safe <- sum(is.na(result_safe))
  n_na_rcpp <- sum(is.na(rcpproll_na))

  # The whole point: safe helper produces fewer NAs
  expect_lt(n_na_safe, n_na_rcpp)
  # And the non-NA positions are numeric
  expect_true(all(is.numeric(result_safe[!is.na(result_safe)])))
})

# ── NA gate fires at threshold ────────────────────────────────────────────────

test_that("roll_mean_safe returns NA when non-NA fraction is below min_frac", {
  # Positions 1-9 are NA, position 10 is 1.0 → only 1/10 non-NA = 10%
  x <- c(rep(NA_real_, 9), 1.0)

  # min_frac = 0.5 → requires ceiling(0.5 * 10) = 5 non-NA values → gate fires
  result_50 <- roll_mean_safe(x, n = 10, min_frac = 0.5)
  expect_true(is.na(result_50[10]))

  # min_frac = 0.1 → requires ceiling(0.1 * 10) = 1 non-NA value → gate passes
  result_10 <- roll_mean_safe(x, n = 10, min_frac = 0.1)
  expect_equal(result_10[10], 1.0)
})

# ── No look-ahead ─────────────────────────────────────────────────────────────

test_that("roll_mean_safe at position 3 uses only x[1:3] (right-aligned)", {
  # x[4] and x[5] are large; if look-ahead occurred, position 3 would be inflated
  x <- c(1, 2, 3, 1000, 1000)
  result <- roll_mean_safe(x, n = 3, min_frac = 0.01)
  expect_equal(result[3], mean(c(1, 2, 3)))
})

# ── Edge: all-NA window ───────────────────────────────────────────────────────

test_that("roll_mean_safe returns NA for all-NA window without error", {
  x <- c(NA_real_, NA_real_, NA_real_, NA_real_, NA_real_)
  result <- roll_mean_safe(x, n = 3, min_frac = 0.01)
  expect_true(all(is.na(result)))
})

# ── Edge: n = 1 ───────────────────────────────────────────────────────────────

test_that("roll_mean_safe with n = 1 returns x unchanged", {
  x <- c(1, NA, 3, 4, NA)
  result <- roll_mean_safe(x, n = 1, min_frac = 0.5)
  # With n = 1, min_obs = ceiling(0.5 * 1) = 1; NA positions have 0 non-NA so
  # still return NA, non-NA positions return themselves
  expect_equal(result[!is.na(x)], x[!is.na(x)])
  expect_true(all(is.na(result[is.na(x)])))
})

# ── Edge: n > length(x) ───────────────────────────────────────────────────────

test_that("roll_mean_safe handles n > length(x) without error", {
  x <- c(1, 2, 3)
  # .complete = FALSE means partial windows are allowed; result is numeric length 3
  result <- roll_mean_safe(x, n = 10, min_frac = 0.01)
  expect_length(result, 3L)
  # No position has 10 obs, but all have >=1 (min_obs=1); each uses available obs
  expect_false(any(is.na(result)))
})

# ── Input validation: snapshot error messages ─────────────────────────────────

test_that("roll_mean_safe errors with cli_abort on negative n", {
  expect_snapshot(
    error = TRUE,
    roll_mean_safe(1:10, n = -1)
  )
})

test_that("roll_mean_safe errors with cli_abort on min_frac > 1", {
  expect_snapshot(
    error = TRUE,
    roll_mean_safe(1:10, n = 5, min_frac = 1.5)
  )
})

test_that("roll_quantile_safe errors with cli_abort on probs > 1", {
  expect_snapshot(
    error = TRUE,
    roll_quantile_safe(1:10, n = 5, probs = 1.5)
  )
})

# ── SD correctness ────────────────────────────────────────────────────────────

test_that("roll_sd_safe matches base sd on clean data at full windows", {
  x <- as.numeric(1:20)
  result <- roll_sd_safe(x, n = 5, min_frac = 0.01)
  # Position 5: sd(1:5)
  expect_equal(result[5], stats::sd(1:5), tolerance = 1e-10)
  # Position 10: sd(6:10)
  expect_equal(result[10], stats::sd(6:10), tolerance = 1e-10)
})
