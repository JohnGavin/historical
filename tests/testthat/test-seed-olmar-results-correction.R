# Tests for scripts/seed_olmar_results_correction.R (Refs #974, #975, #962): one
# critiques row is APPENDED, parented on the newest OLMAR results row, listing
# exactly the affected results rows (uuid@timestamp) split by stored value; no
# existing row is edited; the script is idempotent; it refuses a log holding a
# value it does not describe; and it writes no sharpe_hac value anywhere. Every
# run uses a temp base_dir with synthetic rows; the tracked log is never touched.

testthat::local_edition(3)

.rc_script <- function() here::here("scripts", "seed_olmar_results_correction.R")

.run_rc <- function(base_dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript, c(shQuote(.rc_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  out[grepl("^seed_olmar_results_correction:|^  (uuid|parent_uuid|affected_rows|skipped)", out)]
}

.run_rc_raw <- function(base_dir) {
  suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(.rc_script()), shQuote(base_dir)), stdout = TRUE, stderr = TRUE
  ))
}

.skip_unless_rc_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.rc_script()), "results-correction script not found")
  testthat::skip_if_not_installed("pkgload")
}

# Temp log: one OLMAR-1 hypothesis, its implementation, and OLMAR results rows
# (value, n_obs, timestamp) given by `specs`. Default: 2 rows of 0.883 on 4093
# observations (oldest) and 3 rows of 0.78 on 4063 observations.
.make_rc_log <- function(specs = NULL, with_results = TRUE) {
  if (is.null(specs)) {
    specs <- list(
      list(0.883, 4093L, "2026-05-23 22:58:43"),
      list(0.883, 4093L, "2026-08-06 23:00:12"),
      list(0.780, 4063L, "2026-08-18 20:31:17"),
      list(0.780, 4063L, "2026-09-21 13:20:05"),
      list(0.780, 4063L, "2026-09-28 15:39:55")
    )
  }
  d <- tempfile("seed-olmar-rc-")
  dir.create(d)
  claim <- paste0("Equity prices mean-revert toward a short moving average ",
                  "over daily horizons. (synthetic test claim)")
  pred <- "MA/price ratio (OLMAR-1): SMA(25d) / p_t"
  hyp_id  <- hd_rlog_uuid()
  impl_id <- hd_rlog_uuid()
  hd_rlog_append("hypotheses", tibble::tibble(
    uuid = hyp_id, economic_claim = claim, predictor = pred,
    status = "inconclusive-underpowered", extra_json = NA_character_
  ), base_dir = d)
  hd_rlog_append("implementations", tibble::tibble(
    uuid = impl_id, parent_uuid = hyp_id, code_ref = "synthetic",
    notebook_path = NA_character_, params_json = "{}",
    extra_json = NA_character_
  ), base_dir = d)
  if (with_results) {
    for (spec in specs) {
      hd_rlog_append("results", tibble::tibble(
        uuid = hd_rlog_uuid(), parent_uuid = impl_id, strategy_id = "olmar",
        timestamp = as.POSIXct(spec[[3]], tz = "UTC"),
        partition = "full", cagr = 0.1, sharpe_hac = spec[[1]],
        max_dd = 0.2, turnover_annual = 5, n_obs = as.integer(spec[[2]]),
        results_db_run_date = Sys.Date(), extra_json = NA_character_
      ), base_dir = d)
    }
  }
  d
}

.rc_new_row <- function(d) {
  crit <- hd_rlog_query("critiques", base_dir = d)
  crit[crit$defect_class == "metric-basis", , drop = FALSE]
}

# Split the affected_rows tail of the finding into its two lists.
.rc_refs <- function(finding) {
  tail <- sub(".*affected_rows \\(uuid@timestamp\\), ", "", finding)
  geo_part   <- sub("; arithmetic_no_rf_.*$", "", tail)
  arith_part <- sub("^.*; arithmetic_no_rf_[0-9.]+ \\[[0-9]+\\]: ", "", tail)
  split_refs <- function(x) {
    x <- sub("^.*\\]: ", "", x)
    x <- sub("\\.$", "", x)
    strsplit(x, ", ", fixed = TRUE)[[1]]
  }
  list(geo = split_refs(geo_part), arith = split_refs(arith_part))
}

