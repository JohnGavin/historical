testthat::local_edition(3)
# #567: ONE cost per strategy on the leaderboard.
#
# Before: the leaderboard subtracted its own measured-turnover cost from series
# that were ALREADY net of the strategy's own internal cost (Stock MAX deducts
# ~1.85%/month inside portfolio_longshort(), then the leaderboard deducted
# ~2.25% on top). Now: where a gross series exists the leaderboard cost REPLACES
# the internal one (it is applied to the GROSS series); where only a net series
# exists the internal cost is kept and the leaderboard charges nothing
# (`cost_basis` = "internal: <reason>"). Every expected value is hand-computed.

pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_strategy_correlation.R"))
source(here::here("R/plan_leaderboard.R"))
source(here::here("R/plan_qa_gates.R"))

.sn <- function() hd_strategy_names_tbl()
.hand_realised <- function() {
  data.frame(code_name = .sn()$code_name, turnover_realised = NA_real_,
             na_reason = "fixture: no measurement", stringsAsFactors = FALSE)
}

# ── (1) leg factor: cost = traded value x cost per unit traded, exactly once ──

test_that("leg factor: a full A->B switch of a long-only book costs 2 x 0.5% = 1%", {
  # Sell all of A (1.0 traded), buy all of B (1.0 traded): two-way traded = 2.0.
  two_way <- hd_turnover(c(A = 0, B = 1), c(A = 1, B = 0), side = "two")
  one_way <- hd_turnover(c(A = 0, B = 1), c(A = 1, B = 0), side = "one")
  expect_equal(two_way, 2)
  expect_equal(one_way, 1)
  # The leaderboard turnover is the ONE-WAY figure; cost per traded unit is
  # 0.005, so the monthly cost must be 2.0 * 0.005 = 0.01 -- not 0.005 (buy or
  # sell forgotten) and not 0.02 (two-way figure multiplied by the x2 again).
  expect_equal(.period_cost(one_way, "long_only"), 0.01, tolerance = 1e-12)
  expect_equal(.period_cost(one_way, "long_only"), two_way * 0.005, tolerance = 1e-12)
})

test_that("leg factor: a full replacement of BOTH legs of a long-short book costs 4 x 0.5% = 2% + borrow", {
  # Previous: +100% A, -100% B. New: +100% C, -100% D. Traded: sell A 1, cover B 1,
  # buy C 1, short D 1 = 4.0 two-way; one-way (hd_turnover default) = 2.0.
  prev <- c(A = 1, B = -1, C = 0, D = 0)
  now  <- c(A = 0, B = 0, C = 1, D = -1)
  one_way <- hd_turnover(now, prev)
  two_way <- hd_turnover(now, prev, side = "two")
  expect_equal(c(one_way, two_way), c(2, 4))
  # strategy_realised_turnover divides by legs (2): per-leg one-way = 1.0.
  per_leg <- one_way / 2
  cost_no_borrow <- .period_cost(per_leg, "long_short") - 0.03 / 12
  expect_equal(cost_no_borrow, two_way * 0.005, tolerance = 1e-12)  # 0.02
  expect_equal(cost_no_borrow, 0.02, tolerance = 1e-12)
})

test_that("leg factor: an overlay switching SPY -> cash trades ONE side, costs 0.5% (not 1%)", {
  # SPY and cash are both names in the measured weights (rt_entry_exposure()). Selling
  # 100% SPY into cash: sum|dw| = 2.0, one-way (default) = 1.0 = 1.0 of SPY sold; the
  # cash side costs nothing. Cost = 1.0 * 0.005 = 0.5%; the x2 would charge 1%.
  now  <- c(SPY = 0, CASH = 1)
  prev <- c(SPY = 1, CASH = 0)
  expect_equal(c(hd_turnover(now, prev), hd_turnover(now, prev, side = "two")), c(1, 2))
  expect_equal(.period_cost(hd_turnover(now, prev), "overlay"), 0.005, tolerance = 1e-12)
  # TOM: in and out once a month = two switches = turnover 2.0 -> 1.0%/month
  expect_equal(.period_cost(2, "overlay"), 0.01, tolerance = 1e-12)
})

test_that(".leg_multiplier() is the single home of the 2 / 1 / 4 factor", {
  expect_equal(.leg_multiplier(c("long_only", "overlay", "market_neutral", "long_short")),
               c(2, 1, 2, 4))
  b <- .strategy_turnover_cost_basis(.sn(), .hand_realised())
  expect_equal(b$leg_multiplier, .leg_multiplier(.sn()$directionality))
})

# ── (2) cost_basis: internal-only strategies are charged NOTHING by the leaderboard ──

