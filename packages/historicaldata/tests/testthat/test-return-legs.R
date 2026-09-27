# Tests for hd_return_legs() -- overnight/intraday return split (#914 Gap 1)
#
# Every numeric expectation below is hand-derived from the same closed-form
# algebra documented in hd_return_legs()'s roxygen "Details" section, not
# re-run through the function's own code path -- a bug in the formula would
# show up as a mismatch here, not just reproduce itself.

# ── Basic split, no corporate actions (adjusted_close == close) ──────────

test_that("overnight and intraday legs match hand-derived values with no corporate actions", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:3,
    open           = c(100, 101, 103, 104),
    close          = c(101, 103, 104, 106),
    adjusted_close = c(101, 103, 104, 106)
  )
  out <- hd_return_legs(toy, quiet = TRUE)

  # Day 1 (2024-01-01) is dropped: no previous close.
  expect_equal(nrow(out), 3L)
  expect_equal(out$date, as.Date("2024-01-02") + 0:2)

  expect_equal(out$overnight[1], 101 / 101 - 1)   # open_2 / close_1 - 1
  expect_equal(out$intraday[1], 103 / 101 - 1)    # close_2 / open_2 - 1
  expect_equal(out$overnight[2], 103 / 103 - 1)
  expect_equal(out$intraday[2], 104 / 103 - 1)
  expect_equal(out$overnight[3], 104 / 104 - 1)
  expect_equal(out$intraday[3], 106 / 104 - 1)

  # No corporate actions -> adj_ratio constant at 1 every day.
  expect_true(all(!out$corp_action_adjusted))

  expect_equal(attr(out, "method"), "adjusted")
  expect_equal(attr(out, "n_dropped_first_row"), 1L)
  expect_equal(attr(out, "n_dropped_missing_open"), 0L)
  expect_equal(attr(out, "n_dropped_missing_adjusted_close"), 0L)
  expect_equal(attr(out, "n_corp_action_adjusted"), 0L)
})

test_that("overnight and intraday legs compound to the close-to-close return", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:3,
    open           = c(100, 101, 99, 104),
    close          = c(101, 99, 104, 106),
    adjusted_close = c(101, 99, 104, 106)
  )
  out <- hd_return_legs(toy, quiet = TRUE)
  recompounded <- (1 + out$overnight) * (1 + out$intraday) - 1
  expect_equal(recompounded, out$close_to_close, tolerance = 1e-12)
  # No corporate actions: matches raw close-to-close directly.
  expect_equal(out$close_to_close, diff(log(c(101, 99, 104, 106))) |> exp() - 1,
    tolerance = 1e-12
  )
})

# ── Split event: the case hd_return_legs() exists to handle correctly ────

test_that("a 2:1 split is corrected, not reported as a fake overnight crash", {
  # Raw close halves overnight between day 2 and day 3 (2:1 split effective
  # at the open of day 3). adjusted_close carries the true total return.
  toy <- tibble::tibble(
    ticker         = "X",
    date           = as.Date("2024-01-01") + 0:3,
    open           = c(99, 100, 51, 52),
    close          = c(100, 100, 52, 53),
    adjusted_close = c(50, 50, 52, 53)
  )
  out <- hd_return_legs(toy, quiet = TRUE)
  expect_equal(nrow(out), 3L)

  # Day 2 (index 1 in `out`): no split, ratio unchanged (0.5 -> 0.5).
  expect_equal(out$overnight[1], 0, tolerance = 1e-12)
  expect_equal(out$intraday[1], 0, tolerance = 1e-12)
  expect_false(out$corp_action_adjusted[1])

  # Day 3 (index 2 in `out`): the split day. Naive raw overnight would be
  # 51/100 - 1 = -49%; the corrected value is the real +2% move.
  expect_equal(out$overnight[2], 51 / 50 - 1, tolerance = 1e-12)
  expect_equal(out$intraday[2], 52 / 51 - 1, tolerance = 1e-12)
  expect_equal(out$close_to_close[2], 52 / 50 - 1, tolerance = 1e-12)
  expect_true(out$corp_action_adjusted[2])

  # Day 4 (index 3 in `out`): no further split.
  expect_equal(out$overnight[3], 0, tolerance = 1e-12)
  expect_equal(out$intraday[3], 53 / 52 - 1, tolerance = 1e-12)
  expect_false(out$corp_action_adjusted[3])

  expect_equal(attr(out, "n_corp_action_adjusted"), 1L)
})