test_that("correction script appends one critiques row and is idempotent", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log()
  n_before <- length(list.files(file.path(d, "critiques"), pattern = "\\.parquet$"))
  first <- .run_rc(d)
  second <- .run_rc(d)
  expect_snapshot(cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>",
                          c(first, "--- second run ---", second)), sep = "\n"))
  n_after <- length(list.files(file.path(d, "critiques"), pattern = "\\.parquet$"))
  expect_equal(n_after, n_before + 1L)
})

test_that("row is parented on the newest results row and lists exactly the affected rows", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log()
  res <- hd_rlog_query("results", base_dir = d)
  res <- res[order(res$timestamp), ]
  invisible(.run_rc(d))

  new <- .rc_new_row(d)
  expect_equal(nrow(new), 1L)
  # Wrong parent would be any other results row, an implementation or hypothesis.
  expect_equal(new$parent_uuid, res$uuid[nrow(res)])
  expect_equal(new$severity, "major")
  expect_false(new$resolved)

  refs <- .rc_refs(new$finding)
  fmt <- function(d) paste0(d$uuid, "@",
                            format(d$timestamp, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  expect_equal(length(refs$geo), 3L)
  expect_equal(length(refs$arith), 2L)
  expect_setequal(refs$geo, fmt(res[round(res$sharpe_hac, 3) == 0.78, ]))
  expect_setequal(refs$arith, fmt(res[round(res$sharpe_hac, 3) == 0.883, ]))
  expect_equal(length(c(refs$geo, refs$arith)), nrow(res))
  # The counts stated in prose match the lists.
  expect_match(new$finding, "the 5 results rows are append-only")
  expect_match(new$finding, "(1) 3 rows hold 0.78", fixed = TRUE)
  expect_match(new$finding, "(2) 2 rows hold 0.883", fixed = TRUE)
  expect_match(new$finding, "over 4093 rows", fixed = TRUE)
})

test_that("finding states the corrected basis, labels quoted figures, links issues", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log()
  invisible(.run_rc(d))
  f <- .rc_new_row(d)$finding
  expect_match(f, "0.9271", fixed = TRUE)
  expect_match(f, "HAC t 3.723", fixed = TRUE)
  expect_match(f, "not recomputed by this script", fixed = TRUE)
  expect_match(f, "0.8117", fixed = TRUE)
  expect_match(f, "no risk-free rate deducted", fixed = TRUE)
  expect_match(f, "[#974](https://github.com/JohnGavin/historical/issues/974)",
               fixed = TRUE)
  expect_match(f, "[#975](https://github.com/JohnGavin/historical/issues/975)",
               fixed = TRUE)
  expect_match(f, "[PR #979](https://github.com/JohnGavin/historical/pull/979)",
               fixed = TRUE)
  expect_no_match(f, "significant", ignore.case = TRUE)
  expect_no_match(f, "HAC Sharpe is 0.78", fixed = TRUE)
  expect_snapshot(cat(
    gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@",
         "<uuid>@", f)
  ))
})

test_that("append-only: no existing row changes and no sharpe_hac is written", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log()
  before <- lapply(c("hypotheses", "implementations", "results", "critiques",
                     "robustness"),
                   function(t) suppressWarnings(hd_rlog_query(t, base_dir = d)))
  invisible(.run_rc(d))
  after <- lapply(c("hypotheses", "implementations", "results", "critiques",
                    "robustness"),
                  function(t) suppressWarnings(hd_rlog_query(t, base_dir = d)))
  # hypotheses, implementations, results, robustness: identical.
  for (i in c(1L, 2L, 3L, 5L)) expect_equal(after[[i]], before[[i]])
  # critiques: exactly one new row.
  expect_equal(nrow(after[[4]]), nrow(before[[4]]) + 1L)
})

test_that("script aborts when a stored value is not one of the two described", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log(specs = list(
    list(0.883, 4093L, "2026-05-23 22:58:43"),
    list(0.931, 4063L, "2026-09-28 15:39:55")
  ))
  out <- .run_rc_raw(d)
  expect_true(any(grepl("other than", out)))
  expect_false(any(grepl("written=1", out)))
})

test_that("script aborts when no OLMAR results rows are reachable", {
  .skip_unless_rc_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_rc_log(with_results = FALSE)
  out <- .run_rc_raw(d)
  expect_true(any(grepl("No OLMAR results rows reachable", out)))
  expect_false(any(grepl("written=1", out)))
})