test_that(".strategy_turnover_cost_basis() marks internal-only strategies and charges them 0", {
  b <- .strategy_turnover_cost_basis(.sn(), .hand_realised())
  expect_true("cost_basis" %in% names(b))
  internal <- b$code_name[startsWith(b$cost_basis, "internal")]
  expect_setequal(internal, c("pso_optimal", "cmr_conditioned"))
  expect_true(all(b$monthly_cost[b$code_name %in% internal] == 0))
  expect_true(all(is.na(b$turnover_basis[b$code_name %in% internal])))
  # every other strategy: leaderboard cost, strictly positive
  other <- b[!b$code_name %in% internal, ]
  expect_true(all(other$cost_basis == "leaderboard"))
  expect_true(all(other$monthly_cost > 0))
})

test_that(".strategy_turnover_cost_basis() aborts on an internal-only code that is not in strategy_names", {
  expect_error(
    .strategy_turnover_cost_basis(.sn(), .hand_realised(), internal_only = c(not_a_strategy = "x")),
    "not_a_strategy"
  )
})

# ── (3) no double deduction: the cost pass works on the GROSS series ────────

test_that(".cost_ext_rows() applies the leaderboard cost to the GROSS series, never to the net one", {
  # internal cost of 0.003/month was already inside the net series
  gross <- rep(0.02, 12)
  net   <- gross - 0.003
  net_wide   <- data.frame(ym = sprintf("2020-%02d", 1:12), x = net)
  gross_wide <- data.frame(ym = sprintf("2020-%02d", 1:12), x = gross)
  basis <- data.frame(code_name = "x_code", cost_basis = "leaderboard",
                      monthly_cost = 0.01, stringsAsFactors = FALSE)
  out <- .cost_ext_rows(
    list(list(code = "x_code", wide_col = "x", label = "X")),
    net_wide, gross_wide, basis
  )
  # one cost: gross 0.02 - 0.01 = 0.01/month. The double count would be 0.02 - 0.003 - 0.01 = 0.007.
  expect_equal(out$net_cagr, 1.01^12 - 1, tolerance = 1e-12)
  expect_false(isTRUE(all.equal(out$net_cagr, 1.007^12 - 1)))
  expect_equal(out$strategy, "X")
  expect_equal(out$period, "Full Period")
})

test_that(".cost_ext_rows() charges an internal-only strategy no second cost (net series used as is)", {
  net <- rep(0.012, 12)
  net_wide   <- data.frame(ym = sprintf("2020-%02d", 1:12), y = net)
  gross_wide <- data.frame(ym = sprintf("2020-%02d", 1:12), z = 0)  # no y column: none exists
  basis <- data.frame(code_name = "y_code", cost_basis = "internal: only net exposed",
                      monthly_cost = 0, stringsAsFactors = FALSE)
  out <- .cost_ext_rows(
    list(list(code = "y_code", wide_col = "y", label = "Y")),
    net_wide, gross_wide, basis
  )
  expect_equal(out$net_cagr, 1.012^12 - 1, tolerance = 1e-12)
})

test_that(".cost_ext_rows() uses the net series for a strategy that has no internal cost (Avoid Worst)", {
  r <- rep(0.01, 12)
  net_wide   <- data.frame(ym = sprintf("2020-%02d", 1:12), avoid_worst = r)
  gross_wide <- data.frame(ym = sprintf("2020-%02d", 1:12), z = 0)
  basis <- data.frame(code_name = "avoid_worst", cost_basis = "leaderboard",
                      monthly_cost = 0.004, stringsAsFactors = FALSE)
  out <- .cost_ext_rows(
    list(list(code = "avoid_worst", wide_col = "avoid_worst", label = "Avoid Worst")),
    net_wide, gross_wide, basis
  )
  expect_equal(out$net_cagr, 1.006^12 - 1, tolerance = 1e-12)
})

test_that(".cost_ext_rows() fails loud when a leaderboard-cost strategy has no gross series", {
  net_wide   <- data.frame(ym = sprintf("2020-%02d", 1:12), x = 0.01)
  gross_wide <- data.frame(ym = sprintf("2020-%02d", 1:12), other = 0.01)
  basis <- data.frame(code_name = "x_code", cost_basis = "leaderboard",
                      monthly_cost = 0.01, stringsAsFactors = FALSE)
  expect_error(
    .cost_ext_rows(list(list(code = "x_code", wide_col = "x", label = "X")),
                   net_wide, gross_wide, basis),
    "gross"
  )
  expect_error(
    .cost_ext_rows(list(list(code = "x_code", wide_col = "x", label = "X")),
                   net_wide, NULL, basis),
    "gross"
  )
})

test_that("the leaderboard cost pass reads a gross column for every costed strategy (source guard)", {
  src <- paste(readLines(here::here("R/plan_leaderboard.R")), collapse = "\n")
  expect_match(src, 'slice_portfolio\\(fm_portfolio,\\s+"gross_port_ret"')
  expect_match(src, 'slice_portfolio\\(drif_portfolio,\\s+"gross_port_ret"')
  expect_match(src, "strat_returns_gross_wide", fixed = TRUE)
})

