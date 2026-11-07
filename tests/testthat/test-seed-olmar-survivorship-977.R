# Tests for scripts/seed_olmar_survivorship_977.R (Refs #977): appends exactly
# one survivorship-bias critique parented on the newest OLMAR full-period results
# row, with every number read from the committed CSVs; a second run writes
# nothing (exit 1); exits 3 when the OLMAR lineage is absent. Temp base_dir
# only; the tracked log is never touched.

testthat::local_edition(3)

.sv_script <- function() here::here("scripts", "seed_olmar_survivorship_977.R")

.run_sv <- function(base_dir) {
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c(shQuote(.sv_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  list(out = out, status = attr(out, "status") %||% 0L)
}

.skip_unless_sv_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.sv_script()), "survivorship script not found")
  testthat::skip_if_not(dir.exists(here::here("docs", "olmar-survivorship-977")),
                        "survivorship CSVs not found")
  testthat::skip_if_not_installed("pkgload")
}

.make_sv_log <- function(with_olmar = TRUE) {
  d <- tempfile("seed-olmar-sv-")
  dir.create(d)
  claim <- paste0("Equity prices mean-revert toward a short moving average ",
                  "over daily horizons. (synthetic test claim)")
  pred <- if (with_olmar) "MA/price ratio (OLMAR-1): SMA(25d) / p_t" else "other"
  hyp_id <- hd_rlog_uuid()
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
    notebook_path = NA_character_, params_json = "{}", extra_json = NA_character_
  ), base_dir = d)
  res_id <- NULL
  for (k in 1:2) {
    res_id <- hd_rlog_uuid()
    hd_rlog_append("results", tibble::tibble(
      uuid = res_id, parent_uuid = impl_id, strategy_id = "olmar",
      partition = "full", cagr = 0.1, sharpe_hac = 0.78,
      max_dd = 0.2, turnover_annual = 5, n_obs = 4063L,
      results_db_run_date = Sys.Date(), extra_json = NA_character_
    ), base_dir = d)
    Sys.sleep(1.1)
  }
  list(dir = d, newest_res = res_id)
}

test_that("appends exactly one survivorship-bias critique, then does nothing", {
  .skip_unless_sv_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_sv_log()
  expect_warning(
    before <- hd_rlog_query("critiques", base_dir = lg$dir),
    "No parquet files"
  )

  first <- .run_sv(lg$dir)
  expect_equal(first$status, 0L)
  expect_true(any(grepl("written=1", first$out)))
  after <- hd_rlog_query("critiques", base_dir = lg$dir)
  expect_equal(nrow(after), nrow(before) + 1L)
  expect_equal(after$defect_class, "survivorship-bias")
  expect_equal(after$parent_uuid, lg$newest_res)
  expect_false(after$resolved)
  expect_equal(after$severity, "major")
  # Numbers come from the CSVs, not from this test's own typing: re-derive two.
  res <- utils::read.csv(here::here("docs", "olmar-survivorship-977", "results.csv"))
  cur <- res$sharpe[res$universe == "current" & res$strategy == "OLMAR-1" &
                      res$period == "Full Period"]
  expect_match(after$finding, sprintf("OLMAR-1 Sharpe %.3f", cur), fixed = TRUE)
  mc <- utils::read.csv(here::here("docs", "olmar-survivorship-977",
                                   "membership_classes.csv"))
  n_abs <- sum(mc$n[mc$class %in% c("absent_from_equity_daily", "delisted_per_source")])
  expect_match(after$finding, sprintf("%d of %d", n_abs, sum(mc$n)), fixed = TRUE)
  expect_no_match(after$finding, "[0-9]th percentile")
  expect_match(after$finding, "issues/977", fixed = TRUE)

  second <- .run_sv(lg$dir)
  expect_equal(second$status, 1L)
  expect_true(any(grepl("written=0", second$out)))
  expect_equal(nrow(hd_rlog_query("critiques", base_dir = lg$dir)), nrow(after))
})

test_that("a later OLMAR results row does not make a re-run append a duplicate", {
  .skip_unless_sv_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_sv_log()
  first <- .run_sv(lg$dir)
  expect_equal(first$status, 0L)
  n1 <- nrow(hd_rlog_query("critiques", base_dir = lg$dir))
  # Append one more OLMAR full-period results row under the same implementation.
  impl <- hd_rlog_query("implementations", base_dir = lg$dir)
  Sys.sleep(1.1)
  hd_rlog_append("results", tibble::tibble(
    uuid = hd_rlog_uuid(), parent_uuid = impl$uuid[[1]], strategy_id = "olmar",
    partition = "full", cagr = 0.1, sharpe_hac = 0.78,
    max_dd = 0.2, turnover_annual = 5, n_obs = 4063L,
    results_db_run_date = Sys.Date(), extra_json = NA_character_
  ), base_dir = lg$dir)
  second <- .run_sv(lg$dir)
  expect_equal(second$status, 1L)
  expect_equal(nrow(hd_rlog_query("critiques", base_dir = lg$dir)), n1)
})

test_that("a pre-existing qualitative survivorship-bias row does not block the estimate", {
  .skip_unless_sv_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_sv_log()
  hd_rlog_append("critiques", tibble::tibble(
    parent_uuid = lg$newest_res, defect_class = "survivorship-bias",
    severity = "major", finding = "earlier, size unknown",
    cell_ref = "results:strategy_id=olmar (2 rows); universe", resolved = FALSE
  ), base_dir = lg$dir)
  r <- .run_sv(lg$dir)
  expect_equal(r$status, 0L)
  cr <- hd_rlog_query("critiques", base_dir = lg$dir)
  expect_equal(sum(cr$defect_class == "survivorship-bias"), 2L)
})

test_that("exits 3 and writes nothing when the OLMAR lineage is absent", {
  .skip_unless_sv_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_sv_log(with_olmar = FALSE)
  r <- .run_sv(lg$dir)
  expect_equal(r$status, 3L)
  expect_true(any(grepl("INDETERMINATE", r$out)))
  expect_false(dir.exists(file.path(lg$dir, "critiques")) &&
                 length(list.files(file.path(lg$dir, "critiques"))) > 0L)
})
