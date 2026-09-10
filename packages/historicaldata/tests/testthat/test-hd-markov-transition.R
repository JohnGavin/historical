# Tests for hd_markov_transition() — Markov transition-matrix diagnostic (#838)
#
# The state-transition counting is simple enough that every numeric test
# below independently hand-derives the expected counts/probabilities from
# the fixture rather than re-deriving via the same code path -- a mismatch
# here would mean the implementation drifted from the documented counting
# rule, not that the arithmetic is wrong.

test_that("a perfectly sticky 2-state series has diagonal persistence of 1", {
  s <- c("low", "low", "low", "low", "high", "high", "high", "low", "low")
  out <- hd_markov_transition(s)

  expect_equal(out$states, c("high", "low"))
  # low->low: positions 1-2,2-3,3-4 (stay low), 8-9 (stay low) = 4 stays;
  # low->high: position 4-5 = 1; high->high: 5-6,6-7 = 2; high->low: 7-8 = 1
  expect_equal(out$counts["low", "low"], 4L)
  expect_equal(out$counts["low", "high"], 1L)
  expect_equal(out$counts["high", "high"], 2L)
  expect_equal(out$counts["high", "low"], 1L)
  expect_equal(out$n_transitions, 8L)  # length(s) - 1

  low_row <- out$persistence[out$persistence$state == "low", ]
  expect_equal(low_row$p_stay, 4 / 5, tolerance = 1e-9)
  expect_equal(low_row$n_from, 5L)

  high_row <- out$persistence[out$persistence$state == "high", ]
  expect_equal(high_row$p_stay, 2 / 3, tolerance = 1e-9)
  expect_equal(high_row$n_from, 3L)
})

test_that("an alternating 2-state series has diagonal persistence of 0", {
  s <- c("a", "b", "a", "b", "a", "b")
  out <- hd_markov_transition(s)
  expect_equal(out$persistence$p_stay, c(0, 0))
})

test_that("transition_matrix rows sum to 1 for every observed origin state", {
  s <- rep(c("low", "medium", "high"), times = c(10, 6, 4))
  out <- hd_markov_transition(s)
  row_sums <- rowSums(out$transition_matrix)
  expect_equal(unname(row_sums), rep(1, 3), tolerance = 1e-9)
})

test_that("a 3-state factor input uses factor levels as the declared vocabulary", {
  s <- factor(c("benign", "cautious", "hostile", "benign"),
              levels = c("benign", "cautious", "hostile"))
  out <- hd_markov_transition(s)
  expect_equal(out$states, c("benign", "cautious", "hostile"))
  expect_equal(nrow(out$persistence), 3L)
})

test_that("a state never observed as an origin gets an NA persistence row", {
  # "hostile" only ever appears as a destination (last element), never as
  # an origin -- its row in the transition matrix must be NA, not 0/0.
  s <- factor(c("benign", "cautious", "benign", "cautious", "hostile"),
              levels = c("benign", "cautious", "hostile"))
  out <- hd_markov_transition(s)
  hostile_row <- out$persistence[out$persistence$state == "hostile", ]
  expect_true(is.na(hostile_row$p_stay))
  expect_equal(hostile_row$n_from, 0L)
  expect_true(all(is.na(out$transition_matrix["hostile", ])))
})

test_that("NA adjacent pairs are dropped and counted, with a warning", {
  s <- c("low", "low", NA, "low", "high", "high")
  expect_warning(
    out <- hd_markov_transition(s),
    regexp = "Dropped 2 adjacent pair"
  )
  # Pairs (1,2)=low->low kept; (2,3) has NA dest, dropped; (3,4) has NA
  # origin, dropped; (4,5)=low->high kept; (5,6)=high->high kept.
  expect_equal(out$n_dropped, 2L)
  expect_equal(out$n_transitions, 3L)
})

test_that("explicit states argument overrides factor levels as the declared vocabulary", {
  s <- c("low", "high", "low", "high")
  out <- hd_markov_transition(s, states = c("low", "high", "extreme"))
  expect_equal(out$states, c("low", "high", "extreme"))
  extreme_row <- out$persistence[out$persistence$state == "extreme", ]
  expect_equal(extreme_row$n_from, 0L)
})

# ── Input validation (fail-loud-not-null.md) ─────────────────────────────

test_that("non-character/factor state aborts with an informative message", {
  expect_snapshot(error = TRUE, hd_markov_transition(1:5))
})

test_that("a state series shorter than 2 aborts", {
  expect_snapshot(error = TRUE, hd_markov_transition("only_one"))
})

test_that("a state series with only 1 distinct observed value aborts", {
  expect_snapshot(error = TRUE, hd_markov_transition(c("low", "low", "low")))
})

test_that("a state series with a value outside the declared vocabulary aborts", {
  expect_snapshot(
    error = TRUE,
    hd_markov_transition(c("low", "high", "extreme"), states = c("low", "high"))
  )
})

test_that("a declared states vocabulary with fewer than 2 entries aborts", {
  expect_snapshot(
    error = TRUE,
    hd_markov_transition(c("low", "low"), states = "low")
  )
})

test_that("a malformed states argument aborts", {
  expect_snapshot(error = TRUE, hd_markov_transition(c("low", "high"), states = c("low", "low")))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_markov_transition))
})
