# Tests for hd_turnover() / hd_turnover_series() (#567 A1, #663 Phase 1)
#
# Every expected value below is worked by hand in the comment above it, never
# read back from the function. Snapshot ratio: the error blocks and the
# signature block are snapshotted (snapshot-test-policy).

# ---- hd_turnover(): hand-computed cases ---------------------------------

test_that("swap A -> B: one-way 1, two-way 2", {
  # |0-1| + |1-0| = 2 -> one-way 1
  expect_equal(hd_turnover(c(A = 0, B = 1), c(A = 1, B = 0)), 1)
  expect_equal(hd_turnover(c(A = 0, B = 1), c(A = 1, B = 0), side = "two"), 2)
})

test_that("an exiting name counts as a sale", {
  # A: |.5-.4| = .1, B: |.5-.4| = .1, C (exit): |0-.2| = .2 -> sum .4
  w_new  <- c(A = 0.5, B = 0.5)
  w_prev <- c(A = 0.4, B = 0.4, C = 0.2)
  expect_equal(hd_turnover(w_new, w_prev), 0.2)
  expect_equal(hd_turnover(w_new, w_prev, side = "two"), 0.4)
  # Name order must not matter.
  expect_equal(hd_turnover(w_new[2:1], w_prev[3:1]), 0.2)
})

test_that("an entering name counts as a purchase", {
  # Mirror image of the exit case: C enters at .2.
  expect_equal(hd_turnover(c(A = 0.4, B = 0.4, C = 0.2), c(A = 0.5, B = 0.5)), 0.2)
})

test_that("no previous book: turnover is the cost of entry, sum(abs(w)) / 2", {
  expect_equal(hd_turnover(c(A = 0.5, B = 0.5)), 0.5)
  expect_equal(hd_turnover(c(A = 0.5, B = 0.5), numeric(0)), 0.5)
  # Dollar-neutral long-short 1/1: sum|w| = 2 -> 1
  expect_equal(hd_turnover(c(A = 1, B = -1)), 1)
})

test_that("all-cash books: nothing held, nothing traded", {
  expect_equal(hd_turnover(numeric(0), numeric(0)), 0)
  expect_equal(hd_turnover(c(CASH = 1), c(CASH = 1)), 0)
  expect_equal(hd_turnover(c(A = 0, B = 0), c(A = 0, B = 0)), 0)
  # Going to cash with cash listed: A 1 -> 0 and CASH 0 -> 1 = 2 -> one-way 1
  expect_equal(hd_turnover(c(A = 0, CASH = 1), c(A = 1, CASH = 0)), 1)
})

test_that("unnamed vectors align by position", {
  # |.5-1| + |.5-0| = 1 -> .5
  expect_equal(hd_turnover(c(0.5, 0.5), c(1, 0)), 0.5)
})

test_that("a book that does not trade has zero turnover once drifted", {
  w_prev <- c(A = 0.6, B = 0.4)
  r      <- c(A = 0.2, B = 0)
  # Drifted: A = .6*1.2 / (1 + .6*.2) = .72/1.12, B = .4/1.12. Holding still
  # means today's weights ARE the drifted weights.
  w_now <- c(A = 0.72 / 1.12, B = 0.4 / 1.12)
  expect_equal(hd_turnover(w_now, w_prev, drift_ret = r), 0, tolerance = 1e-12)
  # Against the STALE weights the same book appears to trade:
  # |.72/1.12 - .6| = .6428571 - .6 = .0428571 on each of two names -> one-way .0428571
  expect_equal(hd_turnover(w_now, w_prev), 0.72 / 1.12 - 0.6, tolerance = 1e-12)
})

test_that("drift then rebalance: turnover is the distance from the DRIFTED book", {
  # prev .5/.5, A doubles (+100%), B flat: gross 1 + .5 = 1.5,
  # drifted A = 1/1.5 = 2/3, B = .5/1.5 = 1/3. Rebalance to .5/.5:
  # |.5-2/3| + |.5-1/3| = 1/3 -> one-way 1/6.
  expect_equal(
    hd_turnover(c(A = 0.5, B = 0.5), c(A = 0.5, B = 0.5), drift_ret = c(A = 1, B = 0)),
    1 / 6, tolerance = 1e-12
  )
})

