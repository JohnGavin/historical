testthat::local_edition(3)
# Tests for check_strategy_periodicity_reconciliation() -- QA gate S28
# (#719 Layer 3, the pipeline-wide periodicity coverage backstop).
#
# The gate reconciles each daily-native strategy's declared ann_factor
# (STRATEGY_OBS_ANN_FACTOR) against the observed date frequency of its own
# return series (strat_returns_daily_native), independent of whether that
# strategy's own metrics code calls a periodicity guard directly -- the
# "guard scoped to the known path" gap fail-loud-not-null.md Required
# Pattern 5 warns about, applied at the pipeline level rather than a single
# function.
#
# The functions are defined in R/plan_qa_gates.R (which itself calls
# .assert_periodicity_reconciles(), R/utils_periodicity.R). Tests exercise
# the gate directly, on synthetic fixtures, without running tar_make().

source(here::here("R/utils_periodicity.R"))
source(here::here("R/plan_qa_gates.R"))
# R/plan_strategy_correlation.R and R/plan_strategy_names.R are sourced ONLY
# for the two structural cross-checks below (STRAT_RETURNS_DAILY_NATIVE_CODES
# coverage and hd_strategy_names_tbl() display-name parity) -- production
# code in R/plan_qa_gates.R deliberately does NOT depend on either at source
# time (see PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY's roxygen for why:
# root _targets.R's tar_source("R/plan_qa_gates.R") and this file's own
# source() calls above both source it standalone).
source(here::here("R/plan_strategy_correlation.R"))
source(here::here("R/plan_strategy_names.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

biz_days <- function(from, n) {
  all_days <- seq.Date(as.Date(from), by = "day", length.out = ceiling(n * 7 / 5) + 14L)
  wd <- all_days[!format(all_days, "%u") %in% c("6", "7")]
  wd[seq_len(n)]
}
month_days <- function(from, n) seq.Date(as.Date(from), by = "month", length.out = n)

good_daily_ret <- function(dates) tibble::tibble(date = dates, ret = stats::rnorm(length(dates), 0, 0.01))

good_daily_native <- function() {
  list(
    cmr             = good_daily_ret(biz_days("2010-01-04", 400L)),
    cmr_conditioned = good_daily_ret(biz_days("2010-01-04", 400L)),
    olmar_1         = good_daily_ret(biz_days("2010-01-04", 400L)),
    tom             = good_daily_ret(biz_days("2010-01-04", 400L)),
    risk_state      = good_daily_ret(biz_days("2010-01-04", 400L)),
    avoid_worst     = good_daily_ret(biz_days("2010-01-04", 400L))
  )
}

good_obs_ann_factor <- tibble::tibble(
  strategy = c("CMR", "CMR Conditioned", "OLMAR-1", "TOM", "Risk State", "Avoid Worst"),
  obs_ann_factor = c(252L, 252L, 252L, 252L, 252L, 252L),
  obs_ann_factor_source = "test fixture"
)

# ── Passing cases ────────────────────────────────────────────────────────

test_that("check_strategy_periodicity_reconciliation passes when every series matches its declared ann_factor", {
  expect_true(
    check_strategy_periodicity_reconciliation(good_daily_native(), good_obs_ann_factor)
  )
})

# ── Failing cases: a NEW (non-exempt) strategy with a real mismatch ────────

test_that("a non-exempt strategy with a mismatched declared ann_factor aborts and names it", {
  bad <- good_daily_native()
  bad$tom <- good_daily_ret(month_days("1990-01-01", 100L))  # actually monthly

  expect_error(
    check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor),
    "TOM"
  )
  expect_snapshot(
    error = TRUE,
    check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor)
  )
})

test_that("multiple non-exempt mismatches are all named in one abort, not just the first", {
  bad <- good_daily_native()
  bad$tom        <- good_daily_ret(month_days("1990-01-01", 100L))
  bad$risk_state <- good_daily_ret(month_days("1990-01-01", 100L))

  err <- tryCatch(
    check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "TOM")
  expect_match(err, "Risk State")
  expect_match(err, "2 strategy")
})

# ── The documented exemption: CMR (#738) runs warn-mode, not abort ─────────

test_that("the exempted strategy (cmr, #738) downgrades a mismatch to a warning and the gate still passes", {
  bad <- good_daily_native()
  # A CMR-shaped defect: monthly era then daily era, declared daily.
  bad$cmr <- good_daily_ret(
    sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  )

  w <- testthat::capture_warnings(
    result <- check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor)
  )
  expect_true(result)
  expect_true(any(grepl("NOT consistent with a single declared periodicity", w)))
  expect_true(any(grepl("CMR", w)))
})

