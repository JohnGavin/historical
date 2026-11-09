testthat::local_edition(3)
# #567: leaderboard cost model uses MEASURED turnover (strategy_realised_turnover)
# where trusted, the hand-typed value otherwise (with the reason carried as
# `turnover_basis`), and charges cost SUBTRACTIVELY (net = ret - cost), not as a
# multiplicative haircut. Pure functions in R/plan_leaderboard.R; every expected
# value below is worked by hand in the comment above it.

source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))

# Toy strategy_names / strategy_realised_turnover (only the columns used).
.toy_names <- function() {
  data.frame(
    code_name = c("m_ls", "m_lo", "daily_lo", "typed_na", "cmr"),
    short_name = c("M LS", "M LO", "Daily LO", "Typed NA", "CMR"),
    directionality = factor(
      c("long_short", "long_only", "overlay", "long_short", "long_short"),
      levels = c("long_only", "long_short", "market_neutral", "overlay")
    ),
    turnover_pct_per_period_avg = c(100, 50, 10, 100, 100),
    stringsAsFactors = FALSE
  )
}
.toy_realised <- function() {
  data.frame(
    code_name = c("m_ls", "m_lo", "daily_lo", "typed_na", "cmr"),
    turnover_realised = c(0.40, 0.25, 2.00, NA, 0.33),
    na_reason = c(NA, NA, NA, "no weight vector exists", NA),
    stringsAsFactors = FALSE
  )
}

# ── (a) turnover + basis choice ──────────────────────────────────────────────

test_that(".choose_cost_turnover() uses measured turnover when trusted", {
  out <- .choose_cost_turnover(.toy_names(), .toy_realised())
  expect_equal(out$turnover[out$code_name == "m_ls"], 0.40)
  expect_equal(out$turnover[out$code_name == "daily_lo"], 2.00)
  expect_equal(out$turnover_basis[out$code_name == "m_ls"], "measured")
  expect_equal(out$turnover_basis[out$code_name == "daily_lo"], "measured")
})

test_that(".choose_cost_turnover() falls back to hand-typed with the na_reason", {
  out <- .choose_cost_turnover(.toy_names(), .toy_realised())
  row <- out[out$code_name == "typed_na", ]
  expect_equal(row$turnover, 1.00)  # 100 / 100
  expect_equal(row$turnover_basis, "hand-typed: no weight vector exists")
})

test_that(".choose_cost_turnover() keeps CMR hand-typed even though it has a measured value (#567 A2)", {
  out <- .choose_cost_turnover(.toy_names(), .toy_realised())
  row <- out[out$code_name == "cmr", ]
  expect_equal(row$turnover, 1.00)
  expect_match(row$turnover_basis, "^hand-typed: ")
  expect_match(row$turnover_basis, "exits not counted", fixed = TRUE)
})

test_that(".choose_cost_turnover() never labels a hand-typed value 'measured' (missing value, no reason)", {
  realised <- .toy_realised()
  realised$na_reason[realised$code_name == "typed_na"] <- NA
  out <- .choose_cost_turnover(.toy_names(), realised)
  row <- out[out$code_name == "typed_na", ]
  expect_equal(row$turnover, 1.00)
  expect_match(row$turnover_basis, "^hand-typed: ")
})

test_that(".choose_cost_turnover() fails loud on a strategy with no realised row, duplicates, negatives", {
  expect_error(
    .choose_cost_turnover(.toy_names(), .toy_realised()[-1, ]),
    "no row in strategy_realised_turnover"
  )
  dup <- rbind(.toy_realised(), .toy_realised()[1, ])
  expect_error(.choose_cost_turnover(.toy_names(), dup), "duplicate")
  neg <- .toy_realised()
  neg$turnover_realised[1] <- -0.1
  expect_error(.choose_cost_turnover(.toy_names(), neg), "negative")
})

# ── (b) subtractive cost per period ──────────────────────────────────────────

test_that(".period_cost(): long-short with borrow, monthly series", {
  # turnover 0.40, long_short: 0.40 * 0.005 * 4 = 0.008; borrow 0.03/12 = 0.0025
  expect_equal(.period_cost(0.40, "long_short"), 0.0105, tolerance = 1e-12)
})

test_that(".period_cost(): long-only has no borrow and 2 legs-sides", {
  # 0.25 * 0.005 * 2 = 0.0025
  expect_equal(.period_cost(0.25, "long_only"), 0.0025, tolerance = 1e-12)
  expect_equal(.period_cost(0.25, "overlay"), 0.0025, tolerance = 1e-12)
})

test_that(".period_cost(): a daily-frequency series is charged the monthly cost spread over 252/12 periods", {
  # TOM-like: measured 2.0/month one-way (~24/yr), overlay -> 2.0 * 0.005 * 2 = 0.02 per MONTH.
  expect_equal(.period_cost(2.0, "overlay", series_ann_factor = 12), 0.02, tolerance = 1e-12)
  # per DAY: 0.02 * 12 / 252
  expect_equal(.period_cost(2.0, "overlay", series_ann_factor = 252),
               0.02 * 12 / 252, tolerance = 1e-12)
  # 21 trading days of that daily charge add back to one month's cost
  expect_equal(21 * .period_cost(2.0, "overlay", series_ann_factor = 252), 0.02, tolerance = 1e-12)
})

