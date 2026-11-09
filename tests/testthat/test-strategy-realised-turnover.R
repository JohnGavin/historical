testthat::local_edition(3)
# Tests for the per-strategy realised-turnover target's pure helpers and its QA
# gate (#663 Phase 1, #567 A1/A2). Every expected value is worked by hand in the
# comment above it.

pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_cost_convention.R"))
source(here::here("R/plan_qa_gates.R"))

d <- as.Date(c("2024-01-31", "2024-02-29", "2024-03-29", "2024-04-30"))

toy_names <- tibble::tibble(
  code_name = c("a", "b", "c"),
  short_name = c("A", "B", "C"),
  frequency = c("monthly", "daily", "monthly"),
  ann_factor = c(12L, 252L, 12L),
  turnover_pct_per_period_avg = c(50, 10, 20),
  directionality = factor(c("long_short", "long_only", "overlay"),
                          levels = c("long_only", "long_short", "market_neutral", "overlay"))
)

# ── build_strategy_realised_turnover() ───────────────────────────────────────

test_that("build: averages, annualises and puts realised on the per-month per-leg basis", {
  out <- build_strategy_realised_turnover(
    list(
      a = .rt_entry(c(NA, 0.4, 0.6), "src", FALSE, "n"),
      b = .rt_entry(c(0.1, 0.3), "src", TRUE, "n"),
      c = .rt_na_entry("no weights")
    ),
    toy_names
  )
  # A: mean(.4,.6) = .5 over 2 periods; x12 = 6; legs 2 -> 6/12/2 = .25; hand-typed .50 -> ratio .5
  expect_equal(out$avg_turnover_oneway[1], 0.5)
  expect_equal(out$n_periods[1], 2L)
  expect_equal(out$annualised_turnover_oneway[1], 6)
  expect_equal(out$legs[1], 2)
  expect_equal(out$turnover_realised[1], 0.25)
  expect_equal(out$turnover_hand_typed[1], 0.5)
  expect_equal(out$turnover_ratio[1], 0.5)
  # B: mean(.1,.3) = .2 daily; x252 = 50.4; legs 1 -> 50.4/12 = 4.2; hand-typed .10 -> 42
  expect_equal(out$annualised_turnover_oneway[2], 50.4)
  expect_equal(out$turnover_realised[2], 4.2)
  expect_equal(out$turnover_ratio[2], 42)
  # C: overlay counts as one leg; no measurement, but a stated reason.
  expect_equal(out$legs[3], 1)
  expect_true(is.na(out$avg_turnover_oneway[3]))
  expect_equal(out$na_reason[3], "no weights")
  expect_equal(out$n_periods[3], 0L)
  expect_true(check_strategy_realised_turnover(out, toy_names))
})

test_that("build: drop_leading removes warm-up periods before averaging", {
  out <- build_strategy_realised_turnover(
    list(
      a = .rt_entry(c(1, 0.4, 0.6), "src", FALSE, "n", drop_leading = 1L),
      b = .rt_na_entry("x"), c = .rt_na_entry("y")
    ),
    toy_names
  )
  expect_equal(out$avg_turnover_oneway[1], 0.5)
  expect_equal(out$n_periods[1], 2L)
})

test_that("build: aborts on a missing entry, an extra entry, and bad series", {
  ok <- list(a = .rt_na_entry("x"), b = .rt_na_entry("y"), c = .rt_na_entry("z"))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(ok[c("a", "b")], toy_names))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(c(ok, list(zzz = .rt_na_entry("q"))), toy_names))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(
    modifyList(ok, list(a = .rt_entry(c(0.1, -0.2), "s", FALSE, "n"))), toy_names))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(
    modifyList(ok, list(a = .rt_entry(c(0.1, NA, 0.2), "s", FALSE, "n"))), toy_names))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(
    modifyList(ok, list(a = .rt_entry(c(0.1, 0.2), "s", FALSE, "n", drop_leading = 2L))), toy_names))
  expect_snapshot(error = TRUE, build_strategy_realised_turnover(ok, toy_names[, -1]))
})

test_that(".rt_na_entry refuses a blank reason", {
  expect_snapshot(error = TRUE, .rt_na_entry(""))
  expect_snapshot(error = TRUE, .rt_na_entry(NA_character_))
})

