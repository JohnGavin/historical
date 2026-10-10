testthat::local_edition(3)
# #937 (refs #919): strat_returns_wide fed Stock MAX / Factor MAX / Factor DRIF
# from port_returns, whose monthly spine is bounded to the overlap of the two
# STOCK series. The factor series (and Stock MAX's early history) were cut to
# that window, so strat_deflated_sharpe scored them over 193 months while the
# leaderboard scores Factor MAX on 740. Each strategy must enter the wide
# table through its OWN full-length portfolio series, the same way LTR, Mom and
# HML already do. port_returns itself is unchanged (the optimiser needs it).

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_strategy_correlation.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

.yms <- function(from, n) {
  format(seq(as.Date(paste0(from, "-01")), by = "month", length.out = n), "%Y-%m")
}

# Toy world mirroring the store: stock series 2010-02.., factor series start
# decades earlier (Factor MAX 120 months, Factor DRIF 100, Stock MAX 150).
.toy <- function() {
  set.seed(937)
  stk_drif_ym <- .yms("2010-02", 60L)
  stk_max_ym  <- .yms("2005-02", 120L)          # same end as stk_drif
  fm_ym       <- .yms("2000-01", 240L)
  drif_ym     <- .yms("2002-01", 200L)
  stk_max_portfolio  <- tibble::tibble(ym = stk_max_ym, port_ret = rnorm(120L, 0.004, 0.03))
  stk_drif_portfolio <- tibble::tibble(ym = stk_drif_ym, port_ret = rnorm(60L, 0.004, 0.03))
  fm_portfolio       <- tibble::tibble(ym = fm_ym, portfolio_ret = rnorm(240L, 0.004, 0.03))
  drif_portfolio     <- tibble::tibble(ym = drif_ym, portfolio_ret = rnorm(200L, 0.004, 0.03))

  # port_returns exactly as plan_portfolio_opt.R builds it: spine bounded to
  # the stock-level overlap, factors left-joined on.
  spine <- .yms(max(min(stk_max_ym), min(stk_drif_ym)), 60L)
  port_returns <- tibble::tibble(ym = spine) |>
    dplyr::left_join(dplyr::select(stk_max_portfolio, ym, stk_max = port_ret), by = "ym") |>
    dplyr::left_join(dplyr::select(stk_drif_portfolio, ym, stk_drif = port_ret), by = "ym") |>
    dplyr::left_join(dplyr::select(fm_portfolio, ym, fac_max = portfolio_ret), by = "ym") |>
    dplyr::left_join(dplyr::select(drif_portfolio, ym, fac_drif = portfolio_ret), by = "ym")

  dts <- as.Date(paste0(.yms("2010-02", 6L), "-15"))
  ltr_portfolio <- tibble::tibble(date = dts, port_ret = 0.001)
  xgb_drif_portfolio <- tibble::tibble(ym = .yms("2010-02", 6L), port_ret = 0.001)
  mom <- tibble::tibble(exec_date = dts, ret_ls = 0.001)
  list(
    stk_max_portfolio = stk_max_portfolio, stk_drif_portfolio = stk_drif_portfolio,
    fm_portfolio = fm_portfolio, drif_portfolio = drif_portfolio,
    port_returns = port_returns,
    ltr_portfolio = ltr_portfolio, xgb_drif_portfolio = xgb_drif_portfolio,
    mom_prepeak_returns = mom, mom_postpeak_returns = mom, mom_combined_returns = mom,
    ev_portfolios = tibble::tibble(date = dts, ret_value_hml = 0.001),
    mf_portfolios = tibble::tibble(date = dts, ret_ls = 0.001),
    strat_returns_daily_native = list()
  )
}

.run_wide <- function(toy) {
  cmd <- .target_command(plan_strategy_correlation(), "strat_returns_wide")
  env <- list2env(toy, envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

test_that("Factor MAX / Factor DRIF / Stock MAX enter strat_returns_wide at their OWN full length", {
  toy <- .toy()
  w <- .run_wide(toy)
  expect_equal(sum(!is.na(w$fac_max)),  nrow(toy$fm_portfolio))        # 240, not 60
  expect_equal(sum(!is.na(w$fac_drif)), nrow(toy$drif_portfolio))      # 200, not 60
  expect_equal(sum(!is.na(w$stk_max)),  nrow(toy$stk_max_portfolio))   # 120, not 60
})

test_that("values on the overlap are bit-identical to the old port_returns-sourced series", {
  toy <- .toy()
  w <- .run_wide(toy)
  pr <- toy$port_returns
  m <- match(pr$ym, w$ym)
  for (col in c("stk_max", "stk_drif", "fac_max", "fac_drif")) {
    expect_identical(w[[col]][m], pr[[col]])
  }
})

test_that("Stock DRIF is unchanged (its spine window IS its full length)", {
  toy <- .toy()
  w <- .run_wide(toy)
  expect_equal(sum(!is.na(w$stk_drif)), nrow(toy$stk_drif_portfolio))
})

test_that("FALSIFICATION: truncating the source to port_returns' window is detected", {
  # What the pre-fix target produced: every base column cut to the stock window.
  toy <- .toy()
  w <- .run_wide(toy)
  old_n <- sum(!is.na(toy$port_returns$fac_max))
  expect_gt(sum(!is.na(w$fac_max)), old_n)
  expect_lt(old_n, nrow(toy$fm_portfolio))
})

test_that("a consumer needing the COMMON window still gets it (strat_corr_augment restricts visibly)", {
  # strat_corr_augment drops incomplete rows itself (complete-case full_rets).
  # Extending the early history of ONE column must not move its Sharpe panel.
  skip_if_not(exists(".strat_excess_wide", mode = "function"))
  run_aug <- function(wide) {
    cmd <- .target_command(plan_strategy_correlation(), "strat_corr_augment")
    cols <- c("stk_max", "fac_max")
    env <- list2env(list(
      strat_returns_wide = wide,
      strat_corr_matrix_leaderboard = matrix(
        c(1, 0.3, 0.3, 1), 2L, dimnames = list(cols, cols)
      ),
      strat_returns_daily_native = list(
        cmr_conditioned = tibble::tibble(date = as.Date("2010-01-01"), ret = 0, cash_weight = 0, rf_ret = 0)
      ),
      ev_portfolios = tibble::tibble(date = as.Date("2010-01-15"), RF = 0),
      mf_portfolios = tibble::tibble(date = as.Date("2010-01-15"), RF = 0),
      olmar_portfolio = tibble::tibble(date = as.Date("2010-01-01"), rf_ret = 0),
      tom_portfolio = tibble::tibble(date = as.Date("2010-01-01"), rf_ret = 0),
      rsc_portfolio = tibble::tibble(date = as.Date("2010-01-01"), rf_daily = 0),
      aw_daily_rf = tibble::tibble(date = as.Date("2010-01-01"), rf_ret = 0)
    ), envir = new.env(parent = globalenv()))
    eval(cmd, envir = env)
  }
  set.seed(1)
  n <- 60L
  base <- tibble::tibble(ym = .yms("2010-02", n), stk_max = rnorm(n, 0.004, 0.03), fac_max = rnorm(n, 0.004, 0.03))
  longer <- dplyr::bind_rows(
    tibble::tibble(ym = .yms("2000-01", 48L), stk_max = NA_real_, fac_max = rnorm(48L, 0.01, 0.05)),
    base
  )
  expect_equal(run_aug(base)$incremental_sharpe, run_aug(longer)$incremental_sharpe)
})
