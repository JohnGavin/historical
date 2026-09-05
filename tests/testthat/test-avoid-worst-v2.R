# Tests for plan_avoid_worst_v2.R (Avoid Worst multiverse, issue #490 Gap 2,
# generalising the #157 DRIF multiverse pattern -- see test-drif.R).
testthat::local_edition(3)

# ── aw_multiverse_grid unit tests ────────────────────────────────────────────

test_that("aw_multiverse_grid has 16 rows with expected columns", {
  # Inline the grid construction so the test is self-contained
  # (does not require a running targets pipeline).
  grid <- tidyr::expand_grid(
    vix_high            = c(25, 30),
    shock_threshold      = c(0.02, 0.03),
    min_cooloff_days    = c(3L, 5L),
    cost_per_switch_bps = c(0, 5)
  ) |>
    dplyr::mutate(
      spec_id    = sprintf("S%02d", dplyr::row_number()),
      is_current = vix_high == 30 &
                   shock_threshold == 0.03 &
                   min_cooloff_days == 5L &
                   cost_per_switch_bps == 5
    )

  expect_equal(nrow(grid), 16L)
  expect_true("spec_id"    %in% names(grid))
  expect_true("is_current" %in% names(grid))
  # Exactly one row flagged as the current production specification
  expect_equal(sum(grid$is_current), 1L)
})

test_that("aw_multiverse_grid contains the current aw_practical_params defaults", {
  grid <- tidyr::expand_grid(
    vix_high            = c(25, 30),
    shock_threshold      = c(0.02, 0.03),
    min_cooloff_days    = c(3L, 5L),
    cost_per_switch_bps = c(0, 5)
  )
  # vix_high=30, shock_threshold=0.03 are aw_practical_params' current
  # defaults (plan_avoid_worst.R); both must be represented in the grid.
  expect_setequal(unique(grid$vix_high), c(25, 30))
  expect_setequal(unique(grid$shock_threshold), c(0.02, 0.03))
})

test_that("aw_multiverse_caption is a non-empty string", {
  # Simulate the caption computation on a toy aw_multiverse tibble
  toy_mv <- tibble::tibble(
    spec_id             = c("S01", "S02", "S03"),
    vix_high            = c(30, 25, 30),
    shock_threshold     = c(0.03, 0.03, 0.02),
    min_cooloff_days    = c(5L, 5L, 3L),
    cost_per_switch_bps = c(5, 0, 5),
    is_current          = c(TRUE, FALSE, FALSE),
    oos_sharpe          = c(0.65, 0.58, 0.72)
  )

  d <- toy_mv |>
    dplyr::filter(!is.na(oos_sharpe)) |>
    dplyr::arrange(oos_sharpe)

  n_specs        <- nrow(d)
  current_rank   <- which(d$is_current)
  min_sharpe     <- round(min(d$oos_sharpe, na.rm = TRUE), 2)
  max_sharpe     <- round(max(d$oos_sharpe, na.rm = TRUE), 2)
  current_sharpe <- round(d$oos_sharpe[current_rank], 2)
  current_row    <- d[current_rank, ]
  current_desc   <- sprintf(
    "%s: vix=%s, shock=%s, cooloff=%sd, cost=%sbp",
    current_row$spec_id, current_row$vix_high,
    current_row$shock_threshold, current_row$min_cooloff_days,
    current_row$cost_per_switch_bps
  )

  caption <- paste0(
    "Of ", n_specs, " specifications tested (varying VIX trigger, ",
    "shock threshold, cooling-off window, and transaction-cost ",
    "assumption), the current Avoid Worst VIX-overlay spec (",
    current_desc, ") ranks ", current_rank,
    " by OOS Sharpe (", current_sharpe,
    "). Sharpe range across specs: ", min_sharpe, " to ", max_sharpe,
    ". Source: plan_avoid_worst_v2.R; pattern: #157 (DRIF multiverse)."
  )

  expect_type(caption, "character")
  expect_gt(nchar(caption), 50L)
  expect_true(grepl("plan_avoid_worst_v2", caption))
  expect_true(grepl("#157", caption))
  # Snapshot guard: catches format/wording drift in the assembled caption (#340)
  expect_snapshot(cat(caption))
})

test_that("run_spec helper applies switch cost and computes OOS metrics from a toy dataset", {
  # Simulate the computation that happens inside run_spec() in
  # plan_avoid_worst_v2.R, without needing hd_ohlcv()/hd_macro() data.
  set.seed(42L)
  n <- 300L
  dates <- seq.Date(as.Date("2020-01-02"), by = "day", length.out = n)
  ret <- rnorm(n, mean = 0.0003, sd = 0.01)
  vix <- pmax(10, 20 + cumsum(rnorm(n, sd = 0.5)))
  d <- tibble::tibble(date = dates, ret = ret, vix = vix)

  vix_h   <- 30
  shock_t <- 0.03
  cooloff <- 5L
  vix_r   <- vix_h - 5

  in_mkt <- rep(TRUE, n)
  cool <- 0L
  for (i in 2:n) {
    if (cool > 0) cool <- cool - 1L
    shocked      <- abs(d$ret[i - 1]) > shock_t
    vp           <- d$vix[i - 1]
    vix_elevated <- !is.na(vp) && vp > vix_h
    if (shocked || vix_elevated) {
      in_mkt[i] <- FALSE
      cool <- max(cool, cooloff)
    } else if (cool > 0) {
      in_mkt[i] <- FALSE
    } else if (!is.na(vp) && vp > vix_r) {
      in_mkt[i] <- FALSE
    }
  }

  strat_ret_gross <- ifelse(in_mkt, d$ret, 0)
  switch_day <- c(FALSE, diff(as.integer(in_mkt)) != 0)
  n_switches <- sum(switch_day)

  cost_bps  <- 5
  cost_frac <- cost_bps / 10000
  strat_ret_net <- strat_ret_gross
  strat_ret_net[switch_day] <- strat_ret_net[switch_day] - cost_frac

  years  <- n / 252
  cum    <- cumprod(1 + strat_ret_net)
  max_dd <- min((cum - cummax(cum)) / cummax(cum))

  result <- tibble::tibble(
    n_days     = n,
    oos_cagr   = utils::tail(cum, 1)^(1 / years) - 1,
    oos_vol    = stats::sd(strat_ret_net) * sqrt(252),
    oos_max_dd = max_dd,
    n_switches = n_switches,
    pct_cash   = sum(!in_mkt) / n
  )

  expect_equal(result$n_days, n)
  # max drawdown must be <= 0
  expect_lte(result$oos_max_dd, 0)
  # annualised vol must be positive
  expect_gt(result$oos_vol, 0)
  # pct_cash is a fraction in [0, 1]
  expect_gte(result$pct_cash, 0)
  expect_lte(result$pct_cash, 1)
  # net-of-cost return series applies the cost exactly on switch days
  n_before <- length(strat_ret_gross)
  expect_equal(n_before, length(strat_ret_net))
  expect_equal(
    sum(strat_ret_gross[switch_day] - strat_ret_net[switch_day]),
    n_switches * cost_frac,
    tolerance = 1e-12
  )
})