# ── Entry builders on hand-computed toys ─────────────────────────────────────

test_that("weight panel: an exit and an entry count; first rebalance excluded", {
  panel <- data.frame(
    as_of_date = d[c(1, 1, 2, 2, 3, 3)],
    ticker = c("A", "B", "A", "C", "A", "C"),
    weight = c(0.5, -0.5, 0.5, -0.5, 0.5, -0.5)
  )
  e <- .rt_entry_weight_panel(panel, "weights: toy")
  # d1 NA (funding). d2: B exits (|0-(-.5)|=.5), C enters (.5) -> sum 1 -> .5. d3 unchanged -> 0.
  expect_equal(e$turnover, c(NA, 0.5, 0))
  expect_false(e$drift_adjusted)
  expect_equal(.rt_summarise(e, "toy")$avg, 0.25)
  expect_equal(.rt_summarise(e, "toy")$n, 2L)
})

test_that("exposure overlay, 0/1 book: turnover 1 on each switch day", {
  df <- data.frame(date = d, exposure = c(0, 1, 1, 0))
  e <- .rt_entry_exposure(df, "exposure", source = "toy", note = "n")
  # SPY 0,1,1,0 with CASH 1,0,0,1: d2 = (1+1)/2 = 1, d3 = 0, d4 = 1
  expect_equal(e$turnover, c(NA, 1, 0, 1))
  expect_equal(.rt_summarise(e, "toy")$avg, 2 / 3)
  expect_false(e$drift_adjusted)
})

test_that("exposure overlay with returns: holding a 50/50 mix still re-hedges after drift", {
  df <- data.frame(date = d[1:2], exposure = c(0.5, 0.5), spy = c(1, 0), cash = c(0, 0))
  e <- .rt_entry_exposure(df, "exposure", "spy", "cash", source = "toy", note = "n")
  # SPY doubles on d1: g = 1 + .5 = 1.5; drifted SPY = 1/1.5, CASH = .5/1.5; back to .5/.5:
  # (|.5-2/3| + |.5-1/3|)/2 = 1/6
  expect_equal(e$turnover, c(NA, 1 / 6))
  expect_true(e$drift_adjusted)
})

test_that("managed futures: warm-up dropped, CASH listed, drift applied", {
  mf <- data.frame(
    date = d,
    SPY = c(0.00, 0.10, 0.00, 0.00), TLT = 0, GLD = 0, DBC = 0, RF = 0,
    pos_SPY = c(0, 2, 2, 2), pos_TLT = 0, pos_GLD = 0, pos_DBC = 0
  )
  e <- .rt_entry_managed_futures(mf)
  # Month 1 is warm-up (all positions 0) and is dropped. Month 2: SPY = 2/4 = .5, CASH = .5,
  # SPY returns +10%: g = 1 + .05 = 1.05, drifted SPY = .55/1.05, CASH = .5/1.05. Month 3 back to
  # .5/.5: 2 x (.55/1.05 - .5) / 2 = .55/1.05 - .5 = 1/42.
  expect_equal(e$turnover, c(NA, 0.55 / 1.05 - 0.5, 0), tolerance = 1e-12)
  expect_equal(.rt_summarise(e, "toy")$avg, (0.55 / 1.05 - 0.5) / 2, tolerance = 1e-12)
  expect_true(e$drift_adjusted)
})

test_that("managed futures with no live month aborts", {
  mf <- data.frame(date = d, SPY = 0, TLT = 0, GLD = 0, DBC = 0, RF = 0,
                   pos_SPY = 0, pos_TLT = 0, pos_GLD = 0, pos_DBC = 0)
  expect_snapshot(error = TRUE, .rt_entry_managed_futures(mf))
})

# ── Wiring: the target exists and accounts for the whole roster ──────────────

test_that("the strategy_realised_turnover target is defined in plan_cost_convention()", {
  nms <- vapply(plan_cost_convention(), function(t) t$settings$name, character(1))
  expect_true("strategy_realised_turnover" %in% nms)
})