test_that("drift is correct for a long-short book with cash listed", {
  # prev: A +1, B -1, CASH +1 (NAV 1). Returns A +10%, B +20%, CASH 0.
  # gross = 1 + (1*.1 + -1*.2 + 0) = .9. drifted A = 1.1/.9, B = -1.2/.9, CASH = 1/.9.
  # Rebalance back to the original: diffs 1.1/.9-1 = .2222, -1.2/.9+1 = -.3333,
  # 1/.9-1 = .1111 -> abs sum = .6667 -> one-way .3333
  w <- c(A = 1, B = -1, CASH = 1)
  expect_equal(
    hd_turnover(w, w, drift_ret = c(A = 0.1, B = 0.2, CASH = 0)),
    (abs(1.1 / 0.9 - 1) + abs(-1.2 / 0.9 + 1) + abs(1 / 0.9 - 1)) / 2,
    tolerance = 1e-12
  )
})

test_that("extra names in drift_ret are ignored; unnamed drift works by position", {
  expect_equal(
    hd_turnover(c(A = 0.5, B = 0.5), c(A = 0.5, B = 0.5),
                drift_ret = c(A = 1, B = 0, Z = 9)),
    1 / 6, tolerance = 1e-12
  )
  expect_equal(
    hd_turnover(c(0.5, 0.5), c(0.5, 0.5), drift_ret = c(1, 0)),
    1 / 6, tolerance = 1e-12
  )
})

# ---- hd_turnover_series() ------------------------------------------------

d <- as.Date(c("2024-01-31", "2024-02-29", "2024-03-29"))

test_that("series: entry, exit and entry again, hand-computed", {
  w <- data.frame(
    date   = d[c(1, 1, 2, 2)],
    name   = c("A", "B", "B", "C"),
    weight = c(0.5, 0.5, 0.5, 0.5)
  )
  out <- hd_turnover_series(w)
  # d1: entry sum|w|/2 = .5. d2: A exits (.5), C enters (.5): sum 1 -> .5
  expect_equal(out$date, d[1:2])
  expect_equal(out$turnover, c(0.5, 0.5))
  expect_equal(hd_turnover_series(w, first = "na")$turnover, c(NA, 0.5))
  expect_equal(hd_turnover_series(w, side = "two")$turnover, c(1, 1))
})

test_that("series: a period with no rows is an all-cash book", {
  w <- data.frame(date = d[c(1, 1, 2, 2)], name = c("A", "B", "A", "B"),
                  weight = 0.5)
  out <- hd_turnover_series(w, periods = d)
  # d1 entry .5; d2 unchanged 0; d3 empty: sells everything, sum 1 -> .5
  expect_equal(out$turnover, c(0.5, 0, 0.5))
})

test_that("series: drift by period returns", {
  w <- data.frame(date = d[c(1, 1, 2, 2)], name = c("A", "B", "A", "B"),
                  weight = 0.5)
  r <- data.frame(date = d[c(1, 1)], name = c("A", "B"), ret = c(1, 0))
  out <- hd_turnover_series(w, returns = r, first = "na")
  # Same arithmetic as the scalar drift-then-rebalance case: 1/6
  expect_equal(out$turnover, c(NA, 1 / 6), tolerance = 1e-12)
})

test_that("series matches the scalar function period by period (random books)", {
  set.seed(1)
  nms <- LETTERS[1:6]
  rows <- lapply(seq_along(d), function(i) {
    k <- sample(nms, sample(2:5, 1))
    data.frame(date = d[i], name = k, weight = stats::runif(length(k)))
  })
  w <- do.call(rbind, rows)
  out <- hd_turnover_series(w, first = "na")
  by <- split(w, w$date)
  vec <- function(x) stats::setNames(x$weight, x$name)
  expect_equal(out$turnover[2], hd_turnover(vec(by[[2]]), vec(by[[1]])))
  expect_equal(out$turnover[3], hd_turnover(vec(by[[3]]), vec(by[[2]])))
})

