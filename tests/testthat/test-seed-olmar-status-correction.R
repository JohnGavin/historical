# Tests for scripts/seed_olmar_status_correction.R (Refs #968, #962, #937):
# the correction row keeps OLMAR-1's `inconclusive-unmeasurable` status, is
# APPENDED (no existing row edited), idempotent, unsealed with a reason, and
# its basis is built from the results table through the hypothesis ->
# implementation -> results lineage. Every run uses a temp base_dir seeded with
# synthetic rows; the tracked log is never touched.

testthat::local_edition(3)

.corr_script <- function() here::here("scripts", "seed_olmar_status_correction.R")

.run_corr <- function(base_dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript, c(shQuote(.corr_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  out[grepl("^seed_olmar_status_correction:|^  (uuid|parent_uuid|skipped)", out)]
}

.skip_unless_corr_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.corr_script()), "correction script not found")
  testthat::skip_if_not_installed("pkgload")
}

# Temp log: one deprecated-status OLMAR-1 hypothesis, its implementation, three
# results rows parented on the implementation (two n_obs levels), an earlier
# `inconclusive-unmeasurable` row carrying the false "no linked results" claim,
# and one unrelated finished idea.
.make_corr_log <- function() {
  d <- tempfile("seed-olmar-corr-")
  dir.create(d)
  claim <- paste0("Equity prices mean-revert toward a short moving average ",
                  "over daily horizons. (synthetic test claim)")
  pred <- "MA/price ratio (OLMAR-1): SMA(25d) / p_t"
  hyp_id  <- hd_rlog_uuid()
  impl_id <- hd_rlog_uuid()
  testthat::expect_warning(
    hd_rlog_append("hypotheses", tibble::tibble(
      uuid = hyp_id, economic_claim = claim, predictor = pred,
      status = "tested", extra_json = NA_character_
    ), base_dir = d),
    "deprecated"
  )
  hd_rlog_append("implementations", tibble::tibble(
    uuid = impl_id, parent_uuid = hyp_id, code_ref = "synthetic",
    notebook_path = NA_character_, params_json = "{}",
    extra_json = NA_character_
  ), base_dir = d)
  for (spec in list(c(1.111, 101L), c(0.555, 99L), c(0.555, 99L))) {
    hd_rlog_append("results", tibble::tibble(
      uuid = hd_rlog_uuid(), parent_uuid = impl_id, strategy_id = "olmar",
      partition = "full", cagr = 0.1, sharpe_hac = spec[[1]],
      max_dd = 0.2, turnover_annual = 5, n_obs = as.integer(spec[[2]]),
      results_db_run_date = Sys.Date(), extra_json = NA_character_
    ), base_dir = d)
  }
  hd_strategy_idea_append(
    name = "other_idea", economic_claim = "An unrelated finished idea",
    source = "test", priority = NA_character_, asset_class = "equity",
    status = "refuted", base_dir = d
  )
  Sys.sleep(1.1)  # the earlier status row must be strictly newest
  hd_strategy_idea_append(
    name = pred, economic_claim = claim, source = "test",
    priority = NA_character_, asset_class = "equity",
    status = "inconclusive-unmeasurable", parent_uuid = hyp_id,
    seal_omitted_reason = "synthetic earlier status row",
    extra = list(status_basis = paste0(
      "The research log holds no linked results row for this hypothesis (0), ",
      "so no Sharpe, deflated Sharpe or sample size is recorded."
    )),
    base_dir = d
  )
  Sys.sleep(1.1)
  d
}

.olmar_group <- function(led) led[grepl("OLMAR-1", led$name), ]

test_that("correction script appends one row and is idempotent", {
  .skip_unless_corr_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_corr_log()
  n_before <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  first <- .run_corr(d)
  second <- .run_corr(d)
  expect_snapshot(cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>",
                          c(first, "--- second run ---", second)), sep = "\n"))
  n_after <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  expect_equal(n_after, n_before + 1L)
})

test_that("status stays unmeasurable, old rows untouched, ledger behaviour as measured", {
  .skip_unless_corr_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_corr_log()
  before_rows <- hd_rlog_query("hypotheses", base_dir = d)
  before_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  before_n <- suppressMessages(hd_strategy_trial_count(base_dir = d))
  expect_equal(.olmar_group(before_led)$latest_status, "inconclusive-unmeasurable")

  invisible(.run_corr(d))

  after_rows <- hd_rlog_query("hypotheses", base_dir = d)
  after_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  olmar <- .olmar_group(after_led)
  expect_equal(nrow(olmar), 1L)
  expect_equal(olmar$latest_status, "inconclusive-unmeasurable")
  # The status was already counted, so the group gains one attempt but the
  # trial count (distinct counted ideas) does not move.
  expect_equal(olmar$n_attempts, .olmar_group(before_led)$n_attempts + 1L)
  expect_equal(suppressMessages(hd_strategy_trial_count(base_dir = d)), before_n)

  # Append-only: every earlier row is present and identical.
  expect_equal(nrow(after_rows), nrow(before_rows) + 1L)
  old <- after_rows[after_rows$uuid %in% before_rows$uuid, ]
  expect_equal(old[order(old$uuid, old$timestamp), ],
               before_rows[order(before_rows$uuid, before_rows$timestamp), ])
})

test_that("new row is a correction: unsealed, parented, basis from the data", {
  .skip_unless_corr_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_corr_log()
  old <- hd_rlog_query("hypotheses", base_dir = d)
  prior <- old[old$status == "inconclusive-unmeasurable" &
                 startsWith(old$predictor, "MA/price ratio (OLMAR-1)"), ]
  invisible(.run_corr(d))

  rows <- hd_rlog_query("hypotheses", base_dir = d)
  new <- rows[!(rows$uuid %in% old$uuid), ]
  expect_equal(nrow(new), 1L)
  expect_equal(new$status, "inconclusive-unmeasurable")
  expect_equal(new$parent_uuid, prior$uuid)
  expect_true(is.na(new$commit_hash))
  expect_true(is.na(new$sealed_at))
  expect_true(is.na(new$seal_method))

  ex <- jsonlite::fromJSON(new$extra_json)
  expect_false(ex$preregistered)
  expect_match(ex$seal_omitted_reason, "not a new pre-registration")
  expect_equal(ex$correction_of, prior$uuid)
  expect_equal(ex$issue, 968L)

  basis <- ex$status_basis
  expect_match(basis, "CORRECTION")
  expect_no_match(basis, "no linked results", ignore.case = TRUE)
  expect_no_match(basis, "no Sharpe, deflated Sharpe or sample size")
  # Counts and values come from the synthetic results table.
  expect_match(basis, "3 OLMAR results rows \\(3 distinct result uuids")
  expect_match(basis, "sharpe_hac 1.111 on n_obs 101 in 1 row")
  expect_match(basis, "sharpe_hac 0.555 on n_obs 99 in 2 rows")
  expect_match(basis, "not a verdict on the strategy")
  expect_match(basis, "neither has been done")
})

test_that("script aborts when no results are reachable via the lineage", {
  .skip_unless_corr_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_corr_log()
  unlink(list.files(file.path(d, "results"), full.names = TRUE))
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(.corr_script()), shQuote(d)), stdout = TRUE, stderr = TRUE
  ))
  expect_true(any(grepl("No results rows reachable", out)))
  expect_false(any(grepl("written=1", out)))
})