test_that(".period_cost() is vectorised and rejects bad input", {
  expect_equal(
    .period_cost(c(0.40, 0.25), c("long_short", "long_only")),
    c(0.0105, 0.0025), tolerance = 1e-12
  )
  expect_error(.period_cost(0.1, "sideways"), "directionality")
  expect_error(.period_cost(NA_real_, "long_only"), "finite")
  expect_error(.period_cost(0.1, "long_only", series_ann_factor = 0), "series_ann_factor")
})

test_that(".strategy_turnover_cost_basis() joins choice and cost (hand-computed)", {
  out <- .strategy_turnover_cost_basis(.toy_names(), .toy_realised(), internal_only = character(0))
  by <- function(code, col) out[[col]][out$code_name == code]
  # m_ls: measured 0.40, long_short -> 0.0105
  expect_equal(by("m_ls", "monthly_cost"), 0.0105, tolerance = 1e-12)
  expect_equal(by("m_ls", "leg_multiplier"), 4)
  # m_lo: measured 0.25 -> 0.0025
  expect_equal(by("m_lo", "monthly_cost"), 0.0025, tolerance = 1e-12)
  # daily_lo: measured 2.0, overlay -> 0.02/month
  expect_equal(by("daily_lo", "monthly_cost"), 0.02, tolerance = 1e-12)
  # typed_na: hand-typed 1.0, long_short -> 1.0*0.005*4 + 0.0025 = 0.0225
  expect_equal(by("typed_na", "monthly_cost"), 0.0225, tolerance = 1e-12)
  # cmr: hand-typed 1.0 (distrusted measured 0.33), long_short -> 0.0225
  expect_equal(by("cmr", "monthly_cost"), 0.0225, tolerance = 1e-12)
  expect_true(all(c("code_name", "short_name", "cost_basis", "turnover", "turnover_basis",
                    "leg_multiplier", "monthly_cost") %in% names(out)))
  expect_true(all(out$cost_basis == "leaderboard"))
})

test_that(".calc_cost_metrics() is SUBTRACTIVE: net = ret - cost, not ret * (1 - cost)", {
  ret <- rep(0.02, 12)
  out <- .calc_cost_metrics(ret, cost_per_month = 0.005)
  # net monthly return 0.015; 12 months compounded; n = 12 -> CAGR = 1.015^12 - 1
  expect_equal(out$net_cagr, 1.015^12 - 1, tolerance = 1e-12)
  expect_equal(out$cum_pnl, 1.015^12 - 1, tolerance = 1e-12)
  # the old multiplicative haircut would give 0.02 * 0.995 = 0.0199 per month
  expect_false(isTRUE(all.equal(out$net_cagr, (1 + 0.02 * 0.995)^12 - 1)))
  # a zero-return month still pays cost: all-zero returns lose exactly the cost
  z <- .calc_cost_metrics(rep(0, 12), cost_per_month = 0.01)
  expect_equal(z$net_cagr, 0.99^12 - 1, tolerance = 1e-12)
  # cvar is on GROSS returns (unchanged definition)
  r2 <- c(rep(0.01, 19), -0.10)
  expect_equal(.calc_cost_metrics(r2, 0.003)$cvar_95, -0.10)
})

test_that(".calc_cost_metrics() handles NA/empty input and requires an explicit cost", {
  expect_true(is.na(.calc_cost_metrics(c(NA_real_, NA_real_), 0.01)$net_cagr))
  expect_error(.calc_cost_metrics(c(0.01, 0.02)), "cost_per_month")
  expect_error(.calc_cost_metrics(c(0.01, 0.02), NA_real_), "cost_per_month")
})

# ── real registry: every strategy resolves, distrusted rows stay hand-typed ──

test_that("the real strategy_names table yields one basis row per strategy; charged ones have positive cost", {
  sn <- hd_strategy_names_tbl()
  realised <- data.frame(
    code_name = sn$code_name,
    turnover_realised = NA_real_,
    na_reason = "no measurement in this fixture",
    stringsAsFactors = FALSE
  )
  out <- .strategy_turnover_cost_basis(sn, realised)
  expect_equal(nrow(out), nrow(sn))
  expect_true(all(out$monthly_cost[out$cost_basis == "leaderboard"] > 0))
  # every strategy the leaderboard charges is hand-typed in this fixture; the two
  # internal-only strategies are charged nothing and carry no turnover basis
  charged <- out$cost_basis == "leaderboard"
  expect_true(all(startsWith(out$turnover_basis[charged], "hand-typed: ")))
  expect_true(all(is.na(out$turnover_basis[!charged])))
  expect_true(all(out$monthly_cost[!charged] == 0))
  # hand-typed turnover x 0.005 x legs + borrow: spot-check two
  expect_equal(out$monthly_cost[out$code_name == "ltr"], 0.0065, tolerance = 1e-12)
  expect_equal(out$monthly_cost[out$code_name == "ev_ebit"], 0.002, tolerance = 1e-12)
})
