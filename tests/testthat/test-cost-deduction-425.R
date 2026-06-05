# Tests for transaction-cost deduction (#425)
# Verifies that drif_portfolio, fm_portfolio, and rsc_portfolio correctly
# deduct transaction costs and expose gross_port_ret / net portfolio_ret.
testthat::local_edition(3)

# ── Helper: replicate drif_portfolio cost logic on toy inputs ────────────────

drif_apply_cost <- function(factor_rets_by_month, top_n, cost_per_trade) {
  # factor_rets_by_month: named list of named numeric vectors (month → factor returns)
  # Returns tibble with gross_port_ret, turnover, cost, portfolio_ret (net)
  months <- names(factor_rets_by_month)
  prev_factors <- character(0L)

  results <- lapply(seq_along(months), function(i) {
    m <- months[i]
    current_factors <- names(factor_rets_by_month[[m]])

    n_overlap <- length(intersect(prev_factors, current_factors))
    turnover <- if (length(prev_factors) == 0L) 1.0 else
      1.0 - n_overlap / top_n

    cost <- cost_per_trade * turnover * 2.0
    gross_ret <- mean(factor_rets_by_month[[m]])
    net_ret <- gross_ret - cost

    prev_factors <<- current_factors

    tibble::tibble(
      ym = m,
      gross_port_ret = gross_ret,
      turnover = turnover,
      cost = cost,
      portfolio_ret = net_ret
    )
  })

  dplyr::bind_rows(results)
}

# ── Helper: replicate fm_portfolio cost logic on toy inputs ─────────────────

fm_apply_cost <- function(factor_selections_by_month, factor_rets_by_month,
                          cost_per_trade) {
  # factor_selections_by_month: named list of character vectors (previous-month selection)
  # factor_rets_by_month: named list of numeric vectors (current-month returns)
  months <- names(factor_selections_by_month)
  top_n <- length(factor_selections_by_month[[1]])
  prev_selected <- character(0L)

  results <- lapply(seq_along(months), function(i) {
    m <- months[i]
    selected <- factor_selections_by_month[[m]]

    n_overlap <- length(intersect(prev_selected, selected))
    turnover <- if (length(prev_selected) == 0L) 1.0 else
      1.0 - n_overlap / top_n

    cost <- cost_per_trade * turnover * 2.0
    gross_ret <- mean(factor_rets_by_month[[m]])
    net_ret <- gross_ret - cost

    prev_selected <<- selected

    tibble::tibble(
      ym = m,
      gross_port_ret = gross_ret,
      turnover = turnover,
      cost = cost,
      portfolio_ret = net_ret
    )
  })

  dplyr::bind_rows(results)
}

# ── Helper: replicate rsc_portfolio cost logic on toy inputs ────────────────

rsc_apply_cost <- function(exposure_vec, spy_ret_vec, cost_per_trade) {
  # Returns tibble with gross_ret_strategy, trade_cost, ret_strategy (net)
  n <- length(exposure_vec)
  stopifnot(length(spy_ret_vec) == n)

  exposure_change <- abs(exposure_vec - dplyr::lag(exposure_vec,
    default = exposure_vec[1L]))
  trade_cost <- cost_per_trade * exposure_change * 2.0
  gross_ret <- exposure_vec * spy_ret_vec + (1 - exposure_vec) * 0.0
  net_ret <- gross_ret - trade_cost

  tibble::tibble(
    day = seq_len(n),
    exposure = exposure_vec,
    spy_ret = spy_ret_vec,
    exposure_change = exposure_change,
    trade_cost = trade_cost,
    gross_ret_strategy = gross_ret,
    ret_strategy = net_ret
  )
}

# ── Test 1: drif_portfolio cost deduction ────────────────────────────────────