test_that("naive raw overnight (uncorrected) would have shown a fake -49% crash", {
  # Documents the failure mode hd_return_legs() avoids -- not a test of the
  # function itself, a positive control that the split fixture above is
  # actually adversarial.
  naive_overnight_day3 <- 51 / 100 - 1
  expect_lt(naive_overnight_day3, -0.4)
})

# ── Dropped-row accounting ────────────────────────────────────────────────

test_that("missing open is dropped and counted separately from first-row drops", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:3,
    open           = c(100, NA, 102, 103),
    close          = c(101, 102, 102, 104),
    adjusted_close = c(101, 102, 102, 104)
  )
  out <- hd_return_legs(toy, quiet = TRUE)

  # Day 1: first row, dropped. Day 2: open is NA, dropped. Days 3-4: kept.
  expect_equal(nrow(out), 2L)
  expect_equal(out$date, as.Date("2024-01-01") + 2:3)
  expect_equal(attr(out, "n_dropped_first_row"), 1L)
  expect_equal(attr(out, "n_dropped_missing_open"), 1L)
})

test_that("missing adjusted_close is dropped and counted under its own reason", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:3,
    open           = c(100, 101, 102, 103),
    close          = c(101, 102, 102, 104),
    adjusted_close = c(101, NA, 102, 104)
  )
  out <- hd_return_legs(toy, quiet = TRUE)

  # Day 1: first row. Day 2: adjusted_close itself NA. Day 3: PREVIOUS row's
  # adjusted_close (day 2) is NA, so day 3's overnight leg is also undefined.
  # Day 4: fully defined.
  expect_equal(nrow(out), 1L)
  expect_equal(out$date, as.Date("2024-01-04"))
  expect_equal(attr(out, "n_dropped_first_row"), 1L)
  expect_equal(attr(out, "n_dropped_missing_open"), 0L)
  expect_equal(attr(out, "n_dropped_missing_adjusted_close"), 2L)
})

test_that("first-row drops are counted per ticker independently", {
  toy <- tibble::tibble(
    ticker         = c("A", "A", "B", "B"),
    date           = rep(as.Date("2024-01-01") + 0:1, 2),
    open           = c(100, 101, 200, 202),
    close          = c(101, 102, 201, 203),
    adjusted_close = c(101, 102, 201, 203)
  )
  out <- hd_return_legs(toy, quiet = TRUE)
  expect_equal(nrow(out), 2L)
  expect_setequal(out$ticker, c("A", "B"))
  expect_equal(attr(out, "n_dropped_first_row"), 2L)
})

# ── Unaccounted drop: a close-to-close NA that isn't "missing open" ───────

test_that("a non-first-row NA close (with adjusted_close still present) aborts as an unaccounted drop", {
  # close is NA on row 2 but adjusted_close is NOT -- this is the one gap
  # none of the three named drop reasons (first-row, missing-open,
  # missing-adjusted_close) covers, because it is `close`, not `open` or
  # `adjusted_close`, that is missing. Row 3 cascades into "first-row-like"
  # (its own previous close is NA), which IS accounted for; row 2 itself is
  # not, which is exactly what should trip the unaccounted-drop guard.
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:2,
    open           = c(100, 101, 102),
    close          = c(101, NA, 103),
    adjusted_close = c(101, 102, 103)
  )
  expect_snapshot(error = TRUE, hd_return_legs(toy, quiet = TRUE))
})

# ── Error paths (snapshot-tested per snapshot-test-policy.md) ─────────────