test_that("PERIODICITY_RECONCILIATION_EXEMPT lists only cited, tracked issues (currently just cmr/#738)", {
  # fail-loud-not-null.md Required Pattern 2: an explicit, documented
  # default needs a test asserting it holds -- this pins the exemption
  # list so a future addition is a deliberate edit, not silent creep.
  expect_equal(PERIODICITY_RECONCILIATION_EXEMPT$code_name, "cmr")
  expect_true(grepl("#738", PERIODICITY_RECONCILIATION_EXEMPT$reason))
})

# ── Structural guards ────────────────────────────────────────────────────

test_that("a code_name absent from PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY aborts loudly", {
  bad <- good_daily_native()
  names(bad)[names(bad) == "tom"] <- "mystery_strategy"

  expect_error(
    check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor),
    "mystery_strategy"
  )
})

test_that("a code_name with no matching STRATEGY_OBS_ANN_FACTOR row aborts loudly, not silently skipped", {
  incomplete <- good_obs_ann_factor[good_obs_ann_factor$strategy != "TOM", , drop = FALSE]

  expect_error(
    check_strategy_periodicity_reconciliation(good_daily_native(), incomplete),
    "TOM"
  )
})

test_that("obs_ann_factor_tbl missing required columns aborts", {
  expect_error(
    check_strategy_periodicity_reconciliation(
      good_daily_native(),
      dplyr::select(good_obs_ann_factor, -obs_ann_factor)
    ),
    "obs_ann_factor"
  )
})

test_that("PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY covers every strat_returns_daily_native code_name (#733/#751)", {
  # Pins the bridge table against STRAT_RETURNS_DAILY_NATIVE_CODES
  # (R/plan_strategy_correlation.R) -- the SAME named constant
  # strat_returns_daily_native's own list() and STRAT_RETURNS_WIDE_CODES's
  # daily cohort are built from -- rather than a hand-typed literal
  # duplicated a third time in this test. #901 added "cmr_conditioned" to
  # STRAT_RETURNS_WIDE_CODES and strat_returns_daily_native's list() but NOT
  # to PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY; the OLD version of this
  # test (a hand-typed `c("cmr", "olmar_1", "tom", "risk_state",
  # "avoid_worst")`) went stale in lockstep with the very map it was meant
  # to protect and did not catch the omission -- only a real
  # scripts/build.sh run did, 40 minutes into a live build. Deriving the
  # expected set from STRAT_RETURNS_DAILY_NATIVE_CODES means the next such
  # omission fails here, in scripts/verify.sh, instead.
  expect_setequal(
    names(PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY),
    STRAT_RETURNS_DAILY_NATIVE_CODES
  )
})

test_that("PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY's display names match hd_strategy_names_tbl()'s short_name, not a hand-guessed string", {
  # PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY cannot call
  # hd_strategy_names_tbl() directly at source time without breaking root
  # _targets.R's tar_source("R/plan_qa_gates.R") (which never sources
  # R/plan_strategy_names.R) -- see that constant's roxygen. This test is
  # the substitute guarantee: every RHS literal is checked here against the
  # single strategy_names source, so a typo or future rename still fails
  # loudly even though the production vector stays a static literal.
  st <- hd_strategy_names_tbl()
  # strat_returns_daily_native's code_name vocabulary diverges from
  # strategy_names' code_name for three of the six ("olmar_1" vs "olmar",
  # "risk_state" vs "rsc", "avoid_worst" vs "avoid_worst" -- coincidentally
  # equal) -- see PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY's own roxygen.
  daily_native_to_strategy_names_code <- c(
    cmr             = "cmr",
    cmr_conditioned = "cmr_conditioned",
    olmar_1         = "olmar",
    tom             = "tom",
    risk_state      = "rsc",
    avoid_worst     = "avoid_worst"
  )
  for (nm in names(PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY)) {
    strategy_names_code <- daily_native_to_strategy_names_code[[nm]]
    expected <- st$short_name[st$code_name == strategy_names_code]
    expect_length(expected, 1L)
    expect_equal(
      PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY[[nm]],
      expected,
      info = sprintf("code_name '%s'", nm)
    )
  }
})
