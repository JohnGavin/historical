testthat::local_edition(3)
# #1057: commodity momentum must read the SAME tradeable-era input as CMR
# (cmr_tradeable_returns, built by .cmr_truncate_to_tradeable_era(), #751).
# Before the fix, commodities_signals / commodities_backtest read the
# untruncated commodities_returns, so the backtest included dates on which
# only the 13 monthly FRED/IMF index series exist (not investable, and
# annualised at 252 bars/year although they are monthly bars).
#
# Still OPEN and deliberately NOT tested here: the post-cutoff mix of daily
# and monthly series (#751 finding 3).

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/utils_metrics.R"))
source(here::here("R/commodities_momentum.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))
source(here::here("R/plan_commodities_momentum.R"))

# ── Fixture: raw long-format prices with a `source` column ───────────────────
# 6 monthly FRED/IMF series from 1996 (pre-tradeable era), 6 daily Yahoo
# series from 2000-03-01. 12 series so n_long = n_short = 10 is feasible.
.mom_raw_fixture <- function() {
  set.seed(1057)
  fred <- lapply(1:6, function(i) {
    tibble::tibble(
      date = seq.Date(as.Date("1996-01-01"), by = "month", length.out = 120),
      series_id = paste0("FRED", i), source = "fred_imf",
      value = 100 * cumprod(1 + rnorm(120, 0.002, 0.02))
    )
  })
  yahoo <- lapply(1:6, function(i) {
    tibble::tibble(
      date = seq.Date(as.Date("2000-03-01"), by = "day", length.out = 150),
      series_id = paste0("YH", i), source = "yahoo",
      value = 50 * cumprod(1 + rnorm(150, 0.0005, 0.01))
    )
  })
  dplyr::bind_rows(c(fred, yahoo))
}

.mom_target <- function(name) {
  tl  <- plan_commodities_momentum()
  hit <- vapply(tl, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  tl[[which(hit)]]$command$expr[[1]]
}

.mom_eval <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

.mom_inputs <- function() {
  returns   <- calculate_commodity_returns(.mom_raw_fixture())
  tradeable <- suppressMessages(.cmr_truncate_to_tradeable_era(returns))
  list(returns = returns, tradeable = tradeable,
       cutoff = .cmr_tradeable_cutoff_date(returns))
}

test_that("fixture really has monthly-only dates before the cutoff", {
  x <- .mom_inputs()
  expect_gt(sum(x$returns$date < x$cutoff), 0L)
  expect_true(all(x$returns$source[x$returns$date < x$cutoff] == "fred_imf"))
})

test_that("momentum signals and backtest contain no monthly-only (pre-cutoff) dates", {
  x <- .mom_inputs()
  # Both inputs are supplied: only the target that reads the tradeable one
  # can produce an era-clean result.
  signals <- .mom_eval(.mom_target("commodities_signals"),
                       commodities_returns = x$returns,
                       cmr_tradeable_returns = x$tradeable)
  expect_true(all(signals$date >= x$cutoff))

  bt <- .mom_eval(.mom_target("commodities_backtest"),
                  commodities_signals = signals,
                  commodities_returns = x$returns,
                  cmr_tradeable_returns = x$tradeable)
  expect_gt(nrow(bt), 0L)
  expect_true(all(bt$date >= x$cutoff))
})

test_that("plan wiring: momentum targets read cmr_tradeable_returns, not commodities_returns", {
  for (nm in c("commodities_signals", "commodities_backtest")) {
    vars <- all.vars(.mom_target(nm))
    expect_true("cmr_tradeable_returns" %in% vars, info = nm)
    expect_false("commodities_returns" %in% vars, info = nm)
  }
})
