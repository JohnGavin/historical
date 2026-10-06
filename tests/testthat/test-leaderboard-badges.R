testthat::local_edition(3)
# Tests for detection_badge()/psr_badge() -- the short-label + hover/focus
# pop-up badge builders (#726/#851/#927) used by docs/leaderboard.qmd's
# Rankings table. Defined in R/leaderboard_badges.R (extracted out of the
# qmd's own chunk into a sourced file -- the same pattern the qmd already
# uses for plan_qa_gates.R's DEFLATED_SHARPE_EXEMPTIONS -- so the
# badge-verdict logic is unit-testable rather than living only inside a
# rendered Quarto chunk). Ported from the owner-approved #927 Phase-0
# prototype (explorations/prob_sharpe_prototype/prototype.qmd, revision 2).
#
# One snapshot per state, for BOTH badge builders, mirroring the 6-state
# vocabulary the prototype's PR body documents: not applicable (Sharpe <=
# 0), not computed (defect), fails the single test, passes (MT not
# computed), passes single but fails MT-correction, passes both.

source(here::here("R/leaderboard_badges.R"))

THRESHOLD <- 0.95

# ── detection_badge(): 6 states ─────────────────────────────────────────────

test_that("detection_badge: not applicable (sharpe <= 0)", {
  expect_snapshot(
    cat(detection_badge("Value (HML)", sr = -0.2, avail = 62.5, under = NA,
                         dmin = NA_real_, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
  )
  expect_equal(
    detection_badge("Value (HML)", sr = -0.2, avail = 62.5, under = NA,
                     dmin = NA_real_, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$rank,
    4L
  )
})

test_that("detection_badge: not computed (defect -- positive Sharpe, no verdict)", {
  expect_snapshot(
    cat(detection_badge("Risk State", sr = 0.252, avail = NA_real_, under = NA,
                         dmin = NA_real_, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
  )
  expect_equal(
    detection_badge("Risk State", sr = 0.252, avail = NA_real_, under = NA,
                     dmin = NA_real_, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$rank,
    5L
  )
})

test_that("detection_badge: fails the single test (underpowered)", {
  expect_snapshot(
    cat(detection_badge("Value (HML)", sr = 0.068, avail = 62.5, under = TRUE,
                         dmin = 1337.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
  )
  expect_equal(
    detection_badge("Value (HML)", sr = 0.068, avail = 62.5, under = TRUE,
                     dmin = 1337.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$rank,
    3L
  )
})

test_that("detection_badge: passes single test, MT not computed", {
  expect_snapshot(
    cat(detection_badge("Avoid Worst", sr = 0.620, avail = 33.1, under = FALSE,
                         dmin = 16.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
  )
  expect_equal(
    detection_badge("Avoid Worst", sr = 0.620, avail = 33.1, under = FALSE,
                     dmin = 16.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$rank,
    1L
  )
})

test_that("detection_badge: passes single, fails MT-correction", {
  expect_snapshot(
    cat(detection_badge("OLMAR-1", sr = 0.780, avail = 16.1, under = FALSE,
                         dmin = 10.2, under_mt = TRUE, dmin_mt = 21.3, keff = 14.5)$html)
  )
  expect_equal(
    detection_badge("OLMAR-1", sr = 0.780, avail = 16.1, under = FALSE,
                     dmin = 10.2, under_mt = TRUE, dmin_mt = 21.3, keff = 14.5)$rank,
    2L
  )
})

test_that("detection_badge: passes single and MT-correction", {
  expect_snapshot(
    cat(detection_badge("Avoid Worst", sr = 0.620, avail = 33.1, under = FALSE,
                         dmin = 16.1, under_mt = FALSE, dmin_mt = 18.0, keff = 14.5)$html)
  )
  expect_equal(
    detection_badge("Avoid Worst", sr = 0.620, avail = 33.1, under = FALSE,
                     dmin = 16.1, under_mt = FALSE, dmin_mt = 18.0, keff = 14.5)$rank,
    1L
  )
})

# ── psr_badge(): 6 states ────────────────────────────────────────────────────

test_that("psr_badge: not applicable (sharpe <= 0)", {
  expect_snapshot(
    cat(psr_badge("Value (HML)", sr = -0.2, psr = NA_real_, psr_insuff = NA,
                  psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
  )
  expect_equal(
    psr_badge("Value (HML)", sr = -0.2, psr = NA_real_, psr_insuff = NA,
              psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$rank,
    4L
  )
})

test_that("psr_badge: not computed (defect -- positive Sharpe, no verdict)", {
  expect_snapshot(
    cat(psr_badge("Risk State", sr = 0.252, psr = NA_real_, psr_insuff = NA,
                  psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
  )
  expect_equal(
    psr_badge("Risk State", sr = 0.252, psr = NA_real_, psr_insuff = NA,
              psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$rank,
    5L
  )
})

test_that("psr_badge: fails the single test (insufficient)", {
  expect_snapshot(
    cat(psr_badge("Value (HML)", sr = 0.068, psr = 0.62, psr_insuff = TRUE,
                  psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
  )
  expect_equal(
    psr_badge("Value (HML)", sr = 0.068, psr = 0.62, psr_insuff = TRUE,
              psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$rank,
    3L
  )
})

test_that("psr_badge: passes single test, MT not computed", {
  expect_snapshot(
    cat(psr_badge("Avoid Worst", sr = 0.620, psr = 0.99, psr_insuff = FALSE,
                  psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
  )
  expect_equal(
    psr_badge("Avoid Worst", sr = 0.620, psr = 0.99, psr_insuff = FALSE,
              psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$rank,
    1L
  )
})

test_that("psr_badge: passes single, fails MT-correction (Managed Futures disagreement case)", {
  expect_snapshot(
    cat(psr_badge("Managed Futures", sr = 0.477, psr = 0.981, psr_insuff = FALSE,
                  psr_mt = 0.87, psr_mt_insuff = TRUE, threshold = THRESHOLD, keff = 14.5)$html)
  )
  expect_equal(
    psr_badge("Managed Futures", sr = 0.477, psr = 0.981, psr_insuff = FALSE,
              psr_mt = 0.87, psr_mt_insuff = TRUE, threshold = THRESHOLD, keff = 14.5)$rank,
    2L
  )
})

test_that("psr_badge: passes single and MT-correction", {
  expect_snapshot(
    cat(psr_badge("Avoid Worst", sr = 0.620, psr = 0.99, psr_insuff = FALSE,
                  psr_mt = 0.97, psr_mt_insuff = FALSE, threshold = THRESHOLD, keff = 14.5)$html)
  )
  expect_equal(
    psr_badge("Avoid Worst", sr = 0.620, psr = 0.99, psr_insuff = FALSE,
              psr_mt = 0.97, psr_mt_insuff = FALSE, threshold = THRESHOLD, keff = 14.5)$rank,
    1L
  )
})

# ── hd_pop_links(): dashboard-link presence/absence ────────────────────────

test_that("hd_pop_links includes the strategy dashboard link only where one exists", {
  with_link <- hd_pop_links("Avoid Worst", 726)
  expect_true(grepl("avoid-worst-days.html", with_link, fixed = TRUE))

  # Risk State deliberately has NO entry in HD_STRATEGY_DASHBOARD_HREF --
  # verified by grepping docs/macro-defense-rotation.qmd for "Risk State"
  # (zero matches) rather than guessing from the VIX-related filename.
  without_link <- hd_pop_links("Risk State", 726)
  expect_false(grepl("dashboard", without_link, fixed = TRUE))
  expect_true(grepl("biases-and-caveats", without_link, fixed = TRUE))
})

test_that("hd_pop_links always links back to Biases and Caveats", {
  expect_true(grepl("#biases-and-caveats", hd_pop_links("Avoid Worst", 726), fixed = TRUE))
})
