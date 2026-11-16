testthat::local_edition(3)
# #1057: commodity momentum must read the SAME tradeable-era input as CMR
# (cmr_tradeable_returns, built by .cmr_truncate_to_tradeable_era(), #751).
# Before the fix, commodities_signals / commodities_backtest read the
# untruncated commodities_returns, so the backtest included dates on which
# only the 13 monthly FRED/IMF index series exist (not investable, and
# annualised at 252 bars/year although they are monthly bars).
#
# #1061: momentum must also trade CMR's POSITION pool, cmr_deduplicated_returns
# (= the keep = TRUE rows of .HD_CMR_EXPOSURE_MAP, #808), so the monthly
# IMF/FRED series (conditioning data or twins) are never ranked or held. The
# targets are therefore fed cmr_deduplicated_returns, built exactly as the CMR
# plan builds it (hd_commodity_mr_dedupe_universe(cmr_tradeable_returns)).

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
# Real .HD_CMR_EXPOSURE_MAP ids (the dedupe step aborts on unmapped ids).
# Monthly FRED/IMF from 1996 (pre-tradeable era): the conditioning = TRUE
# series plus one keep = FALSE twin (PGOLDUSDM). Daily Yahoo futures
# (keep = TRUE) from 2000-03-01.
.mom_cond_ids    <- .HD_CMR_EXPOSURE_MAP$series_id[.HD_CMR_EXPOSURE_MAP$conditioning]
.mom_keep_ids    <- .HD_CMR_EXPOSURE_MAP$series_id[.HD_CMR_EXPOSURE_MAP$keep]
.mom_nonkeep_ids <- .HD_CMR_EXPOSURE_MAP$series_id[!.HD_CMR_EXPOSURE_MAP$keep]
.mom_monthly_ids <- c(.mom_cond_ids, "PGOLDUSDM")
.mom_daily_ids   <- c("BZ=F", "CL=F", "GC=F", "SI=F", "HG=F", "ZW=F")

.mom_raw_fixture <- function() {
  set.seed(1057)
  fred <- lapply(.mom_monthly_ids, function(id) {
    tibble::tibble(
      date = seq.Date(as.Date("1996-01-01"), by = "month", length.out = 120),
      series_id = id, source = "fred_imf",
      value = 100 * cumprod(1 + rnorm(120, 0.002, 0.02))
    )
  })
  yahoo <- lapply(.mom_daily_ids, function(id) {
    tibble::tibble(
      date = seq.Date(as.Date("2000-03-01"), by = "day", length.out = 150),
      series_id = id, source = "yahoo",
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

.mom_inputs <- function() {
  returns   <- calculate_commodity_returns(.mom_raw_fixture())
  tradeable <- suppressMessages(.cmr_truncate_to_tradeable_era(returns))
  list(returns = returns, tradeable = tradeable,
       dedup = hd_commodity_mr_dedupe_universe(tradeable),
       cutoff = .cmr_tradeable_cutoff_date(returns))
}

# Evaluate a momentum target with every upstream target it could read, as the
# pipeline provides them (extra = further upstream objects, e.g. signals).
.mom_run <- function(name, x, extra = list()) {
  vars <- c(list(commodities_returns = x$returns,
                 cmr_tradeable_returns = x$tradeable,
                 cmr_deduplicated_returns = x$dedup),
            extra)
  env <- list2env(vars, envir = new.env(parent = globalenv()))
  eval(.mom_target(name), envir = env)
}

test_that("fixture really has monthly-only dates before the cutoff", {
  x <- .mom_inputs()
  expect_gt(sum(x$returns$date < x$cutoff), 0L)
  expect_true(all(x$returns$source[x$returns$date < x$cutoff] == "fred_imf"))
})

test_that("momentum signals and backtest contain no monthly-only (pre-cutoff) dates", {
  x <- .mom_inputs()
  # All inputs are supplied: only a target that reads the era-clean pool can
  # produce an era-clean result.
  signals <- .mom_run("commodities_signals", x)
  expect_true(all(signals$date >= x$cutoff))

  bt <- .mom_run("commodities_backtest", x, list(commodities_signals = signals))
  expect_gt(nrow(bt), 0L)
  expect_true(all(bt$date >= x$cutoff))
})

test_that("plan wiring: momentum targets read cmr_deduplicated_returns only", {
  for (nm in c("commodities_signals", "commodities_backtest")) {
    vars <- all.vars(.mom_target(nm))
    expect_true("cmr_deduplicated_returns" %in% vars, info = nm)
    expect_false("commodities_returns" %in% vars, info = nm)
    expect_false("cmr_tradeable_returns" %in% vars, info = nm)
  }
})

test_that("plan wiring: the pool momentum reads is the target CMR ranks", {
  tl  <- plan_commodities_mean_reversion()
  hit <- vapply(tl, function(t) identical(t$settings$name, "cmr_deduplicated_returns"),
                logical(1))
  expect_equal(sum(hit), 1L)
  cmd <- tl[[which(hit)]]$command$expr[[1]]
  expect_true("hd_commodity_mr_dedupe_universe" %in% all.names(cmd))
})

# ── #1061: conditioning = TRUE series are never ranked or held ───────────────

test_that("fixture has conditioning series in the tradeable input (so the check can fail)", {
  x <- .mom_inputs()
  expect_true(all(.mom_cond_ids %in% x$tradeable$series_id))
  expect_length(intersect(.mom_cond_ids, x$dedup$series_id), 0L)
})

test_that("no conditioning = TRUE or keep = FALSE series reaches momentum's universe or positions", {
  x <- .mom_inputs()
  signals <- .mom_run("commodities_signals", x)
  expect_length(intersect(unique(signals$series_id), .mom_nonkeep_ids), 0L)
  expect_length(intersect(unique(signals$series_id), .mom_cond_ids), 0L)

  bt <- .mom_run("commodities_backtest", x, list(commodities_signals = signals))
  expect_gt(nrow(bt), 0L)
  # The backtest ranks and holds only series present in its signals/returns
  # (it returns date-level results, not positions), so the series on the
  # backtest's dates are the candidate positions.
  held <- signals |>
    dplyr::semi_join(dplyr::filter(bt, strategy == "baseline"), by = "date") |>
    dplyr::pull(series_id) |>
    unique()
  expect_gt(length(held), 0L)
  expect_true(all(held %in% .mom_keep_ids))
})