test_that("an all-explained table over the REAL roster passes the QA gate", {
  sn <- hd_strategy_names_tbl()
  entries <- stats::setNames(
    lapply(sn$code_name, function(x) .rt_na_entry(paste("no weights for", x))),
    sn$code_name
  )
  out <- build_strategy_realised_turnover(entries, sn)
  expect_equal(nrow(out), nrow(sn))
  expect_true(check_strategy_realised_turnover(out, sn))
})

# ── QA gate: pass, and a deliberate failure for each assertion ───────────────

good <- build_strategy_realised_turnover(
  list(
    a = .rt_entry(c(NA, 0.4, 0.6), "src", FALSE, "n"),
    b = .rt_entry(c(0.1, 0.3), "src", TRUE, "n"),
    c = .rt_na_entry("no weights")
  ),
  toy_names
)

test_that("gate passes the consistent table", {
  expect_true(check_strategy_realised_turnover(good, toy_names))
})

test_that("gate fails a strategy with neither a value nor a reason", {
  bad <- good
  bad$na_reason[3] <- NA_character_
  expect_snapshot(error = TRUE, check_strategy_realised_turnover(bad, toy_names))
})

test_that("gate fails a strategy with both a value and a reason", {
  bad <- good
  bad$na_reason[1] <- "also explained"
  expect_snapshot(error = TRUE, check_strategy_realised_turnover(bad, toy_names))
})

test_that("gate fails a derived column that disagrees with its definition", {
  bad <- good
  bad$turnover_realised[1] <- 0.99
  expect_snapshot(error = TRUE, check_strategy_realised_turnover(bad, toy_names))
})

test_that("gate fails a roster that disagrees with strategy_names", {
  bad <- good[-2, ]
  expect_snapshot(error = TRUE, check_strategy_realised_turnover(bad, toy_names))
})

test_that("gate fails a missing column", {
  expect_snapshot(error = TRUE, check_strategy_realised_turnover(good[, -1], toy_names))
})

# ── Migration regression: the OLD grid-completion code vs hd_turnover_series() ──
# backtest_momentum_signals() used a tidyr complete()+lag() computation; it now
# calls hd_turnover_series(). This keeps the old computation as a reference and
# checks the two agree, including an exit, an entry, and a scheme that has a gap.

old_turnover <- function(portfolio) {
  all_dates <- sort(unique(portfolio$date))
  portfolio |>
    dplyr::select(scheme, ticker, date, weight) |>
    dplyr::arrange(scheme, ticker, date) |>
    tidyr::complete(tidyr::nesting(scheme, ticker), date = all_dates, fill = list(weight = 0)) |>
    dplyr::group_by(scheme, ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(prev_weight = dplyr::lag(weight, default = 0),
                  weight_change = abs(weight - prev_weight)) |>
    dplyr::group_by(scheme, date) |>
    dplyr::summarise(turnover = sum(weight_change, na.rm = TRUE) / 2, .groups = "drop")
}

test_that("hd_turnover_series() reproduces the old grid-completion turnover exactly", {
  set.seed(7)
  mk <- function(scheme, dates) {
    do.call(rbind, lapply(dates, function(dt) {
      k <- sample(LETTERS[1:8], 4)
      data.frame(scheme = scheme, ticker = k, date = dt,
                 weight = c(0.5, 0.5, -0.5, -0.5), stringsAsFactors = FALSE)
    }))
  }
  # Scheme "gap" has no rows at d[3]: the old grid treats that date as all-cash.
  portfolio <- rbind(mk("full", d), mk("gap", d[c(1, 2, 4)]))
  old <- old_turnover(portfolio)
  all_dates <- sort(unique(portfolio$date))
  new <- dplyr::bind_rows(lapply(split(portfolio, portfolio$scheme), function(p) {
    o <- hd_turnover_series(data.frame(date = p$date, name = p$ticker, weight = p$weight),
                            periods = all_dates)
    o$scheme <- p$scheme[1]
    o[c("scheme", "date", "turnover")]
  }))
  j <- dplyr::inner_join(old, new, by = c("scheme", "date"), suffix = c(".old", ".new"))
  expect_equal(nrow(j), nrow(old))
  expect_equal(j$turnover.new, j$turnover.old, tolerance = 1e-12)
})