test_that("missing required columns aborts with an informative message", {
  toy <- tibble::tibble(date = as.Date("2024-01-01"), ticker = "A", open = 100)
  expect_snapshot(error = TRUE, hd_return_legs(toy))
})

test_that("no adjusted_close and unadjusted_ok = FALSE (default) aborts", {
  toy <- tibble::tibble(
    ticker = "A",
    date   = as.Date("2024-01-01") + 0:1,
    open   = c(100, 101),
    close  = c(101, 102)
  )
  expect_snapshot(error = TRUE, hd_return_legs(toy))
})

test_that("a non-positive price aborts with an informative message", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:1,
    open           = c(100, 0),
    close          = c(101, 102),
    adjusted_close = c(101, 102)
  )
  expect_snapshot(error = TRUE, hd_return_legs(toy, quiet = TRUE))
})

test_that("hd_return_legs() argument list is stable (catches API drift)", {
  expect_snapshot(args(hd_return_legs))
})

# ── unadjusted_ok = TRUE opt-out path ──────────────────────────────────────

test_that("unadjusted_ok = TRUE computes from raw close/open and flags no corp actions", {
  toy <- tibble::tibble(
    ticker = "A",
    date   = as.Date("2024-01-01") + 0:2,
    open   = c(100, 101, 99),
    close  = c(101, 99, 104)
  )
  out <- hd_return_legs(toy, unadjusted_ok = TRUE, quiet = TRUE)

  expect_equal(attr(out, "method"), "unadjusted")
  expect_equal(out$overnight[1], 101 / 101 - 1)
  expect_equal(out$intraday[1], 99 / 101 - 1)
  expect_equal(out$overnight[2], 99 / 99 - 1)
  expect_equal(out$intraday[2], 104 / 99 - 1)
  expect_true(all(is.na(out$corp_action_adjusted)))

  recompounded <- (1 + out$overnight) * (1 + out$intraday) - 1
  expect_equal(recompounded, out$close_to_close, tolerance = 1e-12)
})

test_that("emits an informative message unless quiet = TRUE", {
  toy <- tibble::tibble(
    ticker         = "A",
    date           = as.Date("2024-01-01") + 0:1,
    open           = c(100, 101),
    close          = c(101, 102),
    adjusted_close = c(101, 102)
  )
  expect_message(hd_return_legs(toy, quiet = FALSE), "row.*kept")
  expect_no_message(hd_return_legs(toy, quiet = TRUE))
})

# ── Falsification test for .hd_check_compounding() ─────────────────────
#
# The compounding identity in hd_return_legs() cannot actually diverge for
# internally-consistent input (see the function's roxygen "Verification"
# section) -- so this test exercises the extracted helper DIRECTLY with a
# deliberately wrong `expected` to prove the check has power to fail
# (verification-before-completion.md: "a check you have never seen fail is
# not a check").

test_that(".hd_check_compounding aborts when observed and expected diverge beyond tolerance", {
  expect_snapshot(
    error = TRUE,
    historicaldata:::.hd_check_compounding(
      observed = c(0.04, 0.01),
      expected = c(0.00, 0.01),   # row 1 deliberately wrong: 0.04 vs 0.00
      ticker = c("X", "X"),
      date = as.Date("2024-01-03") + 0:1,
      tolerance = 1e-6
    )
  )
})

test_that(".hd_check_compounding passes silently when observed and expected agree within tolerance", {
  expect_true(
    isTRUE(historicaldata:::.hd_check_compounding(
      observed = c(0.04, 0.01),
      expected = c(0.04 + 1e-9, 0.01),
      ticker = c("X", "X"),
      date = as.Date("2024-01-03") + 0:1,
      tolerance = 1e-6
    ))
  )
})

test_that(".hd_check_compounding aborts on non-finite observed or expected values", {
  expect_snapshot(
    error = TRUE,
    historicaldata:::.hd_check_compounding(
      observed = c(NaN, 0.01),
      expected = c(0.00, 0.01),
      ticker = c("X", "X"),
      date = as.Date("2024-01-03") + 0:1,
      tolerance = 1e-6
    )
  )
})
