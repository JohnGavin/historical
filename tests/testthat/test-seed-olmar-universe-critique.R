# Tests for scripts/seed_olmar_universe_critique.R (Refs #976, #977): appends
# two critiques rows parented on the newest OLMAR results row, never edits an
# existing row, is idempotent (second run exits 1), and exits 3 when the OLMAR
# lineage is absent. Every run uses a temp base_dir with synthetic rows; the
# tracked log is never touched.

testthat::local_edition(3)

.uc_script <- function() here::here("scripts", "seed_olmar_universe_critique.R")

.run_uc <- function(base_dir) {
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c(shQuote(.uc_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  list(out = out, status = attr(out, "status") %||% 0L)
}

.skip_unless_uc_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.uc_script()), "universe critique script not found")
  testthat::skip_if_not_installed("pkgload")
}

.make_uc_log <- function(with_olmar = TRUE) {
  d <- tempfile("seed-olmar-uc-")
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

test_that("script appends two critiques on the newest results row, then exits 1", {
  .skip_unless_uc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_uc_log()
  expect_warning(
    before <- hd_rlog_query("critiques", base_dir = lg$dir),
    "No parquet files"
  )
  hyp_before <- hd_rlog_query("hypotheses", base_dir = lg$dir)
  res_before <- hd_rlog_query("results", base_dir = lg$dir)

  first <- .run_uc(lg$dir)
  expect_equal(first$status, 0L)
  expect_true(any(grepl("written=2", first$out)))

  after <- hd_rlog_query("critiques", base_dir = lg$dir)
  expect_equal(nrow(after), nrow(before) + 2L)
  expect_setequal(after$defect_class, c("universe-mismatch", "survivorship-bias"))
  expect_true(all(after$parent_uuid == lg$newest_res))
  expect_true(all(!after$resolved))
  f976 <- after$finding[after$defect_class == "universe-mismatch"]
  f977 <- after$finding[after$defect_class == "survivorship-bias"]
  expect_match(f976, "XLRE")
  expect_match(f976, "0 rows")
  expect_match(f976, "issues/976")
  expect_match(f977, "19 of 20")
  expect_match(f977, "2012-05-18")
  expect_match(f977, "size unknown")
  expect_match(f977, "issues/977")
  expect_no_match(f977, "significant", ignore.case = TRUE)

  # Append-only: hypotheses and results untouched.
  expect_equal(hd_rlog_query("hypotheses", base_dir = lg$dir), hyp_before)
  expect_equal(hd_rlog_query("results", base_dir = lg$dir), res_before)

  second <- .run_uc(lg$dir)
  expect_equal(second$status, 1L)
  expect_true(any(grepl("written=0", second$out)))
  expect_equal(nrow(hd_rlog_query("critiques", base_dir = lg$dir)), nrow(after))
})

test_that("only the missing defect class is written when one already exists", {
  .skip_unless_uc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_uc_log()
  hd_rlog_append("critiques", tibble::tibble(
    parent_uuid = lg$newest_res, defect_class = "survivorship-bias",
    severity = "major", finding = "earlier", cell_ref = "x", resolved = FALSE
  ), base_dir = lg$dir)
  r <- .run_uc(lg$dir)
  expect_equal(r$status, 0L)
  expect_true(any(grepl("written=1", r$out)))
  cr <- hd_rlog_query("critiques", base_dir = lg$dir)
  expect_equal(sum(cr$defect_class == "survivorship-bias"), 1L)
  expect_equal(sum(cr$defect_class == "universe-mismatch"), 1L)
})

test_that("script exits 3 and writes nothing when the OLMAR lineage is absent", {
  .skip_unless_uc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  lg <- .make_uc_log(with_olmar = FALSE)
  r <- .run_uc(lg$dir)
  expect_equal(r$status, 3L)
  expect_true(any(grepl("INDETERMINATE", r$out)))
  expect_false(dir.exists(file.path(lg$dir, "critiques")) &&
                 length(list.files(file.path(lg$dir, "critiques"))) > 0L)
})