# ── (4) strat_returns_gross_wide builder ────────────────────────────────────

test_that("build_strat_returns_gross_wide(): gross = net + the strategy's own internal cost, per source", {
  d <- function(n) as.Date("2020-01-01") + 0:(n - 1)
  n <- 40  # > 15 days in Jan-Feb 2020 -> Jan complete; Feb partial excluded by design
  out <- build_strat_returns_gross_wide(
    ltr_portfolio = tibble::tibble(date = as.Date(c("2020-01-31", "2020-02-29")),
                                   port_ret = c(0.01, 0.02), ls_ret_gross = c(0.015, 0.03)),
    mom_returns = list(
      mom_prepeak  = tibble::tibble(exec_date = as.Date(c("2020-01-31", "2020-02-29")),
                                    ret_long = c(0.05, 0.04), ret_short = c(0.01, 0.01), ret_ls = c(0.03, 0.02)),
      mom_postpeak = tibble::tibble(exec_date = as.Date(c("2020-01-31", "2020-02-29")),
                                    ret_long = c(0.05, 0.04), ret_short = c(0.01, 0.01), ret_ls = c(0.03, 0.02)),
      mom_combined = tibble::tibble(exec_date = as.Date(c("2020-01-31", "2020-02-29")),
                                    ret_long = c(0.05, 0.04), ret_short = c(0.01, 0.01), ret_ls = c(0.03, 0.02))
    ),
    ev_portfolios = tibble::tibble(date = as.Date(c("2020-01-31", "2020-02-29")),
                                   RF = c(0.001, 0.001), HML = c(0.01, 0.02), ret_value_hml = c(0.009, 0.019)),
    mf_portfolios = tibble::tibble(date = as.Date(c("2020-01-31", "2020-02-29")), ret_ls = c(0.004, 0.006)),
    mf_params = list(cost_monthly = 0.001),
    cmr_port = tibble::tibble(date = d(n), gross_ret = 0.001, net_ret = 0.0008),
    olmar_portfolio = tibble::tibble(date = d(n), gross_ret = 0.002, net_ret = 0.0015),
    tom_portfolio = tibble::tibble(date = d(n), ret_gross = 0.003, ret_net = 0.0025),
    rsc_portfolio = tibble::tibble(date = d(n), gross_ret_strategy = 0.004, ret_strategy = 0.0035)
  )
  expect_true(all(c("ym", "ltr", "mom_prepeak", "mom_postpeak", "mom_combined",
                    "value_hml", "managed_futures", "cmr", "olmar_1", "tom", "risk_state") %in% names(out)))
  jan <- out[out$ym == "2020-01", ]
  expect_equal(jan$ltr, 0.015)                       # ls_ret_gross
  expect_equal(jan$mom_prepeak, 0.05 - 0.01)         # ret_long - ret_short
  expect_equal(jan$value_hml, 0.001 + 0.01)          # RF + HML
  expect_equal(jan$managed_futures, 0.004 + 0.001)   # ret_ls + cost_monthly
  # daily: 31 January days compounded
  expect_equal(jan$olmar_1, 1.002^31 - 1, tolerance = 1e-12)
  expect_equal(jan$tom,     1.003^31 - 1, tolerance = 1e-12)
  expect_equal(jan$risk_state, 1.004^31 - 1, tolerance = 1e-12)
  expect_equal(jan$cmr,     1.001^31 - 1, tolerance = 1e-12)
})

# ── (5) stock long-short gross, and the validation script's single cost home ──

test_that(".stk_with_gross() adds back trade + borrow cost: gross = long - short", {
  p <- data.frame(long_ret = c(0.05, 0.02), short_ret = c(0.01, 0.03),
                  total_cost = c(0.0185, 0.0185))
  p$port_ret <- p$long_ret - p$short_ret - p$total_cost
  g <- .stk_with_gross(p)
  expect_equal(g$gross_port_ret, p$long_ret - p$short_ret, tolerance = 1e-12)
  expect_error(.stk_with_gross(p[, c("long_ret", "short_ret")]), "total_cost")
})

test_that("scripts/evaluate_validation.R calls the leaderboard's cost functions (no second copy)", {
  src <- readLines(here::here("scripts/evaluate_validation.R"))
  expect_false(any(grepl("^\\s*COST_PER_MONTH\\s*<-", src)))
  expect_false(any(grepl("(1 - COST_PER_MONTH)", src, fixed = TRUE)))
  expect_false(any(grepl("^\\s*calc_cost_metrics\\s*<-\\s*function", src)))
  expect_true(any(grepl(".calc_cost_metrics(", src, fixed = TRUE)))
  expect_true(any(grepl(".strategy_turnover_cost_basis(", src, fixed = TRUE)))
  expect_no_error(parse(here::here("scripts/evaluate_validation.R")))
})