# ---- Input validation: error snapshots ------------------------------------

test_that("bad side aborts", {
  expect_snapshot(error = TRUE, hd_turnover(c(A = 1), side = "both"))
})

test_that("non-numeric w aborts", {
  expect_snapshot(error = TRUE, hd_turnover(c("a", "b")))
})

test_that("NA in w aborts", {
  expect_snapshot(error = TRUE, hd_turnover(c(A = 0.5, B = NA_real_)))
})

test_that("mixed named / unnamed aborts", {
  expect_snapshot(error = TRUE, hd_turnover(c(A = 0.5, B = 0.5), c(0.5, 0.5)))
})

test_that("unnamed vectors of different length abort", {
  expect_snapshot(error = TRUE, hd_turnover(c(0.5, 0.5), c(1, 0, 0)))
})

test_that("duplicate names abort", {
  expect_snapshot(error = TRUE, hd_turnover(c(A = 0.5, A = 0.5)))
})

test_that("drift_ret without a previous book aborts", {
  expect_snapshot(error = TRUE, hd_turnover(c(A = 1), NULL, drift_ret = c(A = 0.1)))
})

test_that("drift_ret missing a held name aborts", {
  expect_snapshot(error = TRUE,
                  hd_turnover(c(A = 1), c(A = 0.5, B = 0.5), drift_ret = c(A = 0.1)))
})

test_that("drift_ret with NA aborts", {
  expect_snapshot(error = TRUE,
                  hd_turnover(c(A = 1), c(A = 1), drift_ret = c(A = NA_real_)))
})

test_that("a previous book wiped out by its returns aborts", {
  expect_snapshot(error = TRUE,
                  hd_turnover(c(A = 1), c(A = 1), drift_ret = c(A = -1.5)))
})

test_that("series: missing columns abort", {
  expect_snapshot(error = TRUE, hd_turnover_series(data.frame(date = d[1], name = "A")))
})

test_that("series: duplicated (date, name) aborts", {
  expect_snapshot(error = TRUE, hd_turnover_series(
    data.frame(date = d[c(1, 1)], name = c("A", "A"), weight = c(0.5, 0.5))
  ))
})

test_that("series: returns missing a held name aborts", {
  w <- data.frame(date = d[c(1, 2)], name = c("A", "A"), weight = 1)
  r <- data.frame(date = d[1], name = "Z", ret = 0.1)
  expect_snapshot(error = TRUE, hd_turnover_series(w, returns = r))
})

test_that("series: periods that omit a weights date abort", {
  w <- data.frame(date = d[c(1, 2)], name = c("A", "A"), weight = 1)
  expect_snapshot(error = TRUE, hd_turnover_series(w, periods = d[1]))
})

test_that("series: bad `first` aborts", {
  w <- data.frame(date = d[1], name = "A", weight = 1)
  expect_snapshot(error = TRUE, hd_turnover_series(w, first = "zero"))
})

# ---- Signature stability --------------------------------------------------

test_that("function signatures are stable (catches API drift)", {
  expect_snapshot(args(hd_turnover))
  expect_snapshot(args(hd_turnover_series))
})

# ---- Migration regression: weight_stability's L1 turnover ------------------
# hd_weight_stability_diagnostic() used mean(rowSums(abs(diff of weight rows))).
# It now calls hd_turnover(side = "two") per transition. Same value.
test_that("hd_turnover(side = 'two') equals the L1 row-difference it replaced", {
  set.seed(3)
  wts <- matrix(stats::runif(40), nrow = 8, ncol = 5)
  old <- mean(rowSums(abs(wts[-1L, , drop = FALSE] - wts[-nrow(wts), , drop = FALSE])))
  new <- mean(vapply(seq_len(nrow(wts) - 1L),
                     function(k) hd_turnover(unname(wts[k + 1L, ]), unname(wts[k, ]), side = "two"),
                     numeric(1L)))
  expect_equal(new, old, tolerance = 1e-14)
})