test_that("drif_portfolio deducts cost per #425 (snapshot)", {
  # Toy: 3 months, top_n=2, cost_per_trade=0.001
  #   Month 1: factors A=0.02, B=0.03 → gross=0.025, first entry turnover=1.0
  #            cost = 0.001 * 1.0 * 2 = 0.002, net = 0.023
  #   Month 2: factors A=0.01, B=0.04 → same 2 factors, no rotation
  #            turnover = 1 - 2/2 = 0, cost = 0, net = gross = 0.025
  #   Month 3: factors C=0.05, D=0.01 → full rotation (0 overlap with A,B)
  #            turnover = 1 - 0/2 = 1.0, cost = 0.002, net = 0.03 - 0.002 = 0.028

  factor_rets <- list(
    "2024-01" = c(A = 0.02, B = 0.03),
    "2024-02" = c(A = 0.01, B = 0.04),
    "2024-03" = c(C = 0.05, D = 0.01)
  )

  result <- drif_apply_cost(factor_rets, top_n = 2L, cost_per_trade = 0.001)

  # Verify hand-derived values
  expect_equal(result$gross_port_ret[1], 0.025)
  expect_equal(result$turnover[1], 1.0)
  expect_equal(result$cost[1], 0.002)
  expect_equal(result$portfolio_ret[1], 0.023)

  expect_equal(result$turnover[2], 0.0)   # no rotation
  expect_equal(result$cost[2], 0.0)
  expect_equal(result$portfolio_ret[2], result$gross_port_ret[2])

  expect_equal(result$turnover[3], 1.0)   # full rotation
  expect_equal(result$portfolio_ret[3], result$gross_port_ret[3] - 0.002)

  # Snapshot: catches format and column drift
  expect_snapshot(print(result, n = Inf))
})

# ── Test 2: fm_portfolio cost deduction ─────────────────────────────────────

test_that("fm_portfolio deducts cost per #425 (snapshot)", {
  # Toy: 3 trade months, top_n=2, cost_per_trade=0.001
  # Previous-month MAX selections drive the entry; current-month returns are earned
  #   Month 1: prev selected HML,SMB → gross = (0.02+0.03)/2 = 0.025
  #            first trade → turnover=1, cost=0.002, net=0.023
  #   Month 2: prev selected HML,SMB → no change → turnover=0, cost=0, net=gross
  #   Month 3: prev selected RMW,CMA → full rotation vs HML,SMB
  #            turnover=1, cost=0.002, net = gross - 0.002

  selections <- list(
    "2024-02" = c("HML", "SMB"),
    "2024-03" = c("HML", "SMB"),
    "2024-04" = c("RMW", "CMA")
  )
  factor_rets <- list(
    "2024-02" = c(HML = 0.02, SMB = 0.03),
    "2024-03" = c(HML = 0.01, SMB = 0.04),
    "2024-04" = c(RMW = 0.05, CMA = 0.01)
  )

  result <- fm_apply_cost(selections, factor_rets, cost_per_trade = 0.001)

  expect_equal(result$turnover[1], 1.0)
  expect_equal(result$portfolio_ret[1], 0.025 - 0.002)
  expect_equal(result$turnover[2], 0.0)
  expect_equal(result$portfolio_ret[2], result$gross_port_ret[2])
  expect_equal(result$turnover[3], 1.0)
  expect_equal(result$portfolio_ret[3], result$gross_port_ret[3] - 0.002)

  expect_snapshot(print(result, n = Inf))
})

# ── Test 3: rsc_portfolio cost deduction ────────────────────────────────────

test_that("rsc_portfolio deducts cost on exposure changes per #425 (snapshot)", {
  # Toy: 5 days, cost_per_trade=0.0005
  # Day 1: exposure=1.0 (benign) → lag = itself (default) → change=0, cost=0
  # Day 2: exposure=1.0 → change=0, cost=0
  # Day 3: exposure=0.5 (cautious) → change=0.5, cost=0.0005*0.5*2=0.0005
  # Day 4: exposure=0.1 (hostile) → change=0.4, cost=0.0005*0.4*2=0.0004
  # Day 5: exposure=1.0 (back to benign) → change=0.9, cost=0.0005*0.9*2=0.0009

  exposure_vec <- c(1.0, 1.0, 0.5, 0.1, 1.0)
  spy_ret_vec  <- c(0.01, 0.005, -0.02, -0.03, 0.015)

  result <- rsc_apply_cost(exposure_vec, spy_ret_vec, cost_per_trade = 0.0005)

  # Days with no regime switch: cost = 0
  expect_equal(result$trade_cost[1], 0.0)  # first day: lag = itself (default)
  expect_equal(result$trade_cost[2], 0.0)

  # Day 3: switch from 1.0 to 0.5 → |delta| = 0.5 → cost = 0.0005
  expect_equal(result$trade_cost[3], 0.0005, tolerance = 1e-10)

  # Day 4: switch from 0.5 to 0.1 → |delta| = 0.4 → cost = 0.0004
  expect_equal(result$trade_cost[4], 0.0004, tolerance = 1e-10)

  # Net return < gross return on switch days
  expect_lt(result$ret_strategy[3], result$gross_ret_strategy[3])
  expect_lt(result$ret_strategy[4], result$gross_ret_strategy[4])

  # Net return = gross return on no-switch days
  expect_equal(result$ret_strategy[2], result$gross_ret_strategy[2])

  expect_snapshot(print(result, n = Inf))
})
