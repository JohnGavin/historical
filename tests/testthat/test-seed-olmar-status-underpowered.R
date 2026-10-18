# Tests for scripts/seed_olmar_status_underpowered.R (Refs #962, #937): the new
# row moves OLMAR-1 from `inconclusive-unmeasurable` to
# `inconclusive-underpowered`, is APPENDED (no existing row edited), idempotent,
# unsealed with a truthful reason, parented on the newest row, takes its counts
# from the results table, quotes (and labels as quoted) the analysis metrics,
# and never writes a naive value into a sharpe_hac field. Every run uses a temp
# base_dir with synthetic rows; the tracked log is never touched.

testthat::local_edition(3)

.up_script <- function() here::here("scripts", "seed_olmar_status_underpowered.R")

.run_up <- function(base_dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript, c(shQuote(.up_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  out[grepl("^seed_olmar_status_underpowered:|^  (uuid|parent_uuid|skipped)", out)]
}

.skip_unless_up_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.up_script()), "underpowered script not found")
  testthat::skip_if_not_installed("pkgload")
}

# Temp log: a deprecated-status OLMAR-1 hypothesis, its implementation, results
# on two n_obs levels (4063 rows are the full period), and a newest
# `inconclusive-unmeasurable` row.
.make_up_log <- function(newest_status = "inconclusive-unmeasurable",
                         full_n_obs = 4063L) {
  d <- tempfile("seed-olmar-up-")
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
  for (spec in list(c(0.883, 4093L), c(0.78, full_n_obs), c(0.78, full_n_obs))) {
    hd_rlog_append("results", tibble::tibble(
      uuid = hd_rlog_uuid(), parent_uuid = impl_id, strategy_id = "olmar",
      partition = "full", cagr = 0.1, sharpe_hac = spec[[1]],
      max_dd = 0.2, turnover_annual = 5, n_obs = as.integer(spec[[2]]),
      results_db_run_date = Sys.Date(), extra_json = NA_character_
    ), base_dir = d)
  }
  Sys.sleep(1.1)
  hd_strategy_idea_append(
    name = pred, economic_claim = claim, source = "test",
    priority = NA_character_, asset_class = "equity",
    status = newest_status, parent_uuid = hyp_id,
    seal_omitted_reason = "synthetic earlier status row", base_dir = d
  )
  Sys.sleep(1.1)
  d
}

.up_group <- function(led) led[grepl("OLMAR-1", led$name), ]

test_that("underpowered script appends one row and is idempotent", {
  .skip_unless_up_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_up_log()
  n_before <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  first <- .run_up(d)
  second <- .run_up(d)
  expect_snapshot(cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>",
                          c(first, "--- second run ---", second)), sep = "\n"))
  n_after <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  expect_equal(n_after, n_before + 1L)
})

test_that("status moves to underpowered, old rows untouched", {
  .skip_unless_up_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_up_log()
  before_rows <- hd_rlog_query("hypotheses", base_dir = d)
  before_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  expect_equal(.up_group(before_led)$latest_status, "inconclusive-unmeasurable")

  invisible(.run_up(d))

  after_rows <- hd_rlog_query("hypotheses", base_dir = d)
  after_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  olmar <- .up_group(after_led)
  expect_equal(nrow(olmar), 1L)
  expect_equal(olmar$latest_status, "inconclusive-underpowered")

  # Append-only: every earlier row is present and identical.
  expect_equal(nrow(after_rows), nrow(before_rows) + 1L)
  old <- after_rows[after_rows$uuid %in% before_rows$uuid, ]
  expect_equal(old[order(old$uuid, old$timestamp), ],
               before_rows[order(before_rows$uuid, before_rows$timestamp), ])
})

test_that("new row is unsealed, parented on the newest row, basis from data", {
  .skip_unless_up_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_up_log()
  old <- hd_rlog_query("hypotheses", base_dir = d)
  prior <- old[old$status == "inconclusive-unmeasurable", ]
  invisible(.run_up(d))

  rows <- hd_rlog_query("hypotheses", base_dir = d)
  new <- rows[!(rows$uuid %in% old$uuid), ]
  expect_equal(nrow(new), 1L)
  expect_equal(new$status, "inconclusive-underpowered")
  expect_equal(new$parent_uuid, prior$uuid)
  expect_true(is.na(new$commit_hash))
  expect_true(is.na(new$sealed_at))
  expect_true(is.na(new$seal_method))

  ex <- jsonlite::fromJSON(new$extra_json)
  expect_false(ex$preregistered)
  expect_match(ex$seal_omitted_reason, "never sealed")
  expect_equal(ex$supersedes, prior$uuid)
  expect_equal(ex$issue, 962L)
  # Computed from the synthetic results table, not typed.
  expect_equal(ex$n_obs_full, 4063L)
  expect_equal(ex$years_of_data, round(4063 / 252, 2))
  # Quoted figures are labelled as quoted, and no naive Sharpe is written under
  # a sharpe_hac name.
  expect_match(ex$metrics_source, "QUOTED")
  expect_false("sharpe_hac" %in% names(ex))
  expect_false("sharpe_hac" %in% names(ex$return_basis))
  expect_equal(ex$detection_power$years_needed_at_stored_sharpe$K14_ledger, 20.52)
  expect_equal(ex$signal_null$n_beat_actual, 0L)

  basis <- ex$status_basis
  expect_match(basis, "2 OLMAR results rows on 4063 observations")
  expect_match(basis, "stored Sharpe 0.78")
  # The false earlier claim may be named, but only as false, never asserted.
  expect_match(basis, "false claim of no linked results")
  expect_no_match(basis, "(holds|has) no linked results", ignore.case = TRUE)
  expect_no_match(basis, "significant", ignore.case = TRUE)
  expect_match(basis, "#974")
  expect_match(basis, "#975")
  expect_match(basis, "#976")
  expect_match(basis, "#977")
  expect_match(basis, "NOT resolved")
})

test_that("script aborts unless the newest row is inconclusive-unmeasurable", {
  .skip_unless_up_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_up_log(newest_status = "refuted")
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(.up_script()), shQuote(d)), stdout = TRUE, stderr = TRUE
  ))
  expect_true(any(grepl("newest OLMAR-1 row has status", out)))
  expect_false(any(grepl("written=1", out)))
})

test_that("script aborts when no full-period results are reachable", {
  .skip_unless_up_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_up_log(full_n_obs = 999L)
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(.up_script()), shQuote(d)), stdout = TRUE, stderr = TRUE
  ))
  expect_true(any(grepl("No OLMAR results rows with n_obs = 4063", out)))
  expect_false(any(grepl("written=1", out)))
})
